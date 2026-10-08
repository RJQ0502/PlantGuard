import 'package:flutter/material.dart';

import 'app_sound.dart';
import 'app_ui.dart';
import 'login_screen.dart';
import 'verification_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  static Route<void> route() =>
      slideSideRoute<void>(const ResetPasswordScreen());

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _confirmFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _busy = false;

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
  }

  @override
  void dispose() {
    _intro.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _createPassword() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppSound.instance.error();
      return;
    }

    setState(() => _busy = true);
    // TODO(backend): submit the new password.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _busy = false);

    Navigator.of(context).pushReplacement(
      VerificationScreen.passwordChangedRoute(),
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      LoginScreen.route(greeting: LoginGreeting.pleaseLogIn),
      (route) => false,
    );
  }

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

                  stagger(
                    1,
                    Text(
                      'RESET PASSWORD',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppMetrics.s(w, 20),
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
                        shadows: const [
                          Shadow(
                            color: Color(0x59000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: AppMetrics.s(w, 8)),
                  stagger(
                    2,
                    Text(
                      'Your identity has been verified!\nSet your new password',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppMetrics.s(w, 11.5),
                        color: AppColors.bodyText,
                        height: 1.45,
                      ),
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              stagger(
                4,
                AppField(
                  screenW: w,
                  controller: _passwordCtrl,
                  hint: 'New Password',
                  obscure: _obscurePassword,
                  onSubmitted: (_) => _confirmFocus.requestFocus(),
                  trailing: _eye(
                    on: _obscurePassword,
                    onTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (value) {
                    final String v = value ?? '';
                    if (v.isEmpty) return 'Enter a new password';
                    if (v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 12)),

              stagger(
                5,
                AppField(
                  screenW: w,
                  controller: _confirmCtrl,
                  focusNode: _confirmFocus,
                  hint: 'Confirm Password',
                  obscure: _obscureConfirm,
                  action: TextInputAction.done,
                  onSubmitted: (_) => _createPassword(),
                  trailing: _eye(
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
                6,
                PrimaryButton(
                  label: 'Create Password',
                  screenW: w,
                  busy: _busy,
                  onPressed: _createPassword,
                ),
              ),
              SizedBox(height: AppMetrics.s(w, 10)),

              stagger(
                7,
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

  Widget _eye({required bool on, required VoidCallback onTap}) {
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