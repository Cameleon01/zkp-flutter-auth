/* import 'package:flutter/material.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class BackupScreen extends StatefulWidget {
  final String username;

  const BackupScreen({Key? key, required this.username}) : super(key: key);

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final ZKAuthClient _zkAuthClient = ZKAuthClient(
    baseUrl: 'http://10.64.10.211:8000',
    //baseUrl: 'http://192.168.100.6:8000', //
    // baseUrl: 'http://172.25.215.80:8000', //
  );

  bool _isBackingUp = false;
  bool _backupComplete = false;
  String? _errorMessage;

  /// Fonction principale de sauvegarde
  Future<void> _performBackup() async {
    setState(() {
      _isBackingUp = true;
      _errorMessage = null;
    });

    try {
      print('Début sauvegarde: ${widget.username}');

      // 1. Récupérer la Clé privée
      final privateKeyHex = await _zkAuthClient.getPrivateKey(widget.username);

      if (privateKeyHex == null) {
        throw Exception('Clé privée introuvable');
      }

      // 2. Fragmenter en 2 parties
      final fragments = _splitKey(privateKeyHex);
      final fragmentA = fragments['fragmentA']!;
      final fragmentB = fragments['fragmentB']!;

      print('Clé fragmenté');

      // 3. Envoyer fragment A par email
      await _sendFragmentByEmail(fragmentA, widget.username);
      print('Envoie fragment A Email');

      // 4. Envoyer fragment B au cloud
      await _sendFragmentToCloud(fragmentB, widget.username);
      print('Envoie fragment B Cloud');

      // 5. SuccÃ¨s
      setState(() {
        _backupComplete = true;
        _isBackingUp = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(' Sauvegarde réussie !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isBackingUp = false;
      });
    }
  }

  /// Fragmente la Clé en 2 parties
  Map<String, String> _splitKey(String key) {
    final mid = (key.length / 2).ceil();
    return {
      'fragmentA': key.substring(0, mid),
      'fragmentB': key.substring(mid),
    };
  }

  /// Envoie fragment A par email
  Future<void> _sendFragmentByEmail(String fragment, String username) async {
    final subject = Uri.encodeComponent('ZK-AUTH - Fragment A');
    final body = Uri.encodeComponent(
      'Votre fragment A de clé ZK-AUTH:\n\n'
      '$fragment\n\n'
      'Utilisateur: $username\n'
      'Conservez ce fragment en sécurité.',
    );

    final mailtoUrl = 'mailto:?subject=$subject&body=$body';
    final uri = Uri.parse(mailtoUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw Exception('Impossible d\'ouvrir l\'email');
    }
  }

  /// Envoie fragment B au cloud ZK-AUTH
  Future<void> _sendFragmentToCloud(String fragment, String username) async {
    final response = await http.post(
      Uri.parse('${_zkAuthClient.baseUrl}/api/auth/backup-fragment/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': username,
        'fragment': fragment,
        'fragment_type': 'B',
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(' sauvegarde cloud: ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Sauvegarde de la Clé'),
        backgroundColor: Colors.orange,
        automaticallyImplyLeading: !_isBackingUp && !_backupComplete,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // IcÃ´ne
              Icon(
                _backupComplete ? Icons.cloud_done : Icons.cloud_upload,
                size: 100,
                color: _backupComplete ? Colors.green : Colors.blue,
              ),

              const SizedBox(height: 32),

              // Titre
              Text(
                _backupComplete
                    ? 'Sauvegarde réussie !'
                    : 'Sauvegarde Sécurisée',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Contenu
              if (!_backupComplete) ...[
                const Text(
                  'Votre Clé de restauration sera fragmentée et chiffrée en deux parties :',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Fragment A Google Drive',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Fragment B Cloud privé ZK-AUTH',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Aucun des deux fragments ne suffit seul pour restaurer votre compte.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ] else ...[
                const Text(
                  'Votre Clé a été sauvegardée avec succè !',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green, size: 32),
                      SizedBox(height: 12),
                      Text(
                        'Fragment A envoyé par email\n'
                        'Fragment B sauvegardé sur cloud',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Erreur
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),

              // Boutons
              if (!_backupComplete) ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isBackingUp ? null : _performBackup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isBackingUp
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Lancer la sauvegarde',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/login', (route) => false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Retour au Login',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
 */

import 'package:flutter/material.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart';

class BackupScreen extends StatefulWidget {
  final String username;

  const BackupScreen({Key? key, required this.username}) : super(key: key);

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final ZKAuthClient _zkAuthClient = ZKAuthClient(
    baseUrl: 'http://10.64.10.211:8000',
    // baseUrl: 'http://192.168.100.6:8000',
    //baseUrl: 'http://172.25.215.80:8000', //
  );

  bool _isBackingUp = false;
  bool _backupComplete = false;
  String? _errorMessage;
  String? _driveFileId;

  /// Fonction principale de sauvegarde avec Google Drive
  Future<void> _performBackup() async {
    setState(() {
      _isBackingUp = true;
      _errorMessage = null;
      _backupComplete = false;
    });

    try {
      print('[BACKUP] Début sauvegarde pour: ${widget.username}');

      // Utiliser la méthode backupToGoogleDrive du client ZK-AUTH
      final result = await _zkAuthClient.backupToGoogleDrive(widget.username);

      if (result.success) {
        setState(() {
          _backupComplete = true;
          _isBackingUp = false;
          _driveFileId = result.driveFileId;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message ?? 'Sauvegarde réussie'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(result.error ?? 'Échec de la sauvegarde');
      }
    } catch (e) {
      print('[BACKUP] Erreur: $e');
      setState(() {
        _errorMessage = e.toString();
        _isBackingUp = false;
        _backupComplete = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sauvegarde sécurisée'),
        backgroundColor: const Color(0xFFFF6B00),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Icône
              Icon(
                _backupComplete ? Icons.cloud_done : Icons.cloud_upload,
                size: 100,
                color: _backupComplete ? Colors.green : const Color(0xFFFF6B00),
              ),

              const SizedBox(height: 32),

              // Titre
              Text(
                _backupComplete
                    ? 'Sauvegarde réussie !'
                    : 'Sauvegarde Sécurisée',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Contenu
              if (!_backupComplete) ...[
                const Text(
                  'Votre clé sera fragmentée et chiffrée en deux parties :',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.cloud, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Fragment A → Google Drive',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.cloud_circle,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Fragment B → Cloud privé ZK-AUTH',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange[800]),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Aucun des deux fragments ne suffit seul pour restaurer votre compte.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const Text(
                  'Votre clé a été sauvegardée avec succès !',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Fragment A sauvegardé sur Google Drive',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: const [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Fragment B sauvegardé sur le serveur',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      if (_driveFileId != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'ID Drive: ${_driveFileId!.substring(0, 20)}...',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Message d'erreur
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),

              // Bouton de sauvegarde
              if (!_backupComplete)
                ElevatedButton(
                  onPressed: _isBackingUp ? null : _performBackup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B00),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isBackingUp
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Sauvegarder maintenant',
                          style: TextStyle(fontSize: 16),
                        ),
                )
              else
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/',
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Retour à l\'accueil',
                    style: TextStyle(fontSize: 16),
                  ),
                ),

              const SizedBox(height: 16),

              // Instructions
              if (!_backupComplete)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Processus de sauvegarde :',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. Vérification biométrique',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '2. Fragmentation de la clé',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '3. Connexion à Google Drive',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '4. Sauvegarde des fragments',
                        style: TextStyle(fontSize: 12),
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
