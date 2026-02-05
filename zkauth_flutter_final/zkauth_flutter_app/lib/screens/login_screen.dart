import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart';
import 'register_screen.dart';
import 'home_screen.dart';

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

  //  VÉRIFIER SI BIOMÉTRIE DISPONIBLE
  Future<void> _checkBiometrics() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      setState(() {
        _biometricsAvailable = canCheckBiometrics && isDeviceSupported;
        _biometricsChecked = true;
      });

      print(' Biométrie disponible: $_biometricsAvailable');

      if (_biometricsAvailable) {
        final availableBiometrics = await _localAuth.getAvailableBiometrics();
        print(' Types: $availableBiometrics');
      }
    } on PlatformException catch (e) {
      print('❌ Erreur: ${e.code} - ${e.message}');
      setState(() {
        _biometricsAvailable = false;
        _biometricsChecked = true;
      });
    } catch (e) {
      print('❌ Erreur: $e');
      setState(() {
        _biometricsAvailable = false;
        _biometricsChecked = true;
      });
    }
  }

  //  CONNEXION AVEC BIOMÉTRIE
  Future<void> _login() async {
    final username = _usernameController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Veuillez entrer votre nom d\'utilisateur';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      //  ÉTAPE 1 : Authentification biométrique LOCALE
      if (_biometricsAvailable) {
        print('🔐 Demande biométrie...');

        bool authenticated = false;
        try {
          authenticated = await _localAuth.authenticate(
            localizedReason: 'Authentifiez-vous pour accéder à MyMomo',
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: false, //  Permet PIN en fallback
              useErrorDialogs: true,
              sensitiveTransaction: false,
            ),
          );
        } on PlatformException catch (e) {
          print('❌ Erreur biométrie: ${e.code}');

          // Gestion des erreurs spécifiques
          if (e.code == 'NotAvailable') {
            setState(() {
              _errorMessage =
                  'Biométrie non disponible. Activez Touch ID/Face ID dans les paramètres.';
            });
          } else if (e.code == 'NotEnrolled') {
            setState(() {
              _errorMessage = 'Aucune biométrie enregistrée sur cet appareil.';
            });
          } else if (e.code == 'LockedOut') {
            setState(() {
              _errorMessage = 'Trop de tentatives. Réessayez dans 30 secondes.';
            });
          } else {
            setState(() {
              _errorMessage = 'Erreur biométrie: ${e.message}';
            });
          }

          setState(() => _isLoading = false);
          return;
        }

        if (!authenticated) {
          setState(() {
            _errorMessage = 'Authentification biométrique annulée';
            _isLoading = false;
          });
          return;
        }

        print(' Biométrie OK');
      } else {
        print('⚠️ Connexion sans biométrie (non disponible)');
      }

      //  ÉTAPE 2 : Authentification Zero-Knowledge
      print('🚀 Auth ZK: $username');

      final result = await zkAuthClient.authenticate(username);

      if (result.success && mounted) {
        print(' Connexion réussie!');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Échec authentification';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

                // Username
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

                // Error
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

                // Login button
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _login,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
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

                // Register
                OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        ),
                  child: const Text('Créer un compte'),
                ),
                const SizedBox(height: 32),

                // Info sécurité
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.security, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Votre clé privée ne quitte jamais votre appareil',
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Statut biométrie
                if (_biometricsChecked) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _biometricsAvailable
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _biometricsAvailable
                              ? Icons.check_circle
                              : Icons.warning,
                          color: _biometricsAvailable
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _biometricsAvailable
                                ? 'Biométrie disponible '
                                : 'Biométrie non disponible. Connexion sans biométrie.',
                            style: TextStyle(
                              color: _biometricsAvailable
                                  ? Colors.green.shade900
                                  : Colors.orange.shade900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
