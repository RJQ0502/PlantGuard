import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_sound.dart';
import 'app_ui.dart';
import 'auth_service.dart';
import 'signup_screen.dart';

/// Which greeting the login screen shows under "Hello there,".
enum LoginGreeting {
  /// An account has already been created on this device.
  welcomeBack,

  /// Fresh install, or the user has just changed their password.
  pleaseLogIn,
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.greeting});

  /// Forces a greeting. Leave null to decide from device state - the normal
  /// case. Pass [LoginGreeting.pleaseLogIn] when arriving straight after a
  /// password change.
  final LoginGreeting? greeting;

  // --- Device state keys -------------------------------------------------
  static const String _kHasAccount = 'pg_has_account';
  static const String _kRememberMe = 'pg_remember_me';
  static const String _kSavedUsername = 'pg_saved_username';

  /// Call once a sign-up succeeds. From then on this device shows
  /// "Welcome Back!" instead of "Please Log in".
  static Future<void> markAccountCreated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasAccount, true);
  }

  /// Wipes the local trace of an account (handy for testing both greetings
  /// without reinstalling).
  static Future<void> clearDeviceAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHasAccount);
    await prefs.remove(_kRememberMe);
    await prefs.remove(_kSavedUsername);
  }

  /// Rise-and-fade route, used coming out of the splash.
  static Route<void> route({LoginGreeting? greeting}) =>
      slideUpRoute<void>(LoginScreen(greeting: greeting));

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _busy = false;

  /// Null until device state has been read - the second greeting line stays
  /// hidden until then, so it never flashes the wrong words.
  LoginGreeting? _greeting;

  @override
  void initState() {
    super.initState();
    _greeting = widget.greeting;
    _loadDeviceState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // Lets the route's own slide land first.
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _intro.forward();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final bool hasAccount = prefs.getBool(LoginScreen._kHasAccount) ?? false;
    final bool remember = prefs.getBool(LoginScreen._kRememberMe) ?? false;
    final String savedUser = prefs.getString(LoginScreen._kSavedUsername) ?? '';

    setState(() {
      // An explicit greeting passed into the widget always wins.
      _greeting ??=
          hasAccount ? LoginGreeting.welcomeBack : LoginGreeting.pleaseLogIn;
      _rememberMe = remember;
      if (remember && savedUser.isNotEmpty) _usernameCtrl.text = savedUser;
    });
  }

  Future<void> _persistRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LoginScreen._kRememberMe, _rememberMe);
    if (_rememberMe) {
      await prefs.setString(
        LoginScreen._kSavedUsername,
        _usernameCtrl.text.trim(),
      );
    } else {
      await prefs.remove(LoginScreen._kSavedUsername);
    }
  }

  // ---------------------------------------------------------------------
  // ACTIONS - UI is complete; the marked spots take the backend later.
  // ---------------------------------------------------------------------

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppSound.instance.error();
      return;
    }

    setState(() => _busy = true);

    // Accepts a username or an email - AuthService resolves a username to its
    // email via Firestore before handing it to Firebase. try/finally so an
    // unexpected throw cannot leave the button stuck disabled.
    String? error;
    try {
      error = await AuthService.instance.signIn(
        usernameOrEmail: _usernameCtrl.text,
        password: _passwordCtrl.text,
      );
    } catch (e) {
      error = 'Unexpected error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;

    if (error != null) {
      AppSound.instance.error();
      showAppDialog(context, message: error);
      return;
    }

    await _persistRememberMe();
    await LoginScreen.markAccountCreated();
    if (!mounted) return;
    AppSound.instance.success();

    // TODO(dashboard): replace this with the real destination once it exists:
    // Navigator.of(context).pushAndRemoveUntil(
    //   slideUpRoute<void>(const DashboardScreen()), (route) => false);
    showAppSnack(context, 'Signed in as ${_usernameCtrl.text.trim()}');
  }

  void _handleCreateAccount() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(SignupScreen.route());
  }

  Future<void> _handleForgotPassword() async {
    FocusScope.of(context).unfocus();

    // A reset with no account attached to it is meaningless - it used to walk
    // straight into the OTP screen on an empty field. The login form only
    // collects a username, but a reset has to be sent somewhere, so ask for
    // the email here rather than guessing.
    final String? email = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => _ForgotPasswordDialog(screenW: MediaQuery.of(context).size.width),
    );

    if (email == null || !mounted) return; // dismissed

    // Firebase's own reset LINK, not our custom OTP - and not by choice.
    //
    // The Firebase client SDK cannot change a signed-out user's password:
    // updatePassword() only ever acts on the currently signed-in user. So a
    // custom code could confirm the user's identity and then have no way to
    // actually set the new password. Resetting a password you cannot log into
    // needs either this emailed link or the Admin SDK in a Cloud Function.
    //
    // reset_password_screen.dart is still useful - wire it to a "change
    // password" option in settings, where the user IS signed in and
    // updatePassword() works.
    final String? error = await AuthService.instance.sendPasswordReset(email);
    if (!mounted) return;

    if (error != null) {
      AppSound.instance.error();
      showAppDialog(context, message: error);
      return;
    }

    AppSound.instance.success();
    showAppDialog(context,
        title: 'Check your inbox',
        isError: false,
        message: 'We sent a password reset link to $email.');
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double w = size.width;
    final double sideMargin = AppMetrics.s(w, 16);

    Widget stagger(int slot, Widget child, {double dy = 26}) =>
        StaggerIn(controller: _intro, slot: slot, dy: dy, child: child);

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
                  SizedBox(height: size.height * 0.11),
                  Padding(
                    padding: EdgeInsets.only(left: AppMetrics.s(w, 8)),
                    child: _greetingBlock(w),
                  ),
                  SizedBox(height: size.height * 0.045),
                  // The card is the heavy object, so it travels further.
                  Expanded(child: stagger(2, _card(w), dy: 60)),
                  SizedBox(height: sideMargin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _greetingBlock(double w) {
    final String second = switch (_greeting) {
      LoginGreeting.welcomeBack => 'Welcome Back!',
      LoginGreeting.pleaseLogIn => 'Please Log in',
      null => '',
    };

    final TextStyle style = TextStyle(
      fontFamily: 'Inter',
      fontSize: AppMetrics.s(w, 30),
      fontWeight: FontWeight.w700,
      color: Colors.white,
      height: 1.25,
      shadows: const [
        Shadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, 2)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        StaggerIn(
          controller: _intro,
          slot: 0,
          dy: 22,
          child: Text('Hello there,', style: style),
        ),
        // Two gates: the stagger, plus a fade that waits for device state - so
        // the wrong greeting is never briefly visible on launch.
        StaggerIn(
          controller: _intro,
          slot: 1,
          dy: 22,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            opacity: _greeting == null ? 0.0 : 1.0,
            child: Text(second.isEmpty ? ' ' : second, style: style),
          ),
        ),
      ],
    );
  }

  Widget _card(double w) {
    Widget stagger(int slot, Widget child) =>
        StaggerIn(controller: _intro, slot: slot, child: child);

    return GlassCard(
      screenW: w,
      padded: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppMetrics.s(w, 24),
          AppMetrics.s(w, 28),
          AppMetrics.s(w, 24),
          AppMetrics.s(w, 24),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              stagger(3, BrandLockup(screenW: w)),
              SizedBox(height: AppMetrics.s(w, 26)),

              stagger(
                4,
                AppField(
                  screenW: w,
                  controller: _usernameCtrl,
                  hint: 'Username',
                  trailing: const Icon(Icons.person, size: 21),
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter your username'
                      : null,
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 14)),

              stagger(
                5,
                AppField(
                  screenW: w,
                  controller: _passwordCtrl,
                  focusNode: _passwordFocus,
                  hint: 'Password',
                  obscure: _obscurePassword,
                  action: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                  trailing: PressableScale(
                    onTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    pressedScale: 0.85,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 21,
                        color: AppColors.hint,
                      ),
                    ),
                  ),
                  validator: (value) => (value == null || value.isEmpty)
                      ? 'Enter your password'
                      : null,
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 4)),

              stagger(6, _rememberRow(w)),
              SizedBox(height: AppMetrics.s(w, 22)),

              stagger(
                7,
                PrimaryButton(
                  label: 'Log In',
                  screenW: w,
                  busy: _busy,
                  onPressed: _handleLogin,
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 12)),

              stagger(
                8,
                GhostButton(
                  label: 'Create Account',
                  screenW: w,
                  onPressed: _busy ? null : _handleCreateAccount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rememberRow(double w) {
    return Row(
      children: [
        Transform.scale(
          scale: 0.72,
          alignment: Alignment.centerLeft,
          child: Switch(
            value: _rememberMe,
            onChanged: (value) {
              AppSound.instance.tap();
              setState(() => _rememberMe = value);
              _persistRememberMe();
            },
            // WidgetStateProperty rather than activeColor/inactiveTrackColor:
            // those shorthands are deprecated on recent Flutter versions.
            thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
            trackColor: WidgetStateProperty.resolveWith<Color>(
              (states) => states.contains(WidgetState.selected)
                  ? AppColors.green
                  : const Color(0x33FFFFFF),
            ),
            trackOutlineColor:
                const WidgetStatePropertyAll<Color>(Colors.transparent),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        SizedBox(width: AppMetrics.s(w, 6)),
        Text(
          'Remember me',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppMetrics.s(w, 13),
            fontWeight: FontWeight.w600,
            color: AppColors.bodyText,
          ),
        ),
        const Spacer(),
        PressableScale(
          onTap: _handleForgotPassword,
          pressedScale: 0.92,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppMetrics.s(w, 6)),
            child: Text(
              // Copy matches the Figma frame exactly.
              'Forget Password?',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppMetrics.s(w, 13),
                fontWeight: FontWeight.w600,
                color: AppColors.bodyText,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Asks for the email a reset should be sent to.
///
/// Deliberately its own dialog rather than reusing the username on the form:
/// a username is not a delivery address, and Firebase's reset API takes an
/// email specifically. Returns the trimmed email, or null if dismissed.
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.screenW});

  final double screenW;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppSound.instance.error();
      return;
    }
    Navigator.of(context).pop(_emailCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final double w = widget.screenW;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: AppMetrics.s(w, 24)),
      child: GlassCard(
        screenW: w,
        padded: false,
        radiusPx: 26,
        child: Padding(
          padding: EdgeInsets.all(AppMetrics.s(w, 22)),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reset your password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppMetrics.s(w, 17),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: AppMetrics.s(w, 8)),
                Text(
                  'Enter the email on your account and we will send you a '
                  'verification code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppMetrics.s(w, 11.5),
                    color: AppColors.bodyText,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: AppMetrics.s(w, 18)),

                AppField(
                  screenW: w,
                  controller: _emailCtrl,
                  hint: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  action: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  trailing: const Icon(Icons.mail_outline, size: 20),
                  validator: (value) {
                    final String v = (value ?? '').trim();
                    if (v.isEmpty) return 'Enter your email';
                    if (!v.contains('@') || !v.contains('.')) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                SizedBox(height: AppMetrics.s(w, 20)),

                PrimaryButton(
                  label: 'Send code',
                  screenW: w,
                  onPressed: _submit,
                ),
                SizedBox(height: AppMetrics.s(w, 8)),
                GhostButton(
                  label: 'Cancel',
                  screenW: w,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}