import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_sound.dart';
import 'app_ui.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'otp_service.dart';
import 'reset_password_screen.dart';
import 'verification_screen.dart';

/// What the code is confirming. The two paths look identical but continue to
/// different places, so the screen has to be told which one it is on.
enum OtpPurpose {
  /// Confirming a brand new account -> straight to "Verification Complete".
  signup,

  /// Confirming identity before a password change -> on to Reset Password.
  passwordReset,
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.purpose,
    this.email,
    this.pending,
  });

  final OtpPurpose purpose;

  /// Shown in the blurb so the user knows where to look. Optional.
  final String? email;

  /// Signup details, carried here so the account can be created AFTER the
  /// code is verified rather than before. Null for the password-reset path.
  final PendingSignup? pending;

  static Route<void> route({
    required OtpPurpose purpose,
    String? email,
    PendingSignup? pending,
  }) =>
      slideSideRoute<void>(
        OtpScreen(purpose: purpose, email: email, pending: pending),
      );

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  static const int _codeLength = 6;
  static const int _resendSeconds = 60;

  late final AnimationController _intro;

  final List<TextEditingController> _boxes = List<TextEditingController>.generate(
    _codeLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focus = List<FocusNode>.generate(
    _codeLength,
    (_) => FocusNode(),
  );

  Timer? _ticker;
  int _remaining = _resendSeconds;
  bool _busy = false;

  String get _code => _boxes.map((c) => c.text).join();
  bool get _complete => _code.length == _codeLength;
  bool get _canResend => _remaining <= 0;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _intro.forward();
    });
    _startCountdown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _intro.dispose();
    for (final c in _boxes) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _ticker?.cancel();
    setState(() => _remaining = _resendSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) timer.cancel();
    });
  }

  String get _clock {
    final int s = _remaining < 0 ? 0 : _remaining;
    final String mm = (s ~/ 60).toString().padLeft(2, '0');
    final String ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  // ---------------------------------------------------------------------
  // BOX BEHAVIOUR
  // ---------------------------------------------------------------------

  void _onBoxChanged(int index, String value) {
    // Pasting the whole code lands entirely in one box - spread it across the
    // rest rather than dropping everything but the first digit.
    if (value.length > 1) {
      final String digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < _codeLength - index; i++) {
        if (i < digits.length) _boxes[index + i].text = digits[i];
      }
      final int landed = (index + digits.length).clamp(0, _codeLength - 1);
      _focus[landed].requestFocus();
      setState(() {});
      return;
    }

    if (value.isNotEmpty && index < _codeLength - 1) {
      _focus[index + 1].requestFocus();
    }
    setState(() {}); // refreshes the Verify button's enabled state
  }

  /// Backspace on an empty box should step back to the previous one, which
  /// a plain TextField will not do on its own.
  KeyEventResult _onBoxKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _boxes[index].text.isEmpty &&
        index > 0) {
      _boxes[index - 1].clear();
      _focus[index - 1].requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (!_complete) {
      AppSound.instance.error();
      showAppDialog(context,
          title: 'Incomplete code',
          message: 'Enter all $_codeLength digits.');
      return;
    }

    setState(() => _busy = true);

    // Checked against the code OtpService emailed. Handles expiry and the
    // attempt limit too, returning a message when either trips.
    final String? error = OtpService.instance.verify(_code);

    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      AppSound.instance.error();
      showAppDialog(context, title: 'Verification failed', message: error);
      for (final c in _boxes) {
        c.clear();
      }
      _focus.first.requestFocus();
      setState(() {});
      return;
    }

    switch (widget.purpose) {
      case OtpPurpose.signup:
        // The code is confirmed, so NOW the account gets created. Up to this
        // point nothing existed in Firebase - which is why cancelling or
        // force-quitting this screen leaves nothing behind.
        final PendingSignup? pending = widget.pending;
        if (pending == null) {
          showAppDialog(context,
              message: 'Signup details were lost. Please start again.');
          return;
        }

        setState(() => _busy = true);
        String? createError;
        try {
          createError = await AuthService.instance.createAccount(
            email: pending.email,
            password: pending.password,
            username: pending.username,
          );
        } catch (e) {
          createError = 'Unexpected error: $e';
        } finally {
          if (mounted) setState(() => _busy = false);
        }

        if (!mounted) return;
        if (createError != null) {
          AppSound.instance.error();
          showAppDialog(context,
              title: 'Could not finish signup', message: createError);
          return;
        }

        // Only now does this device count as having an account.
        await LoginScreen.markAccountCreated();
        if (!mounted) return;

        AppSound.instance.success();
        Navigator.of(context).pushReplacement(
          VerificationScreen.completeRoute(),
        );
        break;

      case OtpPurpose.passwordReset:
        AppSound.instance.success();
        Navigator.of(context).pushReplacement(
          ResetPasswordScreen.route(),
        );
        break;
    }
  }

  Future<void> _resend() async {
    if (!_canResend || _busy) return;

    setState(() => _busy = true);
    final String? error = await OtpService.instance.sendCode(
      email: widget.email ?? OtpService.instance.pendingEmail ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      AppSound.instance.error();
      showAppDialog(context, message: error);
      return;
    }

    for (final c in _boxes) {
      c.clear();
    }
    _focus.first.requestFocus();
    _startCountdown();
    showAppSnack(context, 'A new code is on its way.');
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double w = size.width;
    final double sideMargin = AppMetrics.s(w, 16);

    Widget stagger(int slot, Widget child, {double dx = 32}) =>
        StaggerIn(controller: _intro, slot: slot, dx: dx, dy: 0, child: child);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1E0D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackground(),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: sideMargin),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: size.height * 0.06),
                  stagger(0, Center(child: BrandLockup(screenW: w, logoPx: 52))),
                  SizedBox(height: size.height * 0.045),

                  stagger(1, _title(w, 'OTP VERIFICATION')),
                  SizedBox(height: AppMetrics.s(w, 8)),
                  stagger(
                    2,
                    _blurb(
                      w,
                      'Please enter the OTP (One-Time-Password) sent to '
                      '${widget.email ?? 'you email'} to complete your '
                      'verification',
                    ),
                  ),
                  SizedBox(height: AppMetrics.s(w, 20)),

                  stagger(3, _card(w), dx: 44),
                  SizedBox(height: sideMargin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(double w, String text) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppMetrics.s(w, 20),
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.4,
          shadows: const [
            Shadow(color: Color(0x59000000), blurRadius: 10, offset: Offset(0, 2)),
          ],
        ),
      );

  Widget _blurb(double w, String text) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppMetrics.s(w, 11.5),
          fontWeight: FontWeight.w400,
          color: AppColors.bodyText,
          height: 1.45,
        ),
      );

  Widget _card(double w) {
    Widget stagger(int slot, Widget child) =>
        StaggerIn(controller: _intro, slot: slot, dx: 28, dy: 0, child: child);

    return GlassCard(
      screenW: w,
      padded: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppMetrics.s(w, 20),
          AppMetrics.s(w, 24),
          AppMetrics.s(w, 20),
          AppMetrics.s(w, 22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            stagger(4, _boxRow(w)),
            SizedBox(height: AppMetrics.s(w, 18)),

            stagger(5, _timerRow(w)),
            SizedBox(height: AppMetrics.s(w, 6)),
            stagger(6, _resendRow(w)),
            SizedBox(height: AppMetrics.s(w, 22)),

            stagger(
              7,
              PrimaryButton(
                label: 'Verify',
                screenW: w,
                busy: _busy,
                onPressed: _verify,
              ),
            ),
            SizedBox(height: AppMetrics.s(w, 10)),
            stagger(
              8,
              GhostButton(
                label: 'Cancel',
                screenW: w,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boxRow(double w) {
    // Sized off the available width so six boxes always fit with even gaps,
    // rather than a fixed width that overflows on a narrow screen.
    final double gap = AppMetrics.s(w, 8);
    final double inner = w - (AppMetrics.s(w, 16) * 2) - (AppMetrics.s(w, 20) * 2);
    final double box = ((inner - gap * (_codeLength - 1)) / _codeLength)
        .clamp(28.0, AppMetrics.s(w, 52));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(_codeLength, (int i) {
        return Padding(
          padding: EdgeInsets.only(right: i == _codeLength - 1 ? 0 : gap),
          child: SizedBox(
            width: box,
            height: box * 1.15,
            child: Focus(
              onKeyEvent: (node, event) => _onBoxKey(i, event),
              child: TextField(
                controller: _boxes[i],
                focusNode: _focus[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (value) => _onBoxChanged(i, value),
                cursorColor: Colors.white,
                showCursor: false,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: box * 0.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.fieldFill,
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppMetrics.s(w, 10)),
                    borderSide: const BorderSide(color: AppColors.fieldStroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppMetrics.s(w, 10)),
                    borderSide: const BorderSide(
                      color: AppColors.green,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _timerRow(double w) {
    return Row(
      children: [
        Text(
          'Remaining time: ',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppMetrics.s(w, 11.5),
            color: AppColors.bodyText,
          ),
        ),
        Text(
          _clock,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppMetrics.s(w, 11.5),
            fontWeight: FontWeight.w700,
            // Turns amber as it runs out, so the state is readable at a glance.
            color: _canResend ? AppColors.wordmarkGreen : const Color(0xFFE0C24A),
          ),
        ),
      ],
    );
  }

  Widget _resendRow(double w) {
    return Row(
      children: [
        Text(
          "Didn't get the code? ",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppMetrics.s(w, 11.5),
            color: AppColors.bodyText,
          ),
        ),
        PressableScale(
          onTap: _canResend ? _resend : null,
          pressedScale: 0.9,
          child: Text(
            'Resend',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppMetrics.s(w, 11.5),
              fontWeight: FontWeight.w700,
              // Dimmed until the countdown expires, so the disabled state is
              // obvious without an extra label.
              color: _canResend
                  ? AppColors.wordmarkGreen
                  : AppColors.wordmarkGreen.withValues(alpha: 0.4),
              decoration: TextDecoration.underline,
              decorationColor: _canResend
                  ? AppColors.wordmarkGreen
                  : AppColors.wordmarkGreen.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }
}