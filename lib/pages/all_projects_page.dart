import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AllProjectsPage extends StatefulWidget {
  final VoidCallback? onCreateProject;
  final Function(String projectId, String projectName)? onProjectSelected;
  
  const AllProjectsPage({
    super.key,
    this.onCreateProject,
    this.onProjectSelected,
  });

  @override
  State<AllProjectsPage> createState() => _AllProjectsPageState();
}

class _AllProjectsPageState extends State<AllProjectsPage> {
  final TextEditingController _searchController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _filteredProjects = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _hoveredIndex; // Track which project row is being hovered

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadProjects();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterProjects();
    });
  }

  void _filterProjects() {
    if (_searchQuery.isEmpty) {
      _filteredProjects = List.from(_projects);
    } else {
      _filteredProjects = _projects.where((project) {
        final name = (project['project_name'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery);
      }).toList();
    }
  }

  Future<void> _loadProjects() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _isLoading = false;
          _projects = [];
          _filteredProjects = [];
        });
        return;
      }

      final response = await _supabase
          .from('projects')
          .select()
          .eq('user_id', userId)
          .order('project_name', ascending: true); // Sort alphabetically

      setState(() {
        _projects = List<Map<String, dynamic>>.from(response);
        _filterProjects();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading projects: $e');
      setState(() {
        _isLoading = false;
        _projects = [];
        _filteredProjects = [];
      });
    }
  }

  String _formatDate(DateTime dateTime) {
    return DateFormat('d MMM yyyy').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header section
        Padding(
          padding: const EdgeInsets.only(
            top: 0,
            left: 24,
            right: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All Projects',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 28 : isTablet ? 32 : 36,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "View and manage all projects you have access to.",
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        // Sort by section
        Transform.translate(
          offset: const Offset(-24, 0), // Move left by 24px
          child: Container(
            width: MediaQuery.of(context).size.width + 24, // Full width plus compensate for transform
            height: 32,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF5C5C5C),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 48), // Compensate for Transform.translate + 24px for tab options
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    height: 32,
                    child: Center(
                      child: Text(
                        'Sort by:',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 60),
                // Alphabetical order (active)
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: const Color(0xFF0C8CE9),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Alphabetical order',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0C8CE9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 36),
        // Action buttons row
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 24),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Create new project button
                    GestureDetector(
                      onTap: widget.onCreateProject,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C8CE9),
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
                          children: [
                            Text(
                              'Create new project',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SvgPicture.asset(
                              'assets/images/Cretae_new_projet_white.svg',
                              width: 13,
                              height: 13,
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 13,
                                height: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Search bar
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: const Color(0xFF5C5C5C),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          SvgPicture.asset(
                            'assets/images/Search_projects.svg',
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                            placeholderBuilder: (context) => const SizedBox(
                              width: 24,
                              height: 24,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: Colors.black.withOpacity(0.8),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search by project name',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black.withOpacity(0.8),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    // Create new project button
                    GestureDetector(
                      onTap: widget.onCreateProject,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C8CE9),
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
                          children: [
                            Text(
                              'Create new project',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SvgPicture.asset(
                              'assets/images/Cretae_new_projet_white.svg',
                              width: 13,
                              height: 13,
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 13,
                                height: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Search bar
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: const Color(0xFF5C5C5C),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            SvgPicture.asset(
                              'assets/images/Search_projects.svg',
                              width: 24,
                              height: 24,
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 24,
                                height: 24,
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black.withOpacity(0.8),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search by project name',
                                  hintStyle: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.black.withOpacity(0.8),
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        // Projects list or empty state
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredProjects.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(left: 24, right: 24),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Empty state icon
                            SvgPicture.asset(
                              'assets/images/Rcent_projects_folder.svg',
                              width: 108,
                              height: 80,
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 108,
                                height: 80,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No projects found'
                                  : 'No projects yet',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Try a different search term.'
                                  : 'Create your first project to get started.',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: const Color(0xFF5C5C5C),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_searchQuery.isEmpty) ...[
                              const SizedBox(height: 24),
                              // Create new project button (empty state)
                              GestureDetector(
                                onTap: widget.onCreateProject,
                                child: Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
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
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Create new project',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.normal,
                                          color: const Color(0xFF0C8CE9),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Plus icon
                                      SvgPicture.asset(
                                        'assets/images/Create_new_project_blue.svg',
                                        width: 13,
                                        height: 13,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) => const SizedBox(
                                          width: 13,
                                          height: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: _buildProjectsTable(),
                    ),
        ),
      ],
    );
  }

  Widget _buildProjectsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Table header
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // Project Name column
              SizedBox(
                width: 320,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Project Name',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF5C5C5C),
                    ),
                  ),
                ),
              ),
              // Created column
              SizedBox(
                width: 294,
                child: Center(
                  child: Text(
                    'Created',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF5C5C5C),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Last modified column
              SizedBox(
                width: 294,
                child: Center(
                  child: Text(
                    'Last modified',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF5C5C5C),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Table rows
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: _filteredProjects.asMap().entries.map((entry) {
                final index = entry.key;
                final project = entry.value;
                final projectId = project['id'] as String;
                final projectName = (project['project_name'] ?? 'Unnamed') as String;
                final createdAtStr = project['created_at'] as String?;
                final updatedAtStr = project['updated_at'] as String?;
                final isHovered = _hoveredIndex == index;
                
                DateTime? createdAt;
                DateTime? updatedAt;
                
                try {
                  if (createdAtStr != null) {
                    createdAt = DateTime.parse(createdAtStr);
                  }
                  if (updatedAtStr != null) {
                    updatedAt = DateTime.parse(updatedAtStr);
                  }
                } catch (e) {
                  print('Error parsing date: $e');
                }

                return MouseRegion(
                  onEnter: (_) {
                    setState(() {
                      _hoveredIndex = index;
                    });
                  },
                  onExit: (_) {
                    setState(() {
                      _hoveredIndex = null;
                    });
                  },
                  child: GestureDetector(
                    onTap: () {
                      widget.onProjectSelected?.call(projectId, projectName);
                    },
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isHovered ? const Color(0xFF5C5C5C).withOpacity(0.1) : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.black.withOpacity(0.1),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Project Name column
                          SizedBox(
                            width: 320,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                projectName,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // Created column
                          SizedBox(
                            width: 294,
                            child: Center(
                              child: Text(
                                createdAt != null ? _formatDate(createdAt) : '-',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                          // Last modified column
                          SizedBox(
                            width: 294,
                            child: Center(
                              child: Text(
                                updatedAt != null ? _formatDate(updatedAt) : '-',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                          // Spacer to push Open button to the right
                          const Spacer(),
                          // Open button - only visible on hover
                          if (isHovered)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Open',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                      color: const Color(0xFF0C8CE9),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Transform.rotate(
                                    angle: -45 * 3.14159 / 180,
                                    child: SvgPicture.asset(
                                      'assets/images/Hover_open.svg',
                                      width: 16,
                                      height: 16,
                                      fit: BoxFit.contain,
                                      placeholderBuilder: (context) => const Icon(
                                        Icons.east,
                                        color: Color(0xFF0C8CE9),
                                        size: 16,
                                      ),
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Icon(
                                          Icons.east,
                                          color: Color(0xFF0C8CE9),
                                          size: 16,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            const SizedBox(width: 0),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
