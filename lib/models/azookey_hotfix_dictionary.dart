const String azooKeyHotfixStorageKey = 'azooKey_hotfix_dictionary_storage';
const String azooKeyHotfixLatestTagKey =
    'azooKey_hotfix_dictionary_storage_latest_tag';
const String azooKeyHotfixLastCheckDateKey =
    'azooKey_hotfix_dictionary_storage_last_check_date';

class AzooKeyHotfixDictionary {
  const AzooKeyHotfixDictionary({
    required this.metadata,
    required this.entries,
  });

  final AzooKeyHotfixMetadata metadata;
  final List<AzooKeyHotfixEntry> entries;

  factory AzooKeyHotfixDictionary.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    final data = json['data'];
    if (metadata is! Map || data is! List) {
      throw const FormatException('azooKey hotfix dictionary is malformed.');
    }
    return AzooKeyHotfixDictionary(
      metadata: AzooKeyHotfixMetadata.fromJson(
        Map<String, dynamic>.from(metadata),
      ),
      entries: data
          .map((entry) {
            if (entry is! Map) {
              throw const FormatException(
                'azooKey hotfix dictionary entry is malformed.',
              );
            }
            return AzooKeyHotfixEntry.fromJson(
              Map<String, dynamic>.from(entry),
            );
          })
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    'data': entries.map((entry) => entry.toJson()).toList(growable: false),
  };
}

class AzooKeyHotfixMetadata {
  const AzooKeyHotfixMetadata({
    required this.status,
    required this.name,
    required this.description,
    required this.version,
    required this.lastUpdate,
  });

  final String status;
  final String name;
  final String description;
  final String version;
  final String lastUpdate;

  bool get isActive => status == 'active';

  factory AzooKeyHotfixMetadata.fromJson(Map<String, dynamic> json) {
    final status = _requiredString(json, 'status');
    if (status != 'active' && status != 'disabled') {
      throw FormatException('Unknown azooKey hotfix status: $status');
    }
    return AzooKeyHotfixMetadata(
      status: status,
      name: _requiredString(json, 'name'),
      description: _requiredString(json, 'description'),
      version: _requiredString(json, 'version'),
      lastUpdate: _requiredString(json, 'last_update'),
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'name': name,
    'description': description,
    'version': version,
    'last_update': lastUpdate,
  };
}

class AzooKeyHotfixEntry {
  const AzooKeyHotfixEntry({
    required this.word,
    required this.ruby,
    required this.wordWeight,
    required this.lcid,
    required this.rcid,
    required this.mid,
    required this.date,
    required this.author,
  });

  final String word;
  final String ruby;
  final double wordWeight;
  final int lcid;
  final int rcid;
  final int mid;
  final String date;
  final String author;

  factory AzooKeyHotfixEntry.fromJson(Map<String, dynamic> json) {
    return AzooKeyHotfixEntry(
      word: _requiredString(json, 'word'),
      ruby: _requiredString(json, 'ruby'),
      wordWeight: _requiredNumber(json, 'word_weight').toDouble(),
      lcid: _requiredNumber(json, 'lcid').toInt(),
      rcid: _requiredNumber(json, 'rcid').toInt(),
      mid: _requiredNumber(json, 'mid').toInt(),
      date: _requiredString(json, 'date'),
      author: _requiredString(json, 'author'),
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'ruby': ruby,
    'word_weight': wordWeight,
    'lcid': lcid,
    'rcid': rcid,
    'mid': mid,
    'date': date,
    'author': author,
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('azooKey hotfix field "$key" is missing.');
}

num _requiredNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value;
  throw FormatException('azooKey hotfix field "$key" is missing.');
}
