import 'dart:async' show unawaited;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sound and haptics for the whole app.
///
/// WHY A POOL OF PLAYERS
/// The first version routed every sound effect through ONE AudioPlayer and did
/// `stop()` then `play()` on each call. Two problems followed from that:
///
///   1. Any sound fired while another was still playing killed it. A tap
///      landing during a whoosh silenced the whoosh, and vice versa.
///   2. `stop()` and `play()` are both async, so overlapping calls interleave
///      unpredictably - stop(A), stop(B), play(A), play(B). Sometimes nothing
///      came out, sometimes two things came out together.
///
/// Both symptoms had the same cause. Now each effect grabs the next player
/// from a small round-robin pool, so concurrent sounds coexist and a stop()
/// only ever touches the least recently used player - which has almost
/// certainly finished already.
///
/// The app is also designed to run with NO audio files at all: taps fall back
/// to the platform's own click plus a haptic tick.
class AppSound {
  AppSound._();
  static final AppSound instance = AppSound._();

  // NOTE ON PATHS: audioplayers' AssetSource already prefixes everything with
  // "assets/", so these are written WITHOUT it and resolve to
  // assets/sounds/*.mp3 on disk. Image.asset does NOT do this - image paths
  // elsewhere in the app spell out "assets/images/..." in full.
  static const String tapAsset = 'sounds/tap.mp3';
  static const String successAsset = 'sounds/success.mp3';
  static const String errorAsset = 'sounds/error.mp3';
  static const String ambientAsset = 'sounds/ambient_loop.mp3';

  /// The wordmark-reveal sound has gone by two names during development.
  /// Rather than break every time it is renamed, both spellings are tried in
  /// order and the first one that loads wins - and the winner is remembered,
  /// so the miss costs one lookup, not one per play.
  static const List<String> shineAssets = <String>[
    'sounds/splash_chime.mp3',
    'sounds/splash_shine.mp3',
  ];
  static const String whoosh1Asset = 'sounds/whoosh1.mp3';
  static const String whoosh2Asset = 'sounds/whoosh2.mp3';

  /// Four is enough for a tap landing on top of a transition whoosh with room
  /// to spare, without holding open more audio handles than necessary.
  static const int _poolSize = 4;

  final List<AudioPlayer> _pool = <AudioPlayer>[];
  int _nextPlayer = 0;

  final AudioPlayer _music = AudioPlayer(playerId: 'pg_music');

  /// Consecutive load failures per asset. A file is only given up on after
  /// several tries - one transient failure during startup shouldn't silence a
  /// sound for the rest of the session.
  final Map<String, int> _failures = <String, int>{};
  static const int _maxFailures = 3;

  bool soundEnabled = true;
  bool hapticsEnabled = true;
  bool musicEnabled = true;

  /// Effects sit near full volume; the ambient bed stays well underneath.
  double sfxVolume = 0.9;
  double musicVolume = 0.18;

  bool _ambientRunning = false;
  bool get isAmbientPlaying => _ambientRunning;

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      for (int i = 0; i < _poolSize; i++) {
        final AudioPlayer p = AudioPlayer(playerId: 'pg_sfx_$i');
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setVolume(sfxVolume);
        _pool.add(p);
      }
      await _music.setReleaseMode(ReleaseMode.loop); // seamless looping
      await _music.setVolume(musicVolume);
      _ready = true;
    } catch (e) {
      debugPrint('AppSound.init: $e');
    }
  }

  Future<void> dispose() async {
    for (final AudioPlayer p in _pool) {
      await p.dispose();
    }
    _pool.clear();
    await _music.dispose();
    _ready = false;
  }

  // ---------------------------------------------------------------------
  // EFFECTS
  // ---------------------------------------------------------------------

  /// Every button calls this. Haptic tick plus a short click.
  Future<void> tap() async {
    if (hapticsEnabled) unawaited(HapticFeedback.selectionClick());
    if (!soundEnabled) return;
    await _playSfx(tapAsset, fallbackToSystemClick: true);
  }

  /// Confirmations - verification complete, password changed, and so on.
  Future<void> success() async {
    if (hapticsEnabled) unawaited(HapticFeedback.mediumImpact());
    if (!soundEnabled) return;
    await _playSfx(successAsset, fallbackToSystemClick: true);
  }

  /// Failed validation or a rejected login.
  Future<void> error() async {
    if (hapticsEnabled) unawaited(HapticFeedback.heavyImpact());
    if (!soundEnabled) return;
    await _playSfx(errorAsset, fallbackToSystemClick: false);
  }

  /// Sparkle on the wordmark reveal in the splash.
  Future<void> splashShine({double volumeScale = 1.0}) async {
    if (!soundEnabled) return;
    await _playFirstAvailable(shineAssets, volumeScale: volumeScale);
  }

  /// Plays whichever of [candidates] loads first. Once one succeeds it is
  /// cached, so later calls go straight to it.
  String? _resolvedShine;

  Future<void> _playFirstAvailable(
    List<String> candidates, {
    double volumeScale = 1.0,
  }) async {
    final String? known = _resolvedShine;
    if (known != null) {
      await _playSfx(known, fallbackToSystemClick: false, volumeScale: volumeScale);
      return;
    }
    for (final String candidate in candidates) {
      if ((_failures[candidate] ?? 0) >= _maxFailures) continue;
      final bool ok = await _playSfx(
        candidate,
        fallbackToSystemClick: false,
        volumeScale: volumeScale,
      );
      if (ok) {
        _resolvedShine = candidate;
        return;
      }
    }
  }

  /// Movement sound. Variant 1 rides the splash roll-in; variant 2 is the
  /// hero move and the general page-transition whoosh.
  ///
  /// [volumeScale] trims it relative to [sfxVolume]. Page transitions pass a
  /// low value: the same sample that reads well under a big 1.2s splash move
  /// is far too heavy under a 0.6s slide between screens.
  Future<void> whoosh({int variant = 1, double volumeScale = 1.0}) async {
    if (!soundEnabled) return;
    await _playSfx(
      variant == 2 ? whoosh2Asset : whoosh1Asset,
      fallbackToSystemClick: false,
      volumeScale: volumeScale,
    );
  }

  // ---------------------------------------------------------------------
  // AMBIENT BED
  // ---------------------------------------------------------------------

  /// Starts the looping ambient bed. Safe to call repeatedly.
  ///
  /// Deliberately NOT called from the splash, login or signup - those screens
  /// stay quiet apart from their own effects. Call this once the dashboard
  /// appears, e.g. from its initState:
  ///
  ///   AppSound.instance.startAmbient();
  ///
  /// and call [stopAmbient] on sign-out.
  Future<void> startAmbient() async {
    if (!musicEnabled || _ambientRunning) return;
    if ((_failures[ambientAsset] ?? 0) >= _maxFailures) return;
    try {
      await _music.setVolume(musicVolume);
      await _music.play(AssetSource(ambientAsset));
      _ambientRunning = true;
      _failures.remove(ambientAsset);
    } catch (e) {
      _failures[ambientAsset] = (_failures[ambientAsset] ?? 0) + 1;
      debugPrint('AppSound: ambient unavailable - running silent. ($e)');
    }
  }

  Future<void> stopAmbient() async {
    if (!_ambientRunning) return;
    try {
      await _music.stop();
    } catch (_) {
      // The bed is optional either way.
    }
    _ambientRunning = false;
  }

  Future<void> pauseAmbient() async {
    if (!_ambientRunning) return;
    try {
      await _music.pause();
    } catch (_) {}
  }

  Future<void> resumeAmbient() async {
    if (!_ambientRunning || !musicEnabled) return;
    try {
      await _music.resume();
    } catch (_) {}
  }

  /// For a settings toggle.
  Future<void> setMusicEnabled(bool value) async {
    musicEnabled = value;
    if (value) {
      await startAmbient();
    } else {
      await stopAmbient();
    }
  }

  // ---------------------------------------------------------------------
  // INTERNALS
  // ---------------------------------------------------------------------

  /// Round-robin. Returns the least recently used player, so the stop() below
  /// lands on one that has had the longest time to finish.
  AudioPlayer? _take() {
    if (_pool.isEmpty) return null;
    final AudioPlayer p = _pool[_nextPlayer];
    _nextPlayer = (_nextPlayer + 1) % _pool.length;
    return p;
  }

  /// Returns true if the asset actually played, so callers that try several
  /// filenames can tell which one exists.
  Future<bool> _playSfx(
    String asset, {
    required bool fallbackToSystemClick,
    double volumeScale = 1.0,
  }) async {
    // Given up on: skip straight to the fallback, no exception, no delay.
    if ((_failures[asset] ?? 0) >= _maxFailures) {
      if (fallbackToSystemClick) {
        unawaited(SystemSound.play(SystemSoundType.click));
      }
      return false;
    }

    final AudioPlayer? p = _take();
    if (p == null) {
      // init() hasn't run or failed outright.
      if (fallbackToSystemClick) {
        unawaited(SystemSound.play(SystemSoundType.click));
      }
      return false;
    }

    try {
      await p.stop();
      await p.play(
        AssetSource(asset),
        volume: (sfxVolume * volumeScale).clamp(0.0, 1.0),
      );
      _failures.remove(asset); // recovered - forget earlier failures
      return true;
    } catch (e) {
      final int count = (_failures[asset] ?? 0) + 1;
      _failures[asset] = count;
      // Logged on EVERY failure, not just the last one. A sound that silently
      // never plays is impossible to diagnose otherwise - this prints the
      // exact path it looked for, so a filename mismatch is obvious in the
      // run console.
      debugPrint(
        'AppSound: failed to play "$asset" (attempt $count of $_maxFailures). '
        'Expected on disk at "assets/$asset". '
        'Check the filename matches exactly and that assets/sounds/ is listed '
        'in pubspec.yaml. ($e)',
      );
      if (fallbackToSystemClick) {
        unawaited(SystemSound.play(SystemSoundType.click));
      }
      return false;
    }
  }
}