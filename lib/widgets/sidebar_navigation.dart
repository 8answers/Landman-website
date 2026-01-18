import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'nav_link.dart';
import '../models/navigation_page.dart';
import 'project_save_status.dart';

class SidebarNavigation extends StatefulWidget {
  final NavigationPage currentPage;
  final Function(NavigationPage) onPageChanged;
  final String? projectName;
  final ProjectSaveStatusType? saveStatus;
  final String? savedTimeAgo;
  final bool? hasDataEntryErrors;

  const SidebarNavigation({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
    this.projectName,
    this.saveStatus,
    this.savedTimeAgo,
    this.hasDataEntryErrors,
  });

  @override
  State<SidebarNavigation> createState() => _SidebarNavigationState();
}

class _SidebarNavigationState extends State<SidebarNavigation> {
  bool _isHomeHovered = false;
  bool _isDataEntryHovered = false;

  Widget _buildProjectDetailsSidebar() {
    return Container(
      width: 252,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 2,
            offset: const Offset(1, 0),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 8answers title
                Text(
                  '8answers',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 40),
                // Home link
                MouseRegion(
                  onEnter: (_) => setState(() => _isHomeHovered = true),
                  onExit: (_) => setState(() => _isHomeHovered = false),
                  child: GestureDetector(
                    onTap: () => widget.onPageChanged(NavigationPage.home),
                    child: Container(
                      height: 24,
                      child: Row(
                        children: [
                          // Back arrow icon
                          Container(
                            width: 7,
                            height: 14,
                            child: Icon(
                              Icons.arrow_back_ios,
                              size: 14,
                              color: const Color(0xFF5C5C5C),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Home icon
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: SvgPicture.asset(
                              _isHomeHovered
                                  ? 'assets/images/Home_hover.svg'
                                  : (widget.currentPage == NavigationPage.home
                                      ? 'assets/images/Home_active.svg'
                                      : 'assets/images/Home_inactive.svg'),
                              width: 16,
                              height: 16,
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 16,
                                height: 16,
                              ),
                              errorBuilder: (context, error, stackTrace) {
                                print('Error loading Home icon: $error');
                                return const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: Icon(Icons.home, size: 16, color: Color(0xFF5C5C5C)),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Home text
                          Text(
                            'Home',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: widget.currentPage == NavigationPage.home
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                              color: widget.currentPage == NavigationPage.home
                                  ? const Color(0xFF000000)
                                  : (_isHomeHovered
                                      ? const Color(0xCC000000)
                                      : const Color(0xFF5C5C5C)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Project section
                if (widget.projectName != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Project label
                      Text(
                        'Project',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: const Color(0xFF5D5D5D),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Project name
                      Text(
                        widget.projectName!,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Project save status
                      if (widget.saveStatus != null)
                        ProjectSaveStatus(
                          status: widget.saveStatus!,
                          savedTimeAgo: widget.savedTimeAgo,
                        ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
                // Data Visualization section
                Text(
                  'Data Visualization',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: const Color(0xFF5D5D5D),
                  ),
                ),
                const SizedBox(height: 16),
                NavLink(
                  inactiveIconPath: 'assets/images/Dashboard_inactive.svg',
                  hoverIconPath: 'assets/images/Dashboard_hover.svg',
                  activeIconPath: 'assets/images/Dashboard_active.svg',
                  label: 'Dashboard',
                  isActive: widget.currentPage == NavigationPage.dashboard,
                  onTap: () => widget.onPageChanged(NavigationPage.dashboard),
                ),
                const SizedBox(height: 40),
                // Edit section
                Text(
                  'Edit',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: const Color(0xFF5D5D5D),
                  ),
                ),
                const SizedBox(height: 16),
                MouseRegion(
                  onEnter: (_) => setState(() => _isDataEntryHovered = true),
                  onExit: (_) => setState(() => _isDataEntryHovered = false),
                  child: GestureDetector(
                    onTap: () => widget.onPageChanged(NavigationPage.dataEntry),
                    child: Container(
                      width: double.infinity,
                      height: 24,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: SvgPicture.asset(
                              widget.currentPage == NavigationPage.dataEntry
                                  ? 'assets/images/Account_active.svg'
                                  : (_isDataEntryHovered
                                      ? 'assets/images/Account_.hoversvg.svg'
                                      : 'assets/images/Account_inactive.svg'),
                              width: 16,
                              height: 16,
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 16,
                                height: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Data Entry',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: widget.currentPage == NavigationPage.dataEntry
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: widget.currentPage == NavigationPage.dataEntry
                                  ? Colors.black
                                  : (_isDataEntryHovered
                                      ? const Color(0xCC000000)
                                      : const Color(0xA3000000)),
                              letterSpacing: 0,
                            ),
                          ),
                          if (widget.hasDataEntryErrors == true) ...[
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
                ),
                const SizedBox(height: 8),
                NavLink(
                  inactiveIconPath: 'assets/images/Plot_status_inactive.svg',
                  hoverIconPath: 'assets/images/Plot_status_hover.svg',
                  activeIconPath: 'assets/images/Plot_status_active.svg',
                  label: 'Plot Status',
                  isActive: widget.currentPage == NavigationPage.plotStatus,
                  onTap: () => widget.onPageChanged(NavigationPage.plotStatus),
                ),
                const SizedBox(height: 40),
                // Task section
                Text(
                  'Task',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: const Color(0xFF5D5D5D),
                  ),
                ),
                const SizedBox(height: 16),
                NavLink(
                  inactiveIconPath: 'assets/images/To-do_inactive.svg',
                  hoverIconPath: 'assets/images/To-do_hover.svg',
                  activeIconPath: 'assets/images/To-do_active.svg',
                  label: 'To-Do List',
                  isActive: widget.currentPage == NavigationPage.toDoList,
                  onTap: () => widget.onPageChanged(NavigationPage.toDoList),
                ),
              ],
            ),
            // Settings at bottom
            NavLink(
              inactiveIconPath: 'assets/images/Account_inactive.svg', // Placeholder - will need Settings icon
              hoverIconPath: 'assets/images/Account_.hoversvg.svg',
              activeIconPath: 'assets/images/Account_active.svg',
              label: 'Settings',
              isActive: widget.currentPage == NavigationPage.settings,
              onTap: () => widget.onPageChanged(NavigationPage.settings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOriginalSidebar() {
    return Container(
      width: 252,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 2,
            offset: const Offset(1, 0),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '8answers',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          // Navigation items
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Account (Active)
                      NavLink(
                        key: ValueKey('account_${widget.currentPage == NavigationPage.account}'),
                        inactiveIconPath: 'assets/images/Account_inactive.svg',
                        hoverIconPath: 'assets/images/Account_.hoversvg.svg',
                        activeIconPath: 'assets/images/Account_active.svg',
                        label: 'Account',
                        isActive: widget.currentPage == NavigationPage.account,
                        onTap: () => widget.onPageChanged(NavigationPage.account),
                      ),
                      const SizedBox(height: 40),
                      // Task section
                      Text(
                        'Task',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      NavLink(
                        inactiveIconPath: 'assets/images/Notifications_inactive.svg',
                        hoverIconPath: 'assets/images/Notifications_hover.svg',
                        activeIconPath: 'assets/images/Notificatons_active.svg',
                        label: 'Notifications',
                        isActive: widget.currentPage == NavigationPage.notifications,
                        onTap: () => widget.onPageChanged(NavigationPage.notifications),
                      ),
                      const SizedBox(height: 16),
                      NavLink(
                        inactiveIconPath: 'assets/images/To-do_inactive.svg',
                        hoverIconPath: 'assets/images/To-do_hover.svg',
                        activeIconPath: 'assets/images/To-do_active.svg',
                        label: 'To-Do List',
                        isActive: widget.currentPage == NavigationPage.toDoList,
                        onTap: () => widget.onPageChanged(NavigationPage.toDoList),
                      ),
                      const SizedBox(height: 40),
                      // Projects section
                      Text(
                        'Projects',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      NavLink(
                        inactiveIconPath: 'assets/images/Recent projects_inactive.svg',
                        hoverIconPath: 'assets/images/Recent projects_hover.svg',
                        activeIconPath: 'assets/images/Recent projects_active.svg',
                        label: 'Recent Projects',
                        isActive: widget.currentPage == NavigationPage.recentProjects,
                        onTap: () => widget.onPageChanged(NavigationPage.recentProjects),
                      ),
                      const SizedBox(height: 16),
                      NavLink(
                        inactiveIconPath: 'assets/images/All projects_inactive.svg',
                        hoverIconPath: 'assets/images/All_projects_hover.svg',
                        activeIconPath: 'assets/images/All projects_active.svg',
                        label: 'All Projects',
                        isActive: widget.currentPage == NavigationPage.allProjects,
                        onTap: () => widget.onPageChanged(NavigationPage.allProjects),
                      ),
                      const SizedBox(height: 40),
                      // Recover section
                      Text(
                        'Recover',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      NavLink(
                        inactiveIconPath: 'assets/images/Trash_inactive.svg',
                        hoverIconPath: 'assets/images/Trash_hover.svg',
                        activeIconPath: 'assets/images/Trash_active.svg',
                        label: 'Trash',
                        isActive: widget.currentPage == NavigationPage.trash,
                        onTap: () => widget.onPageChanged(NavigationPage.trash),
                      ),
                      const SizedBox(height: 40),
                      // About section
                      Text(
                        'About',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      NavLink(
                        inactiveIconPath: 'assets/images/Help_inactive.svg',
                        hoverIconPath: 'assets/images/Help_hover.svg',
                        activeIconPath: 'assets/images/Help_active.svg',
                        label: 'Help',
                        isActive: widget.currentPage == NavigationPage.help,
                        onTap: () => widget.onPageChanged(NavigationPage.help),
                      ),
                    ],
                  ),
                  // Footer
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NavLink(
                        inactiveIconPath: 'assets/images/Loggout_inactive.svg',
                        hoverIconPath: 'assets/images/Logout_hver.svg',
                        activeIconPath: 'assets/images/Logout_active.svg',
                        label: 'Log Out',
                        iconRotation: 180,
                        isActive: widget.currentPage == NavigationPage.logout,
                        onTap: () => widget.onPageChanged(NavigationPage.logout),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Text(
                          'Version 1.1.1',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: const Color(0xFF666666),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show new sidebar design when on project details, dashboard, data entry, or plot status pages
    if (widget.currentPage == NavigationPage.projectDetails ||
        widget.currentPage == NavigationPage.dashboard ||
        widget.currentPage == NavigationPage.dataEntry ||
        widget.currentPage == NavigationPage.plotStatus) {
      return _buildProjectDetailsSidebar();
    }
    return _buildOriginalSidebar();
  }
}

