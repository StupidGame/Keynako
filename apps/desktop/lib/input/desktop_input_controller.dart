import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:keynako_conversion/keynako_conversion.dart';

import 'desktop_shared_dictionary.dart';
import 'desktop_personal_dictionary.dart';

enum InputMode { japanese, english }

enum ZenzaiModel { off, xsmall, small }

typedef ZenzaiEngineFactory = Future<ZenzaiEngine?> Function(ZenzaiModel model);

class DesktopInputController extends ChangeNotifier {
  factory DesktopInputController({
    ZenzaiEngineFactory? zenzaiEngineFactory,
    SharedDictionaryRepository? sharedDictionaryRepository,
    PersonalDictionaryRepository? personalDictionaryRepository,
    KeynakoDictionarySubmitter? sharedDictionarySubmitter,
    Duration sharedDictionaryInterval = desktopSharedDictionaryInterval,
  }) => DesktopInputController._(
    zenzaiEngineFactory,
    sharedDictionaryRepository,
    personalDictionaryRepository,
    sharedDictionarySubmitter ?? KeynakoDictionarySubmissionClient(),
    sharedDictionaryInterval,
  );

  DesktopInputController._(
    this._zenzaiEngineFactory,
    this._sharedDictionaryRepository,
    this._personalDictionaryRepository,
    this._sharedDictionarySubmitter,
    this._sharedDictionaryInterval,
  );

  static const _japaneseConverter = JapaneseConverter();
  static const _englishConverter = EnglishConverter();
  static const _closingDelimiters = <String, String>{
    '「': '」',
    '『': '』',
    '(': ')',
    '（': '）',
    '[': ']',
    '［': '］',
    '{': '}',
    '｛': '｝',
    '【': '】',
    '〈': '〉',
    '《': '》',
  };

  static String? closingDelimiterFor(String value) => _closingDelimiters[value];

  static String? trailingOpeningDelimiter(String value) {
    for (final opening in _closingDelimiters.keys) {
      if (value.endsWith(opening)) return opening;
    }
    return null;
  }

  final ZenzaiEngineFactory? _zenzaiEngineFactory;
  final SharedDictionaryRepository? _sharedDictionaryRepository;
  final PersonalDictionaryRepository? _personalDictionaryRepository;
  final KeynakoDictionarySubmitter _sharedDictionarySubmitter;
  final Duration _sharedDictionaryInterval;
  final Map<String, int> _learning = {};

  InputMode _mode = InputMode.japanese;
  ZenzaiModel _zenzaiModel = ZenzaiModel.off;
  ZenzaiEngine? _zenzaiEngine;
  String _rawInput = '';
  String _committedText = '';
  int _committedSelectionOffset = 0;
  List<ConversionCandidate> _candidates = const [];
  int _selectedIndex = 0;
  int _requestSequence = 0;
  Timer? _zenzaiDebounce;
  bool _zenzaiWorking = false;
  String _zenzaiStatus = '無効';
  bool _liveConversionEnabled = true;
  bool _converting = false;
  List<ConversionDictionaryEntry> _sharedDictionary = const [];
  List<ConversionDictionaryEntry> _personalDictionary = const [];
  bool _personalDictionaryLoadFailed = false;
  Timer? _sharedDictionaryTimer;
  bool _sharedDictionarySyncing = false;
  String _sharedDictionaryStatus = '未取得';
  bool _candidateSharing = false;
  String _candidateShareStatus = '';
  bool _disposed = false;

  InputMode get mode => _mode;
  ZenzaiModel get zenzaiModel => _zenzaiModel;
  String get rawInput => _rawInput;
  String get committedText => _committedText;
  int get committedSelectionOffset => _committedSelectionOffset;
  List<ConversionCandidate> get candidates => _candidates;
  int get selectedIndex => _selectedIndex;
  bool get zenzaiWorking => _zenzaiWorking;
  String get zenzaiStatus => _zenzaiStatus;
  bool get liveConversionEnabled => _liveConversionEnabled;
  bool get converting => _converting;
  bool get sharedDictionarySyncing => _sharedDictionarySyncing;
  String get sharedDictionaryStatus => _sharedDictionaryStatus;
  int get sharedDictionaryEntryCount => _sharedDictionary.length;
  List<ConversionDictionaryEntry> get personalDictionary =>
      List.unmodifiable(_personalDictionary);
  bool get personalDictionaryLoadFailed => _personalDictionaryLoadFailed;
  bool isPersonalCandidate(ConversionCandidate candidate) =>
      _personalDictionary.any(
        (entry) =>
            entry.value == candidate.text &&
            entry.reading.toLowerCase() == candidate.reading.toLowerCase(),
      );
  bool get candidateSharing => _candidateSharing;
  String get candidateShareStatus => _candidateShareStatus;

  String get composingText => _mode == InputMode.japanese
      ? _japaneseConverter.romanToHiragana(_rawInput)
      : _rawInput;

  String get displayedComposition {
    if (_mode == InputMode.japanese &&
        (_liveConversionEnabled || _converting) &&
        _candidates.isNotEmpty) {
      return (_converting
              ? _candidates[_selectedIndex]
              : _firstCompleteCandidate())
          .text;
    }
    return composingText;
  }

  ConversionCandidate _firstCompleteCandidate() => _candidates.firstWhere(
    (candidate) => !candidate.source.contains('prediction'),
    orElse: () => ConversionCandidate(
      text: composingText,
      reading: composingText,
      source: 'hiragana',
    ),
  );

  void setLiveConversionEnabled(bool enabled) {
    if (_liveConversionEnabled == enabled) return;
    _liveConversionEnabled = enabled;
    notifyListeners();
  }

  Future<void> initializeSharedDictionary() async {
    final repository = _sharedDictionaryRepository;
    if (repository == null) return;
    try {
      final cached = await repository.load();
      if (cached != null) _applySharedDictionary(cached);
    } catch (_) {
      _sharedDictionaryStatus = '保存データ読込失敗';
    }
    _sharedDictionaryTimer?.cancel();
    _sharedDictionaryTimer = Timer.periodic(
      _sharedDictionaryInterval,
      (_) => unawaited(importSharedDictionary()),
    );
    try {
      if (await repository.isRefreshDue()) {
        unawaited(importSharedDictionary());
      }
    } catch (_) {
      unawaited(importSharedDictionary());
    }
  }

  Future<bool> importSharedDictionary() async {
    final repository = _sharedDictionaryRepository;
    if (repository == null || _sharedDictionarySyncing || _disposed) {
      return false;
    }
    _sharedDictionarySyncing = true;
    _sharedDictionaryStatus = '更新中';
    notifyListeners();
    try {
      final snapshot = await repository.refresh();
      if (_disposed) return false;
      _applySharedDictionary(snapshot);
      return true;
    } catch (_) {
      if (!_disposed) {
        _sharedDictionaryStatus = '更新失敗';
        notifyListeners();
      }
      return false;
    } finally {
      if (!_disposed) {
        _sharedDictionarySyncing = false;
        notifyListeners();
      }
    }
  }

  void _applySharedDictionary(SharedDictionarySnapshot snapshot) {
    _sharedDictionary = snapshot.entries;
    _sharedDictionaryStatus =
        'v${snapshot.version} · ${snapshot.entries.length}語';
    if (_rawInput.isNotEmpty) _rebuildBaseCandidates();
    if (!_disposed) notifyListeners();
  }

  Future<void> initializePersonalDictionary() async {
    final repository = _personalDictionaryRepository;
    if (repository == null) return;
    try {
      _personalDictionary = await repository.load();
      _personalDictionaryLoadFailed = false;
    } on Object {
      _personalDictionary = const [];
      _personalDictionaryLoadFailed = true;
    }
    if (_rawInput.isNotEmpty) _rebuildBaseCandidates();
    notifyListeners();
  }

  Future<void> savePersonalDictionary(
    List<ConversionDictionaryEntry> entries,
  ) async {
    final repository = _personalDictionaryRepository;
    if (repository == null) throw StateError('個人辞書を保存できない');
    await repository.save(entries);
    _personalDictionary = List.unmodifiable(entries);
    _personalDictionaryLoadFailed = false;
    if (_rawInput.isNotEmpty) _rebuildBaseCandidates();
    notifyListeners();
  }

  Future<void> setZenzaiModel(ZenzaiModel model) async {
    if (_zenzaiModel == model &&
        (model == ZenzaiModel.off || _zenzaiEngine != null)) {
      return;
    }
    _requestSequence += 1;
    final previous = _zenzaiEngine;
    _zenzaiEngine = null;
    _zenzaiModel = model;
    _zenzaiWorking = false;
    _zenzaiStatus = model == ZenzaiModel.off ? '無効' : '準備中';
    notifyListeners();
    await previous?.close();

    if (model == ZenzaiModel.off) return;
    final engine = await _zenzaiEngineFactory?.call(model);
    if (_zenzaiModel != model) {
      await engine?.close();
      return;
    }
    _zenzaiEngine = engine;
    _zenzaiStatus = engine == null ? 'モデル未検出' : '待機中';
    notifyListeners();
    if (_rawInput.isNotEmpty) _scheduleZenzai();
  }

  void setMode(InputMode mode) {
    if (_mode == mode) return;
    final wasConverting = _converting;
    _mode = mode;
    _selectedIndex = 0;
    _rebuildBaseCandidates();
    _converting = wasConverting && _candidates.isNotEmpty;
    _requestSequence += 1;
    _zenzaiDebounce?.cancel();
    _zenzaiWorking = false;
    notifyListeners();
    if (_mode == InputMode.japanese && _rawInput.isNotEmpty) {
      _scheduleZenzai();
    }
  }

  void updateRawInput(String value) {
    _rawInput = value;
    _selectedIndex = 0;
    _converting = false;
    _rebuildBaseCandidates();
    notifyListeners();
    if (_mode == InputMode.japanese && value.isNotEmpty) {
      _scheduleZenzai();
    } else {
      _requestSequence += 1;
      _zenzaiDebounce?.cancel();
      _zenzaiWorking = false;
    }
  }

  void replaceCommittedText(String value) {
    _committedText = value;
    _committedSelectionOffset = value.length;
    notifyListeners();
  }

  void commitDirectText(String value, {int? replaceStart, int? replaceEnd}) {
    if (value.isEmpty) return;
    final closingDelimiter = closingDelimiterFor(value);
    _replaceCommittedRange(
      closingDelimiter == null ? value : '$value$closingDelimiter',
      replaceStart,
      replaceEnd,
      selectionOffsetInReplacement: closingDelimiter == null
          ? null
          : value.length,
    );
    cancelComposition();
  }

  void selectCandidate(int index) {
    if (index < 0 || index >= _candidates.length) return;
    _selectedIndex = index;
    _converting = true;
    notifyListeners();
  }

  Future<bool> shareCandidate(int index) async {
    if (index < 0 || index >= _candidates.length) return false;
    final candidate = _candidates[index];
    return shareCandidateText(candidate.text, candidate.reading);
  }

  Future<bool> shareCandidateText(String word, String reading) async {
    if (_candidateSharing || word.trim().isEmpty || reading.trim().isEmpty) {
      return false;
    }
    _candidateSharing = true;
    _candidateShareStatus = '共有ストレージへ送信中';
    notifyListeners();
    try {
      final sent = await _sharedDictionarySubmitter.submit(
        word: word,
        ruby: reading,
        importance: 3,
        categories: const [],
        note: 'Desktop candidate right-click',
      );
      _candidateShareStatus = sent ? '共有ストレージへ送信しました' : '共有ストレージへ送信できませんでした';
      return sent;
    } on Object {
      _candidateShareStatus = '共有ストレージへ送信できませんでした';
      return false;
    } finally {
      _candidateSharing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> saveCandidateToPersonalDictionary(int index) async {
    if (index < 0 || index >= _candidates.length) return false;
    final candidate = _candidates[index];
    return saveCandidateTextToPersonalDictionary(
      candidate.text,
      candidate.reading,
    );
  }

  Future<bool> saveCandidateTextToPersonalDictionary(
    String word,
    String reading,
  ) async {
    final repository = _personalDictionaryRepository;
    if (_candidateSharing ||
        repository == null ||
        word.trim().isEmpty ||
        reading.trim().isEmpty) {
      return false;
    }
    _candidateSharing = true;
    _candidateShareStatus = '個人辞書に登録中';
    notifyListeners();
    try {
      final entries = await repository.load();
      if (entries.any(
        (entry) => entry.reading == reading && entry.value == word,
      )) {
        _personalDictionary = List.unmodifiable(entries);
        _personalDictionaryLoadFailed = false;
        if (_rawInput.isNotEmpty) _rebuildBaseCandidates();
        _candidateShareStatus = '個人辞書に登録済みです';
        return true;
      }
      await savePersonalDictionary([
        ...entries,
        ConversionDictionaryEntry(reading: reading, value: word, importance: 3),
      ]);
      _candidateShareStatus = '個人辞書に登録しました';
      return true;
    } on Object {
      _candidateShareStatus = '個人辞書に登録できませんでした';
      return false;
    } finally {
      _candidateSharing = false;
      if (!_disposed) notifyListeners();
    }
  }

  void beginOrCycleCandidate(int delta) {
    if (_candidates.isEmpty) return;
    if (_converting) {
      _selectedIndex = (_selectedIndex + delta) % _candidates.length;
    } else {
      _converting = true;
      _selectedIndex = delta < 0 ? _candidates.length - 1 : 0;
    }
    notifyListeners();
  }

  bool cancelConversion() {
    if (!_converting) return false;
    _converting = false;
    _selectedIndex = 0;
    notifyListeners();
    return true;
  }

  void commitSelected({int? replaceStart, int? replaceEnd}) {
    if (_rawInput.isEmpty) return;
    final selected = _candidates.isEmpty
        ? null
        : (_converting
              ? _candidates[_selectedIndex]
              : _firstCompleteCandidate());
    final candidate = selected?.text ?? composingText;
    if (candidate.isEmpty) return;
    CandidateLearning.record(
      _learning,
      reading: selected?.reading ?? composingText,
      text: candidate,
      english: _mode == InputMode.english,
      explicitSelection: _converting,
    );
    final committedCandidate = _mode == InputMode.english
        ? '$candidate '
        : candidate;
    _replaceCommittedRange(committedCandidate, replaceStart, replaceEnd);
    cancelComposition();
  }

  void _replaceCommittedRange(
    String value,
    int? replaceStart,
    int? replaceEnd, {
    int? selectionOffsetInReplacement,
  }) {
    var selectionStart = _committedText.length;
    var selectionEnd = _committedText.length;
    if (replaceStart != null &&
        replaceEnd != null &&
        replaceStart >= 0 &&
        replaceEnd >= 0 &&
        replaceStart <= _committedText.length &&
        replaceEnd <= _committedText.length) {
      selectionStart = replaceStart < replaceEnd ? replaceStart : replaceEnd;
      selectionEnd = replaceStart < replaceEnd ? replaceEnd : replaceStart;
    }
    _committedText = _committedText.replaceRange(
      selectionStart,
      selectionEnd,
      value,
    );
    _committedSelectionOffset =
        selectionStart + (selectionOffsetInReplacement ?? value.length);
  }

  void cancelComposition() {
    _rawInput = '';
    _candidates = const [];
    _selectedIndex = 0;
    _converting = false;
    _requestSequence += 1;
    _zenzaiDebounce?.cancel();
    _zenzaiWorking = false;
    notifyListeners();
  }

  void _rebuildBaseCandidates() {
    if (_rawInput.isEmpty) {
      _candidates = const [];
      return;
    }
    final options = ConversionOptions(
      userDictionary: [..._personalDictionary, ..._sharedDictionary],
      learning: _learning,
    );
    _candidates = _mode == InputMode.japanese
        ? _japaneseConverter.candidates(
            input: _rawInput,
            romanInput: true,
            options: options,
          )
        : _englishConverter.candidates(input: _rawInput, options: options);
  }

  void _scheduleZenzai() {
    final engine = _zenzaiEngine;
    if (engine == null) return;
    final sequence = ++_requestSequence;
    final reading = composingText;
    _zenzaiDebounce?.cancel();
    _zenzaiWorking = true;
    _zenzaiStatus = '入力待ち';
    notifyListeners();
    _zenzaiDebounce = Timer(
      const Duration(milliseconds: 140),
      () => _runZenzai(engine, sequence, reading),
    );
  }

  Future<void> _runZenzai(
    ZenzaiEngine engine,
    int sequence,
    String reading,
  ) async {
    if (sequence != _requestSequence) return;
    _zenzaiStatus = '推論中';
    notifyListeners();
    try {
      final committedCharacters = _committedText.characters;
      final skipCount = committedCharacters.length - 40;
      final generated = await engine.generate(
        ZenzaiRequest(
          reading: reading,
          leftContext: committedCharacters
              .skip(skipCount < 0 ? 0 : skipCount)
              .toString(),
        ),
      );
      if (sequence != _requestSequence || generated == null) return;
      final selectedText = _converting && _candidates.isNotEmpty
          ? _candidates[_selectedIndex].text
          : null;
      final existingIndex = _candidates.indexWhere(
        (candidate) => candidate.text == generated,
      );
      if (existingIndex < 0) {
        _candidates = [
          ConversionCandidate(
            text: generated,
            reading: reading,
            source: 'zenzai',
            score: 1000,
          ),
          ..._candidates,
        ];
      } else if (_candidatePhase(_candidates[existingIndex]) == 0) {
        // The model may select a word already present in a dictionary or learning.
        _candidates[existingIndex] = ConversionCandidate(
          text: generated,
          reading: reading,
          source: 'zenzai',
          score: 1000,
        );
      }
      final learned = CandidateLearning.exactScores(_learning, reading);
      final ranked = _candidates.indexed.toList()
        ..sort((left, right) {
          final leftPhase = _candidatePhase(left.$2);
          final rightPhase = _candidatePhase(right.$2);
          if (leftPhase != rightPhase) {
            return leftPhase.compareTo(rightPhase);
          }
          final leftPriority = _candidatePriority(left.$2);
          final rightPriority = _candidatePriority(right.$2);
          if (leftPriority != rightPriority) {
            return leftPriority.compareTo(rightPriority);
          }
          final score = (learned[right.$2.text] ?? 0).compareTo(
            learned[left.$2.text] ?? 0,
          );
          return leftPriority == 1 && score != 0
              ? score
              : left.$1.compareTo(right.$1);
        });
      _candidates = ranked.map((entry) => entry.$2).toList();
      _selectedIndex = selectedText == null
          ? 0
          : _candidates.indexWhere((value) => value.text == selectedText);
      if (_selectedIndex < 0) _selectedIndex = 0;
      _zenzaiStatus = '待機中';
    } catch (_) {
      if (sequence != _requestSequence) return;
      _zenzaiStatus = '利用不可';
    } finally {
      if (sequence == _requestSequence) {
        _zenzaiWorking = false;
        notifyListeners();
      }
    }
  }

  static int _candidatePriority(ConversionCandidate candidate) {
    if (candidate.source == 'zenzai') return -1;
    if (candidate.source.startsWith('user')) return 1;
    if (candidate.source.startsWith('learned')) return 2;
    return 0;
  }

  static int _candidatePhase(ConversionCandidate candidate) {
    if (const {
      'hiragana',
      'katakana',
      'half-kana',
      'full-width',
      'english',
    }.contains(candidate.source)) {
      return 2;
    }
    return candidate.source == 'user-prefix' ||
            candidate.source.contains('prediction')
        ? 1
        : 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _requestSequence += 1;
    _zenzaiDebounce?.cancel();
    _sharedDictionaryTimer?.cancel();
    _zenzaiEngine?.close();
    super.dispose();
  }
}
