/// Utilitaire de logging structuré pour ZK-AUTH
/// Emplacement : zk_auth_sdk/lib/utils/zk_logger.dart
///
/// Usage :
///   ZKLogger.step(1, 'Challenge', 'Envoi requête GET');
///   ZKLogger.value('challenge', '3f8a...');
///   ZKLogger.success('Preuve ZK générée');
///   ZKLogger.error('Clé privée introuvable');

class ZKLogger {
  static const String _reset = '\x1B[0m';
  static const String _bold = '\x1B[1m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _blue = '\x1B[34m';
  static const String _cyan = '\x1B[36m';
  static const String _white = '\x1B[37m';
  static const String _gray = '\x1B[90m';

  // ─── Séparateurs ────────────────────────────────────────────────────────────

  static void banner(String title) {
    print('$_bold$_cyan');
    print('╔══════════════════════════════════════════════════════════╗');
    print('║  ZK-AUTH  ›  ${title.padRight(44)}║');
    print(
        '╚══════════════════════════════════════════════════════════╝$_reset');
  }

  static void divider() {
    print(
        '$_gray──────────────────────────────────────────────────────────$_reset');
  }

  // ─── Étape numérotée ────────────────────────────────────────────────────────

  static void step(int n, String label, [String? detail]) {
    final d = detail != null ? '  $_gray$detail$_reset' : '';
    print('$_bold$_blue  ÉTAPE $n │$_reset $_white$label$_reset$d');
  }

  // ─── Valeurs ────────────────────────────────────────────────────────────────

  static void value(String key, String value, {bool truncate = true}) {
    final v =
        truncate && value.length > 60 ? '${value.substring(0, 60)}…' : value;
    print('$_gray   ├ $key:$_reset $_yellow$v$_reset');
  }

  static void valueShort(String key, String value) =>
      print('$_gray   ├ $key:$_reset $_yellow$value$_reset');

  static void valueFull(String key, String value) {
    print('$_gray   ├ $key:$_reset');
    print('$_yellow     $value$_reset');
  }

  // ─── Statuts ────────────────────────────────────────────────────────────────

  static void success(String message) => print('$_green  *  $message$_reset');

  static void warning(String message) => print('$_yellow  *  $message$_reset');

  static void error(String message) => print('$_red  *  $message$_reset');

  static void info(String message) => print('$_cyan  * $message$_reset');

  // ─── HTTP ───────────────────────────────────────────────────────────────────

  static void request(String method, String url) =>
      print('$_bold$_blue  → HTTP $method$_reset  $_gray$url$_reset');

  static void response(int status, [String? preview]) {
    final color = status >= 200 && status < 300 ? _green : _red;
    final p = preview != null
        ? '  $_gray${preview.length > 80 ? preview.substring(0, 80) + '…' : preview}$_reset'
        : '';
    print('$color  ← HTTP $status$_reset$p');
  }

  // ─── Crypto détaillé ────────────────────────────────────────────────────────

  static void cryptoBlock({
    required String challenge,
    required String r,
    required String s,
    String? e,
  }) {
    divider();
    print('$_bold  **** PROTOCOLE SCHNORR (secp256k1)$_reset');
    divider();
    print('$_gray  │  k      → nonce aléatoire (jamais affiché)');
    print('  │  R = k·G (commitment point)$_reset');
    value('R (hex)', r);
    print('$_gray  │  e = SHA256(R ‖ challenge)$_reset');
    value('challenge', challenge);
    if (e != null) value('e (hash)', e);
    print('$_gray  │  s = k + e·privKey  (mod n)$_reset');
    value('s (hex)', s);
    divider();
  }

  // ─── Résultat final ─────────────────────────────────────────────────────────

  static void authResult({
    required bool success,
    String? token,
    String? error,
    int? httpStatus,
  }) {
    divider();
    if (success) {
      print('$_bold$_green  ***  AUTHENTIFICATION RÉUSSIE$_reset');
      if (token != null) value('token (aperçu)', token);
      if (httpStatus != null) valueShort('HTTP status', httpStatus.toString());
    } else {
      print('$_bold$_red  ***  AUTHENTIFICATION ÉCHOUÉE$_reset');
      if (error != null) print('$_red   └─ $error$_reset');
      if (httpStatus != null) valueShort('HTTP status', httpStatus.toString());
    }
    divider();
  }
}
