import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AllProjectsPage extends StatelessWidget {
  final VoidCallback? onCreateProject;
  
  const AllProjectsPage({super.key, this.onCreateProject});

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
                // Date created (active)
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
                      'Date created',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0C8CE9),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 60),
                // Alphabetical order
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: Text(
                      'Alphabetical order',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: const Color(0xFF5C5C5C),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 60),
                // Last modified
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: Text(
                      'Last modified',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: const Color(0xFF5C5C5C),
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
                        onTap: onCreateProject,
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
                            color: Colors.black,
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
                              child: Text(
                                'Search by project name',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black.withOpacity(0.8),
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
                        onTap: onCreateProject,
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
                              color: Colors.black,
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
                                child: Text(
                                  'Search by project name',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.black.withOpacity(0.8),
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
        // Empty state - centered
        Expanded(
          child: Padding(
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
                    'No projects found',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first project to get started.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF5C5C5C),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // Create new project button (empty state)
                  GestureDetector(
                    onTap: onCreateProject,
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
                ),
            ),
          ),
        ),
      ],
    );
  }
}
