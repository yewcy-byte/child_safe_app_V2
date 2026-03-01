import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GroomingInferenceResult {
  static const double detectionThreshold = 0.35;

  final List<double> logits;
  final double groomingProbability;

  const GroomingInferenceResult({
    required this.logits,
    required this.groomingProbability,
  });

  bool get isGrooming => groomingProbability >= detectionThreshold;
}

class SafetyModelService {
  SafetyModelService._();

  static final SafetyModelService instance = SafetyModelService._();

  static const MethodChannel _detectorChannel = MethodChannel(
    'com.safetyapp/detector',
  );

  final Queue<String> _recentMessageIds = Queue<String>();
  final Set<String> _recentMessageIdSet = <String>{};
  final Map<String, DateTime> _lastDetectionAtByPackage = <String, DateTime>{};

  static const Duration _detectionCooldown = Duration(seconds: 15);

  bool _initialized = false;
  final Set<String> _keywordList = <String>{
    'nude',
    'nudes',
    'naked',
    'sexy',
    'sex',
  };

  Future<void> initialize() async {
    _initialized = true;
  }

  Future<GroomingInferenceResult?> analyzeText({
    required String packageName,
    required String messageText,
    String? messageId,
  }) async {
    if (messageText.trim().isEmpty) {
      return null;
    }

    await initialize();

    final dedupeId =
        messageId ?? '${packageName}_${messageText.trim().hashCode}';
    if (_isDuplicateMessage(dedupeId)) {
      return null;
    }

    final normalized = _normalizeText(messageText);
    final matchedKeywords = _matchedKeywords(normalized);
    if (matchedKeywords.isNotEmpty && _isInCooldownWindow(packageName)) {
      return null;
    }

    final probability = matchedKeywords.isNotEmpty ? 1.0 : 0.0;

    final result = GroomingInferenceResult(
      logits: <double>[1.0 - probability, probability],
      groomingProbability: probability,
    );

    if (result.isGrooming) {
      _markDetectionNow(packageName);
      await _showLocalNotification(
        packageName: packageName,
        probability: result.groomingProbability,
      );
    }
    return result;
  }

  String _normalizeText(String messageText) {
    final lower = messageText.toLowerCase();
    return lower
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Set<String> _matchedKeywords(String normalizedText) {
    final words = normalizedText
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();
    final matches = <String>{};
    for (final keyword in _keywordList) {
      if (words.contains(keyword)) {
        matches.add(keyword);
      }
    }
    return matches;
  }

  bool _isDuplicateMessage(String messageId) {
    if (_recentMessageIdSet.contains(messageId)) {
      return true;
    }

    _recentMessageIds.addLast(messageId);
    _recentMessageIdSet.add(messageId);

    while (_recentMessageIds.length > 10) {
      final removed = _recentMessageIds.removeFirst();
      _recentMessageIdSet.remove(removed);
    }

    return false;
  }

  bool _isInCooldownWindow(String packageName) {
    final lastDetectedAt = _lastDetectionAtByPackage[packageName];
    if (lastDetectedAt == null) {
      return false;
    }
    return DateTime.now().difference(lastDetectedAt) < _detectionCooldown;
  }

  void _markDetectionNow(String packageName) {
    _lastDetectionAtByPackage[packageName] = DateTime.now();
  }

  Future<void> _showLocalNotification({
    required String packageName,
    required double probability,
  }) async {
    try {
      await _detectorChannel.invokeMethod('showGroomingLocalNotification', {
        'title': 'Child grooming risk detected',
        'body':
            'Potential grooming content found in $packageName. Please review child activity.',
        'packageName': packageName,
        'probability': probability,
      });
    } catch (error) {
      debugPrint('SafetyModelService local notification failed: $error');
    }
  }

  Future<void> dispose() async {
    _initialized = false;
    _lastDetectionAtByPackage.clear();
  }
}
