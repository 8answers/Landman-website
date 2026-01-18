import 'package:flutter/material.dart';
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
import '../pages/settings_page.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  NavigationPage _currentPage = NavigationPage.account;
  NavigationPage? _previousPage;
  String? _projectName;
  String? _projectId;
  ProjectSaveStatusType _saveStatus = ProjectSaveStatusType.saved;
  String? _savedTimeAgo;
  bool _hasDataEntryErrors = false;

  Widget _getPageContentForPage(NavigationPage page) {
    switch (page) {
      case NavigationPage.account:
        return const AccountSettingsContent();
      case NavigationPage.notifications:
        return const NotificationsPage();
      case NavigationPage.toDoList:
        return const ToDoListPage();
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
        );
      case NavigationPage.home:
        return _previousPage != null ? _getPageContentForPage(_previousPage!) : const AccountSettingsContent();
      case NavigationPage.dashboard:
        return DashboardPage(projectId: _projectId);
      case NavigationPage.dataEntry:
        return ProjectDetailsPage(
          initialProjectName: _projectName,
          projectId: _projectId,
          onSaveStatusChanged: _handleSaveStatusChanged,
          onErrorStateChanged: _handleErrorStateChanged,
        ); // Data Entry shows Project Details page
      case NavigationPage.plotStatus:
        return PlotStatusPage(projectId: _projectId);
      case NavigationPage.settings:
        return const SettingsPage();
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
        );
      case NavigationPage.home:
        // This should not be reached as Home navigates back
        return _previousPage != null ? _getPageContentForPage(_previousPage!) : const AccountSettingsContent();
      case NavigationPage.dashboard:
        return DashboardPage(projectId: _projectId);
      case NavigationPage.dataEntry:
        return ProjectDetailsPage(
          initialProjectName: _projectName,
          projectId: _projectId,
          onSaveStatusChanged: _handleSaveStatusChanged,
        ); // Data Entry shows Project Details page
      case NavigationPage.plotStatus:
        return PlotStatusPage(projectId: _projectId);
      case NavigationPage.settings:
        return const SettingsPage();
    }
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

  @override
  Widget build(BuildContext context) {
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
              onPageChanged: (page) {
                if (page == NavigationPage.home) {
                  if (_previousPage != null) {
                    setState(() {
                      _currentPage = _previousPage!;
                      _previousPage = null;
                    });
                  }
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
              },
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
              onPageChanged: (page) {
                if (page == NavigationPage.home) {
                  if (_previousPage != null) {
                    setState(() {
                      _currentPage = _previousPage!;
                      _previousPage = null;
                    });
                  }
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
              },
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
              onPageChanged: (page) {
                if (page == NavigationPage.home) {
                  // Go back to previous page
                  if (_previousPage != null) {
                    setState(() {
                      _currentPage = _previousPage!;
                      _previousPage = null;
                    });
                  }
                } else {
                  // Track previous page when navigating to project details
                  if (page == NavigationPage.projectDetails) {
                    setState(() {
                      _previousPage = _currentPage;
                      _currentPage = page;
                    });
                  } else {
                    setState(() {
                      _currentPage = page;
                    });
                  }
                }
              },
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

  const DesktopLayout({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
    required this.pageContent,
    this.projectName,
    this.saveStatus,
    this.savedTimeAgo,
    this.hasDataEntryErrors,
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

class TabletLayout extends StatelessWidget {
  final NavigationPage currentPage;
  final Function(NavigationPage) onPageChanged;
  final Widget pageContent;
  final String? projectName;
  final ProjectSaveStatusType? saveStatus;
  final String? savedTimeAgo;
  final bool? hasDataEntryErrors;

  const TabletLayout({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
    required this.pageContent,
    this.projectName,
    this.saveStatus,
    this.savedTimeAgo,
    this.hasDataEntryErrors,
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

  const MobileLayout({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
    required this.pageContent,
    this.projectName,
    this.saveStatus,
    this.savedTimeAgo,
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

