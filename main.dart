import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/env.dart';
import 'features/billing/billing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // clean URLs on the web; Cloudflare Pages serves index.html for every path (_redirects)
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  await BillingService.instance.init();
  final auth = Supabase.instance.client.auth;
  if (auth.currentUser != null) BillingService.instance.logIn(auth.currentUser!.id);
  auth.onAuthStateChange.listen((state) {
    final user = state.session?.user;
    if (user != null) {
      BillingService.instance.logIn(user.id);
    } else {
      BillingService.instance.logOut();
    }
  });
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'GoldenTongue',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      // Phone-first layout: on tablets and desktops the app stays a centered column instead of stretching.
      builder: (context, child) => ColoredBox(
        color: Colors.black,
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child ?? const SizedBox.shrink())),
      ),
    );
  }
}
