import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;
//
enum DashboardTab {
  overview,
  site,
  partners,
  projectManagers,
  agents,
  compensation,
}

class DashboardPage extends StatefulWidget {
  final String? projectId;
  
  const DashboardPage({super.key, this.projectId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  Map<String, dynamic>? _dashboardData;
  List<Map<String, dynamic>> _siteLayouts = [];
  double _projectManagersCompensation = 0.0;
  double _agentsCompensation = 0.0;
  List<Map<String, dynamic>> _partners = [];
  List<Map<String, dynamic>> _projectManagers = [];
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _compensationLayouts = [];
  double _totalCompensation = 0.0;
  
  // Loading state flags for individual data sections
  bool _isPartnersLoading = false;
  bool _isProjectManagersLoading = false;
  bool _isAgentsLoading = false;
  bool _isSiteDataLoading = false;
  
  // Scroll controllers for tables
  final ScrollController _partnersTableScrollController = ScrollController();
  final ScrollController _projectManagersTableScrollController = ScrollController();
  final ScrollController _layoutPlotsTableScrollController = ScrollController();
  final ScrollController _agentsTableScrollController = ScrollController();
  final ScrollController _compensationTableScrollController = ScrollController();
  
  // Tab state
  DashboardTab _activeTab = DashboardTab.overview;

  @override
  void initState() {
    super.initState();
    if (widget.projectId != null) {
      _loadDashboardData();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void didUpdateWidget(DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.projectId != oldWidget.projectId) {
      if (widget.projectId != null) {
        _loadDashboardData();
      } else {
        setState(() {
          _dashboardData = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDashboardData() async {
    if (widget.projectId == null) return;
    final projectId = widget.projectId!;

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Fetch project data
      final projectData = await _supabase
          .from('projects')
          .select()
          .eq('id', projectId)
          .eq('user_id', userId)
          .single();

      // Fetch expenses
      final expenses = await _supabase
          .from('expenses')
          .select('amount')
          .eq('project_id', projectId);

      // Fetch non-sellable areas
      final nonSellableAreas = await _supabase
          .from('non_sellable_areas')
          .select('area')
          .eq('project_id', projectId);

      // Fetch layouts
      final layouts = await _supabase
          .from('layouts')
          .select('id, name')
          .eq('project_id', projectId);

      final layoutIds = layouts.map((l) => l['id'] as String).toList();

      // Fetch plots - optimized: single query for all plots
      List<Map<String, dynamic>> allPlots = [];
      if (layoutIds.isNotEmpty) {
        // Use 'in' filter to get all plots in one query instead of multiple
        final plots = await _supabase
            .from('plots')
            .select('id, layout_id, area, status, sale_price')
            .inFilter('layout_id', layoutIds);
        allPlots = List<Map<String, dynamic>>.from(plots);
      }

      // Calculate metrics
      final estimatedDevelopmentCost = (projectData['estimated_development_cost'] as num?)?.toDouble() ?? 0.0;
      
      final totalExpenses = expenses.fold<double>(
        0.0,
        (sum, expense) => sum + ((expense['amount'] as num?)?.toDouble() ?? 0.0),
      );

      final totalArea = (projectData['total_area'] as num?)?.toDouble() ?? 0.0;
      final sellingArea = (projectData['selling_area'] as num?)?.toDouble() ?? 0.0;

      final nonSellableArea = nonSellableAreas.fold<double>(
        0.0,
        (sum, area) => sum + ((area['area'] as num?)?.toDouble() ?? 0.0),
      );

      final allInCost = sellingArea > 0 ? totalExpenses / sellingArea : 0.0;

      final totalLayouts = layouts.length;
      final totalPlots = allPlots.length;
      final availablePlots = allPlots.where((p) => p['status'] == 'available').length;
      final soldPlots = allPlots.where((p) => p['status'] == 'sold').length;
      final saleProgress = totalPlots > 0 ? (soldPlots / totalPlots) * 100 : 0.0;

      // Calculate total sales value = sum of (sale_price * area) for all sold plots
      final totalSalesValue = allPlots
          .where((p) => p['status'] == 'sold')
          .fold<double>(
            0.0,
            (sum, plot) {
              final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
              final area = ((plot['area'] as num?)?.toDouble() ?? 0.0);
              return sum + (salePrice * area);
            },
          );

      // Calculate sum of sale prices (per sqft) for all sold plots across all layouts
      final totalSalePriceSum = allPlots
          .where((p) => p['status'] == 'sold')
          .fold<double>(
            0.0,
            (sum, plot) {
              final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
              return sum + salePrice;
            },
          );

      // Average Sale Price = Sum of sale prices of all layouts / Number of plots sold
      final avgSalePricePerSqft = soldPlots > 0 ? totalSalePriceSum / soldPlots : 0.0;

      // Calculate sales by layout
      final salesByLayout = <Map<String, dynamic>>[];
      for (var layout in layouts) {
        final layoutId = layout['id'] as String;
        final layoutPlots = allPlots.where((p) => p['layout_id'] == layoutId).toList();
        final layoutSoldPlots = layoutPlots.where((p) => p['status'] == 'sold').toList();
        // Calculate layout sales value = sum of (sale_price * area) for all sold plots in this layout
        final layoutSalesValue = layoutSoldPlots.fold<double>(
          0.0,
          (sum, plot) {
            final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
            final area = ((plot['area'] as num?)?.toDouble() ?? 0.0);
            return sum + (salePrice * area);
          },
        );
        final layoutSalePercentage = layoutPlots.isNotEmpty 
            ? (layoutSoldPlots.length / layoutPlots.length) * 100 
            : 0.0;

        salesByLayout.add({
          'name': layout['name'] as String,
          'totalPlots': layoutPlots.length,
          'soldPlots': layoutSoldPlots.length,
          'salesValue': layoutSalesValue,
          'salePercentage': layoutSalePercentage,
        });
      }

      // Set loading flags for data sections and store dashboard data
      setState(() {
        _dashboardData = {
          'estimatedDevelopmentCost': estimatedDevelopmentCost,
          'totalExpenses': totalExpenses,
          'allInCost': allInCost,
          'totalArea': totalArea,
          'sellingArea': sellingArea,
          'nonSellableArea': nonSellableArea,
          'totalLayouts': totalLayouts,
          'totalPlots': totalPlots,
          'availablePlots': availablePlots,
          'soldPlots': soldPlots,
          'saleProgress': saleProgress,
          'totalSalesValue': totalSalesValue,
          'avgSalePricePerSqft': avgSalePricePerSqft,
          'salesByLayout': salesByLayout,
        };
        _isPartnersLoading = true;
        _isProjectManagersLoading = true;
        _isAgentsLoading = true;
        if (_activeTab == DashboardTab.site) {
          _isSiteDataLoading = true;
        }
      });
      
      // Load all required data in parallel for better performance
      // Note: Always load compensation data (partners, project managers, agents) for net profit calculation
      // regardless of the active tab
      try {
        await Future.wait([
          _loadPartnersData(),
          _loadProjectManagersData(),
          _loadAgentsData(),
          _loadSiteData(), // Always load site data to support agent sold plot checking
        ]).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            print('Warning: Data loading timeout after 30 seconds');
            return [];
          },
        );
      } catch (e) {
        print('Error during parallel data loading: $e');
      }
      
      // Calculate and store net profit after all compensation data is loaded
      // Gross Profit = Sales - Expenses (same calculation as in _buildProfitAndROISection)
      final grossProfit = totalSalesValue - totalExpenses;
      
      // Total Compensation = Project Managers + Agents (same calculation as in _buildProfitAndROISection)
      final totalCompensation = _calculateTotalProjectManagersCompensation() + _calculateTotalAgentsCompensation();
      
      // Net Profit = Gross Profit - Total Compensation (same as overview section)
      final netProfit = grossProfit - totalCompensation;
      
      // Update _dashboardData with net profit and mark loading as complete
      setState(() {
        _dashboardData = {
          ..._dashboardData!,
          'netProfit': netProfit,
        };
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading dashboard data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSiteData() async {
    if (widget.projectId == null || _dashboardData == null) return;
    final projectId = widget.projectId!;

    // Set loading flag at the start if not already set
    if (!_isSiteDataLoading) {
      setState(() {
        _isSiteDataLoading = true;
      });
    }

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Fetch layouts with full plot details
      final layouts = await _supabase
          .from('layouts')
          .select('id, name')
          .eq('project_id', projectId);

      final layoutIds = layouts.map((l) => l['id'] as String).toList();
      if (layoutIds.isEmpty) {
        setState(() {
          _siteLayouts = [];
        });
        return;
      }

      // Optimize: Fetch all plots in one query, ordered by creation time to maintain consistent order
      final allPlots = await _supabase
          .from('plots')
          .select('*')
          .inFilter('layout_id', layoutIds)
          .order('created_at', ascending: true);

      // Get all plot IDs to fetch partners in one query
      final plotIds = allPlots.map((p) => p['id'] as String).toList();
      
      // Fetch all plot partners in one query
      final allPlotPartners = plotIds.isNotEmpty
          ? await _supabase
              .from('plot_partners')
              .select('plot_id, partner_name')
              .inFilter('plot_id', plotIds)
          : <Map<String, dynamic>>[];

      // Group partners by plot_id
      final partnersByPlotId = <String, List<String>>{};
      for (var partner in allPlotPartners) {
        final plotId = partner['plot_id'] as String;
        final partnerName = partner['partner_name'] as String;
        if (!partnersByPlotId.containsKey(plotId)) {
          partnersByPlotId[plotId] = [];
        }
        partnersByPlotId[plotId]!.add(partnerName);
      }

      // Build site layouts with plots
      final siteLayouts = <Map<String, dynamic>>[];
      for (var layout in layouts) {
        final layoutId = layout['id'] as String;
        final layoutPlots = allPlots
            .where((p) => p['layout_id'] == layoutId)
            .map((plot) => {
              ...plot,
              'partners': partnersByPlotId[plot['id'] as String] ?? [],
            })
            .toList();

        siteLayouts.add({
          'id': layoutId,
          'name': layout['name'] as String,
          'plots': layoutPlots,
        });
      }

      // Fetch project managers and calculate compensation
      final projectManagers = await _supabase
          .from('project_managers')
          .select('*')
          .eq('project_id', projectId);

      double projectManagersCompensation = 0.0;
      // Calculate compensation based on type (simplified - you may need to adjust based on your compensation logic)
      for (var manager in projectManagers) {
        final compensationType = manager['compensation_type'] as String? ?? '';
        final compensation = (manager['compensation'] as num?)?.toDouble() ?? 0.0;
        // Add logic here to calculate based on compensation type
        projectManagersCompensation += compensation;
      }

      // Fetch agents and calculate compensation
      final agents = await _supabase
          .from('agents')
          .select('*')
          .eq('project_id', projectId);

      double agentsCompensation = 0.0;
      // Calculate compensation based on type (simplified - you may need to adjust based on your compensation logic)
      for (var agent in agents) {
        final compensationType = agent['compensation_type'] as String? ?? '';
        final compensation = (agent['compensation'] as num?)?.toDouble() ?? 0.0;
        // Add logic here to calculate based on compensation type
        agentsCompensation += compensation;
      }

      setState(() {
        _siteLayouts = siteLayouts;
        _projectManagersCompensation = projectManagersCompensation;
        _agentsCompensation = agentsCompensation;
        _isSiteDataLoading = false;
      });
    } catch (e) {
      print('Error loading site data: $e');
      setState(() {
        _isSiteDataLoading = false;
      });
    }
  }

  Future<void> _loadPartnersData() async {
    if (widget.projectId == null) return;
    final projectId = widget.projectId!;

    try {
      final partners = await _supabase
          .from('partners')
          .select('*')
          .eq('project_id', projectId)
          .order('name');

      setState(() {
        _partners = partners.map((p) => {
          'name': (p['name'] ?? '').toString(),
          'amount': (p['amount'] as num?)?.toDouble() ?? 0.0,
        }).toList();
        _isPartnersLoading = false;
      });
    } catch (e) {
      print('Error loading partners data: $e');
      setState(() {
        _isPartnersLoading = false;
      });
    }
  }

  Future<void> _loadProjectManagersData() async {
    if (widget.projectId == null) return;
    final projectId = widget.projectId!;

    try {
      final projectManagers = await _supabase
          .from('project_managers')
          .select('*')
          .eq('project_id', projectId)
          .order('name');

      setState(() {
        _projectManagers = projectManagers.map((pm) => {
          'id': pm['id'],
          'name': (pm['name'] ?? '').toString(),
          'compensation_type': (pm['compensation_type'] ?? '').toString(),
          'earning_type': (pm['earning_type'] ?? '').toString(),
          'percentage': (pm['percentage'] as num?)?.toDouble(),
          'fixed_fee': (pm['fixed_fee'] as num?)?.toDouble(),
          'monthly_fee': (pm['monthly_fee'] as num?)?.toDouble(),
          'months': (pm['months'] as num?)?.toInt(),
        }).toList();
        _isProjectManagersLoading = false;
      });
    } catch (e) {
      print('Error loading project managers data: $e');
      setState(() {
        _isProjectManagersLoading = false;
      });
    }
  }

  Future<void> _loadAgentsData() async {
    if (widget.projectId == null) return;
    final projectId = widget.projectId!;

    try {
      final agents = await _supabase
          .from('agents')
          .select('*')
          .eq('project_id', projectId)
          .order('name');

      setState(() {
        _agents = agents.map((agent) => {
          'id': agent['id'],
          'name': (agent['name'] ?? '').toString(),
          'compensation_type': (agent['compensation_type'] ?? '').toString(),
          'earning_type': (agent['earning_type'] ?? '').toString(),
          'percentage': (agent['percentage'] as num?)?.toDouble(),
          'fixed_fee': (agent['fixed_fee'] as num?)?.toDouble(),
          'monthly_fee': (agent['monthly_fee'] as num?)?.toDouble(),
          'months': (agent['months'] as num?)?.toInt(),
          'per_sqft_fee': (agent['per_sqft_fee'] as num?)?.toDouble(),
        }).toList();
        _isAgentsLoading = false;
      });
    } catch (e) {
      print('Error loading agents data: $e');
      setState(() {
        _isAgentsLoading = false;
      });
    }
  }

  Future<void> _loadCompensationData() async {
    if (widget.projectId == null || _dashboardData == null) return;
    final projectId = widget.projectId!;

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Fetch layouts
      final layouts = await _supabase
          .from('layouts')
          .select('id, name')
          .eq('project_id', projectId);

      final layoutIds = layouts.map((l) => l['id'] as String).toList();
      final compensationLayouts = <Map<String, dynamic>>[];
      double totalCompensation = 0.0;

      for (var layout in layouts) {
        final layoutId = layout['id'] as String;
        final plots = await _supabase
            .from('plots')
            .select('*')
            .eq('layout_id', layoutId)
            .order('created_at', ascending: true);

        // Load agent information for each plot
        final plotsWithCompensation = <Map<String, dynamic>>[];
        for (var plot in plots) {
          final plotId = plot['id'] as String;
          
          // Get agent for this plot from agent_blocks
          final agentBlocks = await _supabase
              .from('agent_blocks')
              .select('agent_id')
              .eq('plot_id', plotId)
              .limit(1);
          
          String? agentName;
          double? compensationPerSqft;
          double? projectManagerCompensation;
          
          if (agentBlocks.isNotEmpty) {
            final agentId = agentBlocks[0]['agent_id'] as String;
            final agent = await _supabase
                .from('agents')
                .select('name, per_sqft_fee')
                .eq('id', agentId)
                .single();
            
            agentName = agent['name'] as String?;
            compensationPerSqft = (agent['per_sqft_fee'] as num?)?.toDouble();
          } else {
            // Check if plot has agent_name directly
            agentName = plot['agent_name'] as String?;
          }
          
          // Calculate compensation for this plot
          final area = (plot['area'] as num?)?.toDouble() ?? 0.0;
          final plotStatus = (plot['status'] as String? ?? 'available').toLowerCase();
          final plotCompensation = (compensationPerSqft != null && plotStatus == 'sold')
              ? compensationPerSqft * area 
              : 0.0;
          
          // Only add compensation for sold plots
          if (plotStatus == 'sold') {
            totalCompensation += plotCompensation;
          }
          
          plotsWithCompensation.add({
            ...plot,
            'agent_name': agentName,
            'compensation_per_sqft': compensationPerSqft ?? 0.0,
            'compensation': plotCompensation,
          });
        }

        // Calculate layout totals
        final allInCost = _dashboardData!['allInCost'] as double;
        double totalArea = 0.0;
        double totalPlotCost = 0.0;
        double totalSaleValue = 0.0;
        int availablePlots = 0;
        int soldPlots = 0;
        
        for (var plot in plotsWithCompensation) {
          final area = (plot['area'] as num?)?.toDouble() ?? 0.0;
          final status = (plot['status'] as String? ?? 'available').toLowerCase();
          final salePrice = (plot['sale_price'] as num?)?.toDouble() ?? 0.0;
          
          totalArea += area;
          totalPlotCost += area * allInCost;
          
          if (status == 'sold') {
            soldPlots++;
            totalSaleValue += salePrice * area;
          } else {
            availablePlots++;
          }
        }
        
        final grossProfit = totalSaleValue - totalPlotCost;
        final layoutCompensation = plotsWithCompensation.fold<double>(
          0.0,
          (sum, plot) {
            final status = (plot['status'] as String? ?? 'available').toLowerCase();
            if (status == 'sold') {
              return sum + (plot['compensation'] as double? ?? 0.0);
            }
            return sum;
          },
        );

        compensationLayouts.add({
          'id': layoutId,
          'name': layout['name'] as String,
          'plots': plotsWithCompensation,
          'totalPlots': plotsWithCompensation.length,
          'availablePlots': availablePlots,
          'soldPlots': soldPlots,
          'grossProfit': grossProfit,
          'totalCompensation': layoutCompensation,
        });
      }

      setState(() {
        _compensationLayouts = compensationLayouts;
        _totalCompensation = totalCompensation;
      });
    } catch (e) {
      print('Error loading compensation data: $e');
    }
  }

  String _formatCurrency(double value) {
    if (value == 0) return '₹ 0.00';
    
    // Format with Indian numbering system
    final parts = value.toStringAsFixed(2).split('.');
    final integerPart = parts[0];
    final decimalPart = parts[1];
    
    String formatted = '';
    final length = integerPart.length;
    
    if (length <= 3) {
      formatted = integerPart;
    } else {
      final lastThree = integerPart.substring(length - 3);
      final remaining = integerPart.substring(0, length - 3);
      
      // Add commas every 2 digits from right
      String formattedRemaining = '';
      for (int i = remaining.length - 1; i >= 0; i--) {
        if ((remaining.length - 1 - i) > 0 && (remaining.length - 1 - i) % 2 == 0) {
          formattedRemaining = ',' + formattedRemaining;
        }
        formattedRemaining = remaining[i] + formattedRemaining;
      }
      
      formatted = formattedRemaining.isEmpty ? lastThree : '$formattedRemaining,$lastThree';
    }
    
    return '₹ $formatted.$decimalPart';
  }

  String _formatCurrencyNumber(double value) {
    if (value == 0) return '0.00';
    
    // Format with Indian numbering system (without rupee symbol)
    final parts = value.toStringAsFixed(2).split('.');
    final integerPart = parts[0];
    final decimalPart = parts[1];
    
    String formatted = '';
    final length = integerPart.length;
    
    if (length <= 3) {
      formatted = integerPart;
    } else {
      final lastThree = integerPart.substring(length - 3);
      final remaining = integerPart.substring(0, length - 3);
      
      // Add commas every 2 digits from right
      String formattedRemaining = '';
      for (int i = remaining.length - 1; i >= 0; i--) {
        if ((remaining.length - 1 - i) > 0 && (remaining.length - 1 - i) % 2 == 0) {
          formattedRemaining = ',' + formattedRemaining;
        }
        formattedRemaining = remaining[i] + formattedRemaining;
      }
      
      formatted = formattedRemaining.isEmpty ? lastThree : '$formattedRemaining,$lastThree';
    }
    
    return '$formatted.$decimalPart';
  }

  String _formatArea(double value) {
    if (value == 0) return '0.00';
    
    // Format with Indian numbering system
    final parts = value.toStringAsFixed(2).split('.');
    final integerPart = parts[0];
    final decimalPart = parts[1];
    
    String formatted = '';
    final length = integerPart.length;
    
    if (length <= 3) {
      formatted = integerPart;
    } else {
      final lastThree = integerPart.substring(length - 3);
      final remaining = integerPart.substring(0, length - 3);
      
      // Add commas every 2 digits from right
      String formattedRemaining = '';
      for (int i = remaining.length - 1; i >= 0; i--) {
        if ((remaining.length - 1 - i) > 0 && (remaining.length - 1 - i) % 2 == 0) {
          formattedRemaining = ',' + formattedRemaining;
        }
        formattedRemaining = remaining[i] + formattedRemaining;
      }
      
      formatted = formattedRemaining.isEmpty ? lastThree : '$formattedRemaining,$lastThree';
    }
    
    return '$formatted.$decimalPart';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header section - Fixed at top
        Padding(
          padding: const EdgeInsets.only(
            top: 0,
            left: 0,
            right: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project Overview',
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A high-level snapshot of project cost, area, layouts, and sales progress.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Tab navigation bar - Fixed at top
        Transform.translate(
          offset: const Offset(-22, 0), // Move left to start from sidebar shadow end
          child: Container(
            width: MediaQuery.of(context).size.width - 0 + 24, // Full screen width minus sidebar+shadow, plus extend 24px to right edge
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
              const SizedBox(width: 24),
                // Overview tab
                GestureDetector(
                  onTap: () => setState(() => _activeTab = DashboardTab.overview),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: _activeTab == DashboardTab.overview
                        ? BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFF0C8CE9),
                                width: 2,
                              ),
                            ),
                          )
                        : null,
                    child: Center(
                      child: Text(
                        'Overview',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: _activeTab == DashboardTab.overview
                              ? FontWeight.w500
                              : FontWeight.normal,
                          color: _activeTab == DashboardTab.overview
                              ? const Color(0xFF0C8CE9)
                              : const Color(0xFF5C5C5C),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 36),
                // Site tab
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _activeTab = DashboardTab.site;
                      if (_dashboardData != null && _siteLayouts.isEmpty) {
                        _isSiteDataLoading = true;
                        _loadSiteData();
                      }
                    });
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: _activeTab == DashboardTab.site
                        ? BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFF0C8CE9),
                                width: 2,
                              ),
                            ),
                          )
                        : null,
                    child: Center(
                      child: Text(
                        'Site',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: _activeTab == DashboardTab.site
                              ? FontWeight.w500
                              : FontWeight.normal,
                          color: _activeTab == DashboardTab.site
                              ? const Color(0xFF0C8CE9)
                              : const Color(0xFF5C5C5C),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 36),
                // Partner(s) tab
                GestureDetector(
                  onTap: () => setState(() => _activeTab = DashboardTab.partners),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: _activeTab == DashboardTab.partners
                        ? BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFF0C8CE9),
                                width: 2,
                              ),
                            ),
                          )
                        : null,
                    child: Center(
                      child: Text(
                        'Partner(s)',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: _activeTab == DashboardTab.partners
                              ? FontWeight.w500
                              : FontWeight.normal,
                          color: _activeTab == DashboardTab.partners
                              ? const Color(0xFF0C8CE9)
                              : const Color(0xFF5C5C5C),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 36),
                // Project Manager(s) tab
                GestureDetector(
                  onTap: () {
                    setState(() => _activeTab = DashboardTab.projectManagers);
                    _loadProjectManagersData();
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: _activeTab == DashboardTab.projectManagers
                        ? BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFF0C8CE9),
                                width: 2,
                              ),
                            ),
                          )
                        : null,
                    child: Center(
                      child: Text(
                        'Project Manager(s)',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: _activeTab == DashboardTab.projectManagers
                              ? FontWeight.w500
                              : FontWeight.normal,
                          color: _activeTab == DashboardTab.projectManagers
                              ? const Color(0xFF0C8CE9)
                              : const Color(0xFF5C5C5C),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 36),
                // Agent(s) tab
                GestureDetector(
                  onTap: () {
                    setState(() => _activeTab = DashboardTab.agents);
                    _loadAgentsData();
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: _activeTab == DashboardTab.agents
                        ? BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFF0C8CE9),
                                width: 2,
                              ),
                            ),
                          )
                        : null,
                    child: Center(
                      child: Text(
                        'Agent(s)',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: _activeTab == DashboardTab.agents
                              ? FontWeight.w500
                              : FontWeight.normal,
                          color: _activeTab == DashboardTab.agents
                              ? const Color(0xFF0C8CE9)
                              : const Color(0xFF5C5C5C),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 36),
                // Compensation tab
                GestureDetector(
                  onTap: () {
                    setState(() => _activeTab = DashboardTab.compensation);
                    if (_dashboardData != null) {
                      _loadCompensationData();
                    }
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: _activeTab == DashboardTab.compensation
                        ? BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFF0C8CE9),
                                width: 2,
                              ),
                            ),
                          )
                        : null,
                    child: Center(
                      child: Text(
                        'Compensation',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: _activeTab == DashboardTab.compensation
                              ? FontWeight.w500
                              : FontWeight.normal,
                          color: _activeTab == DashboardTab.compensation
                              ? const Color(0xFF0C8CE9)
                              : const Color(0xFF5C5C5C),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        const SizedBox(height: 16),
        // Content - Scrollable
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              clipBehavior: Clip.hardEdge,
              padding: const EdgeInsets.only(
                top: 0,
                left: 0,
                right: 24,
                bottom: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tab content - Conditional based on data availability
                  if (widget.projectId == null) ...[
            Center(
              child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
                      'No project selected',
          style: GoogleFonts.inter(
                        fontSize: 18,
                        color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
                      'Please select a project to view the dashboard',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
                  ] else if (_dashboardData == null) ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No data available',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: const Color(0xFF5C5C5C),
                          ),
                        ),
                      ),
                    ),
                  ] else if (_activeTab == DashboardTab.overview) ...[
                    // Project Cost & Area Summary
                    _buildCostAndAreaSummary(),
                    const SizedBox(height: 24),
                    
                    // Break-even section
                    _buildBreakEvenSection(),
                    const SizedBox(height: 24),
                    
                    // Profit and ROI section
                    _buildProfitAndROISection(),
                    const SizedBox(height: 24),
                    
                    // Site Overview
                    _buildSiteOverview(),
                    const SizedBox(height: 24),
                    
                    // Sales Highlights
                    _buildSalesHighlights(),
                    const SizedBox(height: 24),
                    
                    // Sales by Layout
                    _buildSalesByLayout(),
                  ] else if (_activeTab == DashboardTab.site) ...[
                    _buildSiteTabContent(),
                  ] else if (_activeTab == DashboardTab.partners) ...[
                    // Partners tab content
                    _buildPartnersSection(),
                  ] else if (_activeTab == DashboardTab.projectManagers) ...[
                    // Project Managers tab content
                    _buildProjectManagersSection(),
                  ] else if (_activeTab == DashboardTab.agents) ...[
                    // Agents tab content
                    _buildAgentsSection(),
                  ] else if (_activeTab == DashboardTab.compensation) ...[
                    // Compensation tab content
                    _buildCompensationSection(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCostAndAreaSummary() {
    return Container(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project Cost & Area Summary',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Key financial and land metrics for this project.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // First row
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Estimated Development Cost',
                  _formatCurrency(_dashboardData!['estimatedDevelopmentCost'] as double),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildMetricCard(
                  'Total Expenses',
                  _formatCurrency(_dashboardData!['totalExpenses'] as double),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildMetricCard(
                  'All-in Cost (₹ / sqft)',
                  _formatCurrency(_dashboardData!['allInCost'] as double),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Second row
          Row(
            children: [
              Expanded(
                child: _buildMetricCardWithUnit(
                  'Total Project Area',
                  _formatArea(_dashboardData!['totalArea'] as double),
                  'sqft',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildMetricCardWithUnit(
                  'Approved Selling Area ',
                  _formatArea(_dashboardData!['sellingArea'] as double),
                  'sqft',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildMetricCardWithUnit(
                  'Non-Sellable Area',
                  _formatArea(_dashboardData!['nonSellableArea'] as double),
                  'sqft',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakEvenSection() {
    final totalExpenses = _dashboardData!['totalExpenses'] as double;
    final salesTillDate = _dashboardData!['totalSalesValue'] as double;
    final breakEvenAmount = salesTillDate - totalExpenses;
    
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Break-even',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              // Break-even Amount card
              Container(
                width: 320,
                height: 101,
                padding: const EdgeInsets.all(16),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Break-even Amount',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF5C5C5C),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatCurrency(breakEvenAmount),
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.normal,
                        color: breakEvenAmount >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Sales Till Date card
              Container(
                width: 320,
                height: 101,
                padding: const EdgeInsets.all(16),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sales Till Date',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF5C5C5C),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatCurrency(salesTillDate),
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfitAndROISection() {
    final totalExpenses = _dashboardData!['totalExpenses'] as double;
    final salesTillDate = _dashboardData!['totalSalesValue'] as double;
    
    // Calculate Gross Profit using the same logic as _calculateTotalGrossProfit()
    // This only counts cost of sold plots, not all plots
    final grossProfit = _calculateTotalGrossProfit();
    
    // Calculate Total Compensation (Project Managers + Agents)
    final totalCompensation = _calculateTotalProjectManagersCompensation() + _calculateTotalAgentsCompensation();
    
    // Net Profit = Gross Profit - Total Compensation
    final netProfit = grossProfit - totalCompensation;
    
    // Calculate Profit Margin (%) = (Net Profit / Total Sales Value) * 100
    final profitMargin = salesTillDate > 0 ? (netProfit / salesTillDate) * 100 : 0.0;
    
    // Calculate ROI (%) = (Net Profit / Total Expenses) * 100
    final roi = totalExpenses > 0 ? (netProfit / totalExpenses) * 100 : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profit and ROI',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          // First row: Gross Profit and Net Profit
          Row(
            children: [
              _buildProfitCard(
                'Gross Profit',
                _formatCurrency(grossProfit),
              ),
              const SizedBox(width: 24),
              _buildProfitCard(
                'Net Profit',
                _formatCurrency(netProfit),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Second row: Profit Margin and ROI
          Row(
            children: [
              _buildProfitCard(
                'Profit Margin (%)',
                '${profitMargin.toStringAsFixed(2)}%',
              ),
              const SizedBox(width: 24),
              _buildProfitCard(
                'ROI (%)',
                '${roi.toStringAsFixed(2)}%',
                valueColor: roi < 0 ? Colors.red : Colors.black,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfitCard(String label, String value, {Color? valueColor}) {
    return Container(
      width: 320,
      height: 101,
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5C5C5C),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.normal,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiteOverview() {
    final saleProgress = _dashboardData!['saleProgress'] as double;
    final remainingPercentage = 100 - saleProgress;
    
    return Container(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Site Overview',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Distribution of layouts and current plot availability.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // Layout and plot metrics
          Row(
            children: [
              _buildSmallMetricCard(
                'Total Layouts',
                '${_dashboardData!['totalLayouts']}',
              ),
              const SizedBox(width: 40),
              _buildSmallMetricCard(
                'Total Plots',
                _formatNumber(_dashboardData!['totalPlots'] as int),
              ),
              const SizedBox(width: 24),
              _buildSmallMetricCard(
                'Available Plots',
                _formatNumber(_dashboardData!['availablePlots'] as int),
                valueColor: const Color(0xFF06AB00),
              ),
              const SizedBox(width: 24),
              _buildSmallMetricCard(
                'Sold Plots',
                _formatNumber(_dashboardData!['soldPlots'] as int),
                valueColor: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Sale Progress
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sale Progress',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF5C5C5C),
                    ),
                  ),
                  Text(
                    '${saleProgress.toStringAsFixed(2)}% Complete',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF5C5C5C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildProgressBar(saleProgress, remainingPercentage),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(double soldPercentage, double remainingPercentage) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final remainingWidth = totalWidth * (remainingPercentage / 100);
        final soldWidth = totalWidth * (soldPercentage / 100);
        
        return SizedBox(
          height: 32,
          child: Row(
            children: [
              // Remaining (green) - left side
              if (remainingPercentage > 0)
                Container(
                  width: remainingWidth,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(100),
                      bottomLeft: Radius.circular(100),
                    ),
                    border: Border.all(
                      color: const Color(0xFF707070).withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '${remainingPercentage.toStringAsFixed(0)}% Remaining',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Sold (red) - right side
              if (soldPercentage > 0)
                Container(
                  width: soldWidth,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(100),
                      bottomRight: Radius.circular(100),
                    ),
                    border: Border.all(
                      color: const Color(0xFF707070).withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    '${soldPercentage.toStringAsFixed(0)}% Sold',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSalesHighlights() {
    return Container(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sales Highlights',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Summary of sales performance and pricing.',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: Colors.black.withOpacity(0.8),
          ),
        ),
      ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildSalesCard(
                'Total Sales Value',
                _formatCurrency(_dashboardData!['totalSalesValue'] as double),
                '${_dashboardData!['soldPlots']} plots sold',
              ),
              const SizedBox(width: 24),
              _buildSalesCard(
                'Avg Sale Price / sqft',
                _formatCurrency(_dashboardData!['avgSalePricePerSqft'] as double),
                'Based on sold plots',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSalesByLayout() {
    final salesByLayout = _dashboardData!['salesByLayout'] as List<Map<String, dynamic>>;
    
    return Container(
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
            'Sales by Layout',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          // Layout cards in rows of 2
          LayoutBuilder(
            builder: (context, constraints) {
              // Calculate card width: (available width - gap) / 2
              final cardWidth = (constraints.maxWidth - 16) / 2;
              
              return Column(
                children: List.generate(
                  (salesByLayout.length / 2).ceil(),
                  (rowIndex) {
                    final startIndex = rowIndex * 2;
                    final endIndex = math.min(startIndex + 2, salesByLayout.length);
                    final rowLayouts = salesByLayout.sublist(startIndex, endIndex);
                    
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: rowIndex < (salesByLayout.length / 2).ceil() - 1 ? 16 : 0,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: cardWidth,
                            child: _buildLayoutCard(rowLayouts[0]),
                          ),
                          if (rowLayouts.length > 1) ...[
                            const SizedBox(width: 16),
                            SizedBox(
                              width: cardWidth,
                              child: _buildLayoutCard(rowLayouts[1]),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutCard(Map<String, dynamic> layout) {
    final index = (_dashboardData!['salesByLayout'] as List).indexOf(layout) + 1;
    final salePercentage = layout['salePercentage'] as double;
    
    return Container(
      padding: const EdgeInsets.all(16),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Layout name row
                Row(
                  children: [
                    Text(
                      '$index.',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF5C5C5C),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Layout: ${layout['name']}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF5C5C5C),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Currency value
                Flexible(
                  child: Text(
                    _formatCurrency(layout['salesValue'] as double),
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 16),
                // Plots sold
                Text(
                  '${layout['soldPlots']}/${layout['totalPlots']} plots sold',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5C5C5C),
                  ),
                ),
              ],
            ),
          ),
          // Right column - Percentage and "sold" label
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${salePercentage.toStringAsFixed(0)}%',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'sold',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value) {
    return Container(
      height: 101,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5C5C5C),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.normal,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCardWithUnit(String label, String value, String unit) {
    return Container(
      height: 101,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5C5C5C),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                unit,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallMetricCard(String label, String value, {Color? valueColor}) {
    return Container(
      height: 101,
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5C5C5C),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.normal,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesCard(String label, String value, String subtitle) {
    return Container(
      width: 300,
      height: 141,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5C5C5C),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.normal,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5C5C5C),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int value) {
    if (value < 1000) return value.toString();
    
    final parts = value.toString().split('');
    String formatted = '';
    final length = parts.length;
    
    if (length <= 3) {
      formatted = value.toString();
    } else {
      final lastThree = parts.sublist(length - 3).join();
      final remaining = parts.sublist(0, length - 3).join();
      
      // Add commas every 2 digits from right
      String formattedRemaining = '';
      for (int i = remaining.length - 1; i >= 0; i--) {
        if ((remaining.length - 1 - i) > 0 && (remaining.length - 1 - i) % 2 == 0) {
          formattedRemaining = ',' + formattedRemaining;
        }
        formattedRemaining = remaining[i] + formattedRemaining;
      }
      
      formatted = formattedRemaining.isEmpty ? lastThree : '$formattedRemaining,$lastThree';
    }
    
    return formatted;
  }

  Widget _buildSiteTabContent() {
    // Show loading indicator until site data is loaded
    if (_dashboardData == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_isSiteDataLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final totalExpenses = _dashboardData!['totalExpenses'] as double;
    final sellingArea = _dashboardData!['sellingArea'] as double;
    final allInCost = _dashboardData!['allInCost'] as double;
    final totalSalesValue = _dashboardData!['totalSalesValue'] as double;
    
    // Calculate Total Plot Cost = sum of (area * all-in cost) for all plots
    double totalPlotCost = 0.0;
    // Calculate Gross Profit = sum of gross profit of all layouts
    double grossProfit = 0.0;
    
    for (var layout in _siteLayouts) {
      final plots = layout['plots'] as List<dynamic>;
      double layoutGrossProfit = 0.0;
      
      for (var plot in plots) {
        final area = ((plot['area'] as num?)?.toDouble() ?? 0.0);
        totalPlotCost += area * allInCost;
        
        // Calculate profit for sold plots
        final status = (plot['status'] as String? ?? 'available').toLowerCase();
        if (status == 'sold') {
          final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
          final saleValue = salePrice * area;
          final plotCost = area * allInCost;
          final plotProfit = saleValue - plotCost;
          layoutGrossProfit += plotProfit;
        }
      }
      
      grossProfit += layoutGrossProfit;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Site Financial Summary
        _buildSiteFinancialSummary(
          totalPlotCost: totalPlotCost,
          totalSalesValue: totalSalesValue,
          projectManagersCompensation: _calculateTotalProjectManagersCompensation(),
          agentsCompensation: _calculateTotalAgentsCompensation(),
          grossProfit: grossProfit,
        ),
        const SizedBox(height: 24),
        
        // Site Overview (reuse existing method)
        _buildSiteOverview(),
        const SizedBox(height: 24),
        
        // Layout Wise Financial Summary
        _buildLayoutWiseFinancialSummary(),
      ],
    );
  }

  Widget _buildSiteFinancialSummary({
    required double totalPlotCost,
    required double totalSalesValue,
    required double projectManagersCompensation,
    required double agentsCompensation,
    required double grossProfit,
  }) {
    return Container(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Site Financial Summary',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Track project costs, sales, and final profit in one place.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // First row
          Row(
            children: [
              _buildProfitCard(
                'Total Plot Cost',
                _formatCurrency(totalPlotCost),
              ),
              const SizedBox(width: 24),
              _buildProfitCard(
                'Total Sales Value',
                _formatCurrency(totalSalesValue),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Second row
          Row(
            children: [
              _buildProfitCard(
                'Project Managers Compensation',
                _formatCurrency(projectManagersCompensation),
              ),
              const SizedBox(width: 24),
              _buildProfitCard(
                'Agents Compensation',
                _formatCurrency(agentsCompensation),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Third row
          Row(
            children: [
              _buildProfitCard(
                'Gross Profit',
                _formatCurrency(grossProfit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutWiseFinancialSummary() {
    return Container(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Layout Wise Financial Summary',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Track project costs, sales, and final profit in one place.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_siteLayouts.length} Layouts',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Layout cards
          ..._siteLayouts.asMap().entries.map((entry) {
            final index = entry.key;
            final layout = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: index < _siteLayouts.length - 1 ? 24 : 0),
              child: _buildLayoutFinancialCard(layout, index),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLayoutFinancialCard(Map<String, dynamic> layout, int layoutIndex) {
    final layoutName = layout['name'] as String? ?? 'Layout ${layoutIndex + 1}';
    final plots = layout['plots'] as List<dynamic>? ?? [];
    
    final allInCost = _dashboardData!['allInCost'] as double;
    final projectManagersCompensation = _projectManagersCompensation;
    final agentsCompensation = _agentsCompensation;
    
    // Calculate layout totals
    double totalArea = 0.0;
    double totalPlotCost = 0.0;
    double totalSalePrice = 0.0;
    double totalSaleValue = 0.0;
    double areaSold = 0.0;
    double grossProfit = 0.0; // Sum of profit column values
    int availablePlots = 0;
    int soldPlots = 0;
    
    for (var plot in plots) {
      final area = ((plot['area'] as num?)?.toDouble() ?? 0.0);
      final status = (plot['status'] as String? ?? 'available').toLowerCase();
      final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
      
      totalArea += area;
      totalPlotCost += area * allInCost;
      
      if (status == 'sold') {
        soldPlots++;
        totalSalePrice += salePrice;
        final saleValue = salePrice * area;
        totalSaleValue += saleValue;
        areaSold += area;
        // Calculate profit for this plot: (saleValue - plotCost)
        final plotCost = area * allInCost;
        final plotProfit = saleValue - plotCost;
        grossProfit += plotProfit;
      } else {
        availablePlots++;
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Layout header
          Row(
            children: [
              Text(
                '${layoutIndex + 1}.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Layout: $layoutName',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Plot count and status
          Row(
            children: [
              Text(
                '${plots.length} plots',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFF06AB00),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$availablePlots Available',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF5C5C5C),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$soldPlots Sold',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF5C5C5C),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Financial summary
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Area: ${_formatArea(totalArea)} sqft',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Total All-in Cost: ${_formatCurrency(allInCost * plots.length)}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Total Plot Cost: ${_formatCurrency(totalPlotCost)}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Sale Price: ₹/sqft ${_formatCurrency(totalSalePrice)}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Total Sale Value: ${_formatCurrency(totalSaleValue)}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Area Sold: ${_formatArea(areaSold)} sqft',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gross Profit: ${_formatCurrency(grossProfit)}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Plot table (simplified - showing key columns)
          _buildLayoutPlotsTable(plots, allInCost),
        ],
      ),
    );
  }

  Widget _buildPartnersSection() {
    // Show loading indicator until all required data is loaded
    if (_dashboardData == null || 
        _isPartnersLoading || 
        _isProjectManagersLoading || 
        _isAgentsLoading ||
        _dashboardData!['netProfit'] == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Calculate total gross profit (sum of all layouts' gross profits)
    final totalGrossProfit = _calculateTotalGrossProfit();

    // Calculate total capital contribution
    final totalCapitalContribution = _partners.fold<double>(
      0.0,
      (sum, partner) => sum + (partner['amount'] as double? ?? 0.0),
    );

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          // Net Profit card (from overview section)
          Container(
            width: 320,
            padding: const EdgeInsets.all(16),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Net Profit',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5C5C5C),
                  ),
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    // Calculate net profit the same way as overview section for consistency
                    final totalSalesValue = _dashboardData?['totalSalesValue'] as double? ?? 0.0;
                    final totalExpenses = _dashboardData?['totalExpenses'] as double? ?? 0.0;
                    final grossProfit = totalSalesValue - totalExpenses;
                    final totalCompensation = _calculateTotalProjectManagersCompensation() + _calculateTotalAgentsCompensation();
                    final netProfit = grossProfit - totalCompensation;
                    return Text(
                      _formatCurrency(netProfit),
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Partners table
          _buildPartnersTable(totalCapitalContribution, totalGrossProfit),
        ],
      ),
    );
  }

  Widget _buildPartnersTable(double totalCapitalContribution, double totalGrossProfit) {
    // Get estimated development cost for share calculation (matching project details page)
    final estimatedDevelopmentCost = _dashboardData!['estimatedDevelopmentCost'] as double? ?? 0.0;
    
    // Use the net profit from _dashboardData (calculated in overview section)
    // This ensures consistency between overview and partners sections
    final totalSalesValue = _dashboardData!['totalSalesValue'] as double? ?? 0.0;
    final totalExpenses = _dashboardData!['totalExpenses'] as double? ?? 0.0;
    final grossProfit = totalSalesValue - totalExpenses;
    final totalCompensation = _calculateTotalProjectManagersCompensation() + _calculateTotalAgentsCompensation();
    final totalNetProfit = grossProfit - totalCompensation;
    
    // Pre-calculate profit shares for all partners to ensure consistency
    // Use estimated development cost as denominator (matching project details page)
    final partnersWithProfitShare = _partners.map((partner) {
      final capitalContribution = partner['amount'] as double? ?? 0.0;
      final profitShare = estimatedDevelopmentCost > 0 
          ? (capitalContribution / estimatedDevelopmentCost) * 100 
          : 0.0;
      return {
        ...partner,
        'profitShare': profitShare,
        'allocatedProfit': (totalNetProfit * profitShare) / 100,
      };
    }).toList();
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        controller: _partnersTableScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _partnersTableScrollController,
          scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Sl. No. column
            Column(
              children: [
                _buildPartnersTableHeaderCell('Sl. No.', isFirst: true, isLast: false),
                ...partnersWithProfitShare.asMap().entries.map((entry) {
                  final index = entry.key;
                  final isLastRow = index == partnersWithProfitShare.length - 1;
                  return _buildPartnersTableDataCell(
                    '${index + 1}',
                    columnName: 'Sl. No.',
                    isFirst: true,
                    isLastRow: isLastRow,
                    isLast: false,
                  );
                }),
              ],
            ),
            // Partner Name column
            Column(
              children: [
                _buildPartnersTableHeaderCell('Partner Name', isFirst: false, isLast: false),
                ...partnersWithProfitShare.asMap().entries.map((entry) {
                  final index = entry.key;
                  final partner = entry.value;
                  final isLastRow = index == partnersWithProfitShare.length - 1;
                  return _buildPartnersTableDataCell(
                    partner['name'] as String? ?? '',
                    columnName: 'Partner Name',
                    isFirst: false,
                    isLastRow: isLastRow,
                    isLast: false,
                    isPartnerName: true,
                  );
                }),
              ],
            ),
            // Capital Contribution (₹) column
            Column(
              children: [
                _buildPartnersTableHeaderCell('Capital Contribution (₹)', isFirst: false, isLast: false),
                ...partnersWithProfitShare.asMap().entries.map((entry) {
                  final index = entry.key;
                  final partner = entry.value;
                  final amount = partner['amount'] as double? ?? 0.0;
                  final isLastRow = index == partnersWithProfitShare.length - 1;
                  return _buildPartnersTableDataCell(
                    _formatCurrencyNumber(amount),
                    columnName: 'Capital Contribution (₹)',
                    isFirst: false,
                    isLastRow: isLastRow,
                    isLast: false,
                    prefix: '₹ ',
                  );
                }),
              ],
            ),
            // Profit Share (%) column
            Column(
              children: [
                _buildPartnersTableHeaderCell('Profit Share (%)', isFirst: false, isLast: false, flexible: false),
                ...partnersWithProfitShare.asMap().entries.map((entry) {
                  final index = entry.key;
                  final partner = entry.value;
                  final profitShare = partner['profitShare'] as double? ?? 0.0;
                  final isLastRow = index == partnersWithProfitShare.length - 1;
                  return _buildPartnersTableDataCell(
                    '${profitShare.toStringAsFixed(0)} %',
                    columnName: 'Profit Share (%)',
                    isFirst: false,
                    isLastRow: isLastRow,
                    isLast: false,
                    flexible: false,
                    textColor: const Color(0xFF5D5D5D),
                  );
                }),
              ],
            ),
            // Allocated Profit (₹) column
            Column(
              children: [
                _buildPartnersTableHeaderCell('Allocated Profit (₹)', isFirst: false, isLast: true),
                ...partnersWithProfitShare.asMap().entries.map((entry) {
                  final index = entry.key;
                  final partner = entry.value;
                  final allocatedProfit = partner['allocatedProfit'] as double? ?? 0.0;
                  final isLastRow = index == partnersWithProfitShare.length - 1;
                  return _buildPartnersTableDataCell(
                    _formatCurrencyNumber(allocatedProfit),
                    columnName: 'Allocated Profit (₹)',
                    isFirst: false,
                    isLastRow: isLastRow,
                    isLast: true,
                    prefix: '₹ ',
                  );
                }),
              ],
            ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildPartnersTableHeaderCell(String text, {bool isFirst = false, bool isLast = false, bool flexible = false}) {
    final width = _getPartnersColumnWidth(text);
    return Container(
      height: 48,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF707070).withOpacity(0.08),
        border: Border(
          top: const BorderSide(color: Colors.black, width: 1),
          bottom: const BorderSide(color: Colors.black, width: 1),
          left: isFirst ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          right: const BorderSide(color: Colors.black, width: 1),
        ),
        borderRadius: isFirst
            ? const BorderRadius.only(topLeft: Radius.circular(8))
            : isLast
                ? const BorderRadius.only(topRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildPartnersTableDataCell(
    String text, {
    required String columnName,
    bool isFirst = false,
    bool isLastRow = false,
    bool isLast = false,
    bool isPartnerName = false,
    bool flexible = false,
    String? prefix,
    Color? textColor,
  }) {
    final width = _getPartnersColumnWidth(columnName);
    return Container(
      height: 48,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: const BorderSide(color: Colors.black, width: 1),
          left: isFirst ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          right: const BorderSide(color: Colors.black, width: 1),
        ),
        borderRadius: isFirst && isLastRow
            ? const BorderRadius.only(bottomLeft: Radius.circular(8))
            : isLast && isLastRow
                ? const BorderRadius.only(bottomRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: isPartnerName
            ? Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    text,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            : Text(
                prefix != null ? '$prefix$text' : text,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: textColor ?? Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }

  double _getPartnersColumnWidth(String columnName) {
    switch (columnName) {
      case 'Sl. No.':
        return 60;
      case 'Partner Name':
        return 320;
      case 'Capital Contribution (₹)':
        return 215;
      case 'Profit Share (%)':
        return 200; // Fixed width to ensure visibility and alignment
      case 'Allocated Profit (₹)':
        return 215;
      default:
        // For data cells, try to infer from text content
        if (columnName.length < 10) return 60;
        if (columnName.length < 20) return 200;
        return 320;
    }
  }

  // Helper function to calculate total gross profit (sum of all layouts' gross profits)
  double _calculateTotalGrossProfit() {
    if (_dashboardData == null || _siteLayouts.isEmpty) {
      return 0.0;
    }
    
    final allInCost = _dashboardData!['allInCost'] as double;
    double totalGrossProfit = 0.0;
    
    for (var layout in _siteLayouts) {
      final plots = layout['plots'] as List<dynamic>? ?? [];
      double layoutGrossProfit = 0.0;
      
      for (var plot in plots) {
        final status = (plot['status'] as String? ?? 'available').toLowerCase();
        if (status == 'sold') {
          final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
          final area = ((plot['area'] as num?)?.toDouble() ?? 0.0);
          final saleValue = salePrice * area;
          final plotCost = area * allInCost;
          final plotProfit = saleValue - plotCost;
          layoutGrossProfit += plotProfit;
        }
      }
      
      totalGrossProfit += layoutGrossProfit;
    }
    
    return totalGrossProfit;
  }

  double _calculateProjectManagerEarnings(Map<String, dynamic> manager) {
    final compensationType = manager['compensation_type'] as String? ?? '';
    final earningType = manager['earning_type'] as String? ?? '';
    
    if (compensationType == 'Fixed Fee') {
      return manager['fixed_fee'] as double? ?? 0.0;
    } else if (compensationType == 'Monthly Fee') {
      final monthlyFee = manager['monthly_fee'] as double? ?? 0.0;
      final months = manager['months'] as int? ?? 0;
      return monthlyFee * months;
    } else if (compensationType == 'Percentage Bonus') {
      final percentage = manager['percentage'] as double? ?? 0.0;
      
      // Check earning type to determine calculation method
      final isLumpSum = earningType == 'Lump Sum' || 
                        earningType == '% of Total Project Profit' ||
                        (earningType.toLowerCase().contains('total project profit') || earningType.toLowerCase().contains('lump'));
      
      if (isLumpSum) {
        // Calculate as percentage of total gross profit
        final totalGrossProfit = _calculateTotalGrossProfit();
        return (totalGrossProfit * percentage) / 100;
      } else {
        // For per-plot earnings (Profit Per Plot or Selling Price Per Plot), 
        // calculate from individual plots assigned to this manager
        double totalEarnings = 0.0;
        final managerName = manager['name'] as String? ?? '';
        final managerId = manager['id'] as String?;
        
        if (_siteLayouts.isNotEmpty && managerName.isNotEmpty) {
          // Get plots assigned to this manager from project_manager_blocks
          final allInCost = _dashboardData!['allInCost'] as double? ?? 0.0;
          
          for (var layout in _siteLayouts) {
            final plots = layout['plots'] as List<dynamic>? ?? [];
            for (var plot in plots) {
              final status = (plot['status'] as String? ?? '').toLowerCase();
              if (status == 'sold') {
                // Check if this plot is assigned to this manager via project_manager_blocks
                // Note: We'll need to load manager-block associations, but for now,
                // we'll calculate based on all sold plots if manager has percentage bonus
                // This is a simplified approach - you may need to load block associations
                
                // Calculate per-plot compensation
                final salePrice = (plot['sale_price'] as num?)?.toDouble() ?? 0.0;
                final area = (plot['area'] as num?)?.toDouble() ?? 0.0;
                final saleValue = salePrice * area;
                
                // Check for "Selling Price Per Plot"
                final isSellingPriceBased = earningType == 'Selling Price Per Plot' || 
                                            earningType == '% of Selling Price per Plot' ||
                                            (earningType.toLowerCase().contains('selling price') && earningType.toLowerCase().contains('plot'));
                
                if (isSellingPriceBased) {
                  totalEarnings += (saleValue * percentage) / 100;
                } else {
                  // Profit Per Plot
                  final plotCost = area * allInCost;
                  final plotProfit = saleValue - plotCost;
                  totalEarnings += (plotProfit * percentage) / 100;
                }
              }
            }
          }
        }
        
        return totalEarnings;
      }
    }
    
    return 0.0;
  }

  Widget _buildProjectManagersSection() {
    if (_dashboardData == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Calculate earnings for each project manager
    final managersWithEarnings = _projectManagers.map((manager) {
      final earnings = _calculateProjectManagerEarnings(manager);
      return {
        ...manager,
        'earnings': earnings,
      };
    }).toList();

    // Calculate total earnings
    final totalEarnings = managersWithEarnings.fold<double>(
      0.0,
      (sum, manager) => sum + (manager['earnings'] as double? ?? 0.0),
    );

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Project Manager(s) Earnings',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          
          // Total Earnings card
          Container(
            width: 320,
            padding: const EdgeInsets.all(16),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total Earnings',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5C5C5C),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatCurrency(totalEarnings),
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Project Managers table
          _buildProjectManagersTable(managersWithEarnings),
        ],
      ),
    );
  }

  Widget _buildProjectManagersTable(List<Map<String, dynamic>> managers) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        controller: _projectManagersTableScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _projectManagersTableScrollController,
          scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sl. No. column
              Column(
                children: [
                  _buildProjectManagersTableHeaderCell('Sl. No.', isFirst: true, isLast: false),
                  ...managers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final isLastRow = index == managers.length - 1;
                    return _buildProjectManagersTableDataCell(
                      '${index + 1}',
                      columnName: 'Sl. No.',
                      isFirst: true,
                      isLastRow: isLastRow,
                      isLast: false,
                    );
                  }),
                ],
              ),
              // Project Manager Name column
              Column(
                children: [
                  _buildProjectManagersTableHeaderCell('Project Manager Name', isFirst: false, isLast: false),
                  ...managers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final manager = entry.value;
                    final isLastRow = index == managers.length - 1;
                    return _buildProjectManagersTableDataCell(
                      manager['name'] as String? ?? '',
                      columnName: 'Project Manager Name',
                      isFirst: false,
                      isLastRow: isLastRow,
                      isLast: false,
                      isManagerName: true,
                    );
                  }),
                ],
              ),
              // Compensation column
              Column(
                children: [
                  _buildProjectManagersTableHeaderCell('Compensation ', isFirst: false, isLast: false),
                  ...managers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final manager = entry.value;
                    final compensationType = manager['compensation_type'] as String? ?? '';
                    final isLastRow = index == managers.length - 1;
                    return _buildProjectManagersTableDataCell(
                      compensationType.isEmpty ? 'None' : compensationType,
                      columnName: 'Compensation ',
                      isFirst: false,
                      isLastRow: isLastRow,
                      isLast: false,
                      isCompensation: true,
                      compensationType: compensationType,
                    );
                  }),
                ],
              ),
              // Earning Type column
              Column(
                children: [
                  _buildProjectManagersTableHeaderCell('Earning Type ', isFirst: false, isLast: false),
                  ...managers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final manager = entry.value;
                    final compensationType = manager['compensation_type'] as String? ?? '';
                    final earningType = manager['earning_type'] as String? ?? '';
                    final percentage = manager['percentage'] as double?;
                    final fixedFee = manager['fixed_fee'] as double?;
                    final monthlyFee = manager['monthly_fee'] as double?;
                    final months = manager['months'] as int?;
                    final isLastRow = index == managers.length - 1;
                    return _buildProjectManagersEarningTypeCell(
                      manager: manager,
                      compensationType: compensationType,
                      earningType: earningType,
                      percentage: percentage,
                      fixedFee: fixedFee,
                      monthlyFee: monthlyFee,
                      months: months,
                      isLastRow: isLastRow,
                    );
                  }),
                ],
              ),
              // Earnings (₹) column
              Column(
                children: [
                  _buildProjectManagersTableHeaderCell('Earnings (₹)', isFirst: false, isLast: true),
                  ...managers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final manager = entry.value;
                    final earnings = manager['earnings'] as double? ?? 0.0;
                    final isLastRow = index == managers.length - 1;
                    return _buildProjectManagersTableDataCell(
                      _formatCurrencyNumber(earnings),
                      columnName: 'Earnings (₹)',
                      isFirst: false,
                      isLastRow: isLastRow,
                      isLast: true,
                      prefix: '₹ ',
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildProjectManagersTableHeaderCell(String text, {bool isFirst = false, bool isLast = false}) {
    final width = _getProjectManagersColumnWidth(text);
    return Container(
      height: 48,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF707070).withOpacity(0.08),
        border: Border(
          top: const BorderSide(color: Colors.black, width: 1),
          bottom: const BorderSide(color: Colors.black, width: 1),
          left: isFirst ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          right: const BorderSide(color: Colors.black, width: 1),
        ),
        borderRadius: isFirst
            ? const BorderRadius.only(topLeft: Radius.circular(8))
            : isLast
                ? const BorderRadius.only(topRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: text.replaceAll(' *', ''),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              if (text.contains('*'))
                TextSpan(
                  text: ' *',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectManagersTableDataCell(
    String text, {
    required String columnName,
    bool isFirst = false,
    bool isLastRow = false,
    bool isLast = false,
    bool isManagerName = false,
    bool isCompensation = false,
    String? compensationType,
    String? prefix,
  }) {
    final width = _getProjectManagersColumnWidth(columnName);
    return Container(
      height: 48,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: const BorderSide(color: Colors.black, width: 1),
          left: isFirst ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          right: const BorderSide(color: Colors.black, width: 1),
        ),
        borderRadius: isFirst && isLastRow
            ? const BorderRadius.only(bottomLeft: Radius.circular(8))
            : isLast && isLastRow
                ? const BorderRadius.only(bottomRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: isManagerName
            ? Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    text,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            : isCompensation
                ? Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECF6FD),
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
                    child: Center(
                      child: Text(
                        text,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Text(
                    prefix != null ? '$prefix$text' : text,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
      ),
    );
  }

  Widget _buildProjectManagersEarningTypeCell({
    required Map<String, dynamic> manager,
    required String compensationType,
    required String earningType,
    double? percentage,
    double? fixedFee,
    double? monthlyFee,
    int? months,
    required bool isLastRow,
  }) {
    final width = _getProjectManagersColumnWidth('Earning Type ');
    return Container(
      height: 48,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: const BorderSide(color: Colors.black, width: 1),
          right: const BorderSide(color: Colors.black, width: 1),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildEarningTypeContent(
          compensationType: compensationType,
          earningType: earningType,
          percentage: percentage,
          fixedFee: fixedFee,
          monthlyFee: monthlyFee,
          months: months,
        ),
      ),
    );
  }

  Widget _buildEarningTypeContent({
    required String compensationType,
    required String earningType,
    double? percentage,
    double? fixedFee,
    double? monthlyFee,
    int? months,
  }) {
    if (compensationType == 'Percentage Bonus') {
      // Map database earning type to UI display (same mapping as project_details_page)
      String displayEarningType = earningType;
      final lowerEarningType = earningType.toLowerCase();
      
      if (lowerEarningType == 'profit per plot') {
        displayEarningType = '% of Profit on Each Sold Plot';
      } else if (lowerEarningType == 'selling price per plot' || lowerEarningType == '% of selling price per plot') {
        displayEarningType = '% of Selling Price per Plot';
      } else if (lowerEarningType == 'lump sum' || lowerEarningType == '% of total project profit') {
        displayEarningType = '% of Total Project Profit';
      } else if (lowerEarningType == 'per plot') {
        displayEarningType = '% of Profit on Each Sold Plot';
      }
      
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                percentage != null ? '${percentage.toStringAsFixed(0)}' : '0',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFECF6FD),
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
            constraints: const BoxConstraints(maxWidth: 350),
            child: Text(
              displayEarningType,
              textAlign: TextAlign.left,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Colors.black,
              ),
            ),
          ),
        ],
      );
    } else if (compensationType == 'Fixed Fee') {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            fixedFee != null ? _formatCurrencyNumber(fixedFee) : '₹ 0.00',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5D5D5D),
            ),
          ),
        ),
      );
    } else if (compensationType == 'Monthly Fee') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                monthlyFee != null ? _formatCurrencyNumber(monthlyFee) : '₹ 0.00',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5D5D5D),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '*',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5C5C5C),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                months != null ? '$months' : '0',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Months',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5C5C5C),
            ),
          ),
        ],
      );
    } else {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            'NA',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5C5C5C),
            ),
          ),
        ),
      );
    }
  }

  double _getProjectManagersColumnWidth(String columnName) {
    switch (columnName) {
      case 'Sl. No.':
        return 60;
      case 'Project Manager Name':
        return 320;
      case 'Compensation ':
        return 176;
      case 'Earning Type ':
        return 340;
      case 'Earnings (₹)':
        return 215;
      default:
        return 200;
    }
  }

  Widget _buildLayoutPlotsTable(List<dynamic> plots, double allInCost) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        controller: _layoutPlotsTableScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _layoutPlotsTableScrollController,
          scrollDirection: Axis.horizontal,
          child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: Colors.black, width: 1),
            verticalInside: BorderSide(color: Colors.black, width: 1),
          ),
          columnWidths: const {
            0: FixedColumnWidth(60),   // Sl. No.
            1: FixedColumnWidth(186),  // Plot Number
            2: FixedColumnWidth(215),  // Area (sqft)
            3: FixedColumnWidth(180),  // Status
            4: FixedColumnWidth(215),  // All-in Cost
            5: FixedColumnWidth(215),  // Total Plot Cost
            6: FixedColumnWidth(215),  // Sale Price
            7: FixedColumnWidth(215),  // Sale Value
            8: FixedColumnWidth(248),  // Profit (₹/sqft)
            9: FixedColumnWidth(248),  // Profit (₹)
            10: FixedColumnWidth(241), // Partner(s)
            11: FixedColumnWidth(241), // Agent
            12: FixedColumnWidth(320), // Buyer Name
            13: FixedColumnWidth(167), // Sale date
          },
          children: [
            // Header row
            TableRow(
              decoration: const BoxDecoration(
                color: Color(0x70707070), // rgba(112,112,112,0.2)
              ),
              children: [
                _buildTableHeaderCell('Sl. No.', isFirst: true),
                _buildTableHeaderCell('Plot Number'),
                _buildTableHeaderCell('Area (sqft)'),
                _buildTableHeaderCell('Status'),
                _buildTableHeaderCell('All-in Cost (₹/sqft)'),
                _buildTableHeaderCell('Total Plot Cost (₹)'),
                _buildTableHeaderCell('Sale Price (₹/sqft)'),
                _buildTableHeaderCell('Sale Value (₹)'),
                _buildTableHeaderCell('Profit (₹/sqft)'),
                _buildTableHeaderCell('Profit (₹)'),
                _buildTableHeaderCell('Partner(s)'),
                _buildTableHeaderCell('Agent'),
                _buildTableHeaderCell('Buyer Name'),
                _buildTableHeaderCell('Sale date', isLast: true),
              ],
            ),
            // Data rows
            ...plots.asMap().entries.map((entry) {
              final index = entry.key;
              final plot = entry.value;
              final area = ((plot['area'] as num?)?.toDouble() ?? 0.0);
              final status = (plot['status'] as String? ?? 'available').toLowerCase();
              final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
              final plotNumber = (plot['plot_number'] as String? ?? '').toString();
              final totalPlotCost = area * allInCost;
              final saleValue = status == 'sold' ? salePrice * area : 0.0;
              final profitPerSqft = status == 'sold' && area > 0 ? (salePrice - allInCost) : 0.0;
              final profit = status == 'sold' ? (saleValue - totalPlotCost) : 0.0;
              final partners = (plot['partners'] as List<dynamic>? ?? []).map((p) => p.toString()).toList();
              final agent = (plot['agent_name'] as String? ?? '').toString();
              final buyerName = (plot['buyer_name'] as String? ?? '').toString();
              final saleDate = (plot['sale_date'] as String? ?? '').toString();
              final isLastRow = index == plots.length - 1;
              
              return TableRow(
                children: [
                  _buildTableDataCell('${index + 1}', isFirst: true, isLastRow: isLastRow),
                  _buildTableDataCell(plotNumber, isFirst: false, isLastRow: isLastRow),
                  _buildAreaCell(area, isLastRow),
                  _buildStatusCell(status == 'sold' ? 'Sold' : 'Available', status == 'sold', isLastRow),
                  _buildTableDataCell('₹/sqft ${_formatCurrencyNumber(allInCost)}', isFirst: false, isLastRow: isLastRow),
                  _buildTableDataCell('₹ ${_formatCurrencyNumber(totalPlotCost)}', isFirst: false, isLastRow: isLastRow),
                  _buildTableDataCell(status == 'sold' ? '₹/sqft ${_formatCurrencyNumber(salePrice)}' : '-', isFirst: false, isLastRow: isLastRow),
                  _buildTableDataCell(status == 'sold' ? '₹ ${_formatCurrencyNumber(saleValue)}' : '-', isFirst: false, isLastRow: isLastRow),
                  _buildTableDataCell(status == 'sold' ? '₹/sqft ${_formatCurrencyNumber(profitPerSqft)}' : '-', isFirst: false, isLastRow: isLastRow),
                  _buildTableDataCell(status == 'sold' ? '₹ ${_formatCurrencyNumber(profit)}' : '-', isFirst: false, isLastRow: isLastRow),
                  _buildPartnerCell(partners, isLastRow),
                  _buildAgentCell(agent, status == 'sold', isLastRow),
                  _buildBuyerNameCell(buyerName, status == 'sold', isLastRow),
                  _buildSaleDateCell(saleDate, status == 'sold', isLastRow, isLast: true),
                ],
              );
            }).toList(),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, {bool isFirst = false, bool isLast = false}) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF707070).withOpacity(0.08),
        borderRadius: isFirst
            ? const BorderRadius.only(topLeft: Radius.circular(8))
            : isLast
                ? const BorderRadius.only(topRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildTableDataCell(String text, {bool isFirst = false, bool isLastRow = false}) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: isFirst && isLastRow
            ? const BorderRadius.only(bottomLeft: Radius.circular(8))
            : null,
      ),
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: text == '-' ? const Color(0xFF5D5D5D) : Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCell(String text, bool isSold, bool isLastRow) {
    final statusColor = isSold ? const Color(0xFFFF0000) : const Color(0xFF50CD89);
    final statusBackgroundColor = isSold ? const Color(0xFFFFECEC) : const Color(0xFFE9F7EB);
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusBackgroundColor,
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
              Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  fontStyle: FontStyle.normal,
                  color: Colors.black,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartnerCell(List<String> partners, bool isLastRow) {
    final partnerText = partners.isEmpty ? '-' : partners.join(', ');
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              partnerText,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: partners.isEmpty ? const Color(0xFF5D5D5D) : Colors.black.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAgentCell(String agent, bool isSold, bool isLastRow) {
    if (!isSold) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Center(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '-',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5D5D5D),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: agent.isEmpty
                ? const Color(0xFFF8F9FA)
                : const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 2,
                offset: const Offset(0, 0),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              agent.isEmpty ? 'Select Agent' : agent,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: agent.isEmpty
                    ? const Color(0xFF5D5D5D)
                    : Colors.black,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBuyerNameCell(String buyerName, bool isSold, bool isLastRow) {
    if (!isSold) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Center(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '-',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5D5D5D),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              buyerName.isEmpty ? "Enter buyer's name" : buyerName,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: buyerName.isEmpty ? const Color(0xFF5D5D5D) : Colors.black,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAreaCell(double area, bool isLastRow) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'sqft ',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF5D5D5D),
                    ),
                  ),
                  TextSpan(
                    text: _formatArea(area),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaleDateCell(String saleDate, bool isSold, bool isLastRow, {bool isLast = false}) {
    if (!isSold) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: isLastRow && isLast
              ? const BorderRadius.only(bottomRight: Radius.circular(8))
              : null,
        ),
        child: Center(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '-',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5D5D5D),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: isLastRow && isLast
            ? const BorderRadius.only(bottomRight: Radius.circular(8))
            : null,
      ),
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: const Color(0xFF5D5D5D),
              ),
              const SizedBox(width: 8),
              Text(
                saleDate.isEmpty ? 'dd/mm/yyyy' : saleDate,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5D5D5D),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Calculate per-plot compensation for an agent
  double _calculateAgentPerPlotCompensation(Map<String, dynamic> agent, Map<String, dynamic> plot) {
    final compensationType = agent['compensation_type'] as String? ?? '';
    final earningType = agent['earning_type'] as String? ?? '';
    final status = (plot['status'] as String? ?? 'available').toLowerCase();
    
    // Only calculate compensation for sold plots
    if (status != 'sold') {
      return 0.0;
    }
    
    if (compensationType == 'Fixed Fee') {
      // Fixed fee is not per plot, return 0 for individual plot
      return 0.0;
    } else if (compensationType == 'Monthly Fee') {
      // Monthly fee is not per plot, return 0 for individual plot
      return 0.0;
    } else if (compensationType == 'Per Sqft Fee') {
      final perSqftFee = agent['per_sqft_fee'] as double? ?? 0.0;
      final area = (plot['area'] as num?)?.toDouble() ?? 0.0;
      return perSqftFee * area;
    } else if (compensationType == 'Percentage Bonus') {
      final percentage = agent['percentage'] as double? ?? 0.0;
      final salePrice = (plot['sale_price'] as num?)?.toDouble() ?? 0.0;
      final area = (plot['area'] as num?)?.toDouble() ?? 0.0;
      final saleValue = salePrice * area;
      
      // Check for "Selling Price Per Plot" - calculate percentage from sale value
      if (earningType == 'Selling Price Per Plot' || 
          earningType == '% of Selling Price per Plot' ||
          (earningType.toLowerCase().contains('selling price') && earningType.toLowerCase().contains('plot'))) {
        // Apply percentage to this plot's sale value
        return (saleValue * percentage) / 100;
      }
      // Check for "Profit Per Plot" - calculate percentage from profit
      else if (earningType == 'Profit Per Plot' || 
               earningType == 'Per Plot' || 
               earningType == '% of Profit on Each Sold Plot' ||
               (earningType.toLowerCase().contains('profit') && earningType.toLowerCase().contains('plot'))) {
        // Calculate profit for this specific plot
        final allInCost = _dashboardData!['allInCost'] as double;
        final plotCost = area * allInCost;
        final plotProfit = saleValue - plotCost;
        
        // Apply percentage to this plot's profit
        return (plotProfit * percentage) / 100;
      } else if (earningType == 'Lump Sum' || earningType == '% of Total Project Profit') {
        // This is not per plot, return 0 for individual plot
        return 0.0;
      }
    }
    
    return 0.0;
  }

  // Calculate total project managers compensation (sum of earnings)
  double _calculateTotalProjectManagersCompensation() {
    if (_projectManagers.isEmpty) {
      return 0.0;
    }
    
    return _projectManagers.fold<double>(
      0.0,
      (sum, manager) => sum + _calculateProjectManagerEarnings(manager),
    );
  }

  // Calculate total agents compensation (sum of earnings)
  double _calculateTotalAgentsCompensation() {
    if (_agents == null || _agents!.isEmpty) {
      return 0.0;
    }
    
    return _agents!.fold<double>(
      0.0,
      (sum, agent) => sum + _calculateAgentEarnings(agent),
    );
  }

  // Helper: check if an agent has at least one sold plot assigned in site layouts
  bool _agentHasSoldPlot(String agentName) {
    if (_siteLayouts.isEmpty || agentName.trim().isEmpty) {
      print('_agentHasSoldPlot: Empty layouts or agent name - returning false');
      return false;
    }

    print('_agentHasSoldPlot: Checking agent "$agentName" in ${_siteLayouts.length} layouts');
    
    for (var layout in _siteLayouts) {
      final plots = layout['plots'] as List<dynamic>? ?? [];
      print('  Layout "${layout['name']}": ${plots.length} plots');
      for (var plot in plots) {
        final status = (plot['status'] as String? ?? '').toLowerCase();
        // Check both 'agent' and 'agent_name' fields for backward compatibility
        final plotAgent = (plot['agent_name'] as String? ?? plot['agent'] as String? ?? '').trim();
        if (status == 'sold') {
          print('    Found sold plot with agent "$plotAgent" (looking for "$agentName")');
          if (plotAgent == agentName.trim()) {
            print('    -> MATCH! Agent has sold plot');
            return true;
          }
        }
      }
    }

    print('_agentHasSoldPlot: No sold plots found for agent "$agentName"');
    return false;
  }

  double _calculateAgentEarnings(Map<String, dynamic> agent) {
    final compensationType = agent['compensation_type'] as String? ?? '';
    final earningType = agent['earning_type'] as String? ?? '';
    final agentName = agent['name'] as String? ?? '';

    // Business rule: only show earnings for agents who have at least one sold plot.
    // If the agent has no sold plots, their earnings should be treated as zero.
    if (!_agentHasSoldPlot(agentName)) {
      return 0.0;
    }
    
    if (compensationType == 'Fixed Fee') {
      return agent['fixed_fee'] as double? ?? 0.0;
    } else if (compensationType == 'Monthly Fee') {
      final monthlyFee = agent['monthly_fee'] as double? ?? 0.0;
      final months = agent['months'] as int? ?? 0;
      return monthlyFee * months;
    } else if (compensationType == 'Per Sqft Fee') {
      final perSqftFee = agent['per_sqft_fee'] as double? ?? 0.0;
      // Calculate total area of sold plots for this agent
      double totalSoldArea = 0.0;
      
      if (_dashboardData != null && _siteLayouts.isNotEmpty) {
        for (var layout in _siteLayouts) {
          final plots = layout['plots'] as List<dynamic>? ?? [];
          for (var plot in plots) {
            final status = plot['status'] as String? ?? '';
            final agentName = plot['agent'] as String? ?? '';
            if (status == 'sold' && agentName == agent['name']) {
              final area = (plot['area'] as num?)?.toDouble() ?? 0.0;
              totalSoldArea += area;
            }
          }
        }
      }
      
      return perSqftFee * totalSoldArea;
    } else if (compensationType == 'Percentage Bonus') {
      final percentage = agent['percentage'] as double? ?? 0.0;
      final agentName = agent['name'] as String? ?? '';
      
      // Check earning type to determine calculation method
      final isSellingPriceBased = earningType == 'Selling Price Per Plot' || 
                                   earningType == '% of Selling Price per Plot' ||
                                   (earningType.toLowerCase().contains('selling price') && earningType.toLowerCase().contains('plot'));
      
      if (isSellingPriceBased) {
        // Calculate agent earnings as percentage of selling price on each of their sold plots
        double totalSaleValue = 0.0;
        
        if (_siteLayouts.isNotEmpty && agentName.isNotEmpty) {
          for (var layout in _siteLayouts) {
            final plots = layout['plots'] as List<dynamic>? ?? [];
            for (var plot in plots) {
              final status = (plot['status'] as String? ?? '').toLowerCase();
              final plotAgentName = (plot['agent_name'] as String? ?? plot['agent'] as String? ?? '').trim();
              
              if (status == 'sold' && plotAgentName == agentName.trim()) {
                final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
                final area = ((plot['area'] as num?)?.toDouble() ?? 0.0);
                final saleValue = salePrice * area;
                totalSaleValue += saleValue;
              }
            }
          }
        }
        
        return (totalSaleValue * percentage) / 100;
      } else {
        // Check if it's Lump Sum / Total Project Profit
        final isLumpSum = earningType == 'Lump Sum' || 
                          earningType == '% of Total Project Profit' ||
                          (earningType.toLowerCase().contains('total project profit') || earningType.toLowerCase().contains('lump'));
        
        if (isLumpSum) {
          // Calculate as percentage of total gross profit
          final totalGrossProfit = _calculateTotalGrossProfit();
          return (totalGrossProfit * percentage) / 100;
        } else {
          // Calculate agent earnings as percentage of profit on each of their sold plots
          double agentProfit = 0.0;
          final allInCost = _dashboardData!['allInCost'] as double? ?? 0.0;
          
          if (_siteLayouts.isNotEmpty && agentName.isNotEmpty) {
            for (var layout in _siteLayouts) {
              final plots = layout['plots'] as List<dynamic>? ?? [];
              for (var plot in plots) {
                final status = (plot['status'] as String? ?? '').toLowerCase();
                final plotAgentName = (plot['agent_name'] as String? ?? plot['agent'] as String? ?? '').trim();
                
                if (status == 'sold' && plotAgentName == agentName.trim()) {
                  final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
                  final area = ((plot['area'] as num?)?.toDouble() ?? 0.0);
                  final saleValue = salePrice * area;
                  final plotCost = area * allInCost;
                  final plotProfit = saleValue - plotCost;
                  agentProfit += plotProfit;
                }
              }
            }
          }
          
          return (agentProfit * percentage) / 100;
        }
      }
    }
    
    return 0.0;
  }

  Widget _buildAgentsSection() {
    if (_dashboardData == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Ensure _agents is initialized - check if it's null or not a list
    final agentsList = _agents ?? <Map<String, dynamic>>[];
    if (agentsList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agent(s) Earnings',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No agents found',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: const Color(0xFF5C5C5C),
              ),
            ),
          ],
        ),
      );
    }

    // Calculate earnings for each agent
    final agentsWithEarnings = agentsList.map((agent) {
      final earnings = _calculateAgentEarnings(agent);
      return {
        ...agent,
        'earnings': earnings,
      };
    }).toList();

    // Calculate total earnings
    final totalEarnings = agentsWithEarnings.fold<double>(
      0.0,
      (sum, agent) => sum + (agent['earnings'] as double? ?? 0.0),
    );

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Agent(s) Earnings',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          
          // Total Earnings card
          Container(
            width: 320,
            padding: const EdgeInsets.all(16),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total Earnings',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5C5C5C),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatCurrency(totalEarnings),
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Agents table
          _buildAgentsTable(agentsWithEarnings),
        ],
      ),
    );
  }

  Widget _buildAgentsTable(List<Map<String, dynamic>> agents) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        controller: _agentsTableScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _agentsTableScrollController,
          scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sl. No. column
              Column(
                children: [
                  _buildAgentsTableHeaderCell('Sl. No.', isFirst: true, isLast: false),
                  ...agents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final isLastRow = index == agents.length - 1;
                    return _buildAgentsTableDataCell(
                      '${index + 1}',
                      columnName: 'Sl. No.',
                      isFirst: true,
                      isLastRow: isLastRow,
                      isLast: false,
                    );
                  }),
                ],
              ),
              // Agent Name column
              Column(
                children: [
                  _buildAgentsTableHeaderCell('Agent Name', isFirst: false, isLast: false),
                  ...agents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final agent = entry.value;
                    final isLastRow = index == agents.length - 1;
                    return _buildAgentsTableDataCell(
                      agent['name'] as String? ?? '',
                      columnName: 'Agent Name',
                      isFirst: false,
                      isLastRow: isLastRow,
                      isLast: false,
                      isAgentName: true,
                    );
                  }),
                ],
              ),
              // Compensation column
              Column(
                children: [
                  _buildAgentsTableHeaderCell('Compensation ', isFirst: false, isLast: false),
                  ...agents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final agent = entry.value;
                    final compensationType = agent['compensation_type'] as String? ?? '';
                    final isLastRow = index == agents.length - 1;
                    return _buildAgentsTableDataCell(
                      compensationType.isEmpty ? 'None' : compensationType,
                      columnName: 'Compensation ',
                      isFirst: false,
                      isLastRow: isLastRow,
                      isLast: false,
                      isCompensation: true,
                      compensationType: compensationType,
                    );
                  }),
                ],
              ),
              // Earning Type column
              Column(
                children: [
                  _buildAgentsTableHeaderCell('Earning Type ', isFirst: false, isLast: false),
                  ...agents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final agent = entry.value;
                    final compensationType = agent['compensation_type'] as String? ?? '';
                    final earningType = agent['earning_type'] as String? ?? '';
                    final percentage = agent['percentage'] as double?;
                    final fixedFee = agent['fixed_fee'] as double?;
                    final monthlyFee = agent['monthly_fee'] as double?;
                    final months = agent['months'] as int?;
                    final perSqftFee = agent['per_sqft_fee'] as double?;
                    final hasSoldPlot = _agentHasSoldPlot(agent['name'] as String? ?? '');
                    final isLastRow = index == agents.length - 1;
                    
                    // Show earning type only if agent has sold plots
                    if (!hasSoldPlot) {
                      return _buildAgentsTableDataCell(
                        '-',
                        columnName: 'Earning Type ',
                        isFirst: false,
                        isLastRow: isLastRow,
                        isLast: false,
                      );
                    }
                    
                    return _buildAgentsEarningTypeCell(
                      agent: agent,
                      compensationType: compensationType,
                      earningType: earningType,
                      percentage: percentage,
                      fixedFee: fixedFee,
                      monthlyFee: monthlyFee,
                      months: months,
                      perSqftFee: perSqftFee,
                      isLastRow: isLastRow,
                    );
                  }),
                ],
              ),
              // Earnings (₹) column
              Column(
                children: [
                  _buildAgentsTableHeaderCell('Earnings (₹)', isFirst: false, isLast: true),
                  ...agents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final agent = entry.value;
                    final earnings = agent['earnings'] as double? ?? 0.0;
                    final hasSoldPlot = _agentHasSoldPlot(agent['name'] as String? ?? '');
                    final isLastRow = index == agents.length - 1;
                    // Show earnings only if agent has at least one sold plot; otherwise display '-'
                    final displayText = hasSoldPlot
                        ? _formatCurrencyNumber(earnings)
                        : '-';
                    return _buildAgentsTableDataCell(
                      displayText,
                      columnName: 'Earnings (₹)',
                      isFirst: false,
                      isLastRow: isLastRow,
                      isLast: true,
                      prefix: displayText == '-' ? null : '₹ ',
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildAgentsTableHeaderCell(String text, {bool isFirst = false, bool isLast = false}) {
    final width = _getAgentsColumnWidth(text);
    return Container(
      height: 48,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF707070).withOpacity(0.08),
        border: Border(
          top: const BorderSide(color: Colors.black, width: 1),
          bottom: const BorderSide(color: Colors.black, width: 1),
          left: isFirst ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          right: const BorderSide(color: Colors.black, width: 1),
        ),
        borderRadius: isFirst
            ? const BorderRadius.only(topLeft: Radius.circular(8))
            : isLast
                ? const BorderRadius.only(topRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: text.replaceAll(' *', ''),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              if (text.contains('*'))
                TextSpan(
                  text: ' *',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentsTableDataCell(
    String text, {
    required String columnName,
    bool isFirst = false,
    bool isLastRow = false,
    bool isLast = false,
    bool isAgentName = false,
    bool isCompensation = false,
    String? compensationType,
    String? prefix,
  }) {
    final width = _getAgentsColumnWidth(columnName);
    return Container(
      height: 48,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: const BorderSide(color: Colors.black, width: 1),
          left: isFirst ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          right: const BorderSide(color: Colors.black, width: 1),
        ),
        borderRadius: isFirst && isLastRow
            ? const BorderRadius.only(bottomLeft: Radius.circular(8))
            : isLast && isLastRow
                ? const BorderRadius.only(bottomRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: isAgentName
            ? Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    text,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            : isCompensation
                ? Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECF6FD),
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
                    child: Center(
                      child: Text(
                        text,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Text(
                    prefix != null ? '$prefix$text' : text,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
      ),
    );
  }

  Widget _buildAgentsEarningTypeCell({
    required Map<String, dynamic> agent,
    required String compensationType,
    required String earningType,
    double? percentage,
    double? fixedFee,
    double? monthlyFee,
    int? months,
    double? perSqftFee,
    required bool isLastRow,
  }) {
    final width = _getAgentsColumnWidth('Earning Type ');
    return Container(
      height: 48,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: const BorderSide(color: Colors.black, width: 1),
          right: const BorderSide(color: Colors.black, width: 1),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildAgentsEarningTypeContent(
          compensationType: compensationType,
          earningType: earningType,
          percentage: percentage,
          fixedFee: fixedFee,
          monthlyFee: monthlyFee,
          months: months,
          perSqftFee: perSqftFee,
        ),
      ),
    );
  }

  Widget _buildAgentsEarningTypeContent({
    required String compensationType,
    required String earningType,
    double? percentage,
    double? fixedFee,
    double? monthlyFee,
    int? months,
    double? perSqftFee,
  }) {
    if (compensationType == 'Percentage Bonus') {
      // Map database earning type to UI display (same mapping as project_details_page)
      String displayEarningType = earningType;
      final lowerEarningType = earningType.toLowerCase();
      
      if (lowerEarningType == 'profit per plot') {
        displayEarningType = '% of Profit on Each Sold Plot';
      } else if (lowerEarningType == 'selling price per plot' || lowerEarningType == '% of selling price per plot') {
        displayEarningType = '% of Selling Price per Plot';
      } else if (lowerEarningType == 'lump sum' || lowerEarningType == '% of total project profit') {
        displayEarningType = '% of Total Project Profit';
      } else if (lowerEarningType == 'per plot') {
        displayEarningType = '% of Profit on Each Sold Plot';
      }
      
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                percentage != null ? '${percentage.toStringAsFixed(0)}' : '0',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFECF6FD),
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
            child: Text(
              displayEarningType,
              textAlign: TextAlign.left,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Colors.black,
              ),
            ),
          ),
        ],
      );
    } else if (compensationType == 'Fixed Fee') {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            fixedFee != null ? _formatCurrencyNumber(fixedFee) : '₹ 0.00',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5D5D5D),
            ),
          ),
        ),
      );
    } else if (compensationType == 'Monthly Fee') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                monthlyFee != null ? _formatCurrencyNumber(monthlyFee) : '₹ 0.00',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5D5D5D),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '*',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5C5C5C),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                months != null ? '$months' : '0',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Months',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5C5C5C),
            ),
          ),
        ],
      );
    } else if (compensationType == 'Per Sqft Fee') {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            perSqftFee != null ? _formatCurrencyNumber(perSqftFee) : '₹ 0.00',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5D5D5D),
            ),
          ),
        ),
      );
    } else {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            'NA',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF5C5C5C),
            ),
          ),
        ),
      );
    }
  }

  double _getAgentsColumnWidth(String columnName) {
    switch (columnName) {
      case 'Sl. No.':
        return 60;
      case 'Agent Name':
        return 320;
      case 'Compensation ':
        return 176;
      case 'Earning Type ':
        return 337;
      case 'Earnings (₹)':
        return 215;
      default:
        return 200;
    }
  }

  Widget _buildCompensationSection() {
    if (_dashboardData == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Container(
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
          // Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Compensation Summary',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Track Project Managers and Agents compensation plot wise',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_compensationLayouts.length} Layouts',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Compensation cards row
          Row(
            children: [
              // Total Compensation card (first)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Compensation given',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF5C5C5C),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _formatCurrency(_calculateTotalProjectManagersCompensation() + _calculateTotalAgentsCompensation()),
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Project Managers Compensation card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Project Managers Compensation',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF5C5C5C),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _formatCurrency(_calculateTotalProjectManagersCompensation()),
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Agents Compensation card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agents Compensation',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF5C5C5C),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _formatCurrency(_calculateTotalAgentsCompensation()),
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Layout sections
          ..._compensationLayouts.asMap().entries.map((entry) {
            final index = entry.key;
            final layout = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: index < _compensationLayouts.length - 1 ? 24 : 0),
              child: _buildLayoutCompensationCard(layout, index),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLayoutCompensationCard(Map<String, dynamic> layout, int layoutIndex) {
    final layoutName = layout['name'] as String? ?? 'Layout ${layoutIndex + 1}';
    final plots = layout['plots'] as List<dynamic>? ?? [];
    final totalPlots = layout['totalPlots'] as int? ?? 0;
    final availablePlots = layout['availablePlots'] as int? ?? 0;
    final soldPlots = layout['soldPlots'] as int? ?? 0;
    final grossProfit = layout['grossProfit'] as double? ?? 0.0;
    final totalCompensation = layout['totalCompensation'] as double? ?? 0.0;

    return Container(
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
          // Layout header
          Row(
            children: [
              Text(
                '${layoutIndex + 1}.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Layout: $layoutName',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Plot count and status
          Row(
            children: [
              Text(
                '$totalPlots plots',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFF06AB00),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$availablePlots Available',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF5C5C5C),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$soldPlots Sold',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF5C5C5C),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Agents Compensation summary
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
              children: [
                const TextSpan(text: 'Agents Compensation:'),
                TextSpan(
                  text: ' ${_formatCurrency(totalCompensation)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Compensation table
          _buildCompensationTable(plots),
        ],
      ),
    );
  }

  Widget _buildCompensationTable(List<dynamic> plots) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        controller: _compensationTableScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _compensationTableScrollController,
          scrollDirection: Axis.horizontal,
          child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: Colors.black, width: 1),
            verticalInside: BorderSide(color: Colors.black, width: 1),
          ),
          columnWidths: const {
            0: FixedColumnWidth(60),   // Sl. No.
            1: FixedColumnWidth(186),  // Plot Number
            2: FixedColumnWidth(215),  // Area (sqft)
            3: FixedColumnWidth(180),  // Status
            4: FixedColumnWidth(174),  // Agent
            5: FixedColumnWidth(215),  // Compensation
          },
          children: [
            // Header row
            TableRow(
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.08),
              ),
              children: [
                _buildCompensationTableHeaderCell('Sl. No.', isFirst: true),
                _buildCompensationTableHeaderCell('Plot Number'),
                _buildCompensationTableHeaderCell('Area (sqft)'),
                _buildCompensationTableHeaderCell('Status'),
                _buildCompensationTableHeaderCell('Agent'),
                _buildCompensationTableHeaderCell('Compensation', isLast: true),
              ],
            ),
            // Data rows
            ...plots.asMap().entries.map((entry) {
              final index = entry.key;
              final plot = entry.value as Map<String, dynamic>;
              final plotNumber = plot['plot_number'] as String? ?? '-';
              final area = (plot['area'] as num?)?.toDouble() ?? 0.0;
              final status = (plot['status'] as String? ?? 'available').toLowerCase();
              final isSold = status == 'sold';
              final agentName = plot['agent_name'] as String? ?? '';
              
              // Calculate agent's compensation for THIS SPECIFIC PLOT
              double plotCompensation = 0.0;
              if (agentName.isNotEmpty && isSold && _agents != null) {
                final agent = _agents!.firstWhere(
                  (a) => (a['name'] as String? ?? '').toLowerCase() == agentName.toLowerCase(),
                  orElse: () => <String, dynamic>{},
                );
                if (agent.isNotEmpty) {
                  final compensationType = agent['compensation_type'] as String? ?? '';
                  
                  if (compensationType == 'Fixed Fee') {
                    plotCompensation = agent['fixed_fee'] as double? ?? 0.0;
                  } else if (compensationType == 'Monthly Fee') {
                    final monthlyFee = agent['monthly_fee'] as double? ?? 0.0;
                    final months = agent['months'] as int? ?? 0;
                    plotCompensation = monthlyFee * months;
                  } else if (compensationType == 'Per Sqft Fee') {
                    final perSqftFee = agent['per_sqft_fee'] as double? ?? 0.0;
                    plotCompensation = perSqftFee * area;
                  } else if (compensationType == 'Percentage Bonus') {
                    final percentage = agent['percentage'] as double? ?? 0.0;
                    final earningType = agent['earning_type'] as String? ?? '';
                    final salePrice = ((plot['sale_price'] as num?)?.toDouble() ?? 0.0);
                    final saleValue = salePrice * area;
                    
                    // Check for "Selling Price Per Plot" - calculate percentage from sale value
                    final isSellingPriceBased = earningType == 'Selling Price Per Plot' || 
                                                earningType == '% of Selling Price per Plot' ||
                                                (earningType.toLowerCase().contains('selling price') && earningType.toLowerCase().contains('plot'));
                    
                    // Check if it's Lump Sum / Total Project Profit
                    final isLumpSum = earningType == 'Lump Sum' || 
                                    earningType == '% of Total Project Profit' ||
                                    (earningType.toLowerCase().contains('total project profit') || earningType.toLowerCase().contains('lump'));
                    
                    if (isSellingPriceBased) {
                      // Apply percentage to this plot's sale value
                      plotCompensation = (saleValue * percentage) / 100;
                    } else if (isLumpSum) {
                      // For "% of Total Project Profit", calculate total agent compensation
                      // then distribute proportionally across agent's sold plots
                      final totalGrossProfit = _calculateTotalGrossProfit();
                      final totalAgentCompensation = (totalGrossProfit * percentage) / 100;
                      
                      // Calculate total sale value for all plots sold by this agent
                      double totalAgentSaleValue = 0.0;
                      if (_siteLayouts.isNotEmpty && agentName.isNotEmpty) {
                        for (var layout in _siteLayouts) {
                          final layoutPlots = layout['plots'] as List<dynamic>? ?? [];
                          for (var layoutPlot in layoutPlots) {
                            final plotStatus = (layoutPlot['status'] as String? ?? '').toLowerCase();
                            final plotAgentName = (layoutPlot['agent_name'] as String? ?? layoutPlot['agent'] as String? ?? '').trim();
                            
                            if (plotStatus == 'sold' && plotAgentName == agentName.trim()) {
                              final plotSalePrice = ((layoutPlot['sale_price'] as num?)?.toDouble() ?? 0.0);
                              final plotArea = ((layoutPlot['area'] as num?)?.toDouble() ?? 0.0);
                              totalAgentSaleValue += plotSalePrice * plotArea;
                            }
                          }
                        }
                      }
                      
                      // Distribute compensation proportionally based on this plot's sale value
                      if (totalAgentSaleValue > 0) {
                        plotCompensation = (totalAgentCompensation * saleValue) / totalAgentSaleValue;
                      } else {
                        plotCompensation = 0.0;
                      }
                    } else {
                      // Calculate profit for this specific plot
                      final allInCost = _dashboardData!['allInCost'] as double? ?? 0.0;
                      final plotCost = area * allInCost;
                      final plotProfit = saleValue - plotCost;
                      
                      // Apply percentage to this plot's profit
                      plotCompensation = (plotProfit * percentage) / 100;
                    }
                  }
                }
              }
              
              final isLastRow = index == plots.length - 1;
              
              return TableRow(
                children: [
                  _buildCompensationTableDataCell('${index + 1}', isFirst: true, isLastRow: isLastRow),
                  _buildCompensationTableDataCell(plotNumber, isFirst: false, isLastRow: isLastRow),
                  _buildCompensationAreaCell(area, isLastRow),
                  _buildCompensationStatusCell(isSold ? 'Sold' : 'Available', isSold, isLastRow),
                  _buildCompensationAgentCell(agentName, isSold, isLastRow),
                  _buildCompensationTableDataCell(
                    plotCompensation > 0 ? _formatCurrency(plotCompensation) : '-',
                    isFirst: false,
                    isLastRow: isLastRow,
                    isLast: true,
                  ),
                ],
              );
            }).toList(),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompensationTableHeaderCell(String text, {bool isFirst = false, bool isLast = false}) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF707070).withOpacity(0.08),
        border: Border(
          top: const BorderSide(color: Colors.black, width: 1),
          bottom: const BorderSide(color: Colors.black, width: 1),
          left: isFirst ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          right: isLast ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
        ),
        borderRadius: isFirst
            ? const BorderRadius.only(topLeft: Radius.circular(8))
            : isLast
                ? const BorderRadius.only(topRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCompensationTableDataCell(String text, {bool isFirst = false, bool isLastRow = false, bool isLast = false}) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          left: isFirst ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          right: isLast ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          bottom: isLastRow ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
        ),
        borderRadius: isFirst && isLastRow
            ? const BorderRadius.only(bottomLeft: Radius.circular(8))
            : isLast && isLastRow
                ? const BorderRadius.only(bottomRight: Radius.circular(8))
                : null,
      ),
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: text == '-' ? const Color(0xFF5D5D5D) : const Color(0xFF5D5D5D),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompensationAreaCell(double area, bool isLastRow) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide.none,
          right: BorderSide.none,
          bottom: isLastRow ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
        ),
      ),
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5D5D5D),
                ),
                children: [
                  const TextSpan(text: 'sqft '),
                  TextSpan(
                    text: area.toStringAsFixed(2),
                    style: GoogleFonts.inter(
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompensationStatusCell(String text, bool isSold, bool isLastRow) {
    final statusColor = isSold ? const Color(0xFFFF0000) : const Color(0xFF50CD89);
    final statusBackgroundColor = isSold ? const Color(0xFFFFECEC) : const Color(0xFFE9F7EB);
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide.none,
          right: BorderSide.none,
          bottom: isLastRow ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusBackgroundColor,
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
              Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  fontStyle: FontStyle.normal,
                  color: Colors.black,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompensationAgentCell(String agentName, bool isSold, bool isLastRow) {
    if (!isSold || agentName.isEmpty) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide.none,
            right: BorderSide.none,
            bottom: isLastRow ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
          ),
        ),
        child: Center(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '-',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: const Color(0xFF5D5D5D),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final isDirectSale = agentName.toLowerCase() == 'direct sale';
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide.none,
          right: BorderSide.none,
          bottom: isLastRow ? const BorderSide(color: Colors.black, width: 1) : BorderSide.none,
        ),
      ),
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 2,
                offset: const Offset(0, 0),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              agentName,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: isDirectSale ? const Color(0xFF0C8CE9) : Colors.black,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

}
