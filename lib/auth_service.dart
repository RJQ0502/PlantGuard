import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Signup details held between submitting the form and verifying the emailed
/// code, at which point the account is actually created.
///
/// The password lives in memory for the length of that hop. It is no more
/// exposed than it already was in the form's TextEditingController, and it is
/// never written to disk, Firestore, or the OTP email.
class PendingSignup {
  const PendingSignup({
    required this.email,
    required this.password,
    required this.username,
  });

  final String email;
  final String password;
  final String username;
}

/// Thin wrapper over Firebase Auth and the user profile in Firestore.
///
/// Every method returns `null` on success or a ready-to-show message on
/// failure, so call sites stay a simple `if (error != null)`.
///
/// WHY EVERY CALL HAS A TIMEOUT
/// Firestore is offline-first: when it cannot reach the server it does NOT
/// throw, it queues the operation and waits. A signup against an unreachable
/// database therefore hangs forever with no error - the button just spins.
/// Timeouts convert that silence into a message the user can act on. This is
/// the single most important thing in this file.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Long enough for a slow mobile connection, short enough that a user does
  /// not think the app is dead.
  static const Duration _timeout = Duration(seconds: 15);

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  Stream<User?> get authState => _auth.authStateChanges();

  // =====================================================================
  // SIGN UP - deliberately two steps
  //
  // The account is NOT created when the form is submitted. If it were,
  // abandoning the OTP screen would leave an unverified account behind
  // forever, and deleting it on Cancel would not help because a force-quit
  // skips that path entirely.
  //
  // So: [checkAvailability] runs on submit, the code is emailed, and
  // [createAccount] only runs once that code has been verified. Nothing
  // exists in Firebase until the user has proved they own the address.
  // =====================================================================

  /// Verifies the username and email are both free, before anything is
  /// created. Returns null when the signup may proceed.
  Future<String?> checkAvailability({
    required String email,
    required String username,
  }) async {
    final String cleanUser = username.trim();
    final String cleanEmail = email.trim().toLowerCase();

    try {
      // Source.server, not the default cache-then-server: an offline read
      // returns an empty result, which would read as "free" and let a
      // duplicate through. Better to fail loudly.
      final QuerySnapshot<Map<String, dynamic>> byName = await _db
          .collection('users')
          .where('username', isEqualTo: cleanUser)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      if (byName.docs.isNotEmpty) return 'That username is already taken.';

      // Email is checked against our own collection rather than
      // fetchSignInMethodsForEmail(), which returns an empty list on modern
      // projects because email enumeration protection is on by default - it
      // would report every address as free.
      final QuerySnapshot<Map<String, dynamic>> byEmail = await _db
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      if (byEmail.docs.isNotEmpty) {
        return 'An account already exists with that email.';
      }

      return null;
    } on TimeoutException {
      return _timeoutMessage;
    } on FirebaseException catch (e) {
      return _firestoreMessage(e);
    } catch (e) {
      debugPrint('AuthService.checkAvailability: $e');
      return 'Could not reach the database. Check your connection.';
    }
  }

  /// Creates the account. Call ONLY after the emailed code has been verified.
  Future<String?> createAccount({
    required String email,
    required String password,
    required String username,
  }) async {
    final String cleanUser = username.trim();
    final String cleanEmail = email.trim().toLowerCase();

    // --- 2. Create the account ----------------------------------------
    UserCredential cred;
    try {
      cred = await _auth
          .createUserWithEmailAndPassword(email: cleanEmail, password: password)
          .timeout(_timeout);
    } on TimeoutException {
      return _timeoutMessage;
    } on FirebaseAuthException catch (e) {
      return _authMessage(e);
    } catch (e) {
      debugPrint('AuthService.createAccount create: $e');
      return 'Could not create the account. Please try again.';
    }

    final User? user = cred.user;
    if (user == null) return 'Account created but no user returned.';

    // --- 3. Write the profile -----------------------------------------
    // If this fails the account exists but has no username, so login by
    // username would never find it. Rather than leave that orphan behind,
    // the account is deleted and the user can simply try again.
    try {
      await user.updateDisplayName(cleanUser).timeout(_timeout);
      await _db
          .collection('users')
          .doc(user.uid)
          .set(<String, dynamic>{
            'username': cleanUser,
            'email': cleanEmail,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(_timeout);
    } catch (e) {
      debugPrint('AuthService.createAccount profile write failed, rolling back: $e');
      try {
        await user.delete().timeout(_timeout);
      } catch (_) {
        // Rollback itself failed - the orphan stays, but reporting the
        // original problem is more useful than reporting this one.
      }
      if (e is TimeoutException) return _timeoutMessage;
      if (e is FirebaseException) return _firestoreMessage(e);
      return 'Could not save your profile. Please try again.';
    }

    // --- 4. Optional: Firebase's own verification link ------------------
    // Not fatal if it fails - the account is already usable, and the app
    // sends its own 6-digit code separately.
    try {
      await user.sendEmailVerification().timeout(_timeout);
    } catch (e) {
      debugPrint('AuthService.createAccount verification email: $e');
    }

    return null;
  }

  // =====================================================================
  // SIGN IN
  // =====================================================================

  Future<String?> signIn({
    required String usernameOrEmail,
    required String password,
  }) async {
    String email = usernameOrEmail.trim();

    // A username has to be resolved to its email first - Firebase only
    // authenticates by email.
    if (!email.contains('@')) {
      try {
        final QuerySnapshot<Map<String, dynamic>> snap = await _db
            .collection('users')
            .where('username', isEqualTo: email)
            .limit(1)
            .get(const GetOptions(source: Source.server))
            .timeout(_timeout);

        if (snap.docs.isEmpty) return 'No account found with that username.';
        email = snap.docs.first.data()['email'] as String;
      } on TimeoutException {
        return _timeoutMessage;
      } on FirebaseException catch (e) {
        return _firestoreMessage(e);
      } catch (e) {
        debugPrint('AuthService.signIn lookup: $e');
        return 'Could not reach the database. Check your connection.';
      }
    }

    try {
      await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(_timeout);
      return null;
    } on TimeoutException {
      return _timeoutMessage;
    } on FirebaseAuthException catch (e) {
      return _authMessage(e);
    } catch (e) {
      debugPrint('AuthService.signIn: $e');
      return 'Sign-in failed. Please try again.';
    }
  }

  Future<void> signOut() => _auth.signOut();

  // =====================================================================
  // PROFILE
  // =====================================================================

  Future<String?> currentUsername() async {
    final User? user = _auth.currentUser;
    if (user == null) return null;
    if ((user.displayName ?? '').isNotEmpty) return user.displayName;

    try {
      final doc = await _db
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(_timeout);
      return doc.data()?['username'] as String?;
    } catch (e) {
      debugPrint('AuthService.currentUsername: $e');
      return null;
    }
  }

  // =====================================================================
  // PASSWORD RESET
  // =====================================================================

  /// Sends Firebase's built-in reset email (a link, not a code).
  ///
  /// Succeeds even when no account uses that address - deliberate, so the
  /// endpoint cannot be used to discover which emails are registered.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim()).timeout(_timeout);
      return null;
    } on TimeoutException {
      return _timeoutMessage;
    } on FirebaseAuthException catch (e) {
      return _authMessage(e);
    } catch (e) {
      debugPrint('AuthService.sendPasswordReset: $e');
      return 'Could not send the reset email. Please try again.';
    }
  }

  // =====================================================================
  // DIAGNOSTICS
  // =====================================================================

  /// Round-trips a tiny read to prove Firestore is actually reachable.
  /// Handy from a debug button when something "just doesn't respond".
  Future<String> diagnose() async {
    final StringBuffer out = StringBuffer();
    out.writeln('Signed in: $isSignedIn');
    try {
      await _db
          .collection('users')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      out.writeln('Firestore: reachable');
    } on TimeoutException {
      out.writeln('Firestore: TIMED OUT - not created, or no network');
    } on FirebaseException catch (e) {
      out.writeln('Firestore: ${e.code} - ${e.message}');
    } catch (e) {
      out.writeln('Firestore: $e');
    }
    return out.toString();
  }

  // =====================================================================
  // MESSAGES
  // =====================================================================

  static const String _timeoutMessage =
      'The server is not responding. Check your internet connection, and '
      'that Firestore has been created in the Firebase console.';

  /// Firestore failures, kept separate from auth failures because the fixes
  /// are completely different - and "database not created yet" is by far the
  /// most common one during setup.
  String _firestoreMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Database access denied. Check your Firestore security rules.';
      case 'unavailable':
        return 'Cannot reach the database. Check your connection.';
      case 'not-found':
      case 'failed-precondition':
        return 'Firestore has not been created for this project yet. '
            'Firebase Console -> Build -> Firestore Database -> Create '
            'database.';
      default:
        return 'Database error (${e.code}). ${e.message ?? ''}';
    }
  }

  /// Recent Firebase returns 'invalid-credential' for BOTH a wrong password
  /// and an unknown email, on purpose - so nobody can probe which addresses
  /// have accounts. The message stays vague for the same reason.
  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'Password is too weak - use at least 8 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again.';
      case 'operation-not-allowed':
        return 'Email sign-in is not enabled for this Firebase project.';
      default:
        return 'Authentication failed (${e.code}).';
    }
  }
}