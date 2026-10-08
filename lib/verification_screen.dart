import 'package:flutter/material.dart';

import 'app_sound.dart';
import 'app_ui.dart';
import 'login_screen.dart';

/// Both success states from the Figma share one layout and differ only in
/// copy, so they are one screen with two named constructors rather than two
/// near-identical files.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    required this.title,
    required this.message,
    this.onContinue,
    this.greetingAfter,
  });

  /// "Verification Complete" - the end of the sign-up path.
  const VerificationScreen.complete({super.key, this.onContinue})
      : title = 'Verification Complete',
        message = 'Enjoy our service',
        greetingAfter = null;

  /// "Successful!" - the end of the password-reset path.
  const VerificationScreen.passwordChanged({super.key, this.onContinue})
      : title = 'Successful!',
        message = 'Congratulations! Your password has been changed. '
            'Click "Continue" to log in again.',
        greetingAfter = LoginGreeting.pleaseLogIn;

  final String title;
  final String message;
  final VoidCallback? onContinue;

  /// Which greeting login should show when Continue lands there. A password
  /// change deliberately asks the user to log in again.
  final LoginGreeting? greetingAfter;

  static Route<void> completeRoute({VoidCallback? onContinue}) =>
      slideSideRoute<void>(VerificationScreen.complete(onContinue: onContinue));

  static Route<void> passwordChangedRoute({VoidCallback? onContinue}) =>
      slideSideRoute<void>(
        VerificationScreen.passwordChanged(onContinue: onContinue),
      );

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _badge;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    // The badge gets its own controller so it can overshoot and settle,
    // which the shared linear stagger can't express.
    _badge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _intro.forward();
    });
    Future.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      _badge.forward();
      AppSound.instance.success();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _badge.dispose();
    super.dispose();
  }

  void _continue() {
    if (widget.onContinue != null) {
      widget.onContinue!.call();
      return;
    }
    // Default: clear the whole auth stack and land on login, so back can't
    // walk the user through the flow again.
    Navigator.of(context).pushAndRemoveUntil(
      LoginScreen.route(greeting: widget.greetingAfter),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double w = size.width;
    final double sideMargin = AppMetrics.s(w, 16);
    final double badge = AppMetrics.s(w, 76);

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
                children: [
                  SizedBox(height: size.height * 0.06),
                  StaggerIn(
                    controller: _intro,
                    slot: 0,
                    dy: 20,
                    child: BrandLockup(screenW: w, logoPx: 52),
                  ),
                  SizedBox(height: size.height * 0.16),

                  // clipBehavior none so the badge can hang above the card's
                  // top edge, as in the design.
                  StaggerIn(
                    controller: _intro,
                    slot: 2,
                    dy: 40,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: badge / 2),
                          child: _card(w, badge),
                        ),
                        _checkBadge(badge),
                      ],
                    ),
                  ),
                  SizedBox(height: sideMargin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkBadge(double d) {
    return AnimatedBuilder(
      animation: _badge,
      builder: (context, _) {
        // easeOutBack overshoots past 1.0 and settles - that little pop is
        // what makes it read as a confirmation rather than a static icon.
        final double t = Curves.easeOutBack.transform(_badge.value);
        return Transform.scale(
          scale: t.clamp(0.0, 1.4),
          child: Opacity(
            // Opacity asserts outside 0..1, and easeOutBack exceeds 1, so the
            // fade rides a separate non-overshooting curve.
            opacity: Curves.easeOut.transform(_badge.value).clamp(0.0, 1.0),
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF56C24A), Color(0xFF2E9E3E)],
                ),
                border: Border.all(color: Colors.white, width: d * 0.045),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: d * 0.55,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(double w, double badge) {
    return GlassCard(
      screenW: w,
      padded: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppMetrics.s(w, 22),
          // Room for the half of the badge overlapping the card.
          (badge / 2) + AppMetrics.s(w, 18),
          AppMetrics.s(w, 22),
          AppMetrics.s(w, 24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StaggerIn(
              controller: _intro,
              slot: 4,
              dy: 18,
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppMetrics.s(w, 21),
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: AppMetrics.s(w, 8)),

            StaggerIn(
              controller: _intro,
              slot: 5,
              dy: 18,
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppMetrics.s(w, 12),
                  fontWeight: FontWeight.w400,
                  color: AppColors.bodyText,
                  height: 1.45,
                ),
              ),
            ),
            SizedBox(height: AppMetrics.s(w, 26)),

            StaggerIn(
              controller: _intro,
              slot: 6,
              dy: 18,
              child: PrimaryButton(
                label: 'Continue',
                screenW: w,
                onPressed: _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}