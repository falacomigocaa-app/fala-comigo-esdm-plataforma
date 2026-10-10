import 'package:flutter/material.dart';

import 'beta_telemetry_service.dart';

class BetaTelemetryNavigatorObserver extends NavigatorObserver {
  static const _routeScreens = {
    '/login': 'login',
    '/coleta-escola': 'coleta_escola',
    '/painel-consentimento': 'painel_consentimento',
    '/metas-esdm': 'metas_esdm',
    '/esdm-dashboard': 'esdm_dashboard',
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _track(newRoute);
  }

  void _track(Route<dynamic> route) {
    final screen = _routeScreens[route.settings.name];
    if (screen != null) {
      BetaTelemetryService.track('screen_view', screen: screen);
    }
  }
}
