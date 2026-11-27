import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pay first: the app only opens for members with an active membership and for admins.
/// The decision comes from the database (`is_premium_self`, true for admins as well); the router reads it.
class AccessNotifier extends ChangeNotifier {
  bool? premium; // null: not checked yet, or the check failed (see [failed])
  bool admin = false;
  bool failed = false;

  Future<void> refresh() async {
    final client = Supabase.instance.client;
    try {
      final p = await client.rpc('is_premium_self');
      final a = await client.rpc('is_admin_self');
      premium = p == true;
      admin = a == true;
      failed = false;
    } catch (_) {
      premium = null;
      failed = true;
    }
    notifyListeners();
  }

  void clear() {
    premium = null;
    admin = false;
    failed = false;
    notifyListeners();
  }
}

final accessProvider = ChangeNotifierProvider<AccessNotifier>((ref) {
  final notifier = AccessNotifier();
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) notifier.refresh();
  final sub = auth.onAuthStateChange.listen((state) {
    if (state.session != null) {
      notifier.refresh();
    } else {
      notifier.clear();
    }
  });
  ref.onDispose(sub.cancel);
  return notifier;
});

/// Where the router sends a visitor, given the sign-in and membership state.
/// Pure function so the rules can be unit tested.
String? accessRedirect({required String location, required bool signedIn, required bool? premium}) {
  if (!signedIn) return location == '/login' ? null : '/login';
  if (premium == null) return location == '/splash' ? null : '/splash';
  if (!premium) return location == '/paywall' ? null : '/paywall';
  if (location == '/login' || location == '/splash' || location == '/paywall') return '/home';
  return null;
}
