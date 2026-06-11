import 'package:flutter/material.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart'; // Pour zkAuthClient global

class BackupScreen extends StatefulWidget {
  final String username;

  const BackupScreen({Key? key, required this.username}) : super(key: key);

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isBackingUp = false;
  bool _backupComplete = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    // CORRECTION bug 7 : Vérifier que le username n'est pas vide
    if (widget.username.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _errorMessage = 'Username manquant. Retournez à l\'écran principal.';
        });
      });
    }
  }

  /// Lancer la sauvegarde via le SDK (fragmentation XOR + chiffrement AES-256-GCM)
  Future<void> _performBackup() async {
    if (widget.username.isEmpty) {
      setState(() {
        _errorMessage = 'Username manquant';
      });
      return;
    }

    setState(() {
      _isBackingUp = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      print(' [BackupScreen] Début sauvegarde sécurisée: ${widget.username}');

      final result = await zkAuthClient.backupToGoogleDrive(widget.username);

      if (result.success) {
        setState(() {
          _backupComplete = true;
          _isBackingUp = false;
          _successMessage = result.message;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Sauvegarde sécurisée réussie !'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Erreur inconnue';
          _isBackingUp = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isBackingUp = false;
      });
    }
  }

  /// Retour vers l'écran de login en effaçant toute la pile de navigation
  void _goToLogin() {
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login', // Adapter si ta route login est '/' ou autre
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sauvegarde securisee'),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        // Masquer la flèche retour de l'AppBar après succès
        automaticallyImplyLeading: !_backupComplete,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header - icône change selon l'état
            Icon(
              _backupComplete ? Icons.cloud_done : Icons.cloud_upload,
              size: 64,
              color: _backupComplete ? Colors.green : const Color(0xFFFF6B00),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sauvegarder vos cles',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Utilisateur : ${widget.username}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Info sécurité - Fragmentation XOR
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Column(
                children: [
                  Icon(Icons.security, color: Colors.blue, size: 32),
                  SizedBox(height: 8),
                  Text(
                    'Fragmentation cryptographique XOR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Votre cle privee est divisee en deux fragments par '
                    'operation XOR. Chaque fragment est chiffre avec AES-256-'
                    'GCM avant envoi. Un seul fragment est inutile sans l\'autre.',
                    style: TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Message d'erreur
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Erreur: $_errorMessage',
                  style: TextStyle(color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
              ),

            // =========================================================
            // BOUTONS — logique conditionnelle selon _backupComplete
            // =========================================================
            if (_backupComplete) ...[
              // ✅ SUCCÈS : Afficher le résumé de succès + bouton Retour SEULEMENT
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sauvegarde réussie !',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 16,
                      ),
                    ),
                    if (_successMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _successMessage!,
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Fragment A chiffré → Google Drive\n'
                      'Fragment B chiffré → Serveur\n'
                      '(Fragmentation XOR + AES-256-GCM)',
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Seul bouton visible après succès → Retour vers Login
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _goToLogin,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFFFF6B00),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Retour',
                    style: TextStyle(color: Color(0xFFFF6B00), fontSize: 16),
                  ),
                ),
              ),
            ] else ...[
              // ⏳ PAS ENCORE SAUVEGARDÉ : bouton Lancer + bouton Retour (pop)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (_isBackingUp || widget.username.isEmpty)
                      ? null
                      : _performBackup,
                  icon: _isBackingUp
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload, color: Colors.white),
                  label: Text(
                    _isBackingUp
                        ? 'Sauvegarde en cours...'
                        : 'Lancer la sauvegarde',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isBackingUp ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFFFF6B00),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Retour',
                    style: TextStyle(color: Color(0xFFFF6B00), fontSize: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
