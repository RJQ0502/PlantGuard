import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'otp_config.dart';

/// Emails a 6-digit verification code via EmailJS and checks it back.
///
/// WHAT THIS IS FOR
/// Signup email verification - proving the person owns the address they typed.
/// The code is generated on the device and compared on the device, which is
/// fine here: the only person who could cheat is the one verifying their own
/// email, and they already have that email.
///
/// WHAT THIS IS NOT FOR
/// Forgotten-password reset. Two reasons, and the second is fatal:
///   1. A locally-checked code could be bypassed on a modified client.
///   2. More decisively, the Firebase client SDK simply CANNOT change a
///      signed-out user's password. `updatePassword()` only ever acts on the
///      currently signed-in user. Resetting a password you cannot log into
///      requires Firebase's own emailed link, or the Admin SDK in a Cloud
///      Function. No amount of custom OTP work gets around that.
/// Use `AuthService.sendPasswordReset()` for that path instead.
class OtpService {
  OtpService._();
  static final OtpService instance = OtpService._();

  // =====================================================================
  // SETUP - fill these three in from your EmailJS dashboard.
  //
  //  1. emailjs.com -> Email Services  -> add Gmail (or similar) -> Service ID
  //  2.              -> Email Templates -> new template          -> Template ID
  //  3.              -> Account         -> General               -> Public Key
  //
  //  IMPORTANT: EmailJS blocks non-browser callers by default, and Flutter
  //  counts as one. Turn OFF Account -> Security -> "Allow EmailJS API for
  //  non-browser applications"... actually turn it ON. Without it every call
  //  comes back 403 Forbidden with no other explanation.
  //
  //  These param names match EmailJS's stock "One-Time Password" template
  //  as-is, so it works without rewriting the template body:
  //     {{email}}      recipient - already the template's "To Email" field
  //     {{passcode}}   the 6 digits
  //     {{time}}       human-readable expiry, for the "valid till ..." line
  //  `name` is also sent, unused by that template but handy if you add it.
  // =====================================================================
  // Credentials live in otp_config.dart so that replacing THIS file never
  // wipes them again.
  static String get serviceId => OtpConfig.serviceId;
  static String get templateId => OtpConfig.templateId;
  static String get publicKey => OtpConfig.publicKey;
  static String get privateKey => OtpConfig.privateKey;

  /// 15 minutes so it agrees with the stock template's "valid for 15 minutes"
  /// wording. Change both together if you shorten it.
  static const Duration codeLifetime = Duration(minutes: 15);
  static const int maxAttempts = 5;
  static const int codeLength = 6;

  static const String _endpoint =
      'https://api.emailjs.com/api/v1.0/email/send';

  // Held in memory only - never written to disk or Firestore, so it dies with
  // the app rather than lingering somewhere readable.
  String? _code;
  String? _sentTo;
  DateTime? _expiresAt;
  int _attempts = 0;

  bool get hasPendingCode => _code != null && !_isExpired;
  String? get pendingEmail => _sentTo;

  bool get _isExpired =>
      _expiresAt == null || DateTime.now().isAfter(_expiresAt!);

  /// True when all three placeholders above have been replaced.
  static bool get isConfigured => _missingConfig.isEmpty;

  /// Names the constants still holding their placeholder value, so the error
  /// says WHICH one is missing instead of a blanket "not set up".
  static List<String> get _missingConfig {
    final List<String> missing = <String>[];
    if (serviceId.isEmpty || serviceId == 'YOUR_SERVICE_ID') {
      missing.add('serviceId');
    }
    if (templateId.isEmpty || templateId == 'YOUR_TEMPLATE_ID') {
      missing.add('templateId');
    }
    if (publicKey.isEmpty || publicKey == 'YOUR_PUBLIC_KEY') {
      missing.add('publicKey');
    }
    return missing;
  }

  /// Renders the expiry for the template's "valid ... till {{time}}" line,
  /// e.g. "9 Sep 2025, 10:45 PM". Written by hand rather than pulling in the
  /// intl package for one string.
  String _formatExpiry(DateTime t) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final int hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final String minute = t.minute.toString().padLeft(2, '0');
    final String meridiem = t.hour < 12 ? 'AM' : 'PM';
    return '${t.day} ${months[t.month - 1]} ${t.year}, '
        '$hour12:$minute $meridiem';
  }

  /// Cryptographically-seeded so codes aren't predictable from the clock.
  String _generate() {
    final Random rng = Random.secure();
    return List<int>.generate(codeLength, (_) => rng.nextInt(10)).join();
  }

  /// Sends a fresh code to [email].
  /// Returns null on success, or a message to show the user.
  Future<String?> sendCode({required String email, String? name}) async {
    if (!isConfigured) {
      final String missing = _missingConfig.join(', ');
      debugPrint(
        'OtpService: EmailJS not configured. Still placeholder: $missing '
        '(edit the constants near the top of lib/otp_service.dart, then do a '
        'FULL restart - these are compile-time consts, hot reload will not '
        'pick them up).',
      );
      return 'Email service is not set up yet.\n\nStill missing: $missing';
    }

    final String code = _generate();

    try {
      final http.Response res = await http
          .post(
            Uri.parse(_endpoint),
            // NO Origin header.
            //
            // I previously sent 'origin: http://localhost' thinking it would
            // help. It does the opposite: an Origin header makes EmailJS treat
            // the call as coming from a BROWSER, so it validates that origin
            // against the allowed-domains list on your account. localhost is
            // not on that list, so the request is refused. A non-browser call
            // must simply not send one.
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'service_id': serviceId,
              'template_id': templateId,
              'user_id': publicKey,
              // Required for non-browser callers - which Flutter is. Without
              // it, EmailJS's strict API mode rejects the request outright.
              // Omitted from the payload entirely if you haven't set one.
              if (privateKey.isNotEmpty) 'accessToken': privateKey,
              'template_params': <String, String>{
                'email': email.trim(),
                'passcode': code,
                'time': _formatExpiry(DateTime.now().add(codeLifetime)),
                'name': (name == null || name.trim().isEmpty)
                    ? email.split('@').first
                    : name.trim(),
              },
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        _code = code;
        _sentTo = email.trim();
        _expiresAt = DateTime.now().add(codeLifetime);
        _attempts = 0;
        return null;
      }

      debugPrint('OtpService: EmailJS ${res.statusCode} - ${res.body}');

      // EmailJS explains 4xx failures in the response body as plain text, so
      // it is shown directly rather than hidden behind a generic message -
      // it names the actual problem ("The recipients address is empty",
      // "API calls are disabled for non-browser applications", and so on).
      final String detail = res.body.trim();
      if (res.statusCode == 403) {
        return 'Email service rejected the request.\n\n'
            '${detail.isEmpty ? 'Enable API access for non-browser apps in '
                'EmailJS Account > Security.' : detail}';
      }
      return 'Could not send the code (${res.statusCode}).'
          '${detail.isEmpty ? '' : '\n\n$detail'}';
    } catch (e) {
      debugPrint('OtpService: send failed - $e');
      return 'Could not reach the email service. Check your connection.';
    }
  }

  /// Checks [input] against the code that was sent.
  /// Returns null when it matches, otherwise a message to show.
  String? verify(String input) {
    if (_code == null) return 'No code has been sent yet.';
    if (_isExpired) {
      clear();
      return 'That code has expired. Tap Resend for a new one.';
    }

    _attempts++;
    if (_attempts > maxAttempts) {
      clear();
      return 'Too many incorrect attempts. Request a new code.';
    }

    if (input.trim() != _code) {
      final int left = maxAttempts - _attempts + 1;
      return 'Incorrect code. $left ${left == 1 ? 'try' : 'tries'} left.';
    }

    clear(); // single use
    return null;
  }

  void clear() {
    _code = null;
    _sentTo = null;
    _expiresAt = null;
    _attempts = 0;
  }
}