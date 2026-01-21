import 'dart:async';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/project_save_status.dart';
import '../widgets/decimal_input_field.dart';
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

    // Find the position of the decimal point in the new value (before cleaning)
    int decimalPosition = newValue.text.indexOf('.');
    
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
      integerPart = splitParts[0].isEmpty ? '0' : splitParts[0]; // Default to '0' if empty
      decimalPart = splitParts.length > 1 ? splitParts[1] : '';
    } else {
      integerPart = cleaned.isEmpty ? '0' : cleaned; // Default to '0' if empty
    }

    // Format integer part with Indian numbering
    // Numbers < 1000: no commas (e.g., 100, 999)
    // Numbers >= 1000: Indian numbering (e.g., 1,000, 1,00,000)
    String formattedInteger = '';
    
    if (integerPart.isEmpty || integerPart == '0') {
      formattedInteger = integerPart.isEmpty ? '0' : integerPart;
    } else if (integerPart.length <= 3) {
      // No commas for numbers less than 1000
      formattedInteger = integerPart;
    } else {
      // Indian numbering for numbers >= 1000
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
    // Keep the decimal point even if decimalPart is empty (user might still be typing)
    String formattedText = cleaned.contains('.')
        ? '$formattedInteger.${decimalPart}'
        : formattedInteger;

    // Calculate cursor position
    int cursorPosition = formattedText.length;
    
    // Count commas in the formatted text up to where the cursor should be
    // Based on how many non-comma characters were in the original input
    int unformattedLength = newValue.selection.baseOffset;
    int commaCount = 0;
    int charCount = 0;
    
    for (int i = 0; i < formattedText.length && charCount < unformattedLength; i++) {
      if (formattedText[i] != ',') {
        charCount++;
      } else {
        commaCount++;
      }
    }
    
    cursorPosition = unformattedLength + commaCount;
    cursorPosition = cursorPosition.clamp(0, formattedText.length);

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: cursorPosition),
    );
  }
}

// TextInputFormatter for months (limit to 12)
class MonthsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Remove all non-digit characters
    String cleaned = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    
    // Limit to 12
    if (cleaned.isNotEmpty) {
      final value = int.tryParse(cleaned) ?? 0;
      if (value > 12) {
        cleaned = '12';
      }
    }

    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}

// TextInputFormatter for percentage (limit to 100)
class PercentageInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Remove all non-digit characters
    String cleaned = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    
    // Limit to 100
    if (cleaned.isNotEmpty) {
      final value = int.tryParse(cleaned) ?? 0;
      if (value > 100) {
        cleaned = '100';
      }
    }

    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}

class ProjectDetailsPage extends StatefulWidget {
  final String? initialProjectName;
  final String? projectId;
  final Function(ProjectSaveStatusType)? onSaveStatusChanged;
  final Function(bool)? onErrorStateChanged;
  
  const ProjectDetailsPage({
    super.key, 
    this.initialProjectName,
    this.projectId,
    this.onSaveStatusChanged,
    this.onErrorStateChanged,
  });

  @override
  State<ProjectDetailsPage> createState() => _ProjectDetailsPageState();
}

enum ProjectTab {
  about,
  partners,
  expenses,
  site,
  projectManagers,
  agents,
}

class _ProjectDetailsPageState extends State<ProjectDetailsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _projectNameController = TextEditingController();
  final TextEditingController _totalAreaController = TextEditingController();
  final TextEditingController _sellingAreaController = TextEditingController();
  
  final FocusNode _projectNameFocusNode = FocusNode();
  final FocusNode _totalAreaFocusNode = FocusNode();
  final FocusNode _sellingAreaFocusNode = FocusNode();
  
  List<Map<String, String>> _nonSellableAreas = [
    {'name': '', 'area': '0.00'},
  ];
  
  // Controllers for non-sellable area names
  final Map<int, TextEditingController> _nonSellableNameControllers = {};
  // Controllers for non-sellable area values
  final Map<int, TextEditingController> _nonSellableAreaControllers = {};
  
  // Timer for debouncing save status changes
  Timer? _saveStatusTimer;
  // Timer for debouncing data changed callbacks to prevent focus loss
  Timer? _dataChangedDebounceTimer;
  // Flag to prevent saving during data loading
  bool _isLoadingData = false;
  
  // Tab state
  ProjectTab _activeTab = ProjectTab.about;
  
  // Partners data
  final TextEditingController _estimatedDevelopmentCostController = TextEditingController();
  List<Map<String, dynamic>> _partners = [
    {'name': '', 'amount': '0.00'},
  ];
  final Map<int, TextEditingController> _partnerNameControllers = {};
  final Map<int, TextEditingController> _partnerAmountControllers = {};
  
  // Expenses data
  List<Map<String, dynamic>> _expenses = [
    {'item': 'Total Plot Purchasing Cost', 'amount': '0.00', 'category': 'Land Cost'},
    {'item': '', 'amount': '0.00', 'category': ''},
  ];
  final Map<int, TextEditingController> _expenseItemControllers = {};
  final Map<int, TextEditingController> _expenseAmountControllers = {};
  final List<String> _expenseCategories = [
    'Land Cost',
    'Statutory & Registration',
    'Legal & Professional Fees',
    'Survey, Approvals & Conversion',
    'Construction & Development',
    'Amenities & Infrastructure',
    'Others',
  ];

  // Site/Layouts data
  final TextEditingController _numberOfLayoutsController = TextEditingController(text: '0');
  final FocusNode _numberOfLayoutsFocusNode = FocusNode();
  List<Map<String, dynamic>> _layouts = []; // Each layout will contain plots
  final Map<int, TextEditingController> _layoutNameControllers = {}; // Controllers for layout names
  final Map<int, FocusNode> _layoutNameFocusNodes = {}; // Focus nodes for layout names
  final Map<String, TextEditingController> _plotNumberControllers = {}; // Key: 'layoutIndex_plotIndex'
  final Map<String, FocusNode> _plotNumberFocusNodes = {}; // Focus nodes for plot numbers
  final Map<String, TextEditingController> _plotAreaControllers = {}; // Key: 'layoutIndex_plotIndex'
  final Map<String, FocusNode> _plotAreaFocusNodes = {}; // Focus nodes for plot areas
  final Map<String, TextEditingController> _plotPurchaseRateControllers = {}; // Key: 'layoutIndex_plotIndex'
  final Map<String, FocusNode> _plotPurchaseRateFocusNodes = {}; // Focus nodes for purchase rates
  final Map<String, List<String>> _plotPartners = {}; // Key: 'layoutIndex_plotIndex', value: list of partner names
  bool _isCreateTableEnabled = false; // State for Create Table button

  // Project Managers data
  List<Map<String, dynamic>> _projectManagers = [
    {'name': '', 'compensation': '', 'earningType': ''},
  ];
  final Map<int, TextEditingController> _projectManagerNameControllers = {};
  final Map<int, TextEditingController> _projectManagerFixedFeeControllers = {}; // Fixed Fee amount controllers
  final Map<int, FocusNode> _projectManagerFixedFeeFocusNodes = {}; // Fixed Fee focus nodes
  final Map<int, TextEditingController> _projectManagerMonthlyFeeControllers = {}; // Monthly Fee amount controllers
  final Map<int, FocusNode> _projectManagerMonthlyFeeFocusNodes = {}; // Monthly Fee focus nodes
  final Map<int, TextEditingController> _projectManagerMonthsControllers = {}; // Months controllers
  final Map<int, FocusNode> _projectManagerMonthsFocusNodes = {}; // Months focus nodes
  final Map<int, TextEditingController> _projectManagerPercentageControllers = {}; // Percentage controllers
  final Map<int, FocusNode> _projectManagerPercentageFocusNodes = {}; // Percentage focus nodes
  final Map<int, String> _projectManagerCompensation = {}; // Selected compensation type
  final Map<int, String> _projectManagerEarningType = {}; // Selected earning type
  final Map<int, String> _projectManagerPercentage = {}; // Percentage value for earning type
  final Map<int, String> _projectManagerFixedFee = {}; // Fixed Fee amount value
  final Map<int, String> _projectManagerMonthlyFee = {}; // Monthly Fee amount value
  final Map<int, String> _projectManagerMonths = {}; // Months value
  final Map<int, List<String>> _projectManagerSelectedBlocks = {}; // Selected blocks/plots for each project manager
  
  // Agents data
  List<Map<String, dynamic>> _agents = [
    {'name': '', 'compensation': '', 'earningType': ''},
  ];
  final Map<int, TextEditingController> _agentNameControllers = {};
  final Map<int, TextEditingController> _agentFixedFeeControllers = {}; // Fixed Fee amount controllers
  final Map<int, FocusNode> _agentFixedFeeFocusNodes = {}; // Fixed Fee focus nodes
  final Map<int, TextEditingController> _agentMonthlyFeeControllers = {}; // Monthly Fee amount controllers
  final Map<int, FocusNode> _agentMonthlyFeeFocusNodes = {}; // Monthly Fee focus nodes
  final Map<int, TextEditingController> _agentMonthsControllers = {}; // Months controllers
  final Map<int, FocusNode> _agentMonthsFocusNodes = {}; // Months focus nodes
  final Map<int, TextEditingController> _agentPercentageControllers = {}; // Percentage controllers
  final Map<int, FocusNode> _agentPercentageFocusNodes = {}; // Percentage focus nodes
  final Map<int, String> _agentCompensation = {}; // Selected compensation type
  final Map<int, String> _agentEarningType = {}; // Selected earning type
  final Map<int, String> _agentPercentage = {}; // Percentage value for earning type
  final Map<int, String> _agentFixedFee = {}; // Fixed Fee amount value
  final Map<int, String> _agentMonthlyFee = {}; // Monthly Fee amount value
  final Map<int, String> _agentMonths = {}; // Months value
  final Map<int, TextEditingController> _agentPerSqftFeeControllers = {}; // Per Sqft Fee amount controllers
  final Map<int, FocusNode> _agentPerSqftFeeFocusNodes = {}; // Per Sqft Fee focus nodes
  final Map<int, String> _agentPerSqftFee = {}; // Per Sqft Fee amount value
  final Map<int, List<String>> _agentSelectedBlocks = {}; // Selected blocks/plots for each agent
  
  // Scroll controllers for tables
  final ScrollController _partnersTableScrollController = ScrollController();
  final ScrollController _expensesTableScrollController = ScrollController();
  final ScrollController _projectManagersTableScrollController = ScrollController();
  final ScrollController _agentsTableScrollController = ScrollController();
  final Map<int, ScrollController> _plotsTableScrollControllers = {}; // Key: layoutIndex
  
  // Agent-specific compensation types (includes Per Sqft Fee)
  final List<String> _agentCompensationTypes = [
    'Percentage Bonus',
    'Fixed Fee',
    'Monthly Fee',
    'Per Sqft Fee',
    'None',
  ];
  
  final List<String> _compensationTypes = [
    'Percentage Bonus',
    'Fixed Fee',
    'Monthly Fee',
    'None',
  ];
  final List<String> _earningTypes = [
    'Per Plot',
    'Per Square Foot',
    'Lump Sum',
  ];
  final List<String> _percentageBonusEarningTypes = [
    '% of Profit on Each Sold Plot',
    '% of Selling Price per Plot',
    '% of Total Project Profit',
  ];

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Land Purchase Cost':
        return const Color(0xFFE2F4D1).withOpacity(0.8);
      case 'Statutory & Registration':
        return const Color(0xFFC8C0DC);
      case 'Legal & Professional Fees':
        return const Color(0xFFDCD4C0);
      case 'Survey, Approvals & Conversion':
        return const Color(0xFFC0DCDC);
      case 'Construction & Development':
        return const Color(0xFFDCC0CF);
      case 'Amenities & Infrastructure':
        return const Color(0xFFE7B7B8);
      case 'Others':
        return const Color(0xFFC4C4C4).withOpacity(0.8);
      default:
        return const Color(0xFFF5F5F5).withOpacity(0.8);
    }
  }

  Color _getCompensationColor(String compensation) {
    // All compensation types use the same blue shade
    return const Color(0xFFECF6FD);
  }

  // Helper function to format integer part with Indian numbering
  // Numbers < 10000: no commas (e.g., 1000, 9999)
  // Numbers >= 10000: Indian numbering (e.g., 10,000, 1,00,000)
  String _formatIntegerWithIndianNumbering(String integerPart) {
    if (integerPart.length <= 3) {
      // No commas for numbers less than 1000
      return integerPart;
    } else {
      // Indian numbering for numbers >= 1000
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
      return formattedRemaining.isEmpty 
          ? lastThreeDigits 
          : '$formattedRemaining,$lastThreeDigits';
    }
  }

  // Helper function to format amount: append .00 if no decimals and add Indian number formatting
  String _formatAmount(String value) {
    if (value.trim().isEmpty) {
      return '0.00';
    }
    
    // Remove any currency symbols, spaces, and commas
    String cleaned = value.trim().replaceAll('₹', '').replaceAll(' ', '').replaceAll(',', '');
    
    String integerPart;
    String decimalPart;
    
    // If it doesn't contain a decimal point, append .00
    if (!cleaned.contains('.')) {
      integerPart = cleaned.isEmpty ? '0' : cleaned;
      decimalPart = '00';
    } else {
      // If it contains a decimal point, ensure 2 decimal places
      final parts = cleaned.split('.');
      integerPart = parts[0].isEmpty ? '0' : parts[0];
      decimalPart = parts.length > 1 ? parts[1] : '00';
      
      // Pad decimal part to 2 places or truncate if longer
      decimalPart = decimalPart.length > 2 
          ? decimalPart.substring(0, 2) 
          : decimalPart.padRight(2, '0');
    }
    
    // Format integer part with Indian numbering
    final formattedInteger = _formatIntegerWithIndianNumbering(integerPart);
    
    return '$formattedInteger.$decimalPart';
  }

  // Helper function to format currency value for display (₹ 0.00 format)
  String _formatCurrency(String value) {
    if (value.isEmpty || value == '0') {
      return '₹ 0.00';
    }
    
    // Parse the value to handle decimals
    double? numValue = double.tryParse(value);
    if (numValue == null) {
      return '₹ 0.00';
    }
    
    // Format to always show 2 decimal places
    String formatted = numValue.toStringAsFixed(2);
    
    // Add Indian numbering formatting for the integer part
    final parts = formatted.split('.');
    String integerPart = parts[0];
    String decimalPart = parts.length > 1 ? parts[1] : '00';
    
    // Format integer part with Indian numbering
    String formattedInteger = _formatIntegerWithIndianNumbering(integerPart);
    
    return '₹ $formattedInteger.$decimalPart';
  }

  // Helper function to format double amount for display with Indian numbering
  String _formatAmountForDisplay(double amount, {int decimalPlaces = 2}) {
    final isNegative = amount < 0;
    String formattedAmount = amount.abs().toStringAsFixed(decimalPlaces);
    final parts = formattedAmount.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '0' * decimalPlaces;
    
    // Format integer part with Indian numbering
    final formattedInteger = _formatIntegerWithIndianNumbering(integerPart);
    
    return '${isNegative ? '-' : ''}$formattedInteger.$decimalPart';
  }

  double get _totalNonSellableArea {
    return _nonSellableAreas.fold(0.0, (sum, area) => sum + (double.tryParse(area['area'] ?? '0') ?? 0.0));
  }

  double get _remainingArea {
    final totalArea = double.tryParse(_totalAreaController.text) ?? 0;
    final sellingArea = double.tryParse(_sellingAreaController.text) ?? 0;
    return totalArea - sellingArea - _totalNonSellableArea;
  }

  double get _estimatedDevelopmentCost {
    final cleaned = _estimatedDevelopmentCostController.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  double get _totalPartnerAmount {
    return _partners.fold(0.0, (sum, partner) {
      final amount = double.tryParse(partner['amount'] ?? '0.00') ?? 0.0;
      return sum + amount;
    });
  }

  double get _remainingPartnerAmount {
    return _estimatedDevelopmentCost - _totalPartnerAmount;
  }

  double get _totalExpenses {
    double total = 0.0;
    for (int i = 0; i < _expenses.length; i++) {
      // Prioritize controller text (what's actually in the amount column)
      final controllerAmount = _expenseAmountControllers[i]?.text.trim() ?? '';
      // Remove commas and currency symbols for parsing
      final cleanedAmount = controllerAmount.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
      final amount = double.tryParse(cleanedAmount.isEmpty ? '0.00' : cleanedAmount) ?? 0.0;
      total += amount;
    }
    return total;
  }

  double get _remainingBudget {
    return _estimatedDevelopmentCost - _totalExpenses;
  }

  double get _totalSharePercentage {
    if (_estimatedDevelopmentCost == 0) return 0.0;
    return (_totalPartnerAmount / _estimatedDevelopmentCost) * 100;
  }

  double _getPartnerShare(int index) {
    if (_estimatedDevelopmentCost == 0) return 0.0;
    final amount = double.tryParse(_partners[index]['amount'] ?? '0.00') ?? 0.0;
    return (amount / _estimatedDevelopmentCost) * 100;
  }

  // Site/Layouts calculations
  double get _approvedSellingArea {
    try {
      final text = _sellingAreaController.text;
      if (text.isEmpty) return 0.0;
      final cleaned = text.replaceAll(',', '').replaceAll(' ', '');
      return double.tryParse(cleaned) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  double get _allocatedArea {
    // Sum of all plot areas across all layouts
    double total = 0.0;
    for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
      final plotsData = _layouts[layoutIndex]['plots'];
      List<Map<String, dynamic>> plots;
      if (plotsData is List) {
        plots = plotsData.map((p) {
          if (p is Map<String, dynamic>) {
            return p;
          } else if (p is Map) {
            return Map<String, dynamic>.from(p);
          } else {
            return <String, dynamic>{};
          }
        }).toList();
      } else {
        plots = [];
      }
      
      for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
        final key = '${layoutIndex}_$plotIndex';
        final areaController = _plotAreaControllers[key];
        if (areaController != null) {
          final area = double.tryParse(areaController.text.replaceAll(',', '').replaceAll(' ', '')) ?? 0.0;
          total += area;
        }
      }
    }
    return total;
  }

  double get _remainingSiteArea {
    return _approvedSellingArea - _allocatedArea;
  }

  double get _totalPurchaseRate {
    // Calculate as sum of all-in cost values from the fourth column in the plots table
    // This is the sum of actual all-in cost values shown for each plot
    final allInCost = _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;
    
    double total = 0.0;
    for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
      final plotsData = _layouts[layoutIndex]['plots'];
      List<Map<String, dynamic>> plots;
      if (plotsData is List) {
        plots = plotsData.map((p) {
          if (p is Map<String, dynamic>) {
            return p;
          } else if (p is Map) {
            return Map<String, dynamic>.from(p);
          } else {
            return <String, dynamic>{};
          }
        }).toList();
      } else {
        plots = [];
      }
      
      for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
        final key = '${layoutIndex}_$plotIndex';
        final areaController = _plotAreaControllers[key];
        if (areaController != null) {
          final area = double.tryParse(areaController.text.replaceAll(',', '').replaceAll(' ', '').trim() ?? '0') ?? 0.0;
          // Only sum for plots with area > 0
          if (area > 0) {
            // Add the all-in cost for this plot (same rate for all plots)
            total += allInCost;
          }
        }
      }
    }
    
    // Return sum of all-in cost column values
    return total;
  }

  double get _totalPlotCost {
    // Calculate as sum of (area * all-in cost) for all plots
    // All-in cost = total expenses / approved selling area
    final allInCost = _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;
    
    double total = 0.0;
    for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
      final plotsData = _layouts[layoutIndex]['plots'];
      List<Map<String, dynamic>> plots;
      if (plotsData is List) {
        plots = plotsData.map((p) {
          if (p is Map<String, dynamic>) {
            return p;
          } else if (p is Map) {
            return Map<String, dynamic>.from(p);
          } else {
            return <String, dynamic>{};
          }
        }).toList();
      } else {
        plots = [];
      }
      
      for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
        final key = '${layoutIndex}_$plotIndex';
        final areaController = _plotAreaControllers[key];
        if (areaController != null) {
          final area = double.tryParse(areaController.text.replaceAll(',', '').replaceAll(' ', '').trim() ?? '0') ?? 0.0;
          // Total Plot Cost for this plot = area * all-in cost
          total += area * allInCost;
        }
      }
    }
    return total;
  }

  bool get _hasPartnerValidationErrors {
    if (_partners.isEmpty) return false;
    
    // Check if any partner has validation errors
    for (int i = 0; i < _partners.length; i++) {
      // Check name field - prioritize controller text, fallback to partner data
      final controllerName = _partnerNameControllers[i]?.text.trim() ?? '';
      final partnerName = _partners[i]['name']?.toString().trim() ?? '';
      final nameEmpty = controllerName.isEmpty && partnerName.isEmpty;
      
      // Check amount field - prioritize controller text, fallback to partner data
      final controllerAmount = _partnerAmountControllers[i]?.text.trim() ?? '';
      final partnerAmount = _partners[i]['amount']?.toString().trim() ?? '';
      final amountEmpty = (controllerAmount.isEmpty || controllerAmount == '0.00') &&
                          (partnerAmount.isEmpty || partnerAmount == '0.00');
      
      // Check if exceeding estimated development cost
      final exceedsAmount = _totalPartnerAmount > _estimatedDevelopmentCost && _estimatedDevelopmentCost > 0;
      
      if (nameEmpty || amountEmpty || exceedsAmount) {
        return true;
      }
    }
    
    return false;
  }

  bool get _hasExpenseValidationErrors {
    if (_expenses.isEmpty) return false;
    
    // Check if any expense has validation errors (red box shadows)
    for (int i = 0; i < _expenses.length; i++) {
      // Check expense item field - prioritize controller text, fallback to expense data
      final controllerItem = _expenseItemControllers[i]?.text.trim() ?? '';
      final expenseItem = _expenses[i]['item']?.toString().trim() ?? '';
      final itemEmpty = (controllerItem.isEmpty) &&
                       (expenseItem.isEmpty || expenseItem == null);
      
      // Check amount field - prioritize controller text, fallback to expense data
      final controllerAmount = _expenseAmountControllers[i]?.text.trim() ?? '';
      final expenseAmount = _expenses[i]['amount']?.toString().trim() ?? '';
      // Remove commas for checking
      final cleanedControllerAmount = controllerAmount.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
      final cleanedExpenseAmount = expenseAmount.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
      final amountEmpty = (cleanedControllerAmount.isEmpty || cleanedControllerAmount == '0.00') &&
                          (cleanedExpenseAmount.isEmpty || cleanedExpenseAmount == '0.00');
      
      if (itemEmpty || amountEmpty) {
        return true;
      }
    }
    
    return false;
  }

  bool get _hasProjectManagerValidationErrors {
    if (_projectManagers.isEmpty) return false;
    
    // Check if any project manager has validation errors (red box shadows)
    for (int i = 0; i < _projectManagers.length; i++) {
      // Check name field - prioritize controller text, fallback to stored value
      final controllerName = _projectManagerNameControllers[i]?.text.trim() ?? '';
      final managerName = _projectManagers[i]['name']?.toString().trim() ?? '';
      final nameEmpty = controllerName.isEmpty && managerName.isEmpty;
      
      // Get compensation type
      final compensationType = _projectManagerCompensation[i] ?? '';
      final compensationEmpty = compensationType.isEmpty || compensationType == 'None';
      
      // Get earning type
      String selectedEarningType = '';
      try {
        selectedEarningType = _projectManagerEarningType[i] ?? '';
      } catch (e) {
        selectedEarningType = '';
      }
      
      // Red box shadow appears when:
      // 1. Name is empty (regardless of compensation)
      if (nameEmpty) {
        return true;
      }
      
      // 2. Compensation is empty (regardless of name)
      if (compensationEmpty) {
        return true;
      }
      
      // 3. Compensation is not empty/None AND earning type is empty
      if (!compensationEmpty && selectedEarningType.isEmpty) {
        return true;
      }
    }
    
    return false;
  }

  bool get _hasAgentValidationErrors {
    if (_agents.isEmpty) return false;
    
    // Check if any agent has validation errors (red box shadows)
    for (int i = 0; i < _agents.length; i++) {
      // Check name field - prioritize controller text, fallback to stored value
      final controllerName = _agentNameControllers[i]?.text.trim() ?? '';
      final agentName = _agents[i]['name']?.toString().trim() ?? '';
      final nameEmpty = controllerName.isEmpty && agentName.isEmpty;
      
      // Get compensation type
      final compensationType = _agentCompensation[i] ?? '';
      final compensationEmpty = compensationType.isEmpty || compensationType == 'None';
      
      // Get earning type
      String selectedEarningType = '';
      try {
        selectedEarningType = _agentEarningType[i] ?? '';
      } catch (e) {
        selectedEarningType = '';
      }
      
      // Red box shadow appears when:
      // 1. Name is empty (regardless of compensation)
      if (nameEmpty) {
        return true;
      }
      
      // 2. Compensation is empty (regardless of name)
      if (compensationEmpty) {
        return true;
      }
      
      // 3. Compensation is not empty/None AND earning type is empty
      if (!compensationEmpty && selectedEarningType.isEmpty) {
        return true;
      }
    }
    
    return false;
  }

  bool get _hasSiteValidationErrors {
    if (_layouts.isEmpty) return false;
    
    // Check if any plot in any layout has validation errors (red box shadows)
    for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
      final plots = _layouts[layoutIndex]['plots'] as List<dynamic>? ?? [];
      
      for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
        final key = '${layoutIndex}_$plotIndex';
        
        // Check plot number
        final plotNumberController = _plotNumberControllers[key];
        final plotNumberEmpty = (plotNumberController?.text.trim().isEmpty ?? true) || 
                                (plots[plotIndex]['plotNumber']?.toString().trim().isEmpty ?? true);
        
        // Check area
        final areaController = _plotAreaControllers[key];
        final cleanedAreaText = areaController?.text.replaceAll(',', '').replaceAll(' ', '').trim() ?? '';
        final areaIsEmpty = cleanedAreaText.isEmpty || cleanedAreaText == '0' || cleanedAreaText == '0.00';
        final areaEmpty = areaIsEmpty || 
                         (plots[plotIndex]['area']?.toString().trim().isEmpty ?? true) || 
                         plots[plotIndex]['area'] == '0.00';
        
        // Check purchase rate
        final purchaseRateController = _plotPurchaseRateControllers[key];
        final cleanedPurchaseRateText = purchaseRateController?.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim() ?? '';
        final purchaseRateIsEmpty = cleanedPurchaseRateText.isEmpty || cleanedPurchaseRateText == '0' || cleanedPurchaseRateText == '0.00';
        final purchaseRateEmpty = purchaseRateIsEmpty ||
                                  (plots[plotIndex]['purchaseRate']?.toString().trim().isEmpty ?? true) ||
                                  plots[plotIndex]['purchaseRate'] == '0.00';
        
        // Check partners
        final selectedPartners = _plotPartners[key] ?? [];
        final partnersEmpty = selectedPartners.isEmpty;
        
        if (plotNumberEmpty || areaEmpty || purchaseRateEmpty || partnersEmpty) {
          return true;
        }
      }
    }
    
    return false;
  }

  // Helper method to process number of layouts and create layouts
  void _processNumberOfLayouts() {
    // Remove commas before parsing
    final cleaned = _numberOfLayoutsController.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
    
    // If value is empty, don't remove layouts - just update the controller
    if (cleaned.isEmpty) {
      _numberOfLayoutsController.text = _layouts.length.toString();
      setState(() {
        _isCreateTableEnabled = _layouts.length > 0;
      });
      _onDataChanged();
      FocusScope.of(context).unfocus();
      return;
    }
    
    // Parse the number (handle decimal by taking integer part)
    final numValue = double.tryParse(cleaned) ?? 0.0;
    final numLayouts = numValue.toInt();
    
    // Don't allow reducing below current number of layouts with data
    // Only allow adding more layouts
    if (numLayouts < _layouts.length) {
      // If user tries to reduce, keep current count and update controller
      final formatted = _formatIntegerWithIndianNumbering(_layouts.length.toString());
      _numberOfLayoutsController.text = formatted;
      setState(() {
        _isCreateTableEnabled = _layouts.length > 0;
      });
      _onDataChanged();
      FocusScope.of(context).unfocus();
      return;
    }
    
    // Format the number with Indian numbering
    final formatted = _formatIntegerWithIndianNumbering(numLayouts.toString());
    _numberOfLayoutsController.text = formatted;
    
    setState(() {
      _isCreateTableEnabled = numLayouts > 0;
      // Only add new layouts if the number is greater than current count
      if (numLayouts > _layouts.length) {
        // Add new layouts (keep existing ones)
        for (int i = _layouts.length; i < numLayouts; i++) {
          // Create default plot for new layout
          final defaultPlot = {
            'plotNumber': '',
            'area': '0.00',
            'purchaseRate': '0.00',
            'totalPlotCost': '0.00',
            'partner': '',
          };
          _layouts.add({
            'name': 'Layout ${i + 1}',
            'plots': [defaultPlot],
          });
          // Initialize layout name controller with empty text to show placeholder
          _layoutNameControllers[i] = TextEditingController(
            text: '',
          );
          // Initialize controllers for the default plot
          final plotKey = '${i}_0';
          _plotNumberControllers[plotKey] = TextEditingController();
          _plotAreaControllers[plotKey] = TextEditingController();
          _plotPurchaseRateControllers[plotKey] = TextEditingController();
        }
      }
      // If numLayouts equals _layouts.length, do nothing (keep existing layouts)
    });
    _onDataChanged();
    FocusScope.of(context).unfocus();
  }

  @override
  void initState() {
    super.initState();
    // Set initial project name if provided
    if (widget.initialProjectName != null) {
      _projectNameController.text = widget.initialProjectName!;
    }
    // Initialize controllers for existing non-sellable areas
    for (int i = 0; i < _nonSellableAreas.length; i++) {
      _nonSellableNameControllers[i] = TextEditingController(
        text: _nonSellableAreas[i]['name'] ?? 'Roads and Utilities',
      );
      final nonSellableAreaValue = _nonSellableAreas[i]['area'] ?? '0.00';
      final nonSellableAreaNum = double.tryParse(nonSellableAreaValue.toString().replaceAll(',', '')) ?? 0.0;
      _nonSellableAreaControllers[i] = TextEditingController(
        text: nonSellableAreaNum == 0.0 ? '' : nonSellableAreaValue.toString(),
      );
    }
    // Initialize partner controllers
    for (int i = 0; i < _partners.length; i++) {
      _partnerNameControllers[i] = TextEditingController(
        text: _partners[i]['name'] ?? '',
      );
      _partnerAmountControllers[i] = TextEditingController();
    }
    // Initialize expense controllers
    for (int i = 0; i < _expenses.length; i++) {
      _expenseItemControllers[i] = TextEditingController(
        text: _expenses[i]['item'] ?? '',
      );
      final expenseAmount = _expenses[i]['amount'] ?? '0.00';
      final expenseAmountNum = double.tryParse(expenseAmount.toString().replaceAll(',', '')) ?? 0.0;
      _expenseAmountControllers[i] = TextEditingController(
        text: expenseAmountNum == 0.0 ? '' : expenseAmount.toString(),
      );
    }
    
    // Initialize project manager controllers
    for (int i = 0; i < _projectManagers.length; i++) {
      _projectManagerNameControllers[i] = TextEditingController(
        text: _projectManagers[i]['name'] ?? '',
      );
      _projectManagerCompensation[i] = _projectManagers[i]['compensation'] ?? '';
      _projectManagerEarningType[i] = _projectManagers[i]['earningType'] ?? '';
      _projectManagerPercentage[i] = '';
      _projectManagerFixedFee[i] = '';
      _projectManagerMonthlyFee[i] = '';
      _projectManagerMonths[i] = '';
      _projectManagerPercentageControllers[i] = TextEditingController();
      _projectManagerFixedFeeControllers[i] = TextEditingController();
      _projectManagerMonthlyFeeControllers[i] = TextEditingController();
      _projectManagerMonthsControllers[i] = TextEditingController();
    }
    
    // Initialize agent controllers
    for (int i = 0; i < _agents.length; i++) {
      _agentNameControllers[i] = TextEditingController(
        text: _agents[i]['name'] ?? '',
      );
      _agentCompensation[i] = _agents[i]['compensation'] ?? '';
      _agentEarningType[i] = _agents[i]['earningType'] ?? '';
      _agentPercentage[i] = '';
      _agentFixedFee[i] = '';
      _agentMonthlyFee[i] = '';
      _agentMonths[i] = '';
      _agentPerSqftFee[i] = '';
      _agentPercentageControllers[i] = TextEditingController();
      _agentFixedFeeControllers[i] = TextEditingController();
      _agentMonthlyFeeControllers[i] = TextEditingController();
      _agentMonthsControllers[i] = TextEditingController();
      _agentPerSqftFeeControllers[i] = TextEditingController();
    }
    
    // Load project data from Supabase if projectId is provided
    if (widget.projectId != null && widget.projectId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadProjectData();
      });
    }
    
    // Notify initial error state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyErrorState();
    });
  }

  Future<void> _loadProjectData() async {
    if (widget.projectId == null || widget.projectId!.isEmpty) {
      print('_loadProjectData: No projectId provided');
      return;
    }

    print('_loadProjectData: Loading data for projectId=${widget.projectId}');
    _isLoadingData = true; // Prevent saving during data load
    
    try {
      // Load project basic info
      final project = await _supabase
          .from('projects')
          .select()
          .eq('id', widget.projectId!)
          .single();

      setState(() {
        _projectNameController.text = project['project_name'] ?? widget.initialProjectName ?? '';
        final totalArea = project['total_area'] ?? 0.0;
        final sellingArea = project['selling_area'] ?? 0.0;
        final estimatedCost = project['estimated_development_cost'] ?? 0.0;
        _totalAreaController.text = (totalArea is num && totalArea == 0.0) ? '' : _formatDecimal(totalArea);
        _sellingAreaController.text = (sellingArea is num && sellingArea == 0.0) ? '' : _formatDecimal(sellingArea);
        _estimatedDevelopmentCostController.text = (estimatedCost is num && estimatedCost == 0.0) ? '' : _formatDecimal(estimatedCost);
      });

      // Load non-sellable areas
      final nonSellableAreas = await _supabase
          .from('non_sellable_areas')
          .select()
          .eq('project_id', widget.projectId!);
      
      // Dispose old controllers first
      for (var controller in _nonSellableNameControllers.values) {
        controller.dispose();
      }
      for (var controller in _nonSellableAreaControllers.values) {
        controller.dispose();
      }
      _nonSellableNameControllers.clear();
      _nonSellableAreaControllers.clear();
      
      setState(() {
        if (nonSellableAreas.isNotEmpty) {
          _nonSellableAreas = nonSellableAreas.map((area) => <String, String>{
            'name': (area['name'] ?? '').toString(),
            'area': _formatDecimal(area['area'] ?? 0.0),
          }).toList();
        } else {
          // Keep at least one empty row
          _nonSellableAreas = [{'name': '', 'area': '0.00'}];
        }
        
        // Create new controllers
        print('Creating controllers for ${_nonSellableAreas.length} non-sellable areas');
        for (int i = 0; i < _nonSellableAreas.length; i++) {
          print('  Creating controller $i: name="${_nonSellableAreas[i]['name']}", area="${_nonSellableAreas[i]['area']}"');
          _nonSellableNameControllers[i] = TextEditingController(text: _nonSellableAreas[i]['name'] ?? '');
          final areaValue = _nonSellableAreas[i]['area'] ?? '0.00';
          final areaNum = double.tryParse(areaValue.toString().replaceAll(',', '')) ?? 0.0;
          _nonSellableAreaControllers[i] = TextEditingController(text: areaNum == 0.0 ? '' : areaValue.toString());
        }
        print('Created ${_nonSellableNameControllers.length} name controllers and ${_nonSellableAreaControllers.length} area controllers');
      });

      // Load partners
      final partners = await _supabase
          .from('partners')
          .select()
          .eq('project_id', widget.projectId!);
      
      // Dispose old controllers first
      for (var controller in _partnerNameControllers.values) {
        controller.dispose();
      }
      for (var controller in _partnerAmountControllers.values) {
        controller.dispose();
      }
      _partnerNameControllers.clear();
      _partnerAmountControllers.clear();
      
      setState(() {
        if (partners.isNotEmpty) {
          _partners = partners.map((partner) => {
            'name': partner['name'] ?? '',
            'amount': _formatDecimal(partner['amount'] ?? 0.0),
          }).toList();
        } else {
          // Keep at least one empty row
          _partners = [{'name': '', 'amount': '0.00'}];
        }
        
        // Create new controllers
        for (int i = 0; i < _partners.length; i++) {
          _partnerNameControllers[i] = TextEditingController(text: _partners[i]['name'] ?? '');
          final partnerAmount = _partners[i]['amount'] ?? '0.00';
          final partnerAmountNum = double.tryParse(partnerAmount.toString().replaceAll(',', '')) ?? 0.0;
          _partnerAmountControllers[i] = TextEditingController(text: partnerAmountNum == 0.0 ? '' : partnerAmount.toString());
        }
      });

      // Load expenses
      final expenses = await _supabase
          .from('expenses')
          .select()
          .eq('project_id', widget.projectId!);
      
      // Dispose old controllers first
      for (var controller in _expenseItemControllers.values) {
        controller.dispose();
      }
      for (var controller in _expenseAmountControllers.values) {
        controller.dispose();
      }
      _expenseItemControllers.clear();
      _expenseAmountControllers.clear();
      
      setState(() {
        if (expenses.isNotEmpty) {
          _expenses = expenses.map((expense) => {
            'item': expense['item'] ?? '',
            'amount': _formatDecimal(expense['amount'] ?? 0.0),
            // Map database category back to UI label
            'category': _mapExpenseCategoryFromDatabase(expense['category'] ?? ''),
          }).toList();
          
          // Ensure the first row has the default values
          if (_expenses.isNotEmpty) {
            _expenses[0] = {
              'item': 'Total Plot Purchasing Cost',
              'amount': _expenses[0]['amount'] ?? '0.00',
              'category': 'Land Cost',
            };
          }
        } else {
          // Keep at least one empty row with default first row
          _expenses = [
            {'item': 'Total Plot Purchasing Cost', 'amount': '0.00', 'category': 'Land Cost'},
            {'item': '', 'amount': '0.00', 'category': ''},
          ];
        }
        
        // Create new controllers
        for (int i = 0; i < _expenses.length; i++) {
          _expenseItemControllers[i] = TextEditingController(text: _expenses[i]['item'] ?? '');
          final expenseAmount = _expenses[i]['amount'] ?? '0.00';
          final expenseAmountNum = double.tryParse(expenseAmount.toString().replaceAll(',', '')) ?? 0.0;
          _expenseAmountControllers[i] = TextEditingController(text: expenseAmountNum == 0.0 ? '' : expenseAmount.toString());
        }
      });

      // Load layouts and plots
      // Ensure deterministic ordering based on user entry:
      // - Layouts ordered by created_at
      // - Plots within each layout ordered by created_at
      final layouts = await _supabase
          .from('layouts')
          .select()
          .eq('project_id', widget.projectId!)
          .order('created_at', ascending: true);
      
      final layoutsData = <Map<String, dynamic>>[];
      
      if (layouts.isNotEmpty) {
        for (var layout in layouts) {
          final layoutId = layout['id'];
          final plots = await _supabase
              .from('plots')
              .select()
              .eq('layout_id', layoutId)
              .order('created_at', ascending: true);
          
          final plotsData = <Map<String, dynamic>>[];
          for (var plot in plots) {
            // Load plot partners
            final plotPartners = await _supabase
                .from('plot_partners')
                .select()
                .eq('plot_id', plot['id']);
            
            plotsData.add({
              'plotNumber': (plot['plot_number'] ?? '').toString(),
              'area': _formatDecimal(plot['area'] ?? 0.0),
              'purchaseRate': _formatDecimal(plot['all_in_cost_per_sqft'] ?? 0.0),
              'totalPlotCost': _formatDecimal(plot['total_plot_cost'] ?? 0.0),
              'status': (plot['status'] ?? 'available').toString(),
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
      
      // Dispose old layout and plot controllers first
      for (var controller in _layoutNameControllers.values) {
        controller.dispose();
      }
      for (var controller in _plotNumberControllers.values) {
        controller.dispose();
      }
      for (var controller in _plotAreaControllers.values) {
        controller.dispose();
      }
      for (var controller in _plotPurchaseRateControllers.values) {
        controller.dispose();
      }
      _layoutNameControllers.clear();
      _plotNumberControllers.clear();
      _plotAreaControllers.clear();
      _plotPurchaseRateControllers.clear();
      _plotPartners.clear();
      
      setState(() {
        _layouts = layoutsData;
        print('Loaded ${_layouts.length} layouts from database');
        // Update numberOfLayouts controller to match loaded layouts
        if (_layouts.isNotEmpty) {
          _numberOfLayoutsController.text = _layouts.length.toString();
          _isCreateTableEnabled = true;
        } else {
          _numberOfLayoutsController.text = '0';
          _isCreateTableEnabled = false;
        }
        // Initialize layout controllers with layout name from database
        for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
          final layoutName = _layouts[layoutIndex]['name'] ?? '';
          _layoutNameControllers[layoutIndex] = TextEditingController(text: layoutName);
          
          // Convert plots to proper type List<Map<String, dynamic>>
          final plotsData = _layouts[layoutIndex]['plots'];
          List<Map<String, dynamic>> plots;
          if (plotsData is List) {
            plots = plotsData.map((p) {
              if (p is Map<String, dynamic>) {
                return p;
              } else if (p is Map) {
                return Map<String, dynamic>.from(p);
              } else {
                return <String, dynamic>{};
              }
            }).toList();
          } else {
            plots = [];
          }
          
          print('Layout ${layoutIndex + 1}: ${layoutName}, ${plots.length} plots');
          
          // Ensure each layout has at least one default plot
          if (plots.isEmpty) {
            plots = [{
              'plotNumber': '',
              'area': '0.00',
              'purchaseRate': '0.00',
              'totalPlotCost': '0.00',
              'partner': '',
              'partners': [],
            }];
          }
          
          // Update the layout with properly typed plots
          _layouts[layoutIndex]['plots'] = plots;
          
          for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
            final key = '${layoutIndex}_$plotIndex';
            final plot = plots[plotIndex];
            _plotNumberControllers[key] = TextEditingController(text: (plot['plotNumber'] ?? '').toString());
            final plotArea = plot['area'] ?? '0.00';
            final plotAreaNum = double.tryParse(plotArea.toString().replaceAll(',', '')) ?? 0.0;
            _plotAreaControllers[key] = TextEditingController(text: plotAreaNum == 0.0 ? '' : plotArea.toString());
            final plotPurchaseRate = plot['purchaseRate'] ?? '0.00';
            final plotPurchaseRateNum = double.tryParse(plotPurchaseRate.toString().replaceAll(',', '')) ?? 0.0;
            _plotPurchaseRateControllers[key] = TextEditingController(text: plotPurchaseRateNum == 0.0 ? '' : plotPurchaseRate.toString());
            _plotPartners[key] = List<String>.from((plot['partners'] ?? []).map((p) => p.toString()));
          }
        }
      });

      // Load project managers
      final projectManagers = await _supabase
          .from('project_managers')
          .select()
          .eq('project_id', widget.projectId!);
      
      print('_loadProjectData: Loaded ${projectManagers.length} project managers from database');
      for (var pm in projectManagers) {
        print('  Manager: id=${pm['id']}, name=${pm['name']}, compensation_type=${pm['compensation_type']}, earning_type=${pm['earning_type']}, percentage=${pm['percentage']}, fixed_fee=${pm['fixed_fee']}, monthly_fee=${pm['monthly_fee']}, months=${pm['months']}');
      }
      
      // Always clear old controllers and data before reloading
      // This ensures UI state matches database state
      for (var controller in _projectManagerNameControllers.values) {
        controller.dispose();
      }
      for (var controller in _projectManagerPercentageControllers.values) {
        controller.dispose();
      }
      for (var controller in _projectManagerFixedFeeControllers.values) {
        controller.dispose();
      }
      for (var controller in _projectManagerMonthlyFeeControllers.values) {
        controller.dispose();
      }
      for (var controller in _projectManagerMonthsControllers.values) {
        controller.dispose();
      }
      _projectManagerNameControllers.clear();
      _projectManagerPercentageControllers.clear();
      _projectManagerFixedFeeControllers.clear();
      _projectManagerMonthlyFeeControllers.clear();
      _projectManagerMonthsControllers.clear();
      _projectManagerCompensation.clear();
      _projectManagerEarningType.clear();
      _projectManagerPercentage.clear();
      _projectManagerFixedFee.clear();
      _projectManagerMonthlyFee.clear();
      _projectManagerMonths.clear();
      _projectManagerSelectedBlocks.clear();
      
      setState(() {
        if (projectManagers.isNotEmpty) {
          _projectManagers = projectManagers.map((manager) {
            // Map earning type correctly from the start
            final dbEarningType = (manager['earning_type'] ?? '').toString();
            final compensationType = (manager['compensation_type'] ?? '').toString();
            String mappedEarningType = dbEarningType;
            if (compensationType == 'Percentage Bonus') {
              final lowerEarningType = dbEarningType.toLowerCase();
              if (lowerEarningType == 'profit per plot') {
                mappedEarningType = '% of Profit on Each Sold Plot';
              } else if (lowerEarningType == 'selling price per plot' || lowerEarningType == '% of selling price per plot') {
                mappedEarningType = '% of Selling Price per Plot';
              } else if (lowerEarningType == 'lump sum' || lowerEarningType == '% of total project profit') {
                mappedEarningType = '% of Total Project Profit';
              } else if (lowerEarningType == 'per plot') {
                mappedEarningType = '% of Profit on Each Sold Plot';
              }
            }
            return <String, dynamic>{
              'id': manager['id'],
              'name': (manager['name'] ?? '').toString(),
              'compensation': (manager['compensation_type'] ?? '').toString(),
              'earningType': mappedEarningType,
            };
          }).toList();
        } else {
          // Keep at least one empty row
          _projectManagers = [<String, dynamic>{'name': '', 'compensation': '', 'earningType': ''}];
        }
          
        // Create new controllers and maps
        for (int i = 0; i < _projectManagers.length; i++) {
          if (i < projectManagers.length) {
            final manager = projectManagers[i];
            _projectManagerNameControllers[i] = TextEditingController(text: (manager['name'] ?? '').toString());
            _projectManagerCompensation[i] = (manager['compensation_type'] ?? '').toString();
            // Use the already-mapped earning type from _projectManagers
            _projectManagerEarningType[i] = _projectManagers[i]['earningType'] as String? ?? '';
            _projectManagerPercentage[i] = manager['percentage'] != null ? manager['percentage'].toString() : '';
            _projectManagerFixedFee[i] = manager['fixed_fee'] != null ? _formatDecimal(manager['fixed_fee']) : '';
            _projectManagerMonthlyFee[i] = manager['monthly_fee'] != null ? _formatDecimal(manager['monthly_fee']) : '';
            _projectManagerMonths[i] = manager['months'] != null ? manager['months'].toString() : '';
          } else {
            // Initialize empty row
            _projectManagerNameControllers[i] = TextEditingController();
            _projectManagerCompensation[i] = '';
            _projectManagerEarningType[i] = '';
            _projectManagerPercentage[i] = '';
            _projectManagerFixedFee[i] = '';
            _projectManagerMonthlyFee[i] = '';
            _projectManagerMonths[i] = '';
          }
          
          _projectManagerPercentageControllers[i] = TextEditingController(text: _projectManagerPercentage[i] ?? '');
          _projectManagerFixedFeeControllers[i] = TextEditingController(text: _projectManagerFixedFee[i] ?? '');
          _projectManagerMonthlyFeeControllers[i] = TextEditingController(text: _projectManagerMonthlyFee[i] ?? '');
          _projectManagerMonthsControllers[i] = TextEditingController(text: _projectManagerMonths[i] ?? '');
        }
      });
      
      // Load selected blocks for project managers (outside setState since it's async)
      final loadedManagerBlocks = <int, List<String>>{};
      for (int i = 0; i < projectManagers.length; i++) {
        final manager = projectManagers[i];
        final managerId = manager['id'];
        
        // Load block associations
        final blockAssociations = await _supabase
            .from('project_manager_blocks')
            .select('plot_id')
            .eq('project_manager_id', managerId);
        
        if (blockAssociations.isNotEmpty) {
          final plotIds = blockAssociations.map((b) => b['plot_id']).toList();
          
          // Get plot details - query each plot individually if needed
          final plots = <Map<String, dynamic>>[];
          for (var plotId in plotIds) {
            final plotResult = await _supabase
                .from('plots')
                .select('id, plot_number, layout_id')
                .eq('id', plotId);
            if (plotResult.isNotEmpty) {
              plots.addAll(plotResult);
            }
          }
          
          // Get layout details
          final layoutIds = plots.map((p) => p['layout_id']).toSet().toList();
          final layouts = <Map<String, dynamic>>[];
          for (var layoutId in layoutIds) {
            final layoutResult = await _supabase
                .from('layouts')
                .select('id, name')
                .eq('id', layoutId);
            if (layoutResult.isNotEmpty) {
              layouts.addAll(layoutResult);
            }
          }
          
          final layoutMap = <String, String>{};
          for (var layout in layouts) {
            layoutMap[layout['id']] = (layout['name'] ?? '').toString();
          }
          
          // Reconstruct block strings
          final selectedBlocks = <String>[];
          for (var plot in plots) {
            final layoutId = plot['layout_id'];
            final layoutName = layoutMap[layoutId] ?? '';
            final plotNumber = (plot['plot_number'] ?? '').toString();
            if (layoutName.isNotEmpty && plotNumber.isNotEmpty) {
              selectedBlocks.add('$layoutName - $plotNumber');
            }
          }
          
          loadedManagerBlocks[i] = selectedBlocks;
        }
      }
      
      // Update state once with all loaded blocks
      if (mounted) {
        setState(() {
          loadedManagerBlocks.forEach((index, blocks) {
            print('Loading blocks for manager $index: $blocks (length: ${blocks.length})');
            _projectManagerSelectedBlocks[index] = List<String>.from(blocks);
            print('Stored blocks for manager $index: ${_projectManagerSelectedBlocks[index]}');
          });
        });
        print('After setState, _projectManagerSelectedBlocks keys: ${_projectManagerSelectedBlocks.keys.toList()}');
      }

      // Load agents
      final agents = await _supabase
          .from('agents')
          .select()
          .eq('project_id', widget.projectId!);
      
      print('_loadProjectData: Loaded ${agents.length} agents from database');
      for (var agent in agents) {
        print('  Agent: id=${agent['id']}, name=${agent['name']}, compensation_type=${agent['compensation_type']}, earning_type=${agent['earning_type']}, percentage=${agent['percentage']}, fixed_fee=${agent['fixed_fee']}, monthly_fee=${agent['monthly_fee']}, months=${agent['months']}, per_sqft_fee=${agent['per_sqft_fee']}');
      }
      
      // Always clear old controllers and data before reloading
      // This ensures UI state matches database state
      for (var controller in _agentNameControllers.values) {
        controller.dispose();
      }
      for (var controller in _agentPercentageControllers.values) {
        controller.dispose();
      }
      for (var controller in _agentFixedFeeControllers.values) {
        controller.dispose();
      }
      for (var controller in _agentMonthlyFeeControllers.values) {
        controller.dispose();
      }
      for (var controller in _agentMonthsControllers.values) {
        controller.dispose();
      }
      for (var controller in _agentPerSqftFeeControllers.values) {
        controller.dispose();
      }
      _agentNameControllers.clear();
      _agentPercentageControllers.clear();
      _agentFixedFeeControllers.clear();
      _agentMonthlyFeeControllers.clear();
      _agentMonthsControllers.clear();
      _agentPerSqftFeeControllers.clear();
      _agentCompensation.clear();
      _agentEarningType.clear();
      _agentPercentage.clear();
      _agentFixedFee.clear();
      _agentMonthlyFee.clear();
      _agentMonths.clear();
      _agentPerSqftFee.clear();
      _agentSelectedBlocks.clear();
      
      setState(() {
        if (agents.isNotEmpty) {
          _agents = agents.map((agent) {
            // Map earning type correctly from the start
            final dbEarningType = (agent['earning_type'] ?? '').toString();
            final compensationType = (agent['compensation_type'] ?? '').toString();
            String mappedEarningType = dbEarningType;
            if (compensationType == 'Percentage Bonus') {
              final lowerEarningType = dbEarningType.toLowerCase();
              if (lowerEarningType == 'profit per plot') {
                mappedEarningType = '% of Profit on Each Sold Plot';
              } else if (lowerEarningType == 'selling price per plot' || lowerEarningType == '% of selling price per plot') {
                mappedEarningType = '% of Selling Price per Plot';
              } else if (lowerEarningType == 'lump sum' || lowerEarningType == '% of total project profit') {
                mappedEarningType = '% of Total Project Profit';
              } else if (lowerEarningType == 'per plot') {
                mappedEarningType = '% of Profit on Each Sold Plot';
              }
            }
            return <String, dynamic>{
              'id': agent['id'],
              'name': (agent['name'] ?? '').toString(),
              'compensation': (agent['compensation_type'] ?? '').toString(),
              'earningType': mappedEarningType,
            };
          }).toList();
        } else {
          // Keep at least one empty row
          _agents = [<String, dynamic>{'name': '', 'compensation': '', 'earningType': ''}];
        }
          
        // Create new controllers and maps
        for (int i = 0; i < _agents.length; i++) {
          if (i < agents.length) {
            final agent = agents[i];
            _agentNameControllers[i] = TextEditingController(text: (agent['name'] ?? '').toString());
            _agentCompensation[i] = (agent['compensation_type'] ?? '').toString();
            // Use the already-mapped earning type from _agents
            _agentEarningType[i] = _agents[i]['earningType'] as String? ?? '';
            _agentPercentage[i] = agent['percentage'] != null ? agent['percentage'].toString() : '';
            _agentFixedFee[i] = agent['fixed_fee'] != null ? _formatDecimal(agent['fixed_fee']) : '';
            _agentMonthlyFee[i] = agent['monthly_fee'] != null ? _formatDecimal(agent['monthly_fee']) : '';
            _agentMonths[i] = agent['months'] != null ? agent['months'].toString() : '';
            _agentPerSqftFee[i] = agent['per_sqft_fee'] != null ? _formatDecimal(agent['per_sqft_fee']) : '';
          } else {
            // Initialize empty row
            _agentNameControllers[i] = TextEditingController();
            _agentCompensation[i] = '';
            _agentEarningType[i] = '';
            _agentPercentage[i] = '';
            _agentFixedFee[i] = '';
            _agentMonthlyFee[i] = '';
            _agentMonths[i] = '';
            _agentPerSqftFee[i] = '';
          }
          
          _agentPercentageControllers[i] = TextEditingController(text: _agentPercentage[i] ?? '');
          _agentFixedFeeControllers[i] = TextEditingController(text: _agentFixedFee[i] ?? '');
          _agentMonthlyFeeControllers[i] = TextEditingController(text: _agentMonthlyFee[i] ?? '');
          _agentMonthsControllers[i] = TextEditingController(text: _agentMonths[i] ?? '');
          _agentPerSqftFeeControllers[i] = TextEditingController(text: _agentPerSqftFee[i] ?? '');
        }
      });
      
      // Load selected blocks for agents (outside setState since it's async)
      final loadedAgentBlocks = <int, List<String>>{};
      for (int i = 0; i < agents.length; i++) {
        final agent = agents[i];
        final agentId = agent['id'];
        
        // Load block associations
        final blockAssociations = await _supabase
            .from('agent_blocks')
            .select('plot_id')
            .eq('agent_id', agentId);
        
        if (blockAssociations.isNotEmpty) {
          final plotIds = blockAssociations.map((b) => b['plot_id']).toList();
          
          // Get plot details - query each plot individually if needed
          final plots = <Map<String, dynamic>>[];
          for (var plotId in plotIds) {
            final plotResult = await _supabase
                .from('plots')
                .select('id, plot_number, layout_id')
                .eq('id', plotId);
            if (plotResult.isNotEmpty) {
              plots.addAll(plotResult);
            }
          }
          
          // Get layout details
          final layoutIds = plots.map((p) => p['layout_id']).toSet().toList();
          final layouts = <Map<String, dynamic>>[];
          for (var layoutId in layoutIds) {
            final layoutResult = await _supabase
                .from('layouts')
                .select('id, name')
                .eq('id', layoutId);
            if (layoutResult.isNotEmpty) {
              layouts.addAll(layoutResult);
            }
          }
          
          final layoutMap = <String, String>{};
          for (var layout in layouts) {
            layoutMap[layout['id']] = (layout['name'] ?? '').toString();
          }
          
          // Reconstruct block strings
          final selectedBlocks = <String>[];
          for (var plot in plots) {
            final layoutId = plot['layout_id'];
            final layoutName = layoutMap[layoutId] ?? '';
            final plotNumber = (plot['plot_number'] ?? '').toString();
            if (layoutName.isNotEmpty && plotNumber.isNotEmpty) {
              selectedBlocks.add('$layoutName - $plotNumber');
            }
          }
          
          loadedAgentBlocks[i] = selectedBlocks;
        }
      }
      
      // Update state once with all loaded blocks
      if (mounted) {
        setState(() {
          loadedAgentBlocks.forEach((index, blocks) {
            print('Loading blocks for agent $index: $blocks (length: ${blocks.length})');
            _agentSelectedBlocks[index] = List<String>.from(blocks);
            print('Stored blocks for agent $index: ${_agentSelectedBlocks[index]}');
          });
        });
        print('After setState, _agentSelectedBlocks keys: ${_agentSelectedBlocks.keys.toList()}');
      }
      
      print('_loadProjectData: Successfully loaded all project data');
      print('  - Non-sellable areas: ${_nonSellableAreas.length}');
      print('  - Partners: ${_partners.length}');
      print('  - Expenses: ${_expenses.length}');
      print('  - Layouts: ${_layouts.length}');
      print('  - Project managers: ${_projectManagers.length}');
      print('  - Agents: ${_agents.length}');
    } catch (e, stackTrace) {
      print('Error loading project data: $e');
      print('Stack trace: $stackTrace');
    } finally {
      // Always reset the loading flag, even if there was an error
      _isLoadingData = false;
      print('_loadProjectData: Finished loading, _isLoadingData set to false');
    }
  }

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

  /// Map UI expense category labels to database values enforced by expenses_category_check.
  /// UI uses 'Land Cost' while DB expects 'Land Purchase Cost'.
  String _mapExpenseCategoryForDatabase(String category) {
    final trimmed = category.trim();
    if (trimmed == 'Land Cost') {
      return 'Land Purchase Cost';
    }
    return trimmed;
  }

  /// Map database expense category back to UI label for display.
  String _mapExpenseCategoryFromDatabase(String category) {
    final trimmed = category.trim();
    if (trimmed == 'Land Purchase Cost') {
      return 'Land Cost';
    }
    return trimmed;
  }

  /// Convert date from database format (YYYY-MM-DD or null) to UI format (DD/MM/YYYY)
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
      // Convert to DD/MM/YYYY format
      return '$day/$month/$year';
    }
    
    // If already in DD/MM/YYYY format, return as is
    final ddmmyyyyPattern = RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$');
    if (ddmmyyyyPattern.hasMatch(dateStr)) {
      return dateStr;
    }
    
    // Return empty string if format is not recognized
    return '';
  }

  void _notifyErrorState() {
    // Notify if there are any validation errors (partners, expenses, project managers, or agents)
    widget.onErrorStateChanged?.call(_hasPartnerValidationErrors || 
                                     _hasExpenseValidationErrors || 
                                     _hasProjectManagerValidationErrors || 
                                     _hasAgentValidationErrors);
  }

  void _onDataChanged() {
    // Don't save if we're currently loading data (prevents overwriting with empty values)
    if (_isLoadingData) {
      return;
    }
    
    // Save to local storage immediately (for better data persistence)
    _saveLayoutsData();
    _saveAgentsData();
    if (_projectNameController.text.isNotEmpty) {
      LayoutStorageService.saveProjectName(_projectNameController.text);
    }
    
    // Debounce both error state and save status callbacks to prevent rebuilds on every keystroke
    _dataChangedDebounceTimer?.cancel();
    _dataChangedDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _notifyErrorState();
      
      // Update status to saving (only after user stops typing)
      widget.onSaveStatusChanged?.call(ProjectSaveStatusType.saving);
      
      // Save to Supabase if project ID is available
      if (widget.projectId != null && widget.projectId!.isNotEmpty) {
        _saveToSupabase();
      }
      
      // Cancel existing timer
      _saveStatusTimer?.cancel();
      
      // Set timer to change to saved after 1 second of no changes (reduced for faster feedback)
      _saveStatusTimer = Timer(const Duration(seconds: 1), () {
        widget.onSaveStatusChanged?.call(ProjectSaveStatusType.saved);
      });
    });
  }

  Future<void> _saveToSupabase() async {
    if (widget.projectId == null || widget.projectId!.isEmpty) return;
    
    // Don't save if we're currently loading data (additional safety check)
    if (_isLoadingData) {
      print('_saveToSupabase: Skipping save because _isLoadingData is true');
      return;
    }

    try {
      // Prepare layouts data with plot partners
      final layoutsData = <Map<String, dynamic>>[];
      for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
        final layout = _layouts[layoutIndex];
        final layoutNameController = _layoutNameControllers[layoutIndex];
        final layoutName = layoutNameController?.text ?? layout['name'] ?? 'Layout ${layoutIndex + 1}';
        
        final plots = layout['plots'] as List<dynamic>? ?? [];
        final plotsData = <Map<String, dynamic>>[];
        
        for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
          final key = '${layoutIndex}_$plotIndex';
          final plotNumberController = _plotNumberControllers[key];
          final plotAreaController = _plotAreaControllers[key];
          
          final plotNumber = plotNumberController?.text.trim() ?? '';
          if (plotNumber.isEmpty) continue;
          
          // Get plot partners
          final plotPartners = _plotPartners[key] as List<String>? ?? [];
          
          // Calculate All-in Cost (same for all plots) = Total Expenses / Approved Selling Area
          // This is what should be saved as all_in_cost_per_sqft
          final allInCost = _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;
          
          // Calculate Total Plot Cost = Area * All-in Cost
          final area = double.tryParse(plotAreaController?.text.replaceAll(',', '').replaceAll(' ', '').trim() ?? '0') ?? 0.0;
          final totalPlotCost = area * allInCost;
          
          // Debug logging for first plot only
          if (plotIndex == 0 && layoutIndex == 0) {
            print('All-in Cost calculation: _totalExpenses=$_totalExpenses, _approvedSellingArea=$_approvedSellingArea, allInCost=$allInCost');
          }
          
          print('DEBUG: Saving plot ${plotNumber}: partners=$plotPartners (${plotPartners.length} partners)');
          
          plotsData.add({
            'plotNumber': plotNumber,
            'area': plotAreaController?.text.replaceAll(',', '') ?? '0.00',
            'purchaseRate': allInCost.toStringAsFixed(2), // Save calculated all-in cost
            'totalPlotCost': totalPlotCost.toStringAsFixed(2), // Save calculated total plot cost
            'partners': plotPartners,
            'status': plots[plotIndex]['status']?.toString() ?? 'available',
            'salePrice': plots[plotIndex]['salePrice']?.toString(),
            'buyerName': plots[plotIndex]['buyerName']?.toString(),
            'saleDate': plots[plotIndex]['saleDate']?.toString(),
            'agent': plots[plotIndex]['agent']?.toString(),
          });
        }
        
        // Only add layout to save list if it has at least one plot with data
        if (plotsData.isNotEmpty) {
          layoutsData.add({
            'name': layoutName,
            'plots': plotsData,
          });
        } else {
          print('DEBUG: Skipping layout "$layoutName" - no plots with data');
        }
      }

      // Prepare project managers data
      final projectManagersData = <Map<String, dynamic>>[];
      for (int i = 0; i < _projectManagers.length; i++) {
        final manager = _projectManagers[i];
        final name = _projectManagerNameControllers[i]?.text.trim() ?? '';
        if (name.isEmpty) continue;
        
        final compensation = _projectManagerCompensation[i] ?? '';
        final earningType = _projectManagerEarningType[i] ?? '';
        final percentage = _projectManagerPercentageControllers[i]?.text.replaceAll(',', '') ?? _projectManagerPercentage[i] ?? '';
        final fixedFee = _projectManagerFixedFeeControllers[i]?.text.replaceAll(',', '') ?? _projectManagerFixedFee[i] ?? '';
        final monthlyFee = _projectManagerMonthlyFeeControllers[i]?.text.replaceAll(',', '') ?? _projectManagerMonthlyFee[i] ?? '';
        final months = _projectManagerMonthsControllers[i]?.text ?? _projectManagerMonths[i] ?? '';
        
        print('Saving Project Manager $i: name=$name, compensation=$compensation, earningType=$earningType, percentage=$percentage, fixedFee=$fixedFee, monthlyFee=$monthlyFee, months=$months');
        
        projectManagersData.add({
          'id': manager['id'],
          'name': name,
          'compensation': compensation,
          'earningType': earningType,
          'percentage': percentage,
          'fixedFee': fixedFee,
          'monthlyFee': monthlyFee,
          'months': months,
          'selectedBlocks': _projectManagerSelectedBlocks[i] ?? [],
        });
      }

      // Prepare agents data
      final agentsData = <Map<String, dynamic>>[];
      for (int i = 0; i < _agents.length; i++) {
        final agent = _agents[i];
        final name = _agentNameControllers[i]?.text.trim() ?? '';
        if (name.isEmpty) continue;
        
        // Get compensation from map first, then fall back to agents data structure
        final compensation = _agentCompensation[i] ?? _agents[i]['compensation']?.toString() ?? '';
        final earningType = _agentEarningType[i] ?? _agents[i]['earningType']?.toString() ?? '';
        final percentage = _agentPercentageControllers[i]?.text.replaceAll(',', '') ?? _agentPercentage[i] ?? '';
        final fixedFee = _agentFixedFeeControllers[i]?.text.replaceAll(',', '') ?? _agentFixedFee[i] ?? '';
        final monthlyFee = _agentMonthlyFeeControllers[i]?.text.replaceAll(',', '') ?? _agentMonthlyFee[i] ?? '';
        final months = _agentMonthsControllers[i]?.text ?? _agentMonths[i] ?? '';
        final perSqftFee = _agentPerSqftFeeControllers[i]?.text.replaceAll(',', '') ?? _agentPerSqftFee[i] ?? '';
        
        print('Saving Agent $i: name=$name, compensation=$compensation (from map: ${_agentCompensation[i]}, from data: ${_agents[i]['compensation']}), earningType=$earningType, percentage=$percentage, fixedFee=$fixedFee, monthlyFee=$monthlyFee, months=$months, perSqftFee=$perSqftFee');
        
        agentsData.add({
          'id': agent['id'],
          'name': name,
          'compensation': compensation,
          'earningType': earningType,
          'percentage': percentage,
          'fixedFee': fixedFee,
          'monthlyFee': monthlyFee,
          'months': months,
          'perSqftFee': perSqftFee,
          'selectedBlocks': _agentSelectedBlocks[i] ?? [],
        });
      }

      // Prepare non-sellable areas
      final nonSellableAreasData = <Map<String, String>>[];
      print('Preparing non-sellable areas: _nonSellableAreas.length=${_nonSellableAreas.length}, controllers.length=${_nonSellableNameControllers.length}');
      for (int i = 0; i < _nonSellableAreas.length; i++) {
        final nameController = _nonSellableNameControllers[i];
        final areaController = _nonSellableAreaControllers[i];
        // Use controller text if available, otherwise fall back to data structure
        final name = nameController?.text.trim() ?? _nonSellableAreas[i]['name']?.toString().trim() ?? '';
        final area = areaController?.text.replaceAll(',', '').replaceAll(' ', '').trim() ?? _nonSellableAreas[i]['area']?.toString().replaceAll(',', '').replaceAll(' ', '').trim() ?? '0.00';
        print('Non-sellable area $i: name="$name", area="$area", controller exists=${nameController != null}');
        if (name.isNotEmpty) {
          nonSellableAreasData.add({'name': name, 'area': area});
        }
      }
      print('Prepared ${nonSellableAreasData.length} non-sellable areas');

      // Prepare partners data
      final partnersData = <Map<String, dynamic>>[];
      print('Preparing partners: _partners.length=${_partners.length}, controllers.length=${_partnerNameControllers.length}');
      for (int i = 0; i < _partners.length; i++) {
        final nameController = _partnerNameControllers[i];
        final amountController = _partnerAmountControllers[i];
        // Use controller text if available, otherwise fall back to data structure
        final name = nameController?.text.trim() ?? _partners[i]['name']?.toString().trim() ?? '';
        final amount = amountController?.text.replaceAll(',', '').replaceAll(' ', '').trim() ?? _partners[i]['amount']?.toString().replaceAll(',', '').replaceAll(' ', '').trim() ?? '0.00';
        print('Partner $i: name="$name", amount="$amount", controller exists=${nameController != null}');
        if (name.isNotEmpty) {
          partnersData.add({'name': name, 'amount': amount});
        }
      }
      print('Prepared ${partnersData.length} partners');
      
      // Only save partners if we're not loading data
      // This prevents deleting partners when data is still being loaded
      final shouldSavePartners = !_isLoadingData;

      // Prepare expenses data
      final expensesData = <Map<String, dynamic>>[];
      print('Preparing expenses: _expenses.length=${_expenses.length}, controllers.length=${_expenseItemControllers.length}');
      for (int i = 0; i < _expenses.length; i++) {
        final itemController = _expenseItemControllers[i];
        final amountController = _expenseAmountControllers[i];
        // Use controller text if available and non-empty, otherwise fall back to data structure
        final item = itemController?.text.trim() ?? _expenses[i]['item']?.toString().trim() ?? '';
        final controllerAmount = amountController?.text.replaceAll(',', '').replaceAll(' ', '').trim() ?? '';
        final amount = controllerAmount.isNotEmpty ? controllerAmount : (_expenses[i]['amount']?.toString().replaceAll(',', '').replaceAll(' ', '').trim() ?? '0.00');
        final rawCategory = _expenses[i]['category']?.toString().trim() ?? '';
        // Map UI category labels to database enum values (see expenses_category_check)
        final category = _mapExpenseCategoryForDatabase(rawCategory);
        print('Expense $i: item="$item", amount="$amount", category="$category", controller exists=${itemController != null}');
        if (item.isNotEmpty && category.isNotEmpty) {
          expensesData.add({'item': item, 'amount': amount, 'category': category});
        }
      }
      print('Prepared ${expensesData.length} expenses');

      // IMPORTANT: Prevent accidental wiping of tables.
      // ProjectStorageService deletes & re-inserts when a list is provided.
      // So only provide expenses / project managers / agents when we have "ready" controllers AND meaningful rows.
      final canSafelySaveExpenses =
          _expenseItemControllers.length == _expenses.length &&
          _expenseAmountControllers.length == _expenses.length &&
          expensesData.isNotEmpty;

      // Project Managers safety check
      // We check if controllers match the data model length (synchronization check)
      final canSafelySaveProjectManagers =
          _projectManagerNameControllers.length == _projectManagers.length;

      print('Project Managers safety check: controllers.length=${_projectManagerNameControllers.length}, _projectManagers.length=${_projectManagers.length}, canSafelySave=$canSafelySaveProjectManagers, projectManagersData.length=${projectManagersData.length}');

      List<Map<String, dynamic>>? finalProjectManagersData;
      if (canSafelySaveProjectManagers) {
        if (_projectManagers.isEmpty) {
          // Explicitly delete all if user removed them
          finalProjectManagersData = [];
          print('Project Managers: Setting to empty list (user removed all)');
        } else if (projectManagersData.isNotEmpty) {
          // Save valid data
          finalProjectManagersData = projectManagersData;
          print('Project Managers: Will save ${projectManagersData.length} managers');
        } else {
          print('Project Managers: Data is empty but _projectManagers is not empty, passing null to avoid deletion');
        }
        // If _projectManagers is NOT empty but projectManagersData IS empty (e.g. all filtered out),
        // we pass null to avoid accidental deletion of existing data.
      } else {
        print('Project Managers: Safety check FAILED - controllers and data model out of sync, NOT saving');
      }

      // Agents safety check
      final canSafelySaveAgents =
          _agentNameControllers.length == _agents.length;

      print('Agents safety check: controllers.length=${_agentNameControllers.length}, _agents.length=${_agents.length}, canSafelySave=$canSafelySaveAgents, agentsData.length=${agentsData.length}');

      List<Map<String, dynamic>>? finalAgentsData;
      if (canSafelySaveAgents) {
        if (_agents.isEmpty) {
          // Explicitly delete all if user removed them
          finalAgentsData = [];
          print('Agents: Setting to empty list (user removed all)');
        } else if (agentsData.isNotEmpty) {
          // Save valid data
          finalAgentsData = agentsData;
          print('Agents: Will save ${agentsData.length} agents');
        } else {
          print('Agents: Data is empty but _agents is not empty, passing null to avoid deletion');
        }
        // Same safety logic as project managers
      } else {
        print('Agents: Safety check FAILED - controllers and data model out of sync, NOT saving');
      }

      // Save all data to Supabase
      // Clean the area values by removing commas, spaces, and other formatting
      final totalAreaText = _totalAreaController.text.replaceAll(',', '').replaceAll(' ', '').trim();
      final sellingAreaText = _sellingAreaController.text.replaceAll(',', '').replaceAll(' ', '').trim();
      final estimatedCostText = _estimatedDevelopmentCostController.text.replaceAll(',', '').replaceAll(' ', '').trim();
      
      print('Saving project data: projectId=${widget.projectId}');
      print('  totalArea: "${_totalAreaController.text}" -> cleaned: "$totalAreaText"');
      print('  sellingArea: "${_sellingAreaController.text}" -> cleaned: "$sellingAreaText"');
      print('  nonSellableAreas=${nonSellableAreasData.length}, partners=${partnersData.length}, expenses=${expensesData.length}, layouts=${layoutsData.length}, projectManagers=${projectManagersData.length}, agents=${agentsData.length}');
      
      await ProjectStorageService.saveProjectData(
        projectId: widget.projectId!,
        projectName: _projectNameController.text.trim(),
        totalArea: totalAreaText.isEmpty ? '' : totalAreaText,
        sellingArea: sellingAreaText.isEmpty ? '' : sellingAreaText,
        estimatedDevelopmentCost: estimatedCostText.isEmpty ? '' : estimatedCostText,
        nonSellableAreas: nonSellableAreasData,
        partners: shouldSavePartners ? partnersData : null, // Only pass partners if we should save them
        expenses: canSafelySaveExpenses ? expensesData : null,
        layouts: layoutsData,
        projectManagers: finalProjectManagersData,
        agents: finalAgentsData,
      );
      print('Successfully saved project data to Supabase');
    } catch (e, stackTrace) {
      print('Error saving to Supabase: $e');
      print('Stack trace: $stackTrace');
      // Don't show error to user, just log it
    }
  }

  void _saveLayoutsData() {
    // Save layout data to local storage
    LayoutStorageService.saveLayoutsData(
      _layouts,
      _layoutNameControllers,
      _plotNumberControllers,
      _plotAreaControllers,
      _plotPurchaseRateControllers,
    );
  }

  void _saveAgentsData() {
    // Save agents data to local storage
    LayoutStorageService.saveAgentsData(_agents);
  }

  @override
  void dispose() {
    // If there's a pending debounce, cancel it. We avoid forcing an async Supabase save from dispose()
    // because it can race with controller disposal and lead to incomplete/unsafe saves.
    if (_dataChangedDebounceTimer?.isActive ?? false) {
      _dataChangedDebounceTimer?.cancel();
      _notifyErrorState();
      widget.onSaveStatusChanged?.call(ProjectSaveStatusType.saving);
      _saveLayoutsData();
      _saveAgentsData();
    }
    
    _saveStatusTimer?.cancel();
    _dataChangedDebounceTimer?.cancel();
    _projectNameController.dispose();
    _totalAreaController.dispose();
    _sellingAreaController.dispose();
    _projectNameFocusNode.dispose();
    _totalAreaFocusNode.dispose();
    _sellingAreaFocusNode.dispose();
    _estimatedDevelopmentCostController.dispose();
    _numberOfLayoutsController.dispose();
    // Dispose all non-sellable name controllers
    for (var controller in _nonSellableNameControllers.values) {
      controller.dispose();
    }
    _nonSellableNameControllers.clear();
    // Dispose all non-sellable area controllers
    for (var controller in _nonSellableAreaControllers.values) {
      controller.dispose();
    }
    _nonSellableAreaControllers.clear();
    // Dispose all partner controllers
    for (var controller in _partnerNameControllers.values) {
      controller.dispose();
    }
    _partnerNameControllers.clear();
    for (var controller in _partnerAmountControllers.values) {
      controller.dispose();
    }
    _partnerAmountControllers.clear();
    // Dispose all expense controllers
    for (var controller in _expenseItemControllers.values) {
      controller.dispose();
    }
    _expenseItemControllers.clear();
    for (var controller in _expenseAmountControllers.values) {
      controller.dispose();
    }
    _expenseAmountControllers.clear();
    // Dispose all layout name controllers
    for (var controller in _layoutNameControllers.values) {
      controller.dispose();
    }
    _layoutNameControllers.clear();
    // Dispose all plot controllers
    for (var controller in _plotNumberControllers.values) {
      controller.dispose();
    }
    _plotNumberControllers.clear();
    for (var controller in _plotAreaControllers.values) {
      controller.dispose();
    }
    _plotAreaControllers.clear();
    _plotPurchaseRateControllers.clear();
    // Dispose all project manager fee controllers and focus nodes
    for (var controller in _projectManagerFixedFeeControllers.values) {
      controller.dispose();
    }
    _projectManagerFixedFeeControllers.clear();
    for (var focusNode in _projectManagerFixedFeeFocusNodes.values) {
      focusNode.dispose();
    }
    _projectManagerFixedFeeFocusNodes.clear();
    for (var controller in _projectManagerMonthlyFeeControllers.values) {
      controller.dispose();
    }
    _projectManagerMonthlyFeeControllers.clear();
    for (var focusNode in _projectManagerMonthlyFeeFocusNodes.values) {
      focusNode.dispose();
    }
    _projectManagerMonthlyFeeFocusNodes.clear();
    // Dispose all agent fee controllers and focus nodes
    for (var controller in _agentFixedFeeControllers.values) {
      controller.dispose();
    }
    _agentFixedFeeControllers.clear();
    for (var focusNode in _agentFixedFeeFocusNodes.values) {
      focusNode.dispose();
    }
    _agentFixedFeeFocusNodes.clear();
    for (var controller in _agentMonthlyFeeControllers.values) {
      controller.dispose();
    }
    _agentMonthlyFeeControllers.clear();
    for (var focusNode in _agentMonthlyFeeFocusNodes.values) {
      focusNode.dispose();
    }
    _agentMonthlyFeeFocusNodes.clear();
    for (var controller in _agentPerSqftFeeControllers.values) {
      controller.dispose();
    }
    _agentPerSqftFeeControllers.clear();
    _agentPerSqftFeeFocusNodes.clear();
    // Dispose all project manager months controllers and focus nodes
    for (var controller in _projectManagerMonthsControllers.values) {
      controller.dispose();
    }
    _projectManagerMonthsControllers.clear();
    for (var focusNode in _projectManagerMonthsFocusNodes.values) {
      focusNode.dispose();
    }
    _projectManagerMonthsFocusNodes.clear();
    // Dispose all project manager percentage controllers and focus nodes
    for (var controller in _projectManagerPercentageControllers.values) {
      controller.dispose();
    }
    _projectManagerPercentageControllers.clear();
    for (var focusNode in _projectManagerPercentageFocusNodes.values) {
      focusNode.dispose();
    }
    _projectManagerPercentageFocusNodes.clear();
    // Dispose all agent months controllers and focus nodes
    for (var controller in _agentMonthsControllers.values) {
      controller.dispose();
    }
    _agentMonthsControllers.clear();
    for (var focusNode in _agentMonthsFocusNodes.values) {
      focusNode.dispose();
    }
    _agentMonthsFocusNodes.clear();
    // Dispose all agent percentage controllers and focus nodes
    for (var controller in _agentPercentageControllers.values) {
      controller.dispose();
    }
    _agentPercentageControllers.clear();
    for (var focusNode in _agentPercentageFocusNodes.values) {
      focusNode.dispose();
    }
    _agentPercentageFocusNodes.clear();
    // Dispose scroll controllers
    _partnersTableScrollController.dispose();
    _expensesTableScrollController.dispose();
    _projectManagersTableScrollController.dispose();
    _agentsTableScrollController.dispose();
    for (var controller in _plotsTableScrollControllers.values) {
      controller.dispose();
    }
    _plotsTableScrollControllers.clear();
    super.dispose();
  }

  // Helper method to build project manager fixed fee field
  Widget _buildProjectManagerFixedFeeField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_projectManagerFixedFeeControllers[index] == null) {
      _projectManagerFixedFeeControllers[index] = TextEditingController();
    }
    if (_projectManagerFixedFeeFocusNodes[index] == null) {
      _projectManagerFixedFeeFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _projectManagerFixedFeeFocusNodes[index]!,
      child: DecimalInputField(
        controller: _projectManagerFixedFeeControllers[index]!,
        focusNode: _projectManagerFixedFeeFocusNodes[index]!,
        hintText: '0.00',
        inputFormatters: [IndianNumberFormatter()],
        onTap: () {
          // Clear '0.00' when field is tapped
          final cleaned = _projectManagerFixedFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
          if (cleaned == '0' || cleaned == '0.00') {
            _projectManagerFixedFeeControllers[index]!.text = '';
            _projectManagerFixedFeeControllers[index]!.selection = TextSelection.collapsed(offset: 0);
          }
        },
        onChanged: (value) {
          // Remove commas for storage (for real-time calculations)
          final rawValue = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          _projectManagerFixedFee[index] = rawValue.isEmpty ? '0' : rawValue;
          _projectManagers[index]['fixedFee'] = rawValue.isEmpty ? '0' : rawValue;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          // Remove commas before formatting
          final cleaned = _projectManagerFixedFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          final formatted = _formatAmount(cleaned);
          _projectManagerFixedFeeControllers[index]!.text = formatted;
          setState(() {
            _projectManagerFixedFee[index] = formatted.replaceAll(',', '');
            _projectManagers[index]['fixedFee'] = formatted.replaceAll(',', '');
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  // Helper method to build project manager monthly fee field
  Widget _buildProjectManagerMonthlyFeeField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_projectManagerMonthlyFeeControllers[index] == null) {
      _projectManagerMonthlyFeeControllers[index] = TextEditingController();
    }
    if (_projectManagerMonthlyFeeFocusNodes[index] == null) {
      _projectManagerMonthlyFeeFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _projectManagerMonthlyFeeFocusNodes[index]!,
      child: DecimalInputField(
        controller: _projectManagerMonthlyFeeControllers[index]!,
        focusNode: _projectManagerMonthlyFeeFocusNodes[index]!,
        hintText: '0.00',
        inputFormatters: [IndianNumberFormatter()],
        onTap: () {
          // Clear '0.00' when field is tapped
          final cleaned = _projectManagerMonthlyFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
          if (cleaned == '0' || cleaned == '0.00') {
            _projectManagerMonthlyFeeControllers[index]!.text = '';
            _projectManagerMonthlyFeeControllers[index]!.selection = TextSelection.collapsed(offset: 0);
          }
        },
        onChanged: (value) {
          // Remove commas for storage (for real-time calculations)
          final rawValue = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          _projectManagerMonthlyFee[index] = rawValue.isEmpty ? '0' : rawValue;
          _projectManagers[index]['monthlyFee'] = rawValue.isEmpty ? '0' : rawValue;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          // Remove commas before formatting
          final cleaned = _projectManagerMonthlyFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          final formatted = _formatAmount(cleaned);
          _projectManagerMonthlyFeeControllers[index]!.text = formatted;
          setState(() {
            _projectManagerMonthlyFee[index] = formatted.replaceAll(',', '');
            _projectManagers[index]['monthlyFee'] = formatted.replaceAll(',', '');
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  // Helper method to build agent fixed fee field
  Widget _buildAgentFixedFeeField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_agentFixedFeeControllers[index] == null) {
      _agentFixedFeeControllers[index] = TextEditingController();
    }
    if (_agentFixedFeeFocusNodes[index] == null) {
      _agentFixedFeeFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _agentFixedFeeFocusNodes[index]!,
      child: DecimalInputField(
        controller: _agentFixedFeeControllers[index]!,
        focusNode: _agentFixedFeeFocusNodes[index]!,
        hintText: '0.00',
        inputFormatters: [IndianNumberFormatter()],
        onTap: () {
          // Clear '0.00' when field is tapped
          final cleaned = _agentFixedFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
          if (cleaned == '0' || cleaned == '0.00') {
            _agentFixedFeeControllers[index]!.text = '';
            _agentFixedFeeControllers[index]!.selection = TextSelection.collapsed(offset: 0);
          }
        },
        onChanged: (value) {
          // Remove commas for storage (for real-time calculations)
          final rawValue = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          _agentFixedFee[index] = rawValue.isEmpty ? '0' : rawValue;
          _agents[index]['fixedFee'] = rawValue.isEmpty ? '0' : rawValue;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          // Remove commas before formatting
          final cleaned = _agentFixedFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          final formatted = _formatAmount(cleaned);
          _agentFixedFeeControllers[index]!.text = formatted;
          setState(() {
            _agentFixedFee[index] = formatted.replaceAll(',', '');
            _agents[index]['fixedFee'] = formatted.replaceAll(',', '');
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  // Helper method to build agent monthly fee field
  Widget _buildAgentMonthlyFeeField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_agentMonthlyFeeControllers[index] == null) {
      _agentMonthlyFeeControllers[index] = TextEditingController();
    }
    if (_agentMonthlyFeeFocusNodes[index] == null) {
      _agentMonthlyFeeFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _agentMonthlyFeeFocusNodes[index]!,
      child: DecimalInputField(
        controller: _agentMonthlyFeeControllers[index]!,
        focusNode: _agentMonthlyFeeFocusNodes[index]!,
        hintText: '0.00',
        inputFormatters: [IndianNumberFormatter()],
        onTap: () {
          // Clear '0.00' when field is tapped
          final cleaned = _agentMonthlyFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
          if (cleaned == '0' || cleaned == '0.00') {
            _agentMonthlyFeeControllers[index]!.text = '';
            _agentMonthlyFeeControllers[index]!.selection = TextSelection.collapsed(offset: 0);
          }
        },
        onChanged: (value) {
          // Remove commas for storage (for real-time calculations)
          final rawValue = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          _agentMonthlyFee[index] = rawValue.isEmpty ? '0' : rawValue;
          _agents[index]['monthlyFee'] = rawValue.isEmpty ? '0' : rawValue;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          // Remove commas before formatting
          final cleaned = _agentMonthlyFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          final formatted = _formatAmount(cleaned);
          _agentMonthlyFeeControllers[index]!.text = formatted;
          setState(() {
            _agentMonthlyFee[index] = formatted.replaceAll(',', '');
            _agents[index]['monthlyFee'] = formatted.replaceAll(',', '');
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  // Helper method to build agent per sqft fee field
  Widget _buildAgentPerSqftFeeField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_agentPerSqftFeeControllers[index] == null) {
      _agentPerSqftFeeControllers[index] = TextEditingController();
    }
    if (_agentPerSqftFeeFocusNodes[index] == null) {
      _agentPerSqftFeeFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _agentPerSqftFeeFocusNodes[index]!,
      child: DecimalInputField(
        controller: _agentPerSqftFeeControllers[index]!,
        focusNode: _agentPerSqftFeeFocusNodes[index]!,
        hintText: '0.00',
        inputFormatters: [IndianNumberFormatter()],
        onTap: () {
          // Clear '0.00' when field is tapped
          final cleaned = _agentPerSqftFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
          if (cleaned == '0' || cleaned == '0.00') {
            _agentPerSqftFeeControllers[index]!.text = '';
            _agentPerSqftFeeControllers[index]!.selection = TextSelection.collapsed(offset: 0);
          }
        },
        onChanged: (value) {
          // Remove commas for storage (for real-time calculations)
          final rawValue = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          _agentPerSqftFee[index] = rawValue.isEmpty ? '0' : rawValue;
          _agents[index]['perSqftFee'] = rawValue.isEmpty ? '0' : rawValue;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          // Remove commas before formatting
          final cleaned = _agentPerSqftFeeControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
          final formatted = _formatAmount(cleaned);
          _agentPerSqftFeeControllers[index]!.text = formatted;
          setState(() {
            _agentPerSqftFee[index] = formatted.replaceAll(',', '');
            _agents[index]['perSqftFee'] = formatted.replaceAll(',', '');
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  // Helper method to build project manager months field
  Widget _buildProjectManagerMonthsField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_projectManagerMonthsControllers[index] == null) {
      final currentMonthsValue = _projectManagerMonths[index] ?? '';
      _projectManagerMonthsControllers[index] = TextEditingController(text: currentMonthsValue);
    }
    if (_projectManagerMonthsFocusNodes[index] == null) {
      _projectManagerMonthsFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _projectManagerMonthsFocusNodes[index]!,
      height: 40,
      child: TextField(
        key: Key('pm_months_$index'),
        controller: _projectManagerMonthsControllers[index],
        focusNode: _projectManagerMonthsFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlignVertical: TextAlignVertical.center,
        inputFormatters: [MonthsInputFormatter()],
        onChanged: (value) {
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          _projectManagerMonths[index] = value;
          _projectManagers[index]['months'] = value;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          setState(() {
            _projectManagerMonths[index] = _projectManagerMonthsControllers[index]!.text;
            _projectManagers[index]['months'] = _projectManagerMonthsControllers[index]!.text;
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        decoration: InputDecoration(
          hintText: 'Months',
          hintStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: const Color(0xFF5D5D5D),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          isDense: true,
        ),
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: Colors.black,
        ),
      ),
    );
  }

  // Helper method to build agent months field
  Widget _buildAgentMonthsField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_agentMonthsControllers[index] == null) {
      final currentMonthsValue = _agentMonths[index] ?? '';
      _agentMonthsControllers[index] = TextEditingController(text: currentMonthsValue);
    }
    if (_agentMonthsFocusNodes[index] == null) {
      _agentMonthsFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _agentMonthsFocusNodes[index]!,
      height: 40,
      child: TextField(
        key: Key('agent_months_$index'),
        controller: _agentMonthsControllers[index],
        focusNode: _agentMonthsFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlignVertical: TextAlignVertical.center,
        inputFormatters: [MonthsInputFormatter()],
        onChanged: (value) {
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          _agentMonths[index] = value;
          _agents[index]['months'] = value;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          setState(() {
            _agentMonths[index] = _agentMonthsControllers[index]!.text;
            _agents[index]['months'] = _agentMonthsControllers[index]!.text;
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        decoration: InputDecoration(
          hintText: 'Months',
          hintStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: const Color(0xFF5D5D5D),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          isDense: true,
        ),
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: Colors.black,
        ),
      ),
    );
  }

  // Helper method to build project manager percentage field
  Widget _buildProjectManagerPercentageField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_projectManagerPercentageControllers[index] == null) {
      final currentPercentageValue = _projectManagerPercentage[index] ?? '0';
      _projectManagerPercentageControllers[index] = TextEditingController(text: currentPercentageValue == '0' ? '' : currentPercentageValue);
    }
    if (_projectManagerPercentageFocusNodes[index] == null) {
      _projectManagerPercentageFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _projectManagerPercentageFocusNodes[index]!,
      height: 40,
      child: TextField(
        key: Key('pm_percentage_$index'),
        controller: _projectManagerPercentageControllers[index],
        focusNode: _projectManagerPercentageFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlignVertical: TextAlignVertical.center,
        textAlign: TextAlign.center,
        inputFormatters: [PercentageInputFormatter()],
        onChanged: (value) {
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          final numValue = value.isEmpty ? '0' : value;
          _projectManagerPercentage[index] = numValue;
          _projectManagers[index]['percentage'] = numValue;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          final numValue = _projectManagerPercentageControllers[index]!.text.isEmpty ? '0' : _projectManagerPercentageControllers[index]!.text;
          setState(() {
            _projectManagerPercentage[index] = numValue;
            _projectManagers[index]['percentage'] = numValue;
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: const Color(0xFF5D5D5D),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          isDense: true,
        ),
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: const Color(0xFF5C5C5C),
        ),
      ),
    );
  }

  // Helper method to build agent percentage field
  Widget _buildAgentPercentageField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_agentPercentageControllers[index] == null) {
      final currentPercentageValue = _agentPercentage[index] ?? '0';
      _agentPercentageControllers[index] = TextEditingController(text: currentPercentageValue == '0' ? '' : currentPercentageValue);
    }
    if (_agentPercentageFocusNodes[index] == null) {
      _agentPercentageFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _agentPercentageFocusNodes[index]!,
      height: 40,
      child: TextField(
        key: Key('agent_percentage_$index'),
        controller: _agentPercentageControllers[index],
        focusNode: _agentPercentageFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlignVertical: TextAlignVertical.center,
        textAlign: TextAlign.center,
        inputFormatters: [PercentageInputFormatter()],
        onChanged: (value) {
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          final numValue = value.isEmpty ? '0' : value;
          _agentPercentage[index] = numValue;
          _agents[index]['percentage'] = numValue;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onEditingComplete instead
        },
        onEditingComplete: () {
          final numValue = _agentPercentageControllers[index]!.text.isEmpty ? '0' : _agentPercentageControllers[index]!.text;
          setState(() {
            _agentPercentage[index] = numValue;
            _agents[index]['percentage'] = numValue;
          });
          _onDataChanged();
          FocusScope.of(context).nextFocus();
        },
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: const Color(0xFF5D5D5D),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          isDense: true,
        ),
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: const Color(0xFF5C5C5C),
        ),
      ),
    );
  }

  // Helper widget to build focus-aware input container with dynamic shadow
  Widget _buildFocusAwareInputContainer({
    required Widget child,
    required FocusNode focusNode,
    VoidCallback? onFocusLost,
    double width = double.infinity,
    double height = 40,
    Color backgroundColor = const Color(0xFFF8F9FA),
    double borderRadius = 8,
  }) {
    return _FocusAwareInputContainer(
      focusNode: focusNode,
      onFocusLost: onFocusLost,
      width: width,
      height: height,
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
      child: child,
    );
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
            left: 0,
            right: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project Details',
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  height: 1.25, // 40px line-height / 32px font-size = 1.25
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Enter and manage project details for this project.",
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                  height: 1.0, // line-height: normal
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Tab navigation bar (from Figma design)
        Transform.translate(
          offset: const Offset(-22, 0), // Move left to start from sidebar shadow end (252 + 1 offset)
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
              const SizedBox(width: 24), // 24 + 253 to compensate for Transform.translate
              // Overview tab
              GestureDetector(
                onTap: () => setState(() => _activeTab = ProjectTab.about),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: _activeTab == ProjectTab.about
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
                      'Area',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: _activeTab == ProjectTab.about
                            ? FontWeight.w500
                            : FontWeight.normal,
                        color: _activeTab == ProjectTab.about
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
                onTap: () => setState(() => _activeTab = ProjectTab.partners),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: _activeTab == ProjectTab.partners
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
                            fontSize: 14,
                            fontWeight: _activeTab == ProjectTab.partners
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: _activeTab == ProjectTab.partners
                                ? const Color(0xFF0C8CE9)
                                : const Color(0xFF5C5C5C),
                          ),
                        ),
                      ),
                    ),
                    if (_hasPartnerValidationErrors)
                      Positioned(
                        top: -8,
                        child: SvgPicture.asset(
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
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 36),
              // Expenses tab
              GestureDetector(
                onTap: () => setState(() => _activeTab = ProjectTab.expenses),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: _activeTab == ProjectTab.expenses
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
                          'Expenses',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: _activeTab == ProjectTab.expenses
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: _activeTab == ProjectTab.expenses
                                ? const Color(0xFF0C8CE9)
                                : const Color(0xFF5C5C5C),
                          ),
                        ),
                      ),
                    ),
                    if (_hasExpenseValidationErrors)
                      Positioned(
                        top: -8,
                        child: SvgPicture.asset(
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
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 36),
              // Site tab
              GestureDetector(
                onTap: () => setState(() => _activeTab = ProjectTab.site),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: _activeTab == ProjectTab.site
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
                        fontSize: 14,
                        fontWeight: _activeTab == ProjectTab.site
                            ? FontWeight.w500
                            : FontWeight.normal,
                        color: _activeTab == ProjectTab.site
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
                onTap: () => setState(() => _activeTab = ProjectTab.projectManagers),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: _activeTab == ProjectTab.projectManagers
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
                            fontSize: 14,
                            fontWeight: _activeTab == ProjectTab.projectManagers
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: _activeTab == ProjectTab.projectManagers
                                ? const Color(0xFF0C8CE9)
                                : const Color(0xFF5C5C5C),
                          ),
                        ),
                      ),
                    ),
                    if (_hasProjectManagerValidationErrors)
                      Positioned(
                        top: -8,
                        child: SvgPicture.asset(
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
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 36),
              // Agent(s) tab
              GestureDetector(
                onTap: () => setState(() => _activeTab = ProjectTab.agents),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: _activeTab == ProjectTab.agents
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
                            fontSize: 14,
                            fontWeight: _activeTab == ProjectTab.agents
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: _activeTab == ProjectTab.agents
                                ? const Color(0xFF0C8CE9)
                                : const Color(0xFF5C5C5C),
                          ),
                        ),
                      ),
                    ),
                    if (_hasAgentValidationErrors)
                      Positioned(
                        top: -8,
                        child: SvgPicture.asset(
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
                      ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
          ),
        ),
        const SizedBox(height: 16),
        // Content
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              clipBehavior: Clip.hardEdge,
              padding: EdgeInsets.only(
                top: 28,
                left: 4,
                right: 24,
              ),
              child: (_activeTab == ProjectTab.about
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Site Area Details card
                        Container(
                          width: 696,
                          margin: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header section
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Site Area Details',
                                    style: GoogleFonts.inter(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                      height: 1.0, // line-height: normal
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: 532,
                                    height: 18,
                                    child: Center(
                                      child: Text(
                                        "Approved selling and non-sellable areas together make up the total project area.",
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          color: Colors.black.withOpacity(0.8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              // Fields container
                              Container(
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
                                    // Total Project Area field
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Total Project Area ',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black,
                                              ),
                                            ),
                                            Text(
                                              '*',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        _buildFocusAwareInputContainer(
                                          focusNode: _totalAreaFocusNode,
                                          width: 200,
                                          height: 40,
                                          backgroundColor: Colors.white.withOpacity(0.95),
                                          child: Center(
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                Expanded(
                                                  child: DecimalInputField(
                                                    controller: _totalAreaController,
                                                    focusNode: _totalAreaFocusNode,
                                                    hintText: '0.00',
                                                    inputFormatters: [IndianNumberFormatter()],
                                                    onTap: () {
                                                      final cleaned = _totalAreaController.text.replaceAll(',', '').replaceAll(' ', '').trim();
                                                      if (cleaned == '0' || cleaned == '0.00') {
                                                        _totalAreaController.text = '';
                                                        _totalAreaController.selection = TextSelection.collapsed(offset: 0);
                                                        setState(() {});
                                                      }
                                                    },
                                                    onChanged: (_) {
                                                      setState(() {});
                                                      _onDataChanged();
                                                    },
                                                    onEditingComplete: () {
                                                      final cleaned = _totalAreaController.text.replaceAll(',', '').replaceAll(' ', '');
                                                      final formatted = _formatAmount(cleaned);
                                                      _totalAreaController.text = formatted;
                                                      setState(() {});
                                                      _onDataChanged();
                                                      FocusScope.of(context).nextFocus();
                                                    },
                                                    contentPadding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 8),
                                                  child: Text(
                                                    'sqft',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.normal,
                                                      color: const Color(0xFF5C5C5C),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    // Approved Selling Area field
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Approved Selling Area ',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black,
                                              ),
                                            ),
                                            Text(
                                              '*',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        _buildFocusAwareInputContainer(
                                          focusNode: _sellingAreaFocusNode,
                                          width: 208,
                                          height: 40,
                                          backgroundColor: Colors.white.withOpacity(0.95),
                                          child: Center(
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                Expanded(
                                                  child: DecimalInputField(
                                                    controller: _sellingAreaController,
                                                    focusNode: _sellingAreaFocusNode,
                                                    hintText: '0.00',
                                                    inputFormatters: [IndianNumberFormatter()],
                                                    onTap: () {
                                                      final cleaned = _sellingAreaController.text.replaceAll(',', '').replaceAll(' ', '').trim();
                                                      if (cleaned == '0' || cleaned == '0.00') {
                                                        _sellingAreaController.text = '';
                                                        _sellingAreaController.selection = TextSelection.collapsed(offset: 0);
                                                        setState(() {});
                                                      }
                                                    },
                                                    onChanged: (_) {
                                                      setState(() {});
                                                      _onDataChanged();
                                                    },
                                                    onEditingComplete: () {
                                                      final cleaned = _sellingAreaController.text.replaceAll(',', '').replaceAll(' ', '');
                                                      final formatted = _formatAmount(cleaned);
                                                      _sellingAreaController.text = formatted;
                                                      setState(() {});
                                                      _onDataChanged();
                                                      FocusScope.of(context).nextFocus();
                                                    },
                                                    contentPadding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 8),
                                                  child: Text(
                                                    'sqft',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.normal,
                                                      color: const Color(0xFF5C5C5C),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    // Non-Sellable Area(s) section
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Non-Sellable Area(s) ',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black,
                                              ),
                                            ),
                                            Text(
                                              '*',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Total Non-Sellable Area: ${_totalNonSellableArea.toStringAsFixed(2)} sqft',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.normal,
                                            color: const Color(0xFF5C5C5C),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // Non-sellable area entries
                                        ..._nonSellableAreas.asMap().entries.map((entry) {
                                          final index = entry.key;
                                          final area = entry.value;
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 8),
                                            child: Row(
                                              children: [
                                                // Area field
                                                Container(
                                                  width: 208,
                                                  height: 40,
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.95),
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
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      crossAxisAlignment: CrossAxisAlignment.center,
                                                      children: [
                                                        Expanded(
                                                          child: Builder(
                                                            builder: (context) {
                                                              // Ensure controller exists
                                                              if (_nonSellableAreaControllers[index] == null) {
                                                                _nonSellableAreaControllers[index] = TextEditingController();
                                                              }
                                                              return DecimalInputField(
                                                                hintText: '0.00',
                                                                controller: _nonSellableAreaControllers[index]!,
                                                                inputFormatters: [IndianNumberFormatter()],
                                                                onTap: () {
                                                                  final cleaned = _nonSellableAreaControllers[index]!.text.replaceAll(',', '').replaceAll(' ', '').trim();
                                                                  if (cleaned == '0' || cleaned == '0.00') {
                                                                    _nonSellableAreaControllers[index]!.text = '';
                                                                    _nonSellableAreaControllers[index]!.selection = TextSelection.collapsed(offset: 0);
                                                                    setState(() {});
                                                                  }
                                                                },
                                                                onChanged: (value) {
                                                                  final rawValue = value.replaceAll(',', '').replaceAll(' ', '');
                                                                  setState(() {
                                                                    _nonSellableAreas[index]['area'] = rawValue.isEmpty ? '0.00' : rawValue;
                                                                  });
                                                                  _onDataChanged();
                                                                },
                                                                onEditingComplete: () {
                                                                  final cleaned = _nonSellableAreaControllers[index]!.text.replaceAll(',', '').replaceAll(' ', '');
                                                                  final formatted = _formatAmount(cleaned);
                                                                  _nonSellableAreaControllers[index]!.text = formatted;
                                                                  setState(() {
                                                                    _nonSellableAreas[index]['area'] = formatted.replaceAll(',', '');
                                                                  });
                                                                  _onDataChanged();
                                                                  FocusScope.of(context).nextFocus();
                                                                },
                                                                contentPadding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      Padding(
                                                        padding: const EdgeInsets.only(left: 8),
                                                        child: Text(
                                                          'sqft',
                                                          style: GoogleFonts.inter(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.normal,
                                                            color: const Color(0xFF5C5C5C),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Name field
                                                Container(
                                                  width: 250,
                                                  height: 40,
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.95),
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
                                                  child: Align(
                                                    alignment: Alignment.centerLeft,
                                                    child: TextField(
                                                      textAlignVertical: TextAlignVertical.top,
                                                      controller: _nonSellableNameControllers[index],
                                                      onChanged: (value) {
                                                        setState(() {
                                                          _nonSellableAreas[index]['name'] = value;
                                                        });
                                                        _onDataChanged();
                                                      },
                                                      decoration: InputDecoration(
                                                        hintText: 'Roads & Utilities',
                                                        hintStyle: GoogleFonts.inter(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w500,
                                                          color: const Color(0xFFADADAD).withOpacity(0.75),
                                                        ),
                                                        border: InputBorder.none,
                                                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                                                        isDense: true,
                                                        alignLabelWithHint: false,
                                                      ),
                                                      style: GoogleFonts.inter(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w500,
                                                        color: Colors.black,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Remove button
                                                GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _nonSellableNameControllers[index]?.dispose();
                                                      _nonSellableAreaControllers[index]?.dispose();
                                                      _nonSellableAreas.removeAt(index);
                                                      final oldNameControllers = Map<int, TextEditingController>.from(_nonSellableNameControllers);
                                                      final oldAreaControllers = Map<int, TextEditingController>.from(_nonSellableAreaControllers);
                                                      _nonSellableNameControllers.clear();
                                                      _nonSellableAreaControllers.clear();
                                                      for (int i = 0; i < _nonSellableAreas.length; i++) {
                                                        if (i < index) {
                                                          _nonSellableNameControllers[i] = oldNameControllers[i]!;
                                                          _nonSellableAreaControllers[i] = oldAreaControllers[i]!;
                                                        } else {
                                                          _nonSellableNameControllers[i] = oldNameControllers[i + 1]!;
                                                          _nonSellableAreaControllers[i] = oldAreaControllers[i + 1]!;
                                                        }
                                                      }
                                                    });
                                                    _onDataChanged();
                                                  },
                                                  child: Container(
                                                    height: 36,
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                                                    child: Center(
                                                      child: Text(
                                                        'Remove',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.normal,
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        const SizedBox(height: 0),
                                        // Remaining Area
                                        Row(
                                          children: [
                                            Text(
                                              'Remaining Area: ',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: _remainingArea == 0 
                                                    ? const Color(0xFF06AB00) // Green when 0
                                                    : Colors.red, // Red when not 0
                                              ),
                                            ),
                                            Text(
                                              '${_remainingArea.toStringAsFixed(2)} sqft',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.normal,
                                                color: _remainingArea == 0 
                                                    ? const Color(0xFF06AB00) // Green when 0
                                                    : Colors.red, // Red when not 0
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Add Non-Sellable Area button
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              final newIndex = _nonSellableAreas.length;
                                              _nonSellableAreas.add({
                                                'name': 'Roads & Utilities',
                                                'area': '0.00',
                                              });
                                              _nonSellableNameControllers[newIndex] = TextEditingController();
                                              _nonSellableAreaControllers[newIndex] = TextEditingController();
                                            });
                                            _onDataChanged();
                                          },
                                          child: Container(
                                            height: 36,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                                  'Add Non-Sellable Area',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.normal,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                SvgPicture.asset(
                                                  'assets/images/Cretae_new_projet_white.svg',
                                                  width: 12,
                                                  height: 12,
                                                  fit: BoxFit.contain,
                                                  placeholderBuilder: (context) => const SizedBox(
                                                    width: 12,
                                                    height: 12,
                                                  ),
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return const SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child: Icon(Icons.add, size: 12, color: Colors.white),
                                                    );
                                                  },
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
                            ],
                          ),
                        ),
                      ],
                    )
                  : GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                      },
                      child: (_activeTab == ProjectTab.partners
                              ? _buildPartnersContent()
                              : _activeTab == ProjectTab.expenses
                                  ? _buildExpensesContent()
                                  : _activeTab == ProjectTab.site
                                      ? _buildSiteContent()
                                      : _activeTab == ProjectTab.projectManagers
                                          ? _buildProjectManagersContent()
                                          : _activeTab == ProjectTab.agents
                                              ? _buildAgentsContent()
                                              : const SizedBox.shrink()))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPartnersContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Estimated Development Cost card
        Container(
          width: 430,
          margin: const EdgeInsets.only(bottom: 40),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
              // Title and asterisk
              Row(
                children: [
                  Text(
                    'Estimated Development Cost (₹) ',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '*',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Description
              Text(
                'Base budget used to allocate partner capital contribution.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.black.withOpacity(0.80),
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
              const SizedBox(height: 16),
              // Input field
              Container(
                width: 178,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF).withOpacity(0.95),
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
                  children: [
                    Text(
                      '₹',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF5D5D5D),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DecimalInputField(
                        controller: _estimatedDevelopmentCostController,
                        hintText: '0.00',
                        inputFormatters: [IndianNumberFormatter()],
                        onTap: () {
                          // Clear '0.00' when field is tapped
                          final cleaned = _estimatedDevelopmentCostController.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                          if (cleaned == '0' || cleaned == '0.00') {
                            _estimatedDevelopmentCostController.text = '';
                            _estimatedDevelopmentCostController.selection = TextSelection.collapsed(offset: 0);
                            setState(() {});
                          }
                        },
                        onChanged: (_) {
                          setState(() {});
                          _onDataChanged();
                        },
                        onEditingComplete: () {
                          // Remove commas before formatting
                          final cleaned = _estimatedDevelopmentCostController.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
                          final formatted = _formatAmount(cleaned);
                          _estimatedDevelopmentCostController.text = formatted;
                          setState(() {});
                          _onDataChanged();
                          FocusScope.of(context).nextFocus();
                        },
                        contentPadding: const EdgeInsets.only(top: 8, bottom: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Partners section
        Container(
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
              // New Partner(s) Details Title
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Partner(s) Details',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              // Informational text 1
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: 535,
                  child: Text(
                    'Total Capital Contributed must equal the Estimated Development Cost.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.black.withOpacity(0.80),
                    ),
                  ),
                ),
              ),
              // Informational text 2
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  width: 532,
                  child: Text(
                    'Net profit will be shared based on the profit-sharing percentage (%).',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.black.withOpacity(0.80),
                    ),
                  ),
                ),
              ),
              // Partners table
              _buildPartnersTable(),
              const SizedBox(height: 8),
              // Summary - Total Capital Contributed
              Text(
                'Total Capital Contributed: ₹ ${_formatAmountForDisplay(_totalPartnerAmount)}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              // Add Partner button
              GestureDetector(
                onTap: () {
                  setState(() {
                    final newIndex = _partners.length;
                    _partners.add({'name': '', 'amount': '0.00'});
                    _partnerNameControllers[newIndex] = TextEditingController();
                    _partnerAmountControllers[newIndex] = TextEditingController();
                  });
                  _onDataChanged();
                  // Ensure error state is updated after state change
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _notifyErrorState();
                  });
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                        'Add Partner',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SvgPicture.asset(
                        'assets/images/Cretae_new_projet_white.svg',
                        width: 12,
                        height: 12,
                        fit: BoxFit.contain,
                        placeholderBuilder: (context) => const SizedBox(
                          width: 12,
                          height: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Summary - Remaining and Total Share
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final exceedsAmount = _totalPartnerAmount > _estimatedDevelopmentCost && _estimatedDevelopmentCost > 0;
                      final remaining = _remainingPartnerAmount;
                      String formattedAmount = _formatAmountForDisplay(remaining.abs());
                      
                      final displayText = exceedsAmount
                          ? 'Remaining Budget to Allocate: - ₹ $formattedAmount [ Exceeding Estimated Development Cost (₹) ]'
                          : 'Remaining Budget to Allocate: ₹ $formattedAmount';
                      
                      return Text(
                        displayText,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: (remaining != 0 || exceedsAmount) ? Colors.red : const Color(0xFF06AB00),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total Share Allocated: ${_totalSharePercentage % 1 == 0 ? _totalSharePercentage.toStringAsFixed(0) : _totalSharePercentage.toStringAsFixed(2)}%',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _totalSharePercentage != 100 ? Colors.red : const Color(0xFF06AB00),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPartnersTable() {
    if (_partners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _partnersTableScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _partnersTableScrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sl. No. column
          Column(
            children: [
              // Header
              Container(
                width: 60,
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
              ...List.generate(_partners.length, (index) {
                final isLast = index == _partners.length - 1;
                return Container(
                  width: 60,
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
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }),
            ],
          ),
          // Partner Name column
          Column(
            children: [
              // Header
              Container(
                width: 320,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF707070).withOpacity(0.2),
                  border: const Border(
                    top: BorderSide(color: Colors.black, width: 1.0),
                    right: BorderSide(color: Colors.black, width: 1.0),
                    bottom: BorderSide(color: Colors.black, width: 1.0),
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Partner Name ',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        '*',
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
              // Rows
              ...List.generate(_partners.length, (index) {
                final isLast = index == _partners.length - 1;
                return Container(
                  width: 320,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      right: const BorderSide(color: Colors.black, width: 1.0),
                      bottom: const BorderSide(color: Colors.black, width: 1.0),
                      top: BorderSide.none,
                      left: BorderSide.none,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                      child: TextField(
                        controller: _partnerNameControllers[index],
                        textAlignVertical: TextAlignVertical.center,
                        textAlign: TextAlign.left,
                        onChanged: (value) {
                          setState(() {
                            _partners[index]['name'] = value;
                          });
                          _onDataChanged();
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter a name',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color.fromARGB(191, 173, 173, 173),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.only(left: 0, top: 11),
                          isDense: true,
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          // Amount column
          Column(
            children: [
              // Header
              Container(
                width: 294,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF707070).withOpacity(0.2),
                  border: const Border(
                    top: BorderSide(color: Colors.black, width: 1.0),
                    right: BorderSide(color: Colors.black, width: 1.0),
                    bottom: BorderSide(color: Colors.black, width: 1.0),
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Amount (₹) ',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        '*',
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
              // Rows
              ...List.generate(_partners.length, (index) {
                final isLast = index == _partners.length - 1;
                return Container(
                  width: 294,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      right: const BorderSide(color: Colors.black, width: 1.0),
                      bottom: const BorderSide(color: Colors.black, width: 1.0),
                      top: BorderSide.none,
                      left: BorderSide.none,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '₹',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                // Ensure controller exists
                                if (_partnerAmountControllers[index] == null) {
                                  _partnerAmountControllers[index] = TextEditingController();
                                }
                                return DecimalInputField(
                                  controller: _partnerAmountControllers[index]!,
                                  hintText: '0.00',
                                  inputFormatters: [IndianNumberFormatter()],
                                  onTap: () {
                                    // Clear '0.00' when field is tapped
                                    final cleaned = _partnerAmountControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                                    if (cleaned == '0' || cleaned == '0.00') {
                                      _partnerAmountControllers[index]!.text = '';
                                      _partnerAmountControllers[index]!.selection = TextSelection.collapsed(offset: 0);
                                      setState(() {});
                                    }
                                  },
                                  onChanged: (value) {
                                    // Remove commas for storage (for real-time calculations)
                                    final rawValue = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
                                    setState(() {
                                      _partners[index]['amount'] = rawValue.isEmpty ? '0.00' : rawValue;
                                    });
                                    _onDataChanged();
                                  },
                                  onEditingComplete: () {
                                    // Remove commas before formatting
                                    final cleaned = _partnerAmountControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
                                    final formatted = _formatAmount(cleaned);
                                    _partnerAmountControllers[index]!.text = formatted;
                                    setState(() {
                                      _partners[index]['amount'] = formatted.replaceAll(',', '');
                                    });
                                    _onDataChanged();
                                    FocusScope.of(context).nextFocus();
                                  },
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          // Share column
          Column(
            children: [
              // Header
              Container(
                width: 120,
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
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Share (%)',
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
              ...List.generate(_partners.length, (index) {
                final isLast = index == _partners.length - 1;
                final exceedsAmount = _totalPartnerAmount > _estimatedDevelopmentCost && _estimatedDevelopmentCost > 0;
                final shareValue = _getPartnerShare(index);
                final shareDisplay = shareValue % 1 == 0 ? shareValue.toStringAsFixed(0) : shareValue.toStringAsFixed(2);
                final displayText = exceedsAmount ? 'NA' : '$shareDisplay %';
                return Container(
                  width: 120,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      right: const BorderSide(color: Colors.black, width: 1.0),
                      bottom: const BorderSide(color: Colors.black, width: 1.0),
                      top: BorderSide.none,
                      left: BorderSide.none,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      displayText,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: (shareValue == 0 && !exceedsAmount)
                            ? Color.fromARGB(191, 173, 173, 173)  // Grey placeholder when 0%
                            : (exceedsAmount
                                ? Colors.red
                                : const Color(0xFF5D5D5D)),  // Dark grey when has value
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }),
            ],
          ),
          // Remove column
          Column(
            children: [
              // Spacer to align Remove buttons with partner data rows
              const SizedBox(
                width: 120,
                height: 47,
              ),
              // Rows with Remove buttons
              ...List.generate(_partners.length, (index) {
                final isLast = index == _partners.length - 1;
                return Container(
                  width: 120,
                  height: index == 0 ? 49 : 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      top: index == 0
                          ? const BorderSide(color: Colors.black, width: 1.0)
                          : BorderSide.none,
                      right: const BorderSide(color: Colors.black, width: 1.0),
                      bottom: const BorderSide(color: Colors.black, width: 1.0),
                      left: BorderSide.none,
                    ),
                    borderRadius: index == 0 && isLast
                        ? const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          )
                        : (index == 0
                            ? const BorderRadius.only(
                                topRight: Radius.circular(8),
                              )
                            : (isLast
                                ? const BorderRadius.only(
                                    bottomRight: Radius.circular(8),
                                  )
                                : null)),
                  ),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        if (_partners.length > 1) {
                          setState(() {
                            _partnerNameControllers[index]?.dispose();
                            _partnerAmountControllers[index]?.dispose();
                            _partners.removeAt(index);
                            // Rebuild controllers maps
                            final oldNameControllers = Map<int, TextEditingController>.from(_partnerNameControllers);
                            final oldAmountControllers = Map<int, TextEditingController>.from(_partnerAmountControllers);
                            _partnerNameControllers.clear();
                            _partnerAmountControllers.clear();
                            for (int i = 0; i < _partners.length; i++) {
                              if (i < index) {
                                _partnerNameControllers[i] = oldNameControllers[i]!;
                                _partnerAmountControllers[i] = oldAmountControllers[i]!;
                              } else {
                                _partnerNameControllers[i] = oldNameControllers[i + 1]!;
                                _partnerAmountControllers[i] = oldAmountControllers[i + 1]!;
                              }
                            }
                          });
                          _onDataChanged();
                        }
                      },
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                        child: Center(
                          child: Text(
                            'Remove',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpensesContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            Container(
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
                    'Expense Details',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track and manage all project expenses in one place.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.black.withOpacity(0.80),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildExpensesTable(),
                  const SizedBox(height: 16),
                  // Add Expenses button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        final newIndex = _expenses.length;
                        _expenses.add({'item': '', 'amount': '0.00', 'category': ''});
                        _expenseItemControllers[newIndex] = TextEditingController();
                        _expenseAmountControllers[newIndex] = TextEditingController();
                      });
                      _onDataChanged();
                    },
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                            'Add Expenses',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SvgPicture.asset(
                            'assets/images/Cretae_new_projet_white.svg',
                            width: 12,
                            height: 12,
                            fit: BoxFit.contain,
                            placeholderBuilder: (context) => const SizedBox(
                              width: 12,
                              height: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Summary information
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Expenses: ₹ ${_formatAmountForDisplay(_totalExpenses)}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Row(
                          children: [
                            Text(
                              'Estimated Development Cost [Budget]: ',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              '₹ ${_formatAmountForDisplay(_estimatedDevelopmentCost)} ',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: Colors.black,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() => _activeTab = ProjectTab.partners);
                              },
                              child: Text(
                                '[Edit]',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  color: const Color(0xFF0C8CE9),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final remaining = _remainingBudget;
                            String formattedAmount = _formatAmountForDisplay(remaining.abs());
                            
                            String displayText;
                            Color textColor;
                            
                            if (remaining < 0) {
                              // Negative (over budget) - red
                              displayText = 'Remaining Budget: - ₹ $formattedAmount [Over Budget]';
                              textColor = Colors.red;
                            } else if (remaining == 0) {
                              // Zero - current color (black)
                              displayText = 'Remaining Budget: ₹ $formattedAmount';
                              textColor = Colors.black;
                            } else {
                              // Positive - green
                              displayText = 'Remaining Budget: ₹ $formattedAmount';
                              textColor = const Color(0xFF06AB00);
                            }
                            
                            return Text(
                              displayText,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
    );
  }

  Widget _buildSiteContent() {
    final controllerText = _numberOfLayoutsController.text;
    final numberOfLayouts = int.tryParse(controllerText.isEmpty ? '0' : controllerText) ?? 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            // Site Details section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Site Details',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Define layouts and add plots for this project.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: Colors.black.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 24),
                // Number of Layouts and Overall section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Number of Layouts card
                    Flexible(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxWidth: 523),
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Number of Layouts ',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Text(
                                    '*',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Enter the total number of layouts to automatically create sections for adding plots.',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black.withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _buildFocusAwareInputContainer(
                                    focusNode: _numberOfLayoutsFocusNode,
                                    onFocusLost: () {
                                      _processNumberOfLayouts();
                                    },
                                    width: 96,
                                    child: TextField(
                                      controller: _numberOfLayoutsController,
                                      focusNode: _numberOfLayoutsFocusNode,
                                      keyboardType: TextInputType.number,
                                      textAlignVertical: TextAlignVertical.center,
                                      inputFormatters: [IndianNumberFormatter()],
                                      onTap: () {
                                        // Clear '0' or '0.00' when field is tapped
                                        final cleaned = _numberOfLayoutsController.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                                        if (cleaned == '0' || cleaned == '0.00') {
                                          _numberOfLayoutsController.text = '';
                                          _numberOfLayoutsController.selection = TextSelection.collapsed(offset: 0);
                                          setState(() {
                                            _isCreateTableEnabled = false;
                                          });
                                        }
                                      },
                                      onChanged: (value) {
                                        // Check if a valid number > 0 is entered
                                        final cleaned = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                                        final numValue = double.tryParse(cleaned) ?? 0.0;
                                        final numLayouts = numValue.toInt();
                                        
                                        setState(() {
                                          _isCreateTableEnabled = numLayouts > 0;
                                        });
                                        _onDataChanged();
                                      },
                                      onEditingComplete: () {
                                        _processNumberOfLayouts();
                                      },
                                      decoration: InputDecoration(
                                        hintText: '0',
                                        hintStyle: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.normal,
                                          color: const Color(0xFF5C5C5C),
                                        ),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.only(top: 12, bottom: 16),
                                      ),
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Create Table button
                                  GestureDetector(
                                    onTap: _isCreateTableEnabled ? () {
                                      _processNumberOfLayouts();
                                    } : null,
                                    child: Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                            'Create Table',
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.normal,
                                              color: _isCreateTableEnabled
                                                  ? const Color(0xFF0C8CE9)
                                                  : const Color(0xFF0C8CE9).withOpacity(0.4),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _isCreateTableEnabled
                                              ? SvgPicture.asset(
                                                  'assets/images/Active_create_table.svg',
                                                  width: 16,
                                                  height: 16,
                                                  fit: BoxFit.contain,
                                                  placeholderBuilder: (context) => const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                  ),
                                                )
                                              : SvgPicture.asset(
                                                  'assets/images/Inactive_create_table.svg',
                                                  width: 16,
                                                  height: 16,
                                                  fit: BoxFit.contain,
                                                  placeholderBuilder: (context) => const SizedBox(
                                                    width: 16,
                                                    height: 16,
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
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 555,
                          child: Text(
                            'Plots are organized by layouts.\nEnter the number of layouts above to create sections for adding plots.',
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
                    const SizedBox(width: 24),
                    // Overall summary card
                    Flexible(
                      flex: 1,
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 561),
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
                            'Overall',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Area information
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Approved Selling Area (sqft): ',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Text(
                                    '${_formatAmountForDisplay(_approvedSellingArea)} sqft ',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.black,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() => _activeTab = ProjectTab.about);
                                    },
                                    child: Text(
                                      '[Edit]',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: const Color(0xFF0C8CE9),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    'Allocated Area: ',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: _allocatedArea > _approvedSellingArea
                                          ? Colors.red
                                          : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    _allocatedArea > _approvedSellingArea
                                        ? '${_formatAmountForDisplay(_allocatedArea)} sqft [Exceeding Selling Area]'
                                        : '${_formatAmountForDisplay(_allocatedArea)} sqft',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: _allocatedArea > _approvedSellingArea
                                          ? Colors.red
                                          : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    'Remaining Area: ',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: _remainingSiteArea < 0
                                          ? Colors.red
                                          : const Color(0xFF06AB00),
                                    ),
                                  ),
                                  Text(
                                    _remainingSiteArea < 0
                                        ? '${_formatAmountForDisplay(_remainingSiteArea)} sqft [Exceeding Selling Area]'
                                        : '${_formatAmountForDisplay(_remainingSiteArea)} sqft',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: _remainingSiteArea < 0
                                          ? Colors.red
                                          : const Color(0xFF06AB00),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Cost information
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Total All-in Cost: ',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Text(
                                    '₹ ${_formatAmountForDisplay(_totalPurchaseRate, decimalPlaces: 3)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    'Total Plot Cost: ',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Text(
                                    '₹ ${_formatAmountForDisplay(_totalPlotCost, decimalPlaces: 3)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Layouts section or empty state
            _layouts.isEmpty
                ? Container(
                    width: 1140,
                    height: 225,
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No Layouts Added',
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter the number of layouts above to start adding plots.',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _layouts.asMap().entries
                        .map((entry) {
                          final index = entry.key;
                          final layout = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: _buildLayoutCard(index, layout),
                          );
                        }).toList(),
                  ),
          ],
    );
  }

  Widget _buildProjectManagersContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Project Manager(s)',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track and manage all project expenses in one place.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildProjectManagersTable(),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  setState(() {
                    final newIndex = _projectManagers.length;
                    _projectManagers.add({
                      'name': '',
                      'compensation': '',
                      'earningType': '',
                    });
                    _projectManagerNameControllers[newIndex] = TextEditingController();
                    _projectManagerCompensation[newIndex] = '';
                    _projectManagerEarningType[newIndex] = '';
                    _projectManagerPercentage[newIndex] = '';
                    _projectManagerFixedFee[newIndex] = '';
                    _projectManagerMonthlyFee[newIndex] = '';
                    _projectManagerMonths[newIndex] = '';
                    _projectManagerPercentageControllers[newIndex] = TextEditingController();
                    _projectManagerFixedFeeControllers[newIndex] = TextEditingController();
                    _projectManagerMonthlyFeeControllers[newIndex] = TextEditingController();
                    _projectManagerMonthsControllers[newIndex] = TextEditingController();
                  });
                  _onDataChanged();
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                        'Add Project Manager',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SvgPicture.asset(
                        'assets/images/Cretae_new_projet_white.svg',
                        width: 12,
                        height: 12,
                        fit: BoxFit.contain,
                        placeholderBuilder: (context) => const SizedBox(
                          width: 12,
                          height: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProjectManagersTable() {
    // Ensure _projectManagers is initialized and has at least one item
    // This ensures the table always renders when the card is visible
    try {
      if (_projectManagers.isEmpty) {
        _projectManagers = [{'name': '', 'compensation': '', 'earningType': ''}];
      }
    } catch (e) {
      // If _projectManagers is undefined, initialize it
      _projectManagers = [{'name': '', 'compensation': '', 'earningType': ''}];
    }
    
    // Ensure controller maps are initialized (defensive check for web compilation)
    // In web compilation, final maps might not be initialized properly
    try {
      // Try to access maps to ensure they exist
      if (_projectManagerNameControllers == null) {
        // This shouldn't happen, but handle it if it does
      }
    } catch (e) {
      // Maps might be undefined, but we'll handle it in access points
    }
    
    final projectManagers = _projectManagers;

    return Scrollbar(
      controller: _projectManagersTableScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _projectManagersTableScrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        // Sl. No. column
        Column(
          children: [
            // Header
            Container(
              width: 60,
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
            ...List.generate(projectManagers.length, (index) {
              // Get selected blocks to calculate same height as other columns
              List<String> selectedBlocks = [];
              try {
                if (_projectManagerSelectedBlocks != null) {
                  selectedBlocks = _projectManagerSelectedBlocks[index] ?? [];
                }
              } catch (e) {
                selectedBlocks = [];
              }
              final isLast = index == projectManagers.length - 1;
              return Container(
                width: 60,
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }),
          ],
        ),
        // Project Manager(s) column
        Column(
          children: [
            // Header
            Container(
              width: 320,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Project Manager(s) ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            // Rows
            ...List.generate(projectManagers.length, (index) {
              // Safely get controller, ensuring map is initialized
              TextEditingController controller;
              try {
                final map = _projectManagerNameControllers;
                controller = map[index] ?? TextEditingController();
                if (map[index] == null) {
                  map[index] = controller;
                }
              } catch (e) {
                // If accessing map fails, create controller anyway
                controller = TextEditingController();
              }
              // Calculate dynamic height to match compensation column
              List<String> selectedBlocks = [];
              try {
                selectedBlocks = _projectManagerSelectedBlocks[index] ?? [];
              } catch (e) {
                selectedBlocks = [];
              }
              final isLast = index == projectManagers.length - 1;
              return Container(
                width: 320,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: ((controller.text.trim().isEmpty) ||
                                  (_projectManagers[index]['name'] == null ||
                                   _projectManagers[index]['name'].toString().trim().isEmpty))
                              ? Colors.red
                              : Colors.black.withOpacity(0.15),
                          blurRadius: 2,
                          offset: const Offset(0, 0),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: controller,
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: (value) {
                        setState(() {
                          _projectManagers[index]['name'] = value;
                        });
                        _onDataChanged();
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter a name',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: const Color(0xFF5D5D5D),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                        isDense: true,
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Compensation column
        Column(
          children: [
            // Header
            Container(
              width: 350,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Compensation ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            // Rows
            ...List.generate(projectManagers.length, (index) {
              // Safely get compensation value
              String selectedCompensation = '';
              try {
                selectedCompensation = _projectManagerCompensation[index] ?? '';
              } catch (e) {
                // If map is null, use empty string
                selectedCompensation = '';
              }
              // Get selected blocks for this project manager
              List<String> selectedBlocks = [];
              try {
                if (_projectManagerSelectedBlocks != null && _projectManagerSelectedBlocks.containsKey(index)) {
                  final blocks = _projectManagerSelectedBlocks[index];
                  if (blocks != null) {
                    // Ensure it's a list of strings
                    selectedBlocks = blocks.map((b) => b.toString()).toList();
                    print('Displaying blocks for manager $index: $selectedBlocks, joined: ${selectedBlocks.join(",")}');
                  }
                }
              } catch (e) {
                selectedBlocks = [];
              }
              final hasSelectedBlocks = selectedBlocks.isNotEmpty;
              final blocksDisplayText = hasSelectedBlocks ? selectedBlocks.join(",") : '';
              final compensationKey = GlobalKey();
              return Container(
                key: compensationKey,
                width: 350,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Builder(
                      builder: (builderContext) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: () {
                                  _showCompensationDropdown(builderContext, index, compensationKey);
                                },
                                child: selectedCompensation.isNotEmpty
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IntrinsicWidth(
                                            child: Container(
                                              height: 32,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: _getCompensationColor(selectedCompensation),
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
                                                child: Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: Text(
                                                    selectedCompensation,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.normal,
                                                      color: Colors.black,
                                                    ),
                                                    textAlign: TextAlign.left,
                                                    overflow: TextOverflow.visible,
                                                    softWrap: true,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (hasSelectedBlocks)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Blocks: $blocksDisplayText',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.normal,
                                                  color: const Color(0xFF5D5D5D),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IntrinsicWidth(
                                            child: Container(
                                              height: 32,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF8F9FA),
                                                borderRadius: BorderRadius.circular(4),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.red,
                                                    blurRadius: 2,
                                                    offset: const Offset(0, 0),
                                                    spreadRadius: 0,
                                                  ),
                                                ],
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'Select the Compensation Type',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.normal,
                                                    color: const Color(0xFF5D5D5D),
                                                  ),
                                                  textAlign: TextAlign.left,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (hasSelectedBlocks)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Blocks: $blocksDisplayText',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.normal,
                                                  color: const Color(0xFF5D5D5D),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Align(
                              alignment: Alignment.center,
                              child: GestureDetector(
                                onTap: () {
                                  _showCompensationDropdown(builderContext, index, compensationKey);
                                },
                                child: SvgPicture.asset(
                                  selectedCompensation.isNotEmpty
                                      ? 'assets/images/Drrrop_down.svg'
                                      : 'assets/images/non_chosen_drop_down.svg',
                                  width: 14,
                                  height: 7,
                                  fit: BoxFit.contain,
                                  placeholderBuilder: (context) => const SizedBox(
                                    width: 14,
                                    height: 7,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Earning Type column
        Column(
          children: [
            // Header
            Container(
              width: 365,
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
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Earning Type ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            // Rows
            ...List.generate(projectManagers.length, (index) {
              // Safely get earning type value
              String selectedEarningType = '';
              try {
                selectedEarningType = _projectManagerEarningType[index] ?? '';
              } catch (e) {
                // If map is null, use empty string
                selectedEarningType = '';
              }
              // Get compensation type
              String compensationType = '';
              try {
                compensationType = _projectManagerCompensation[index] ?? '';
              } catch (e) {
                compensationType = '';
              }
              final isPercentageBonus = compensationType == 'Percentage Bonus';
              final isFixedFee = compensationType == 'Fixed Fee';
              final isMonthlyFee = compensationType == 'Monthly Fee';
              final hasEarningType = selectedEarningType.isNotEmpty;
              // Get percentage value
              String percentageValue = '';
              try {
                percentageValue = _projectManagerPercentage[index] ?? '0';
              } catch (e) {
                percentageValue = '0';
              }
              // Get Fixed Fee amount value
              String fixedFeeValue = '';
              try {
                fixedFeeValue = _projectManagerFixedFee[index] ?? '0';
              } catch (e) {
                fixedFeeValue = '0';
              }
              // Get Monthly Fee amount value
              String monthlyFeeValue = '';
              try {
                monthlyFeeValue = _projectManagerMonthlyFee[index] ?? '0';
              } catch (e) {
                monthlyFeeValue = '0';
              }
              // Get Months value
              String monthsValue = '';
              try {
                monthsValue = _projectManagerMonths[index] ?? '';
              } catch (e) {
                monthsValue = '';
              }
              final isLast = index == projectManagers.length - 1;
              final earningTypeKey = GlobalKey();
              return Container(
                key: earningTypeKey,
                width: 365,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: GestureDetector(
                      onTap: (compensationType.isEmpty || compensationType == 'None') ? null : () {
                        _showEarningTypeDropdown(context, index, earningTypeKey);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                        Expanded(
                          child: Row(
                            children: [
                              // Percentage input field (only show if percentage bonus and earning type selected)
                              if (isPercentageBonus && hasEarningType)
                                Container(
                                  height: 32,
                                  width: 48,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8F9FA),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 2,
                                        offset: const Offset(0, 0),
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: Builder(
                                    builder: (context) => _buildProjectManagerPercentageField(index, context),
                                  ),
                                ),
                              if (isPercentageBonus && hasEarningType)
                                const SizedBox(width: 8),
                              // Earning type display (only for Percentage Bonus)
                              if (hasEarningType && isPercentageBonus)
                                IntrinsicWidth(
                                  child: Container(
                                    constraints: const BoxConstraints(minHeight: 38),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    alignment: Alignment.centerLeft,
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
                                      selectedEarningType,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                )
                              // Fixed Fee amount input - show when Fixed Fee is selected (similar to partners section)
                              else if (isFixedFee)
                                Expanded(
                                  child: Container(
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
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          '₹',
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Builder(
                                            builder: (context) => _buildProjectManagerFixedFeeField(index, context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              // Monthly Fee amount input - show when Monthly Fee is selected
                              else if (isMonthlyFee)
                                Row(
                                  children: [
                                    Container(
                                      width: 224,
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
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            '₹',
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.normal,
                                              color: Colors.black,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Builder(
                                              builder: (context) => _buildProjectManagerMonthlyFeeField(index, context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '*',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 80,
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
                                      child: Builder(
                                        builder: (context) => _buildProjectManagerMonthsField(index, context),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: IntrinsicWidth(
                                          child: Container(
                                            height: 32,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            decoration: BoxDecoration(
                                              color: hasEarningType 
                                                  ? const Color(0xFFECF6FD)
                                                  : const Color(0xFFF8F9FA),
                                              borderRadius: BorderRadius.circular(4),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (compensationType.isNotEmpty && 
                                                          compensationType != 'None' && 
                                                          selectedEarningType.isEmpty)
                                                      ? Colors.red
                                                      : Colors.black.withOpacity(0.15),
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 0),
                                                  spreadRadius: 0,
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  compensationType == 'None'
                                                      ? 'NA'
                                                      : (selectedEarningType.isEmpty
                                                          ? 'Select Earning Type'
                                                          : selectedEarningType),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.normal,
                                                    color: compensationType == 'None'
                                                        ? Colors.black
                                                        : (selectedEarningType.isEmpty 
                                                            ? const Color(0xFF5D5D5D)
                                                            : Colors.black),
                                                  ),
                                                  textAlign: TextAlign.left,
                                                  overflow: TextOverflow.visible,
                                                  softWrap: true,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (compensationType.isNotEmpty && compensationType != 'None') ...[
                                        const SizedBox(width: 4),
                                        Center(
                                          child: SvgPicture.asset(
                                            'assets/images/Drrrop_down.svg',
                                            width: 14,
                                            height: 7,
                                            fit: BoxFit.contain,
                                            placeholderBuilder: (context) => const SizedBox(
                                              width: 14,
                                              height: 7,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isPercentageBonus && hasEarningType)
                          const SizedBox(width: 8),
                        if (isPercentageBonus && hasEarningType)
                          Container(
                            constraints: const BoxConstraints(minHeight: 38),
                            alignment: Alignment.center,
                            child: SvgPicture.asset(
                              'assets/images/Drrrop_down.svg',
                              width: 14,
                              height: 7,
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 14,
                                height: 7,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ),
              );
            }),
          ],
        ),
        // Remove column
        Column(
          children: [
            // Spacer to align Remove buttons with project manager data rows
            const SizedBox(
              width: 120,
              height: 47,
            ),
            // Rows with Remove buttons
            ...List.generate(projectManagers.length, (index) {
              final isLast = index == projectManagers.length - 1;
              return Container(
                width: 120,
                height: index == 0 ? 49 : 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: index == 0
                        ? const BorderSide(color: Colors.black, width: 1.0)
                        : BorderSide.none,
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    left: BorderSide.none,
                  ),
                  borderRadius: index == 0 && projectManagers.length == 1
                      ? const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        )
                      : (index == 0
                          ? const BorderRadius.only(
                              topRight: Radius.circular(8),
                            )
                          : (isLast
                              ? const BorderRadius.only(
                                  bottomRight: Radius.circular(8),
                                )
                              : null)),
                ),
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        try {
                          // Dispose the controller at this index
                          _projectManagerNameControllers[index]?.dispose();
                          
                          // Remove all data for this index
                          _projectManagerNameControllers.remove(index);
                          _projectManagerCompensation.remove(index);
                          _projectManagerEarningType.remove(index);
                          _projectManagerPercentageControllers[index]?.dispose();
                          _projectManagerFixedFeeControllers[index]?.dispose();
                          _projectManagerMonthlyFeeControllers[index]?.dispose();
                          _projectManagerMonthsControllers[index]?.dispose();
                          _projectManagerPercentageControllers.remove(index);
                          _projectManagerFixedFeeControllers.remove(index);
                          _projectManagerMonthlyFeeControllers.remove(index);
                          _projectManagerMonthsControllers.remove(index);
                          _projectManagerPercentage.remove(index);
                          _projectManagerFixedFee.remove(index);
                          _projectManagerMonthlyFee.remove(index);
                          _projectManagerMonths.remove(index);
                          _projectManagerSelectedBlocks.remove(index);
                          
                          // Remove from the main list
                          _projectManagers.removeAt(index);
                          
                          // Reindex all controllers and maps to be sequential starting from 0
                          final newControllers = <int, TextEditingController>{};
                          final newCompensation = <int, String>{};
                          final newEarningType = <int, String>{};
                          final newPercentageControllers = <int, TextEditingController>{};
                          final newFixedFeeControllers = <int, TextEditingController>{};
                          final newMonthlyFeeControllers = <int, TextEditingController>{};
                          final newMonthsControllers = <int, TextEditingController>{};
                          final newPercentage = <int, String>{};
                          final newFixedFee = <int, String>{};
                          final newMonthlyFee = <int, String>{};
                          final newMonths = <int, String>{};
                          final newSelectedBlocks = <int, List<String>>{};
                          
                          int newIndex = 0;
                          for (int oldIndex = 0; oldIndex < _projectManagerNameControllers.length + 1; oldIndex++) {
                            if (oldIndex == index) continue; // Skip the deleted index
                            
                            if (_projectManagerNameControllers.containsKey(oldIndex)) {
                              newControllers[newIndex] = _projectManagerNameControllers[oldIndex]!;
                            }
                            if (_projectManagerCompensation.containsKey(oldIndex)) {
                              newCompensation[newIndex] = _projectManagerCompensation[oldIndex]!;
                            }
                            if (_projectManagerEarningType.containsKey(oldIndex)) {
                              newEarningType[newIndex] = _projectManagerEarningType[oldIndex]!;
                            }
                            if (_projectManagerPercentageControllers.containsKey(oldIndex)) {
                              newPercentageControllers[newIndex] = _projectManagerPercentageControllers[oldIndex]!;
                            }
                            if (_projectManagerFixedFeeControllers.containsKey(oldIndex)) {
                              newFixedFeeControllers[newIndex] = _projectManagerFixedFeeControllers[oldIndex]!;
                            }
                            if (_projectManagerMonthlyFeeControllers.containsKey(oldIndex)) {
                              newMonthlyFeeControllers[newIndex] = _projectManagerMonthlyFeeControllers[oldIndex]!;
                            }
                            if (_projectManagerMonthsControllers.containsKey(oldIndex)) {
                              newMonthsControllers[newIndex] = _projectManagerMonthsControllers[oldIndex]!;
                            }
                            if (_projectManagerPercentage.containsKey(oldIndex)) {
                              newPercentage[newIndex] = _projectManagerPercentage[oldIndex]!;
                            }
                            if (_projectManagerFixedFee.containsKey(oldIndex)) {
                              newFixedFee[newIndex] = _projectManagerFixedFee[oldIndex]!;
                            }
                            if (_projectManagerMonthlyFee.containsKey(oldIndex)) {
                              newMonthlyFee[newIndex] = _projectManagerMonthlyFee[oldIndex]!;
                            }
                            if (_projectManagerMonths.containsKey(oldIndex)) {
                              newMonths[newIndex] = _projectManagerMonths[oldIndex]!;
                            }
                            if (_projectManagerSelectedBlocks.containsKey(oldIndex)) {
                              newSelectedBlocks[newIndex] = _projectManagerSelectedBlocks[oldIndex]!;
                            }
                            
                            newIndex++;
                          }
                          
                          // Replace with reindexed maps
                          _projectManagerNameControllers.clear();
                          _projectManagerCompensation.clear();
                          _projectManagerEarningType.clear();
                          _projectManagerPercentageControllers.clear();
                          _projectManagerFixedFeeControllers.clear();
                          _projectManagerMonthlyFeeControllers.clear();
                          _projectManagerMonthsControllers.clear();
                          _projectManagerPercentage.clear();
                          _projectManagerFixedFee.clear();
                          _projectManagerMonthlyFee.clear();
                          _projectManagerMonths.clear();
                          _projectManagerSelectedBlocks.clear();
                          
                          _projectManagerNameControllers.addAll(newControllers);
                          _projectManagerCompensation.addAll(newCompensation);
                          _projectManagerEarningType.addAll(newEarningType);
                          _projectManagerPercentageControllers.addAll(newPercentageControllers);
                          _projectManagerFixedFeeControllers.addAll(newFixedFeeControllers);
                          _projectManagerMonthlyFeeControllers.addAll(newMonthlyFeeControllers);
                          _projectManagerMonthsControllers.addAll(newMonthsControllers);
                          _projectManagerPercentage.addAll(newPercentage);
                          _projectManagerFixedFee.addAll(newFixedFee);
                          _projectManagerMonthlyFee.addAll(newMonthlyFee);
                          _projectManagerMonths.addAll(newMonths);
                          _projectManagerSelectedBlocks.addAll(newSelectedBlocks);
                        } catch (e) {
                          print('Error deleting project manager: $e');
                          // If maps are null, just remove from _projectManagers
                          _projectManagers.removeAt(index);
                        }
                      });
                      _onDataChanged();
                    },
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                      child: Center(
                        child: Text(
                          'Remove',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
        ),
      ),
    );
  }

  Widget _buildAgentsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agent(s)',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track and manage all agents in one place.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildAgentsTable(),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  setState(() {
                    final newIndex = _agents.length;
                    _agents.add({
                      'name': '',
                      'compensation': '',
                      'earningType': '',
                    });
                    _agentNameControllers[newIndex] = TextEditingController();
                    _agentCompensation[newIndex] = '';
                    _agentEarningType[newIndex] = '';
                    _agentPercentage[newIndex] = '';
                    _agentFixedFee[newIndex] = '';
                    _agentMonthlyFee[newIndex] = '';
                    _agentMonths[newIndex] = '';
                    _agentPerSqftFee[newIndex] = '';
                    _agentPercentageControllers[newIndex] = TextEditingController();
                    _agentFixedFeeControllers[newIndex] = TextEditingController();
                    _agentMonthlyFeeControllers[newIndex] = TextEditingController();
                    _agentMonthsControllers[newIndex] = TextEditingController();
                    _agentPerSqftFeeControllers[newIndex] = TextEditingController();
                  });
                  _saveAgentsData(); // Save agents immediately
                  _onDataChanged();
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                        'Add Agent',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SvgPicture.asset(
                        'assets/images/Cretae_new_projet_white.svg',
                        width: 12,
                        height: 12,
                        fit: BoxFit.contain,
                        placeholderBuilder: (context) => const SizedBox(
                          width: 12,
                          height: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAgentsTable() {
    // Ensure _agents is initialized and has at least one item
    try {
      if (_agents.isEmpty) {
        _agents = [{'name': '', 'compensation': '', 'earningType': ''}];
      }
    } catch (e) {
      _agents = [{'name': '', 'compensation': '', 'earningType': ''}];
    }
    
    try {
      if (_agentNameControllers == null) {
        // This shouldn't happen, but handle it if it does
      }
    } catch (e) {
      // Maps might be undefined, but we'll handle it in access points
    }
    
    final agents = _agents;

    return Scrollbar(
      controller: _agentsTableScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _agentsTableScrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        // Sl. No. column
        Column(
          children: [
            // Header
            Container(
              width: 60,
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
            ...List.generate(agents.length, (index) {
              List<String> selectedBlocks = [];
              try {
                if (_agentSelectedBlocks != null) {
                  selectedBlocks = _agentSelectedBlocks[index] ?? [];
                }
              } catch (e) {
                selectedBlocks = [];
              }
              final isLast = index == agents.length - 1;
              return Container(
                width: 60,
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }),
          ],
        ),
        // Agent(s) column
        Column(
          children: [
            // Header
            Container(
              width: 320,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Agent(s) ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            // Rows
            ...List.generate(agents.length, (index) {
              TextEditingController controller;
              try {
                final map = _agentNameControllers;
                controller = map[index] ?? TextEditingController();
                if (map[index] == null) {
                  map[index] = controller;
                }
              } catch (e) {
                controller = TextEditingController();
              }
              List<String> selectedBlocks = [];
              try {
                selectedBlocks = _agentSelectedBlocks[index] ?? [];
              } catch (e) {
                selectedBlocks = [];
              }
              final isLast = index == agents.length - 1;
              return Container(
                width: 320,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: ((controller.text.trim().isEmpty) ||
                                  (_agents[index]['name'] == null ||
                                   _agents[index]['name'].toString().trim().isEmpty))
                              ? Colors.red
                              : Colors.black.withOpacity(0.15),
                          blurRadius: 2,
                          offset: const Offset(0, 0),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: controller,
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: (value) {
                        setState(() {
                          _agents[index]['name'] = value;
                        });
                        _onDataChanged();
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter a name',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: const Color(0xFF5D5D5D),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                        isDense: true,
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Compensation column
        Column(
          children: [
            // Header
            Container(
              width: 350,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Compensation ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            // Rows
            ...List.generate(agents.length, (index) {
              String selectedCompensation = '';
              try {
                selectedCompensation = _agentCompensation[index] ?? '';
              } catch (e) {
                selectedCompensation = '';
              }
              List<String> selectedBlocks = [];
              try {
                if (_agentSelectedBlocks != null && _agentSelectedBlocks.containsKey(index)) {
                  final blocks = _agentSelectedBlocks[index];
                  if (blocks != null) {
                    // Ensure it's a list of strings
                    selectedBlocks = blocks.map((b) => b.toString()).toList();
                    print('Displaying blocks for agent $index: $selectedBlocks, joined: ${selectedBlocks.join(",")}');
                  }
                }
              } catch (e) {
                selectedBlocks = [];
              }
              final hasSelectedBlocks = selectedBlocks.isNotEmpty;
              final blocksDisplayText = hasSelectedBlocks ? selectedBlocks.join(",") : '';
              final compensationKey = GlobalKey();
              return Container(
                key: compensationKey,
                width: 350,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Builder(
                      builder: (builderContext) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: () {
                                  _showAgentCompensationDropdown(builderContext, index, compensationKey);
                                },
                                child: selectedCompensation.isNotEmpty
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IntrinsicWidth(
                                            child: Container(
                                              height: 32,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: _getCompensationColor(selectedCompensation),
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
                                                child: Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: Text(
                                                    selectedCompensation,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.normal,
                                                      color: Colors.black,
                                                    ),
                                                    textAlign: TextAlign.left,
                                                    overflow: TextOverflow.visible,
                                                    softWrap: true,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (hasSelectedBlocks)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Blocks: $blocksDisplayText',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.normal,
                                                  color: const Color(0xFF5D5D5D),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IntrinsicWidth(
                                            child: Container(
                                              height: 32,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF8F9FA),
                                                borderRadius: BorderRadius.circular(4),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.red,
                                                    blurRadius: 2,
                                                    offset: const Offset(0, 0),
                                                    spreadRadius: 0,
                                                  ),
                                                ],
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'Select the Compensation Type',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.normal,
                                                    color: const Color(0xFF5D5D5D),
                                                  ),
                                                  textAlign: TextAlign.left,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (hasSelectedBlocks)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Blocks: $blocksDisplayText',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.normal,
                                                  color: const Color(0xFF5D5D5D),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Align(
                              alignment: Alignment.center,
                              child: GestureDetector(
                                onTap: () {
                                  _showAgentCompensationDropdown(builderContext, index, compensationKey);
                                },
                                child: SvgPicture.asset(
                                  selectedCompensation.isNotEmpty
                                      ? 'assets/images/Drrrop_down.svg'
                                      : 'assets/images/non_chosen_drop_down.svg',
                                  width: 14,
                                  height: 7,
                                  fit: BoxFit.contain,
                                  placeholderBuilder: (context) => const SizedBox(
                                    width: 14,
                                    height: 7,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Earning Type column
        Column(
          children: [
            // Header
            Container(
              width: 365,
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
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Earning Type ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            // Rows
            ...List.generate(agents.length, (index) {
              String selectedEarningType = '';
              try {
                selectedEarningType = _agentEarningType[index] ?? '';
              } catch (e) {
                selectedEarningType = '';
              }
              String compensationType = '';
              try {
                compensationType = _agentCompensation[index] ?? '';
              } catch (e) {
                compensationType = '';
              }
              final isPercentageBonus = compensationType == 'Percentage Bonus';
              final isFixedFee = compensationType == 'Fixed Fee';
              final isMonthlyFee = compensationType == 'Monthly Fee';
              final isPerSqftFee = compensationType == 'Per Sqft Fee';
              final hasEarningType = selectedEarningType.isNotEmpty;
              String percentageValue = '';
              try {
                percentageValue = _agentPercentage[index] ?? '0';
              } catch (e) {
                percentageValue = '0';
              }
              String fixedFeeValue = '';
              try {
                fixedFeeValue = _agentFixedFee[index] ?? '0';
              } catch (e) {
                fixedFeeValue = '0';
              }
              String monthlyFeeValue = '';
              try {
                monthlyFeeValue = _agentMonthlyFee[index] ?? '0';
              } catch (e) {
                monthlyFeeValue = '0';
              }
              String perSqftFeeValue = '';
              try {
                perSqftFeeValue = _agentPerSqftFee[index] ?? '0';
              } catch (e) {
                perSqftFeeValue = '0';
              }
              String monthsValue = '';
              try {
                monthsValue = _agentMonths[index] ?? '';
              } catch (e) {
                monthsValue = '';
              }
              final isLast = index == agents.length - 1;
              final earningTypeKey = GlobalKey();
              return Container(
                key: earningTypeKey,
                width: 365,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: GestureDetector(
                      onTap: (compensationType.isEmpty || compensationType == 'None') ? null : () {
                        _showAgentEarningTypeDropdown(context, index, earningTypeKey);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (isPercentageBonus && hasEarningType)
                                Container(
                                  height: 32,
                                  width: 48,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8F9FA),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 2,
                                        offset: const Offset(0, 0),
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: Builder(
                                    builder: (context) => _buildAgentPercentageField(index, context),
                                  ),
                                ),
                              if (isPercentageBonus && hasEarningType)
                                const SizedBox(width: 8),
                              if (hasEarningType && isPercentageBonus)
                                IntrinsicWidth(
                                  child: Container(
                                    constraints: const BoxConstraints(minHeight: 38),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    alignment: Alignment.centerLeft,
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
                                      selectedEarningType,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                )
                              else if (isFixedFee)
                                Expanded(
                                  child: Container(
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
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          '₹',
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Builder(
                                            builder: (context) => _buildAgentFixedFeeField(index, context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else if (isMonthlyFee)
                                Row(
                                  children: [
                                    Container(
                                      width: 224,
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
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            '₹',
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.normal,
                                              color: Colors.black,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Builder(
                                              builder: (context) => _buildAgentMonthlyFeeField(index, context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '*',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 80,
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
                                      child: Builder(
                                        builder: (context) => _buildAgentMonthsField(index, context),
                                      ),
                                    ),
                                  ],
                                )
                              else if (isPerSqftFee)
                                Expanded(
                                  child: Container(
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
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          '₹',
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Builder(
                                            builder: (context) => _buildAgentPerSqftFeeField(index, context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: IntrinsicWidth(
                                          child: Container(
                                            height: 32,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            decoration: BoxDecoration(
                                              color: hasEarningType 
                                                  ? const Color(0xFFECF6FD)
                                                  : const Color(0xFFF8F9FA),
                                              borderRadius: BorderRadius.circular(4),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (compensationType.isNotEmpty && 
                                                          compensationType != 'None' && 
                                                          selectedEarningType.isEmpty)
                                                      ? Colors.red
                                                      : Colors.black.withOpacity(0.15),
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 0),
                                                  spreadRadius: 0,
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  compensationType == 'None'
                                                      ? 'NA'
                                                      : (selectedEarningType.isEmpty
                                                          ? 'Select Earning Type'
                                                          : selectedEarningType),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.normal,
                                                    color: compensationType == 'None'
                                                        ? Colors.black
                                                        : (selectedEarningType.isEmpty 
                                                            ? const Color(0xFF5D5D5D)
                                                            : Colors.black),
                                                  ),
                                                  textAlign: TextAlign.left,
                                                  overflow: TextOverflow.visible,
                                                  softWrap: true,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (compensationType.isNotEmpty && compensationType != 'None') ...[
                                        const SizedBox(width: 4),
                                        Center(
                                          child: SvgPicture.asset(
                                            'assets/images/Drrrop_down.svg',
                                            width: 14,
                                            height: 7,
                                            fit: BoxFit.contain,
                                            placeholderBuilder: (context) => const SizedBox(
                                              width: 14,
                                              height: 7,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isPercentageBonus && hasEarningType)
                          const SizedBox(width: 8),
                        if (isPercentageBonus && hasEarningType)
                          Container(
                            constraints: const BoxConstraints(minHeight: 38),
                            alignment: Alignment.center,
                            child: SvgPicture.asset(
                              'assets/images/Drrrop_down.svg',
                              width: 14,
                              height: 7,
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 14,
                                height: 7,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ),
              );
            }),
          ],
        ),
        // Remove column
        Column(
          children: [
            const SizedBox(
              width: 120,
              height: 47,
            ),
            ...List.generate(agents.length, (index) {
              final isLast = index == agents.length - 1;
              return Container(
                width: 120,
                height: index == 0 ? 49 : 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: index == 0
                        ? const BorderSide(color: Colors.black, width: 1.0)
                        : BorderSide.none,
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    left: BorderSide.none,
                  ),
                  borderRadius: index == 0 && agents.length == 1
                      ? const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        )
                      : (index == 0
                          ? const BorderRadius.only(
                              topRight: Radius.circular(8),
                            )
                          : (isLast
                              ? const BorderRadius.only(
                                  bottomRight: Radius.circular(8),
                                )
                              : null)),
                ),
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        try {
                          // Save old data before removal
                          Map<int, TextEditingController> oldControllers = Map<int, TextEditingController>.from(_agentNameControllers);
                          Map<int, String> oldCompensation = Map<int, String>.from(_agentCompensation);
                          Map<int, String> oldEarningType = Map<int, String>.from(_agentEarningType);
                          
                          // Dispose the controller for the row being removed
                          _agentNameControllers[index]?.dispose();
                          
                          // Remove the agent
                          _agents.removeAt(index);
                          
                          // Clear and rebuild controllers with correct indices
                          _agentNameControllers.clear();
                          _agentCompensation.clear();
                          _agentEarningType.clear();
                          
                          // Reindex: keep indices before removed index, shift indices after removed index
                          for (int i = 0; i < _agents.length; i++) {
                            if (i < index) {
                              // Keep indices before removed index as they are
                              if (oldControllers.containsKey(i)) {
                                _agentNameControllers[i] = oldControllers[i]!;
                              }
                              if (oldCompensation.containsKey(i)) {
                                _agentCompensation[i] = oldCompensation[i]!;
                              }
                              if (oldEarningType.containsKey(i)) {
                                _agentEarningType[i] = oldEarningType[i]!;
                              }
                            } else {
                              // Shift indices after removed index down by 1
                              if (oldControllers.containsKey(i + 1)) {
                                _agentNameControllers[i] = oldControllers[i + 1]!;
                              }
                              if (oldCompensation.containsKey(i + 1)) {
                                _agentCompensation[i] = oldCompensation[i + 1]!;
                              }
                              if (oldEarningType.containsKey(i + 1)) {
                                _agentEarningType[i] = oldEarningType[i + 1]!;
                              }
                            }
                          }
                        } catch (e) {
                          // Fallback: just remove the agent if reindexing fails
                          if (index < _agents.length) {
                            _agentNameControllers[index]?.dispose();
                            _agentNameControllers.remove(index);
                            _agentCompensation.remove(index);
                            _agentEarningType.remove(index);
                            _agents.removeAt(index);
                          }
                        }
                      });
                      _onDataChanged();
                    },
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                      child: Center(
                        child: Text(
                          'Remove',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
        ),
      ),
    );
  }

  void _showAgentCompensationDropdown(BuildContext context, int index, GlobalKey cellKey) {
    final RenderBox? renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
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
        left: offset.dx,
        top: offset.dy + renderBox.size.height - 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: renderBox.size.width,
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
                  Container(
                    padding: const EdgeInsets.only(top: 4, left: 8, right: 8, bottom: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Select the Compensation Type',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Transform.rotate(
                          angle: 180 * 3.14159 / 180,
                          child: SvgPicture.asset(
                            'assets/images/Drrrop_down.svg',
                            width: 14,
                            height: 7,
                            fit: BoxFit.contain,
                            placeholderBuilder: (context) => const SizedBox(
                              width: 14,
                              height: 7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._agentCompensationTypes.asMap().entries.map((entry) {
                          final typeIndex = entry.key;
                          final type = entry.value;
                          final isLast = typeIndex == _agentCompensationTypes.length - 1;
                          final currentCompensation = _agentCompensation[index] ?? '';
                          final isSelected = type == currentCompensation;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                try {
                                  _agentCompensation[index] = type;
                                  _agents[index]['compensation'] = type;
                                  if (type == 'Fixed Fee') {
                                    if (_agentFixedFee[index] == null || _agentFixedFee[index]!.isEmpty) {
                                      _agentFixedFee[index] = '0';
                                      _agents[index]['fixedFee'] = '0';
                                    }
                                    if (_agentFixedFeeControllers[index] == null) {
                                      _agentFixedFeeControllers[index] = TextEditingController();
                                    }
                                  }
                                  if (type == 'Monthly Fee') {
                                    if (_agentMonthlyFee[index] == null || _agentMonthlyFee[index]!.isEmpty) {
                                      _agentMonthlyFee[index] = '0';
                                      _agents[index]['monthlyFee'] = '0';
                                    }
                                    if (_agentMonths[index] == null || _agentMonths[index]!.isEmpty) {
                                      _agentMonths[index] = '';
                                      _agents[index]['months'] = '';
                                    }
                                    if (_agentMonthlyFeeControllers[index] == null) {
                                      _agentMonthlyFeeControllers[index] = TextEditingController();
                                    }
                                    if (_agentMonthsControllers[index] == null) {
                                      final currentMonthsValue = _agentMonths[index] ?? '';
                                      _agentMonthsControllers[index] = TextEditingController(
                                        text: currentMonthsValue,
                                      );
                                    }
                                  }
                                } catch (e) {
                                  _agents[index]['compensation'] = type;
                                  if (type == 'Fixed Fee') {
                                    _agentFixedFee[index] = '0';
                                    _agents[index]['fixedFee'] = '0';
                                    if (_agentFixedFeeControllers[index] == null) {
                                      _agentFixedFeeControllers[index] = TextEditingController(text: '');
                                    }
                                  }
                                  if (type == 'Monthly Fee') {
                                    _agentMonthlyFee[index] = '0';
                                    _agents[index]['monthlyFee'] = '0';
                                    _agentMonths[index] = '';
                                    _agents[index]['months'] = '';
                                    if (_agentMonthlyFeeControllers[index] == null) {
                                      _agentMonthlyFeeControllers[index] = TextEditingController(text: '');
                                    }
                                    if (_agentMonthsControllers[index] == null) {
                                      _agentMonthsControllers[index] = TextEditingController(text: '');
                                    }
                                  }
                                  if (type == 'Per Sqft Fee') {
                                    if (_agentPerSqftFee[index] == null || _agentPerSqftFee[index]!.isEmpty) {
                                      _agentPerSqftFee[index] = '0';
                                      _agents[index]['perSqftFee'] = '0';
                                    }
                                    if (_agentPerSqftFeeControllers[index] == null) {
                                      _agentPerSqftFeeControllers[index] = TextEditingController();
                                    }
                                  }
                                } catch (e) {
                                  _agents[index]['compensation'] = type;
                                  if (type == 'Fixed Fee') {
                                    _agentFixedFee[index] = '0';
                                    _agents[index]['fixedFee'] = '0';
                                    if (_agentFixedFeeControllers[index] == null) {
                                      _agentFixedFeeControllers[index] = TextEditingController(text: '');
                                    }
                                  }
                                  if (type == 'Monthly Fee') {
                                    _agentMonthlyFee[index] = '0';
                                    _agents[index]['monthlyFee'] = '0';
                                    _agentMonths[index] = '';
                                    _agents[index]['months'] = '';
                                    if (_agentMonthlyFeeControllers[index] == null) {
                                      _agentMonthlyFeeControllers[index] = TextEditingController();
                                    }
                                    if (_agentMonthsControllers[index] == null) {
                                      _agentMonthsControllers[index] = TextEditingController(text: '');
                                    }
                                  }
                                  if (type == 'Per Sqft Fee') {
                                    _agentPerSqftFee[index] = '0';
                                    _agents[index]['perSqftFee'] = '0';
                                    if (_agentPerSqftFeeControllers[index] == null) {
                                      _agentPerSqftFeeControllers[index] = TextEditingController();
                                    }
                                  }
                                }
                              });
                              _onDataChanged();
                              closeDropdown();
                            },
                            child: Container(
                              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 149,
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: isSelected 
                                      ? const Color(0xFFB0D5F0)
                                      : const Color(0xFFECF6FD),
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
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      type,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.left,
                                      overflow: TextOverflow.visible,
                                      softWrap: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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

  void _showCompensationDropdown(BuildContext context, int index, GlobalKey cellKey) {
    final RenderBox? renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
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
        left: offset.dx,
        top: offset.dy + renderBox.size.height - 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: renderBox.size.width,
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
                            'Select the Compensation Type',
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
                          child: SvgPicture.asset(
                            'assets/images/Drrrop_down.svg',
                            width: 14,
                            height: 7,
                            fit: BoxFit.contain,
                            placeholderBuilder: (context) => const SizedBox(
                              width: 14,
                              height: 7,
                            ),
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
                        ..._compensationTypes.asMap().entries.map((entry) {
                          final typeIndex = entry.key;
                          final type = entry.value;
                          final isLast = typeIndex == _compensationTypes.length - 1;
                          final currentCompensation = _projectManagerCompensation[index] ?? '';
                          final isSelected = type == currentCompensation;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                try {
                                  _projectManagerCompensation[index] = type;
                                  _projectManagers[index]['compensation'] = type;
                                  // Initialize Fixed Fee amount if Fixed Fee is selected
                                  if (type == 'Fixed Fee') {
                                    if (_projectManagerFixedFee[index] == null || _projectManagerFixedFee[index]!.isEmpty) {
                                      _projectManagerFixedFee[index] = '0';
                                      _projectManagers[index]['fixedFee'] = '0';
                                    }
                                    // Initialize controller if it doesn't exist
                                    if (_projectManagerFixedFeeControllers[index] == null) {
                                      _projectManagerFixedFeeControllers[index] = TextEditingController();
                                    }
                                  }
                                  // Initialize Monthly Fee amount if Monthly Fee is selected
                                  if (type == 'Monthly Fee') {
                                    if (_projectManagerMonthlyFee[index] == null || _projectManagerMonthlyFee[index]!.isEmpty) {
                                      _projectManagerMonthlyFee[index] = '0';
                                      _projectManagers[index]['monthlyFee'] = '0';
                                    }
                                    if (_projectManagerMonths[index] == null || _projectManagerMonths[index]!.isEmpty) {
                                      _projectManagerMonths[index] = '';
                                      _projectManagers[index]['months'] = '';
                                    }
                                    // Initialize controllers if they don't exist
                                    if (_projectManagerMonthlyFeeControllers[index] == null) {
                                      _projectManagerMonthlyFeeControllers[index] = TextEditingController();
                                    }
                                    if (_projectManagerMonthsControllers[index] == null) {
                                      final currentMonthsValue = _projectManagerMonths[index] ?? '';
                                      _projectManagerMonthsControllers[index] = TextEditingController(
                                        text: currentMonthsValue,
                                      );
                                    }
                                  }
                                } catch (e) {
                                  // If map is null, just update _projectManagers
                                  _projectManagers[index]['compensation'] = type;
                                  if (type == 'Fixed Fee') {
                                    _projectManagerFixedFee[index] = '0';
                                    _projectManagers[index]['fixedFee'] = '0';
                                    // Initialize controller if it doesn't exist
                                    if (_projectManagerFixedFeeControllers[index] == null) {
                                      _projectManagerFixedFeeControllers[index] = TextEditingController();
                                    }
                                  }
                                  if (type == 'Monthly Fee') {
                                    _projectManagerMonthlyFee[index] = '0';
                                    _projectManagers[index]['monthlyFee'] = '0';
                                    _projectManagerMonths[index] = '';
                                    _projectManagers[index]['months'] = '';
                                    // Initialize controllers if they don't exist
                                    if (_projectManagerMonthlyFeeControllers[index] == null) {
                                      _projectManagerMonthlyFeeControllers[index] = TextEditingController();
                                    }
                                    if (_projectManagerMonthsControllers[index] == null) {
                                      _projectManagerMonthsControllers[index] = TextEditingController(text: '');
                                    }
                                  }
                                }
                              });
                              _onDataChanged();
                              closeDropdown();
                            },
                            child: Container(
                              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                              alignment: Alignment.centerLeft,
                                child: Container(
                                  width: 149,
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected 
                                        ? const Color(0xFFB0D5F0) // Brighter, more blue
                                        : const Color(0xFFECF6FD),
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
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        type,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          color: Colors.black,
                                        ),
                                        textAlign: TextAlign.left,
                                        overflow: TextOverflow.visible,
                                        softWrap: true,
                                      ),
                                    ),
                                  ),
                                ),
                            ),
                          );
                        }).toList(),
                        // Add block selection option if earning type is "Per Plot"
                        if (_projectManagerEarningType[index] == 'Per Plot')
                          GestureDetector(
                            onTap: () {
                              closeDropdown();
                              Future.delayed(const Duration(milliseconds: 100), () {
                                _showBlockSelectionDropdown(context, index, cellKey);
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_box_outline_blank,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Select Blocks',
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

  void _showAgentEarningTypeDropdown(BuildContext context, int index, GlobalKey cellKey) {
    final RenderBox? renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
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
      builder: (context) {
        final compensationType = _agentCompensation[index] ?? '';
        final isPercentageBonus = compensationType == 'Percentage Bonus';
        final isFixedFee = compensationType == 'Fixed Fee';
        final earningTypesToShow = isPercentageBonus ? _percentageBonusEarningTypes : _earningTypes;
        
        return Positioned(
          left: offset.dx,
          top: offset.dy + 48,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: renderBox.size.width,
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
              child: isPercentageBonus
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.only(top: 4, left: 8, right: 8, bottom: 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Select the Earning Type',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.black,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Transform.rotate(
                                  angle: 180 * 3.14159 / 180,
                                  child: SvgPicture.asset(
                                    'assets/images/Drrrop_down.svg',
                                    width: 14,
                                    height: 7,
                                    fit: BoxFit.contain,
                                    placeholderBuilder: (context) => const SizedBox(
                                      width: 14,
                                      height: 7,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...earningTypesToShow.asMap().entries.map((entry) {
                                final typeIndex = entry.key;
                                final type = entry.value;
                                final isLast = typeIndex == earningTypesToShow.length - 1;
                                final currentEarningType = _agentEarningType[index] ?? '';
                                final isSelected = type == currentEarningType;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      try {
                                        _agentEarningType[index] = type;
                                        _agents[index]['earningType'] = type;
                                        if (isPercentageBonus && (_agentPercentage[index] == null || _agentPercentage[index]!.isEmpty)) {
                                          _agentPercentage[index] = '0';
                                          _agents[index]['percentage'] = '0';
                                        }
                                        if (isFixedFee && (_agentFixedFee[index] == null || _agentFixedFee[index]!.isEmpty)) {
                                          _agentFixedFee[index] = '0';
                                          _agents[index]['fixedFee'] = '0';
                                        }
                                      } catch (e) {
                                        _agents[index]['earningType'] = type;
                                        if (isPercentageBonus) {
                                          _agentPercentage[index] = '0';
                                          _agents[index]['percentage'] = '0';
                                        }
                                        if (isFixedFee) {
                                          _agentFixedFee[index] = '0';
                                          _agents[index]['fixedFee'] = '0';
                                        }
                                      }
                                    });
                                    _onDataChanged();
                                    closeDropdown();
                                  },
                                  child: Container(
                                    padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                                    alignment: Alignment.centerLeft,
                                    child: IntrinsicWidth(
                                      child: Container(
                                        height: 32,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected 
                                              ? const Color(0xFFB0D5F0)
                                              : const Color(0xFFECF6FD),
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
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              type,
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.normal,
                                                color: Colors.black,
                                              ),
                                              textAlign: TextAlign.left,
                                              overflow: TextOverflow.visible,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _earningTypes.map((type) {
                      final currentEarningType = _agentEarningType[index] ?? '';
                      final isSelected = type == currentEarningType;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            try {
                              _agentEarningType[index] = type;
                              _agents[index]['earningType'] = type;
                            } catch (e) {
                              _agents[index]['earningType'] = type;
                            }
                          });
                          _onDataChanged();
                          closeDropdown();
                        },
                        child: IntrinsicWidth(
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? const Color(0xFFB0D5F0)
                                  : const Color(0xFFECF6FD),
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
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  type,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.black,
                                  ),
                                  textAlign: TextAlign.left,
                                  overflow: TextOverflow.visible,
                                  softWrap: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
            ),
          ),
        );
      },
    );
    
    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
  }

  void _showEarningTypeDropdown(BuildContext context, int index, GlobalKey cellKey) {
    final RenderBox? renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
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
      builder: (context) {
        // Check if compensation type is "Percentage Bonus" or "Fixed Fee"
        final compensationType = _projectManagerCompensation[index] ?? '';
        final isPercentageBonus = compensationType == 'Percentage Bonus';
        final isFixedFee = compensationType == 'Fixed Fee';
        final earningTypesToShow = isPercentageBonus ? _percentageBonusEarningTypes : _earningTypes;
        
        return Positioned(
          left: offset.dx,
          top: offset.dy + 48,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: renderBox.size.width,
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
              child: isPercentageBonus
                  ? Padding(
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
                                    'Select the Earning Type',
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
                                  child: SvgPicture.asset(
                                    'assets/images/Drrrop_down.svg',
                                    width: 14,
                                    height: 7,
                                    fit: BoxFit.contain,
                                    placeholderBuilder: (context) => const SizedBox(
                                      width: 14,
                                      height: 7,
                                    ),
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
                                ...earningTypesToShow.asMap().entries.map((entry) {
                                final typeIndex = entry.key;
                                final type = entry.value;
                                final isLast = typeIndex == earningTypesToShow.length - 1;
                                final currentEarningType = _projectManagerEarningType[index] ?? '';
                                final isSelected = type == currentEarningType;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      try {
                                        _projectManagerEarningType[index] = type;
                                        _projectManagers[index]['earningType'] = type;
                                        // Initialize percentage value if it doesn't exist for percentage bonus types
                                        if (isPercentageBonus && (_projectManagerPercentage[index] == null || _projectManagerPercentage[index]!.isEmpty)) {
                                          _projectManagerPercentage[index] = '0';
                                          _projectManagers[index]['percentage'] = '0';
                                        }
                                        // Initialize Fixed Fee amount if it doesn't exist for Fixed Fee types
                                        if (isFixedFee && (_projectManagerFixedFee[index] == null || _projectManagerFixedFee[index]!.isEmpty)) {
                                          _projectManagerFixedFee[index] = '0';
                                          _projectManagers[index]['fixedFee'] = '0';
                                        }
                                      } catch (e) {
                                        // If map is null, just update _projectManagers
                                        _projectManagers[index]['earningType'] = type;
                                        if (isPercentageBonus) {
                                          _projectManagerPercentage[index] = '0';
                                          _projectManagers[index]['percentage'] = '0';
                                        }
                                        if (isFixedFee) {
                                          _projectManagerFixedFee[index] = '0';
                                          _projectManagers[index]['fixedFee'] = '0';
                                        }
                                      }
                                    });
                                    _onDataChanged();
                                    closeDropdown();
                                  },
                                  child: Container(
                                    padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                                    alignment: Alignment.centerLeft,
                                    child: IntrinsicWidth(
                                      child: Container(
                                        height: 32,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected 
                                              ? const Color(0xFFB0D5F0) // Brighter, more blue
                                              : const Color(0xFFECF6FD),
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
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              type,
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.normal,
                                                color: Colors.black,
                                              ),
                                              textAlign: TextAlign.left,
                                              overflow: TextOverflow.visible,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _earningTypes.map((type) {
                      final currentEarningType = _projectManagerEarningType[index] ?? '';
                      final isSelected = type == currentEarningType;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            try {
                              _projectManagerEarningType[index] = type;
                              _projectManagers[index]['earningType'] = type;
                              // If "Per Plot" is selected, show block selection
                              if (type == 'Per Plot') {
                                closeDropdown();
                                Future.delayed(const Duration(milliseconds: 100), () {
                                  _showBlockSelectionDropdown(context, index, cellKey);
                                });
                                return;
                              }
                            } catch (e) {
                              // If map is null, just update _projectManagers
                              _projectManagers[index]['earningType'] = type;
                            }
                          });
                          _onDataChanged();
                          closeDropdown();
                        },
                        child: IntrinsicWidth(
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? const Color(0xFFB0D5F0) // Brighter, more blue
                                  : const Color(0xFFECF6FD),
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
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  type,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black,
                                ),
                                textAlign: TextAlign.left,
                                overflow: TextOverflow.visible,
                                softWrap: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    }).toList(),
                  ),
            ),
          ),
        );
      },
    );
    
    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
  }

  void _showAgentPercentageInputDialog(BuildContext context, int index) {
    String currentValue = '0';
    try {
      currentValue = _agentPercentage[index] ?? '0';
    } catch (e) {
      currentValue = '0';
    }
    final controller = TextEditingController(text: currentValue == '0' ? '' : currentValue);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Enter Percentage',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter percentage value',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          style: GoogleFonts.inter(
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                final value = controller.text.isEmpty ? '0' : controller.text;
                try {
                  _agentPercentage[index] = value;
                } catch (e) {
                  _agentPercentage[index] = value;
                }
                try {
                  if (index < _agents.length) {
                    _agents[index]['percentage'] = value;
                  }
                } catch (e) {
                  print('Warning: Could not update _agents: $e');
                }
              });
              _onDataChanged();
              Navigator.of(context).pop();
            },
            child: Text(
              'Save',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBlockSelectionDropdown(BuildContext context, int projectManagerIndex, GlobalKey cellKey) {
    // Get all available blocks/plots from layouts
    List<String> availableBlocks = [];
    for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
      final layout = _layouts[layoutIndex];
      final plots = layout['plots'] as List<Map<String, dynamic>>? ?? [];
      final layoutName = _layoutNameControllers[layoutIndex]?.text ?? 
                        layout['name'] ?? 'Layout ${layoutIndex + 1}';
      
      for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
        final key = '${layoutIndex}_$plotIndex';
        final plotNumber = _plotNumberControllers[key]?.text ?? '';
        if (plotNumber.isNotEmpty) {
          availableBlocks.add('$layoutName - $plotNumber');
        } else {
          availableBlocks.add('$layoutName - Plot ${plotIndex + 1}');
        }
      }
    }

    if (availableBlocks.isEmpty) {
      // Show a message if no blocks are available
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No plots available. Please add plots in the Site/Layouts section first.',
            style: GoogleFonts.inter(fontSize: 14),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final RenderBox? renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final overlay = Overlay.of(context);
    final offset = renderBox.localToGlobal(Offset.zero);
    
    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;
    
    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
    }
    
    // Get currently selected blocks for this project manager
    List<String> currentlySelected = [];
    try {
      currentlySelected = _projectManagerSelectedBlocks[projectManagerIndex] ?? [];
    } catch (e) {
      currentlySelected = [];
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
        left: offset.dx,
        top: offset.dy + 48,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 365,
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.withOpacity(0.3), width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Blocks',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                        GestureDetector(
                          onTap: closeDropdown,
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Block options with checkboxes
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: availableBlocks.map((block) {
                        final isSelected = currentlySelected.contains(block);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              List<String> selected = [];
                              try {
                                if (_projectManagerSelectedBlocks != null) {
                                  selected = _projectManagerSelectedBlocks[projectManagerIndex] ?? [];
                                }
                              } catch (e) {
                                selected = [];
                              }
                              if (isSelected) {
                                selected.remove(block);
                              } else {
                                selected.add(block);
                              }
                              if (_projectManagerSelectedBlocks != null) {
                                _projectManagerSelectedBlocks[projectManagerIndex] = selected;
                              }
                            });
                            _onDataChanged();
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFECF6FD) : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF2196F3) : Colors.grey.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                  size: 20,
                                  color: isSelected ? const Color(0xFF2196F3) : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    block,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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

  // Helper method to safely get percentage value
  String _getPercentageValue(int index) {
    try {
      // Use a more defensive approach for web compilation
      final map = _projectManagerPercentage;
      if (map is Map<int, String>) {
        return map[index] ?? '0';
      }
    } catch (e) {
      // If any error occurs, return default
    }
    return '0';
  }

  // Helper method to safely set percentage value
  void _setPercentageValue(int index, String value) {
    try {
      // Use a more defensive approach for web compilation
      final map = _projectManagerPercentage;
      if (map is Map<int, String>) {
        map[index] = value;
      }
    } catch (e) {
      // If map is null or inaccessible, just skip the update
      print('Warning: Could not update percentage value: $e');
    }
  }

  void _showPercentageInputDialog(BuildContext context, int index) {
    // Safely get current value using helper method
    final currentValue = _getPercentageValue(index);
    final controller = TextEditingController(text: currentValue);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Enter Percentage',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter percentage value',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          style: GoogleFonts.inter(
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                // Safely update percentage value using helper method
                final value = controller.text.isEmpty ? '0' : controller.text;
                _setPercentageValue(index, value);
                // Also update _projectManagers if possible
                try {
                  if (index < _projectManagers.length) {
                    _projectManagers[index]['percentage'] = value;
                  }
                } catch (e) {
                  // If updating _projectManagers fails, just log it
                  print('Warning: Could not update _projectManagers: $e');
                }
              });
              _onDataChanged();
              Navigator.of(context).pop();
            },
            child: Text(
              'Save',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFixedFeeInputDialog(BuildContext context, int index) {
    // Safely get current value
    String currentValue = '0';
    try {
      currentValue = _projectManagerFixedFee[index] ?? '0';
    } catch (e) {
      currentValue = '0';
    }
    final controller = TextEditingController(text: currentValue == '0' ? '' : currentValue);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Enter Fixed Fee Amount',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter amount',
            prefixText: '₹ ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          style: GoogleFonts.inter(
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                // Safely update Fixed Fee value
                final value = controller.text.isEmpty ? '0' : controller.text;
                try {
                  _projectManagerFixedFee[index] = value;
                } catch (e) {
                  // If map is null, initialize it
                  _projectManagerFixedFee[index] = value;
                }
                // Also update _projectManagers if possible
                try {
                  if (index < _projectManagers.length) {
                    _projectManagers[index]['fixedFee'] = value;
                  }
                } catch (e) {
                  // If updating _projectManagers fails, just log it
                  print('Warning: Could not update _projectManagers: $e');
                }
              });
              _onDataChanged();
              Navigator.of(context).pop();
            },
            child: Text(
              'Save',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutCard(int layoutIndex, Map<String, dynamic> layout) {
    // Convert plots to proper type List<Map<String, dynamic>>
    final plotsData = layout['plots'];
    List<Map<String, dynamic>> plots;
    if (plotsData is List) {
      plots = plotsData.map((p) {
        if (p is Map<String, dynamic>) {
          return p;
        } else if (p is Map) {
          return Map<String, dynamic>.from(p);
        } else {
          return <String, dynamic>{};
        }
      }).toList();
    } else {
      plots = [];
    }
    
    final layoutNameController = _layoutNameControllers[layoutIndex] ?? 
        TextEditingController(text: layout['name'] ?? 'Layout ${layoutIndex + 1}');
    if (_layoutNameControllers[layoutIndex] == null) {
      _layoutNameControllers[layoutIndex] = layoutNameController;
    }

    // Calculate totals for this layout
    double totalArea = 0.0;
    double totalAllInCost = 0.0;
    double totalPlotCost = 0.0;
    // Calculate All-in Cost as Total Expenses / Approved selling area
    final allInCost = _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;
    
    int plotCount = 0;
    for (int i = 0; i < plots.length; i++) {
      final areaKey = '${layoutIndex}_$i';
      final areaController = _plotAreaControllers[areaKey];
      if (areaController != null) {
        final area = double.tryParse(areaController.text.replaceAll(',', '').replaceAll(' ', '')) ?? 0.0;
        totalArea += area;
        // Only count plots with area > 0
        if (area > 0) {
          plotCount++;
        }
        // Total Plot Cost for this plot = area * all-in cost
        totalPlotCost += area * allInCost;
      }
    }
    
    // Total All-in Cost = sum of all-in cost values in the column = all-in cost rate * number of plots
    totalAllInCost = allInCost * plotCount;

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
              const SizedBox(width: 8),
              Container(
                width: 304,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 2,
                      offset: const Offset(0, 0),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    TextField(
                      controller: layoutNameController,
                      textAlign: TextAlign.left,
                      onChanged: (value) {
                        _layouts[layoutIndex]['name'] = value;
                        setState(() {});
                        _onDataChanged();
                      },
                      decoration: InputDecoration(
                        hintText: '',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        isDense: true,
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                    if (layoutNameController.text.isEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Enter Layout name or number',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black.withOpacity(0.8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Plots table
          Builder(
            builder: (context) {
              // Ensure scroll controller exists for this layout
              if (!_plotsTableScrollControllers.containsKey(layoutIndex)) {
                _plotsTableScrollControllers[layoutIndex] = ScrollController();
              }
              return Scrollbar(
                controller: _plotsTableScrollControllers[layoutIndex],
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _plotsTableScrollControllers[layoutIndex],
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: _buildPlotsTable(layoutIndex, plots),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Add Plot button
          GestureDetector(
            onTap: () {
              setState(() {
                final newPlotIndex = plots.length;
                // Create a new list to ensure state update is detected
                final updatedPlots = List<Map<String, dynamic>>.from(plots);
                updatedPlots.add({
                  'plotNumber': '',
                  'area': '0.00',
                  'purchaseRate': '0.00',
                  'totalPlotCost': '0.00',
                  'partner': '',
                });
                // Update the layout with the new plots list
                _layouts[layoutIndex]['plots'] = updatedPlots;
                final key = '${layoutIndex}_$newPlotIndex';
                _plotNumberControllers[key] = TextEditingController();
                _plotAreaControllers[key] = TextEditingController();
                _plotPurchaseRateControllers[key] = TextEditingController();
              });
              _onDataChanged();
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    'Add Plot',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SvgPicture.asset(
                    'assets/images/Cretae_new_projet_white.svg',
                    width: 12,
                    height: 12,
                    fit: BoxFit.contain,
                    placeholderBuilder: (context) => const SizedBox(
                      width: 12,
                      height: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Summary section
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Total Area: ',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '${_formatAmountForDisplay(totalArea)} sqft',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Total All-in Cost: ',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '₹ ${_formatAmountForDisplay(totalAllInCost, decimalPlaces: 3)}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Total Plot Cost: ',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '₹ ${_formatAmountForDisplay(totalPlotCost, decimalPlaces: 3)}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlotsTable(int layoutIndex, List<Map<String, dynamic>> plots) {
    // Ensure at least one plot row is always shown - add default plot to layout if empty
    if (plots.isEmpty) {
      final defaultPlot = {
        'plotNumber': '',
        'area': '0.00',
        'purchaseRate': '0.00',
        'totalPlotCost': '0.00',
        'partner': '',
        'partners': [],
      };
      _layouts[layoutIndex]['plots'] = [defaultPlot];
      plots = [defaultPlot];
      // Initialize controllers for the default plot
      final plotKey = '${layoutIndex}_0';
      if (_plotNumberControllers[plotKey] == null) {
        _plotNumberControllers[plotKey] = TextEditingController();
      }
      if (_plotAreaControllers[plotKey] == null) {
        _plotAreaControllers[plotKey] = TextEditingController();
      }
      if (_plotPurchaseRateControllers[plotKey] == null) {
        _plotPurchaseRateControllers[plotKey] = TextEditingController();
      }
      if (_plotPartners[plotKey] == null) {
        _plotPartners[plotKey] = [];
      }
    }
    
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        // Sl. No. column
        Column(
          children: [
            Container(
              width: 60,
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
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            ...List.generate(plots.length, (index) {
              final isLast = index == plots.length - 1;
              final key = '${layoutIndex}_$index';
              final selectedPartners = _plotPartners[key] ?? [];
              // Calculate dynamic height to match Partner(s) column
              final dynamicHeight = selectedPartners.isEmpty || selectedPartners.length == 1
                  ? 48.0
                  : 48.0 + (selectedPartners.length - 1) * 36.0;
              return Container(
                width: 60,
                height: dynamicHeight,
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Plot Number column
        Column(
          children: [
            Container(
              width: 186,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Plot Number ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            ...List.generate(plots.length, (index) {
              final isLast = index == plots.length - 1;
              final key = '${layoutIndex}_$index';
              final selectedPartners = _plotPartners[key] ?? [];
              // Calculate dynamic height to match Partner(s) column
              final dynamicHeight = selectedPartners.isEmpty || selectedPartners.length == 1
                  ? 48.0
                  : 48.0 + (selectedPartners.length - 1) * 36.0;
              final controller = _plotNumberControllers[key] ?? TextEditingController();
              if (_plotNumberControllers[key] == null) {
                _plotNumberControllers[key] = controller;
              }
              final plotNumberEmpty = controller.text.trim().isEmpty || 
                                      (plots[index]['plotNumber']?.toString().trim().isEmpty ?? true);
              return Container(
                width: 186,
                height: dynamicHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 170,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: plotNumberEmpty ? Colors.red : Colors.black.withOpacity(0.15),
                              blurRadius: 2,
                              offset: const Offset(0, 0),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: controller,
                          textAlignVertical: TextAlignVertical.center,
                          onChanged: (value) {
                            plots[index]['plotNumber'] = value;
                            setState(() {}); // Update shadow color
                            _onDataChanged();
                          },
                          decoration: InputDecoration(
                            hintText: 'Enter Plot Number',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                              color: const Color(0xFF5C5C5C),
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        // Area column
        Column(
          children: [
            Container(
              width: 215,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Area (sqft) ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            ...List.generate(plots.length, (index) {
              final key = '${layoutIndex}_$index';
              final selectedPartners = _plotPartners[key] ?? [];
              // Calculate dynamic height to match Partner(s) column
              final dynamicHeight = selectedPartners.isEmpty || selectedPartners.length == 1
                  ? 48.0
                  : 48.0 + (selectedPartners.length - 1) * 36.0;
              final controller = _plotAreaControllers[key] ?? TextEditingController();
              if (_plotAreaControllers[key] == null) {
                _plotAreaControllers[key] = controller;
              }
              final cleanedAreaText = controller.text.replaceAll(',', '').replaceAll(' ', '').trim();
              final areaIsEmpty = cleanedAreaText.isEmpty || cleanedAreaText == '0' || cleanedAreaText == '0.00';
              final areaEmpty = areaIsEmpty || (plots[index]['area']?.toString().trim().isEmpty ?? true) || plots[index]['area'] == '0.00';
              return Container(
                width: 215,
                height: dynamicHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
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
                              color: areaEmpty ? Colors.red : Colors.black.withOpacity(0.15),
                              blurRadius: 2,
                              offset: const Offset(0, 0),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Builder(
                          builder: (context) {
                            final cleanedText = controller.text.replaceAll(',', '').replaceAll(' ', '').trim();
                            final isEmpty = cleanedText.isEmpty || cleanedText == '0' || cleanedText == '0.00';
                            return SizedBox(
                              height: 32,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 20,
                                    child: Center(
                                      child: Text(
                                        'sqft ',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.normal,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: DecimalInputField(
                                      controller: controller,
                                      hintText: '0.00',
                                      inputFormatters: [IndianNumberFormatter()],
                                      onTap: () {
                                        // Clear '0.00' when field is tapped
                                        final cleaned = controller.text.replaceAll(',', '').replaceAll(' ', '').trim();
                                        if (cleaned == '0' || cleaned == '0.00') {
                                          controller.text = '';
                                          controller.selection = TextSelection.collapsed(offset: 0);
                                          setState(() {});
                                        }
                                      },
                                      onChanged: (value) {
                                        final cleaned = value.replaceAll(',', '').replaceAll(' ', '');
                                        plots[index]['area'] = cleaned.isEmpty ? '0.00' : cleaned;
                                        setState(() {}); // Recalculate totals and update shadow
                                        _onDataChanged();
                                      },
                                      onEditingComplete: () {
                                        // Remove commas before formatting
                                        final cleaned = controller.text.replaceAll(',', '').replaceAll(' ', '').trim();
                                        final formatted = _formatAmount(cleaned);
                                        controller.text = formatted;
                                        plots[index]['area'] = formatted.replaceAll(',', '');
                                        setState(() {});
                                        _onDataChanged();
                                        FocusScope.of(context).nextFocus();
                                      },
                                      onTapOutside: () {
                                        // Remove commas before formatting
                                        final cleaned = controller.text.replaceAll(',', '').replaceAll(' ', '').trim();
                                        final formatted = _formatAmount(cleaned);
                                        controller.text = formatted;
                                        plots[index]['area'] = formatted.replaceAll(',', '');
                                        setState(() {});
                                        _onDataChanged();
                                      },
                                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        // All-in Cost (₹/sqft) column - calculated
        Column(
          children: [
            Container(
              width: 215,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Text(
                  'All-in Cost (₹/sqft)',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            ...List.generate(plots.length, (index) {
              final key = '${layoutIndex}_$index';
              final selectedPartners = _plotPartners[key] ?? [];
              // Calculate dynamic height to match Partner(s) column
              final dynamicHeight = selectedPartners.isEmpty || selectedPartners.length == 1
                  ? 48.0
                  : 48.0 + (selectedPartners.length - 1) * 36.0;
              // Calculate All-in Cost as Total Expenses / Approved selling area
              final allInCost = _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;
              final isEmpty = allInCost == 0.0;
              return Container(
                width: 215,
                height: dynamicHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: double.infinity,
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
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                          ),
                          children: [
                            const TextSpan(text: '₹/sqft '),
                            TextSpan(
                              text: isEmpty ? '0.00' : _formatAmountForDisplay(allInCost, decimalPlaces: 5),
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: isEmpty ? const Color(0xFF5D5D5D) : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Total Plot Cost (₹) column
        Column(
          children: [
            Container(
              width: 215,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Text(
                  'Total Plot Cost (₹)',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            ...List.generate(plots.length, (index) {
              final key = '${layoutIndex}_$index';
              final selectedPartners = _plotPartners[key] ?? [];
              // Calculate dynamic height to match Partner(s) column
              final dynamicHeight = selectedPartners.isEmpty || selectedPartners.length == 1
                  ? 48.0
                  : 48.0 + (selectedPartners.length - 1) * 36.0;
              
              // Get Area (column 3) and All-in Cost (column 4) to calculate Total Plot Cost
              final areaController = _plotAreaControllers[key];
              final area = double.tryParse(areaController?.text.replaceAll(',', '').replaceAll(' ', '').trim() ?? '0') ?? 0.0;
              
              // Calculate All-in Cost as Total Expenses / Approved selling area
              final allInCost = _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;
              
              // Total Plot Cost = Area * All-in Cost
              final totalPlotCost = area * allInCost;
              
              return Container(
                width: 215,
                height: dynamicHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: double.infinity,
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
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                          ),
                          children: [
                            const TextSpan(text: '₹ '),
                            TextSpan(
                              text: totalPlotCost == 0.0 ? '0.000' : _formatAmountForDisplay(totalPlotCost, decimalPlaces: 3),
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: totalPlotCost == 0.0 ? const Color(0xFF5D5D5D) : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Partner(s) column
        Column(
          children: [
            Container(
              width: 241,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Partner(s) ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            ...List.generate(plots.length, (index) {
              final isLast = index == plots.length - 1;
              final key = '${layoutIndex}_$index';
              final selectedPartners = _plotPartners[key] ?? [];
              final partnerCellKey = GlobalKey();
              final partnersEmpty = selectedPartners.isEmpty;
              // Calculate dynamic height: base 48px + ~36px per additional partner
              // Accounts for text height (~20px) + spacing (16px) + padding
              final dynamicHeight = selectedPartners.isEmpty || selectedPartners.length == 1
                  ? 48.0
                  : 48.0 + (selectedPartners.length - 1) * 36.0;
              return Container(
                key: partnerCellKey,
                width: 241,
                height: dynamicHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: () {
                          // Show partner selection dropdown
                          _showPartnerDropdown(context, layoutIndex, index, key, partnerCellKey);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: partnersEmpty ? Colors.red : Colors.black.withOpacity(0.15),
                                blurRadius: 2,
                                offset: const Offset(0, 0),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        child: selectedPartners.isEmpty
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Select Partner(s)',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: const Color(0xFF5C5C5C),
                                      ),
                                    ),
                                  ),
                                  SvgPicture.asset(
                                    'assets/images/Drrrop_down.svg',
                                    width: 14,
                                    height: 7,
                                    fit: BoxFit.contain,
                                    placeholderBuilder: (context) => const SizedBox(
                                      width: 14,
                                      height: 7,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        ...selectedPartners.asMap().entries.map((entry) {
                                          final partnerIndex = entry.key;
                                          final partnerName = entry.value;
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              bottom: partnerIndex < selectedPartners.length - 1 ? 16 : 0,
                                            ),
                                            child: Text(
                                              partnerName,
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.inter(
                                                fontSize: 16,
                                                fontWeight: FontWeight.normal,
                                                color: Colors.black,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  SvgPicture.asset(
                                    'assets/images/Drrrop_down.svg',
                                    width: 14,
                                    height: 7,
                                    fit: BoxFit.contain,
                                    placeholderBuilder: (context) => const SizedBox(
                                      width: 14,
                                      height: 7,
                                    ),
                                  ),
                                ],
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        // Remove column
        Column(
          children: [
            // Spacer to align Remove buttons with plot data rows
            const SizedBox(
              width: 120,
              height: 47,
            ),
            // Rows with Remove buttons
            ...List.generate(plots.length, (index) {
              final isLast = index == plots.length - 1;
              final key = '${layoutIndex}_$index';
              final selectedPartners = _plotPartners[key] ?? [];
              // Calculate dynamic height to match Partner(s) column
              final dynamicHeight = selectedPartners.isEmpty || selectedPartners.length == 1
                  ? (index == 0 ? 49.0 : 48.0)
                  : (index == 0 ? 49.0 : 48.0) + (selectedPartners.length - 1) * 36.0;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      final key = '${layoutIndex}_$index';
                      _plotNumberControllers[key]?.dispose();
                      _plotAreaControllers[key]?.dispose();
                      _plotPurchaseRateControllers[key]?.dispose();
                      _plotNumberControllers.remove(key);
                      _plotAreaControllers.remove(key);
                      _plotPurchaseRateControllers.remove(key);
                      _plotPartners.remove(key);
                      plots.removeAt(index);
                      // Update the layout's plots list to ensure persistence
                      _layouts[layoutIndex]['plots'] = plots;
                      // Reindex remaining plots
                      for (int i = index; i < plots.length; i++) {
                        final oldKey = '${layoutIndex}_${i + 1}';
                        final newKey = '${layoutIndex}_$i';
                        if (_plotNumberControllers.containsKey(oldKey)) {
                          _plotNumberControllers[newKey] = _plotNumberControllers.remove(oldKey)!;
                          _plotAreaControllers[newKey] = _plotAreaControllers.remove(oldKey)!;
                          _plotPurchaseRateControllers[newKey] = _plotPurchaseRateControllers.remove(oldKey)!;
                          _plotPartners[newKey] = _plotPartners.remove(oldKey) ?? [];
                        }
                      }
                    });
                    _onDataChanged();
                  },
                  child: Container(
                    width: 120,
                    height: dynamicHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: index == 0
                            ? const BorderSide(color: Colors.black, width: 1.0)
                            : BorderSide.none,
                        right: const BorderSide(color: Colors.black, width: 1.0),
                        bottom: const BorderSide(color: Colors.black, width: 1.0),
                        left: BorderSide.none,
                      ),
                      borderRadius: index == 0 && isLast
                          ? const BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            )
                          : (index == 0
                              ? const BorderRadius.only(
                                  topRight: Radius.circular(8),
                                )
                              : (isLast
                                  ? const BorderRadius.only(
                                      bottomRight: Radius.circular(8),
                                    )
                                  : null)),
                    ),
                    child: Center(
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                        child: Center(
                          child: Text(
                            'Remove',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
      ),
    );
  }

  void _showPartnerDropdown(BuildContext context, int layoutIndex, int plotIndex, String key, GlobalKey cellKey) {
    // Get available partners (filter out empty names)
    final availablePartners = _partners
        .where((partner) => partner['name']?.toString().trim().isNotEmpty == true)
        .map((partner) => partner['name']?.toString().trim() ?? '')
        .toList();

    if (availablePartners.isEmpty) {
      return;
    }

    final RenderBox? renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // Get the cell's position using localToGlobal - this is the actual cell being clicked
    final cellOffset = renderBox.localToGlobal(Offset.zero);
    
    // Use fixed column width (241px) for dropdown size calculation
    const double cellWidth = 241.0; // Partner column width is fixed at 241px
    
    final overlay = Overlay.of(context);
    
    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;
    
    // Function to close both overlays
    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
    }
    
    // Create backdrop
    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeDropdown,
          child: Container(color: Colors.transparent),
        ),
      ),
    );
    
    // Create dropdown menu positioned relative to the partner cell
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: cellOffset.dx - 40, // Moved 4px to the left
        top: cellOffset.dy + 4, // Position 4px below the row's top border
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 320, // Fixed width of 320px
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
            child: StatefulBuilder(
              builder: (context, setOverlayState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select Partner(s)',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: closeDropdown,
                            child: Transform.rotate(
                              angle: 3.14159, // 180 degrees in radians (π)
                              child: SvgPicture.asset(
                                'assets/images/Drrrop_down.svg',
                                width: 14,
                                height: 7,
                                fit: BoxFit.contain,
                                placeholderBuilder: (context) => const SizedBox(
                                  width: 14,
                                  height: 7,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Scrollable partner list
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...availablePartners.map((partnerName) {
                              final selectedPartners = _plotPartners[key] ?? [];
                              final isSelected = selectedPartners.contains(partnerName);
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    final currentPartners = _plotPartners[key] ?? [];
                                    if (isSelected) {
                                      // Remove partner if already selected
                                      currentPartners.remove(partnerName);
                                      _plotPartners[key] = currentPartners;
                                    } else {
                                      // Add partner if not selected
                                      _plotPartners[key] = [...currentPartners, partnerName];
                                    }
                                    print('DEBUG: Partner selection changed for plot $key. Partners now: ${_plotPartners[key]}');
                                  });
                                  setState(() {}); // Update UI to reflect red shadow changes
                                  _onDataChanged();
                                  print('DEBUG: _onDataChanged() called after partner selection for plot $key');
                                  // Update overlay to reflect the new selection state
                                  setOverlayState(() {});
                                },
                                child: Container(
                                  height: 48,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: double.infinity,
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8F9FA),
                                        borderRadius: BorderRadius.circular(4),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: const Color(0xFF0C8CE9),
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 0),
                                                  spreadRadius: 0,
                                                ),
                                              ]
                                            : [
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
                                          partnerName,
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
  }

  Widget _buildExpensesTable() {
    final expenses = _expenses;
    if (expenses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Scrollbar(
      controller: _expensesTableScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _expensesTableScrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sl. No. column
        Column(
          children: [
            // Header
            Container(
              width: 60,
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
            ...List.generate(expenses.length, (index) {
              final isLast = index == expenses.length - 1;
              return Container(
                width: 60,
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }),
          ],
        ),
        // Expenses Item column
        Column(
          children: [
            // Header
            Container(
              width: 320,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        'Expenses Item ',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        '*',
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
            // Rows
            ...List.generate(expenses.length, (index) {
              final isLast = index == expenses.length - 1;
              final isFirstRow = index == 0;
              
              return Container(
                width: 320,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
                    child: TextField(
                      controller: _expenseItemControllers[index],
                      textAlignVertical: TextAlignVertical.center,
                      textAlign: TextAlign.left,
                      enabled: !isFirstRow,
                      readOnly: isFirstRow,
                      onChanged: (value) {
                        if (!isFirstRow) {
                          setState(() {
                            _expenses[index]['item'] = value;
                            // Only create controller if it doesn't exist, don't update text here
                            if (_expenseItemControllers[index] == null) {
                              _expenseItemControllers[index] = TextEditingController(text: value);
                            }
                            // Don't update controller.text here - it's already bound to the TextField
                          });
                          _onDataChanged();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter a name',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color.fromARGB(191, 173, 173, 173),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.only(left: 8, top: 11),
                        isDense: true,
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Amount column
        Column(
          children: [
            // Header
            Container(
              width: 294,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF707070).withOpacity(0.2),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1.0),
                  right: BorderSide(color: Colors.black, width: 1.0),
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Amount (₹) ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            // Rows
            ...List.generate(expenses.length, (index) {
              final isLast = index == expenses.length - 1;
              return Container(
                width: 294,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '₹',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF5D5D5D),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              // Ensure controller exists
                              if (_expenseAmountControllers[index] == null) {
                                _expenseAmountControllers[index] = TextEditingController();
                              }
                              return DecimalInputField(
                                controller: _expenseAmountControllers[index]!,
                                hintText: '0.00',
                                inputFormatters: [IndianNumberFormatter()],
                                onTap: () {
                                  // Clear '0.00' when field is tapped
                                  final cleaned = _expenseAmountControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
                                  if (cleaned == '0' || cleaned == '0.00') {
                                    _expenseAmountControllers[index]!.text = '';
                                    _expenseAmountControllers[index]!.selection = TextSelection.collapsed(offset: 0);
                                    setState(() {});
                                  }
                                },
                                onChanged: (value) {
                                  // Remove commas for storage (for real-time calculations)
                                  final rawValue = value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
                                  setState(() {
                                    _expenses[index]['amount'] = rawValue.isEmpty ? '0.00' : rawValue;
                                  });
                                  _onDataChanged();
                                },
                                onEditingComplete: () {
                                  // Remove commas before formatting
                                  final cleaned = _expenseAmountControllers[index]!.text.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '');
                                  final formatted = _formatAmount(cleaned);
                                  _expenseAmountControllers[index]!.text = formatted;
                                  setState(() {
                                    _expenses[index]['amount'] = formatted.replaceAll(',', '');
                                  });
                                  _onDataChanged();
                                  FocusScope.of(context).nextFocus();
                                },
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Category column
        Column(
          children: [
            // Header
            Container(
              width: 300,
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
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Category ',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '*',
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
            // Rows
            ...List.generate(expenses.length, (index) {
              final isLast = index == expenses.length - 1;
              final isFirstRow = index == 0;
              final selectedCategory = (_expenses[index]['category']?.toString() ?? '').trim();
              final hasCategory = selectedCategory.isNotEmpty;
              return Container(
                width: 300,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    top: BorderSide.none,
                    left: BorderSide.none,
                  ),
                ),
                child: Center(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Builder(
                      builder: (builderContext) {
                        final key = GlobalKey();
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: isFirstRow ? null : () {
                                  _showCategoryDropdown(builderContext, index, key);
                                },
                                child: hasCategory
                                    ? IntrinsicWidth(
                                        child: Container(
                                          key: key,
                                          height: 32,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: _getCategoryColor(selectedCategory),
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
                                              selectedCategory,
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.normal,
                                                color: Colors.black,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      )
                                    : IntrinsicWidth(
                                        child: Container(
                                          key: key,
                                          height: 32,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8F9FA),
                                            borderRadius: BorderRadius.circular(4),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.red,
                                                blurRadius: 2,
                                                offset: const Offset(0, 0),
                                                spreadRadius: 0,
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Select category',
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
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: isFirstRow ? null : () {
                                _showCategoryDropdown(builderContext, index, key);
                              },
                              child: SvgPicture.asset(
                                hasCategory
                                    ? 'assets/images/Drrrop_down.svg'
                                    : 'assets/images/non_chosen_drop_down.svg',
                                width: 14,
                                height: 7,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        // Remove column
        Column(
          children: [
            // Spacer to align Remove buttons with expense data rows
            const SizedBox(
              width: 120,
              height: 47,
            ),
            // Rows with Remove buttons
            ...List.generate(expenses.length, (index) {
              final isLast = index == expenses.length - 1;
              final isFirstRow = index == 0;
              return Container(
                width: 120,
                height: isFirstRow ? 49 : 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: index == 0
                        ? const BorderSide(color: Colors.black, width: 1.0)
                        : BorderSide.none,
                    right: const BorderSide(color: Colors.black, width: 1.0),
                    bottom: const BorderSide(color: Colors.black, width: 1.0),
                    left: BorderSide.none,
                  ),
                  borderRadius: index == 0 && isLast
                      ? const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        )
                      : (index == 0
                          ? const BorderRadius.only(
                              topRight: Radius.circular(8),
                            )
                          : (isLast
                              ? const BorderRadius.only(
                                  bottomRight: Radius.circular(8),
                                )
                              : null)),
                ),
                child: Center(
                  child: GestureDetector(
                    onTap: isFirstRow ? null : () {
                      if (_expenses.length > 1) {
                        setState(() {
                          _expenseItemControllers[index]?.dispose();
                          _expenseAmountControllers[index]?.dispose();
                          _expenses.removeAt(index);
                          // Rebuild controllers maps
                          final oldItemControllers = Map<int, TextEditingController>.from(_expenseItemControllers);
                          final oldAmountControllers = Map<int, TextEditingController>.from(_expenseAmountControllers);
                          _expenseItemControllers.clear();
                          _expenseAmountControllers.clear();
                          for (int i = 0; i < _expenses.length; i++) {
                            if (i < index) {
                              _expenseItemControllers[i] = oldItemControllers[i]!;
                              _expenseAmountControllers[i] = oldAmountControllers[i]!;
                            } else {
                              _expenseItemControllers[i] = oldItemControllers[i + 1]!;
                              _expenseAmountControllers[i] = oldAmountControllers[i + 1]!;
                            }
                          }
                        });
                        _onDataChanged();
                      }
                    },
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                      child: Center(
                        child: Text(
                          'Remove',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: isFirstRow ? Colors.grey : Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
        ),
      ),
    );
  }

  void _showCategoryDropdown(BuildContext context, int index, GlobalKey key) {
    final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // Get the parent container (the category cell) to position relative to it
    final parentRenderBox = renderBox.parent as RenderBox?;
    if (parentRenderBox == null) return;
    
    // Use fixed column width (300px) for dropdown size calculation
    // This ensures dropdown maintains its size regardless of the smaller block inside
    const double cellWidth = 300.0; // Column width is fixed at 300px
    
    final parentOffset = parentRenderBox.localToGlobal(Offset.zero);
    final parentSize = parentRenderBox.size;
    final fieldOffset = renderBox.localToGlobal(Offset.zero);
    final overlay = Overlay.of(context);
    
    // Get screen size to determine if dropdown should show above or below
    final screenSize = MediaQuery.of(context).size;
    
    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;
    
    // Function to close both overlays
    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
    }
    
    // Create backdrop
    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeDropdown,
          child: Container(color: Colors.transparent),
        ),
      ),
    );
    
    // Always show dropdown below the row
    final dropdownHeight = 400.0; // Max height of dropdown
    final topPosition = parentOffset.dy + 4; // Show 4px from the row's top border
    
    // Ensure dropdown stays within viewport bounds horizontally
    double leftPosition = parentOffset.dx - 4;
    final dropdownWidth = cellWidth * 0.93;
    
    if (leftPosition + dropdownWidth > screenSize.width) {
      leftPosition = screenSize.width - dropdownWidth - 8;
    }
    if (leftPosition < 0) {
      leftPosition = 8;
    }
    
    // Calculate remaining space below for dropdown
    final spaceBelow = screenSize.height - topPosition;
    final maxDropdownHeight = min(dropdownHeight, spaceBelow - 8);
    
    // Create dropdown menu
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: leftPosition,
        top: topPosition,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dropdownWidth,
            constraints: BoxConstraints(
              maxHeight: maxDropdownHeight,
            ),
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Header row with "Select category" and dropdown icon
                  Container(
                    padding: const EdgeInsets.only(top: 4, left: 8, right: 8, bottom: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Text(
                            'Select category',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Transform.rotate(
                          angle: 180 * 3.14159 / 180, // Rotate 180 degrees (90 more than before)
                          child: SvgPicture.asset(
                            'assets/images/Drrrop_down.svg',
                            width: 14,
                            height: 7,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Category options
                  ..._expenseCategories.map((category) {
                    final categoryColor = _getCategoryColor(category);
                    
                    return GestureDetector(
                      onTap: () {
                        closeDropdown();
                        setState(() {
                          _expenses[index]['category'] = category;
                        });
                        _onDataChanged();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        alignment: Alignment.centerLeft,
                        child: IntrinsicWidth(
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: categoryColor,
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
                              category,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.left,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              ),
          ),
        ),
      ),
    );
    
    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
    
    // Auto-scroll to ensure dropdown is fully visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Find the nearest Scrollable widget (main page vertical scroll)
        Scrollable.ensureVisible(
          key.currentContext ?? context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.3, // Position the row near top to leave room for dropdown below
        );
      } catch (e) {
        // Silently fail if scrolling isn't possible
      }
    });
  }

}

// Custom widget for focus-aware input containers
class _FocusAwareInputContainer extends StatefulWidget {
  final FocusNode focusNode;
  final Widget child;
  final VoidCallback? onFocusLost;
  final double width;
  final double height;
  final Color backgroundColor;
  final double borderRadius;

  const _FocusAwareInputContainer({
    required this.focusNode,
    required this.child,
    this.onFocusLost,
    this.width = double.infinity,
    this.height = 40,
    this.backgroundColor = const Color(0xFFF8F9FA),
    this.borderRadius = 8,
  });

  @override
  State<_FocusAwareInputContainer> createState() =>
      _FocusAwareInputContainerState();
}

class _FocusAwareInputContainerState extends State<_FocusAwareInputContainer> {
  late VoidCallback _focusListener;
  bool _hadFocus = false;

  @override
  void initState() {
    super.initState();
    _hadFocus = widget.focusNode.hasFocus;
    _focusListener = () {
      // Call onFocusLost when focus changes from true to false
      if (_hadFocus && !widget.focusNode.hasFocus && widget.onFocusLost != null) {
        widget.onFocusLost!();
      }
      _hadFocus = widget.focusNode.hasFocus;
      setState(() {});
    };
    widget.focusNode.addListener(_focusListener);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focusListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: widget.focusNode.hasFocus
                ? const Color(0xFF0C8CE9) // Focus color: #0C8CE9 (solid blue)
                : Colors.black.withOpacity(0.15), // Default color
            blurRadius: 2,
            offset: const Offset(0, 0),
            spreadRadius: 0,
          ),
        ],
      ),
      child: widget.child,
    );
  }
}

