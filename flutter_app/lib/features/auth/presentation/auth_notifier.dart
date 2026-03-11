import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/firebase_guard.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Auth state stream (read-only)
// ─────────────────────────────────────────────────────────────────────────────

/// Tracks the signed-in user. Rebuilds any widget that watches it whenever
/// the auth state changes (sign in, sign out, token refresh).
final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Auth form state
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class AuthFormState {
  const AuthFormState({
    this.isLoading = false,
    this.errorMessage,
  });

  final bool    isLoading;
  final String? errorMessage;

  AuthFormState copyWith({bool? isLoading, Object? errorMessage = _sentinel}) {
    return AuthFormState(
      isLoading:    isLoading    ?? this.isLoading,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _sentinel = Object();

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class AuthNotifier extends Notifier<AuthFormState> {
  @override
  AuthFormState build() => const AuthFormState();

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // firebaseGuardRethrow reports the error to Sentry, then rethrows so
      // we can map FirebaseAuthException codes to user-friendly messages.
      await firebaseGuardRethrow(
        () => FirebaseAuth.instance.signInWithEmailAndPassword(
          email:    email.trim(),
          password: password,
        ),
        tags: {'operation': 'auth_sign_in', 'screen': 'LoginPage'},
      );
      state = state.copyWith(isLoading: false);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading:    false,
        errorMessage: _authMessage(e.code),
      );
    } on Exception {
      state = state.copyWith(
        isLoading:    false,
        errorMessage: 'No internet connection. Check your network.',
      );
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final cred = await firebaseGuardRethrow(
        () => FirebaseAuth.instance.createUserWithEmailAndPassword(
          email:    email.trim(),
          password: password,
        ),
        tags: {'operation': 'auth_register', 'screen': 'LoginPage'},
      );
      await firebaseGuard(
        () async => cred.user?.updateDisplayName(name.trim()),
        tags: {'operation': 'auth_update_display_name'},
      );
      state = state.copyWith(isLoading: false);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading:    false,
        errorMessage: _authMessage(e.code),
      );
    } on Exception {
      state = state.copyWith(
        isLoading:    false,
        errorMessage: 'No internet connection. Check your network.',
      );
    }
  }

  Future<void> signOut() async {
    await firebaseGuard(
      () => FirebaseAuth.instance.signOut(),
      tags: {'operation': 'auth_sign_out'},
    );
    state = const AuthFormState();
  }

  Future<void> sendPasswordReset(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await firebaseGuardRethrow(
        () => FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim()),
        tags: {'operation': 'auth_password_reset', 'screen': 'LoginPage'},
      );
      state = state.copyWith(isLoading: false);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading:    false,
        errorMessage: _authMessage(e.code),
      );
    } on Exception {
      state = state.copyWith(
        isLoading:    false,
        errorMessage: 'No internet connection. Check your network.',
      );
    }
  }

  void clearError() => state = state.copyWith(errorMessage: null);

  String _authMessage(String code) {
    switch (code) {
      case 'user-not-found':         return 'No account found with this email.';
      case 'wrong-password':         return 'Incorrect password.';
      case 'invalid-credential':     return 'Invalid email or password.';
      case 'email-already-in-use':   return 'An account with this email already exists.';
      case 'weak-password':          return 'Password must be at least 6 characters.';
      case 'invalid-email':          return 'Please enter a valid email address.';
      case 'too-many-requests':      return 'Too many attempts. Try again later.';
      case 'network-request-failed': return 'No internet connection. Check your network.';
      default:                       return 'Authentication error ($code).';
    }
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthFormState>(AuthNotifier.new);
