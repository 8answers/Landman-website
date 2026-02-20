import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/project_storage_service.dart';

class SettingsPage extends StatefulWidget {
  final String? projectId;
  final VoidCallback? onProjectDeleted;

  const SettingsPage({
    super.key,
    this.projectId,
    this.onProjectDeleted,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _projectStatus = 'Active';
  bool _isDropdownOpen = false;
  OverlayEntry? _overlayEntry;
  OverlayEntry? _deleteDialogOverlay;
  final TextEditingController _deleteConfirmController = TextEditingController();
  final FocusNode _deleteConfirmFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadProjectStatus();
  }

  @override
  void dispose() {
    _removeOverlay();
    _removeDeleteDialog();
    _deleteConfirmController.dispose();
    _deleteConfirmFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProjectStatus() async {
    final projectId = widget.projectId;
    if (projectId == null || projectId.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('projects')
          .select('project_status')
          .eq('id', projectId)
          .maybeSingle();
      final status = (row?['project_status'] ?? '').toString().trim();
      if (status.isNotEmpty && mounted) {
        setState(() {
          _projectStatus = status;
        });
      }
    } catch (e) {
      print('SettingsPage: failed to load project_status: $e');
    }
  }

  Future<void> _saveProjectStatus() async {
    final projectId = widget.projectId;
    if (projectId == null || projectId.isEmpty) return;
    try {
      await ProjectStorageService.saveProjectData(
        projectId: projectId,
        projectStatus: _projectStatus,
      );
    } catch (e) {
      print('SettingsPage: failed to save project_status: $e');
    }
  }

  void _removeDeleteDialog() {
    _deleteDialogOverlay?.remove();
    _deleteDialogOverlay = null;
    _deleteConfirmController.clear();
    _deleteConfirmFocusNode.unfocus();
  }

  void _showDeleteDialog() {
    _deleteConfirmFocusNode.addListener(() {
      setState(() {}); // Rebuild to update box shadow
    });
    _deleteDialogOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Semi-transparent black background
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeDeleteDialog,
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ),
          // Dialog centered at top
          Positioned(
            top: 24,
            left: MediaQuery.of(context).size.width / 2 - 269, // Center (538/2 = 269)
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 538,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 2,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                // Header with warning icon and close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning,
                          color: Colors.red,
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Delete Project?',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: _removeDeleteDialog,
                      child: Transform.rotate(
                        angle: 0.785398, // 45 degrees
                        child: const Icon(
                          Icons.add,
                          size: 24,
                          color: Color(0xFF0C8CE9),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Warning message
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black.withOpacity(0.8),
                        ),
                        children: const [
                          TextSpan(text: 'This will permanently delete the '),
                          TextSpan(text: 'project and all associated data'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This action cannot be undone.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                        color: Colors.black.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Confirmation input
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFF323232),
                        ),
                        children: [
                          const TextSpan(
                            text: 'Type ',
                            style: TextStyle(fontWeight: FontWeight.normal),
                          ),
                          const TextSpan(
                            text: 'delete ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'to confirm.',
                            style: TextStyle(fontWeight: FontWeight.normal),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 150,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: _deleteConfirmFocusNode.hasFocus
                                ? const Color(0xFF0C8CE9)
                                : const Color(0xFFFF0000),
                            blurRadius: 2,
                            spreadRadius: 0,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _deleteConfirmController,
                        focusNode: _deleteConfirmFocusNode,
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (value) {
                          setState(() {}); // Rebuild to update button state
                        },
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 16),
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Cancel button
                    GestureDetector(
                      onTap: _removeDeleteDialog,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 2,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: const Color(0xFF0C8CE9),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Delete button
                    GestureDetector(
                      onTap: () async {
                        if (_deleteConfirmController.text.toLowerCase() == 'delete') {
                          if (widget.projectId != null) {
                            try {
                              await ProjectStorageService.deleteProject(widget.projectId!);
                              _removeDeleteDialog();
                              // Notify parent that project was deleted
                              if (widget.onProjectDeleted != null) {
                                widget.onProjectDeleted!();
                              }
                            } catch (e) {
                              print('Error deleting project: $e');
                              // Show error message
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to delete project: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          }
                        }
                      },
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 2,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Delete Project',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: _deleteConfirmController.text.toLowerCase() == 'delete'
                                    ? Colors.red
                                    : Colors.red.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SvgPicture.asset(
                              'assets/images/Delete_layout.svg',
                              width: 13,
                              height: 16,
                              colorFilter: ColorFilter.mode(
                                _deleteConfirmController.text.toLowerCase() == 'delete'
                                    ? Colors.red
                                    : Colors.red.withOpacity(0.5),
                                BlendMode.srcIn,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_deleteDialogOverlay!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isDropdownOpen = false;
  }

  void _toggleDropdown(BuildContext context) {
    if (_isDropdownOpen) {
      _removeOverlay();
    } else {
      _showDropdown(context);
    }
  }

  void _showDropdown(BuildContext context) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Invisible barrier to detect outside clicks
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeOverlay,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          // Dropdown menu
          Positioned(
            left: offset.dx,
            top: offset.dy + size.height,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: size.width,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDropdownItem('Active', const Color(0xFF06AB00)),
                    _buildDropdownItem('On Hold', const Color(0xFFFFC107)),
                    _buildDropdownItem('Completed', const Color(0xFF2196F3)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isDropdownOpen = true);
  }

  Widget _buildDropdownItem(String status, Color dotColor) {
    final isSelected = _projectStatus == status;
    Color badgeBackgroundColor;
    
    if (isSelected) {
      // Selected item badge background
      if (status == 'Active') {
        badgeBackgroundColor = const Color(0xFFEBF8EB);
      } else if (status == 'On Hold') {
        badgeBackgroundColor = const Color(0xFFFFFFEB);
      } else {
        badgeBackgroundColor = const Color(0xFFECF6FD);
      }
    } else {
      // Non-selected item badge background
      badgeBackgroundColor = Colors.white;
    }
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _projectStatus = status;
        });
        _saveProjectStatus();
        _removeOverlay();
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(8),
        color: Colors.white,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: badgeBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 2,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header section
        Padding(
          padding: const EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project Settings',
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage project configuration',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Tabs section
        Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFF5C5C5C),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // General tab (active)
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Color(0xFF0C8CE9),
                          width: 2,
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'General',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0C8CE9),
                          height: 1.43,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // Content section
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Project section
                  Container(
                    width: 617,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 2,
                          offset: const Offset(0, 0),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Project',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Update the operational status of this project.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Project Status label
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                            children: const [
                              TextSpan(text: 'Project Status '),
                              TextSpan(
                                text: '*',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Status dropdown
                        Builder(
                          builder: (BuildContext dropdownContext) {
                            Color statusColor;
                            Color statusBgColor;
                            
                            if (_projectStatus == 'Active') {
                              statusColor = const Color(0xFF06AB00);
                              statusBgColor = const Color(0xFFEBF8EB);
                            } else if (_projectStatus == 'On Hold') {
                              statusColor = const Color(0xFFFFC107);
                              statusBgColor = const Color(0xFFFFFFEB);
                            } else {
                              statusColor = const Color(0xFF2196F3);
                              statusBgColor = const Color(0xFFECF6FD);
                            }
                            
                            return GestureDetector(
                              onTap: () => _toggleDropdown(dropdownContext),
                              child: Container(
                                width: 145,
                                height: 40,
                                padding: const EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 2,
                                      offset: const Offset(0, 0),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Status badge
                                    Container(
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: statusBgColor,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.25),
                                            blurRadius: 2,
                                            offset: const Offset(0, 0),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: statusColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _projectStatus,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.normal,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Dropdown arrow
                                    Container(
                                      height: 32,
                                      alignment: const Alignment(0, -0.3),
                                      child: Transform.rotate(
                                        angle: -1.5708, // -90 degrees in radians
                                        child: const Icon(
                                          Icons.arrow_back_ios,
                                          size: 14,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Delete Project section
                  Container(
                    width: 617,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 2,
                          offset: const Offset(0, 0),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delete Project',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Permanently remove this project and all associated data. This action cannot be undone.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Delete button
                        GestureDetector(
                          onTap: _showDeleteDialog,
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 2,
                                  offset: const Offset(0, 0),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Delete Project',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SvgPicture.asset(
                                  'assets/images/Delete_layout.svg',
                                  width: 13,
                                  height: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
  }
}
