import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

class NavLink extends StatefulWidget {
  final String? inactiveIconPath;
  final String? hoverIconPath;
  final String? activeIconPath;
  final IconData? icon;
  final String label;
  final bool isActive;
  final double iconRotation;
  final VoidCallback? onTap;
  final bool hasError;

  const NavLink({
    super.key,
    this.inactiveIconPath,
    this.hoverIconPath,
    this.activeIconPath,
    this.icon,
    required this.label,
    this.isActive = false,
    this.iconRotation = 0,
    this.onTap,
    this.hasError = false,
  }) : assert(inactiveIconPath != null || icon != null, 'Either iconPath or icon must be provided');

  @override
  State<NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<NavLink> {
  bool _isHovered = false;

  String? _getIconPath() {
    if (widget.isActive && widget.activeIconPath != null) {
      return widget.activeIconPath;
    } else if (_isHovered && widget.hoverIconPath != null) {
      return widget.hoverIconPath;
    } else {
      return widget.inactiveIconPath;
    }
  }

  Color _getTextColor() {
    if (widget.isActive) {
      return const Color(0xFF000000); // #000000
    } else if (_isHovered) {
      return const Color(0xCC000000); // #000000CC
    } else {
      return const Color(0xA3000000); // #000000A3
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontWeight = widget.isActive ? FontWeight.w500 : FontWeight.w400;
    
    // Debug: Print to verify state changes
    // print('NavLink ${widget.label}: isActive=${widget.isActive}, fontWeight=$fontWeight');
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          height: 24,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Transform.rotate(
                angle: widget.iconRotation * 3.14159 / 180,
                child: widget.inactiveIconPath != null
                    ? SvgPicture.asset(
                        _getIconPath() ?? widget.inactiveIconPath!,
                        width: 16,
                        height: 16,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        placeholderBuilder: (context) => const SizedBox(
                          width: 16,
                          height: 16,
                        ),
                        errorBuilder: (context, error, stackTrace) {
                          print('Error loading icon ${_getIconPath()}: $error');
                          return const SizedBox(
                            width: 16,
                            height: 16,
                            child: Icon(Icons.error_outline, size: 16, color: Colors.red),
                          );
                        },
                      )
                    : Icon(
                        widget.icon!,
                        size: 16,
                        color: widget.isActive
                            ? const Color(0xFF090909)
                            : Colors.black.withOpacity(0.64),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: fontWeight,
                color: _getTextColor(),
                letterSpacing: 0,
              ),
            ),
            if (widget.hasError) ...[
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/images/Error_msg.svg',
                width: 17,
                height: 15,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  print('Error loading Error_msg.svg: $error');
                  return const SizedBox(
                    width: 17,
                    height: 15,
                  );
                },
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

