import 'package:flutter/widgets.dart';

/// Global [RouteObserver] that can be used across the app to watch route changes.
///
/// Register this in [MaterialApp.navigatorObservers] and subscribe via
/// `routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute)`.
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();
