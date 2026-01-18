import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/layout_storage_service.dart';
import '../services/project_storage_service.dart';

// TextInputFormatter for Indian numbering system (commas every 2 digits)
class IndianNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Remove all non-digit characters except decimal point
    String cleaned = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');
    
    // Only allow one decimal point
    final parts = cleaned.split('.');
    if (parts.length > 2) {
      cleaned = '${parts[0]}.${parts.sublist(1).join()}';
    }
    
    // Limit decimal places to 2
    if (parts.length == 2 && parts[1].length > 2) {
      cleaned = '${parts[0]}.${parts[1].substring(0, 2)}';
    }

    // Split into integer and decimal parts
    String integerPart;
    String decimalPart = '';
    
    if (cleaned.contains('.')) {
      final splitParts = cleaned.split('.');
      integerPart = splitParts[0];
      decimalPart = splitParts.length > 1 ? splitParts[1] : '';
    } else {
      integerPart = cleaned;
    }

    // Format integer part with Indian numbering
    // Numbers < 10000: no commas (e.g., 1000, 9999)
    // Numbers >= 10000: Indian numbering (e.g., 10,000, 1,00,000)
    String formattedInteger = '';
    
    if (integerPart.length <= 4) {
      // No commas for numbers less than 10000
      formattedInteger = integerPart;
    } else {
      // Indian numbering for numbers >= 10000
      // First 3 digits from right have no comma, then every 2 digits get a comma
      final length = integerPart.length;
      final lastThreeDigits = integerPart.substring(length - 3);
      final remainingDigits = integerPart.substring(0, length - 3);
      
      // Format remaining digits with Indian numbering (comma every 2 digits)
      String formattedRemaining = '';
      int count = 0;
      for (int i = remainingDigits.length - 1; i >= 0; i--) {
        if (count > 0 && count % 2 == 0 && i >= 0) {
          formattedRemaining = ',' + formattedRemaining;
        }
        formattedRemaining = remainingDigits[i] + formattedRemaining;
        count++;
      }
      
      // Combine: remaining digits (with commas) + last 3 digits (no comma)
      formattedInteger = formattedRemaining.isEmpty 
          ? lastThreeDigits 
          : '$formattedRemaining,$lastThreeDigits';
    }

    // Combine formatted integer with decimal part
    String formattedText = decimalPart.isNotEmpty 
        ? '$formattedInteger.$decimalPart'
        : formattedInteger;

    // Calculate cursor position
    int cursorPosition = formattedText.length;
    if (newValue.selection.baseOffset < newValue.text.length) {
      // Try to maintain relative cursor position
      final oldLength = oldValue.text.replaceAll(',', '').length;
      final newLength = formattedText.replaceAll(',', '').length;
      if (oldLength > 0) {
        final ratio = newValue.selection.baseOffset / oldValue.text.length;
        cursorPosition = (formattedText.length * ratio).round().clamp(0, formattedText.length);
      }
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: cursorPosition),
    );
  }
}

enum PlotStatus {
  available,
  sold,
  reserved,
  blocked,
}

class PlotStatusPage extends StatefulWidget {
  final List<Map<String, dynamic>>? layouts;
  final List<Map<String, dynamic>>? agents;
  final String? projectId;
  
  const PlotStatusPage({super.key, this.layouts, this.agents, this.projectId});

  @override
  State<PlotStatusPage> createState() => _PlotStatusPageState();
}

class _PlotStatusPageState extends State<PlotStatusPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  String _selectedLayout = 'All Layouts';
  String _selectedStatus = 'All Status';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Plot data structure
  List<Map<String, dynamic>> _allPlots = [];
  
  // Layouts with plots data - loaded from Site section
  List<Map<String, dynamic>> _layouts = [];
  
  // Controllers for editable fields
  final Map<String, TextEditingController> _salePriceControllers = {};
  final Map<String, TextEditingController> _buyerNameControllers = {};
  final Map<String, TextEditingController> _saleDateControllers = {};
  
  // Stored agents list from storage
  List<Map<String, dynamic>> _storedAgents = [];
  
  // Scroll controllers for tables
  final ScrollController _plotStatusTableScrollController = ScrollController();
  final Map<int, ScrollController> _layoutTableScrollControllers = {}; // Key: layoutIndex
  
  // Helper function to format decimal values
  String _formatDecimal(dynamic value) {
    if (value == null) return '0.00';
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null ? parsed.toStringAsFixed(2) : '0.00';
    }
    if (value is num) {
      return value.toStringAsFixed(2);
    }
    return '0.00';
  }
  
  // Helper function to format date from database (YYYY-MM-DD) to UI format (DD/MM/YYYY)
  String _formatDateFromDatabase(dynamic value) {
    if (value == null) return '';
    final dateStr = value.toString().trim();
    if (dateStr.isEmpty) return '';
    
    // Try to parse ISO format (YYYY-MM-DD)
    final isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
    final match = isoPattern.firstMatch(dateStr);
    if (match != null) {
      final year = match.group(1) ?? '';
      final month = match.group(2) ?? '';
      final day = match.group(3) ?? '';
      return '$day/$month/$year';
    }
    
    // If already in DD/MM/YYYY format, return as is
    return dateStr;
  }

  // Get available agents list
  List<String> get _availableAgents {
    final List<String> agents = ['Direct Sale']; // Direct Sale is always first
    
    // First, try to use agents from widget (if passed directly)
    List<Map<String, dynamic>> agentsToUse = widget.agents ?? [];
    
    // If not provided, use stored agents
    if (agentsToUse.isEmpty) {
      agentsToUse = _storedAgents;
    }
    
    // Add agents from the agent section
    for (var agent in agentsToUse) {
      final agentName = agent['name']?.toString().trim() ?? '';
      if (agentName.isNotEmpty && !agents.contains(agentName)) {
        agents.add(agentName);
      }
    }
    
    return agents;
  }
  
  @override
  void initState() {
    super.initState();
    _loadPlotData(); // This now also loads agents
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (var controller in _salePriceControllers.values) {
      controller.dispose();
    }
    for (var controller in _buyerNameControllers.values) {
      controller.dispose();
    }
    for (var controller in _saleDateControllers.values) {
      controller.dispose();
    }
    // Dispose scroll controllers
    _plotStatusTableScrollController.dispose();
    for (var controller in _layoutTableScrollControllers.values) {
      controller.dispose();
    }
    _layoutTableScrollControllers.clear();
    super.dispose();
  }

  Future<void> _loadPlotData() async {
    List<Map<String, dynamic>> sourceLayouts = widget.layouts ?? [];
    List<Map<String, dynamic>> agents = [];
    
    // If projectId is available, load from database first
    if (widget.projectId != null && widget.projectId!.isNotEmpty) {
      try {
        print('PlotStatusPage: Loading data from database for projectId=${widget.projectId}');
        
        // Load layouts from database
        final layouts = await _supabase
            .from('layouts')
            .select('id, name')
            .eq('project_id', widget.projectId!);
        
        final layoutsData = <Map<String, dynamic>>[];
        
        if (layouts.isNotEmpty) {
          for (var layout in layouts) {
            final layoutId = layout['id'];
            final plots = await _supabase
                .from('plots')
                .select()
                .eq('layout_id', layoutId);
            
            final plotsData = <Map<String, dynamic>>[];
            for (var plot in plots) {
              // Load plot partners
              final plotPartners = await _supabase
                  .from('plot_partners')
                  .select('partner_name')
                  .eq('plot_id', plot['id']);
              
              // Parse status string to PlotStatus enum
              PlotStatus plotStatus = PlotStatus.available;
              final statusString = (plot['status'] ?? 'available').toString();
              try {
                plotStatus = PlotStatus.values.firstWhere(
                  (e) => e.name == statusString,
                  orElse: () => PlotStatus.available,
                );
              } catch (e) {
                plotStatus = PlotStatus.available;
              }
              
              plotsData.add({
                'plotNumber': (plot['plot_number'] ?? '').toString(),
                'area': _formatDecimal(plot['area'] ?? 0.0),
                'purchaseRate': _formatDecimal(plot['all_in_cost_per_sqft'] ?? 0.0),
                'totalPlotCost': _formatDecimal(plot['total_plot_cost'] ?? 0.0),
                'status': plotStatus,
                'salePrice': plot['sale_price'] != null ? _formatDecimal(plot['sale_price']) : null,
                'buyerName': (plot['buyer_name'] ?? '').toString(),
                'saleDate': _formatDateFromDatabase(plot['sale_date']),
                'agent': (plot['agent_name'] ?? '').toString(),
                'partners': plotPartners.map((p) => (p['partner_name'] ?? '').toString()).toList(),
              });
            }
            
            layoutsData.add({
              'name': (layout['name'] ?? '').toString(),
              'plots': plotsData,
            });
          }
        }
        
        sourceLayouts = layoutsData;
        
        // Load agents from database
        final agentsData = await _supabase
            .from('agents')
            .select('name')
            .eq('project_id', widget.projectId!);
        
        agents = agentsData.map((a) => {
          'name': (a['name'] ?? '').toString(),
        }).toList();
        
        print('PlotStatusPage: Loaded ${sourceLayouts.length} layouts and ${agents.length} agents from database');
      } catch (e, stackTrace) {
        print('PlotStatusPage: Error loading from database: $e');
        print('Stack trace: $stackTrace');
        // Fall back to local storage if database load fails
      }
    }
    
    // Fallback to local storage or provided layouts if database load didn't work
    if (sourceLayouts.isEmpty) {
      sourceLayouts = await LayoutStorageService.loadLayoutsData();
    }
    
    // Fallback to local storage for agents if not loaded from database
    if (agents.isEmpty) {
      agents = await LayoutStorageService.loadAgentsData();
    }
    
    // Convert layout data from Site section format to plot status format
    setState(() {
      _storedAgents = agents;
      _layouts = _convertLayoutsData(sourceLayouts);
      _allPlots = [];
      
      // Populate _allPlots from layouts for filtering/search
      for (var layout in _layouts) {
        final layoutName = layout['name'] as String? ?? '';
        final plots = layout['plots'] as List<Map<String, dynamic>>? ?? [];
        for (var plot in plots) {
          _allPlots.add({
            'layout': layoutName,
            'plotNumber': plot['plotNumber'] as String? ?? '',
            'area': plot['area'] as String? ?? '0.00',
            'status': plot['status'] is PlotStatus 
                ? plot['status'] as PlotStatus 
                : (plot['status'] is String 
                    ? PlotStatus.values.firstWhere(
                        (e) => e.name == plot['status'].toString(),
                        orElse: () => PlotStatus.available,
                      )
                    : PlotStatus.available),
            'purchaseRate': plot['purchaseRate'] as String? ?? '0.00',
            'totalPlotCost': plot['totalPlotCost'] as String? ?? '0.00',
            'salePrice': plot['salePrice'] as String? ?? null,
            'buyerName': plot['buyerName'] as String? ?? '',
            'agent': plot['agent'] as String? ?? '',
            'saleDate': plot['saleDate'] as String? ?? '',
          });
        }
      }
      
      print('PlotStatusPage: Loaded ${_allPlots.length} plots total');
      
      // Initialize controllers for sale price, buyer name, and sale date from loaded data
      _initializeControllersFromData();
    });
  }
  
  void _initializeControllersFromData() {
    // Dispose old controllers first
    for (var controller in _salePriceControllers.values) {
      controller.dispose();
    }
    for (var controller in _buyerNameControllers.values) {
      controller.dispose();
    }
    for (var controller in _saleDateControllers.values) {
      controller.dispose();
    }
    _salePriceControllers.clear();
    _buyerNameControllers.clear();
    _saleDateControllers.clear();
    
    // Initialize controllers with data from _layouts
    for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
      final plots = _layouts[layoutIndex]['plots'] as List<dynamic>? ?? [];
      for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
        final plot = plots[plotIndex] as Map<String, dynamic>;
        final status = plot['status'] is PlotStatus 
            ? plot['status'] as PlotStatus 
            : (plot['status'] is String 
                ? PlotStatus.values.firstWhere(
                    (e) => e.name == plot['status'].toString(),
                    orElse: () => PlotStatus.available,
                  )
                : PlotStatus.available);
        
        if (status == PlotStatus.sold) {
          // Initialize sale price controller
          final priceKey = '${layoutIndex}_${plotIndex}_price';
          final salePrice = plot['salePrice'] as String?;
          _salePriceControllers[priceKey] = TextEditingController(
            text: (salePrice != null && salePrice.isNotEmpty && salePrice != '0.00') ? salePrice : '',
          );
          
          // Initialize buyer name controller
          final buyerKey = '${layoutIndex}_${plotIndex}_buyer';
          final buyerName = plot['buyerName'] as String? ?? '';
          _buyerNameControllers[buyerKey] = TextEditingController(
            text: buyerName,
          );
          
          // Initialize sale date controller
          final dateKey = '${layoutIndex}_${plotIndex}_date';
          final saleDate = plot['saleDate'] as String? ?? '';
          _saleDateControllers[dateKey] = TextEditingController(
            text: saleDate,
          );
        }
      }
    }
    
    print('PlotStatusPage: Initialized ${_salePriceControllers.length} sale price controllers, ${_buyerNameControllers.length} buyer name controllers, ${_saleDateControllers.length} sale date controllers');
  }

  Future<void> _saveLayoutsData() async {
    // Save updated layout data back to storage
    // Convert _layouts back to the format expected by storage
    final layoutsToSave = _layouts.asMap().entries.map((layoutEntry) {
      final layoutIndex = layoutEntry.key;
      final layout = layoutEntry.value;
      final plots = (layout['plots'] as List<dynamic>).asMap().entries.map((plotEntry) {
        final plotIndex = plotEntry.key;
        final plotMap = plotEntry.value as Map<String, dynamic>;
        
        // Get values from controllers using the correct key format
        final priceKey = '${layoutIndex}_${plotIndex}_price';
        final buyerKey = '${layoutIndex}_${plotIndex}_buyer';
        final dateKey = '${layoutIndex}_${plotIndex}_date';
        
        final salePriceController = _salePriceControllers[priceKey];
        final buyerNameController = _buyerNameControllers[buyerKey];
        final saleDateController = _saleDateControllers[dateKey];
        
        // Get sale price - convert empty string to null
        final salePriceText = salePriceController?.text.trim() ?? plotMap['salePrice']?.toString() ?? '';
        final cleanedSalePrice = salePriceText.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
        final salePrice = (cleanedSalePrice.isEmpty || cleanedSalePrice == '0' || cleanedSalePrice == '0.00') 
            ? null 
            : cleanedSalePrice;
        
        // Get buyer name - convert empty string to null
        final buyerNameText = buyerNameController?.text.trim() ?? plotMap['buyerName']?.toString() ?? '';
        final buyerName = buyerNameText.isEmpty ? null : buyerNameText;
        
        // Get agent - convert empty string to null
        final agentText = plotMap['agent']?.toString() ?? '';
        final agent = agentText.isEmpty ? null : agentText;
        
        // Get sale date - convert empty string to null
        final saleDateText = saleDateController?.text.trim() ?? plotMap['saleDate']?.toString() ?? '';
        final saleDate = saleDateText.isEmpty ? null : saleDateText;
        
        // Get partners - ensure it's a list
        final partners = plotMap['partners'] as List<dynamic>? ?? [];
        final partnersList = partners.map((p) => p.toString()).toList();
        
        return {
          'plotNumber': plotMap['plotNumber'] as String? ?? '',
          'area': plotMap['area'] as String? ?? '0.00',
          'purchaseRate': plotMap['purchaseRate'] as String? ?? '0.00',
          'totalPlotCost': plotMap['totalPlotCost'] as String? ?? '0.00',
          'status': (plotMap['status'] as PlotStatus?)?.name ?? 'available',
          'salePrice': salePrice,
          'buyerName': buyerName,
          'agent': agent,
          'saleDate': saleDate,
          'partners': partnersList,
        };
      }).toList();
      
      return {
        'name': layout['name'] as String? ?? 'Layout',
        'plots': plots,
      };
    }).toList();
    
    // Save to Supabase if projectId is available, otherwise save to local storage
    if (widget.projectId != null && widget.projectId!.isNotEmpty) {
      try {
        await ProjectStorageService.saveProjectData(
          projectId: widget.projectId!,
          projectName: '', // Not updating project name
          layouts: layoutsToSave,
        );
      } catch (e) {
        print('Error saving plot status to Supabase: $e');
        // Fallback to local storage
        await LayoutStorageService.saveLayoutsDataDirect(layoutsToSave);
      }
    } else {
      // Save to local storage if no projectId
      await LayoutStorageService.saveLayoutsDataDirect(layoutsToSave);
    }
  }

  Future<void> _saveToStorage(List<Map<String, dynamic>> layouts) async {
    await LayoutStorageService.saveLayoutsDataDirect(layouts);
  }

  List<Map<String, dynamic>> _convertLayoutsData(List<Map<String, dynamic>> sourceLayouts) {
    // Convert layouts from Site section format to Plot Status format
    // Site format: plots have plotNumber, area, purchaseRate, partner (values may be in controllers)
    // Plot Status format: plots need status, salePrice, buyerName, agent, saleDate
    // If data comes from project_details_page, extract values from controllers
    return sourceLayouts.map((layout) {
      final plots = (layout['plots'] as List<dynamic>? ?? []).map((plot) {
        final plotMap = plot as Map<String, dynamic>;
        
        // Extract plot data - handle both direct values and controller-based values
        String plotNumber = '';
        String area = '0.00';
        String purchaseRate = '0.00';
        String totalPlotCost = '0.00';
        
        // If plotNumber is a controller, get its text, otherwise use the value directly
        if (plotMap['plotNumber'] is TextEditingController) {
          plotNumber = (plotMap['plotNumber'] as TextEditingController).text;
        } else {
          plotNumber = plotMap['plotNumber'] as String? ?? '';
        }
        
        // Same for area
        if (plotMap['area'] is TextEditingController) {
          area = (plotMap['area'] as TextEditingController).text;
        } else {
          area = plotMap['area'] as String? ?? '0.00';
        }
        
        // Same for purchaseRate
        if (plotMap['purchaseRate'] is TextEditingController) {
          purchaseRate = (plotMap['purchaseRate'] as TextEditingController).text;
        } else {
          purchaseRate = plotMap['purchaseRate'] as String? ?? '0.00';
        }
        
        // Same for totalPlotCost
        if (plotMap['totalPlotCost'] is TextEditingController) {
          totalPlotCost = (plotMap['totalPlotCost'] as TextEditingController).text;
        } else {
          totalPlotCost = plotMap['totalPlotCost'] as String? ?? '0.00';
        }
        
        // Handle status - can be PlotStatus enum or string
        PlotStatus plotStatus = PlotStatus.available;
        if (plotMap['status'] is PlotStatus) {
          plotStatus = plotMap['status'] as PlotStatus;
        } else if (plotMap['status'] is String) {
          final statusString = plotMap['status'] as String;
          plotStatus = PlotStatus.values.firstWhere(
            (e) => e.name == statusString,
            orElse: () => PlotStatus.available,
          );
        }
        
        return {
          'plotNumber': plotNumber,
          'area': area.isEmpty ? '0.00' : area,
          'status': plotStatus,
          'salePrice': plotMap['salePrice'] as String? ?? '0.00',
          'buyerName': plotMap['buyerName'] as String? ?? '',
          'agent': plotMap['agent'] as String? ?? '',
          'saleDate': plotMap['saleDate'] as String? ?? '',
          'purchaseRate': purchaseRate.isEmpty ? '0.00' : purchaseRate,
          'totalPlotCost': totalPlotCost.isEmpty ? '0.00' : totalPlotCost,
        };
      }).toList();
      
      // Extract layout name - handle controller case
      String layoutName = 'Layout';
      if (layout['name'] is TextEditingController) {
        layoutName = (layout['name'] as TextEditingController).text;
      } else {
        layoutName = layout['name'] as String? ?? 'Layout';
      }
      
      return {
        'name': layoutName.isEmpty ? 'Layout' : layoutName,
        'plots': plots,
      };
    }).toList();
  }

  void _updatePlotStatus(int index, PlotStatus newStatus) {
    setState(() {
      if (index < _allPlots.length) {
        final plot = _allPlots[index];
        final plotNumber = plot['plotNumber'] as String? ?? '';
        final layoutName = plot['layout'] as String? ?? '';
        
        // Update _allPlots
        _allPlots[index]['status'] = newStatus;
        
        // Also update the corresponding plot in _layouts
        for (var layout in _layouts) {
          if ((layout['name'] as String? ?? '') == layoutName) {
            final plots = layout['plots'] as List<dynamic>? ?? [];
            for (var plotData in plots) {
              if (plotData is Map<String, dynamic>) {
                final pn = plotData['plotNumber'] as String? ?? '';
                if (pn == plotNumber) {
                  plotData['status'] = newStatus;
                  break;
                }
              }
            }
            break;
          }
        }
      }
    });
  }

  List<String> get _availableLayouts {
    final layouts = _allPlots.map((plot) => plot['layout'] as String? ?? '').toSet().toList();
    layouts.remove('');
    layouts.sort();
    return ['All Layouts', ...layouts];
  }

  List<Map<String, dynamic>> get _filteredPlots {
    return _allPlots.where((plot) {
      // Filter by layout
      if (_selectedLayout != 'All Layouts') {
        if ((plot['layout'] as String? ?? '') != _selectedLayout) {
          return false;
        }
      }

      // Filter by status
      if (_selectedStatus != 'All Status') {
        final plotStatus = plot['status'] as PlotStatus? ?? PlotStatus.available;
        final statusString = _getStatusString(plotStatus);
        if (statusString != _selectedStatus) {
          return false;
        }
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final plotNumber = (plot['plotNumber'] as String? ?? '').toLowerCase();
        final layout = (plot['layout'] as String? ?? '').toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!plotNumber.contains(query) && !layout.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _salesData {
    final salesData = <Map<String, dynamic>>[];
    for (var layout in _layouts) {
      final plots = layout['plots'] as List<Map<String, dynamic>>? ?? [];
      for (var plot in plots) {
        final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
        if (status == PlotStatus.sold) {
          salesData.add({
            'plotNumber': plot['plotNumber'] as String? ?? '',
            'area': plot['area'] as String? ?? '0.00',
            'status': status,
            'salePrice': plot['salePrice'] as String? ?? '0.00',
            'buyerName': plot['buyerName'] as String? ?? '',
            'agent': plot['agent'] as String? ?? '',
            'saleDate': plot['saleDate'] as String? ?? '',
          });
        }
      }
    }
    return salesData;
  }

  String _getStatusString(PlotStatus status) {
    switch (status) {
      case PlotStatus.available:
        return 'Available';
      case PlotStatus.sold:
        return 'Sold';
      case PlotStatus.reserved:
        return 'Reserved';
      case PlotStatus.blocked:
        return 'Blocked';
    }
  }

  Color _getStatusColor(PlotStatus status) {
    switch (status) {
      case PlotStatus.available:
        return const Color(0xFF50CD89); // Bright green (matching Figma)
      case PlotStatus.sold:
        return const Color(0xFFFF0000); // Red #FF0000
      case PlotStatus.reserved:
        return const Color(0xFFFFA500); // Orange
      case PlotStatus.blocked:
        return const Color(0xFFFF0000); // Red
    }
  }

  Color _getStatusBackgroundColor(PlotStatus status) {
    switch (status) {
      case PlotStatus.available:
        return const Color(0xFFE9F7EB); // Light green (matching Figma)
      case PlotStatus.sold:
        return const Color(0xFFFFECEC); // Light pink (matching Figma)
      case PlotStatus.reserved:
        return const Color(0xFFFFF4E6); // Light orange
      case PlotStatus.blocked:
        return const Color(0xFFFFEBEE); // Light red
    }
  }

  String _formatIntegerWithIndianNumbering(String integerPart) {
    if (integerPart.length <= 4) {
      return integerPart;
    } else {
      final length = integerPart.length;
      final lastThreeDigits = integerPart.substring(length - 3);
      final remainingDigits = integerPart.substring(0, length - 3);
      
      String formattedRemaining = '';
      int count = 0;
      for (int i = remainingDigits.length - 1; i >= 0; i--) {
        if (count > 0 && count % 2 == 0 && i >= 0) {
          formattedRemaining = ',' + formattedRemaining;
        }
        formattedRemaining = remainingDigits[i] + formattedRemaining;
        count++;
      }
      
      return formattedRemaining.isEmpty 
          ? lastThreeDigits 
          : '$formattedRemaining,$lastThreeDigits';
    }
  }

  String _formatAmount(String value) {
    if (value.trim().isEmpty) {
      return '0.00';
    }
    
    String cleaned = value.trim().replaceAll('₹', '').replaceAll(' ', '').replaceAll(',', '');
    
    String integerPart;
    String decimalPart;
    
    if (!cleaned.contains('.')) {
      integerPart = cleaned.isEmpty ? '0' : cleaned;
      decimalPart = '00';
    } else {
      final parts = cleaned.split('.');
      integerPart = parts[0].isEmpty ? '0' : parts[0];
      decimalPart = parts.length > 1 ? parts[1] : '00';
      decimalPart = decimalPart.length > 2 
          ? decimalPart.substring(0, 2) 
          : decimalPart.padRight(2, '0');
    }
    
    final formattedInteger = _formatIntegerWithIndianNumbering(integerPart);
    return '$formattedInteger.$decimalPart';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload agents when page becomes visible to get latest data
    _refreshAgents();
  }

  Future<void> _refreshAgents() async {
    final agents = await LayoutStorageService.loadAgentsData();
    if (mounted) {
      setState(() {
        _storedAgents = agents;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;

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
                'Plot Status',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 28 : isTablet ? 32 : 36,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage plot availability, holds, and sales with buyer and pricing details.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 0),
          child: Row(
            children: [
              Column(
                children: [
                  Column(
                    children: [
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
                            "Site",
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
                ],
              ),
            ],
          ),
        ),
        // Horizontal line from sidebar to end of screen
        Transform.translate(
          offset: const Offset(-22, 0), // Move left to start from sidebar shadow end
          child: Container(
            width: MediaQuery.of(context).size.width - 0 + 24, // Full screen width minus sidebar+shadow, plus extend 24px to right edge
            height: 1,
            color: const Color(0xFF5C5C5C),
          ),
        ),
        const SizedBox(height: 24),
        // Content - Scrollable
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              clipBehavior: Clip.hardEdge,
              padding: const EdgeInsets.only(
                left: 0,
                bottom: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
        // Overall Sales card
        Builder(
          builder: (context) {
            // Calculate totals from all layouts
            double totalAreaSold = 0.0;
            double totalSalesPrice = 0.0; // Sum of sale price column (₹/sqft)
            double totalSaleValue = 0.0; // Sum of sale value column (₹)
            for (var layout in _layouts) {
              final plots = layout['plots'] as List<Map<String, dynamic>>? ?? [];
              for (var plot in plots) {
                final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
                if (status == PlotStatus.sold) {
                  final area = double.tryParse(plot['area'] as String? ?? '0.00') ?? 0.0;
                  final salePriceStr = (plot['salePrice'] as String? ?? '0.00').replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                  final salePrice = double.tryParse(salePriceStr) ?? 0.0;
                  totalAreaSold += area;
                  totalSalesPrice += salePrice; // Sum of sale price per sqft
                  totalSaleValue += salePrice * area; // Sum of sale value (price * area)
                }
              }
            }
            
            return Container(
              width: 686,
              margin: const EdgeInsets.only(bottom: 24),
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
                children: [
                  Text(
                    "Overall Sales",
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: "Total Area Sold: ",
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: "${_formatAmount(totalAreaSold.toString())} sqft",
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: "Total Sales Price: ",
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: "₹/sqft ${_formatAmount(totalSalesPrice.toString())}",
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: "Total Sale Value: ",
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: "₹ ${_formatAmount(totalSaleValue.toString())}",
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
            );
          },
        ),
        const SizedBox(height: 24),
        // Layout cards with tables
        if (_layouts.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Colors.black.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No layouts found',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: Colors.black.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add layouts and plots in the Site tab to view their status here',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: Colors.black.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          )
        else
          ...List.generate(_layouts.length, (layoutIndex) {
            return Container(
              margin: const EdgeInsets.only(bottom: 24),
              child: _buildLayoutCard(layoutIndex, _layouts[layoutIndex]),
            );
          }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlotStatusTable() {
    final filteredPlots = _filteredPlots;

    if (filteredPlots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.black.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No plots found',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Colors.black.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add plots in the Site tab to view their status here',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: Colors.black.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    return Scrollbar(
      controller: _plotStatusTableScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _plotStatusTableScrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sl. No. column
            _buildColumn(
              header: 'Sl. No.',
              width: 70,
              isFirst: true,
              children: List.generate(filteredPlots.length, (index) {
                return _buildCell(
                  width: 70,
                  content: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.normal,
                      color: Colors.black, // #000
                      height: 1.0, // normal line-height
                    ),
                  ),
                  isLast: index == filteredPlots.length - 1,
                );
              }),
            ),
            // Layout column
            _buildColumn(
              header: 'Layout',
              width: 186,
              children: List.generate(filteredPlots.length, (index) {
                final layout = filteredPlots[index]['layout'] as String? ?? '';
                return _buildCell(
                  width: 186,
                  content: Text(
                    layout.isEmpty ? '-' : layout,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  isLast: index == filteredPlots.length - 1,
                );
              }),
            ),
            // Plot Number column
            _buildColumn(
              header: 'Plot Number',
              width: 215,
              children: List.generate(filteredPlots.length, (index) {
                final plotNumber = filteredPlots[index]['plotNumber'] as String? ?? '';
                return _buildCell(
                  width: 215,
                  content: Text(
                    plotNumber.isEmpty ? '-' : plotNumber,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  isLast: index == filteredPlots.length - 1,
                );
              }),
            ),
            // Area column
            _buildColumn(
              header: 'Area (Sqft)',
              width: 180,
              children: List.generate(filteredPlots.length, (index) {
                final area = filteredPlots[index]['area'] as String? ?? '0.00';
                return _buildCell(
                  width: 180,
                  content: Text(
                    _formatAmount(area),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  isLast: index == filteredPlots.length - 1,
                );
              }),
            ),
            // Purchase Rate column
            _buildColumn(
              header: 'Purchase Rate',
              width: 215,
              children: List.generate(filteredPlots.length, (index) {
                final rate = filteredPlots[index]['purchaseRate'] as String? ?? '0.00';
                return _buildCell(
                  width: 215,
                  content: Text(
                    rate.isEmpty || rate == '0.00' ? '-' : '₹ ${_formatAmount(rate)}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  isLast: index == filteredPlots.length - 1,
                );
              }),
            ),
            // Status column
            _buildColumn(
              header: 'Status',
              width: 320,
              isLast: true,
              children: List.generate(filteredPlots.length, (index) {
                final status = filteredPlots[index]['status'] as PlotStatus? ?? PlotStatus.available;
                final statusColor = _getStatusColor(status);
                final statusText = _getStatusString(status);
                final statusBackgroundColor = _getStatusBackgroundColor(status);
                return _buildCell(
                  width: 320,
                  content: Builder(
                    builder: (builderContext) {
                      final statusKey = GlobalKey();
                      final iconKey = GlobalKey();
                      
                      if (status == PlotStatus.sold) {
                        return Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showStatusChangeDialogForFiltered(builderContext, index, status, statusKey),
                              child: Container(
                                key: statusKey,
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
                                      decoration: BoxDecoration(
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
                                      statusText,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        fontStyle: FontStyle.normal,
                                        color: Colors.black, // #000
                                        height: 1.0, // normal line-height
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              key: iconKey,
                              onTap: () => _showStatusChangeDialogForFiltered(builderContext, index, status, statusKey),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: const Color(0xFF212121), // Dark grey icon
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showStatusChangeDialogForFiltered(builderContext, index, status, statusKey),
                                child: Container(
                                  key: statusKey,
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
                                        decoration: BoxDecoration(
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
                                        statusText,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.normal,
                                          fontStyle: FontStyle.normal,
                                          color: Colors.black, // #000
                                          height: 1.0, // normal line-height
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              key: iconKey,
                              onTap: () => _showStatusChangeDialogForFiltered(builderContext, index, status, statusKey),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: const Color(0xFF212121), // Dark grey icon
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                  isLast: index == filteredPlots.length - 1,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn({
    required String header,
    required double width,
    required List<Widget> children,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Column(
      children: [
        // Header
        Container(
          width: width,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF707070).withOpacity(0.2),
            border: Border.all(color: Colors.black, width: 1.0),
            borderRadius: isFirst
                ? const BorderRadius.only(topLeft: Radius.circular(8))
                : isLast
                    ? const BorderRadius.only(topRight: Radius.circular(8))
                    : null,
          ),
          child: Center(
            child: Text(
              header,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        // Rows
        ...children,
      ],
    );
  }

  Widget _buildCell({
    required double width,
    required Widget content,
    bool isLast = false,
  }) {
    return Container(
      width: width,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          right: const BorderSide(color: Colors.black, width: 1.0),
          bottom: BorderSide(
            color: Colors.black,
            width: isLast ? 1.0 : 1.0,
          ),
          top: BorderSide.none,
          left: BorderSide.none,
        ),
        borderRadius: isLast
            ? const BorderRadius.only(bottomRight: Radius.circular(8))
            : null,
      ),
      child: Center(child: content),
    );
  }

  Widget _buildLayoutCard(int layoutIndex, Map<String, dynamic> layout) {
    final plots = layout['plots'] as List<Map<String, dynamic>>? ?? [];
    final layoutName = layout['name'] as String? ?? 'Layout ${layoutIndex + 1}';
    
    // Calculate totals
    double totalAreaSold = 0.0;
    double totalSalesPrice = 0.0; // Sum of sale price column (₹/sqft)
    double totalSaleValue = 0.0; // Sum of sale value column (₹)
    for (var plot in plots) {
      final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
      if (status == PlotStatus.sold) {
        final area = double.tryParse(plot['area'] as String? ?? '0.00') ?? 0.0;
        final salePriceStr = (plot['salePrice'] as String? ?? '0.00').replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
        final salePrice = double.tryParse(salePriceStr) ?? 0.0;
        totalAreaSold += area;
        totalSalesPrice += salePrice; // Sum of sale price per sqft
        totalSaleValue += salePrice * area; // Sum of sale value (price * area)
      }
    }
    
    return Container(
      width: double.infinity,
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
        children: [
          // Layout header
          Row(
            children: [
              Text(
                '${layoutIndex + 1}. Layout: ',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              Text(
                layoutName,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${layoutIndex + 1}. ',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.transparent,
                ),
              ),
              Text(
                '${plots.length} plots',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Table
          Builder(
            builder: (context) {
              // Initialize scroll controller for this layout if it doesn't exist
              if (!_layoutTableScrollControllers.containsKey(layoutIndex)) {
                _layoutTableScrollControllers[layoutIndex] = ScrollController();
              }
              final scrollController = _layoutTableScrollControllers[layoutIndex]!;
              
              return Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: _buildLayoutTable(layoutIndex, plots),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Footer totals
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Total Area Sold: ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    TextSpan(
                      text: '${_formatAmount(totalAreaSold.toString())} sqft',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Total Sales Price: ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    TextSpan(
                      text: '₹/sqft ${_formatAmount(totalSalesPrice.toString())}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Total Sale Value: ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    TextSpan(
                      text: '₹ ${_formatAmount(totalSaleValue.toString())}',
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
        ],
      ),
    );
  }

  Widget _buildLayoutTable(int layoutIndex, List<Map<String, dynamic>> plots) {
    if (plots.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sl. No. column
          Column(
            children: [
              Container(
                width: 70,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF707070).withOpacity(0.2),
                  border: Border.all(color: Colors.black, width: 1.0),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Sl. No.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.normal,
                      color: Colors.black, // #000
                      height: 1.0, // normal line-height
                    ),
                  ),
                ),
              ),
              ...List.generate(plots.length, (index) {
                final isLast = index == plots.length - 1;
                return Container(
                  width: 70,
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border(
                      left: const BorderSide(color: Colors.black, width: 1.0),
                      right: const BorderSide(color: Colors.black, width: 1.0),
                      bottom: const BorderSide(color: Colors.black, width: 1.0),
                      top: BorderSide.none,
                    ),
                    borderRadius: isLast
                        ? const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                          )
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.normal,
                        color: Colors.black, // #000
                        height: 1.0, // normal line-height
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          // Plot Number column
          _buildTableColumn(
            header: 'Plot Number',
            width: 186,
            plots: plots,
            builder: (plot, index) => Text(
              (plot['plotNumber'] as String? ?? '').isEmpty ? '-' : (plot['plotNumber'] as String? ?? ''),
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Area (sqft) column
          _buildTableColumn(
            header: 'Area (sqft)',
            width: 215,
            plots: plots,
            builder: (plot, index) => Text(
              'sqft ${_formatAmount(plot['area'] as String? ?? '0.00')}',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Status * column
          _buildTableColumn(
            header: 'Status *',
            width: 180,
            plots: plots,
            builder: (plot, index) {
              final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
              final statusColor = _getStatusColor(status);
              final statusBackgroundColor = _getStatusBackgroundColor(status);
              final statusText = _getStatusString(status);
              final statusKey = GlobalKey();
              final iconKey = GlobalKey();
              
              if (status == PlotStatus.sold) {
                return Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showStatusChangeDialog(context, layoutIndex, index, status, statusKey),
                      child: Container(
                        key: statusKey,
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
                              decoration: BoxDecoration(
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
                              statusText,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                fontStyle: FontStyle.normal,
                                color: Colors.black, // #000
                                height: 1.0, // normal line-height
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      key: iconKey,
                      onTap: () => _showStatusChangeDialog(context, layoutIndex, index, status, statusKey),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: const Color(0xFF212121), // Dark grey icon
                      ),
                    ),
                  ],
                );
              } else {
                return Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showStatusChangeDialog(context, layoutIndex, index, status, statusKey),
                        child: Container(
                          key: statusKey,
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
                                decoration: BoxDecoration(
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
                                statusText,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  fontStyle: FontStyle.normal,
                                  color: Colors.black, // #000
                                  height: 1.0, // normal line-height
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      key: iconKey,
                      onTap: () => _showStatusChangeDialog(context, layoutIndex, index, status, statusKey),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: const Color(0xFF212121), // Dark grey icon
                      ),
                    ),
                  ],
                );
              }
            },
          ),
          // Sale Price (₹/sqft) * column
          _buildTableColumn(
            header: 'Sale Price (₹/sqft) *',
            width: 215,
            plots: plots,
            builder: (plot, index) {
              final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
              final key = '${layoutIndex}_${index}_price';
              if (status == PlotStatus.sold) {
                if (!_salePriceControllers.containsKey(key)) {
                  _salePriceControllers[key] = TextEditingController(
                    text: plot['salePrice'] as String? ?? '0.00',
                  );
                } else {
                  // Don't update controller during rebuilds - let the formatter and onChanged handle it
                  // This prevents the controller from being reset while user is typing
                }
                final controller = _salePriceControllers[key]!;
                final salePriceEmpty = controller.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim().isEmpty ||
                                      controller.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim() == '0' ||
                                      controller.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim() == '0.00' ||
                                      (plot['salePrice']?.toString().trim().isEmpty ?? true) ||
                                      plot['salePrice'] == '0.00';
                return Container(
                  width: 200,
                  height: 32,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: salePriceEmpty ? Colors.red : Colors.black.withOpacity(0.15),
                                blurRadius: 2,
                                offset: const Offset(0, 0),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Builder(
                            builder: (context) {
                              final cleanedText = controller.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                              final isEmpty = cleanedText.isEmpty || cleanedText == '0' || cleanedText == '0.00';
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    '₹ ',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      keyboardType: TextInputType.number,
                                      textAlignVertical: TextAlignVertical.center,
                                      inputFormatters: [IndianNumberFormatter()],
                                      onTap: () {
                                        // Clear '0.00' when field is tapped
                                        final cleaned = controller.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                                        if (cleaned == '0' || cleaned == '0.00') {
                                          controller.text = '';
                                          controller.selection = TextSelection.collapsed(offset: 0);
                                          setState(() {});
                                        }
                                      },
                                      onChanged: (value) {
                                        // Remove commas, format, then store with commas
                                        final rawValue = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
                                        final formatted = rawValue.isEmpty ? '0.00' : _formatAmount(rawValue);
                                        setState(() {
                                          _layouts[layoutIndex]['plots'][index]['salePrice'] = formatted;
                                        });
                                        _saveLayoutsData();
                                      },
                                      onEditingComplete: () {
                                        // Remove commas before formatting
                                        final cleaned = controller.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                                        // Format the amount (this ensures .00 is added and adds commas)
                                        final formatted = _formatAmount(cleaned);
                                        // Store value WITH commas
                                        // Apply formatter to ensure commas are displayed
                                        // Pass the cleaned value (without commas) to formatter so it can add them
                                        final cleanedForFormatter = formatted.replaceAll(',', ''); // Already has .00 format
                                        final oldValue = controller.value;
                                        final newValue = TextEditingValue(
                                          text: cleanedForFormatter,
                                          selection: TextSelection.collapsed(offset: cleanedForFormatter.length),
                                        );
                                        final formattedValue = IndianNumberFormatter().formatEditUpdate(
                                          oldValue,
                                          newValue,
                                        );
                                        controller.value = formattedValue;
                                        setState(() {
                                          _layouts[layoutIndex]['plots'][index]['salePrice'] = formatted;
                                        });
                                        _saveLayoutsData();
                                        FocusScope.of(context).nextFocus();
                                      },
                                      onTapOutside: (event) {
                                        // Remove commas before formatting
                                        final cleaned = controller.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                                        // Format the amount (this ensures .00 is added and adds commas)
                                        final formatted = _formatAmount(cleaned);
                                        // Store value WITH commas
                                        // Apply formatter to ensure commas are displayed
                                        // Pass the cleaned value (without commas) to formatter so it can add them
                                        final cleanedForFormatter = formatted.replaceAll(',', ''); // Already has .00 format
                                        final oldValue = controller.value;
                                        final newValue = TextEditingValue(
                                          text: cleanedForFormatter,
                                          selection: TextSelection.collapsed(offset: cleanedForFormatter.length),
                                        );
                                        final formattedValue = IndianNumberFormatter().formatEditUpdate(
                                          oldValue,
                                          newValue,
                                        );
                                        controller.value = formattedValue;
                                        setState(() {
                                          _layouts[layoutIndex]['plots'][index]['salePrice'] = formatted;
                                        });
                                        _saveLayoutsData();
                                      },
                                      decoration: InputDecoration(
                                        hintText: '0.00',
                                        hintStyle: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.normal,
                                          color: const Color(0xFF5D5D5D),
                                        ),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                        isDense: true,
                                      ),
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: isEmpty ? const Color(0xFF5D5D5D) : Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                return Text(
                  '-',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                );
              }
            },
          ),
          // Sale Value (₹) column
          _buildTableColumn(
            header: 'Sale Value (₹)',
            width: 215,
            plots: plots,
            builder: (plot, index) {
              final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
              if (status == PlotStatus.sold) {
                // Calculate sale value = sale price * area
                final salePriceStr = plot['salePrice'] as String? ?? '0.00';
                final areaStr = plot['area'] as String? ?? '0.00';
                
                // Parse values (remove commas and format)
                final salePrice = double.tryParse(
                  salePriceStr.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim()
                ) ?? 0.0;
                final area = double.tryParse(
                  areaStr.replaceAll(',', '').replaceAll(' ', '').trim()
                ) ?? 0.0;
                
                final saleValue = salePrice * area;
                final formattedValue = saleValue > 0 ? _formatAmount(saleValue.toStringAsFixed(2)) : '0.00';
                
                return Container(
                  width: 200,
                  height: 32,
                  child: Center(
                    child: Text(
                      '₹ $formattedValue',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              } else {
                return Text(
                  '-',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                );
              }
            },
          ),
          // Buyer Name * column
          _buildTableColumn(
            header: 'Buyer Name *',
            width: 320,
            plots: plots,
            builder: (plot, index) {
              final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
              final key = '${layoutIndex}_${index}_buyer';
              if (status == PlotStatus.sold) {
                if (!_buyerNameControllers.containsKey(key)) {
                  _buyerNameControllers[key] = TextEditingController(
                    text: plot['buyerName'] as String? ?? '',
                  );
                } else {
                  // Update controller if data has changed
                  final currentValue = plot['buyerName'] as String? ?? '';
                  if (_buyerNameControllers[key]!.text != currentValue) {
                    _buyerNameControllers[key]!.text = currentValue;
                  }
                }
                return Container(
                  width: 300,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
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
                  child: TextField(
                    controller: _buyerNameControllers[key],
                    onChanged: (value) {
                      setState(() {
                        _layouts[layoutIndex]['plots'][index]['buyerName'] = value;
                      });
                      _saveLayoutsData();
                    },
                    textAlignVertical: TextAlignVertical.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter buyer's name",
                      hintStyle: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: const Color(0xFF5D5D5D),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                );
              } else {
                return Text(
                  '-',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                );
              }
            },
          ),
          // Agent * column
          _buildTableColumn(
            header: 'Agent *',
            width: 241,
            plots: plots,
            builder: (plot, index) {
              final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
              final currentAgent = plot['agent'] as String? ?? '';
              if (status == PlotStatus.sold) {
                final agentKey = GlobalKey();
                return Builder(
                  builder: (builderContext) {
                    return Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () => _showAgentDropdown(builderContext, layoutIndex, index, currentAgent, agentKey),
                              child: Container(
                                key: agentKey,
                                constraints: const BoxConstraints(maxWidth: 200),
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: currentAgent.isEmpty
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
                                    currentAgent.isEmpty ? 'Select Agent' : currentAgent,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: currentAgent.isEmpty
                                          ? const Color(0xFF5D5D5D)
                                          : Colors.black,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Align(
                            alignment: Alignment.center,
                            child: GestureDetector(
                              onTap: () => _showAgentDropdown(builderContext, layoutIndex, index, currentAgent, agentKey),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: const Color(0xFF212121),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              } else {
                return Text(
                  '-',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                );
              }
            },
          ),
          // Sale date * column
          _buildTableColumn(
            header: 'Sale date *',
            width: 220,
            isLast: true,
            plots: plots,
            builder: (plot, index) {
              final status = plot['status'] as PlotStatus? ?? PlotStatus.available;
              final key = '${layoutIndex}_${index}_date';
              if (status == PlotStatus.sold) {
                if (!_saleDateControllers.containsKey(key)) {
                  _saleDateControllers[key] = TextEditingController(
                    text: plot['saleDate'] as String? ?? '',
                  );
                } else {
                  // Update controller if data has changed
                  final currentValue = plot['saleDate'] as String? ?? '';
                  if (_saleDateControllers[key]!.text != currentValue) {
                    _saleDateControllers[key]!.text = currentValue;
                  }
                }
                return Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: () => _selectSaleDate(layoutIndex, index, key),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 180),
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
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
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: Colors.black.withOpacity(0.6),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: _saleDateControllers[key],
                                    readOnly: true,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.black,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'dd/mm/yyyy',
                                      hintStyle: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: const Color(0xFF5D5D5D),
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
                      ),
                      const SizedBox(width: 8),
                      Align(
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: () => _selectSaleDate(layoutIndex, index, key),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: const Color(0xFF212121),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return Text(
                  '-',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTableColumn({
    required String header,
    required double width,
    required List<Map<String, dynamic>> plots,
    required Widget Function(Map<String, dynamic> plot, int index) builder,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Container(
          width: width,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF707070).withOpacity(0.2),
            border: const Border(
              top: BorderSide(color: Colors.black, width: 1.0),
              right: BorderSide(color: Colors.black, width: 1.0),
              bottom: BorderSide(color: Colors.black, width: 1.0),
              left: BorderSide.none,
            ),
            borderRadius: isLast
                ? const BorderRadius.only(
                    topRight: Radius.circular(8),
                  )
                : null,
          ),
          child: Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: header.replaceAll(' *', ''),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  if (header.contains('*'))
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
        ),
        ...List.generate(plots.length, (index) {
          final isLastRow = index == plots.length - 1;
          return Container(
            width: width,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                right: const BorderSide(color: Colors.black, width: 1.0),
                bottom: const BorderSide(color: Colors.black, width: 1.0),
                top: BorderSide.none,
                left: BorderSide.none,
              ),
              borderRadius: isLast && isLastRow
                  ? const BorderRadius.only(
                      bottomRight: Radius.circular(8),
                    )
                  : null,
            ),
            child: Center(child: builder(plots[index], index)),
          );
        }),
      ],
    );
  }

  void _showStatusChangeDialog(BuildContext context, int layoutIndex, int plotIndex, PlotStatus currentStatus, GlobalKey statusKey) {
    final RenderBox? renderBox = statusKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final overlay = Overlay.of(context);
    final offset = renderBox.localToGlobal(Offset.zero);
    
    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;
    
    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
    }
    
    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeDropdown,
          child: Container(color: Colors.transparent),
        ),
      ),
    );
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx - 50,
        top: offset.dy + renderBox.size.height - 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: renderBox.size.width + 100,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 2,
                  offset: const Offset(0, 0),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header section
                  Container(
                    padding: const EdgeInsets.only(top: 4, left: 8, right: 8, bottom: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Select Plot Status',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Transform.rotate(
                          angle: 180 * 3.14159 / 180, // Rotate 180 degrees
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Options section
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status options - Only show Available and Sold (matching Figma)
                        ...([PlotStatus.available, PlotStatus.sold].map((status) {
                          final statusColor = _getStatusColor(status);
                          final statusText = _getStatusString(status);
                          final backgroundColor = _getStatusBackgroundColor(status);
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _layouts[layoutIndex]['plots'][plotIndex]['status'] = status;
                              });
                              _saveLayoutsData();
                              closeDropdown();
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: backgroundColor,
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
                                mainAxisSize: status == PlotStatus.sold ? MainAxisSize.min : MainAxisSize.max,
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
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
                                    statusText,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FontStyle.normal,
                                      color: Colors.black, // #000
                                      height: 1.0, // normal line-height
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        })),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
  }

  void _showStatusChangeDialogForFiltered(BuildContext context, int index, PlotStatus currentStatus, GlobalKey statusKey) {
    if (index >= _filteredPlots.length) return;
    
    final RenderBox? renderBox = statusKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final overlay = Overlay.of(context);
    final offset = renderBox.localToGlobal(Offset.zero);
    
    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;
    
    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
    }
    
    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeDropdown,
          child: Container(color: Colors.transparent),
        ),
      ),
    );
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx - 50,
        top: offset.dy + renderBox.size.height - 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: renderBox.size.width + 100,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 2,
                  offset: const Offset(0, 0),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header section
                  Container(
                    padding: const EdgeInsets.only(top: 4, left: 8, right: 8, bottom: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Select Plot Status',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Transform.rotate(
                          angle: 180 * 3.14159 / 180, // Rotate 180 degrees
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Options section
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status options - Only show Available and Sold (matching Figma)
                        ...([PlotStatus.available, PlotStatus.sold].map((status) {
                          final statusColor = _getStatusColor(status);
                          final statusText = _getStatusString(status);
                          final backgroundColor = _getStatusBackgroundColor(status);
                          
                          return GestureDetector(
                            onTap: () async {
                              final filteredPlot = _filteredPlots[index];
                              final actualIndex = _allPlots.indexWhere((p) => 
                                p['plotNumber'] == filteredPlot['plotNumber'] &&
                                p['layout'] == filteredPlot['layout']
                              );
                              if (actualIndex >= 0) {
                                _updatePlotStatus(actualIndex, status);
                                // Save to database after status change
                                await _saveLayoutsData();
                              }
                              closeDropdown();
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: backgroundColor,
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
                                mainAxisSize: status == PlotStatus.sold ? MainAxisSize.min : MainAxisSize.max,
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
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
                                    statusText,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      fontStyle: FontStyle.normal,
                                      color: Colors.black, // #000
                                      height: 1.0, // normal line-height
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        })),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
  }

  void _showAgentDropdown(BuildContext context, int layoutIndex, int plotIndex, String currentAgent, GlobalKey cellKey) {
    final RenderBox? renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final agents = _availableAgents;
    final overlay = Overlay.of(context);
    final offset = renderBox.localToGlobal(Offset.zero);
    
    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;
    
    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
    }
    
    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeDropdown,
          child: Container(color: Colors.transparent),
        ),
      ),
    );
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx - 50,
        top: offset.dy + renderBox.size.height - 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: renderBox.size.width + 100,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 2,
                  offset: const Offset(0, 0),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header section
                  Container(
                    padding: const EdgeInsets.only(top: 4, left: 8, right: 8, bottom: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Select Agent',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Transform.rotate(
                          angle: 180 * 3.14159 / 180, // Rotate 180 degrees
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Options section
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...agents.asMap().entries.map((entry) {
                          final agentIndex = entry.key;
                          final agent = entry.value;
                          final isLast = agentIndex == agents.length - 1;
                          final isDirectSale = agent == 'Direct Sale';
                          final isSelected = agent == currentAgent;
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _layouts[layoutIndex]['plots'][plotIndex]['agent'] = agent;
                              });
                              _saveLayoutsData();
                              closeDropdown();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.black.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    agent,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isDirectSale 
                                          ? const Color(0xFF0C8CE9) // Blue for Direct Sale
                                          : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
  }

  Future<void> _selectSaleDate(int layoutIndex, int plotIndex, String key) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0C8CE9),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      final formattedDate = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      setState(() {
        _layouts[layoutIndex]['plots'][plotIndex]['saleDate'] = formattedDate;
        _saleDateControllers[key]?.text = formattedDate;
      });
      _saveLayoutsData();
    }
  }

}
