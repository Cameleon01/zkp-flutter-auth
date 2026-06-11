import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart';
import 'register_screen.dart';
import 'home_screen.dart';
import 'restore_screen.dart';

// ─── Logger inline (pas besoin d'import externe) ──────────────────────────────
class _L {
  static void banner(String t) {
    print('\n\x1B[1m\x1B[36m╔══════════════════════════════════════════════════╗');
    print('║  ZK-AUTH  ›  ${t.padRight(36)}║');
    print('╚══════════════════════════════════════════════════╝\x1B[0m');
  }
  static void step(int n, String label) =>
      print('\x1B[1m\x1B[34m  [$n] $label\x1B[0m');
  static void val(String k, String v) =>
      print('\x1B[90m   ├ $k:\x1B[0m \x1B[33m${v.length > 70 ? '${v.substring(0, 70)}…' : v}\x1B[0m');
  static void ok(String m) =>
      print('\x1B[32m    $m\x1B[0m');
  static void warn(String m) =>
      print('\x1B[33m   $m\x1B[0m');
  static void err(String m) =>
      print('\x1B[31m    $m\x1B[0m');
  static void div() =>
      print('\x1B[90m  ──────────────────────────────────────────────────\x1B[0m');
}
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isLoading = false;
  String? _errorMessage;
  bool _biometricsAvailable = false;
  bool _biometricsChecked = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  //  Vérification biométrie disponible 
  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      setState(() {
        _biometricsAvailable = canCheck && isSupported;
        _biometricsChecked = true;
      });

      print('[ZK-AUTH] Biométrie disponible: $_biometricsAvailable');

      if (_biometricsAvailable) {
        final types = await _localAuth.getAvailableBiometrics();
        print('[ZK-AUTH] Types biométrie: $types');
      }
    } on PlatformException catch (e) {
      print('[ZK-AUTH] Erreur vérif biométrie: ${e.code} - ${e.message}');
      setState(() {
        _biometricsAvailable = false;
        _biometricsChecked = true;
      });
    }
  }

  //  CONNEXION PRINCIPALE 
  Future<void> _login() async {
    final username = _usernameController.text.trim();

    _L.banner('LOGIN  ›  $username');

    //  Validation 
    _L.step(0, 'Validation saisie');
    if (username.isEmpty) {
      _L.err('Username vide');
      setState(() => _errorMessage = 'Veuillez entrer votre nom d\'utilisateur');
      return;
    }
    _L.ok('Username : "$username"');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      //  ÉTAPE 1 : Biométrie locale 
      _L.step(1, 'Authentification biométrique (locale, Android Keystore)');
      _L.val('biometricsAvailable', _biometricsAvailable.toString());

      if (_biometricsAvailable) {
        _L.val('action', 'Demande empreinte / Face ID en cours…');

        bool authenticated = false;
        try {
          authenticated = await _localAuth.authenticate(
            localizedReason: 'Authentifiez-vous pour accéder à MyMomo',
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: false,
              useErrorDialogs: true,
              sensitiveTransaction: false,
            ),
          );
        } on PlatformException catch (e) {
          _L.err('Erreur biométrie: ${e.code} — ${e.message}');

          if (e.code == 'NotAvailable') {
            setState(() => _errorMessage =
                'Biométrie non disponible. Activez Touch ID/Face ID dans les paramètres.');
          } else if (e.code == 'NotEnrolled') {
            setState(() => _errorMessage =
                'Aucune biométrie enregistrée sur cet appareil.');
          } else if (e.code == 'LockedOut') {
            setState(() => _errorMessage =
                'Trop de tentatives. Réessayez dans 30 secondes.');
          } else {
            setState(() => _errorMessage = 'Erreur biométrie: ${e.message}');
          }

          setState(() => _isLoading = false);
          return;
        }

        _L.val('authenticated', authenticated.toString());

        if (!authenticated) {
          _L.err('Biométrie annulée ou refusée');
          setState(() {
            _errorMessage = 'Authentification biométrique annulée';
            _isLoading = false;
          });
          return;
        }

        _L.ok('Biométrie validée ✓');

      } else {
        _L.warn('Biométrie non disponible → passage direct au ZKP');
      }

      //  ÉTAPE 2 : Authentification Zero-Knowledge (Schnorr) 
      _L.div();
      _L.step(2, 'Authentification Zero-Knowledge — Protocole Schnorr/secp256k1');
      _L.val('méthode', 'zkAuthClient.authenticate("$username")');
      _L.val('protocole', 'k→R=k·G → e=SHA256(R‖challenge) → s=k+e·privKey');
      _L.div();

      final result = await zkAuthClient.authenticate(username);

      //  ÉTAPE 3 
      _L.div();
      _L.step(3, 'Résultat authentification');
      _L.val('success', result.success.toString());
      _L.val('message', result.message ?? result.error ?? '(vide)');

      if (result.success && mounted) {
        _L.ok('Connexion réussie → navigation vers HomeScreen');
        _L.div();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        _L.err('Connexion échouée : ${result.error}');
        _L.div();
        setState(() {
          _errorMessage = result.error ?? 'Échec authentification';
        });
      }

    } catch (e, stack) {
      _L.err('EXCEPTION inattendue : $e');
      print('\x1B[31m$stack\x1B[0m');
      setState(() {
        _errorMessage = 'Erreur: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Center(
                    child: Text(
                      'M',
                      style: TextStyle(
                        fontSize: 50,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                const Text(
                  'MyMomo',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B00),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Authentification Zero-Knowledge',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Champ username
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom d\'utilisateur',
                    prefixIcon: Icon(Icons.person),
                  ),
                  enabled: !_isLoading,
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),

                // Message d'erreur
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),

                // Bouton connexion
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _login,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(
                          _biometricsAvailable
                              ? Icons.fingerprint
                              : Icons.login,
                        ),
                  label: Text(
                    _biometricsAvailable
                        ? 'Se connecter avec biométrie'
                        : 'Se connecter',
                  ),
                ),
                const SizedBox(height: 16),

                // Bouton restaurer
                OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RestoreScreen(),
                            ),
                          ),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restaurer mon compte'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Bouton inscription
                OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Créer un compte'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
