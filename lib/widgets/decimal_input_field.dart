import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// A custom TextField widget that displays ".00" as a grey placeholder suffix while typing
/// This gives users visual feedback that decimal input is expected
class DecimalInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onTap;
  final VoidCallback? onTapOutside;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final String? suffix;
  final TextStyle? suffixStyle;
  final EdgeInsets? contentPadding;
  final bool isDense;

  const DecimalInputField({
    required this.controller,
    this.focusNode,
    this.hintText = '0',
    this.keyboardType = TextInputType.number,
    this.inputFormatters,
    this.onChanged,
    this.onEditingComplete,
    this.onTap,
    this.onTapOutside,
    this.style,
    this.hintStyle,
    this.suffix,
    this.suffixStyle,
    this.contentPadding,
    this.isDense = true,
  });

  @override
  State<DecimalInputField> createState() => _DecimalInputFieldState();
}

class _DecimalInputFieldState extends State<DecimalInputField> {
  late FocusNode _internalFocusNode;
  late TextEditingController _displayController;
  bool _hasFocus = false;
  bool _isUpdatingController = false;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = widget.focusNode ?? FocusNode();
    _internalFocusNode.addListener(_handleFocusChange);
    widget.controller.addListener(_handleTextChange);
    
    // Create a display controller that syncs with the original
    _displayController = TextEditingController(text: _getDisplayText());
    _displayController.addListener(_handleDisplayTextChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChange);
    _internalFocusNode.removeListener(_handleFocusChange);
    _displayController.removeListener(_handleDisplayTextChange);
    _displayController.dispose();
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _hasFocus = _internalFocusNode.hasFocus;
      _updateDisplayController();
      
      // When focus is gained, position cursor at the end of the visible text (before .00)
      if (_hasFocus) {
        final displayText = _getDisplayText();
        _displayController.selection = TextSelection.collapsed(offset: displayText.length);
      }
    });
  }

  void _handleTextChange() {
    if (!_isUpdatingController) {
      setState(() {
        _updateDisplayController();
      });
    }
  }

  void _handleDisplayTextChange() {
    if (!_isUpdatingController) {
      _isUpdatingController = true;
      final displayText = _displayController.text;
      
      // Always update the original controller with the display text
      // (the display text already has ".00" removed if it was there)
      widget.controller.text = displayText;
      widget.onChanged?.call(displayText);
      _isUpdatingController = false;
    }
  }

  void _updateDisplayController() {
    if (!_isUpdatingController) {
      _isUpdatingController = true;
      final displayText = _getDisplayText();
      final selection = _displayController.selection;
      
      if (_displayController.text != displayText) {
        _displayController.value = TextEditingValue(
          text: displayText,
          selection: selection.baseOffset <= displayText.length 
              ? selection 
              : TextSelection.collapsed(offset: displayText.length),
        );
      }
      _isUpdatingController = false;
    }
  }

  String _getDisplayDecimalSuffix() {
    final text = widget.controller.text;
    
    // Don't show suffix if field is empty
    if (text.isEmpty) {
      return '';
    }

    // Check if text already contains a decimal point
    if (text.contains('.')) {
      final parts = text.split('.');
      if (parts.length == 2) {
        final decimalPart = parts[1];
        
        // If user has entered their own decimal digits, don't show overlay
        // Only show overlay if decimal part is exactly "00" (auto-added)
        if (decimalPart == '00') {
          return '.00';
        }
        
        // If decimal part is incomplete (user typed fewer than 2 digits), don't show overlay
        // Let the user complete their entry
        if (decimalPart.length < 2) {
          return '';
        }
      }
      return '';
    }

    // If no decimal point and has text, show .00
    return '.00';
  }

  String _getDisplayText() {
    final text = widget.controller.text;
    // If text ends with ".00", hide it from the TextField display (show as overlay instead)
    if (text.endsWith('.00')) {
      return text.substring(0, text.length - 3); // Remove ".00"
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final decimalSuffix = _getDisplayDecimalSuffix();
    final displayText = _getDisplayText();
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The actual TextField - use display controller to hide ".00" if present
        TextField(
          controller: _displayController,
          focusNode: _internalFocusNode,
          keyboardType: widget.keyboardType,
          textAlignVertical: TextAlignVertical.center,
          textAlign: TextAlign.left,
          inputFormatters: widget.inputFormatters,
          onTap: widget.onTap,
          onTapOutside: (event) {
            widget.onTapOutside?.call();
          },
          onChanged: (value) {
            // Handled by _handleDisplayTextChange listener
          },
          onEditingComplete: () {
            widget.onEditingComplete?.call();
          },
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: widget.hintStyle ??
                GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color.fromARGB(191, 173, 173, 173),
                ),
            border: InputBorder.none,
            contentPadding: widget.contentPadding ?? EdgeInsets.zero,
            isDense: widget.isDense,
          ),
          style: widget.style ??
              GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
        ),
        // Display the decimal suffix as text overlay - positioned at the start of text input
        if (decimalSuffix.isNotEmpty)
          Positioned(
            left: 0,
            top: (widget.contentPadding?.top ?? 0) - 3, // Move up by 3 pixels
            child: IgnorePointer(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display the entered text (but transparent so it doesn't show)
                  Text(
                    displayText,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.transparent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                  // Display the suffix - grey when focused (editing), black when not focused (completed)
                  Text(
                    decimalSuffix,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _hasFocus 
                          ? Color.fromARGB(191, 173, 173, 173)  // Grey when editing
                          : Colors.black,  // Black when completed
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
