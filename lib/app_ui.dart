import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_sound.dart';

// =========================================================================
// DESIGN TOKENS
// Measured against a 390dp-wide frame and applied as ratios, so every screen
// holds its proportions on any device instead of only one size.
// =========================================================================

class AppMetrics {
  const AppMetrics._();

  static const double refW = 390.0;

  /// Scales a Figma pixel value to the current screen width.
  static double s(double screenW, double figmaPx) =>
      screenW * (figmaPx / refW);
}

class AppColors {
  const AppColors._();

  // Background treatment.
  static const Color dimTop = Color(0xA60B1E0D);
  static const Color dimBottom = Color(0xD1071505);
  static const Color fallbackBackdrop = Color(0xFF14331A);

  // Glass card.
  static const Color cardTint = Color(0x66132E14);
  static const Color cardTintDeep = Color(0x9E0B1F0A);
  static const Color cardStroke = Color(0x24FFFFFF);

  // Controls.
  static const Color fieldFill = Color(0x1FFFFFFF);
  static const Color fieldStroke = Color(0x38FFFFFF);
  static const Color fieldStrokeFocused = Color(0x8CFFFFFF);
  static const Color hint = Color(0xB0FFFFFF);
  static const Color bodyText = Color(0xD9FFFFFF);

  // Brand.
  static const Color green = Color(0xFF7CB342);
  static const Color greenDeep = Color(0xFF558B2F);
  static const Color wordmarkGreen = Color(0xFF7DBE4A);

  // Feedback. Muted rather than a bright red - on a dark green card a
  // saturated red reads as an alarm and fights the palette.
  static const Color danger = Color(0x99E9A08C);
  static const Color dangerText = Color(0xCCF3C4B4);
  static const Color snack = Color(0xFF1B3B1C);
}

/// Share of the logo PNG that is real artwork rather than the transparent
/// padding baked into the file. Spacing is measured from the visible shield,
/// not the padded box. Set to 1.0 if the PNG is ever cropped tight.
const double kLogoArtworkFraction = 0.72;

// =========================================================================
// PRESS FEEDBACK
// =========================================================================

/// Wraps any widget so it visibly reacts to touch: it scales down and dims
/// slightly while held, and releases with a haptic tick and a click.
///
/// This is what makes controls feel physical rather than painted on. Use it
/// for anything tappable that isn't already a Material button.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.pressedOpacity = 0.88,
    this.playSound = true,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final double pressedOpacity;
  final bool playSound;
  final HitTestBehavior behavior;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: enabled
          ? () {
              if (widget.playSound) AppSound.instance.tap();
              widget.onTap!.call();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        // Fast down, so the reaction feels immediate rather than laggy.
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: enabled ? (_down ? widget.pressedOpacity : 1.0) : 0.55,
          duration: const Duration(milliseconds: 110),
          child: widget.child,
        ),
      ),
    );
  }
}

// =========================================================================
// STAGGERED ENTRANCE
// =========================================================================

/// Fades and slides [child] into place on its own slice of a shared timeline,
/// so a screen's contents arrive in sequence rather than all at once.
///
/// [dx] slides horizontally (used by screens that arrive from the side),
/// [dy] vertically. Give each element an increasing [slot].
class StaggerIn extends StatelessWidget {
  const StaggerIn({
    super.key,
    required this.controller,
    required this.slot,
    required this.child,
    this.dx = 0,
    this.dy = 26,
    this.step = 0.075,
    this.span = 0.40,
  });

  final Animation<double> controller;
  final int slot;
  final Widget child;
  final double dx;
  final double dy;

  /// How much later each slot starts than the one before it.
  final double step;

  /// How much of the timeline a single element's move occupies.
  final double span;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, inner) {
        final double start = slot * step;
        final double raw = ((controller.value - start) / span).clamp(0.0, 1.0);
        // easeOutCubic never overshoots, so this is safe to feed straight
        // into Opacity, which asserts on values outside 0..1.
        final double t = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((1 - t) * dx, (1 - t) * dy),
            child: inner,
          ),
        );
      },
    );
  }
}

// =========================================================================
// BACKGROUND
// =========================================================================

/// Standard luminance-preserving saturation matrix. 1.0 leaves the image
/// untouched, 0.0 renders it greyscale.
List<double> saturationMatrix(double s) {
  const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final double r = (1 - s) * lr, g = (1 - s) * lg, b = (1 - s) * lb;
  return <double>[
    r + s, g, b, 0, 0, //
    r, g + s, b, 0, 0, //
    r, g, b + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// The shared photographic backdrop: desaturated, blurred, then dimmed with a
/// green wash that deepens toward the bottom so card text always has contrast.
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    this.asset = 'assets/images/background.jpg',
    this.blur = 7.0,
    this.saturation = 0.82,
  });

  final String asset;
  final double blur;
  final double saturation;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.matrix(saturationMatrix(saturation)),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            // Scaled past the edges so the blur has real pixels to sample and
            // doesn't feather at the screen border.
            child: Transform.scale(
              scale: 1.08,
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const ColoredBox(color: AppColors.fallbackBackdrop),
              ),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.dimTop, AppColors.dimBottom],
            ),
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// GLASS CARD
// =========================================================================

/// Frosted panel that blurs whatever sits behind it, rather than being a flat
/// translucent rectangle.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    required this.screenW,
    this.blur = 20.0,
    this.radiusPx = 34,
    this.padded = true,
  });

  final Widget child;
  final double screenW;
  final double blur;
  final double radiusPx;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final double radius = AppMetrics.s(screenW, radiusPx);
    final double pad = AppMetrics.s(screenW, 24);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.cardTint, AppColors.cardTintDeep],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.cardStroke, width: 1),
          ),
          child: padded
              ? Padding(
                  padding: EdgeInsets.fromLTRB(pad, pad * 1.15, pad, pad),
                  child: child,
                )
              : child,
        ),
      ),
    );
  }
}

// =========================================================================
// LOCKUP
// =========================================================================

/// Shield plus "PlantGuard", spaced off the visible artwork rather than the
/// padded PNG box.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    required this.screenW,
    this.logoPx = 46,
    this.guardColour = Colors.white,
  });

  final double screenW;
  final double logoPx;
  final Color guardColour;

  /// Wordmark em size as a fraction of the VISIBLE shield height.
  ///
  /// Measured off the Figma lockup: the shield is ~19px tall and the cap
  /// height of "PlantGuard" ~11px, which is an em size of ~15.3px - so the
  /// font runs at roughly 0.80 of the shield. The previous 0.62 made the
  /// shield read as oversized and chunky next to the word.
  static const double _fontToArt = 0.80;

  /// Gap between shield and "P", as a fraction of the visible shield.
  static const double _gapToArt = 0.13;

  @override
  Widget build(BuildContext context) {
    final double logoBox = AppMetrics.s(screenW, logoPx);
    final double artSize = logoBox * kLogoArtworkFraction;
    final double fontSize = artSize * _fontToArt;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: logoBox,
          height: logoBox,
          child: Image.asset(
            'assets/images/plantguard_logo.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
        SizedBox(width: artSize * _gapToArt),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: fontSize * -0.02,
              height: 1.0,
            ),
            children: [
              const TextSpan(
                text: 'Plant',
                style: TextStyle(color: AppColors.wordmarkGreen),
              ),
              TextSpan(text: 'Guard', style: TextStyle(color: guardColour)),
            ],
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// FIELD
// =========================================================================

class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.screenW,
    required this.controller,
    required this.hint,
    this.trailing,
    this.obscure = false,
    this.keyboardType,
    this.action = TextInputAction.next,
    this.onSubmitted,
    this.focusNode,
    this.validator,
    // Errors appear only after the user has actually touched the field, and
    // clear again as soon as it is valid. Without this, one tap on the submit
    // button lights up every field at once and the screen fills with red -
    // which is what the build screenshots were showing.
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  final double screenW;
  final TextEditingController controller;
  final String hint;
  final Widget? trailing;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction action;
  final void Function(String)? onSubmitted;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final AutovalidateMode autovalidateMode;

  @override
  Widget build(BuildContext context) {
    final double w = screenW;
    final double radius = AppMetrics.s(w, 14);

    OutlineInputBorder border(Color colour) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: colour, width: 1),
        );

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: action,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      autovalidateMode: autovalidateMode,
      cursorColor: Colors.white,
      style: TextStyle(
        fontFamily: 'Inter',
        color: Colors.white,
        fontSize: AppMetrics.s(w, 15),
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          color: AppColors.hint,
          fontSize: AppMetrics.s(w, 15),
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: AppColors.fieldFill,
        suffixIcon: trailing,
        suffixIconColor: AppColors.hint,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppMetrics.s(w, 18),
          vertical: AppMetrics.s(w, 17),
        ),
        border: border(AppColors.fieldStroke),
        enabledBorder: border(AppColors.fieldStroke),
        focusedBorder: border(AppColors.fieldStrokeFocused),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger),
        // Kept tight so an error nudges the layout rather than shoving the
        // whole card down, and small enough not to compete with the field.
        errorStyle: TextStyle(
          fontFamily: 'Inter',
          color: AppColors.dangerText,
          fontSize: AppMetrics.s(w, 11),
          height: 1.1,
        ),
        errorMaxLines: 1,
      ),
    );
  }
}

// =========================================================================
// BUTTONS
// =========================================================================

/// Filled green pill. Presses in, ticks, and swaps to a spinner while busy.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.screenW,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final double screenW;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final double height = AppMetrics.s(screenW, 54);
    final bool enabled = onPressed != null && !busy;

    return PressableScale(
      onTap: enabled ? onPressed : null,
      child: Container(
        height: height,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.green, AppColors.greenDeep],
          ),
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: busy
            ? SizedBox(
                width: height * 0.42,
                height: height * 0.42,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppMetrics.s(screenW, 18),
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

/// Outlined pill for the secondary action.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.screenW,
    this.onPressed,
  });

  final String label;
  final double screenW;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final double height = AppMetrics.s(screenW, 54);

    return PressableScale(
      onTap: onPressed,
      child: Container(
        height: height,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          border: Border.all(color: const Color(0xB3FFFFFF), width: 1.4),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppMetrics.s(screenW, 16),
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// "Already have an Account? Log in" - plain text with a tappable green tail.
class TrailingLink extends StatelessWidget {
  const TrailingLink({
    super.key,
    required this.screenW,
    required this.leading,
    required this.linkLabel,
    this.onTap,
  });

  final double screenW;
  final String leading;
  final String linkLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double size = AppMetrics.s(screenW, 12.5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          leading,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: size,
            fontWeight: FontWeight.w400,
            color: AppColors.bodyText,
          ),
        ),
        PressableScale(
          onTap: onTap,
          pressedScale: 0.92,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppMetrics.s(screenW, 4),
              vertical: AppMetrics.s(screenW, 6),
            ),
            child: Text(
              linkLabel,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: AppColors.wordmarkGreen,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.wordmarkGreen,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Back control for the sign-up frame.
///
/// The Figma shows a bare arrow with no chip behind it, so there is no circle
/// here - but the tap target stays a full 40dp square via the transparent
/// padding, which a bare glyph on its own would not give.
class BackCircleButton extends StatelessWidget {
  const BackCircleButton({super.key, required this.screenW, this.onTap});

  final double screenW;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double d = AppMetrics.s(screenW, 40);
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.86,
      child: SizedBox(
        width: d,
        height: d,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: AppMetrics.s(screenW, 26),
            shadows: const [
              Shadow(color: Color(0x66000000), blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// SNACKBAR
// =========================================================================

/// Centred modal with an OK button - the app's standard way of reporting an
/// error or a result the user must acknowledge.
///
/// Preferred over a snackbar for anything that went wrong: a snackbar slides
/// away on its own and is easy to miss, which is exactly the wrong behaviour
/// for a message the user needs to read and act on.
Future<void> showAppDialog(
  BuildContext context, {
  required String message,
  String? title,
  bool isError = true,
  String okLabel = 'OK',
}) {
  final double w = MediaQuery.of(context).size.width;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0xB3000000),
    builder: (BuildContext ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(horizontal: AppMetrics.s(w, 32)),
        child: GlassCard(
          screenW: w,
          padded: false,
          radiusPx: 26,
          blur: 26,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppMetrics.s(w, 24),
              AppMetrics.s(w, 26),
              AppMetrics.s(w, 24),
              AppMetrics.s(w, 20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon badge - amber for problems, green for confirmations.
                Center(
                  child: Container(
                    width: AppMetrics.s(w, 54),
                    height: AppMetrics.s(w, 54),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isError
                          ? const Color(0x33E9A08C)
                          : const Color(0x3356C24A),
                      border: Border.all(
                        color: isError
                            ? const Color(0x80E9A08C)
                            : const Color(0x8056C24A),
                        width: 1.4,
                      ),
                    ),
                    child: Icon(
                      isError
                          ? Icons.priority_high_rounded
                          : Icons.check_rounded,
                      color: isError
                          ? const Color(0xFFF3C4B4)
                          : const Color(0xFF9BE08C),
                      size: AppMetrics.s(w, 30),
                    ),
                  ),
                ),
                SizedBox(height: AppMetrics.s(w, 16)),

                Text(
                  title ?? (isError ? 'Something went wrong' : 'Done'),
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
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppMetrics.s(w, 12.5),
                    fontWeight: FontWeight.w400,
                    color: AppColors.bodyText,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: AppMetrics.s(w, 22)),

                PrimaryButton(
                  label: okLabel,
                  screenW: w,
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Light, transient confirmations only. Anything the user must acknowledge
/// belongs in [showAppDialog].
void showAppSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Inter')),
        backgroundColor: AppColors.snack,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

// =========================================================================
// ROUTES
// =========================================================================

/// Rises from below and fades in. Used coming out of the splash.
Route<T> slideUpRoute<T>(Widget page, {Duration? duration}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration ?? const Duration(milliseconds: 750),
    reverseTransitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, secondary, child) {
      final Animation<double> curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Slides in from the right while the outgoing screen drifts left - lateral
/// navigation, so it reads as moving sideways through the flow.
Route<T> slideSideRoute<T>(Widget page, {Duration? duration}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration ?? const Duration(milliseconds: 620),
    reverseTransitionDuration: const Duration(milliseconds: 480),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, secondary, child) {
      final Animation<double> inCurve =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final Animation<double> outCurve =
          CurvedAnimation(parent: secondary, curve: Curves.easeOutCubic);

      return SlideTransition(
        // Outgoing screen eases a little to the left, so the two feel
        // connected rather than the new one covering a static page.
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.25, 0),
        ).animate(outCurve),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0),
            end: Offset.zero,
          ).animate(inCurve),
          child: FadeTransition(opacity: inCurve, child: child),
        ),
      );
    },
  );
}