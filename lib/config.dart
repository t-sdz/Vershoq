/// Configuration du serveur de notifications push.
///
/// Après avoir déployé le serveur (server/push.ts) sur Deno Deploy :
///  1. remplace [pushServerUrl] par l'URL de ton déploiement
///     (ex : https://snapit-push.deno.dev)
///  2. mets dans [pushSecret] LA MÊME valeur que la variable PUSH_SECRET
///     définie sur Deno Deploy.
///
/// Tant que pushServerUrl est vide, l'app retombe sur les notifications
/// locales (chaque téléphone gère les siennes).
class AppConfig {
  static const String pushServerUrl = '';
  static const String pushSecret = 'change-moi';

  static bool get pushEnabled => pushServerUrl.isNotEmpty;
}
