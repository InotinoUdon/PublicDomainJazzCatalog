import "dart:convert";
import "dart:io";

void main(List<String> args) async {
  final config = _Config.fromArgs(args);
  final client = HttpClient()..userAgent = "pub-dom-jazz-catalog-builder/0.1";

  try {
    stdout.writeln("Fetching metadata from ${config.metadataUrl}");
    final metadataJson = await _fetchJson(client, config.metadataUrl);
    dynamic manifestJson;
    if (config.manifestUrl != null) {
      try {
        stdout.writeln("Fetching manifest from ${config.manifestUrl}");
        manifestJson = await _fetchJson(client, config.manifestUrl!);
      } catch (e) {
        stdout.writeln("Manifest fetch failed. Continue with metadata-only mode: $e");
      }
    }

    final metadataRecords = _extractRecords(metadataJson);
    final manifestRecords =
        manifestJson == null ? <Map<String, dynamic>>[] : _extractRecords(manifestJson);
    if (config.debug) {
      stdout.writeln("Metadata records: ${metadataRecords.length}");
      stdout.writeln("Manifest records: ${manifestRecords.length}");
      _printRecordShape("metadata[0]", metadataRecords.isEmpty ? null : metadataRecords.first);
      _printRecordShape("manifest[0]", manifestRecords.isEmpty ? null : manifestRecords.first);
    }

    final audioByItemKey = <String, String>{};
    for (final record in manifestRecords) {
      final itemKey = _resolveItemKey(record);
      final audioUrl = _resolveAudioUrl(record);
      if (itemKey == null || audioUrl == null) {
        continue;
      }
      audioByItemKey.putIfAbsent(itemKey, () => audioUrl);
    }
    if (config.debug) {
      stdout.writeln("Manifest item/audio pairs: ${audioByItemKey.length}");
    }

    final tracks = <Map<String, dynamic>>[];
    var skippedNonJazz = 0;
    var skippedNoAudio = 0;
    var skippedDuplicate = 0;
    var skippedUnreachable = 0;
    var resolvedViaItemApi = 0;
    var debugPrintedMissingAudio = 0;
    var debugPrintedItemApiError = 0;
    final seenByAudioUrl = <String>{};
    final seenByTitleArtist = <String>{};
    for (final record in metadataRecords) {
      if (!_looksLikeJazz(record, config.queryTerms)) {
        skippedNonJazz += 1;
        continue;
      }
      final itemKey = _resolveItemKey(record);
      var audioUrl =
          (itemKey == null ? null : audioByItemKey[itemKey]) ?? _resolveAudioUrl(record);
      if (audioUrl == null && config.resolveWithItemApi) {
        audioUrl = await _resolveAudioFromItemApi(
          client,
          record,
          debug: config.debug,
          onError: (message) {
            if (debugPrintedItemApiError < 3) {
              debugPrintedItemApiError += 1;
              stdout.writeln("Item API fallback error: $message");
            }
          },
        );
        if (audioUrl != null) {
          resolvedViaItemApi += 1;
        }
      }
      if (audioUrl == null) {
        skippedNoAudio += 1;
        if (config.debug && debugPrintedMissingAudio < 3) {
          debugPrintedMissingAudio += 1;
          stdout.writeln("---- Missing audio debug sample #$debugPrintedMissingAudio ----");
          stdout.writeln("Id: ${_firstString(record, ["Id", "id", "url"])}");
          stdout.writeln("Title: ${_firstString(record, ["Title", "title", "item_title"])}");
          stdout.writeln("Preview_url: ${_valueByAnyKey(record, ["Preview_url", "preview_url"])}");
          stdout.writeln("Audio_type: ${_valueByAnyKey(record, ["Audio_type", "audio_type"])}");
          stdout.writeln("Mime_type: ${_valueByAnyKey(record, ["Mime_type", "mime_type"])}");
          final iiif = _firstString(record, ["IIIF_manifest", "iiif_manifest"]);
          stdout.writeln("IIIF_manifest: $iiif");
          stdout.writeln("IIIF derived: ${_audioUrlFromIiifManifest(record)}");
          final discovered = _firstAudioLikeUrl(record);
          stdout.writeln("firstAudioLikeUrl: $discovered");
        }
        continue;
      }

      final normalizedUrl = audioUrl.trim().toLowerCase();
      final normalizedTitleArtist = [
        (_firstString(record, ["title", "Title", "item_title"]) ?? "untitled")
            .trim()
            .toLowerCase(),
        (_extractArtist(record) ?? "").trim().toLowerCase(),
      ].join("::");
      if (seenByAudioUrl.contains(normalizedUrl) ||
          seenByTitleArtist.contains(normalizedTitleArtist)) {
        skippedDuplicate += 1;
        continue;
      }

      if (config.checkUrls) {
        final ok = await _isReachableAudioUrl(
          client,
          audioUrl,
          strict: config.strictUrlCheck,
          timeout: config.urlCheckTimeout,
        );
        if (!ok) {
          skippedUnreachable += 1;
          continue;
        }
      }

      tracks.add(_toTrack(record: record, audioUrl: audioUrl, index: tracks.length + 1));
      seenByAudioUrl.add(normalizedUrl);
      seenByTitleArtist.add(normalizedTitleArtist);
      if (config.maxTracks != null && tracks.length >= config.maxTracks!) {
        break;
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final output = {
      "catalogVersion": DateTime.now().toUtc().toIso8601String().split("T").first,
      "generatedAt": now,
      "tracks": tracks,
    };

    final encoder = const JsonEncoder.withIndent("  ");
    final outputJson = encoder.convert(output);
    if (config.dryRun) {
      stdout.writeln(outputJson);
      return;
    }

    final outFile = File(config.outputPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsString("$outputJson\n");

    stdout.writeln("Done.");
    stdout.writeln("Tracks written: ${tracks.length}");
    stdout.writeln("Skipped (non-jazz): $skippedNonJazz");
    stdout.writeln("Skipped (missing audio): $skippedNoAudio");
    stdout.writeln("Skipped (duplicate): $skippedDuplicate");
    if (config.checkUrls) {
      stdout.writeln("Skipped (unreachable url): $skippedUnreachable");
    }
    stdout.writeln("Resolved via item API: $resolvedViaItemApi");
    stdout.writeln("Output: ${outFile.path}");
  } finally {
    client.close(force: true);
  }
}

class _Config {
  final Uri metadataUrl;
  final Uri? manifestUrl;
  final String outputPath;
  final int? maxTracks;
  final bool dryRun;
  final bool resolveWithItemApi;
  final bool debug;
  final bool checkUrls;
  final bool strictUrlCheck;
  final Duration urlCheckTimeout;
  final List<String> queryTerms;

  _Config({
    required this.metadataUrl,
    required this.manifestUrl,
    required this.outputPath,
    required this.maxTracks,
    required this.dryRun,
    required this.resolveWithItemApi,
    required this.debug,
    required this.checkUrls,
    required this.strictUrlCheck,
    required this.urlCheckTimeout,
    required this.queryTerms,
  });

  factory _Config.fromArgs(List<String> args) {
    Uri metadataUrl = Uri.parse("https://data.labs.loc.gov/jukebox/metadata.json");
    Uri? manifestUrl = Uri.parse("https://data.labs.loc.gov/jukebox/manifest.json");
    var outputPath = "assets/tracks.json";
    int? maxTracks;
    var dryRun = false;
    var resolveWithItemApi = true;
    var debug = false;
    var checkUrls = false;
    var strictUrlCheck = false;
    var urlCheckTimeoutMs = 1500;
    var queryTerms = <String>[
      "jazz",
      "ragtime",
      "blues",
      "dixieland",
      "swing",
      "fox trot",
      "foxtrot",
      "one-step",
      "hot dance",
      "syncopation",
      "vocal chorus",
    ];

    for (final arg in args) {
      if (arg == "--dry-run") {
        dryRun = true;
      } else if (arg == "--no-item-api") {
        resolveWithItemApi = false;
      } else if (arg == "--debug") {
        debug = true;
      } else if (arg == "--check-urls") {
        checkUrls = true;
      } else if (arg == "--strict-url-check") {
        strictUrlCheck = true;
      } else if (arg.startsWith("--url-check-timeout-ms=")) {
        urlCheckTimeoutMs = int.tryParse(arg.split("=").last) ?? 1500;
      } else if (arg.startsWith("--metadata-url=")) {
        metadataUrl = Uri.parse(arg.split("=").last);
      } else if (arg.startsWith("--manifest-url=")) {
        final raw = arg.split("=").last.trim();
        manifestUrl = raw.toLowerCase() == "none" ? null : Uri.parse(raw);
      } else if (arg.startsWith("--output=")) {
        outputPath = arg.split("=").last;
      } else if (arg.startsWith("--max=")) {
        maxTracks = int.tryParse(arg.split("=").last);
      } else if (arg.startsWith("--query=")) {
        final raw = arg.split("=").last.trim().toLowerCase();
        if (raw == "none" || raw == "all" || raw.isEmpty) {
          queryTerms = const [];
        } else {
          queryTerms = raw
              .split(",")
              .map((e) => e.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
    }

    return _Config(
      metadataUrl: metadataUrl,
      manifestUrl: manifestUrl,
      outputPath: outputPath,
      maxTracks: maxTracks,
      dryRun: dryRun,
      resolveWithItemApi: resolveWithItemApi,
      debug: debug,
      checkUrls: checkUrls,
      strictUrlCheck: strictUrlCheck,
      urlCheckTimeout: Duration(milliseconds: urlCheckTimeoutMs.clamp(300, 15000)),
      queryTerms: queryTerms,
    );
  }
}

Future<dynamic> _fetchJson(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException("Failed to fetch $uri (status ${response.statusCode})");
  }
  return jsonDecode(body);
}

List<Map<String, dynamic>> _extractRecords(dynamic root) {
  if (root is List) {
    return root.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  if (root is Map<String, dynamic>) {
    const keys = ["records", "results", "items", "data", "files", "rows"];
    for (final key in keys) {
      final value = _valueByAnyKey(root, [key]);
      if (value is List) {
        return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    for (final value in root.values) {
      if (value is List) {
        return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    return [root];
  }
  throw FormatException("Unsupported JSON shape for records.");
}

String? _resolveItemKey(Map<String, dynamic> record) {
  final direct = _firstString(record, ["item_id", "id", "itemId", "item", "Id"]);
  if (direct != null) {
    return _normalizeItemKey(direct);
  }
  final nestedItem = record["item"];
  if (nestedItem is Map<String, dynamic>) {
    final nested = _firstString(nestedItem, ["id", "item_id", "url"]);
    if (nested != null) {
      return _normalizeItemKey(nested);
    }
  }
  return null;
}

String _normalizeItemKey(String raw) {
  final value = raw.trim();
  final match = RegExp(r"/item/([^/]+)/?").firstMatch(value);
  if (match != null) {
    return match.group(1)!;
  }
  return value.replaceAll(RegExp(r"^https?://"), "");
}

String? _resolveAudioUrl(Map<String, dynamic> record) {
  final direct = _firstString(
    record,
    [
      "url",
      "audio_url",
      "download",
      "href",
      "Preview_url",
      "preview_url",
      "Audio",
      "audio",
      "stream_url",
    ],
  );
  if (direct != null && _looksLikeAudioUrl(direct)) {
    return direct;
  }
  final resources = record["resources"];
  if (resources is List) {
    for (final resource in resources.whereType<Map>()) {
      final url = _firstString(resource.cast<String, dynamic>(), ["url", "download", "href"]);
      if (url != null && _looksLikeAudioUrl(url)) {
        return url;
      }
    }
  }
  final discovered = _firstAudioLikeUrl(record);
  if (discovered != null) {
    return discovered;
  }
  final iiifDerived = _audioUrlFromIiifManifest(record);
  if (iiifDerived != null) {
    return iiifDerived;
  }
  return null;
}

bool _looksLikeAudioUrl(String url) {
  final lower = url.toLowerCase();
  return lower.endsWith(".mp3") ||
      lower.endsWith(".wav") ||
      lower.contains(".mp3?") ||
      lower.contains(".wav?") ||
      lower.contains("/audio/") ||
      lower.contains("audio=");
}

bool _looksLikeJazz(Map<String, dynamic> record, List<String> queryTerms) {
  if (queryTerms.isEmpty) {
    return true;
  }
  final searchable = _jazzSearchText(record).toLowerCase();
  return queryTerms.any((term) => searchable.contains(term));
}

String _jazzSearchText(Map<String, dynamic> record) {
  final parts = <String>[];

  // Explicitly prioritize LOC-style metadata fields likely to describe genre.
  for (final key in [
    "Genre",
    "genre",
    "Subjects",
    "subjects",
    "Subject",
    "subject",
    "Description",
    "description",
    "Summary",
    "summary",
    "Title",
    "title",
  ]) {
    final value = _valueByAnyKey(record, [key]);
    if (value != null) {
      parts.add(_flattenText(value));
    }
  }

  // Keep a fallback to whole-record text so we still catch edge schemas.
  parts.add(_flattenText(record));
  return parts.join(" ");
}

Map<String, dynamic> _toTrack({
  required Map<String, dynamic> record,
  required String audioUrl,
  required int index,
}) {
  final title = _firstString(record, ["title", "item_title"]) ?? "Untitled";
  final artist = _extractArtist(record);
  final recordingDate =
      _firstString(record, ["date", "date_created", "recording_date", "created", "Date"]);
  final sourceItemUrl = _firstString(record, ["id", "url", "Id"]) ?? "https://www.loc.gov/";
  final tags = _extractTags(record);
  final now = DateTime.now().toUtc().toIso8601String();

  return {
    "id": "loc-jazz-${index.toString().padLeft(4, "0")}",
    "title": title,
    "artist": artist,
    "recordingDate": recordingDate,
    "durationSec": _firstInt(record, ["duration", "duration_sec", "duration_seconds"]),
    "tags": tags,
    "audio": {
      "streamUrl": audioUrl,
      "mimeType": audioUrl.toLowerCase().endsWith(".wav") ? "audio/wav" : "audio/mpeg",
      "bitrateKbps": null,
      "checksumSha256": null,
      "isOfficialHost": audioUrl.contains("loc.gov"),
    },
    "rights": {
      "rightsStatus": "public_domain",
      "rightsStatement":
          "National Jukebox recordings in this dataset are assumed public domain (pre-1923 publication).",
      "rightsUrl": "https://data.labs.loc.gov/jukebox/",
      "jurisdiction": "US",
      "verifiedAt": now,
      "verifiedBy": "loc-data-script",
    },
    "attribution": {
      "sourceName": "Library of Congress",
      "sourceItemUrl": sourceItemUrl,
      "creditLine": "Source: Library of Congress (National Jukebox Data Package)",
      "providerNotice": null,
    },
    "collection": {
      "collectionId": "loc-jukebox-jazz",
      "collectionName": "LOC Jukebox - Jazz",
      "collectionUrl": "https://citizen-dj.labs.loc.gov/loc-jukebox-jazz/use/",
      "apiEndpoint": "https://data.labs.loc.gov/jukebox/",
    },
    "artworkUrl": _firstString(record, ["image_url", "image"]),
    "notes": "Generated by tools/fetch_loc_catalog.dart",
    "addedAt": now,
    "updatedAt": now,
  };
}

String? _extractArtist(Map<String, dynamic> record) {
  final direct = _firstString(
    record,
    ["artist", "performer", "creator", "contributor_names", "Contributor_names"],
  );
  if (direct != null && direct.isNotEmpty) {
    return direct;
  }

  final contributors = _valueByAnyKey(record, ["Contributors", "contributors"]);
  final names = <String>{};
  void collect(dynamic value) {
    if (value == null) return;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        names.add(trimmed);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        collect(item);
      }
      return;
    }
    if (value is Map) {
      final map = value.cast<dynamic, dynamic>();
      for (final key in ["name", "label", "value", "text", "title"]) {
        final candidate = map[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          names.add(candidate.trim());
        }
      }
      for (final entry in map.entries) {
        if (entry.key.toString().toLowerCase().contains("name") &&
            entry.value is String &&
            (entry.value as String).trim().isNotEmpty) {
          names.add((entry.value as String).trim());
        }
      }
      return;
    }
  }

  collect(contributors);
  if (names.isNotEmpty) {
    return names.join(", ");
  }
  return null;
}

List<String> _extractTags(Map<String, dynamic> record) {
  final tags = <String>{};
  for (final source in ["genre", "genres", "subject", "subjects"]) {
    for (final value in _toStringList(_valueByAnyKey(record, [source, _capitalize(source)]))) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isNotEmpty) {
        tags.add(normalized);
      }
    }
  }
  tags.add("jazz");
  return tags.toList()..sort();
}

List<String> _toStringList(dynamic value) {
  if (value == null) return const [];
  if (value is String) return [value];
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return [value.toString()];
}

String _flattenText(dynamic value) {
  if (value == null) return "";
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return value.map(_flattenText).where((e) => e.isNotEmpty).join(" ");
  }
  if (value is Map) {
    return value.values.map(_flattenText).where((e) => e.isNotEmpty).join(" ");
  }
  return value.toString();
}

String? _firstString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = _valueByAnyKey(map, [key]);
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is String && first.trim().isNotEmpty) {
        return first.trim();
      }
    }
  }
  return null;
}

int? _firstInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = _valueByAnyKey(map, [key]);
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
  }
  return null;
}

dynamic _valueByAnyKey(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (map.containsKey(key)) {
      return map[key];
    }
    final normalizedTarget = key.toLowerCase();
    for (final entry in map.entries) {
      if (entry.key.toLowerCase() == normalizedTarget) {
        return entry.value;
      }
    }
  }
  return null;
}

void _printRecordShape(String label, Map<String, dynamic>? record) {
  if (record == null) {
    stdout.writeln("$label: <empty>");
    return;
  }
  final keys = record.keys.toList()..sort();
  stdout.writeln("$label keys (${keys.length}): ${keys.take(30).join(", ")}");
}

Future<String?> _resolveAudioFromItemApi(
  HttpClient client,
  Map<String, dynamic> record, {
  required bool debug,
  required void Function(String message) onError,
}) async {
  final source = _firstString(record, ["id", "url"]);
  if (source == null) {
    return null;
  }

  Uri? uri = Uri.tryParse(source);
  if (uri == null) {
    return null;
  }
  if (uri.host == "www.loc.gov" || uri.host == "loc.gov") {
    uri = uri.replace(scheme: "https");
    uri = uri.replace(queryParameters: {
      ...uri.queryParameters,
      "fo": "json",
    });
  } else {
    return null;
  }

  try {
    final json = await _fetchJson(client, uri);
    final candidates = <String>{};
    _collectAudioUrls(json, candidates);
    if (candidates.isEmpty) {
      return null;
    }
    final preferred = candidates.firstWhere(
      (url) => url.toLowerCase().endsWith(".mp3"),
      orElse: () => candidates.first,
    );
    return preferred;
  } catch (e) {
    if (debug) {
      onError("uri=$uri error=$e");
    }
    return null;
  }
}

Future<bool> _isReachableAudioUrl(
  HttpClient client,
  String url, {
  required bool strict,
  required Duration timeout,
}) async {
  Uri? uri = Uri.tryParse(url);
  if (uri == null) {
    return false;
  }

  try {
    final headRequest = await client.headUrl(uri).timeout(timeout);
    final headResponse = await headRequest.close().timeout(timeout);
    await headResponse.drain<void>();
    if (headResponse.statusCode >= 200 && headResponse.statusCode < 400) {
      return true;
    }
  } catch (_) {
    if (!strict) {
      return false;
    }
  }

  if (!strict) {
    return false;
  }

  try {
    final getRequest = await client.getUrl(uri).timeout(timeout);
    getRequest.headers.set(HttpHeaders.rangeHeader, "bytes=0-0");
    final getResponse = await getRequest.close().timeout(timeout);
    await getResponse.drain<void>();
    return getResponse.statusCode >= 200 && getResponse.statusCode < 400;
  } catch (_) {
    return false;
  }
}

void _collectAudioUrls(dynamic node, Set<String> out) {
  if (node == null) return;
  if (node is String) {
    if (_looksLikeAudioUrl(node)) {
      out.add(node);
    }
    return;
  }
  if (node is List) {
    for (final item in node) {
      _collectAudioUrls(item, out);
    }
    return;
  }
  if (node is Map) {
    for (final value in node.values) {
      _collectAudioUrls(value, out);
    }
  }
}

String? _firstAudioLikeUrl(dynamic node) {
  if (node == null) return null;
  if (node is String) {
    return _looksLikeAudioUrl(node) ? node : null;
  }
  if (node is List) {
    for (final item in node) {
      final found = _firstAudioLikeUrl(item);
      if (found != null) return found;
    }
    return null;
  }
  if (node is Map) {
    // Prioritize likely audio-related keys first.
    final entries = node.entries.toList()
      ..sort((a, b) {
        final aScore = _audioKeyScore(a.key);
        final bScore = _audioKeyScore(b.key);
        return bScore.compareTo(aScore);
      });
    for (final entry in entries) {
      final found = _firstAudioLikeUrl(entry.value);
      if (found != null) return found;
    }
  }
  return null;
}

int _audioKeyScore(String key) {
  final lower = key.toLowerCase();
  if (lower.contains("preview")) return 5;
  if (lower.contains("audio")) return 4;
  if (lower.contains("download")) return 3;
  if (lower.contains("resource")) return 2;
  if (lower.contains("url")) return 1;
  return 0;
}

String? _audioUrlFromIiifManifest(Map<String, dynamic> record) {
  // Best source: preview image URLs often include:
  // ...service:mbrsrs:mbrsjukebox:<audioId>:<audioId>/...
  final previewCandidates = _toStringList(_valueByAnyKey(record, ["Preview_url", "preview_url"]));
  for (final candidate in previewCandidates) {
    final id = _extractJukeboxAudioId(candidate);
    if (id != null) {
      return "https://tile.loc.gov/storage-services/service/mbrsrs/mbrsjukebox/$id/$id.mp3";
    }
  }

  final iiif = _firstString(record, ["IIIF_manifest", "iiif_manifest"]);
  if (iiif != null) {
    final id = _extractJukeboxAudioId(iiif);
    if (id != null) {
      return "https://tile.loc.gov/storage-services/service/mbrsrs/mbrsjukebox/$id/$id.mp3";
    }
  }

  return null;
}

String? _extractJukeboxAudioId(String text) {
  final match = RegExp(r"service:mbrsrs:mbrsjukebox:([^:\/]+):").firstMatch(text);
  return match?.group(1);
}

String _capitalize(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}
