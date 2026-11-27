import 'package:goldentongue/core/access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? go(String loc, {required bool signedIn, bool? premium}) =>
      accessRedirect(location: loc, signedIn: signedIn, premium: premium);

  test('signed out visitors can only see the login screen', () {
    expect(go('/home', signedIn: false), '/login');
    expect(go('/library', signedIn: false), '/login');
    expect(go('/login', signedIn: false), isNull);
  });

  test('while the membership is being checked the splash screen is shown', () {
    expect(go('/home', signedIn: true, premium: null), '/splash');
    expect(go('/splash', signedIn: true, premium: null), isNull);
  });

  test('signed in without a membership can only see the paywall', () {
    for (final loc in ['/home', '/coach', '/library', '/studio/voice', '/profile', '/login']) {
      expect(go(loc, signedIn: true, premium: false), '/paywall', reason: loc);
    }
    expect(go('/paywall', signedIn: true, premium: false), isNull);
  });

  test('members and admins get the app and are moved off login, splash and paywall', () {
    expect(go('/home', signedIn: true, premium: true), isNull);
    expect(go('/studio/simulator', signedIn: true, premium: true), isNull);
    for (final loc in ['/login', '/splash', '/paywall']) {
      expect(go(loc, signedIn: true, premium: true), '/home', reason: loc);
    }
  });
}
