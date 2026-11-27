import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_providers.dart';

/// Server-side entitlement check (see `is_premium` in the database).
final isPremiumProvider = FutureProvider.autoDispose<bool>((ref) async {
  final res = await sb.rpc('is_premium_self');
  return res == true;
});

/// True for admin accounts (full access, no limits). Checked on the server; admins also count as premium.
final isAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  final res = await sb.rpc('is_admin_self');
  return res == true;
});
