/// Ecran de restauration de compte - VERSION CORRIGEE
/// Correction audit 4.1.3 : Implemente le flux complet de restauration
///
/// AVANT : Contenait un TODO et Future.delayed(2s) + message "en cours de developpement"
/// APRES : Flux complet : verification -> recuperation fragments -> reconstruction -> re-enrolement
///
/// Emplacement : lib/screens/restore_account_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/zk_auth_client.dart';
import '../config/zkauth_config.dart';

class RestoreAccountScreen extends StatefulWidget {
  const RestoreAccountScreen({super.key});

  @override
  State<RestoreAccountScreen> createState() => _RestoreAccountScreenState();
}

class _RestoreAccountScreenState extends State<RestoreAccountScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isRestoring = false;
  String _statusMessage = '';
  int _currentStep = 0;
  bool _restoreSuccess = false;

  final LocalAuthentication _localAuth = LocalAuthentication();
  late ZKAuthClient _zkAuthClient;

  final List<String> _steps = [
    'Verification biometrique',
    'Verification des identifiants',
    'Recuperation Fragment A (Google Drive)',
    'Recuperation Fragment B (Serveur)',
    'Dechiffrement et reconstruction',
    'Generation nouvelle paire de cles',
    'Re-enrolement',
  ];

  @override
  void initState() {
    super.initState();
    _zkAuthClient = ZKAuthClient(baseUrl: ZKAuthConfig.baseUrl);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Verification biometrique avant restauration
  Future<bool> _authenticateBiometric() async {
    try {
      final bool canAuthenticate = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();

      if (!canAuthenticate) {
        // Fallback: pas de biometrie disponible, continuer quand meme
        return true;
      }

      return await _localAuth.authenticate(
        localizedReason:
            'Verification biometrique requise pour la restauration',
        options: const AuthenticationOptions(
          biometricOnly: false, // Permet PIN comme fallback
          stickyAuth: true,
        ),
      );
    } catch (e) {
      _updateStatus('Erreur biometrique: $e');
      return false;
    }
  }

  void _updateStatus(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  void _updateStep(int step) {
    setState(() {
      _currentStep = step;
    });
  }

  /// Lancer le processus de restauration complet
  Future<void> _performRestore() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isRestoring = true;
      _currentStep = 0;
      _restoreSuccess = false;
    });

    try {
      // Etape 0 : Verification biometrique
      _updateStep(0);
      _updateStatus('Verification biometrique en cours...');
      final bioAuth = await _authenticateBiometric();
      if (!bioAuth) {
        _updateStatus('Echec de la verification biometrique');
        setState(() => _isRestoring = false);
        return;
      }

      // Etape 1-6 : Deleguee au client ZK-AUTH
      _updateStep(1);
      _updateStatus('Verification des identifiants...');

      // Le client gere toutes les etapes internes
      final result = await _zkAuthClient.restore(
        _usernameController.text.trim(),
        _emailController.text.trim(),
      );

      if (result['success'] == true) {
        _updateStep(6);
        _updateStatus('Restauration reussie !');
        setState(() => _restoreSuccess = true);

        // Afficher un dialog de succes
        if (mounted) {
          _showSuccessDialog();
        }
      } else {
        _updateStatus(
            'Echec: ${result['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e) {
      _updateStatus('Erreur: $e');
    } finally {
      setState(() => _isRestoring = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Restauration reussie'),
          ],
        ),
        content: const Text(
          'Votre compte a ete restaure avec succes.\n\n'
          'Une nouvelle paire de cles a ete generee. '
          'Pensez a effectuer une nouvelle sauvegarde.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Naviguer vers l'ecran de connexion
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text('Se connecter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restauration de compte'),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              const Icon(
                Icons.restore,
                size: 64,
                color: Color(0xFFFF6B00),
              ),
              const SizedBox(height: 16),
              const Text(
                'Restaurer votre compte',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Entrez vos identifiants pour recuperer votre compte '
                'et generer une nouvelle paire de cles.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Username field
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Nom d\'utilisateur',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez entrer votre nom d\'utilisateur';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Email field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez entrer votre email';
                  }
                  if (!value.contains('@')) {
                    return 'Email invalide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Progress stepper (visible during restoration)
              if (_isRestoring || _restoreSuccess) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Progression :',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(_steps.length, (index) {
                        IconData icon;
                        Color color;
                        if (index < _currentStep) {
                          icon = Icons.check_circle;
                          color = Colors.green;
                        } else if (index == _currentStep && _isRestoring) {
                          icon = Icons.hourglass_top;
                          color = const Color(0xFFFF6B00);
                        } else {
                          icon = Icons.circle_outlined;
                          color = Colors.grey;
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(icon, size: 20, color: color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _steps[index],
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: index == _currentStep
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Status message
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _restoreSuccess
                        ? Colors.green.shade50
                        : (_isRestoring
                            ? Colors.blue.shade50
                            : Colors.red.shade50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _restoreSuccess
                          ? Colors.green.shade700
                          : (_isRestoring
                              ? Colors.blue.shade700
                              : Colors.red.shade700),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 24),

              // Restore button
              ElevatedButton(
                onPressed: _isRestoring ? null : _performRestore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B00),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isRestoring
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Restaurer mon compte',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
              ),

              const SizedBox(height: 24),

              // Info securite
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.security, color: Colors.blue),
                    SizedBox(height: 8),
                    Text(
                      'Processus securise',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Les fragments sont dechiffres localement sur votre appareil. '
                      'Une nouvelle paire de cles est generee pour remplacer l\'ancienne.',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
