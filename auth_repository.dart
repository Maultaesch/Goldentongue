import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  /// Web returns to the site itself; mobile apps return through their deep link.
  static String get _redirect => kIsWeb ? Uri.base.origin : 'io.goldentongue://login-callback';

  final SupabaseClient _client;
  AuthRepository([SupabaseClient? client]) : _client = client ?? Supabase.instance.client;

  /// [captchaToken] is the Turnstile token; Supabase rejects the request when CAPTCHA protection is on and it is missing.
  Future<void> signInWithEmail(String email, String password, {String? captchaToken}) =>
      _client.auth.signInWithPassword(email: email, password: password, captchaToken: captchaToken);

  /// [adultConfirmed] is stored in user metadata and copied to `profiles`
  /// by the `handle_new_user` trigger.
  Future<void> signUpWithEmail(String email, String password,
          {required bool adultConfirmed, String? captchaToken}) =>
      _client.auth.signUp(
        email: email,
        password: password,
        data: {'adult_confirmed': adultConfirmed},
        captchaToken: captchaToken,
      );

  Future<void> signInWithGoogle() => _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _redirect,
      );

  Future<void> signInWithApple() => _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: _redirect,
      );

  Future<void> signOut() => _client.auth.signOut();

  /// Deletes the account and all its data on the server, then signs out locally.
  /// Active store or Stripe subscriptions are not cancelled by this; the app tells the user to cancel them.
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account', body: {'confirm': 'DELETE'});
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }
}
