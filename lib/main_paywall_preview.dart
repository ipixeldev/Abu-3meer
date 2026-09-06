/// Developer-only entrypoint for capturing the real App Store paywall.
///
/// This loads RevenueCat's published offering and StoreKit's localized
/// products, without signing in to a real app account or calling our backend.
/// For a simulator screenshot, configure this Flutter target and run from an
/// Xcode debug scheme using Abu3meerAppStorePreview.storekit. That file is
/// synchronized from App Store Connect; billing remains local Xcode testing.
/// The native paywall remains interactive, so do not tap purchase or restore
/// controls when only capturing screenshots. Restore the generated Flutter
/// target to lib/main.dart afterwards. Normal builds use lib/main.dart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import 'production/subscription_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) {
    throw UnsupportedError(
      'Paywall preview is only available in debug builds.',
    );
  }
  runApp(const _PaywallPreviewApp());
}

class _PaywallPreviewApp extends StatelessWidget {
  const _PaywallPreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: const _PaywallPreviewScreen(),
  );
}

class _PaywallPreviewScreen extends StatefulWidget {
  const _PaywallPreviewScreen();

  @override
  State<_PaywallPreviewScreen> createState() => _PaywallPreviewScreenState();
}

class _PaywallPreviewScreenState extends State<_PaywallPreviewScreen> {
  bool _configured = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPaywall());
  }

  Future<void> _openPaywall() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final key = SubscriptionService.instance.apiKey;
      if (!key.startsWith('appl_')) {
        throw StateError('Use the real iOS appl_ SDK key for this preview.');
      }
      if (!_configured) {
        await Purchases.setLogLevel(LogLevel.debug);
        // Anonymous preview identity; never uses or changes a real app profile.
        await Purchases.configure(PurchasesConfiguration(key));
        _configured = true;
      }
      final offering = (await Purchases.getOfferings()).current;
      if (offering == null || offering.availablePackages.isEmpty) {
        throw StateError(
          'The current App Store offering has no available products.',
        );
      }
      for (final package in offering.availablePackages) {
        debugPrint(
          'Paywall product ${package.storeProduct.identifier}: '
          '${package.storeProduct.priceString}',
        );
      }
      final result = await RevenueCatUI.presentPaywall(
        offering: offering,
        displayCloseButton: true,
      );
      if (result == PaywallResult.error) {
        throw StateError('RevenueCat could not present the published paywall.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ABU 3MEER · Paywall preview'),
              const SizedBox(height: 24),
              if (_loading) const CircularProgressIndicator(),
              if (_error != null) Text(_error!, textAlign: TextAlign.center),
              if (!_loading)
                FilledButton(
                  onPressed: _openPaywall,
                  child: const Text('Open App Store paywall'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
