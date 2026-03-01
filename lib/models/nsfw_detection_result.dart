/// Result of NSFW content detection
class NSFWDetectionResult {
  final double pornScore;
  final double sexyScore;
  final double neutralScore;
  final double drawingScore;
  final double hentaiScore;

  /// Threshold for porn detection
  static const double pornThreshold = 0.7;
  
  /// Threshold for violence (using combined heuristics)
  static const double violenceThreshold = 0.6;

  const NSFWDetectionResult({
    required this.pornScore,
    required this.sexyScore,
    required this.neutralScore,
    required this.drawingScore,
    required this.hentaiScore,
  });

  /// Create from flutter_nsfw result map
  factory NSFWDetectionResult.fromMap(Map<dynamic, dynamic> map) {
    return NSFWDetectionResult(
      pornScore: _parseScore(map['porn']),
      sexyScore: _parseScore(map['sexy']),
      neutralScore: _parseScore(map['neutral']),
      drawingScore: _parseScore(map['drawing']),
      hentaiScore: _parseScore(map['hentai']),
    );
  }

  static double _parseScore(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Whether content is flagged as pornographic
  bool get isPorn => pornScore >= pornThreshold || hentaiScore >= pornThreshold;

  /// Whether content may be violent (heuristic-based)
  /// Note: nsfw.tflite doesn't directly detect violence, this is a placeholder
  bool get isViolent => false; // TODO: Integrate violence detection model

  /// Whether content is safe
  bool get isSafe => !isPorn && !isViolent;

  @override
  String toString() {
    return 'NSFWDetectionResult(porn: ${pornScore.toStringAsFixed(2)}, '
           'sexy: ${sexyScore.toStringAsFixed(2)}, '
           'neutral: ${neutralScore.toStringAsFixed(2)}, '
           'hentai: ${hentaiScore.toStringAsFixed(2)})';
  }
}