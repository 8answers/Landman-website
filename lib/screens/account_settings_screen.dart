import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/sidebar_navigation.dart';
import '../widgets/account_settings_content.dart';
import '../widgets/create_project_dialog.dart';
import '../widgets/project_save_status.dart';
import '../models/navigation_page.dart';
import '../pages/notifications_page.dart';
import '../pages/to_do_list_page.dart';
import '../pages/recent_projects_page.dart';
import '../pages/all_projects_page.dart';
import '../pages/trash_page.dart';
import '../pages/help_page.dart';
import '../pages/project_details_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/data_entry_page.dart';
import '../pages/plot_status_page.dart';
import '../pages/documents_page.dart';
import '../pages/report_page.dart';
import '../pages/settings_page.dart';
import '../pages/login_page.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  NavigationPage _currentPage = NavigationPage.recentProjects;
  NavigationPage? _previousPage;
  String? _projectName;
  String? _projectId;
  ProjectSaveStatusType _saveStatus = ProjectSaveStatusType.saved;
  String? _savedTimeAgo;
  bool _hasDataEntryErrors = false;
  bool _hasPlotStatusErrors = false;
  bool _hasAreaErrors = false;
  bool _hasPartnerErrors = false;
  bool _hasExpenseErrors = false;
  bool _hasSiteErrors = false;
  bool _hasProjectManagerErrors = false;
  bool _hasAgentErrors = false;
  bool _hasAboutErrors = false;

  Widget _getPageContentForPage(NavigationPage page) {
    switch (page) {
      case NavigationPage.account:
        return const AccountSettingsContent();
      case NavigationPage.notifications:
        return const NotificationsPage();
      case NavigationPage.toDoList:
        return const ToDoListPage();
      case NavigationPage.report:
        return ReportPage(projectId: _projectId);
      case NavigationPage.recentProjects:
        return RecentProjectsPage(
          onCreateProject: () => _showCreateProjectDialog(),
          onProjectSelected: (projectId, projectName) {
            setState(() {
              _projectName = projectName;
              _projectId = projectId;
              _previousPage = _currentPage;
              _currentPage = NavigationPage.dataEntry;
            });
          },
        );
      case NavigationPage.allProjects:
        return AllProjectsPage(
          onCreateProject: () => _showCreateProjectDialog(),
        );
      case NavigationPage.trash:
        return const TrashPage();
      case NavigationPage.help:
        return const HelpPage();
      case NavigationPage.logout:
        return const AccountSettingsContent();
      case NavigationPage.projectDetails:
        return ProjectDetailsPage(
          initialProjectName: _projectName,
          projectId: _projectId,
          onSaveStatusChanged: _handleSaveStatusChanged,
          onErrorStateChanged: _handleErrorStateChanged,
          onAreaErrorsChanged: _handleAreaErrorsChanged,
          onPartnerErrorsChanged: _handlePartnerErrorsChanged,
          onExpenseErrorsChanged: _handleExpenseErrorsChanged,
          onSiteErrorsChanged: _handleSiteErrorsChanged,
          onProjectManagerErrorsChanged: _handleProjectManagerErrorsChanged,
          onAgentErrorsChanged: _handleAgentErrorsChanged,
          onAboutErrorsChanged: _handleAboutErrorsChanged,
        );
      case NavigationPage.home:
        return _previousPage != null
            ? _getPageContentForPage(_previousPage!)
            : const AccountSettingsContent();
      case NavigationPage.dashboard:
        return DashboardPage(projectId: _projectId);
      case NavigationPage.dataEntry:
        return ProjectDetailsPage(
          initialProjectName: _projectName,
          projectId: _projectId,
          onSaveStatusChanged: _handleSaveStatusChanged,
          onErrorStateChanged: _handleErrorStateChanged,
          onAreaErrorsChanged: _handleAreaErrorsChanged,
          onPartnerErrorsChanged: _handlePartnerErrorsChanged,
          onExpenseErrorsChanged: _handleExpenseErrorsChanged,
          onSiteErrorsChanged: _handleSiteErrorsChanged,
          onProjectManagerErrorsChanged: _handleProjectManagerErrorsChanged,
          onAgentErrorsChanged: _handleAgentErrorsChanged,
          onAboutErrorsChanged: _handleAboutErrorsChanged,
        ); // Data Entry shows Project Details page
      case NavigationPage.plotStatus:
        return PlotStatusPage(
          projectId: _projectId,
          onPlotStatusErrorsChanged: _handlePlotStatusErrorsChanged,
        );
      case NavigationPage.documents:
        return DocumentsPage(projectId: _projectId);
      case NavigationPage.settings:
        return SettingsPage(
          projectId: _projectId,
          onProjectDeleted: _handleProjectDeleted,
        );
    }
  }

  Widget _getPageContent() {
    switch (_currentPage) {
      case NavigationPage.account:
        return const AccountSettingsContent();
      case NavigationPage.notifications:
        return const NotificationsPage();
      case NavigationPage.toDoList:
        return const ToDoListPage();
      case NavigationPage.report:
        return ReportPage(projectId: _projectId);
      case NavigationPage.recentProjects:
        return RecentProjectsPage(
          onCreateProject: () => _showCreateProjectDialog(),
          onProjectSelected: (projectId, projectName) {
            setState(() {
              _projectName = projectName;
              _projectId = projectId;
              _previousPage = _currentPage;
              _currentPage = NavigationPage.dataEntry;
            });
          },
        );
      case NavigationPage.allProjects:
        return AllProjectsPage(
          onCreateProject: () => _showCreateProjectDialog(),
        );
      case NavigationPage.trash:
        return const TrashPage();
      case NavigationPage.help:
        return const HelpPage();
      case NavigationPage.logout:
        // For logout, you might want to show a dialog or navigate to login
        return const AccountSettingsContent();
      case NavigationPage.projectDetails:
        return ProjectDetailsPage(
          initialProjectName: _projectName,
          onSaveStatusChanged: _handleSaveStatusChanged,
          onErrorStateChanged: _handleErrorStateChanged,
          onAreaErrorsChanged: _handleAreaErrorsChanged,
          onPartnerErrorsChanged: _handlePartnerErrorsChanged,
          onExpenseErrorsChanged: _handleExpenseErrorsChanged,
          onSiteErrorsChanged: _handleSiteErrorsChanged,
          onProjectManagerErrorsChanged: _handleProjectManagerErrorsChanged,
          onAgentErrorsChanged: _handleAgentErrorsChanged,
          onAboutErrorsChanged: _handleAboutErrorsChanged,
        );
      case NavigationPage.home:
        // This should not be reached as Home navigates back
        return _previousPage != null
            ? _getPageContentForPage(_previousPage!)
            : const AccountSettingsContent();
      case NavigationPage.dashboard:
        return DashboardPage(projectId: _projectId);
      case NavigationPage.dataEntry:
        return ProjectDetailsPage(
          initialProjectName: _projectName,
          projectId: _projectId,
          onSaveStatusChanged: _handleSaveStatusChanged,
          onErrorStateChanged: _handleErrorStateChanged,
          onAreaErrorsChanged: _handleAreaErrorsChanged,
          onPartnerErrorsChanged: _handlePartnerErrorsChanged,
          onExpenseErrorsChanged: _handleExpenseErrorsChanged,
          onSiteErrorsChanged: _handleSiteErrorsChanged,
          onProjectManagerErrorsChanged: _handleProjectManagerErrorsChanged,
          onAgentErrorsChanged: _handleAgentErrorsChanged,
          onAboutErrorsChanged: _handleAboutErrorsChanged,
        ); // Data Entry shows Project Details page
      case NavigationPage.plotStatus:
        return PlotStatusPage(
          projectId: _projectId,
          onPlotStatusErrorsChanged: _handlePlotStatusErrorsChanged,
        );
      case NavigationPage.documents:
        return DocumentsPage(projectId: _projectId);
      case NavigationPage.settings:
        return SettingsPage(
          projectId: _projectId,
          onProjectDeleted: _handleProjectDeleted,
        );
    }
  }

  void _handleProjectDeleted() {
    setState(() {
      _projectName = null;
      _projectId = null;
      _currentPage = NavigationPage.allProjects;
      _previousPage = null;
    });
  }

  void _showCreateProjectDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const CreateProjectDialog(),
    );

    if (result != null && result['projectName'] != null) {
      final projectName = result['projectName'] as String;
      final projectId = result['projectId'] as String?;

      setState(() {
        _projectName = projectName;
        _projectId = projectId;
        _saveStatus = ProjectSaveStatusType.saved;
        _savedTimeAgo = 'Just now';
        _previousPage = _currentPage;
        _currentPage = NavigationPage.dataEntry;
      });
    }
  }

  void _handleErrorStateChanged(bool hasErrors) {
    setState(() {
      _hasDataEntryErrors = hasErrors;
    });
  }

  void _handleAreaErrorsChanged(bool hasErrors) {
    setState(() {
      _hasAreaErrors = hasErrors;
    });
  }

  void _handlePartnerErrorsChanged(bool hasErrors) {
    setState(() {
      _hasPartnerErrors = hasErrors;
    });
  }

  void _handleExpenseErrorsChanged(bool hasErrors) {
    setState(() {
      _hasExpenseErrors = hasErrors;
    });
  }

  void _handleSiteErrorsChanged(bool hasErrors) {
    setState(() {
      _hasSiteErrors = hasErrors;
    });
  }

  void _handleProjectManagerErrorsChanged(bool hasErrors) {
    setState(() {
      _hasProjectManagerErrors = hasErrors;
    });
  }

  void _handleAgentErrorsChanged(bool hasErrors) {
    setState(() {
      _hasAgentErrors = hasErrors;
    });
  }

  void _handleAboutErrorsChanged(bool hasErrors) {
    setState(() {
      _hasAboutErrors = hasErrors;
    });
  }

  void _handlePlotStatusErrorsChanged(bool hasErrors) {
    print(
        '🔴 AccountSettingsScreen._handlePlotStatusErrorsChanged: hasErrors=$hasErrors');
    setState(() {
      _hasPlotStatusErrors = hasErrors;
    });
  }

  void _handleSaveStatusChanged(ProjectSaveStatusType status) {
    setState(() {
      _saveStatus = status;
      if (status == ProjectSaveStatusType.saved) {
        // Update saved time when status changes to saved
        _savedTimeAgo = 'Just now';
        // You could implement a more sophisticated time tracking here
        // For example, using DateTime to calculate actual time difference
      }
    });
  }

  void _handleLogout() async {
    // Sign out from Supabase
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      print('Error signing out: $e');
    }

    // Clear any session data and navigate to login page
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  void _handlePageChange(NavigationPage page) {
    // Handle logout separately
    if (page == NavigationPage.logout) {
      _handleLogout();
      return;
    }

    if (page == NavigationPage.home) {
      setState(() {
        _currentPage = NavigationPage.recentProjects;
        _previousPage = null;
      });
    } else {
      // Track previous page when navigating to project details context pages
      if (page == NavigationPage.projectDetails ||
          page == NavigationPage.dataEntry ||
          page == NavigationPage.dashboard ||
          page == NavigationPage.plotStatus) {
        // Only track if we're not already in project details context
        if (_currentPage != NavigationPage.projectDetails &&
            _currentPage != NavigationPage.dataEntry &&
            _currentPage != NavigationPage.dashboard &&
            _currentPage != NavigationPage.plotStatus) {
          setState(() {
            _previousPage = _currentPage;
            _currentPage = page;
          });
        } else {
          // Already in project details context, just switch pages
          setState(() {
            _currentPage = page;
          });
        }
      } else {
        setState(() {
          _currentPage = page;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProjectContextPage =
        _currentPage == NavigationPage.projectDetails ||
            _currentPage == NavigationPage.dashboard ||
            _currentPage == NavigationPage.dataEntry ||
            _currentPage == NavigationPage.plotStatus ||
            _currentPage == NavigationPage.documents ||
            _currentPage == NavigationPage.settings ||
            _currentPage == NavigationPage.report;
    final isSidebarLoading =
        isProjectContextPage && (_projectId == null || _projectName == null);

    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive breakpoints
          if (constraints.maxWidth < 768) {
            // Mobile: Stack sidebar and content
            return MobileLayout(
              currentPage: _currentPage,
              projectName: _projectName,
              saveStatus: _saveStatus,
              savedTimeAgo: _savedTimeAgo,
              hasDataEntryErrors: _hasDataEntryErrors,
              hasPlotStatusErrors: _hasPlotStatusErrors,
              hasAreaErrors: _hasAreaErrors,
              hasPartnerErrors: _hasPartnerErrors,
              hasExpenseErrors: _hasExpenseErrors,
              hasSiteErrors: _hasSiteErrors,
              hasProjectManagerErrors: _hasProjectManagerErrors,
              hasAgentErrors: _hasAgentErrors,
              hasAboutErrors: _hasAboutErrors,
              isSidebarLoading: isSidebarLoading,
              onPageChanged: _handlePageChange,
              pageContent: _getPageContent(),
            );
          } else if (constraints.maxWidth < 1024) {
            // Tablet: Sidebar and content side by side
            return TabletLayout(
              currentPage: _currentPage,
              projectName: _projectName,
              saveStatus: _saveStatus,
              savedTimeAgo: _savedTimeAgo,
              hasDataEntryErrors: _hasDataEntryErrors,
              hasPlotStatusErrors: _hasPlotStatusErrors,
              hasAreaErrors: _hasAreaErrors,
              hasPartnerErrors: _hasPartnerErrors,
              hasExpenseErrors: _hasExpenseErrors,
              hasSiteErrors: _hasSiteErrors,
              hasProjectManagerErrors: _hasProjectManagerErrors,
              hasAgentErrors: _hasAgentErrors,
              hasAboutErrors: _hasAboutErrors,
              isSidebarLoading: isSidebarLoading,
              onPageChanged: _handlePageChange,
              pageContent: _getPageContent(),
            );
          } else {
            // Desktop: Full layout with fixed sidebar
            return DesktopLayout(
              currentPage: _currentPage,
              projectName: _projectName,
              saveStatus: _saveStatus,
              savedTimeAgo: _savedTimeAgo,
              hasDataEntryErrors: _hasDataEntryErrors,
              hasPlotStatusErrors: _hasPlotStatusErrors,
              hasAreaErrors: _hasAreaErrors,
              hasPartnerErrors: _hasPartnerErrors,
              hasExpenseErrors: _hasExpenseErrors,
              hasSiteErrors: _hasSiteErrors,
              hasProjectManagerErrors: _hasProjectManagerErrors,
              hasAgentErrors: _hasAgentErrors,
              hasAboutErrors: _hasAboutErrors,
              isSidebarLoading: isSidebarLoading,
              onPageChanged: _handlePageChange,
              pageContent: _getPageContent(),
            );
          }
        },
      ),
    );
  }
}

class DesktopLayout extends StatelessWidget {
  final NavigationPage currentPage;
  final Function(NavigationPage) onPageChanged;
  final Widget pageContent;
  final String? projectName;
  final ProjectSaveStatusType? saveStatus;
  final String? savedTimeAgo;
  final bool? hasDataEntryErrors;
  final bool? hasPlotStatusErrors;
  final bool? hasAreaErrors;
  final bool? hasPartnerErrors;
  final bool? hasExpenseErrors;
  final bool? hasSiteErrors;
  final bool? hasProjectManagerErrors;
  final bool? hasAgentErrors;
  final bool? hasAboutErrors;
  final bool isSidebarLoading;

  const DesktopLayout({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
    required this.pageContent,
    this.projectName,
    this.saveStatus,
    this.savedTimeAgo,
    this.hasDataEntryErrors,
    this.hasPlotStatusErrors,
    this.hasAreaErrors,
    this.hasPartnerErrors,
    this.hasExpenseErrors,
    this.hasSiteErrors,
    this.hasProjectManagerErrors,
    this.hasAgentErrors,
    this.hasAboutErrors,
    this.isSidebarLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SidebarNavigation(
          currentPage: currentPage,
          onPageChanged: onPageChanged,
          projectName: projectName,
          saveStatus: saveStatus,
          savedTimeAgo: savedTimeAgo,
          hasDataEntryErrors: hasDataEntryErrors,
          hasPlotStatusErrors: hasPlotStatusErrors,
          hasAreaErrors: hasAreaErrors,
          hasPartnerErrors: hasPartnerErrors,
          hasExpenseErrors: hasExpenseErrors,
          hasSiteErrors: hasSiteErrors,
          hasProjectManagerErrors: hasProjectManagerErrors,
          hasAgentErrors: hasAgentErrors,
          hasAboutErrors: hasAboutErrors,
          isLoading: isSidebarLoading,
        ),
        Expanded(
          child: pageContent,
        ),
      ],
    );
  }
}

class TabletLayout extends StatelessWidget {
  final NavigationPage currentPage;
  final Function(NavigationPage) onPageChanged;
  final Widget pageContent;
  final String? projectName;
  final ProjectSaveStatusType? saveStatus;
  final String? savedTimeAgo;
  final bool? hasDataEntryErrors;
  final bool? hasPlotStatusErrors;
  final bool? hasAreaErrors;
  final bool? hasPartnerErrors;
  final bool? hasExpenseErrors;
  final bool? hasSiteErrors;
  final bool? hasProjectManagerErrors;
  final bool? hasAgentErrors;
  final bool? hasAboutErrors;
  final bool isSidebarLoading;

  const TabletLayout({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
    required this.pageContent,
    this.projectName,
    this.saveStatus,
    this.savedTimeAgo,
    this.hasDataEntryErrors,
    this.hasPlotStatusErrors,
    this.hasAreaErrors,
    this.hasPartnerErrors,
    this.hasExpenseErrors,
    this.hasSiteErrors,
    this.hasProjectManagerErrors,
    this.hasAgentErrors,
    this.hasAboutErrors,
    this.isSidebarLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SidebarNavigation(
          currentPage: currentPage,
          onPageChanged: onPageChanged,
          projectName: projectName,
          saveStatus: saveStatus,
          savedTimeAgo: savedTimeAgo,
          hasDataEntryErrors: hasDataEntryErrors,
          hasPlotStatusErrors: hasPlotStatusErrors,
          hasAreaErrors: hasAreaErrors,
          hasPartnerErrors: hasPartnerErrors,
          hasExpenseErrors: hasExpenseErrors,
          hasSiteErrors: hasSiteErrors,
          hasProjectManagerErrors: hasProjectManagerErrors,
          hasAgentErrors: hasAgentErrors,
          hasAboutErrors: hasAboutErrors,
          isLoading: isSidebarLoading,
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(
              left: 24,
              top: 24,
              right: 24,
              bottom: 24,
            ),
            child: pageContent,
          ),
        ),
      ],
    );
  }
}

class MobileLayout extends StatefulWidget {
  final NavigationPage currentPage;
  final Function(NavigationPage) onPageChanged;
  final Widget pageContent;
  final String? projectName;
  final ProjectSaveStatusType? saveStatus;
  final String? savedTimeAgo;
  final bool? hasDataEntryErrors;
  final bool? hasPlotStatusErrors;
  final bool? hasAreaErrors;
  final bool? hasPartnerErrors;
  final bool? hasExpenseErrors;
  final bool? hasSiteErrors;
  final bool? hasProjectManagerErrors;
  final bool? hasAgentErrors;
  final bool? hasAboutErrors;
  final bool isSidebarLoading;

  const MobileLayout({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
    required this.pageContent,
    this.projectName,
    this.saveStatus,
    this.savedTimeAgo,
    this.hasDataEntryErrors,
    this.hasPlotStatusErrors,
    this.hasAreaErrors,
    this.hasPartnerErrors,
    this.hasExpenseErrors,
    this.hasSiteErrors,
    this.hasProjectManagerErrors,
    this.hasAgentErrors,
    this.hasAboutErrors,
    this.isSidebarLoading = false,
  });

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout> {
  bool _sidebarOpen = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Menu button
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    setState(() {
                      _sidebarOpen = !_sidebarOpen;
                    });
                  },
                ),
              ),
              Expanded(
                child: widget.pageContent,
              ),
            ],
          ),
        ),
        // Sidebar overlay
        if (_sidebarOpen)
          GestureDetector(
            onTap: () {
              setState(() {
                _sidebarOpen = false;
              });
            },
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  elevation: 8,
                  child: SizedBox(
                    width: 252,
                    child: SidebarNavigation(
                      currentPage: widget.currentPage,
                      onPageChanged: (page) {
                        widget.onPageChanged(page);
                        setState(() {
                          _sidebarOpen = false;
                        });
                      },
                      projectName: widget.projectName,
                      saveStatus: widget.saveStatus,
                      savedTimeAgo: widget.savedTimeAgo,
                      hasDataEntryErrors: widget.hasDataEntryErrors,
                      hasPlotStatusErrors: widget.hasPlotStatusErrors,
                      hasAreaErrors: widget.hasAreaErrors,
                      hasPartnerErrors: widget.hasPartnerErrors,
                      hasExpenseErrors: widget.hasExpenseErrors,
                      hasSiteErrors: widget.hasSiteErrors,
                      hasProjectManagerErrors: widget.hasProjectManagerErrors,
                      hasAgentErrors: widget.hasAgentErrors,
                      hasAboutErrors: widget.hasAboutErrors,
                      isLoading: widget.isSidebarLoading,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
