import 'dart:async';
import 'dart:ui' show Color;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../models/prompt.dart';
import '../screens/auth/email_login_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/guess/guess_list_screen.dart';
import '../screens/guess/guess_results_screen.dart';
import '../screens/guess/guess_screen.dart';
import '../screens/profile/icon_editor_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/rooms/create_room_screen.dart';
import '../screens/rooms/home_screen.dart';
import '../screens/rooms/room_created_screen.dart';
import '../screens/rooms/room_screen.dart';
import '../screens/round/drawing_screen.dart';
import '../screens/round/prompt_pick_screen.dart';
import '../screens/round/round_home_screen.dart';
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

  /// `/rooms/:roomId/prompt-pick` — Design.md §5 "Prompt pick". Room- (and
  /// member-) scoped now: what a member is offered is persisted to
  /// `rooms/{roomId}/members/{uid}.issuedPromptIds` so it stays stable
  /// across visits.
  static const promptPick = '/rooms/:roomId/prompt-pick';

  /// `/rooms/:roomId/draw` — Design.md §5 "Draw / editor". The chosen
  /// [Prompt] travels via `extra` (it's not URL-safe data, and there's no
  /// server-side "current prompt" to look up instead).
  static const draw = '/rooms/:roomId/draw';

  /// `/rooms/:roomId/guess` — the grid hub: this round's drawings, in a
  /// per-player order, with your own progress on each.
  static const guess = '/rooms/:roomId/guess';

  /// `/rooms/:roomId/guess/:authorUid` — the swipeable guess cards,
  /// opened on that drawing.
  static const guessDrawing = '/rooms/:roomId/guess/:authorUid';

  /// `/rooms/:roomId/results` — the deadline reveal, played as a
  /// sequence. `?drawing=` starts it on that drawing's stage.
  static const results = '/rooms/:roomId/results';

  static String guessDrawingPath(String roomId, String authorUid) =>
      '$rooms/$roomId/guess/$authorUid';

  static String resultsPath(String roomId, {String? startAt}) => startAt == null
      ? '$rooms/$roomId/results'
      : '$rooms/$roomId/results?drawing=$startAt';

  static const profile = '/profile';

  /// The current icon (nullable `List<Color>`) travels via `extra`.
  static const profileIcon = '/profile/icon';
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
        builder: (context, state) =>
            PromptPickScreen(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: AppRoutes.draw,
        builder: (context, state) => DrawingScreen(
          roomId: state.pathParameters['roomId']!,
          prompt: state.extra! as Prompt,
        ),
      ),
      GoRoute(
        path: AppRoutes.guess,
        builder: (context, state) =>
            GuessListScreen(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: AppRoutes.guessDrawing,
        builder: (context, state) => GuessScreen(
          roomId: state.pathParameters['roomId']!,
          authorUid: state.pathParameters['authorUid']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.results,
        builder: (context, state) => GuessResultsScreen(
          roomId: state.pathParameters['roomId']!,
          startAt: state.uri.queryParameters['drawing'],
        ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileIcon,
        builder: (context, state) =>
            IconEditorScreen(initialIcon: state.extra as List<Color>?),
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
