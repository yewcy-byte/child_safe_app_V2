import 'package:flutter/services.dart';

class WordPieceTokenizer {
  final Map<String, int> _vocab = <String, int>{};
  bool get isLoaded => _vocab.isNotEmpty;

  Future<void> loadVocabFromAsset(String assetPath) async {
    if (_vocab.isNotEmpty) {
      return;
    }

    final raw = await rootBundle.loadString(assetPath);
    final lines = raw.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        _vocab[token] = i;
      }
    }
  }

  List<int> tokenize(String text, {int maxLen = 128}) {
    if (_vocab.isEmpty) {
      throw StateError('WordPiece vocab not loaded.');
    }

    final clsId = _vocab['[CLS]'] ?? 101;
    final sepId = _vocab['[SEP]'] ?? 102;
    final unkId = _vocab['[UNK]'] ?? 100;
    final padId = _vocab['[PAD]'] ?? 0;

    final ids = <int>[clsId];
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);

    for (final word in words) {
      ids.addAll(_wordPieceTokenIds(word, unkId));
      if (ids.length >= maxLen - 1) {
        break;
      }
    }

    ids.add(sepId);

    if (ids.length > maxLen) {
      return ids.sublist(0, maxLen);
    }

    while (ids.length < maxLen) {
      ids.add(padId);
    }
    return ids;
  }

  List<int> _wordPieceTokenIds(String word, int unkId) {
    if (_vocab.containsKey(word)) {
      return <int>[_vocab[word]!];
    }

    final pieces = <int>[];
    var start = 0;

    while (start < word.length) {
      int? foundId;
      var end = word.length;

      while (end > start) {
        final piece = start == 0
            ? word.substring(start, end)
            : '##${word.substring(start, end)}';
        final id = _vocab[piece];
        if (id != null) {
          foundId = id;
          start = end;
          break;
        }
        end -= 1;
      }

      if (foundId == null) {
        return <int>[unkId];
      }

      pieces.add(foundId);
    }

    return pieces.isEmpty ? <int>[unkId] : pieces;
  }
}
