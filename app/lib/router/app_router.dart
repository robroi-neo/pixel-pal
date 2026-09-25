import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../screens/create_room_screen.dart';
import '../screens/email_login_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/game_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/prompt_pick_screen.dart';
import '../screens/room_created_screen.dart';
import '../screens/room_screen.dart';
import '../screens/round_home_screen.dart';
import '../services/auth_service.dart';

class AppRoutes {
  AppRoutes._();

  /// Design.md §5 "Sign in" — the landing screen (mark, wordmark, Google
  /// primary / email secondary). Not a form; see [emailLogin] for that.
  static const login = '/login';
  static const emailLogin = '/login/email';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const home = '/home';
  static const createRoom = '/create-room';
  static const roomCreated = '/create-room/success';

  /// `/rooms/:roomId` — build with `'$rooms/$roomId'`. The owner's view
  /// (invite code, waiting for players); see [roundHome] for everyone
  /// else's view of an ongoing room.
  static const rooms = '/rooms';
  static const roomDetail = '/rooms/:roomId';

  /// `/rooms/:roomId/round` — Design.md §5 "Round home (hub)". Reached by
  /// non-owners for now; giving the owner this same hub once a room has
  /// real rounds running is follow-up work.
  static const roundHome = '/rooms/:roomId/round';

  /// Design.md §5 "Prompt pick". Not room-scoped in the path — there's no
  /// per-room prompt issuance yet (Implementations.md Phase 3), so this
  /// doesn't need a roomId to know what to show.
  static const promptPick = '/prompt-pick';
  static const game = '/game';
}

/// Dev-only escape hatch: when true, the auth gate below treats every user
/// as signed in, so the app lands straight on /home without touching
/// Firebase Auth or the emulator. Only takes effect in debug builds —
/// `kDebugMode` is `false` in release/profile builds, so this can never
/// ship as a real auth bypass. Flip to `false` to test the real sign-in
/// flow locally.
const bool kDevBypassAuth = false;

/// Builds the app's router with an auth gate: signed-out users are bounced
/// to /login, signed-in users are bounced away from the auth screens to
/// /home. Re-evaluates automatically whenever [authService]'s auth state
/// changes (sign in, register, sign out) via [GoRouterRefreshStream] — no
/// screen needs to call `context.go` after a successful sign-in.
GoRouter buildAppRouter(AuthService authService) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: GoRouterRefreshStream(authService.authStateChanges),
    redirect: (context, state) {
      final loggedIn =
          (kDebugMode && kDevBypassAuth) || authService.currentUser != null;
      final onAuthScreen =
          state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.emailLogin ||
          state.matchedLocation == AppRoutes.register ||
          state.matchedLocation == AppRoutes.forgotPassword;

      if (!loggedIn && !onAuthScreen) return AppRoutes.login;
      if (loggedIn && onAuthScreen) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.emailLogin,
        builder: (context, state) => const EmailLoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.createRoom,
        builder: (context, state) => const CreateRoomScreen(),
      ),
      GoRoute(
        path: AppRoutes.roomCreated,
        builder: (context, state) =>
            RoomCreatedScreen(args: state.extra! as RoomCreatedArgs),
      ),
      GoRoute(
        path: AppRoutes.roomDetail,
        builder: (context, state) =>
            RoomScreen(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: AppRoutes.roundHome,
        builder: (context, state) =>
            RoundHomeScreen(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: AppRoutes.promptPick,
        builder: (context, state) => const PromptPickScreen(),
      ),
      GoRoute(
        path: AppRoutes.game,
        builder: (context, state) => const GameScreen(),
      ),
    ],
  );
}

/// Bridges a [Stream] (Firebase's authStateChanges) into a [Listenable]
/// so GoRouter re-evaluates `redirect` whenever auth state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<User?> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<User?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
