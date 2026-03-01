import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/object_detection_service.dart';

class WeaponTestPage extends StatefulWidget {
  final VoidCallback onProfileButtonPressed;

  const WeaponTestPage({
    super.key,
    required this.onProfileButtonPressed,
  });

  @override
  State<WeaponTestPage> createState() => _WeaponTestPageState();
}

class _WeaponTestPageState extends State<WeaponTestPage> {
  final ObjectDetectionService _weaponService = ObjectDetectionService();
  final ImagePicker _imagePicker = ImagePicker();

  File? _selectedImage;
  bool _isScanning = false;
  bool? _weaponDetected;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  @override
  void dispose() {
    _weaponService.dispose();
    super.dispose();
  }

  Future<void> _initializeModel() async {
    try {
      await _weaponService.loadModel();
      debugPrint('✅ Weapon detection model loaded successfully');
      debugPrint('✅ Model ready: ${_weaponService.isModelLoaded}');
      if (mounted) {
        setState(() => _errorMessage = null);
      }
    } catch (e) {
      debugPrint('❌ Failed to load model: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load weapon detection model: $e');
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _weaponDetected = null;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      setState(() => _errorMessage = 'Error picking image: $e');
    }
  }

  Future<void> _scanImage() async {
    if (_selectedImage == null) {
      setState(() => _errorMessage = 'Please select an image first');
      return;
    }

    if (!_weaponService.isModelLoaded) {
      setState(() => _errorMessage = 'Model not loaded. Please restart the app.');
      return;
    }

    setState(() => _isScanning = true);

    try {
      debugPrint('🔍 Scanning image for weapons: ${_selectedImage!.path}');
      final result = await _weaponService.detectWeapon(_selectedImage!.path);

      if (mounted) {
        setState(() {
          _weaponDetected = result;
          _isScanning = false;
          _errorMessage = result
              ? '🚨 Weapon detected in image!'
              : '✅ No weapon detected - image is safe';
        });
      }

      debugPrint(
        result
            ? '⚠️ Weapon detected in image'
            : '✅ No weapon detected',
      );
    } catch (e) {
      debugPrint('❌ Scan error: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = 'Error scanning image: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weapon Detection Test'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: widget.onProfileButtonPressed,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weapon Detection Tester',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload an image to test if the weapon detection model can identify firearms or weapons.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Image Preview or Placeholder
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.outline,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surface,
              ),
              child: _selectedImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No image selected',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 24),

            // Pick Image Button
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_search),
              label: const Text('Pick Image from Gallery'),
              style: ElevatedButton.styleFrom(
                foregroundColor: colorScheme.onPrimary,
                backgroundColor: colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Scan Button
            ElevatedButton.icon(
              onPressed: _isScanning || _selectedImage == null ? null : _scanImage,
              icon: _isScanning
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.onError,
                        ),
                      ),
                    )
                  : const Icon(Icons.scanner),
              label: Text(
                _isScanning ? 'Scanning...' : 'Scan for Weapons',
              ),
              style: ElevatedButton.styleFrom(
                foregroundColor: colorScheme.onError,
                backgroundColor: colorScheme.error,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            // Result Card
            if (_errorMessage != null)
              Card(
                color: _weaponDetected == true
                    ? colorScheme.errorContainer
                    : _weaponDetected == false
                        ? colorScheme.tertiaryContainer
                        : colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _weaponDetected == true
                                ? Icons.error
                                : _weaponDetected == false
                                    ? Icons.check_circle
                                    : Icons.info,
                            color: _weaponDetected == true
                                ? colorScheme.onErrorContainer
                                : _weaponDetected == false
                                    ? colorScheme.onTertiaryContainer
                                    : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Detection Result',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _weaponDetected == true
                                    ? colorScheme.onErrorContainer
                                    : _weaponDetected == false
                                        ? colorScheme.onTertiaryContainer
                                        : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _weaponDetected == true
                              ? colorScheme.onErrorContainer
                              : _weaponDetected == false
                                  ? colorScheme.onTertiaryContainer
                                  : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Instructions
            if (_selectedImage == null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Card(
                  color: colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to Use:',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '1. Tap "Pick Image from Gallery"\n'
                          '2. Select an image containing a weapon or firearm\n'
                          '3. Tap "Scan for Weapons"\n'
                          '4. View the detection result',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
