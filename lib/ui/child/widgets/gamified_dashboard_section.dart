import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../../models/tomato_plant_state.dart';
import '../../../services/tomato_plant_service.dart';
import '../../shared/shared.dart';

class GamifiedDashboardSection extends StatefulWidget {
  final String childId;

  const GamifiedDashboardSection({super.key, required this.childId});

  @override
  State<GamifiedDashboardSection> createState() =>
      _GamifiedDashboardSectionState();
}

class _GamifiedDashboardSectionState extends State<GamifiedDashboardSection>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final TomatoPlantService _service = TomatoPlantService();
  static const MethodChannel _screenChannel = MethodChannel(
    'com.childsafe.app/screen_capture',
  );
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int? _liveTodayUsageSeconds;
  late final AudioPlayer _audioPlayer;
  late final AnimationController _popController;
  late final Animation<double> _popAnimation;
  double _lastScreenTimeAllowance = 0.0;
  StreamSubscription<double>? _screenTimeSubscription;
  Offset? _plantPointerDownPosition;
  int? _plantPointerDownAtMs;
  bool _plantPointerExceededTapSlop = false;
  int _activePlantPointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _audioPlayer = AudioPlayer();
    _popAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _popController, curve: Curves.easeOutBack),
    );

    _service.ensurePlantState(widget.childId);
    _service.syncDailyProgress(widget.childId);
    _refreshTodayUsageSeconds();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshTodayUsageSeconds();
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });

    // Listen for parent-initiated screen time allowance changes and notify child
    _screenTimeSubscription = _service
        .watchScreenTimeAllowance(widget.childId)
        .listen((allowance) {
          if (_lastScreenTimeAllowance > 0 &&
              allowance != _lastScreenTimeAllowance &&
              mounted) {
            final difference = allowance - _lastScreenTimeAllowance;
            final change = difference > 0 ? '+' : '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Screen time updated: $change${difference.toStringAsFixed(0)} minutes',
                  style: AppTextStyles.bodyMedium(
                    context,
                  ).copyWith(color: Colors.white),
                ),
                backgroundColor: difference > 0
                    ? Colors.green[700]
                    : Colors.orange[700],
                duration: const Duration(seconds: 2),
              ),
            );
          }
          _lastScreenTimeAllowance = allowance;
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _service.syncDailyProgress(widget.childId);
      _refreshTodayUsageSeconds();
      setState(() {
        _now = DateTime.now();
      });
    }
  }

  Future<void> _refreshTodayUsageSeconds() async {
    try {
      final liveTotalSeconds = await _screenChannel.invokeMethod<dynamic>(
        'getTodayTotalUsageSeconds',
      );
      final parsed = liveTotalSeconds is num
          ? liveTotalSeconds.toInt()
          : int.tryParse('$liveTotalSeconds');
      if (parsed == null || !mounted) {
        return;
      }
      final safeValue = max(0, parsed);
      if (_liveTodayUsageSeconds != safeValue) {
        setState(() {
          _liveTodayUsageSeconds = safeValue;
        });
      }
    } catch (_) {
      // Keep fallback behavior when live usage is unavailable.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _audioPlayer.dispose();
    _popController.dispose();
    _screenTimeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleHarvest() async {
    _popController.forward(from: 0);
    try {
      await _audioPlayer.play(AssetSource('audio/plant_pop.mp3'));
    } catch (_) {
      // Ignore sound errors to keep interaction responsive.
    }
    await _service.harvestTomatoes(widget.childId);
  }

  void _onPlantPointerDown(PointerDownEvent event) {
    _activePlantPointers += 1;
    if (_activePlantPointers == 1) {
      _plantPointerDownPosition = event.position;
      _plantPointerDownAtMs = DateTime.now().millisecondsSinceEpoch;
      _plantPointerExceededTapSlop = false;
      return;
    }
    _plantPointerExceededTapSlop = true;
  }

  void _onPlantPointerMove(PointerMoveEvent event) {
    if (_activePlantPointers != 1) {
      _plantPointerExceededTapSlop = true;
      return;
    }

    final down = _plantPointerDownPosition;
    if (down == null) return;

    final movedDistance = (event.position - down).distance;
    if (movedDistance > 12) {
      _plantPointerExceededTapSlop = true;
    }
  }

  void _onPlantPointerUp(PointerUpEvent event) {
    if (_activePlantPointers == 1) {
      final down = _plantPointerDownPosition;
      final downAt = _plantPointerDownAtMs;
      final upAt = DateTime.now().millisecondsSinceEpoch;

      if (down != null &&
          downAt != null &&
          !_plantPointerExceededTapSlop &&
          (upAt - downAt) <= 300 &&
          (event.position - down).distance <= 12) {
        _handleHarvest();
      }
    }

    _activePlantPointers = (_activePlantPointers - 1).clamp(0, 10);
    if (_activePlantPointers == 0) {
      _plantPointerDownPosition = null;
      _plantPointerDownAtMs = null;
      _plantPointerExceededTapSlop = false;
    }
  }

  void _onPlantPointerCancel(PointerCancelEvent event) {
    _activePlantPointers = (_activePlantPointers - 1).clamp(0, 10);
    if (_activePlantPointers == 0) {
      _plantPointerDownPosition = null;
      _plantPointerDownAtMs = null;
      _plantPointerExceededTapSlop = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TomatoPlantState>(
      stream: _service.watchPlantState(widget.childId),
      builder: (context, snapshot) {
        final state = snapshot.data ?? TomatoPlantState.initial();
        final waterPoints = _service.calculateWaterPoints(state, _now);
        final waterProgress = waterPoints / TomatoPlantService.waterMax;
        final growthProgress =
            state.growthPoints / TomatoPlantService.growthMax;
        final timeLeft = _service.timeUntilDayReset(_now);
        final timeLabel = _formatDuration(timeLeft);
        final levelName = _service.levelName(state.level);
        final dailyYield = _service.dailyTomatoYield(state.level);

        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: AppSpacing.paddingMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today\'s Garden',
                  style: AppTextStyles.titleMedium(context).copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        offset: Offset(2, 2),
                        blurRadius: 4.0,
                        color: Colors.black87,
                      ),
                      Shadow(
                        offset: Offset(-1, -1),
                        blurRadius: 4.0,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapSm,
                _buildWaterSection(
                  context,
                  waterProgress,
                  waterPoints,
                  timeLabel,
                ),
                AppSpacing.gapMd,
                Center(
                  child: Image.asset(
                    'assets/images/warningCard.png',
                    width: MediaQuery.of(context).size.width * 0.85,
                    fit: BoxFit.contain,
                  ),
                ),
                AppSpacing.gapMd,
                Center(
                  child: ScaleTransition(
                    scale: _popAnimation,
                    child: _buildPlantModel(context, state.level, levelName),
                  ),
                ),
                AppSpacing.gapMd,
                _buildGrowthSection(
                  context,
                  growthProgress,
                  state.growthPoints,
                  levelName,
                ),
                AppSpacing.gapMd,
                _buildTomatoSection(context, state.tomatoes, dailyYield),
                AppSpacing.gapSm,
                _buildExchangeSection(
                  context,
                  state.tomatoes,
                  state.screenTimeAllowanceMinutes,
                  state.bonusMinutes,
                  state.dayStart,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlantModel(BuildContext context, int level, String levelName) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final plantSize = (screenWidth * 0.85).clamp(250.0, screenHeight * 0.5);
    // Full Flutter asset path
    final modelAssetPath = 'assets/images/plants/level_$level.glb';

    debugPrint('🌱 ModelViewer loading: $modelAssetPath (width=$plantSize)');

    return Column(
      children: [
        Container(
          width: plantSize,
          height: plantSize,
          decoration: BoxDecoration(
            color: Colors.grey[900]?.withOpacity(0.4),
            borderRadius: BorderRadius.circular(AppSpacing.lg),
          ),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPlantPointerDown,
            onPointerMove: _onPlantPointerMove,
            onPointerUp: _onPlantPointerUp,
            onPointerCancel: _onPlantPointerCancel,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.lg),
              child: Padding(
                padding: AppSpacing.paddingMd,
                child: ModelViewer(
                  src: modelAssetPath,
                  alt: levelName,
                  autoRotate: false,
                  cameraControls: true,
                  exposure: 1.0,
                ),
              ),
            ),
          ),
        ),
        AppSpacing.gapSm,
        Text(
          levelName,
          style: AppTextStyles.titleSmall(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 3.0,
                color: Colors.black.withOpacity(0.7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaterSection(
    BuildContext context,
    double progress,
    int points,
    String timeLabel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Daily Water',
              style: AppTextStyles.labelLarge(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3.0,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              '$points/${TomatoPlantService.waterMax}',
              style: AppTextStyles.labelLarge(context).copyWith(
                color: Colors.lightBlue,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3.0,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
          ],
        ),
        AppSpacing.gapSm,
        LinearProgressIndicator(
          value: progress.clamp(0, 1),
          minHeight: AppSpacing.xs,
          backgroundColor: Colors.white.withOpacity(0.3),
          valueColor: AlwaysStoppedAnimation<Color>(Colors.lightBlue),
        ),
        AppSpacing.gapSm,
        Text(
          '$timeLabel left today',
          style: AppTextStyles.bodySmall(context).copyWith(
            color: Colors.white,
            shadows: [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 2.0,
                color: Colors.black87,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrowthSection(
    BuildContext context,
    double progress,
    int growthPoints,
    String levelName,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Plant Growth',
              style: AppTextStyles.labelLarge(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3.0,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              '$growthPoints/${TomatoPlantService.growthMax}',
              style: AppTextStyles.labelLarge(context).copyWith(
                color: Colors.lightGreen,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3.0,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
          ],
        ),
        AppSpacing.gapSm,
        LinearProgressIndicator(
          value: progress.clamp(0, 1),
          minHeight: AppSpacing.xs,
          backgroundColor: Colors.white.withOpacity(0.3),
          valueColor: AlwaysStoppedAnimation<Color>(Colors.lightGreen),
        ),
        AppSpacing.gapSm,
        Text(
          'Level: $levelName',
          style: AppTextStyles.bodySmall(context).copyWith(
            color: Colors.white,
            shadows: [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 2.0,
                color: Colors.black87,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTomatoSection(
    BuildContext context,
    int tomatoes,
    int dailyYield,
  ) {
    return Row(
      children: [
        Image.asset('assets/images/tomatoIcon.png', width: 32, height: 32),
        AppSpacing.gapSm,
        Expanded(
          child: Text(
            '$tomatoes Tomatoes',
            style: AppTextStyles.titleMedium(context).copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 28,
              color: Colors.white,
              shadows: [
                Shadow(
                  offset: Offset(1, 1),
                  blurRadius: 3.0,
                  color: Colors.black87,
                ),
              ],
            ),
          ),
        ),
        Text(
          '+$dailyYield/day',
          style: AppTextStyles.bodySmall(context).copyWith(
            color: Colors.white,
            shadows: [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 2.0,
                color: Colors.black87,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExchangeSection(
    BuildContext context,
    int tomatoes,
    double screenTimeAllowanceMinutes,
    double bonusMinutes,
    DateTime dayStart,
  ) {
    final remainingSeconds = _calculateRemainingScreenTimeSeconds(
      allowanceMinutes: screenTimeAllowanceMinutes,
      bonusMinutes: bonusMinutes,
      dayStart: dayStart,
      liveUsageSeconds: _liveTodayUsageSeconds,
    );
    final remainingTime = _formatSecondsToMinutesSeconds(remainingSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Remaining Screen Time',
              style: AppTextStyles.labelLarge(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3.0,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              remainingTime,
              style: AppTextStyles.labelLarge(context).copyWith(
                color: remainingSeconds <= 0 ? Colors.red : Colors.amber,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3.0,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  int _calculateRemainingScreenTimeSeconds({
    required double allowanceMinutes,
    required double bonusMinutes,
    required DateTime dayStart,
    int? liveUsageSeconds,
  }) {
    final now = DateTime.now();
    final totalAllowanceSeconds = ((allowanceMinutes + bonusMinutes) * 60)
        .round();
    final elapsedSeconds =
        liveUsageSeconds ?? now.difference(dayStart).inSeconds;
    return max(0, totalAllowanceSeconds - elapsedSeconds);
  }

  String _formatSecondsToMinutesSeconds(int totalSeconds) {
    final remainingSeconds = max(0, totalSeconds);
    final mins = remainingSeconds ~/ 60;
    final secs = remainingSeconds % 60;

    return '${mins}m ${secs}s';
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = max(0, duration.inMinutes);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  String _formatScreenTime(double minutes) {
    final totalSeconds = (minutes * 60).toInt();
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins}m ${secs}s';
  }
}
