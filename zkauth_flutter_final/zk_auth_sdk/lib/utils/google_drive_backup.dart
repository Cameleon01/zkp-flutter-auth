import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Client HTTP personnalisé pour Google Drive API
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

/// Service de sauvegarde et restauration sur Google Drive
class GoogleDriveBackup {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  /// Sauvegarder un fragment sur Google Drive
  Future<String?> saveFragment({
    required String username,
    required String fragment,
    required String fragmentType,
  }) async {
    try {
      print('[DRIVE] Début sauvegarde fragment $fragmentType pour $username');

      // 1. Connexion Google

      //  AJOUT : Forcer déconnexion puis reconnexion
      await _googleSignIn.signOut();

      // Sign in (redemande le compte à chaque fois)
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      //final account = await _googleSignIn.signIn();
      if (account == null) {
        print('[DRIVE] Connexion Google annulée');
        return null;
      }

      print('[DRIVE] Compte connecté: ${account.email}');

      // 2. Obtenir les headers d'authentification
      final authHeaders = await account.authHeaders;
      final authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 3. Vérifier si un fichier existe déjà
      final fileName = 'zkauth_fragment_${fragmentType}_$username.enc';
      final existingFiles = await driveApi.files.list(
        q: "name='$fileName' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      // 4. Supprimer l'ancien fichier s'il existe
      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        for (var file in existingFiles.files!) {
          await driveApi.files.delete(file.id!);
          print('[DRIVE] Ancien fichier supprimé: ${file.id}');
        }
      }

      // 5. Créer le contenu du fichier
      final timestamp = DateTime.now().toIso8601String();
      final fileContent = jsonEncode({
        'version': '1.0',
        'app': 'ZK-AUTH',
        'username': username,
        'fragment_type': fragmentType,
        'timestamp': timestamp,
        'fragment': fragment,
        'checksum': _calculateChecksum(fragment),
      });

      // 6. Créer le fichier sur Drive
      final driveFile = drive.File();
      driveFile.name = fileName;
      driveFile.mimeType = 'application/json';
      driveFile.description = 'ZK-AUTH Fragment $fragmentType';

      final media = drive.Media(
        Stream.value(utf8.encode(fileContent)),
        fileContent.length,
      );

      final response = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
      );

      print('[DRIVE] Fragment $fragmentType sauvegardé: ${response.id}');

      return response.id;
    } catch (e) {
      print('[DRIVE] Erreur sauvegarde: $e');
      return null;
    }
  }

  /// Récupérer un fragment depuis Google Drive
  Future<String?> getFragment({
    required String username,
    required String fragmentType,
  }) async {
    try {
      print('[DRIVE] Récupération fragment $fragmentType pour $username');

      // 1. Connexion Google
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account == null) {
        print('[DRIVE] Connexion annulée');
        return null;
      }

      // 2. Obtenir les headers d'authentification
      final authHeaders = await account.authHeaders;
      final authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 3. Rechercher le fichier
      final fileName = 'zkauth_fragment_${fragmentType}_$username.enc';
      final fileList = await driveApi.files.list(
        q: "name='$fileName' and trashed=false",
        spaces: 'drive',
        orderBy: 'createdTime desc',
        $fields: 'files(id, name)',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        print('[DRIVE] Fragment non trouvé');
        return null;
      }

      final fileId = fileList.files!.first.id!;
      print('[DRIVE] Fichier trouvé: $fileId');

      // 4. Télécharger le contenu
      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final dataStream = <int>[];
      await for (var chunk in media.stream) {
        dataStream.addAll(chunk);
      }

      final fileContent = utf8.decode(dataStream);
      final data = jsonDecode(fileContent);

      // 5. Vérifier l'intégrité
      final fragment = data['fragment'] as String;
      final storedChecksum = data['checksum'] as String?;

      if (storedChecksum != null) {
        final calculatedChecksum = _calculateChecksum(fragment);
        if (calculatedChecksum != storedChecksum) {
          print('[DRIVE] Erreur: Checksum invalide');
          return null;
        }
      }

      print('[DRIVE] Fragment $fragmentType récupéré avec succès');
      return fragment;
    } catch (e) {
      print('[DRIVE] Erreur récupération: $e');
      return null;
    }
  }

  /// Supprimer un fragment de Google Drive
  Future<bool> deleteFragment({
    required String username,
    required String fragmentType,
  }) async {
    try {
      print('[DRIVE] Suppression fragment $fragmentType');

      final account = await _googleSignIn.signIn();
      if (account == null) return false;

      final authHeaders = await account.authHeaders;
      final authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      final fileName = 'zkauth_fragment_${fragmentType}_$username.enc';
      final fileList = await driveApi.files.list(
        q: "name='$fileName' and trashed=false",
        spaces: 'drive',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        print('[DRIVE] Aucun fichier à supprimer');
        return true;
      }

      for (var file in fileList.files!) {
        await driveApi.files.delete(file.id!);
        print('[DRIVE] Fichier supprimé: ${file.id}');
      }

      return true;
    } catch (e) {
      print('[DRIVE] Erreur suppression: $e');
      return false;
    }
  }

  /// Vérifier si un fragment existe
  Future<bool> fragmentExists({
    required String username,
    required String fragmentType,
  }) async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false;

      final authHeaders = await account.authHeaders;
      final authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      final fileName = 'zkauth_fragment_${fragmentType}_$username.enc';
      final fileList = await driveApi.files.list(
        q: "name='$fileName' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );

      return fileList.files != null && fileList.files!.isNotEmpty;
    } catch (e) {
      print('[DRIVE] Erreur vérification: $e');
      return false;
    }
  }

  /// Calculer un checksum simple
  String _calculateChecksum(String data) {
    int hash = 0;
    for (int i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash) + data.codeUnitAt(i);
      hash = hash & hash;
    }
    return hash.abs().toString();
  }

  /// Déconnecter le compte Google
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  /// Obtenir le compte Google actuel
  Future<GoogleSignInAccount?> getCurrentAccount() async {
    return await _googleSignIn.signInSilently();
  }
}
