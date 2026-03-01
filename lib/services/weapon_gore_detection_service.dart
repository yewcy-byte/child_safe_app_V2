import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

enum WeaponGoreLabel {
  blood,
  weapon,
  safe,
}

extension WeaponGoreLabelX on WeaponGoreLabel {
  bool get isUnsafe => this != WeaponGoreLabel.safe;
}

class WeaponGoreResult {
  final WeaponGoreLabel label;
  final List<double> scores;

  const WeaponGoreResult({
    required this.label,
    required this.scores,
  });

  double get confidence {
    if (scores.isEmpty) {
      return 0.0;
    }
    return scores.reduce((a, b) => a > b ? a : b);
  }
}

class WeaponGoreDetectionService {
  static const int _inputSize = 320;
  static const List<String> _labels = ['Blood', 'Weapon', 'Safe'];
  static const double _unsafeConfidenceThreshold = 0.995;

  Interpreter? _interpreter;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _interpreter = await Interpreter.fromAsset('weapon+gore_v2.tflite');
      _interpreter?.allocateTensors();
    } catch (_) {
      _interpreter = null;
    } finally {
      _isInitialized = true;
    }
  }

  Future<WeaponGoreResult> detect(File imageFile) async {
    if (!_isInitialized || _interpreter == null) {
      return const WeaponGoreResult(label: WeaponGoreLabel.safe, scores: []);
    }

    if (!await imageFile.exists()) {
      return const WeaponGoreResult(label: WeaponGoreLabel.safe, scores: []);
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return const WeaponGoreResult(label: WeaponGoreLabel.safe, scores: []);
      }

      final input = _preprocess(decoded);
      final output = List.generate(1, (_) => List<double>.filled(3, 0));

      _interpreter!.run(input, output);

      final scores = output[0];
      int winner = 0;
      for (var i = 1; i < scores.length; i++) {
        if (scores[i] > scores[winner]) {
          winner = i;
        }
      }

      var label = _labelFromIndex(winner);
      final winningScore = scores[winner];
      if (label != WeaponGoreLabel.safe && winningScore < _unsafeConfidenceThreshold) {
        label = WeaponGoreLabel.safe;
      }

      return WeaponGoreResult(
        label: label,
        scores: List<double>.from(scores),
      );
    } catch (_) {
      return const WeaponGoreResult(label: WeaponGoreLabel.safe, scores: []);
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }

  List<List<List<List<double>>>> _preprocess(img.Image image) {
    final int size = image.width < image.height ? image.width : image.height;
    final img.Image cropped = img.copyCrop(
      image,
      x: (image.width - size) ~/ 2,
      y: (image.height - size) ~/ 2,
      width: size,
      height: size,
    );

    final img.Image resized = img.copyResize(
      cropped,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.average,
    );

    final List<List<List<List<double>>>> input =
        List.generate(1, (_) => List.generate(
              _inputSize,
              (_) => List.generate(
                _inputSize,
                (_) => List<double>.filled(3, 0.0),
              ),
            ));

    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input[0][y][x][0] = pixel.r.toDouble();
        input[0][y][x][1] = pixel.g.toDouble();
        input[0][y][x][2] = pixel.b.toDouble();
      }
    }

    return input;
  }

  WeaponGoreLabel _labelFromIndex(int index) {
    if (index < 0 || index >= _labels.length) {
      return WeaponGoreLabel.safe;
    }

    switch (_labels[index]) {
      case 'Blood':
        return WeaponGoreLabel.blood;
      case 'Weapon':
        return WeaponGoreLabel.weapon;
      default:
        return WeaponGoreLabel.safe;
    }
  }
}
