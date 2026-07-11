/// Configuration du serveur de notifications push.
///
/// Le serveur (server/valtown.ts) est déployé sur Val Town.
///  - [pushServerUrl] : l'URL du val HTTP « verchoqs ».
///  - [pushSecret]    : LA MÊME valeur que la variable d'environnement
///                      PUSH_SECRET définie sur Val Town.
///
/// Tant que pushServerUrl est vide, l'app retombe sur les notifications
/// locales (chaque téléphone gère les siennes).
class AppConfig {
  static const String pushServerUrl =
      'https://tsdz--3b85cdc87c7a11f1853f1607ee4eb77e.web.val.run';
  static const String pushSecret = 'snapit-secret-2026';

  static bool get pushEnabled => pushServerUrl.isNotEmpty;
}
