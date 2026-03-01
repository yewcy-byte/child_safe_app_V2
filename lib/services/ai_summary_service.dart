import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AISummaryService {
  AISummaryService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DateTime _startOfCurrentWeek(DateTime value) {
    final dateOnly = DateTime(value.year, value.month, value.day);
    return dateOnly.subtract(Duration(days: dateOnly.weekday - DateTime.monday));
  }

  DateTime _endOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  DateTime? _readDate(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  Map<String, dynamic> _buildWeekScreenTimeData({
    required Map<String, dynamic> raw,
    required DateTime weekStart,
    required DateTime now,
  }) {
    final entries = <Map<String, dynamic>>[];
    final last7Days = raw['last7Days'];
    if (last7Days is List) {
      for (final item in last7Days.whereType<Map>()) {
        final row = item.cast<String, dynamic>();
        final date = _readDate(row['date']);
        if (date == null) {
          continue;
        }

        final day = DateTime(date.year, date.month, date.day);
        if (day.isBefore(weekStart) || day.isAfter(now)) {
          continue;
        }

        entries.add({
          'date': _formatDate(day),
          'minutes': (row['minutes'] as num?)?.toInt() ?? 0,
        });
      }
    }

    final totalWeekMinutes = entries.fold<int>(
      0,
      (totalMinutes, entry) => totalMinutes + ((entry['minutes'] as int?) ?? 0),
    );

    final elapsedDays = now.difference(weekStart).inDays + 1;
    final averageDailyMinutes = elapsedDays > 0
        ? totalWeekMinutes / elapsedDays
        : 0.0;

    return {
      'weekWindow': {
        'startDate': _formatDate(weekStart),
        'endDate': _formatDate(now),
      },
      'days': entries,
      'totalWeekMinutes': totalWeekMinutes,
      'averageDailyMinutesWeekToDate': averageDailyMinutes,
    };
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> generateChildSafetySummary(
    String childId, {
    Duration cooldown = const Duration(minutes: 15),
  }
  ) {
    return Stream.fromFuture(
      _createSummaryDoc(childId, cooldown: cooldown),
    ).where((docRef) => docRef != null).cast<DocumentReference<Map<String, dynamic>>>().asyncExpand(
      (docRef) => docRef.snapshots(),
    );
  }

  Future<DocumentReference<Map<String, dynamic>>> startConsultantSession({
    String? childId,
    String? childName,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    final prompt = await _buildSessionPrompt(
      childId: childId,
      childName: childName,
    );

    return _firestore.collection('users').doc(userId).collection('chat').add({
      'prompt': prompt,
      'basePrompt': prompt,
      'messages': <Map<String, dynamic>>[],
      'createTime': FieldValue.serverTimestamp(),
      'role': 'user',
      'childId': ?childId,
      'childName': ?childName,
      'requestType': 'ai_consultant_session',
      'status': {'state': 'PENDING'},
    });
  }

  Future<String> _buildSessionPrompt({
    String? childId,
    String? childName,
  }) async {
    if (childId == null || childId.isEmpty) {
      return _buildGeneralConsultantPrompt(childName: childName);
    }

    final now = DateTime.now();
    final weekStart = _startOfCurrentWeek(now);
    final weekEnd = _endOfDay(now);

    final appUsageFuture = _firestore
        .collection('users')
        .doc(childId)
        .collection('appUsage')
        .doc('current')
        .get();

    final detectionsFuture = _firestore
        .collection('users')
        .doc(childId)
        .collection('detections')
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
      .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(weekEnd))
        .orderBy('timestamp', descending: true)
        .limit(25)
        .get();

    final screenTimeFuture = _firestore
        .collection('users')
        .doc(childId)
        .collection('screenTime')
        .doc('current')
        .get();

    final results = await Future.wait([
      appUsageFuture,
      detectionsFuture,
      screenTimeFuture,
    ]);

    final appUsageDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final detectionsSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final screenTimeDoc = results[2] as DocumentSnapshot<Map<String, dynamic>>;

    final appUsageData = appUsageDoc.data() ?? <String, dynamic>{};
    final screenTimeDataRaw = screenTimeDoc.data() ?? <String, dynamic>{};
    final detectionsData = detectionsSnapshot.docs
        .map((doc) => doc.data())
        .toList(growable: false);
    final screenTimeData = _buildWeekScreenTimeData(
      raw: screenTimeDataRaw,
      weekStart: weekStart,
      now: now,
    );

    return _buildConsultantPrompt(
      appUsageData: appUsageData,
      detectionsData: detectionsData,
      screenTimeData: screenTimeData,
      weekStart: weekStart,
      weekEnd: now,
    );
  }

  Future<void> sendConsultantMessage({
    required String sessionId,
    required String message,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    final sessionRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('chat')
        .doc(sessionId);

    final sessionSnapshot = await sessionRef.get();
    final data = sessionSnapshot.data() ?? <String, dynamic>{};

    final basePrompt = (data['basePrompt'] as String?)?.trim().isNotEmpty == true
        ? data['basePrompt'] as String
        : (data['prompt'] as String?)?.trim() ?? '';

    final rawMessages = data['messages'];
    final existingMessages = rawMessages is List
        ? rawMessages.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final response = (data['response'] as String?)?.trim() ?? '';
    if (response.isNotEmpty) {
      final lastMessage = existingMessages.isNotEmpty
          ? existingMessages.last
          : null;
      final lastRole = lastMessage?['role'] as String?;
      final lastContent = lastMessage?['content'] as String?;
      if (lastRole != 'assistant' || lastContent != response) {
        existingMessages.add({
          'role': 'assistant',
          'content': response,
        });
      }
    }

    existingMessages.add({
      'role': 'user',
      'content': message,
    });

    final prompt = _buildFollowUpPrompt(
      basePrompt: basePrompt,
      messages: existingMessages,
    );

    await sessionRef.update({
      'messages': existingMessages,
      'prompt': prompt,
      'response': '',
      'status': {'state': 'PENDING'},
      'updatedAt': FieldValue.serverTimestamp(),
      'role': 'user',
    });
  }

  String _buildConsultantPrompt({
    required Map<String, dynamic> appUsageData,
    required List<Map<String, dynamic>> detectionsData,
    required Map<String, dynamic> screenTimeData,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) {
    return '''You are a child safety AI consultant. Provide a concise safety summary, highlight risks, trends, and actionable next steps. Use clear headings and bullet points.

IMPORTANT: When parents request control actions (like setting time limits or blocking apps), execute them using this format:
<action>{"type":"set_app_time_limit", "packageName":"...", "appName":"...", "minutes":number}</action>

Available actions:
- set_app_time_limit: {"type":"set_app_time_limit", "packageName":"...", "appName":"...", "minutes":number}
- set_daily_screen_limit: {"type":"set_daily_screen_limit", "screenTimeMinutes":number}
- block_app: {"type":"block_app", "packageName":"...", "appName":"..."}
- add_reward: {"type":"add_reward", "rewardText":"..."}
- unblock_app: {"type":"unblock_app", "packageName":"..."}

Child Data:
Time Scope: THIS WEEK ONLY (${_formatDate(weekStart)} to ${_formatDate(weekEnd)}; Monday to today)
App Usage (current snapshot): $appUsageData
Detections (this week only): $detectionsData
Screen Time (this week only): $screenTimeData

Use only this week's data when analyzing trends or giving recommendations. If the parent requests an action, proceed with the action and confirm it in your response.''';
  }

  String _buildGeneralConsultantPrompt({String? childName}) {
    final contextLabel = childName != null && childName.trim().isNotEmpty
        ? 'child $childName'
        : 'the child in question';

    return '''You are a child safety AI consultant. Answer parent questions with clear, actionable guidance. Ask for missing context when needed, and focus on safety, healthy habits, and appropriate next steps for $contextLabel.

IMPORTANT: You can execute control actions when parents request them. When a parent asks you to perform an action (like setting a time limit, blocking an app, or adding a reward), respond positively and include the action in this exact format:

<action>{"type":"set_app_time_limit", "packageName":"com.example.app", "appName":"App Name", "minutes":30}</action>

Available actions:
- set_app_time_limit: {"type":"set_app_time_limit", "packageName":"...", "appName":"...", "minutes":number}
- set_daily_screen_limit: {"type":"set_daily_screen_limit", "screenTimeMinutes":number}
- block_app: {"type":"block_app", "packageName":"...", "appName":"..."}
- add_reward: {"type":"add_reward", "rewardText":"..."}
- unblock_app: {"type":"unblock_app", "packageName":"..."}

Always respond conversationally AFTER the action tag. Example:
"Sure! I'll set the game app time limit to 30 minutes. <action>{"type":"set_app_time_limit", "packageName":"com.game", "appName":"Game App", "minutes":30}</action> This should help your child balance their gaming time."''';
  }

  String _buildFollowUpPrompt({
    required String basePrompt,
    required List<Map<String, dynamic>> messages,
  }) {
    final recentMessages = messages.length > 12
        ? messages.sublist(messages.length - 12)
        : messages;

    final history = recentMessages
        .map((entry) {
          final role = (entry['role'] as String?)?.trim().toLowerCase();
          final content = (entry['content'] as String?)?.trim();
          if (role == null || content == null || content.isEmpty) {
            return null;
          }
          final label = role == 'assistant' ? 'Assistant' : 'User';
          return '$label: $content';
        })
        .whereType<String>()
        .join('\n');

    if (history.isEmpty) {
      return basePrompt;
    }

    return '$basePrompt\n\nConversation so far:\n$history\n\nRespond to the latest user question with clear, actionable guidance.';
  }

  Future<DocumentReference<Map<String, dynamic>>?> _createSummaryDoc(
    String childId, {
    required Duration cooldown,
  }
  ) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('No authenticated user found.');
    }

    final hasRecentSummary = await _hasRecentSummaryRequest(
      userId: userId,
      childId: childId,
      cooldown: cooldown,
    );
    if (hasRecentSummary) {
      return null;
    }

    final appUsageFuture = _firestore
        .collection('users')
        .doc(childId)
        .collection('appUsage')
        .doc('current')
        .get();

    final detectionsFuture = _firestore
        .collection('users')
        .doc(childId)
        .collection('detections')
        .get();

    final screenTimeFuture = _firestore
        .collection('users')
        .doc(childId)
        .collection('screenTime')
        .doc('current')
        .get();

    final results = await Future.wait([
      appUsageFuture,
      detectionsFuture,
      screenTimeFuture,
    ]);

    final appUsageDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final detectionsSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final screenTimeDoc = results[2] as DocumentSnapshot<Map<String, dynamic>>;

    final appUsageData = appUsageDoc.data() ?? <String, dynamic>{};
    final screenTimeData = screenTimeDoc.data() ?? <String, dynamic>{};
    final detectionsData = detectionsSnapshot.docs
        .map((doc) => doc.data())
        .toList(growable: false);

 final summaryPrompt = 
    'Analyze this data and provide a summary according to your safety consultant guidelines: '
    'App Usage: $appUsageData, '
    'Detections: $detectionsData, '
    'Screen Time: $screenTimeData.';

    return _firestore.collection('users').doc(userId).collection('chat').add({
      'prompt': summaryPrompt,
      'createTime': FieldValue.serverTimestamp(),
      'role': 'user',
      'childId': childId,
      'requestType': 'child_safety_summary',
    });
  }

  Future<bool> _hasRecentSummaryRequest({
    required String userId,
    required String childId,
    required Duration cooldown,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('chat')
        .orderBy('createTime', descending: true)
        .limit(50)
        .get();

    final now = DateTime.now();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final isSummary = data['requestType'] == 'child_safety_summary';
      final sameChild = data['childId'] == childId;
      if (!isSummary || !sameChild) {
        continue;
      }

      final timestamp = data['createTime'] as Timestamp?;
      if (timestamp == null) {
        continue;
      }

      final elapsed = now.difference(timestamp.toDate());
      return elapsed < cooldown;
    }

    return false;
  }
}
