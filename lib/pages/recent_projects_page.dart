import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class RecentProjectsPage extends StatefulWidget {
  final VoidCallback? onCreateProject;
  final Function(String projectId, String projectName)? onProjectSelected;
  
  const RecentProjectsPage({
    super.key,
    this.onCreateProject,
    this.onProjectSelected,
  });

  @override
  State<RecentProjectsPage> createState() => _RecentProjectsPageState();
}

class _RecentProjectsPageState extends State<RecentProjectsPage> {
  final TextEditingController _searchController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _filteredProjects = [];
  bool _isLoading = true;
  String _searchQuery = '';

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
          .order('updated_at', ascending: false)
          .limit(50);

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

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 30) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
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
                'Recent Projects ',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 28 : isTablet ? 32 : 36,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Quick access to projects you've worked on recently.",
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
                        'Last modified',
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
                                  : 'No recent projects yet',
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
                                  : 'Projects you open will appear here.',
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
            ],
          ),
        ),
        // Projects list
        Expanded(
          child: ListView.separated(
            itemCount: _filteredProjects.length,
            separatorBuilder: (context, index) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              final project = _filteredProjects[index];
              final projectName = project['project_name'] ?? '';
              final updatedAt = project['updated_at'] != null
                  ? DateTime.parse(project['updated_at'])
                  : null;
              final createdAt = project['created_at'] != null
                  ? DateTime.parse(project['created_at'])
                  : null;
              final projectId = project['id']?.toString() ?? '';

              return GestureDetector(
                onTap: () {
                  if (widget.onProjectSelected != null) {
                    widget.onProjectSelected!(projectId, projectName);
                  }
                },
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      // Project Name
                      SizedBox(
                        width: 320,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            projectName,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      // Last modified
                      SizedBox(
                        width: 294,
                        child: Center(
                          child: Text(
                            updatedAt != null
                                ? _formatRelativeTime(updatedAt)
                                : 'N/A',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                              color: const Color(0xFF5C5C5C),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      // Created
                      SizedBox(
                        width: 294,
                        child: Center(
                          child: Text(
                            createdAt != null
                                ? _formatDate(createdAt)
                                : 'N/A',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                              color: const Color(0xFF5C5C5C),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Public method to refresh projects list
  void refreshProjects() {
    _loadProjects();
  }
}
