import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tomato_plant_state.dart';

class TomatoPlantService {
  static const int maxLevels = 5;
  static const int growthMax = 100;
  static const int waterMax = 24;
  static const int violationPenalty = 3;
  static const int exchangeTomatoes = 5;
  static const int exchangeMinutes = 15;

  static const List<String> levelNames = [
    'Seedling',
    'Sprout',
    'Small Plant',
    'Flowering',
    'Ripe',
  ];

  static const List<int> dailyYield = [1, 3, 5, 8, 12];

  final FirebaseFirestore _firestore;

  TomatoPlantService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _docRef(String childId) {
    return _firestore
        .collection('users')
        .doc(childId)
        .collection('gamification')
        .doc('tomatoPlant');
  }

  Stream<TomatoPlantState> watchPlantState(String childId) {
    return _docRef(childId).snapshots().map((snapshot) {
      if (snapshot.data() == null) {
        return TomatoPlantState.initial();
      }
      return TomatoPlantState.fromMap(snapshot.data()!);
    });
  }

  /// Syncs screenTimeAllowanceMinutes from parent-controlled settings to child's plant state.
  /// 
  /// The parent modifies the value at `/users/{childId}/gamification/tomatoPlant` and this
  /// method ensures the child device receives and applies the update immediately.
  /// 
  /// This enables the parent to push screen time updates that take effect instantly on the child device
  /// without requiring the child to manually refresh or restart the app.
  Stream<double> watchScreenTimeAllowance(String childId) {
    return _docRef(childId)
        .snapshots()
        .map((snapshot) {
          if (snapshot.data() == null) {
            return 0.0;
          }
          return (snapshot.data()!['screenTimeAllowanceMinutes'] as num?)?.toDouble() ?? 0.0;
        })
        .distinct();
  }

  Future<TomatoPlantState> ensurePlantState(String childId) async {
    final ref = _docRef(childId);
    final snapshot = await ref.get();
    if (snapshot.data() != null) {
      return TomatoPlantState.fromMap(snapshot.data()!);
    }

    final state = TomatoPlantState.initial();
    await ref.set(state.toMap());
    return state;
  }

  Future<void> syncDailyProgress(String childId) async {
    final ref = _docRef(childId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      var state = snapshot.data() != null
          ? TomatoPlantState.fromMap(snapshot.data()!)
          : TomatoPlantState.initial();

      final now = DateTime.now();
      final todayStart = _dateOnly(now);
      final stateDayStart = _dateOnly(state.dayStart);
      final dayDiff = todayStart.difference(stateDayStart).inDays;

      if (dayDiff <= 0) {
        state = state.copyWith(lastUpdated: now);
        transaction.set(ref, state.toMap(), SetOptions(merge: true));
        return;
      }

      final firstDayWater =
          (waterMax - state.dailyPenaltyPoints).clamp(0, waterMax);
      final extraDays = dayDiff - 1;
      final earnedFromExtraDays = extraDays > 0 ? extraDays * waterMax : 0;
      var updatedGrowth = state.growthPoints + firstDayWater + earnedFromExtraDays;
      var updatedLevel = state.level;

      if (updatedLevel < maxLevels && updatedGrowth >= growthMax) {
        updatedLevel += 1;
        updatedGrowth = 0;
      }

      if (updatedLevel >= maxLevels) {
        updatedLevel = maxLevels;
        updatedGrowth = updatedGrowth.clamp(0, growthMax);
      }

      state = state.copyWith(
        level: updatedLevel,
        growthPoints: updatedGrowth,
        dailyPenaltyPoints: 0,
        dayStart: todayStart,
        lastUpdated: now,
      );

      transaction.set(ref, state.toMap(), SetOptions(merge: true));
    });
  }

  Future<void> deductWater(String childId, {int points = violationPenalty}) async {
    final ref = _docRef(childId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      var state = snapshot.data() != null
          ? TomatoPlantState.fromMap(snapshot.data()!)
          : TomatoPlantState.initial();

      final safePoints = points <= 0 ? 0 : points;

      final now = DateTime.now();
      final todayStart = _dateOnly(now);
      final stateDayStart = _dateOnly(state.dayStart);
      if (todayStart.isAfter(stateDayStart)) {
        final firstDayWater =
            (waterMax - state.dailyPenaltyPoints).clamp(0, waterMax);
        var updatedGrowth = state.growthPoints + firstDayWater;
        var updatedLevel = state.level;

        if (updatedLevel < maxLevels && updatedGrowth >= growthMax) {
          updatedLevel += 1;
          updatedGrowth = 0;
        }

        state = state.copyWith(
          level: updatedLevel,
          growthPoints: updatedGrowth,
          dailyPenaltyPoints: 0,
          dayStart: todayStart,
        );
      }

      final remainingWaterCapacity = (waterMax - state.dailyPenaltyPoints).clamp(0, waterMax);
      final waterPenalty = safePoints.clamp(0, remainingWaterCapacity);
      final growthPenalty = safePoints - waterPenalty;

      final updatedPenalty =
          (state.dailyPenaltyPoints + waterPenalty).clamp(0, waterMax);

      var updatedLevel = state.level;
      var updatedGrowth = state.growthPoints;
      var remainingGrowthPenalty = growthPenalty;

      while (remainingGrowthPenalty > 0) {
        if (updatedGrowth > 0) {
          final applied = remainingGrowthPenalty < updatedGrowth
              ? remainingGrowthPenalty
              : updatedGrowth;
          updatedGrowth -= applied;
          remainingGrowthPenalty -= applied;
          continue;
        }

        if (updatedLevel <= 1) {
          break;
        }

        updatedLevel -= 1;
        updatedGrowth = growthMax;
      }

      state = state.copyWith(
        level: updatedLevel,
        growthPoints: updatedGrowth,
        dailyPenaltyPoints: updatedPenalty,
        lastUpdated: now,
      );

      transaction.set(ref, state.toMap(), SetOptions(merge: true));
    });
  }

  Future<bool> harvestTomatoes(String childId) async {
    final ref = _docRef(childId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      var state = snapshot.data() != null
          ? TomatoPlantState.fromMap(snapshot.data()!)
          : TomatoPlantState.initial();

      final now = DateTime.now();
      final today = _dateOnly(now);
      final lastHarvest = _dateOnly(state.lastHarvestDate);
      if (_isSameDay(today, lastHarvest)) {
        return false;
      }

      final levelIndex = (state.level - 1).clamp(0, dailyYield.length - 1);
      final updatedTomatoes = state.tomatoes + dailyYield[levelIndex];

      state = state.copyWith(
        tomatoes: updatedTomatoes,
        lastHarvestDate: now,
        lastUpdated: now,
      );

      transaction.set(ref, state.toMap(), SetOptions(merge: true));
      return true;
    });
  }

  Future<bool> exchangeTomatoesForScreenTime(String childId) async {
    final ref = _docRef(childId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      var state = snapshot.data() != null
          ? TomatoPlantState.fromMap(snapshot.data()!)
          : TomatoPlantState.initial();

      if (state.tomatoes < exchangeTomatoes) {
        return false;
      }

      state = state.copyWith(
        tomatoes: state.tomatoes - exchangeTomatoes,
        screenTimeAllowanceMinutes:
            state.screenTimeAllowanceMinutes + exchangeMinutes,
        lastUpdated: DateTime.now(),
      );

      transaction.set(ref, state.toMap(), SetOptions(merge: true));
      return true;
    });
  }

  int calculateWaterPoints(TomatoPlantState state, DateTime now) {
    final todayStart = _dateOnly(now);
    // New rule: fixed daily bucket starts full at day start and only decreases by penalties.
    if (todayStart.isAfter(_dateOnly(state.dayStart))) {
      return waterMax;
    }

    return (waterMax - state.dailyPenaltyPoints).clamp(0, waterMax);
  }

  Duration timeUntilDayReset(DateTime now) {
    final nextDay = _dateOnly(now).add(const Duration(days: 1));
    return nextDay.difference(now);
  }

  String levelName(int level) {
    final index = (level - 1).clamp(0, levelNames.length - 1);
    return levelNames[index];
  }

  int dailyTomatoYield(int level) {
    final index = (level - 1).clamp(0, dailyYield.length - 1);
    return dailyYield[index];
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
