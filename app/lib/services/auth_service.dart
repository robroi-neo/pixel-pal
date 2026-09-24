import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around [FirebaseAuth] — screens never touch the Firebase
/// SDK directly, only this service. Keeps auth logic in one place and
/// makes swapping/mocking the provider a one-file change.
class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  // `GoogleSignIn.instance.initialize()` must be called exactly once for
  // the process's lifetime before any other GoogleSignIn method — this
  // caches that call across AuthService instances (screens each construct
  // their own `AuthService()`) rather than tracking init state per-instance.
  static Future<void>? _googleSignInInit;

  static Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInit ??= GoogleSignIn.instance.initialize();
  }

  User? get currentUser => _auth.currentUser;

  /// Emits whenever the signed-in user changes (sign in, sign out,
  /// account deletion). GoRouter listens to this — see router/app_router.dart.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  /// Creates the account and (per Firebase's default behavior) signs the
  /// user in immediately — no separate sign-in call needed afterward.
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (fullName.trim().isNotEmpty) {
        await credential.user?.updateDisplayName(fullName.trim());
      }
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  /// Signs in with Google via the platform's native account picker, then
  /// exchanges the resulting ID token for a Firebase credential.
  ///
  /// Requires OAuth client IDs to be configured in the Firebase/Google
  /// console for each platform this ships on — without that, this throws
  /// a generic [AuthException] rather than a raw plugin error. On web,
  /// `google_sign_in` requires its own rendered button rather than a
  /// custom one (see [GoogleSignIn.supportsAuthenticate]); until that's
  /// wired up separately, web users see the same friendly fallback.
  Future<void> signInWithGoogle() async {
    try {
      await _ensureGoogleSignInInitialized();
      final googleSignIn = GoogleSignIn.instance;
      if (!googleSignIn.supportsAuthenticate()) {
        throw AuthException(
          "Google sign-in isn't set up on this platform yet — use email instead.",
        );
      }
      final account = await googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on AuthException {
      rethrow;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      throw AuthException("Couldn't sign in with Google — try again.");
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    } catch (_) {
      // Covers platform-channel failures — most likely Google sign-in
      // isn't finished configuring yet for this platform/environment.
      throw AuthException(
        "Google sign-in isn't finished setting up yet — use email instead.",
      );
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Maps Firebase's error codes to plain, actionable copy: say what
  /// happened and what to do next, never "Error: request failed."
  String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return "That email address doesn't look right — check it and try again.";
      case 'user-disabled':
        return 'This account has been disabled. Contact support if this seems wrong.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return "Couldn't sign in — check your email and password and try again.";
      case 'email-already-in-use':
        return 'An account already exists for this email — try signing in instead.';
      case 'weak-password':
        return 'Choose a stronger password — at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts — wait a moment and try again.';
      case 'network-request-failed':
        return "Couldn't connect — check your internet and try again.";
      default:
        return e.code;
    }
  }
}

/// Thrown by [AuthService] with copy that's already safe to show the user.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
