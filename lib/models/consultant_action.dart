/// Model representing an AI consultant action to execute
class ConsultantAction {
  final String type;
  final String childId;
  final Map<String, dynamic> parameters;

  ConsultantAction({
    required this.type,
    required this.childId,
    required this.parameters,
  });

  /// Parse action from AI response format: <action>{"type":"...", "childId":"...", "parameters":{...}}</action>
  static ConsultantAction? tryParse(String responseText, String defaultChildId) {
    const actionStart = '<action>';
    const actionEnd = '</action>';

    final startIdx = responseText.indexOf(actionStart);
    final endIdx = responseText.indexOf(actionEnd);

    if (startIdx == -1 || endIdx == -1 || startIdx >= endIdx) {
      return null;
    }

    try {
      final jsonStr = responseText.substring(startIdx + actionStart.length, endIdx).trim();
      // Simple JSON parsing - in production, use json decode
      final isValidJson = jsonStr.startsWith('{') && jsonStr.endsWith('}');
      if (!isValidJson) return null;

      // Extract type
      final typeMatch = RegExp(r'"type"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      if (typeMatch == null) return null;
      final type = typeMatch.group(1)!;

      // For simplicity, return a basic action object
      // In production, you'd properly parse the JSON
      return ConsultantAction(
        type: type,
        childId: defaultChildId,
        parameters: _parseJsonString(jsonStr) ?? {},
      );
    } catch (e) {
      return null;
    }
  }

  /// Extract response without action tags
  static String cleanResponse(String responseText) {
    const actionStart = '<action>';
    const actionEnd = '</action>';

    final startIdx = responseText.indexOf(actionStart);
    final endIdx = responseText.indexOf(actionEnd);

    if (startIdx == -1 || endIdx == -1) {
      return responseText;
    }

    return responseText.replaceRange(startIdx, endIdx + actionEnd.length, '').trim();
  }

  static Map<String, dynamic>? _parseJsonString(String jsonStr) {
    try {
      // Extract key-value pairs from JSON string
      final result = <String, dynamic>{};

      // Simple pattern matching for common fields
      final typeMatch = RegExp(r'"type"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      if (typeMatch != null) result['type'] = typeMatch.group(1);

      final packageMatch = RegExp(r'"packageName"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      if (packageMatch != null) result['packageName'] = packageMatch.group(1);

      final appNameMatch = RegExp(r'"appName"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      if (appNameMatch != null) result['appName'] = appNameMatch.group(1);

      final minutesMatch = RegExp(r'"minutes"\s*:\s*(\d+)').firstMatch(jsonStr);
      if (minutesMatch != null) result['minutes'] = int.parse(minutesMatch.group(1)!);

      final screenTimeMatch = RegExp(r'"screenTimeMinutes"\s*:\s*(\d+)').firstMatch(jsonStr);
      if (screenTimeMatch != null) result['screenTimeMinutes'] = int.parse(screenTimeMatch.group(1)!);

      final rewardMatch = RegExp(r'"rewardText"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      if (rewardMatch != null) result['rewardText'] = rewardMatch.group(1);

      return result.isEmpty ? null : result;
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() => 'ConsultantAction(type: $type, childId: $childId, parameters: $parameters)';
}
