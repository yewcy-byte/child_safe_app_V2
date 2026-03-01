import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/market_service.dart';
import '../../../models/child_model.dart';
import '../../shared/shared.dart';

class QRScannerPage extends StatefulWidget {
  final ChildModel child;
  final String parentId;

  const QRScannerPage({
    required this.child,
    required this.parentId,
    super.key,
  });

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final MobileScannerController _scannerController = MobileScannerController();
  final MarketService _marketService = MarketService();
  bool _isProcessing = false;
  String? _lastScannedCode;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleQRScan(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final data = barcode.rawValue!;

    // Prevent duplicate scans within 2 seconds
    if (_lastScannedCode == data) {
      return;
    }
    _lastScannedCode = data;

    setState(() => _isProcessing = true);

    try {
      // Extract itemId from QR code data
      // Format: item_{childId}_{itemId} or just {itemId}
      final itemId = data.split('_').last;

      // Verify and mark the item as scanned
      final item = await _marketService.getInventoryItemById(
        uid: widget.child.id,
        itemId: itemId,
      );

      if (!mounted) return;

      if (item == null) {
        _showSnackBar(
          'Item not found',
          isError: true,
        );
        setState(() => _isProcessing = false);
        return;
      }

      if (item.isScanned) {
        _showSnackBar(
          'This item was already completed!',
          isError: true,
        );
        setState(() => _isProcessing = false);
        return;
      }

      // Mark item as scanned
      final success = await _marketService.markInventoryItemAsScanned(
        uid: widget.child.id,
        itemId: itemId,
      );

      if (!mounted) return;

      if (success) {
        _showSuccessDialog(item);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
      } else {
        _showSnackBar(
          'Failed to mark item as completed',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Error scanning: ${e.toString()}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      // Allow re-scanning after delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _lastScannedCode = null;
      }
    }
  }

  void _showSuccessDialog(item) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Gift Completed! 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            AppSpacing.gapMd,
            Text(
              'Item: ${item.title}',
              style: AppTextStyles.titleSmall(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (item.parentText != null) ...[
              AppSpacing.gapSm,
              Text(
                'Details: ${item.parentText}',
                style: AppTextStyles.bodySmall(context),
                textAlign: TextAlign.center,
              ),
            ],
            AppSpacing.gapMd,
            Text(
              'The reward has been verified and marked as completed!',
              style: AppTextStyles.bodySmall(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // Return with success flag
              Navigator.pop(context, true);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.tertiary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Scan Reward QR Code',
          style: AppTextStyles.titleLarge(context),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: _handleQRScan,
              errorBuilder: (context, error, child) {
                return Center(
                  child: Text(
                    'Camera Error: ${error.errorCode}',
                    style: AppTextStyles.bodyMedium(context),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: AppSpacing.paddingMd,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'For: ${widget.child.name}',
                  style: AppTextStyles.bodyMedium(context),
                ),
                AppSpacing.gapMd,
                if (_isProcessing)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      AppSpacing.gapSm,
                      Text(
                        'Processing...',
                        style: AppTextStyles.bodySmall(context),
                      ),
                    ],
                  )
                else
                  Text(
                    'Point camera at the QR code.',
                    style: AppTextStyles.bodySmall(context).copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
