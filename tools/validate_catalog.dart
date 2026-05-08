import "dart:convert";
import "dart:io";

/// 生成済み assets/tracks.json の簡易検証（件数・重複・artist null 等）
void main(List<String> args) async {
  final path = args.isNotEmpty ? args.first : "assets/tracks.json";
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln("File not found: $path");
    exitCode = 1;
    return;
  }

  final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final tracks = (map["tracks"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

  var nullArtist = 0;
  var nonPublicDomain = 0;
  var missingStreamUrl = 0;
  final seenUrls = <String>{};
  var duplicateUrlOccurrences = 0;

  for (final t in tracks) {
    if (t["artist"] == null) nullArtist++;
    final rights = t["rights"] as Map<String, dynamic>?;
    final status = rights?["rightsStatus"] as String? ?? "";
    if (status != "public_domain") nonPublicDomain++;

    final audio = t["audio"] as Map<String, dynamic>?;
    final urlRaw = audio?["streamUrl"] as String?;
    final url = urlRaw?.trim().toLowerCase() ?? "";
    if (url.isEmpty) {
      missingStreamUrl++;
      continue;
    }
    if (!seenUrls.add(url)) duplicateUrlOccurrences++;
  }

  stdout.writeln("catalogVersion: ${map["catalogVersion"]}");
  stdout.writeln("generatedAt: ${map["generatedAt"]}");
  stdout.writeln("tracks: ${tracks.length}");
  stdout.writeln("artist == null: $nullArtist");
  stdout.writeln("missing streamUrl: $missingStreamUrl");
  stdout.writeln("duplicate streamUrl rows (beyond first occurrence): $duplicateUrlOccurrences");
  stdout.writeln("rightsStatus != public_domain: $nonPublicDomain");
}
