import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/area_unit_service.dart';

const List<String> _areaUnitOptions = [
  'Square Feet (sqft)',
  'Square Meter (sqm)'
];
const double _areaUnitDropdownWidth = 180;
const double _areaUnitMenuWidth = 180;
const double _areaUnitTriggerHeight = 28;
const double _areaUnitMenuItemHeight = 32;

class AreaUnitSelector extends StatefulWidget {
  final String selectedUnit;
  final String? projectId;
  final ValueChanged<String> onUnitChanged;

  const AreaUnitSelector({
    super.key,
    required this.selectedUnit,
    required this.onUnitChanged,
    this.projectId,
  });

  @override
  State<AreaUnitSelector> createState() => _AreaUnitSelectorState();
}

class _AreaUnitSelectorState extends State<AreaUnitSelector> {
  final GlobalKey _triggerKey = GlobalKey();
  OverlayEntry? _dropdownEntry;
  OverlayEntry? _backdropEntry;

  void _closeDropdown() {
    _dropdownEntry?.remove();
    _backdropEntry?.remove();
    _dropdownEntry = null;
    _backdropEntry = null;
  }

  void _showDropdown(BuildContext context) {
    _closeDropdown();
    final RenderBox? renderBox =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final left = offset.dx;
    final top = offset.dy + renderBox.size.height + 8;
    const double menuPadding = 4;

    _backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: _closeDropdown,
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    _dropdownEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: _areaUnitMenuWidth,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 2,
                  offset: const Offset(0, 0),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(menuPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _areaUnitOptions.asMap().entries.expand((entry) {
                  final isFirst = entry.key == 0;
                  final option = entry.value;
                  final isSelected = option == widget.selectedUnit;
                  return [
                    if (!isFirst) const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        if (option != widget.selectedUnit) {
                          widget.onUnitChanged(option);
                          await AreaUnitService.setAreaUnit(
                              widget.projectId, option);
                        }
                        _closeDropdown();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 148,
                        height: _areaUnitMenuItemHeight,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFECF6FD)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 2,
                              offset: const Offset(0, 0),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            option,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ];
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_backdropEntry!);
    overlay.insert(_dropdownEntry!);
  }

  @override
  void dispose() {
    _closeDropdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 2,
            offset: const Offset(0, 0),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Project Area Unit:',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showDropdown(context),
            child: Container(
              key: _triggerKey,
              width: _areaUnitDropdownWidth,
              height: _areaUnitTriggerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 2,
                    offset: const Offset(0, 0),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.selectedUnit,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SvgPicture.asset(
                    'assets/images/Drrrop_down.svg',
                    width: 7,
                    height: 7,
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF000000),
                      BlendMode.srcIn,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
