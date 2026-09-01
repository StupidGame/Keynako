import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:keynako_conversion/keynako_conversion.dart';

import 'desktop_shared_dictionary.dart';

enum InputMode { japanese, english }

enum ZenzaiModel { off, xsmall, small }

typedef ZenzaiEngineFactory = Future<ZenzaiEngine?> Function(ZenzaiModel model);

class DesktopInputController extends ChangeNotifier {
  factory DesktopInputController({
    ZenzaiEngineFactory? zenzaiEngineFactory,
    SharedDictionaryRepository? sharedDictionaryRepository,
    KeynakoDictionarySubmitter? sharedDictionarySubmitter,
  }) => DesktopInputController._(
    zenzaiEngineFactory,
    sharedDictionaryRepository,
    sharedDictionarySubmitter ?? KeynakoDictionarySubmissionClient(),
  );

  DesktopInputController._(
    this._zenzaiEngineFactory,
    this._sharedDictionaryRepository,
    this._sharedDictionarySubmitter,
  );

  static const _japaneseConverter = JapaneseConverter();
  static const _englishConverter = EnglishConverter();

  final ZenzaiEngineFactory? _zenzaiEngineFactory;
  final SharedDictionaryRepository? _sharedDictionaryRepository;
  final KeynakoDictionarySubmitter _sharedDictionarySubmitter;
  final Map<String, int> _learning = {};

  InputMode _mode = InputMode.japanese;
  ZenzaiModel _zenzaiModel = ZenzaiModel.off;
  ZenzaiEngine? _zenzaiEngine;
  String _rawInput = '';
  String _committedText = '';
  List<ConversionCandidate> _candidates = const [];
  int _selectedIndex = 0;
  int _requestSequence = 0;
  Timer? _zenzaiDebounce;
  bool _zenzaiWorking = false;
  String _zenzaiStatus = '無効';
  bool _liveConversionEnabled = true;
  bool _converting = false;
  List<ConversionDictionaryEntry> _sharedDictionary = const [];
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
  List<ConversionCandidate> get candidates => _candidates;
  int get selectedIndex => _selectedIndex;
  bool get zenzaiWorking => _zenzaiWorking;
  String get zenzaiStatus => _zenzaiStatus;
  bool get liveConversionEnabled => _liveConversionEnabled;
  bool get converting => _converting;
  bool get sharedDictionarySyncing => _sharedDictionarySyncing;
  String get sharedDictionaryStatus => _sharedDictionaryStatus;
  int get sharedDictionaryEntryCount => _sharedDictionary.length;
  bool get candidateSharing => _candidateSharing;
  String get candidateShareStatus => _candidateShareStatus;

  String get composingText => _mode == InputMode.japanese
      ? _japaneseConverter.romanToHiragana(_rawInput)
      : _rawInput;

  String get displayedComposition {
    if (_mode == InputMode.japanese &&
        (_liveConversionEnabled || _converting) &&
        _candidates.isNotEmpty) {
      return _candidates[_selectedIndex].text;
    }
    return composingText;
  }

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
      desktopSharedDictionaryInterval,
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
    _mode = mode;
    _rawInput = '';
    _candidates = const [];
    _selectedIndex = 0;
    _converting = false;
    _requestSequence += 1;
    _zenzaiDebounce?.cancel();
    _zenzaiWorking = false;
    notifyListeners();
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
    notifyListeners();
  }

  void selectCandidate(int index) {
    if (index < 0 || index >= _candidates.length) return;
    _selectedIndex = index;
    _converting = true;
    notifyListeners();
  }

  Future<bool> shareCandidate(int index) async {
    if (_candidateSharing || index < 0 || index >= _candidates.length) {
      return false;
    }
    final candidate = _candidates[index];
    _candidateSharing = true;
    _candidateShareStatus = '共有ストレージへ送信中';
    notifyListeners();
    try {
      final sent = await _sharedDictionarySubmitter.submit(
        word: candidate.text,
        ruby: candidate.reading,
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

  void commitSelected() {
    if (_rawInput.isEmpty) return;
    final candidate = _candidates.isEmpty
        ? composingText
        : _candidates[_selectedIndex].text;
    if (candidate.isEmpty) return;
    final learningKey = _mode == InputMode.japanese
        ? '$composingText\t$candidate'
        : 'english:${_rawInput.toLowerCase()}\t$candidate';
    _learning[learningKey] = (_learning[learningKey] ?? 0) + 1;
    _committedText += candidate;
    if (_mode == InputMode.english) _committedText += ' ';
    cancelComposition();
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
      userDictionary: _sharedDictionary,
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
      _candidates = [
        ConversionCandidate(
          text: generated,
          reading: reading,
          source: 'zenzai',
          score: 1000,
        ),
        ..._candidates.where((candidate) => candidate.text != generated),
      ];
      _selectedIndex = 0;
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
