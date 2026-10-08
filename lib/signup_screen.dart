import 'package:flutter/material.dart';

import 'app_sound.dart';
import 'app_ui.dart';
import 'auth_service.dart';
import 'legal_screen.dart';
import 'login_screen.dart';
import 'otp_screen.dart';
import 'otp_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  /// Lateral slide, matching how this screen sits beside login in the flow.
  ///   Navigator.of(context).push(SignupScreen.route());
  static Route<void> route() => slideSideRoute<void>(const SignupScreen());

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // Let the route's own side-slide land first, so the two motions read as
    // one sequence rather than competing.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _intro.forward();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // ACTIONS - UI is complete; the marked spots take the backend later.
  // ---------------------------------------------------------------------

  Future<void> _handleSignUp() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppSound.instance.error();
      return;
    }

    setState(() => _busy = true);

    // NOTHING is created here. The account only comes into existence once the
    // emailed code is verified - otherwise abandoning the OTP screen would
    // leave an unverified account in Firebase permanently.
    //
    // try/finally so an unexpected throw can never leave _busy true, which
    // would disable the button until an app restart.
    String? error;
    try {
      error = await AuthService.instance.checkAvailability(
        email: _emailCtrl.text,
        username: _usernameCtrl.text,
      );

      // Only worth emailing a code once we know the signup can succeed.
      error ??= await OtpService.instance.sendCode(
        email: _emailCtrl.text,
        name: _usernameCtrl.text,
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

    AppSound.instance.success();

    Navigator.of(context).push(
      OtpScreen.route(
        purpose: OtpPurpose.signup,
        email: _emailCtrl.text.trim(),
        pending: PendingSignup(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          username: _usernameCtrl.text,
        ),
      ),
    );
  }

  void _goToLogin() {
    // Back to login rather than stacking another copy on top.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(LoginScreen.route());
    }
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double w = size.width;
    final double sideMargin = AppMetrics.s(w, 16);

    // Content slides in from the right, echoing the direction the page itself
    // arrived from.
    Widget stagger(int slot, Widget child, {double dx = 34}) =>
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
                  SizedBox(height: AppMetrics.s(w, 8)),
                  stagger(
                    0,
                    BackCircleButton(screenW: w, onTap: _goToLogin),
                    dx: -28, // the back control comes from the other side
                  ),
                  SizedBox(height: AppMetrics.s(w, 18)),

                  stagger(1, _headline(w)),
                  SizedBox(height: size.height * 0.03),

                  Expanded(child: stagger(2, _card(w), dx: 48)),
                  SizedBox(height: sideMargin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headline(double w) {
    return Padding(
      padding: EdgeInsets.only(left: AppMetrics.s(w, 6)),
      child: Text(
        'Keeping your plants\nhealthy with smarter\ncare and real-time\ninsights.',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppMetrics.s(w, 25),
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.28,
          shadows: const [
            Shadow(
              color: Color(0x59000000),
              blurRadius: 12,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(double w) {
    Widget stagger(int slot, Widget child) =>
        StaggerIn(controller: _intro, slot: slot, dx: 30, dy: 0, child: child);

    return GlassCard(
      screenW: w,
      padded: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppMetrics.s(w, 22),
          AppMetrics.s(w, 26),
          AppMetrics.s(w, 22),
          AppMetrics.s(w, 22),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              stagger(3, BrandLockup(screenW: w)),
              SizedBox(height: AppMetrics.s(w, 10)),

              stagger(
                4,
                // Figma has this as a single line, but at 52 characters it
                // sits right on the edge of the card's inner width - so on a
                // slightly narrower screen "plants." dropped to a second line
                // on its own. FittedBox with softWrap off guarantees one line
                // on every device: it shrinks the type a fraction rather than
                // wrapping, and does nothing at all where it already fits.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    'Sign in to start monitoring and caring for your plants.',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppMetrics.s(w, 11.5),
                      fontWeight: FontWeight.w400,
                      color: AppColors.hint,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 20)),

              stagger(
                5,
                AppField(
                  screenW: w,
                  controller: _emailCtrl,
                  hint: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  trailing: const Icon(Icons.mail_outline, size: 20),
                  onSubmitted: (_) => _usernameFocus.requestFocus(),
                  validator: (value) {
                    final String v = (value ?? '').trim();
                    if (v.isEmpty) return 'Enter your email';
                    // Deliberately loose - real validation belongs on the
                    // server; this only catches obvious typos.
                    if (!v.contains('@') || !v.contains('.')) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 12)),

              stagger(
                6,
                AppField(
                  screenW: w,
                  controller: _usernameCtrl,
                  focusNode: _usernameFocus,
                  hint: 'Username',
                  trailing: const Icon(Icons.person_outline, size: 20),
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                  validator: (value) {
                    final String v = (value ?? '').trim();
                    if (v.isEmpty) return 'Choose a username';
                    if (v.length < 3) return 'At least 3 characters';
                    return null;
                  },
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 12)),

              stagger(
                7,
                AppField(
                  screenW: w,
                  controller: _passwordCtrl,
                  focusNode: _passwordFocus,
                  hint: 'Password',
                  obscure: _obscurePassword,
                  onSubmitted: (_) => _confirmFocus.requestFocus(),
                  trailing: _eyeToggle(
                    on: _obscurePassword,
                    onTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (value) {
                    final String v = value ?? '';
                    if (v.isEmpty) return 'Choose a password';
                    if (v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 12)),

              stagger(
                8,
                AppField(
                  screenW: w,
                  controller: _confirmCtrl,
                  focusNode: _confirmFocus,
                  hint: 'Confirm Password',
                  obscure: _obscureConfirm,
                  action: TextInputAction.done,
                  onSubmitted: (_) => _handleSignUp(),
                  trailing: _eyeToggle(
                    on: _obscureConfirm,
                    onTap: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (value) {
                    if ((value ?? '').isEmpty) return 'Confirm your password';
                    if (value != _passwordCtrl.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 24)),

              stagger(
                9,
                PrimaryButton(
                  // Copy matches the Figma frame exactly - see my note about
                  // this reading as "Sign In" on a sign-up screen.
                  label: 'Sign In',
                  screenW: w,
                  busy: _busy,
                  onPressed: _handleSignUp,
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 10)),

              stagger(10, _legalConsent(w)),
              SizedBox(height: AppMetrics.s(w, 10)),

              stagger(
                11,
                TrailingLink(
                  screenW: w,
                  leading: 'Already have an Account?',
                  linkLabel: 'Log in',
                  onTap: _goToLogin,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "By signing up, you agree to our Terms and Conditions and Privacy Policy."
  ///
  /// Built from a Wrap of separate pieces rather than a RichText with tap
  /// recognisers - recognisers have to be created and disposed by hand, and
  /// leaking them is easy. This also lets each link carry the same press
  /// feedback as every other control in the app.
  Widget _legalConsent(double w) {
    final TextStyle plain = TextStyle(
      fontFamily: 'Inter',
      fontSize: AppMetrics.s(w, 11),
      fontWeight: FontWeight.w400,
      color: AppColors.hint,
      height: 1.5,
    );
    final TextStyle link = plain.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.wordmarkGreen,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.wordmarkGreen,
    );

    Widget tappable(String label, LegalDoc doc) => PressableScale(
          pressedScale: 0.92,
          onTap: () => Navigator.of(context).push(LegalScreen.route(doc)),
          child: Text(label, style: link),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text('By signing up, you agree to our ', style: plain),
        tappable('Terms and Conditions', LegalDoc.terms),
        Text(' and ', style: plain),
        tappable('Privacy Policy', LegalDoc.privacy),
        Text('.', style: plain),
      ],
    );
  }

  Widget _eyeToggle({required bool on, required VoidCallback onTap}) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.85,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Icon(
          on ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: AppColors.hint,
        ),
      ),
    );
  }
}