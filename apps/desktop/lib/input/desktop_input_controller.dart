import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:keynako_conversion/keynako_conversion.dart';

enum InputMode { japanese, english }

enum ZenzaiModel { off, xsmall, small }

typedef ZenzaiEngineFactory = Future<ZenzaiEngine?> Function(ZenzaiModel model);

class DesktopInputController extends ChangeNotifier {
  factory DesktopInputController({ZenzaiEngineFactory? zenzaiEngineFactory}) =>
      DesktopInputController._(zenzaiEngineFactory);

  DesktopInputController._(this._zenzaiEngineFactory);

  static const _japaneseConverter = JapaneseConverter();
  static const _englishConverter = EnglishConverter();

  final ZenzaiEngineFactory? _zenzaiEngineFactory;
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

  InputMode get mode => _mode;
  ZenzaiModel get zenzaiModel => _zenzaiModel;
  String get rawInput => _rawInput;
  String get committedText => _committedText;
  List<ConversionCandidate> get candidates => _candidates;
  int get selectedIndex => _selectedIndex;
  bool get zenzaiWorking => _zenzaiWorking;
  String get zenzaiStatus => _zenzaiStatus;
  bool get liveConversionEnabled => _liveConversionEnabled;

  String get composingText => _mode == InputMode.japanese
      ? _japaneseConverter.romanToHiragana(_rawInput)
      : _rawInput;

  String get displayedComposition {
    if (_mode == InputMode.japanese &&
        _liveConversionEnabled &&
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
    _requestSequence += 1;
    _zenzaiDebounce?.cancel();
    _zenzaiWorking = false;
    notifyListeners();
  }

  void updateRawInput(String value) {
    _rawInput = value;
    _selectedIndex = 0;
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
    notifyListeners();
  }

  void cycleCandidate(int delta) {
    if (_candidates.isEmpty) return;
    _selectedIndex = (_selectedIndex + delta) % _candidates.length;
    notifyListeners();
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
    final options = ConversionOptions(learning: _learning);
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
    _requestSequence += 1;
    _zenzaiDebounce?.cancel();
    _zenzaiEngine?.close();
    super.dispose();
  }
}
