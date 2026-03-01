import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_nsfw/flutter_nsfw.dart';
import 'package:path_provider/path_provider.dart';

class NSFWDetectionService {
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDocDir.path}/nsfw.tflite');
      
      // Copy from assets if not already in documents directory
      if (!await modelFile.exists()) {
        try {
          final data = await rootBundle.load('assets/nsfw.tflite');
          await modelFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
        } catch (e) {
          _isInitialized = true;
          return;
        }
      }

      await FlutterNsfw.initNsfw(
        modelFile.path,
        isOpenGPU: false,
        numThreads: 4,
      );
      
      _isInitialized = true;
    } catch (e) {
      _isInitialized = true;
    }
  }

  Future<double> detectNSFW(File imageFile) async {
    if (!_isInitialized) {
      return 0.0;
    }

    if (!await imageFile.exists()) {
      return 0.0;
    }

    try {
      final score = await FlutterNsfw.getPhotoNSFWScore(imageFile.path) ?? 0.0;
      return score;
    } catch (e) {
      return 0.0;
    }
  }

  void dispose() {
    _isInitialized = false;
  }
}
