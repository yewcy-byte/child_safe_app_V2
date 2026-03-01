import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class ObjectDetectionService {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  bool _isRunning = false;
  
  static const int inputSize = 320;
  static const double confidenceThreshold = 0.5;
  static const int weaponClassId = 0; // Class 0 = weapon (check labelmap.txt to confirm)
  
  // Output tensor indices (may vary by TF version)
  int _classesIdx = 1;
  int _scoresIdx = 2;
  bool _isFloatingModel = true;

  /// Check if the model is currently loaded
  bool get isModelLoaded => _isModelLoaded && _interpreter != null;

  Future<void> loadModel() async {
    try {
      print("🔄 Loading weapon detection model...");
      
      // Load the model from assets
      _interpreter = await Interpreter.fromAsset('detect.tflite');
      
      // Verify interpreter was created
      if (_interpreter == null) {
        throw Exception('Interpreter is null after loading');
      }

      // Allocate tensors before querying shapes
      _interpreter!.allocateTensors();

      // Validate input tensor shape
      final inputTensors = _interpreter!.getInputTensors();
      print("📊 Input tensors: ${inputTensors.length}");
      if (inputTensors.isNotEmpty) {
        final inputShape = inputTensors[0].shape;
        final inputType = inputTensors[0].type;
        _isFloatingModel = (inputType == TfLiteType.float32);
        print("📐 Expected input shape: $inputShape");
        print("📐 Expected input type: $inputType");
        print("📐 Floating model: $_isFloatingModel");
        
        // Verify the input shape matches our expectations [1, 320, 320, 3]
        if (inputShape.length != 4 || inputShape[1] != inputSize || inputShape[2] != inputSize) {
          print("⚠️ Warning: Input shape $inputShape doesn't match expected [1, $inputSize, $inputSize, 3]");
        }
      }

      // Validate output tensor shape and determine output order
      final outputTensors = _interpreter!.getOutputTensors();
      print("📊 Output tensors: ${outputTensors.length}");
      bool isTf2Model = false;
      for (int i = 0; i < outputTensors.length; i++) {
        print("   Output $i: ${outputTensors[i].shape} (${outputTensors[i].type}) - ${outputTensors[i].name}");
        
        // Determine if TF2 or TF1 model based on output name
        if (outputTensors[i].name.contains('StatefulPartitionedCall')) {
          isTf2Model = true;
        }
      }

      if (isTf2Model) {
        print("📌 Detected TF2 model");
        _classesIdx = 3;
        _scoresIdx = 0;
      } else {
        print("📌 Detected TF1 model");
        _classesIdx = 1;
        _scoresIdx = 2;
      }

      _isModelLoaded = true;
      print("✅ Weapon detection model loaded successfully");
      print("✅ Model is ready for inference");
      
    } catch (e) {
      _isModelLoaded = false;
      _interpreter = null;
      print("❌ Error loading model: $e");
      rethrow;
    }
  }

  Future<bool> detectWeapon(String imagePath) async {
    try {
      if (!isModelLoaded) {
        print("❌ Model not loaded. Please call loadModel() first.");
        return false;
      }

      if (_isRunning) {
        print("⏳ Weapon detection already running; skipping this frame");
        return false;
      }
      _isRunning = true;

      final interpreter = _interpreter;
      if (interpreter == null) {
        print("❌ Interpreter is null even though model is marked loaded");
        return false;
      }

      final imageFile = File(imagePath);
      if (!imageFile.existsSync()) {
        print("❌ Image file not found: $imagePath");
        return false;
      }

      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      
      if (decodedImage == null) {
        print("❌ Failed to decode image");
        return false;
      }

      if (_isMostlyBlank(decodedImage)) {
        print("🟡 Mostly blank frame detected; skipping weapon detection");
        return false;
      }

      // Preprocess image to [1, 320, 320, 3]
      final input = _preprocess(decodedImage);

      // Prepare output buffers matching actual model outputs
      // Output 0: [1, 10], Output 1: [1, 10, 4], Output 2: [1], Output 3: [1, 10]
      var output0 = List.generate(1, (_) => List.generate(10, (_) => 0.0));
      var output1 = List.generate(1, (_) => List.generate(10, (_) => List.generate(4, (_) => 0.0)));
      var output2 = List.generate(1, (_) => 0.0);
      var output3 = List.generate(1, (_) => List.generate(10, (_) => 0.0));

      final outputs = {
        0: output0,
        1: output1,
        2: output2,
        3: output3,
      };

      print("🚀 Running inference...");

      // Run inference - input must be a properly shaped list
      interpreter.runForMultipleInputs([input], outputs);

      print("✅ Inference completed");

      // boxes output not used in current detection logic
      final classes = _classesIdx == 3 ? output3[0] : output0[0];
      final scores = _scoresIdx == 0 ? output0[0] : output3[0];
      final numDetections = (output2[0] as num).toInt();

      print("🔍 Detections found: $numDetections");
      print("📊 Classes: $classes");
      print("📊 Scores: $scores");

      bool weaponDetected = _checkResults(classes, scores);
      print("🔫 Weapon detected: $weaponDetected");
      
      return weaponDetected;
    } catch (e, stackTrace) {
      print("❌ Detection error: $e");
      print("🧵 Stack trace: $stackTrace");
      return false;
    } finally {
      _isRunning = false;
    }
  }

  List<List<List<List<double>>>> _preprocess(img.Image image) {
    // Resize with letterboxing to preserve aspect ratio and avoid distortion.
    final int srcWidth = image.width;
    final int srcHeight = image.height;
    final double scale = (inputSize / srcWidth).clamp(0.0, double.infinity)
        .compareTo(inputSize / srcHeight) <= 0
        ? inputSize / srcWidth
        : inputSize / srcHeight;
    final int newWidth = (srcWidth * scale).round();
    final int newHeight = (srcHeight * scale).round();

    final img.Image resizedImage = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.average,
    );

    final img.Image letterboxed = img.Image(width: inputSize, height: inputSize);
    img.fill(letterboxed, color: img.ColorUint8.rgba(0, 0, 0, 255));

    final int offsetX = ((inputSize - newWidth) / 2).round();
    final int offsetY = ((inputSize - newHeight) / 2).round();
    img.compositeImage(letterboxed, resizedImage, dstX: offsetX, dstY: offsetY);

    // Create 4D list [1, 320, 320, 3]
    // Normalize to [-1, 1] range as per TFLite object detection models
    const inputMean = 127.5;
    const inputStd = 127.5;

    var input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            var pixel = letterboxed.getPixel(x, y);
            if (_isFloatingModel) {
              // Normalize: (pixel - 127.5) / 127.5 = [-1, 1]
              return [
                (pixel.r.toInt() - inputMean) / inputStd,
                (pixel.g.toInt() - inputMean) / inputStd,
                (pixel.b.toInt() - inputMean) / inputStd,
              ];
            }
            return [
              pixel.r.toInt().toDouble(),
              pixel.g.toInt().toDouble(),
              pixel.b.toInt().toDouble(),
            ];
          },
        ),
      ),
    );

    return input;
  }

  bool _isMostlyBlank(img.Image image) {
    const int sampleStride = 8;
    int totalSamples = 0;
    int nearWhiteSamples = 0;
    double sumLuma = 0.0;
    double sumLumaSq = 0.0;

    for (int y = 0; y < image.height; y += sampleStride) {
      for (int x = 0; x < image.width; x += sampleStride) {
        final pixel = image.getPixel(x, y);
        final int r = pixel.r.toInt();
        final int g = pixel.g.toInt();
        final int b = pixel.b.toInt();

        final double luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
        sumLuma += luma;
        sumLumaSq += luma * luma;
        totalSamples += 1;

        if (r >= 235 && g >= 235 && b >= 235) {
          nearWhiteSamples += 1;
        }
      }
    }

    if (totalSamples == 0) {
      return false;
    }

    final double meanLuma = sumLuma / totalSamples;
    final double variance = (sumLumaSq / totalSamples) - (meanLuma * meanLuma);
    final double nearWhiteRatio = nearWhiteSamples / totalSamples;

    return nearWhiteRatio >= 0.90 && meanLuma >= 0.92 && variance <= 0.01;
  }

  bool _checkResults(List<dynamic> classes, List<dynamic> scores) {
    try {
      print("🔍 Checking all detections (threshold: $confidenceThreshold)");
      
      // Check ALL detections
      bool weaponFound = false;
      for (int i = 0; i < classes.length && i < scores.length; i++) {
        final score = (scores[i] as num?)?.toDouble() ?? 0.0;
        final classId = (classes[i] as num?)?.toInt() ?? -1;
        
        // Only print detections above a low threshold to reduce noise
        if (score > 0.1) {
          print("   Detection $i: class=$classId, score=${(score * 100).toStringAsFixed(1)}%");
        }
        
        // Check if it's a weapon with high enough confidence
        if (score > confidenceThreshold && classId == weaponClassId) {
          print("🚨 WEAPON DETECTED at index $i with score ${(score * 100).toStringAsFixed(1)}% (class $classId)");
          weaponFound = true;
        }
      }
      
      if (!weaponFound) {
        print("✅ No weapons detected above threshold ${(confidenceThreshold * 100).toStringAsFixed(0)}%");
      }
      
      return weaponFound;
    } catch (e) {
      print("❌ Error checking results: $e");
      return false;
    }
  }

  /// Dispose of the interpreter and free resources
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
    print("🗑️ Weapon detection model disposed");
  }
}
