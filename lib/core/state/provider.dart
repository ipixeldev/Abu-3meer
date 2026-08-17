// Provider setup for the app state.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';

/// Multi-provider wrapper for the app.
List<ChangeNotifierProvider> appProviders = [
  ChangeNotifierProvider<AppState>(create: (_) => AppState()),
];

/// Convenience extension for accessing AppState.
extension AppStateExt on BuildContext {
  AppState get appState => watch<AppState>();
  AppState get appStateRead => read<AppState>();
}

/// Consumer widget for AppState (rebuilds only when specific values change).
class AppStateConsumer<T> extends StatelessWidget {
  final T Function(AppState) selector;
  final Widget Function(BuildContext, T, Widget?) builder;
  final Widget? child;

  const AppStateConsumer({
    super.key,
    required this.selector,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return builder(context, selector(state), child);
      },
      child: child,
    );
  }
}

/// Selector for specific AppState values to minimize rebuilds.
class AppStateSelector<T> extends StatelessWidget {
  final T Function(AppState) selector;
  final Widget Function(BuildContext, T) builder;
  final bool Function(T, T)? shouldRebuild;

  const AppStateSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.shouldRebuild,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, T>(
      selector: (_, state) => selector(state),
      shouldRebuild: shouldRebuild ?? (prev, next) => prev != next,
      builder: (_, value, __) => builder(context, value),
    );
  }
}
