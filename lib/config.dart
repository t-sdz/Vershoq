/// Configuration du serveur de notifications push.
///
/// Le serveur (server/valtown.ts) est déployé sur Val Town.
///  - [pushServerUrl] : l'URL du fichier HTTP du val « snapit-cron ».
///  - [pushSecret]    : LA MÊME valeur que la variable d'environnement
///                      PUSH_SECRET définie sur Val Town.
///
/// Tant que pushServerUrl est vide, l'app retombe sur les notifications
/// locales (chaque téléphone gère les siennes).
class AppConfig {
  static const String pushServerUrl =
      'https://jeanne1--0e6a2956bd6611f1a70f1607ee4eb77e.web.val.run';
  static const String pushSecret = 'snapit-secret-2026';

  static bool get pushEnabled => pushServerUrl.isNotEmpty;
}
