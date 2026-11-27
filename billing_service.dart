import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/env.dart';

enum BillingPlan {
  monthly('monthly', 'Monthly', '14.99 USD', 'per month', PackageType.monthly),
  quarterly('quarterly', 'Quarterly', '34.99 USD', 'save 22 percent', PackageType.threeMonth),
  yearly('yearly', 'Yearly', '99.99 USD', 'save 44 percent', PackageType.annual);

  final String id;
  final String title;
  final String fallbackPrice;
  final String note;
  final PackageType packageType;
  const BillingPlan(this.id, this.title, this.fallbackPrice, this.note, this.packageType);
}

/// Mobile: in-app purchases through RevenueCat (App Store and Google Play).
/// Web: Stripe Checkout through the `create-checkout` edge function.
/// The server (webhooks -> `subscriptions` table) is the source of truth.
class BillingService {
  BillingService._();
  static final instance = BillingService._();

  bool _ready = false;
  bool get storeAvailable => !kIsWeb && _ready;

  Future<void> init() async {
    if (kIsWeb) return;
    final key = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => Env.revenueCatIosKey,
      TargetPlatform.android => Env.revenueCatAndroidKey,
      _ => '',
    };
    if (key.isEmpty) return;
    await Purchases.configure(PurchasesConfiguration(key));
    _ready = true;
  }

  Future<void> logIn(String userId) async {
    if (_ready) await Purchases.logIn(userId);
  }

  Future<void> logOut() async {
    if (!_ready) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  Future<Map<BillingPlan, Package>> packages() async {
    if (!_ready) return {};
    final offerings = await Purchases.getOfferings();
    final available = offerings.current?.availablePackages ?? const <Package>[];
    final out = <BillingPlan, Package>{};
    for (final plan in BillingPlan.values) {
      for (final p in available) {
        if (p.packageType == plan.packageType) out[plan] = p;
      }
    }
    return out;
  }

  /// Returns false if the user cancelled the purchase sheet.
  Future<bool> purchase(Package package) async {
    try {
      await Purchases.purchasePackage(package);
      return true;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> restore() async {
    if (_ready) await Purchases.restorePurchases();
  }
}
