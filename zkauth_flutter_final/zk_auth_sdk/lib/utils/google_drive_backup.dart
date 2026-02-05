import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleDriveBackup {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  /// Sauvegarder fragment sur Google Drive
  Future<String?> saveFragment({
    required String username,
    required String fragment,
    required String fragmentType,
  }) async {
    try {
      // Connexion Google
      final account = await _googleSignIn.signIn();
      if (account == null) {
        print('Connexion Google annulée');
        return null;
      }

      final authHeaders = await account.authHeaders;
      final authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // Créer fichier
      final fileName = 'zkauth_fragment_${fragmentType}_$username.txt';
      final fileContent = '''
═══════════════════════════════════════
ZK-AUTH - Fragment $fragmentType
Utilisateur: $username
Date: ${DateTime.now()}
═══════════════════════════════════════

ATTENTION:
- Fragment $fragmentType de votre clé ZK-AUTH
- Nécessite Fragment ${fragmentType == 'A' ? 'B' : 'A'} pour restaurer
- Ne partagez jamais ce fichier

FRAGMENT $fragmentType:
$fragment
''';

      final driveFile = drive.File();
      driveFile.name = fileName;
      driveFile.mimeType = 'text/plain';

      final media = drive.Media(
        Stream.value(fileContent.codeUnits),
        fileContent.length,
      );

      final response = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
      );

      print('Fragment $fragmentType → Google Drive');
      return response.id;
    } catch (e) {
      print('Erreur Google Drive: $e');
      return null;
    }
  }

  /// Récupérer fragment depuis Google Drive
  Future<String?> getFragment({
    required String username,
    required String fragmentType,
  }) async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return null;

      final authHeaders = await account.authHeaders;
      final authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      final fileName = 'zkauth_fragment_${fragmentType}_$username.txt';
      final fileList = await driveApi.files.list(
        q: "name='$fileName'",
        spaces: 'drive',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        return null;
      }

      final fileId = fileList.files!.first.id!;
      final file = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final buffer = StringBuffer();
      await for (final chunk in file.stream) {
        buffer.write(String.fromCharCodes(chunk));
      }

      final content = buffer.toString();
      final fragmentStart = content.indexOf('FRAGMENT $fragmentType:') +
          'FRAGMENT $fragmentType:'.length;
      final fragment = content.substring(fragmentStart).trim();

      print('Fragment $fragmentType récupéré de Drive');
      return fragment;
    } catch (e) {
      print('Erreur récupération: $e');
      return null;
    }
  }

  /// Déconnexion
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
