import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_sound.dart';
import 'app_ui.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // 0: staged off-frame to the RIGHT
  // 1: logo ROLLS in and parks at its lockup spot, landing UPRIGHT
  // 2: "PlantGuard" wipes in left-to-right beside it, then holds
  // 3: wordmark fades out while the logo goes straight up + bigger + to
  //    centre, as one single movement (no separate trip to the middle)
  // 4: hero copy, button and bottom shape arrive
  int _step = 0;

  // --- Motion blur state -------------------------------------------------
  // Pulsed per movement: ramps up fast as travel begins, then burns off over
  // the rest of the movement so everything arrives sharp.
  double _blurSigma = _rollBlur; // starts blurred while off-frame
  double _blurRatio = 0.25; // sigmaY / sigmaX. <1 horizontal, >1 vertical
  Duration _blurDuration = const Duration(milliseconds: 140);

  // ---------------------------------------------------------------------
  // FIGMA REFERENCE (measured on a 390x844 frame), kept as ratios so the
  // layout holds on any screen instead of only at exactly 390dp wide.
  // ---------------------------------------------------------------------
  static const double _refFrameWidth = 390.0;
  static const double _refLogoBox = 103.0; // Figma logo frame: W 103 / H 103

  // ---------------------------------------------------------------------
  // LOCKUP TUNING - how the shield and the wordmark sit together.
  // ---------------------------------------------------------------------

  /// How much of the logo PNG is actual artwork rather than the transparent
  /// padding baked into the file. Padding is invisible but still occupies
  /// layout space, which is what widens the gap and shrinks the word.
  /// Set to 1.0 once the PNG is cropped tight to the shield.
  static const double _logoArtworkFraction = 0.72;

  /// Wordmark font size as a fraction of the VISIBLE shield height.
  static const double _fontToArt = 0.55;

  /// Gap between the visible shield and the "P", as a fraction of the
  /// VISIBLE shield height.
  static const double _gapToArt = 0.14;

  // --- Timing ------------------------------------------------------------
  static const Duration _rollIn = Duration(milliseconds: 1500);
  static const Duration _wipe = Duration(milliseconds: 900);
  static const Duration _heroMove = Duration(milliseconds: 1200);
  static const Duration _blurRamp = Duration(milliseconds: 140);

  /// The wordmark's exit is deliberately much shorter than the hero move it
  /// overlaps. Fading it across the full 1200ms left it hanging around while
  /// the logo travelled; clearing it quickly hands the screen to the logo.
  static const Duration _wordmarkOut = Duration(milliseconds: 320);

  static const double _rollBlur = 26.0;
  static const double _textBlur = 8.0;

  @override
  void initState() {
    super.initState();
    _runAnimationSequence();
  }

  /// Advances to [step] and pulses the motion blur across the movement:
  /// blur snaps up as travel begins, then resolves to sharp over the rest of
  /// the duration. [ratio] weights the blur along the axis of travel.
  Future<void> _move(
    int step, {
    required Duration duration,
    required double sigma,
    required double ratio,
    VoidCallback? onStart,
  }) async {
    if (!mounted) return;
    // Fired in the same frame the movement begins, so the whoosh is locked to
    // the motion rather than trailing it.
    onStart?.call();
    setState(() {
      _step = step;
      _blurSigma = sigma;
      _blurRatio = ratio;
      _blurDuration = _blurRamp;
    });

    await Future.delayed(_blurRamp);
    if (!mounted) return;

    setState(() {
      _blurSigma = 0.0;
      _blurDuration = duration - _blurRamp;
    });
    await Future.delayed(duration - _blurRamp);
  }

  Future<void> _runAnimationSequence() async {
    // Sit on white for a beat so the hand-off from the native launch screen
    // is invisible.
    await Future.delayed(const Duration(milliseconds: 600));

    // The ambient bed is deliberately NOT started here - splash, login and
    // signup stay quiet apart from their own effects. The dashboard starts it
    // with AppSound.instance.startAmbient().

    // STEP 1: roll in from off-frame right, straight to the lockup spot,
    // finishing upright. whoosh1 rides the travel.
    await _move(
      1,
      duration: _rollIn,
      sigma: _rollBlur,
      ratio: 0.25,
      onStart: () => AppSound.instance.whoosh(variant: 1),
    );
    await Future.delayed(const Duration(milliseconds: 350));

    // STEP 2: wordmark wipes in left-to-right beside the shield, then holds.
    // The shine lands on the brand name appearing.
    if (mounted) setState(() => _step = 2);
    AppSound.instance.splashShine();
    await Future.delayed(_wipe + const Duration(milliseconds: 1900));

    // STEP 3: wordmark fades out while the logo goes up + bigger + centre,
    // all in one movement. Lighter blur here than the roll - the logo is
    // scaling rather than travelling fast, and a heavy blur resolving at the
    // end reads as a pop rather than a settle. whoosh2 is a different sample
    // from the roll-in, so the two moves don't sound identical.
    await _move(
      3,
      duration: _heroMove,
      sigma: 9.0,
      ratio: 1.3,
      onStart: () => AppSound.instance.whoosh(variant: 2),
    );

    // STEP 4: hero copy, gradient button and bottom shape.
    if (mounted) setState(() => _step = 4);
  }

  TextStyle _wordmarkStyle(double fontSize) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: FontWeight.w800, // Figma: Extra Bold
      letterSpacing: fontSize * -0.02,
      height: 1.0, // tight line box, so vertical centring is exact
    );
  }

  /// Measures the wordmark exactly as it will render, so the pair is centred
  /// from its REAL width - holds even if 'Inter' isn't bundled and Flutter
  /// substitutes a font with different letter widths.
  Size _wordmarkSize(double fontSize) {
    final painter = TextPainter(
      text: TextSpan(text: 'PlantGuard', style: _wordmarkStyle(fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.size;
  }

  /// Directional blur, weighted along the axis of travel so movement reads as
  /// motion blur rather than an out-of-focus smudge.
  ///
  /// IMPORTANT: this always returns ImageFiltered, even at zero blur, and
  /// floors sigma at a hair above zero instead of returning the bare child.
  /// Returning the child unwrapped once the blur burned off would change the
  /// SHAPE of the widget tree mid-animation - Flutter would then tear down
  /// and rebuild everything below it, so AnimatedRotation and
  /// AnimatedContainer would lose their in-flight animation state and snap
  /// straight to their targets. That snap was the flicker at the end of the
  /// grow. Keeping one stable widget type here costs a spare filter layer and
  /// removes the flicker entirely.
  Widget _motionBlur(double sigma, double ratio, Widget child) {
    final double s = sigma < 0.01 ? 0.01 : sigma; // never exactly zero
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s * ratio),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;
    final double screenH = MediaQuery.of(context).size.height;

    // --- SIZES ---------------------------------------------------------
    final double logoBox = screenW * (_refLogoBox / _refFrameWidth);
    final double artSize = logoBox * _logoArtworkFraction;
    final double logoPad = (logoBox - artSize) / 2;

    final double fontSize = artSize * _fontToArt;
    final double gap = artSize * _gapToArt;
    final Size textSize = _wordmarkSize(fontSize);

    final double bigLogoBox = screenW * 0.50; // hero size, step 3 onward

    // --- CENTRING ------------------------------------------------------
    // Centres the VISIBLE lockup (shield + gap + word), not the padded box,
    // because the visible edges are what the eye reads as centred.
    final double lockupW = artSize + gap + textSize.width;
    final double lockupLeft = (screenW - lockupW) / 2;
    final double centreY = screenH * 0.5;

    // Parked logo box position. The padding is subtracted so the SHIELD, not
    // the box, lands on the mark.
    final double parkedLeft = lockupLeft - logoPad;
    final double offFrameLeft = screenW + logoBox;

    final double textLeft = lockupLeft + artSize + gap;
    final double textTop = centreY - (textSize.height / 2);

    // --- ROLLING -------------------------------------------------------
    // How far it travels, divided by its circumference, is how many turns a
    // wheel of that size would make covering that distance. But that lands
    // on a fraction (~1.46 turns here), and a fractional turn leaves the
    // logo stopped at an angle. So it is ROUNDED TO WHOLE TURNS: still a
    // true-feeling roll, but it always finishes upright.
    // Travelling leftward rolls counter-clockwise, hence negative.
    final double circumference = math.pi * logoBox;
    double rollTurns =
        (-(offFrameLeft - parkedLeft) / circumference).roundToDouble();
    if (rollTurns == 0) rollTurns = -1.0; // always at least one full roll

    // 0 while staged; after that it holds its upright landing angle - there
    // is no rolling during the hero move.
    final double logoTurns = _step == 0 ? 0.0 : rollTurns;

    // --- LOGO STATE PER STEP -------------------------------------------
    final double logoSize = _step >= 3 ? bigLogoBox : logoBox;

    double logoLeft;
    if (_step == 0) {
      logoLeft = offFrameLeft; // fully off-frame, to the right
    } else if (_step <= 2) {
      logoLeft = parkedLeft; // lockup spot
    } else {
      logoLeft = (screenW - bigLogoBox) / 2; // hero, centred
    }

    final double logoTop =
        _step >= 3 ? screenH * 0.12 : centreY - (logoSize / 2);

    Duration logoDuration;
    Curve logoCurve;
    switch (_step) {
      case 0:
        logoDuration = Duration.zero;
        logoCurve = Curves.linear;
        break;
      case 1:
        logoDuration = _rollIn;
        logoCurve = Curves.easeInOutCubic; // gentle at the start of the roll
        break;
      case 2:
        logoDuration = _wipe;
        logoCurve = Curves.easeInOutCubic;
        break;
      default:
        // Up, bigger and centred all ride this one duration and curve, so it
        // reads as a single movement rather than three stacked ones.
        logoDuration = _heroMove;
        logoCurve = Curves.easeInOutCubic;
    }

    final double finalUiTop = (screenH * 0.12) + bigLogoBox + (screenH * 0.03);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // --- FINAL SCREEN: bottom gradient shape ---
          AnimatedPositioned(
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutQuart,
            bottom: _step >= 4 ? 0 : -(screenH * 0.35),
            left: -20,
            right: -20,
            child: Container(
              height: screenH * 0.25,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF385129), Color(0xFF121F0A)],
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.elliptical(screenW * 2, 80),
                ),
              ),
            ),
          ),

          // --- "PlantGuard" wordmark ---
          // Wipes IN left-to-right (ClipRect crops to the Align box, whose
          // widthFactor grows 0 -> 1 anchored on its left edge), then FADES
          // out in step 3 - widthFactor stays at 1 there so it dissolves in
          // place instead of un-wiping while the logo leaves.
          Positioned(
            left: textLeft,
            top: textTop,
            child: ClipRect(
              child: AnimatedAlign(
                duration: _wipe,
                curve: Curves.easeInOutCubic,
                alignment: Alignment.centerLeft,
                widthFactor: _step >= 2 ? 1.0 : 0.0,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: _textBlur,
                    end: _step == 2 ? 0.0 : _textBlur,
                  ),
                  duration: _step >= 3 ? _wordmarkOut : _wipe,
                  curve: Curves.easeOut,
                  builder: (context, sigma, child) =>
                      _motionBlur(sigma, 0.6, child!),
                  child: AnimatedOpacity(
                    // Slow, soft wipe in; quick, clean exit.
                    duration: _step >= 3 ? _wordmarkOut : _wipe,
                    curve: Curves.easeIn,
                    opacity: _step == 2 ? 1.0 : 0.0,
                    // RichText has no const constructor (it builds its span
                    // list at runtime) - only the TextSpan tree can be const.
                    child: RichText(
                      text: TextSpan(
                        style: _wordmarkStyle(fontSize),
                        children: const [
                          TextSpan(
                            text: 'Plant',
                            style: TextStyle(color: Color(0xFF669934)),
                          ),
                          TextSpan(
                            text: 'Guard',
                            style: TextStyle(color: Color(0xFF000000)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // --- LOGO ---
          // Position, rotation and size share one duration and curve, so the
          // roll never slips against the travel and the hero move rises,
          // grows and centres as a single motion.
          AnimatedPositioned(
            duration: logoDuration,
            curve: logoCurve,
            left: logoLeft,
            top: logoTop,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: _rollBlur, end: _blurSigma),
              duration: _blurDuration,
              curve: Curves.easeOut,
              builder: (context, sigma, child) =>
                  _motionBlur(sigma, _blurRatio, child!),
              child: AnimatedRotation(
                turns: logoTurns,
                duration: logoDuration,
                curve: logoCurve,
                child: AnimatedContainer(
                  duration: logoDuration,
                  curve: logoCurve,
                  width: logoSize,
                  height: logoSize,
                  child: Image.asset(
                    'assets/images/plantguard_logo.png',
                    fit: BoxFit.contain,
                    // The hero move scales the artwork up by roughly 2x;
                    // medium filtering keeps that resample clean instead of
                    // crawling as it grows.
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),

          // --- FINAL SCREEN: hero copy + gradient button ---
          AnimatedPositioned(
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutQuart,
            top: _step >= 4 ? finalUiTop : finalUiTop + 40,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 1000),
              opacity: _step >= 4 ? 1.0 : 0.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PlantGuard: Smart Care for\nHealthier Plants',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: screenW * (22 / _refFrameWidth),
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: screenH * 0.05),

                  // Gradient "Get Started" button. PressableScale gives it a
                  // physical press-in with a haptic tick and a click.
                  PressableScale(
                    onTap: () {
                      // LoginScreen.route() is a rise-and-fade rather than the
                      // default cut. pushReplacement so back doesn't return to
                      // the splash.
                      Navigator.of(context)
                          .pushReplacement(LoginScreen.route());
                    },
                    child: Container(
                      width: screenW * 0.85,
                      height: screenW * (60 / _refFrameWidth),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF7CB342), Color(0xFF558B2F)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Text(
                        'Get Started',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: screenW * (20 / _refFrameWidth),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}