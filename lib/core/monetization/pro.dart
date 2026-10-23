import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/camera/application/camera_ui_state.dart' show PrefKeys;
import '../providers.dart';

/// Darkroom Pro: one purchase that lifts the free version's daily limits
/// (unlimited film and battery, swap film mid-roll, full Super 8
/// cartridges). Kept in prefs; a store purchase or restore sets it, and
/// Debug can flip it either way.
class ProNotifier extends Notifier<bool> {
  @override
  bool build() => prefsOf(ref)?.getBool(PrefKeys.pro) ?? false;

  /// [bought]: the store granted it (true) or took it back (false); null
  /// = Debug's switch, which the store leaves alone.
  Future<void> set(bool on, {bool? bought}) async {
    state = on;
    final prefs = prefsOf(ref);
    await prefs?.setBool(PrefKeys.pro, on);
    if (bought != null) await prefs?.setBool(PrefKeys.proBought, bought);
  }

  bool get bought => prefsOf(ref)?.getBool(PrefKeys.proBought) ?? false;
}

/// The app's prefs, or null where there are none (widget tests).
SharedPreferencesWithCache? prefsOf(Ref ref) {
  try {
    return ref.read(sharedPrefsProvider);
  } catch (_) {
    return null;
  }
}

final proProvider = NotifierProvider<ProNotifier, bool>(ProNotifier.new);

/// What happened when the user tried to buy or restore.
enum StoreResult { bought, restored, nothingToRestore, cancelled, unavailable, failed, pending }

/// Google Play / App Store billing for the one product.
class ProStore {
  ProStore(this._ref);

  final Ref _ref;
  static const productId = 'darkroom_pro';

  /// Shown until the store says otherwise.
  static const fallbackPrice = r'$4.99';

  StreamSubscription<List<PurchaseDetails>>? _sub;
  Future<void>? _started;
  Completer<StoreResult>? _waiting;
  bool _restoring = false;
  ProductDetails? _product;

  /// Listens to purchase updates (must start early: a purchase can finish
  /// after the app was closed) and quietly restores an earlier purchase.
  /// Safe to call again: later calls wait for the first.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    try {
      if (!await InAppPurchase.instance.isAvailable()) return;
      _sub = InAppPurchase.instance.purchaseStream.listen(
        _onUpdates,
        onError: (Object e) => _finish(StoreResult.failed),
      );
      await _checkRefund();
      // iOS can ask for the Apple ID password on a restore, so there it
      // only happens from the Restore button.
      if (defaultTargetPlatform == TargetPlatform.android) await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('Store unavailable: $e');
    }
  }

  /// A refunded purchase disappears from Google Play's list: take Pro back
  /// (only Pro the store gave, and only when Play actually answered).
  Future<void> _checkRefund() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final pro = _ref.read(proProvider.notifier);
    if (!_ref.read(proProvider) || !pro.bought) return;
    final r = await InAppPurchase.instance
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
        .queryPastPurchases();
    if (r.error != null) return;
    final owned = r.pastPurchases.any(
      (p) =>
          p.productID == productId && p.status != PurchaseStatus.error && p.status != PurchaseStatus.pending,
    );
    if (!owned) await pro.set(false, bought: false);
  }

  /// The local price, e.g. "$4.99", once the store has answered.
  Future<String> price() async => (await _details())?.price ?? fallbackPrice;

  Future<ProductDetails?> _details() async {
    if (_product != null) return _product;
    try {
      if (!await InAppPurchase.instance.isAvailable()) return null;
      final r = await InAppPurchase.instance.queryProductDetails({productId});
      return _product = r.productDetails.where((p) => p.id == productId).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  Future<StoreResult> buy() async {
    await start();
    final p = await _details();
    if (p == null) return StoreResult.unavailable;
    final waiting = _waiting = Completer<StoreResult>();
    try {
      final ok = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: p),
      );
      if (!ok) _finish(StoreResult.failed);
    } catch (_) {
      _finish(StoreResult.failed);
    }
    return waiting.future.timeout(const Duration(minutes: 5), onTimeout: () => StoreResult.pending);
  }

  Future<StoreResult> restore() async {
    await start();
    if (_sub == null) return StoreResult.unavailable;
    final waiting = _waiting = Completer<StoreResult>();
    _restoring = true;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {
      _finish(StoreResult.failed);
    }
    // Restores arrive on the stream; none at all means nothing was bought.
    return waiting.future.timeout(const Duration(seconds: 8), onTimeout: () => StoreResult.nothingToRestore);
  }

  Future<void> _onUpdates(List<PurchaseDetails> updates) async {
    for (final u in updates) {
      if (u.productID != productId) continue;
      switch (u.status) {
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          await _ref.read(proProvider.notifier).set(true, bought: true);
          _finish(
            u.status == PurchaseStatus.purchased && !_restoring ? StoreResult.bought : StoreResult.restored,
          );
        case PurchaseStatus.pending:
          // Paid later (cash, slow card): Pro arrives on this stream then.
          _finish(StoreResult.pending);
        case PurchaseStatus.canceled:
          _finish(StoreResult.cancelled);
        case PurchaseStatus.error:
          if (u.error?.message.contains('itemAlreadyOwned') ?? false) {
            // Bought before (another phone, a reinstall): that's a restore.
            await _ref.read(proProvider.notifier).set(true, bought: true);
            _finish(StoreResult.restored);
          } else {
            _finish(StoreResult.failed);
          }
      }
      if (u.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(u);
    }
  }

  void _finish(StoreResult r) {
    _restoring = false;
    final w = _waiting;
    _waiting = null;
    if (w != null && !w.isCompleted) w.complete(r);
  }

  void dispose() => _sub?.cancel();
}

final proStoreProvider = Provider<ProStore>((ref) {
  final s = ProStore(ref);
  ref.onDispose(s.dispose);
  return s;
});
