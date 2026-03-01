import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../models/location_model.dart';
import '../../../models/child_model.dart';
import '../../../services/location_tracking_service.dart';
import '../../../services/parent_children_service.dart';
import '../../shared/shared.dart';

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final LocationTrackingService _locationService = LocationTrackingService();
  final ParentChildrenService _childrenService = ParentChildrenService();

  GoogleMapController? _mapController;
  final Map<String, StreamSubscription<LocationModel?>> _locationSubscriptions =
      {};
  final Map<String, LocationModel?> _childrenLocations = {};
  final Map<String, ChildModel> _children = {};
  StreamSubscription<List<ChildModel>>? _childrenSubscription;

  bool _isLoading = true;
  bool _isCheckingAllLocations = false;
  String? _error;

  // Default map center (will be updated based on children locations)
  LatLng _mapCenter = const LatLng(
    37.7749,
    -122.4194,
  ); // San Francisco as default

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  @override
  void dispose() {
    _childrenSubscription?.cancel();
    _childrenSubscription = null;
    _cancelAllSubscriptions();
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }

  void _cancelAllSubscriptions() {
    for (final subscription in _locationSubscriptions.values) {
      subscription.cancel();
    }
    _locationSubscriptions.clear();
  }

  Future<void> _loadChildren() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Listen to children list
      _childrenSubscription?.cancel();
      _childrenSubscription = _childrenService.watchChildren(user.uid).listen((children) {
        setState(() {
          _children.clear();
          for (final child in children) {
            _children[child.id] = child;
          }
        });

        // Subscribe to location updates for each child
        _subscribeToChildrenLocations(children);
      });

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _subscribeToChildrenLocations(List<ChildModel> children) {
    // Cancel existing subscriptions (no longer needed with on-demand approach)
    _cancelAllSubscriptions();

    // Start with no markers shown. Locations are only populated after
    // explicit "Check Locations" action succeeds.
    setState(() {
      _childrenLocations.clear();
      _mapCenter = const LatLng(37.7749, -122.4194);
    });
  }

  Future<void> _checkAllChildrenLocationsNow() async {
    setState(() => _isCheckingAllLocations = true);

    try {
      int successCount = 0;
      int totalCount = _children.length;

      for (final child in _children.values) {
        try {
          final location =
              await _locationService.fetchAndUploadChildLocationNow(child.id);
          if (mounted) {
            setState(() {
              _childrenLocations[child.id] = location;
              if (location != null) successCount++;
            });
          }
        } catch (e) {
          debugPrint('Error checking location for ${child.id}: $e');
        }
      }

      if (mounted) {
        await _safeAnimate(CameraUpdate.newLatLngZoom(_mapCenter, 12));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated $successCount of $totalCount children',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking locations: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingAllLocations = false);
      }
    }
  }

  void _updateMapCenter() {
    // Find the first available location
    for (final location in _childrenLocations.values) {
      if (location != null) {
        _mapCenter = LatLng(location.latitude, location.longitude);
        _safeAnimate(CameraUpdate.newLatLngZoom(_mapCenter, 12));
        break;
      }
    }
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    _childrenLocations.forEach((childId, location) {
      if (location != null) {
        final child = _children[childId];
        final childName = child?.name ?? 'Unknown Child';

        markers.add(
          Marker(
            markerId: MarkerId(childId),
            position: LatLng(location.latitude, location.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(_getMarkerHue(childId)),
            infoWindow: InfoWindow(
              title: childName,
              snippet: _formatLocationInfo(location),
            ),
            onTap: () => _showLocationDetails(child, location),
          ),
        );
      }
    });

    return markers;
  }

  double _getMarkerHue(String childId) {
    // Generate consistent color for each child based on their ID
    final hash = childId.hashCode.abs();
    return (hash % 360).toDouble();
  }

  String _formatLocationInfo(LocationModel location) {
    final timeAgo = _getTimeAgo(location.timestamp);
    final accuracy = location.accuracy?.toStringAsFixed(0) ?? 'N/A';
    return 'Updated $timeAgo\nAccuracy: ±${accuracy}m';
  }

  String _getTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  void _showLocationDetails(ChildModel? child, LocationModel location) {
    if (child == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: AppSpacing.paddingLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary(context),
                  child: Text(
                    child.name[0].toUpperCase(),
                    style: AppTextStyles.titleLarge(
                      context,
                    )?.copyWith(color: AppColors.onPrimary(context)),
                  ),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.name,
                        style: AppTextStyles.titleLarge(context),
                      ),
                      Text(
                        'Last updated: ${_getTimeAgo(location.timestamp)}',
                        style: AppTextStyles.bodySmall(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            AppSpacing.gapLg,
            _buildLocationInfoRow(
              icon: Icons.location_on,
              label: 'Coordinates',
              value:
                  '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
            ),
            _buildLocationInfoRow(
              icon: Icons.my_location,
              label: 'Accuracy',
              value: '±${location.accuracy?.toStringAsFixed(0) ?? 'N/A'}m',
            ),
            if (location.speed != null && location.speed! > 0.5)
              _buildLocationInfoRow(
                icon: Icons.speed,
                label: 'Speed',
                value: '${(location.speed! * 3.6).toStringAsFixed(1)} km/h',
              ),
            if (location.altitude != null)
              _buildLocationInfoRow(
                icon: Icons.terrain,
                label: 'Altitude',
                value: '${location.altitude!.toStringAsFixed(0)}m',
              ),
            AppSpacing.gapLg,
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _safeAnimate(
                  CameraUpdate.newLatLngZoom(
                    LatLng(location.latitude, location.longitude),
                    15,
                  ),
                );
              },
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Center on Map'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary(context)),
          AppSpacing.gapSm,
          Text(
            '$label:',
            style: AppTextStyles.bodyMedium(
              context,
            )?.copyWith(fontWeight: FontWeight.w600),
          ),
          AppSpacing.gapSm,
          Expanded(
            child: Text(value, style: AppTextStyles.bodyMedium(context)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.error(context),
              ),
              AppSpacing.gapMd,
              Text(
                'Error Loading Locations',
                style: AppTextStyles.titleLarge(context),
              ),
              AppSpacing.gapSm,
              Text(
                _error!,
                style: AppTextStyles.bodyMedium(context),
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapLg,
              ElevatedButton.icon(
                onPressed: _loadChildren,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_children.isEmpty) {
      return Center(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.child_care_outlined,
                size: 64,
                color: AppColors.onSurface(context).withOpacity(0.5),
              ),
              AppSpacing.gapMd,
              Text(
                'No Children Paired',
                style: AppTextStyles.titleLarge(context),
              ),
              AppSpacing.gapSm,
              Text(
                'Pair a child device to see their location',
                style: AppTextStyles.bodyMedium(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final hasAnyLocation = _childrenLocations.values.any((loc) => loc != null);

    return Stack(
      children: [
        Column(
          children: [
            // Header
            Container(
              padding: AppSpacing.paddingMd,
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.onSurface(context).withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: AppColors.primary(context)),
                  AppSpacing.gapSm,
                  Text(
                    'Children Locations',
                    style: AppTextStyles.titleMedium(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: hasAnyLocation
                          ? AppColors.primary(context).withOpacity(0.1)
                          : AppColors.error(context).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_childrenLocations.values.where((loc) => loc != null).length}/${_children.length}',
                      style: AppTextStyles.bodySmall(context)?.copyWith(
                        color: hasAnyLocation
                            ? AppColors.primary(context)
                            : AppColors.error(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Map
            Expanded(
              child: hasAnyLocation
                  ? GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _mapCenter,
                        zoom: 12,
                      ),
                      markers: _buildMarkers(),
                      myLocationButtonEnabled: true,
                      myLocationEnabled: false,
                      zoomControlsEnabled: true,
                      mapToolbarEnabled: true,
                      compassEnabled: true,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _updateMapCenter();
                      },
                    )
                  : Center(
                      child: Padding(
                        padding: AppSpacing.paddingLg,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off,
                              size: 64,
                              color: AppColors.onSurface(context).withOpacity(0.5),
                            ),
                            AppSpacing.gapMd,
                            Text(
                              'No Location Data',
                              style: AppTextStyles.titleLarge(context),
                            ),
                            AppSpacing.gapSm,
                            Text(
                              'Waiting for children devices to share their location',
                              style: AppTextStyles.bodyMedium(context),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
        // Floating Action Button overlay
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: _isCheckingAllLocations
                ? null
                : _checkAllChildrenLocationsNow,
            icon: _isCheckingAllLocations
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  )
                : const Icon(Icons.gps_fixed),
            label: Text(
              _isCheckingAllLocations ? 'Checking...' : 'Check Locations',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _safeAnimate(CameraUpdate update) async {
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.animateCamera(update);
    } catch (e) {
      debugPrint('Map animateCamera skipped: $e');
    }
  }
}