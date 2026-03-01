import 'package:flutter/material.dart';
import '../../../../shared/shared.dart';

class EditableNameField extends StatefulWidget {
  final String? initialName;
  final Future<void> Function(String) onNameChanged;
  final int maxLength;

  const EditableNameField({
    super.key,
    this.initialName,
    required this.onNameChanged,
    this.maxLength = 20,
  });

  @override
  State<EditableNameField> createState() => _EditableNameFieldState();
}

class _EditableNameFieldState extends State<EditableNameField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  String _previousName = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
    _previousName = widget.initialName ?? '';
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(EditableNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialName != widget.initialName && 
        _controller.text != widget.initialName) {
      _controller.text = widget.initialName ?? '';
      _previousName = widget.initialName ?? '';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _saveName();
    }
  }

  Future<void> _saveName() async {
    final currentName = _controller.text.trim();
    
    // Only save if changed
    if (currentName == _previousName) return;
    
    // Validate max length
    if (currentName.length > widget.maxLength) {
      _showError('Name cannot exceed ${widget.maxLength} characters');
      _controller.text = _previousName;
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      await widget.onNameChanged(currentName);
      _previousName = currentName;
    } catch (e) {
      _showError('Failed to save name: $e');
      _controller.text = _previousName;
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Name',
          style: AppTextStyles.labelLarge(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLength: widget.maxLength,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _saveName(),
          decoration: InputDecoration(
            hintText: 'Input name here',
            border: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(12.0)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            counterText: '',
          ),
        ),
      ],
    );
  }
}
