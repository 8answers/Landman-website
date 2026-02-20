import 'package:http/http.dart' as http;
import 'dart:html' as html;
import 'dart:async';
import 'dart:math' show min;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/project_save_status.dart';
import '../widgets/decimal_input_field.dart';
import '../services/layout_storage_service.dart';
import '../services/project_storage_service.dart';
import '../services/area_unit_service.dart';
import '../utils/area_unit_utils.dart';
import '../widgets/app_scale_metrics.dart';
import '../widgets/area_unit_selector.dart';

// TextInputFormatter for Indian numbering system (commas every 2 digits)(whole)
class IndianNumberFormatter extends TextInputFormatter {
  final int? maxIntegerDigits;

  IndianNumberFormatter({this.maxIntegerDigits});

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

    if (cleaned.isEmpty || (cleaned == '.' && oldValue.text.isNotEmpty)) {
      return oldValue;
    }

    // Only allow one decimal point
    final parts = cleaned.split('.');
    if (parts.length > 2) {
      cleaned = '${parts[0]}.${parts.sublist(1).join()}';
    }

    // Limit integer part length if maxIntegerDigits is specified
    if (maxIntegerDigits != null) {
      final integerPart = parts[0];
      if (integerPart.length > maxIntegerDigits!) {
        return oldValue; // Reject the input if it exceeds max digits
      }
    }

    // Limit decimal places to 3
    if (parts.length == 2 && parts[1].length > 3) {
      cleaned = '${parts[0]}.${parts[1].substring(0, 3)}';
    }

    // Split into integer and decimal parts
    String integerPart;
    String decimalPart = '';

    if (cleaned.contains('.')) {
      final splitParts = cleaned.split('.');
      integerPart = splitParts[0].isEmpty ? '0' : splitParts[0];
      decimalPart = splitParts.length > 1 ? splitParts[1] : '';
    } else {
      integerPart = cleaned.isEmpty ? '0' : cleaned;
    }

    // Format integer part with Indian numbering
    String formattedInteger = '';

    if (integerPart.isEmpty || integerPart == '0') {
      formattedInteger = integerPart.isEmpty ? '0' : integerPart;
    } else if (integerPart.length <= 3) {
      formattedInteger = integerPart;
    } else {
      final length = integerPart.length;
      final lastThreeDigits = integerPart.substring(length - 3);
      final remaining = integerPart.substring(0, length - 3);
      final remainingReversed = remaining.split('').reversed.join();
      final formattedRemaining = RegExp(r'.{1,2}')
          .allMatches(remainingReversed)
          .map((m) => m.group(0)!)
          .toList()
          .join(',')
          .split('')
          .reversed
          .join('');

      formattedInteger = formattedRemaining.isEmpty
          ? lastThreeDigits
          : '$formattedRemaining,$lastThreeDigits';
    }

    String formattedText = cleaned.contains('.')
        ? '$formattedInteger.${decimalPart}'
        : formattedInteger;

    // Calculate cursor position
    int cursorPosition = formattedText.length;
    int unformattedLength = newValue.selection.baseOffset;
    int commaCount = 0;
    int charCount = 0;

    for (int i = 0;
        i < formattedText.length && charCount < unformattedLength;
        i++) {
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

// TextInputFormatter for percentage (0-100, only allows 3 digits for exactly 100)
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

    // Reject invalid 3rd digit input; only allow 3 digits when value is exactly 100
    if (cleaned.length > 3) {
      return oldValue;
    }
    if (cleaned.length == 3 && cleaned != '100') {
      return oldValue;
    }
    if (cleaned.isNotEmpty) {
      final value = int.tryParse(cleaned) ?? 0;
      if (value > 100) {
        return oldValue;
      }
    }

    // Preserve cursor position - calculate the new cursor position
    int cursorPosition = newValue.selection.baseOffset;
    // Adjust cursor position based on how many characters were removed
    int removedChars = newValue.text.length - cleaned.length;
    cursorPosition = (cursorPosition - removedChars).clamp(0, cleaned.length);

    // If cursor was at the end before, keep it at the end
    if (newValue.selection.baseOffset >= newValue.text.length) {
      cursorPosition = cleaned.length;
    }

    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cursorPosition),
    );
  }
}

class ProjectDetailsPage extends StatefulWidget {
  final String? initialProjectName;
  final String? projectId;
  final Function(ProjectSaveStatusType)? onSaveStatusChanged;
  final Function(bool)? onErrorStateChanged;
  final Function(bool)? onAreaErrorsChanged;
  final Function(bool)? onPartnerErrorsChanged;
  final Function(bool)? onExpenseErrorsChanged;
  final Function(bool)? onSiteErrorsChanged;
  final Function(bool)? onProjectManagerErrorsChanged;
  final Function(bool)? onAgentErrorsChanged;
  final Function(bool)? onPlotStatusErrorsChanged;
  final Function(bool)? onAboutErrorsChanged;

  const ProjectDetailsPage({
    super.key,
    this.initialProjectName,
    this.projectId,
    this.onSaveStatusChanged,
    this.onErrorStateChanged,
    this.onAreaErrorsChanged,
    this.onPartnerErrorsChanged,
    this.onExpenseErrorsChanged,
    this.onSiteErrorsChanged,
    this.onProjectManagerErrorsChanged,
    this.onAgentErrorsChanged,
    this.onAboutErrorsChanged,
    this.onPlotStatusErrorsChanged,
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
  aboutDetails,
}

class _ProjectDetailsPageState extends State<ProjectDetailsPage> {
  static final Set<String> _projectsLoadedThisSession = <String>{};
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _projectNameController = TextEditingController();
  final TextEditingController _projectAddressController =
      TextEditingController();
  final TextEditingController _googleMapsLinkController =
      TextEditingController();
  final TextEditingController _totalAreaController = TextEditingController();
  final TextEditingController _sellingAreaController = TextEditingController();

  final FocusNode _projectNameFocusNode = FocusNode();
  final FocusNode _projectAddressFocusNode = FocusNode();
  final FocusNode _googleMapsLinkFocusNode = FocusNode();
  final FocusNode _totalAreaFocusNode = FocusNode();
  final FocusNode _sellingAreaFocusNode = FocusNode();
  final FocusNode _estimatedDevelopmentCostFocusNode = FocusNode();
  late final VoidCallback _aboutFocusRefreshListener;

  List<Map<String, String>> _nonSellableAreas = [];

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
  bool _isAreaDataLoading = false;
  // Flag to track if this is the first time loading project data
  bool _hasLoadedDataOnce = false;

  // Tab state
  ProjectTab _activeTab = ProjectTab.about;

  // Section error tracking
  bool _hasAreaErrors = false;
  bool _hasPartnerErrors = false;
  bool _hasExpenseErrors = false;
  bool _hasSiteErrors = false;
  bool _hasProjectManagerErrors = false;
  bool _hasAgentErrors = false;
  bool _hasAboutErrors = false;

  // Scroll controller
  final ScrollController _scrollController = ScrollController();

  // Area unit dropdown state
  String _selectedAreaUnit = 'Square Feet (sqft)';

  bool get _isSqm => AreaUnitUtils.isSqm(_selectedAreaUnit);
  String get _areaUnitSuffix => AreaUnitUtils.unitSuffix(_isSqm);

  // Partners data
  final TextEditingController _estimatedDevelopmentCostController =
      TextEditingController();
  List<Map<String, dynamic>> _partners = [
    {'name': '', 'amount': '0.00'},
  ];
  final Map<int, TextEditingController> _partnerNameControllers = {};
  final Map<int, TextEditingController> _partnerAmountControllers = {};
  final Map<int, FocusNode> _partnerNameFocusNodes = {};
  final Map<int, FocusNode> _partnerAmountFocusNodes = {};

  // Expenses data
  List<Map<String, dynamic>> _expenses = [
    {
      'item': 'Total Plot Purchasing Cost',
      'amount': '0.00',
      'category': 'Land Purchase Cost'
    },
    {'item': '', 'amount': '0.00', 'category': ''},
  ];
  final Map<int, TextEditingController> _expenseItemControllers = {};
  final Map<int, TextEditingController> _expenseAmountControllers = {};
  final Map<int, FocusNode> _expenseItemFocusNodes = {};
  final Map<int, FocusNode> _expenseAmountFocusNodes = {};
  final List<String> _expenseCategories = [
    'Land Purchase Cost',
    'Statutory & Registration',
    'Legal & Professional Fees',
    'Survey, Approvals & Conversion',
    'Construction & Development',
    'Amenities & Infrastructure',
    'Others',
  ];

  // Track open category dropdown
  int? _openCategoryDropdownIndex;
  OverlayEntry? _currentCategoryDropdownEntry;
  OverlayEntry? _currentCategoryBackdropEntry;

  // Track open PM/Agent compensation & earning dropdowns
  int? _openProjectManagerCompensationDropdownIndex;
  OverlayEntry? _currentProjectManagerCompensationDropdownEntry;
  OverlayEntry? _currentProjectManagerCompensationBackdropEntry;
  int? _openProjectManagerEarningDropdownIndex;
  OverlayEntry? _currentProjectManagerEarningDropdownEntry;
  OverlayEntry? _currentProjectManagerEarningBackdropEntry;
  int? _openAgentCompensationDropdownIndex;
  OverlayEntry? _currentAgentCompensationDropdownEntry;
  OverlayEntry? _currentAgentCompensationBackdropEntry;
  int? _openAgentEarningDropdownIndex;
  OverlayEntry? _currentAgentEarningDropdownEntry;
  OverlayEntry? _currentAgentEarningBackdropEntry;

  // Track open layout menu
  int? _openLayoutMenuIndex;
  OverlayEntry? _currentLayoutMenuEntry;
  OverlayEntry? _currentLayoutMenuBackdropEntry;
  final GlobalKey _deleteAllLayoutsMenuAnchorKey = GlobalKey();
  final Map<int, GlobalKey> _layoutMenuAnchorKeys = {};

  void _setStateSafe(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    } else {
      fn();
    }
  }

  void _requestFocusAndCursorAfterTap(
      FocusNode node, TextEditingController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        node.requestFocus();
        final cursorPosition = controller.text.length;
        controller.selection = TextSelection.collapsed(offset: cursorPosition);
      }
    });
  }

  // Site/Layouts data
  final TextEditingController _numberOfLayoutsController =
      TextEditingController();
  final FocusNode _numberOfLayoutsFocusNode = FocusNode();
  List<Map<String, dynamic>> _layouts = []; // Each layout will contain plots
  final Map<int, TextEditingController> _layoutNameControllers =
      {}; // Controllers for layout names
  final Map<int, FocusNode> _layoutNameFocusNodes =
      {}; // Focus nodes for layout names
  final Map<String, TextEditingController> _plotNumberControllers =
      {}; // Key: 'layoutIndex_plotIndex'
  final Map<String, FocusNode> _plotNumberFocusNodes =
      {}; // Focus nodes for plot numbers
  final Map<String, TextEditingController> _plotAreaControllers =
      {}; // Key: 'layoutIndex_plotIndex'
  final Map<String, FocusNode> _plotAreaFocusNodes =
      {}; // Focus nodes for plot areas
  final Map<String, TextEditingController> _plotPurchaseRateControllers =
      {}; // Key: 'layoutIndex_plotIndex'
  final Map<String, FocusNode> _plotPurchaseRateFocusNodes =
      {}; // Focus nodes for purchase rates
  final Map<String, List<String>> _plotPartners =
      {}; // Key: 'layoutIndex_plotIndex', value: list of partner names
  bool _isCreateTableEnabled = false; // State for Create Table button

  // Project Managers data
  List<Map<String, dynamic>> _projectManagers = [
    {'name': '', 'compensation': '', 'earningType': ''},
  ];
  final Map<int, TextEditingController> _projectManagerNameControllers = {};
  final Map<int, FocusNode> _projectManagerNameFocusNodes = {};
  final Map<int, TextEditingController> _projectManagerFixedFeeControllers =
      {}; // Fixed Fee amount controllers
  final Map<int, FocusNode> _projectManagerFixedFeeFocusNodes =
      {}; // Fixed Fee focus nodes
  final Map<int, TextEditingController> _projectManagerMonthlyFeeControllers =
      {}; // Monthly Fee amount controllers
  final Map<int, FocusNode> _projectManagerMonthlyFeeFocusNodes =
      {}; // Monthly Fee focus nodes
  final Map<int, TextEditingController> _projectManagerMonthsControllers =
      {}; // Months controllers
  final Map<int, FocusNode> _projectManagerMonthsFocusNodes =
      {}; // Months focus nodes
  final Map<int, TextEditingController> _projectManagerPercentageControllers =
      {}; // Percentage controllers
  final Map<int, FocusNode> _projectManagerPercentageFocusNodes =
      {}; // Percentage focus nodes
  final Map<int, String> _projectManagerCompensation =
      {}; // Selected compensation type
  final Map<int, String> _projectManagerEarningType =
      {}; // Selected earning type
  final Map<int, String> _projectManagerPercentage =
      {}; // Percentage value for earning type
  final Map<int, String> _projectManagerFixedFee = {}; // Fixed Fee amount value
  final Map<int, String> _projectManagerMonthlyFee =
      {}; // Monthly Fee amount value
  final Map<int, String> _projectManagerMonths = {}; // Months value
  final Map<int, List<String>> _projectManagerSelectedBlocks =
      {}; // Selected blocks/plots for each project manager

  // Agents data
  List<Map<String, dynamic>> _agents = [
    {'name': '', 'compensation': '', 'earningType': ''},
  ];
  final Map<int, TextEditingController> _agentNameControllers = {};
  final Map<int, FocusNode> _agentNameFocusNodes = {};
  final Map<int, TextEditingController> _agentFixedFeeControllers =
      {}; // Fixed Fee amount controllers
  final Map<int, FocusNode> _agentFixedFeeFocusNodes =
      {}; // Fixed Fee focus nodes
  final Map<int, TextEditingController> _agentMonthlyFeeControllers =
      {}; // Monthly Fee amount controllers
  final Map<int, FocusNode> _agentMonthlyFeeFocusNodes =
      {}; // Monthly Fee focus nodes
  final Map<int, TextEditingController> _agentMonthsControllers =
      {}; // Months controllers
  final Map<int, FocusNode> _agentMonthsFocusNodes = {}; // Months focus nodes
  final Map<int, TextEditingController> _agentPercentageControllers =
      {}; // Percentage controllers
  final Map<int, FocusNode> _agentPercentageFocusNodes =
      {}; // Percentage focus nodes
  final Map<int, String> _agentCompensation = {}; // Selected compensation type
  final Map<int, String> _agentEarningType = {}; // Selected earning type
  final Map<int, String> _agentPercentage =
      {}; // Percentage value for earning type
  final Map<int, String> _agentFixedFee = {}; // Fixed Fee amount value
  final Map<int, String> _agentMonthlyFee = {}; // Monthly Fee amount value
  final Map<int, String> _agentMonths = {}; // Months value
  final Map<int, TextEditingController> _agentPerSqftFeeControllers =
      {}; // Per Sqft Fee amount controllers
  final Map<int, FocusNode> _agentPerSqftFeeFocusNodes =
      {}; // Per Sqft Fee focus nodes
  final Map<int, String> _agentPerSqftFee = {}; // Per Sqft Fee amount value
  final Map<int, List<String>> _agentSelectedBlocks =
      {}; // Selected blocks/plots for each agent

  // Scroll controllers for tables
  final ScrollController _partnersTableScrollController = ScrollController();
  final ScrollController _expensesTableScrollController = ScrollController();
  final ScrollController _projectManagersTableScrollController =
      ScrollController();
  final ScrollController _agentsTableScrollController = ScrollController();
  final Map<int, ScrollController> _plotsTableScrollControllers =
      {}; // Key: layoutIndex
  final Map<int, ScrollController> _plotsTableVerticalScrollControllers =
      {}; // Key: layoutIndex

  // Track collapsed layouts
  final Set<int> _collapsedLayouts =
      {}; // Set of layout indices that are collapsed

  // Table zoom level (1.0 = 100%, 0.5 = 50%, 2.0 = 200%, etc.)
  double _tableZoomLevel = 1.0;

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

  GlobalKey _layoutMenuAnchorKeyFor(int layoutIndex) {
    return _layoutMenuAnchorKeys.putIfAbsent(layoutIndex, () => GlobalKey());
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Land Purchase Cost':
        return const Color(0xFFD4EDDA);
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
  String _formatAmount(String value, {int decimalPlaces = 2}) {
    if (value.trim().isEmpty) {
      return '';
    }

    // Remove any currency symbols, spaces, and commas
    String cleaned = value
        .trim()
        .replaceAll('₹', '')
        .replaceAll(' ', '')
        .replaceAll(',', '');

    String integerPart;
    String decimalPart = '';
    bool hasDecimal = false;

    // Check if it contains a decimal point
    if (cleaned.contains('.')) {
      final parts = cleaned.split('.');
      integerPart = parts[0].isEmpty ? '0' : parts[0];
      decimalPart = parts.length > 1 ? parts[1] : '';

      // Check if decimal part has any non-zero value
      final hasNonZeroDecimal = decimalPart.isNotEmpty &&
          decimalPart != '0' * decimalPlaces &&
          decimalPart.replaceAll('0', '').isNotEmpty;

      if (hasNonZeroDecimal) {
        hasDecimal = true;

        // Pad decimal part to required places (RIGHT padding) or truncate if longer
        if (decimalPart.length > decimalPlaces) {
          decimalPart = decimalPart.substring(0, decimalPlaces);
        } else {
          // Pad on the RIGHT (e.g., .5 → .50 or .500)
          decimalPart = decimalPart.padRight(decimalPlaces, '0');
        }
      }
    } else {
      // No decimal point - don't add one
      integerPart = cleaned.isEmpty ? '0' : cleaned;
    }

    // Remove leading zeros from integer part (but keep "0" if it's just zero)
    integerPart = int.tryParse(integerPart)?.toString() ?? '0';

    // Check if the entire value is zero
    if (integerPart == '0' &&
        (!hasDecimal || decimalPart.replaceAll('0', '').isEmpty)) {
      return '0';
    }

    // Format integer part with Indian numbering
    final formattedInteger = _formatIntegerWithIndianNumbering(integerPart);

    // Only add decimal part if user entered actual decimal digits
    return hasDecimal ? '$formattedInteger.$decimalPart' : formattedInteger;
  }

  // Helper function to format currency value for display (₹ 0.00 format)
  String _formatCurrency(String value) {
    if (value.isEmpty || value == '0') {
      return '₹ 0';
    }

    // Parse the value to handle decimals
    double? numValue = double.tryParse(value);
    if (numValue == null) {
      return '₹ 0';
    }

    // Format with smart decimal handling
    String amountStr = _formatAmountDisplay(numValue, decimalPlaces: 2);

    // Add Indian numbering formatting for the integer part if value is large enough
    if (numValue.abs() >= 1000) {
      final parts = amountStr.split('.');
      String integerPart = parts[0];
      String decimalPart = parts.length > 1 ? parts[1] : '';

      // Format integer part with Indian numbering
      String formattedInteger = _formatIntegerWithIndianNumbering(integerPart);

      return decimalPart.isEmpty
          ? '₹ $formattedInteger'
          : '₹ $formattedInteger.$decimalPart';
    }

    return '₹ $amountStr';
  }

  // Helper function to format double amount for display with Indian numbering
  String _formatAmountForDisplay(double amount, {int decimalPlaces = 2}) {
    final isNegative = amount < 0;

    // Use smart formatting to hide unnecessary decimals
    String smartFormatted =
        _formatAmountDisplay(amount.abs(), decimalPlaces: decimalPlaces);

    // If the value has no decimals or is small, return with sign
    if (amount.abs() < 1000) {
      return '${isNegative ? '-' : ''}$smartFormatted';
    }

    // For larger values, apply Indian numbering to integer part
    final parts = smartFormatted.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '';

    // Format integer part with Indian numbering
    final formattedInteger = _formatIntegerWithIndianNumbering(integerPart);

    return decimalPart.isEmpty
        ? '${isNegative ? '-' : ''}$formattedInteger'
        : '${isNegative ? '-' : ''}$formattedInteger.$decimalPart';
  }

  // Helper function to format area value, hiding decimals if they're all zeros
  String _formatAreaDisplay(double value, {int decimalPlaces = 3}) {
    if (value == value.toInt()) {
      // No decimal part, return as integer
      return value.toInt().toString();
    }
    // Has decimal part, format with specified decimal places
    String formatted = value.toStringAsFixed(decimalPlaces);
    // Remove trailing zeros
    formatted = formatted.replaceAll(RegExp(r'\.?0+$'), '');
    return formatted;
  }

  // Helper function to format amount for display, hiding decimals if they're all zeros
  String _formatAmountDisplay(double value, {int decimalPlaces = 2}) {
    if (value == value.toInt()) {
      // No decimal part, return as integer
      return value.toInt().toString();
    }
    // Has decimal part, format with specified decimal places
    String formatted = value.toStringAsFixed(decimalPlaces);
    // Remove trailing zeros
    formatted = formatted.replaceAll(RegExp(r'\.?0+$'), '');
    return formatted;
  }

  // Helper for input/controller text formatting with Indian commas.
  // Keeps storage models unformatted while preserving UI formatting on reload.
  String _formatInputAmount(dynamic value, {int decimalPlaces = 2}) {
    if (value == null) return '';

    double numValue;
    if (value is String) {
      numValue = double.tryParse(value.replaceAll(',', '').trim()) ?? 0.0;
    } else if (value is num) {
      numValue = value.toDouble();
    } else {
      return '';
    }

    if (numValue == 0.0) return '';
    final compact =
        _formatAmountDisplay(numValue, decimalPlaces: decimalPlaces);
    return _formatAmount(compact, decimalPlaces: decimalPlaces);
  }

  double get _totalNonSellableArea {
    return _nonSellableAreas.fold(0.0,
        (sum, area) => sum + (double.tryParse(area['area'] ?? '0') ?? 0.0));
  }

  double get _actualSellingArea {
    // Calculate selling area from all layout plots
    double total = 0.0;
    for (var layout in _layouts) {
      final plots = layout['plots'] as List<dynamic>? ?? [];
      for (var plot in plots) {
        final areaText = plot['area']?.toString() ?? '0';
        final area =
            double.tryParse(areaText.replaceAll(',', '').replaceAll(' ', '')) ??
                0.0;
        total += area;
      }
    }
    return total;
  }

  double get _remainingArea {
    final totalArea = double.tryParse(_totalAreaController.text
            .replaceAll(',', '')
            .replaceAll(' ', '')) ??
        0;
    final sellingArea = double.tryParse(_sellingAreaController.text
            .replaceAll(',', '')
            .replaceAll(' ', '')) ??
        0;
    return totalArea - sellingArea - _totalNonSellableArea;
  }

  double get _estimatedDevelopmentCost {
    final cleaned = _estimatedDevelopmentCostController.text
        .replaceAll(',', '')
        .replaceAll('₹', '')
        .replaceAll(' ', '')
        .trim();
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
      final cleanedAmount = controllerAmount
          .replaceAll(',', '')
          .replaceAll('₹', '')
          .replaceAll(' ', '');
      final amount =
          double.tryParse(cleanedAmount.isEmpty ? '0.00' : cleanedAmount) ??
              0.0;
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

  // Site/Layouts calculations (all in sqft for internal consistency)
  double get _approvedSellingArea {
    try {
      final text = _sellingAreaController.text;
      if (text.isEmpty) return 0.0;
      final cleaned = text.replaceAll(',', '').replaceAll(' ', '');
      final displayValue = double.tryParse(cleaned) ?? 0.0;
      return AreaUnitUtils.areaFromDisplayToSqft(displayValue, _isSqm);
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
          final area = double.tryParse(areaController.text
                  .replaceAll(',', '')
                  .replaceAll(' ', '')) ??
              0.0;
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
    final allInCost =
        _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;

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
          final area = double.tryParse(areaController.text
                      .replaceAll(',', '')
                      .replaceAll(' ', '')
                      .trim() ??
                  '0') ??
              0.0;
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
    final allInCost =
        _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;

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
          final area = double.tryParse(areaController.text
                      .replaceAll(',', '')
                      .replaceAll(' ', '')
                      .trim() ??
                  '0') ??
              0.0;
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
      final amountEmpty =
          (controllerAmount.isEmpty || controllerAmount == '0.00') &&
              (partnerAmount.isEmpty || partnerAmount == '0.00');

      // Check if exceeding estimated development cost
      final exceedsAmount = _totalPartnerAmount > _estimatedDevelopmentCost &&
          _estimatedDevelopmentCost > 0;

      if (nameEmpty || amountEmpty || exceedsAmount) {
        return true;
      }
    }

    // Check if remaining budget is red (not fully allocated or exceeds)
    final hasPartnerData = _partners.any((p) =>
        (p['name']?.toString().trim().isNotEmpty ?? false) ||
        ((double.tryParse(
                    (p['amount'] ?? '0').toString().replaceAll(',', '')) ??
                0) >
            0));
    final noDevelopmentCost = _estimatedDevelopmentCost == 0 && hasPartnerData;
    final remaining = _remainingPartnerAmount;
    final exceedsAmount = _totalPartnerAmount > _estimatedDevelopmentCost &&
        _estimatedDevelopmentCost > 0;

    // Show error if remaining budget is red
    if (noDevelopmentCost || remaining != 0 || exceedsAmount) {
      return true;
    }

    // Show error if total share allocated is red (not 100%)
    if (_totalSharePercentage != 100 && (noDevelopmentCost || exceedsAmount)) {
      return true;
    }

    return false;
  }

  bool get _hasAboutValidationErrors {
    // Check if project name is empty
    final projectNameEmpty = _projectNameController.text.trim().isEmpty;

    // Check if location link is invalid
    final locationValue = _googleMapsLinkController.text.trim();
    final uri = Uri.tryParse(locationValue);
    final validMapPattern = RegExp(
        r'^(https?://)?(www\.)?(google\.com/maps|goo\.gl/maps|maps\.app\.goo\.gl|share\.google/)[\w\-]+',
        caseSensitive: false);
    final isGoogleSearchLocation = uri != null &&
        uri.host.contains('google.com') &&
        uri.path.contains('search') &&
        (uri.queryParameters.containsKey('kgmid') ||
            uri.queryParameters.containsKey('kgs'));
    final isMapsAppGooGl = uri != null && uri.host.contains('maps.app.goo.gl');
    final isShareGoogle = uri != null && uri.host.contains('share.google');
    final locationValid = locationValue.isNotEmpty &&
        (isGoogleSearchLocation ||
            isMapsAppGooGl ||
            isShareGoogle ||
            validMapPattern.hasMatch(locationValue));

    return projectNameEmpty || !locationValid;
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
      final cleanedControllerAmount = controllerAmount
          .replaceAll(',', '')
          .replaceAll('₹', '')
          .replaceAll(' ', '');
      final cleanedExpenseAmount = expenseAmount
          .replaceAll(',', '')
          .replaceAll('₹', '')
          .replaceAll(' ', '');
      final amountEmpty = (cleanedControllerAmount.isEmpty ||
              cleanedControllerAmount == '0.00') &&
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
      final controllerName =
          _projectManagerNameControllers[i]?.text.trim() ?? '';
      final managerName = _projectManagers[i]['name']?.toString().trim() ?? '';
      final nameEmpty = controllerName.isEmpty && managerName.isEmpty;

      // Get compensation type
      final compensationType = _projectManagerCompensation[i] ?? '';
      final compensationEmpty =
          compensationType.isEmpty || compensationType == 'None';

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

      // 3. Compensation is "Percentage Bonus" AND earning type is empty
      // Note: Fixed Fee and Monthly Fee don't require earning type
      if (compensationType == 'Percentage Bonus' &&
          selectedEarningType.isEmpty) {
        return true;
      }
    }

    return false;
  }

  bool get _isProjectManagerFirstRowWarningState {
    if (_projectManagers.length != 1) return false;

    final controllerName = _projectManagerNameControllers[0]?.text.trim() ?? '';
    final managerName = _projectManagers[0]['name']?.toString().trim() ?? '';
    final nameEmpty = controllerName.isEmpty && managerName.isEmpty;

    final compensationType = _projectManagerCompensation[0] ?? '';
    final compensationEmpty =
        compensationType.isEmpty || compensationType == 'None';

    return nameEmpty && compensationEmpty;
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
      final compensationEmpty =
          compensationType.isEmpty || compensationType == 'None';

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

      // 3. Compensation is "Percentage Bonus" AND earning type is empty
      // Note: Fixed Fee, Monthly Fee, and Per Sq. Ft. Fee don't require earning type
      if (compensationType == 'Percentage Bonus' &&
          selectedEarningType.isEmpty) {
        return true;
      }
    }

    return false;
  }

  bool get _isAgentFirstRowWarningState {
    if (_agents.length != 1) return false;

    final controllerName = _agentNameControllers[0]?.text.trim() ?? '';
    final agentName = _agents[0]['name']?.toString().trim() ?? '';
    final nameEmpty = controllerName.isEmpty && agentName.isEmpty;

    final compensationType = _agentCompensation[0] ?? '';
    final compensationEmpty =
        compensationType.isEmpty || compensationType == 'None';

    return nameEmpty && compensationEmpty;
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
        final plotNumberEmpty = (plotNumberController?.text.trim().isEmpty ??
                true) ||
            (plots[plotIndex]['plotNumber']?.toString().trim().isEmpty ?? true);

        // Check area
        final areaController = _plotAreaControllers[key];
        final cleanedAreaText = areaController?.text
                .replaceAll(',', '')
                .replaceAll(' ', '')
                .trim() ??
            '';
        final areaIsEmpty = cleanedAreaText.isEmpty ||
            cleanedAreaText == '0' ||
            cleanedAreaText == '0.00';
        final areaEmpty = areaIsEmpty ||
            (plots[plotIndex]['area']?.toString().trim().isEmpty ?? true) ||
            plots[plotIndex]['area'] == '0.00';

        // Check purchase rate
        final purchaseRateController = _plotPurchaseRateControllers[key];
        final cleanedPurchaseRateText = purchaseRateController?.text
                .replaceAll(',', '')
                .replaceAll('₹', '')
                .replaceAll(' ', '')
                .trim() ??
            '';
        final purchaseRateIsEmpty = cleanedPurchaseRateText.isEmpty ||
            cleanedPurchaseRateText == '0' ||
            cleanedPurchaseRateText == '0.00';
        final purchaseRateEmpty = purchaseRateIsEmpty ||
            (plots[plotIndex]['purchaseRate']?.toString().trim().isEmpty ??
                true) ||
            plots[plotIndex]['purchaseRate'] == '0.00';

        // Check partners
        final selectedPartners = _plotPartners[key] ?? [];
        final partnersEmpty = selectedPartners.isEmpty;

        if (plotNumberEmpty ||
            areaEmpty ||
            purchaseRateEmpty ||
            partnersEmpty) {
          return true;
        }
      }
    }

    return false;
  }

  // Helper method to process number of layouts and create layouts
  void _processNumberOfLayouts() {
    // Remove commas before parsing
    final cleaned = _numberOfLayoutsController.text
        .replaceAll(',', '')
        .replaceAll('₹', '')
        .replaceAll(' ', '')
        .trim();

    // If value is empty, don't do anything
    if (cleaned.isEmpty) {
      setState(() {
        _isCreateTableEnabled = false;
      });
      return;
    }

    // Parse the number (handle decimal by taking integer part)
    final numValue = double.tryParse(cleaned) ?? 0.0;
    final numLayouts = numValue.toInt();

    // Don't allow zero or negative values
    if (numLayouts <= 0) {
      _numberOfLayoutsController.clear();
      setState(() {
        _isCreateTableEnabled = false;
      });
      return;
    }

    // Create layouts and controllers BEFORE setState to avoid blocking UI
    final List<Map<String, dynamic>> newLayouts = [];
    final newLayoutNameControllers = <int, TextEditingController>{};
    final newLayoutNameFocusNodes = <int, FocusNode>{};
    final newPlotNumberControllers = <String, TextEditingController>{};
    final newPlotAreaControllers = <String, TextEditingController>{};
    final newPlotPurchaseRateControllers = <String, TextEditingController>{};

    for (int i = _layouts.length; i < _layouts.length + numLayouts; i++) {
      // Create default plot for new layout
      final Map<String, dynamic> defaultPlot = {
        'plotNumber': '',
        'area': '0.00',
        'purchaseRate': '0.00',
        'totalPlotCost': '0.00',
        'partner': '',
      };
      newLayouts.add({
        'name': 'Layout ${i + 1}',
        'plots': [defaultPlot],
      });

      // Initialize controllers
      newLayoutNameControllers[i] = TextEditingController(text: '');
      newLayoutNameFocusNodes[i] = FocusNode();
      final plotKey = '${i}_0';
      newPlotNumberControllers[plotKey] = TextEditingController();
      newPlotAreaControllers[plotKey] = TextEditingController();
      newPlotPurchaseRateControllers[plotKey] = TextEditingController();
    }

    final bool hasNewLayouts = newLayouts.isNotEmpty;

    // Now add everything to the main lists and update state once
    setState(() {
      _layouts.addAll(newLayouts);
      _layoutNameControllers.addAll(newLayoutNameControllers);
      _layoutNameFocusNodes.addAll(newLayoutNameFocusNodes);
      _plotNumberControllers.addAll(newPlotNumberControllers);
      _plotAreaControllers.addAll(newPlotAreaControllers);
      _plotPurchaseRateControllers.addAll(newPlotPurchaseRateControllers);

      // Clear the input field and disable the button
      _numberOfLayoutsController.clear();
      _isCreateTableEnabled = false;
    });
    _onDataChanged();
    FocusScope.of(context).unfocus();

    // If newly added layouts are below the current viewport, auto-scroll to reveal them.
    if (hasNewLayouts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final targetOffset = _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _aboutFocusRefreshListener = () {
      if (mounted) setState(() {});
    };
    _projectNameFocusNode.addListener(_aboutFocusRefreshListener);
    _projectAddressFocusNode.addListener(_aboutFocusRefreshListener);
    _googleMapsLinkFocusNode.addListener(_aboutFocusRefreshListener);
    // Set initial project name if provided
    if (widget.initialProjectName != null) {
      _projectNameController.text = widget.initialProjectName!;
    }
    // Initialize controllers for existing non-sellable areas
    for (int i = 0; i < _nonSellableAreas.length; i++) {
      _nonSellableNameControllers[i] = TextEditingController(
        text: _nonSellableAreas[i]['name'] ?? '',
      );
      final nonSellableAreaValue = _nonSellableAreas[i]['area'] ?? '';
      final nonSellableAreaNum = double.tryParse(
              nonSellableAreaValue.toString().replaceAll(',', '')) ??
          0.0;
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
      final expenseAmountNum =
          double.tryParse(expenseAmount.toString().replaceAll(',', '')) ?? 0.0;
      _expenseAmountControllers[i] = TextEditingController(
        text: expenseAmountNum == 0.0 ? '' : expenseAmount.toString(),
      );
    }

    // Initialize project manager controllers
    for (int i = 0; i < _projectManagers.length; i++) {
      _projectManagerNameControllers[i] = TextEditingController(
        text: _projectManagers[i]['name'] ?? '',
      );
      _projectManagerCompensation[i] =
          _projectManagers[i]['compensation'] ?? '';
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
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _selectedAreaUnit = await AreaUnitService.getAreaUnit(widget.projectId);
        if (mounted) setState(() {});
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProjectAboutFromStorage();
    });

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
    if (mounted) {
      setState(() {
        _isLoadingData = true; // Prevent saving during data load
        _isAreaDataLoading = true;
      });
    } else {
      _isLoadingData = true;
      _isAreaDataLoading = true;
    }

    // Load the persisted flag from local storage
    final prefs = await SharedPreferences.getInstance();
    final persistedFlag =
        prefs.getBool('project_${widget.projectId}_has_loaded_once') ?? false;
    final hideDefaultNonSellable = prefs
            .getBool('project_${widget.projectId}_hide_default_non_sellable') ??
        false;
    _hasLoadedDataOnce =
        persistedFlag || _projectsLoadedThisSession.contains(widget.projectId);
    print(
        '_loadProjectData: Loaded _hasLoadedDataOnce=$_hasLoadedDataOnce, hideDefaultNonSellable=$hideDefaultNonSellable from local storage');

    try {
      // Load area unit preference
      _selectedAreaUnit = await AreaUnitService.getAreaUnit(widget.projectId);

      // Load project basic info
      final project = await _supabase
          .from('projects')
          .select()
          .eq('id', widget.projectId!)
          .single();

      setState(() {
        _projectNameController.text =
            project['project_name'] ?? widget.initialProjectName ?? '';
        _projectAddressController.text =
            (project['project_address'] ?? project['address'] ?? '').toString();
        _googleMapsLinkController.text = (project['google_maps_link'] ??
                project['maps_link'] ??
                project['location_link'] ??
                '')
            .toString();
        final totalAreaSqft = (project['total_area'] ?? 0.0) is num
            ? (project['total_area'] as num).toDouble()
            : 0.0;
        final sellingAreaSqft = (project['selling_area'] ?? 0.0) is num
            ? (project['selling_area'] as num).toDouble()
            : 0.0;
        final estimatedCost = project['estimated_development_cost'] ?? 0.0;
        final totalAreaDisplay = AreaUnitUtils.areaFromSqftToDisplay(
            totalAreaSqft, AreaUnitUtils.isSqm(_selectedAreaUnit));
        final sellingAreaDisplay = AreaUnitUtils.areaFromSqftToDisplay(
            sellingAreaSqft, AreaUnitUtils.isSqm(_selectedAreaUnit));
        _totalAreaController.text = totalAreaSqft == 0.0
            ? ''
            : _formatInputAmount(totalAreaDisplay, decimalPlaces: 3);
        _sellingAreaController.text = sellingAreaSqft == 0.0
            ? ''
            : _formatInputAmount(sellingAreaDisplay, decimalPlaces: 3);
        _estimatedDevelopmentCostController.text =
            (estimatedCost is num && estimatedCost == 0.0)
                ? ''
                : _formatInputAmount(estimatedCost);
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
          _nonSellableAreas = nonSellableAreas.map((area) {
            final areaSqft = (area['area'] ?? 0.0) is num
                ? (area['area'] as num).toDouble()
                : 0.0;
            final areaDisplay = AreaUnitUtils.areaFromSqftToDisplay(
                areaSqft, AreaUnitUtils.isSqm(_selectedAreaUnit));
            return <String, String>{
              'name': (area['name'] ?? '').toString(),
              'area': areaSqft == 0.0 ? '' : _formatDecimal(areaDisplay),
            };
          }).toList();
        } else {
          // Start with empty list - user can add areas as needed
          _nonSellableAreas = [];
        }

        // Create new controllers
        print(
            'Creating controllers for ${_nonSellableAreas.length} non-sellable areas');
        for (int i = 0; i < _nonSellableAreas.length; i++) {
          print(
              '  Creating controller $i: name="${_nonSellableAreas[i]['name']}", area="${_nonSellableAreas[i]['area']}"');
          _nonSellableNameControllers[i] =
              TextEditingController(text: _nonSellableAreas[i]['name'] ?? '');
          final areaValue = _nonSellableAreas[i]['area'] ?? '0.00';
          final areaNum =
              double.tryParse(areaValue.toString().replaceAll(',', '')) ?? 0.0;
          _nonSellableAreaControllers[i] = TextEditingController(
              text: areaNum == 0.0
                  ? ''
                  : _formatInputAmount(areaNum, decimalPlaces: 3));
        }
        print(
            'Created ${_nonSellableNameControllers.length} name controllers and ${_nonSellableAreaControllers.length} area controllers');
        _isAreaDataLoading = false;
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
          _partners = partners
              .map((partner) => {
                    'name': partner['name'] ?? '',
                    'amount': _formatDecimal(partner['amount'] ?? 0.0),
                  })
              .toList();
        } else {
          // Keep at least one empty row
          _partners = [
            {'name': '', 'amount': '0.00'}
          ];
        }

        // Create new controllers
        for (int i = 0; i < _partners.length; i++) {
          _partnerNameControllers[i] =
              TextEditingController(text: _partners[i]['name'] ?? '');
          final partnerAmount = _partners[i]['amount'] ?? '0.00';
          final partnerAmountNum =
              double.tryParse(partnerAmount.toString().replaceAll(',', '')) ??
                  0.0;
          _partnerAmountControllers[i] = TextEditingController(
              text: partnerAmountNum == 0.0
                  ? ''
                  : _formatInputAmount(partnerAmountNum));
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
          _expenses = expenses
              .map((expense) => {
                    'item': expense['item'] ?? '',
                    'amount': _formatDecimal(expense['amount'] ?? 0.0),
                    // Map database category back to UI label
                    'category': _mapExpenseCategoryFromDatabase(
                        expense['category'] ?? ''),
                  })
              .toList();

          // Ensure the first row has the default values
          if (_expenses.isNotEmpty) {
            _expenses[0] = {
              'item': 'Total Plot Purchasing Cost',
              'amount': _expenses[0]['amount'] ?? '0.00',
              'category': 'Land Purchase Cost',
            };
          }
        } else {
          // Keep at least one empty row with default first row
          _expenses = [
            {
              'item': 'Total Plot Purchasing Cost',
              'amount': '0.00',
              'category': 'Land Purchase Cost'
            },
            {'item': '', 'amount': '0.00', 'category': ''},
          ];
        }

        // Create new controllers
        for (int i = 0; i < _expenses.length; i++) {
          _expenseItemControllers[i] =
              TextEditingController(text: _expenses[i]['item'] ?? '');
          final expenseAmount = _expenses[i]['amount'] ?? '0.00';
          final expenseAmountNum =
              double.tryParse(expenseAmount.toString().replaceAll(',', '')) ??
                  0.0;
          _expenseAmountControllers[i] = TextEditingController(
              text: expenseAmountNum == 0.0
                  ? ''
                  : _formatInputAmount(expenseAmountNum));
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
              'purchaseRate':
                  _formatDecimal(plot['all_in_cost_per_sqft'] ?? 0.0),
              'totalPlotCost': _formatDecimal(plot['total_plot_cost'] ?? 0.0),
              'status': (plot['status'] ?? 'available').toString(),
              'salePrice': plot['sale_price'] != null
                  ? _formatDecimal(plot['sale_price'])
                  : null,
              'buyerName': (plot['buyer_name'] ?? '').toString(),
              'saleDate': _formatDateFromDatabase(plot['sale_date']),
              'agent': (plot['agent_name'] ?? '').toString(),
              'partners': plotPartners
                  .map((p) => (p['partner_name'] ?? '').toString())
                  .toList(),
              'payments': plot['payments'] ?? [],
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

      if (!mounted) return;
      setState(() {
        _layouts = layoutsData;
        print('Loaded ${_layouts.length} layouts from database');
        // Keep "Create Table/Add Layouts" input inactive until user enters a fresh value.
        // Existing count is already shown by the summary text ("X layouts"), so don't prefill.
        _numberOfLayoutsController.text = '';
        _isCreateTableEnabled = false;
        // Initialize layout controllers with layout name from database
        for (int layoutIndex = 0;
            layoutIndex < _layouts.length;
            layoutIndex++) {
          final layoutName = _layouts[layoutIndex]['name'] ?? '';
          _layoutNameControllers[layoutIndex] =
              TextEditingController(text: layoutName);

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

          print(
              'Layout ${layoutIndex + 1}: ${layoutName}, ${plots.length} plots');

          // Ensure each layout has at least one default plot
          if (plots.isEmpty) {
            plots = [
              {
                'plotNumber': '',
                'area': '0.00',
                'purchaseRate': '0.00',
                'totalPlotCost': '0.00',
                'partner': '',
                'partners': [],
              }
            ];
          }

          // Update the layout with properly typed plots
          _layouts[layoutIndex]['plots'] = plots;

          for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
            final key = '${layoutIndex}_$plotIndex';
            final plot = plots[plotIndex];
            _plotNumberControllers[key] = TextEditingController(
                text: (plot['plotNumber'] ?? '').toString());
            final plotAreaSqft = double.tryParse(
                    (plot['area'] ?? '0.00').toString().replaceAll(',', '')) ??
                0.0;
            final plotAreaDisplay =
                AreaUnitUtils.areaFromSqftToDisplay(plotAreaSqft, _isSqm);
            _plotAreaControllers[key] = TextEditingController(
                text: plotAreaSqft == 0.0
                    ? ''
                    : _formatInputAmount(plotAreaDisplay, decimalPlaces: 3));
            final plotPurchaseRate = plot['purchaseRate'] ?? '0.00';
            final plotPurchaseRateNum = double.tryParse(
                    plotPurchaseRate.toString().replaceAll(',', '')) ??
                0.0;
            _plotPurchaseRateControllers[key] = TextEditingController(
                text: plotPurchaseRateNum == 0.0
                    ? ''
                    : _formatInputAmount(plotPurchaseRateNum));
            _plotPartners[key] = List<String>.from(
                (plot['partners'] ?? []).map((p) => p.toString()));
          }
        }
      });

      // Load project managers - ordered by created_at to preserve entry order
      final projectManagersRaw = await _supabase
          .from('project_managers')
          .select()
          .eq('project_id', widget.projectId!)
          .order('created_at', ascending: true);

      // Deduplicate project managers by ID first, then by name to prevent showing duplicates
      // Keep the first occurrence (oldest by created_at) for each unique name
      // IMPORTANT: Since projectManagersRaw is already ordered by created_at, we preserve that order
      final seenIds = <String>{};
      final seenNames = <String, String>{}; // name -> id of first occurrence
      final projectManagers = <Map<String, dynamic>>[];
      final duplicateIdsToDelete = <String>[];

      for (var pm in projectManagersRaw) {
        final id = pm['id']?.toString();
        final name = (pm['name'] ?? '').toString().trim().toLowerCase();

        if (id == null) continue;

        // Skip if we've already seen this ID (duplicate ID)
        if (seenIds.contains(id)) {
          duplicateIdsToDelete.add(id);
          print(
              '_loadProjectData: Found duplicate manager ID $id, marking for deletion');
          continue;
        }

        // Check for duplicate names (case-insensitive)
        // Only mark as duplicate if name is not empty and we've seen it before
        if (name.isNotEmpty && seenNames.containsKey(name)) {
          // This is a duplicate name - mark for deletion, keep the first one (already in list)
          duplicateIdsToDelete.add(id);
          print(
              '_loadProjectData: Found duplicate manager name "${pm['name']}" (id=$id), will keep first occurrence (id=${seenNames[name]})');
          continue;
        }

        // This is a unique manager - add it to the list in order
        seenIds.add(id);
        if (name.isNotEmpty) {
          seenNames[name] = id;
        }
        projectManagers.add(pm);
      }

      print(
          '_loadProjectData: Deduplication complete - kept ${projectManagers.length} managers, marked ${duplicateIdsToDelete.length} for deletion');

      // Clean up duplicates from database (async, don't wait)
      if (duplicateIdsToDelete.isNotEmpty) {
        print(
            '_loadProjectData: Cleaning up ${duplicateIdsToDelete.length} duplicate project managers from database');
        _supabase
            .from('project_managers')
            .delete()
            .inFilter('id', duplicateIdsToDelete)
            .then((_) => print(
                '_loadProjectData: Successfully deleted ${duplicateIdsToDelete.length} duplicate managers'))
            .catchError((e) =>
                print('_loadProjectData: Error deleting duplicates: $e'));
      }

      print(
          '_loadProjectData: Loaded ${projectManagers.length} project managers from database (after deduplication, original count: ${projectManagersRaw.length})');
      for (var pm in projectManagers) {
        print(
            '  Manager: id=${pm['id']}, name=${pm['name']}, compensation_type=${pm['compensation_type']}, earning_type=${pm['earning_type']}, percentage=${pm['percentage']}, fixed_fee=${pm['fixed_fee']}, monthly_fee=${pm['monthly_fee']}, months=${pm['months']}');
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
      for (var focusNode in _projectManagerNameFocusNodes.values) {
        focusNode.dispose();
      }
      _projectManagerNameFocusNodes.clear();
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
          // Map project managers and initialize controllers in the same loop to ensure alignment
          _projectManagers = [];
          for (int i = 0; i < projectManagers.length; i++) {
            final manager = projectManagers[i];
            // Map earning type correctly from the start
            final dbEarningType = (manager['earning_type'] ?? '').toString();
            final compensationType =
                (manager['compensation_type'] ?? '').toString();
            String mappedEarningType = dbEarningType;
            if (compensationType == 'Percentage Bonus') {
              final lowerEarningType = dbEarningType.toLowerCase();
              if (lowerEarningType == 'profit per plot') {
                mappedEarningType = '% of Profit on Each Sold Plot';
              } else if (lowerEarningType == 'selling price per plot' ||
                  lowerEarningType == '% of selling price per plot') {
                mappedEarningType = '% of Selling Price per Plot';
              } else if (lowerEarningType == 'lump sum' ||
                  lowerEarningType == '% of total project profit') {
                mappedEarningType = '% of Total Project Profit';
              } else if (lowerEarningType == 'per plot') {
                mappedEarningType = '% of Profit on Each Sold Plot';
              }
            }

            // Add to _projectManagers list
            _projectManagers.add(<String, dynamic>{
              'id': manager['id'],
              'name': (manager['name'] ?? '').toString(),
              'compensation': compensationType,
              'earningType': mappedEarningType,
            });

            // Initialize controllers and maps for this manager
            _projectManagerNameControllers[i] =
                TextEditingController(text: (manager['name'] ?? '').toString());
            _projectManagerCompensation[i] = compensationType;
            _projectManagerEarningType[i] = mappedEarningType;
            _projectManagerPercentage[i] = manager['percentage'] != null
                ? manager['percentage'].toString()
                : '';
            _projectManagerFixedFee[i] = manager['fixed_fee'] != null
                ? _formatInputAmount(manager['fixed_fee'])
                : '';
            _projectManagerMonthlyFee[i] = manager['monthly_fee'] != null
                ? _formatInputAmount(manager['monthly_fee'])
                : '';
            _projectManagerMonths[i] =
                manager['months'] != null ? manager['months'].toString() : '';

            // Initialize text controllers
            _projectManagerPercentageControllers[i] =
                TextEditingController(text: _projectManagerPercentage[i] ?? '');
            _projectManagerFixedFeeControllers[i] =
                TextEditingController(text: _projectManagerFixedFee[i] ?? '');
            _projectManagerMonthlyFeeControllers[i] =
                TextEditingController(text: _projectManagerMonthlyFee[i] ?? '');
            _projectManagerMonthsControllers[i] =
                TextEditingController(text: _projectManagerMonths[i] ?? '');
          }
        } else {
          // Keep at least one empty row
          _projectManagers = [
            <String, dynamic>{'name': '', 'compensation': '', 'earningType': ''}
          ];
          _projectManagerNameControllers[0] = TextEditingController();
          _projectManagerCompensation[0] = '';
          _projectManagerEarningType[0] = '';
          _projectManagerPercentage[0] = '';
          _projectManagerFixedFee[0] = '';
          _projectManagerMonthlyFee[0] = '';
          _projectManagerMonths[0] = '';
          _projectManagerPercentageControllers[0] = TextEditingController();
          _projectManagerFixedFeeControllers[0] = TextEditingController();
          _projectManagerMonthlyFeeControllers[0] = TextEditingController();
          _projectManagerMonthsControllers[0] = TextEditingController();
        }
      });

      // Load selected blocks for project managers (outside setState since it's async)
      // Use _projectManagers instead of projectManagers to ensure correct indexing
      final loadedManagerBlocks = <int, List<String>>{};
      for (int i = 0; i < _projectManagers.length; i++) {
        final managerId = _projectManagers[i]['id'];
        if (managerId == null) continue;

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
            print(
                'Loading blocks for manager $index: $blocks (length: ${blocks.length})');
            _projectManagerSelectedBlocks[index] = List<String>.from(blocks);
            print(
                'Stored blocks for manager $index: ${_projectManagerSelectedBlocks[index]}');
          });
        });
        print(
            'After setState, _projectManagerSelectedBlocks keys: ${_projectManagerSelectedBlocks.keys.toList()}');
      }

      // Load agents
      final agents = await _supabase
          .from('agents')
          .select()
          .eq('project_id', widget.projectId!);

      print('_loadProjectData: Loaded ${agents.length} agents from database');
      for (var agent in agents) {
        print(
            '  Agent: id=${agent['id']}, name=${agent['name']}, compensation_type=${agent['compensation_type']}, earning_type=${agent['earning_type']}, percentage=${agent['percentage']}, fixed_fee=${agent['fixed_fee']}, monthly_fee=${agent['monthly_fee']}, months=${agent['months']}, per_sqft_fee=${agent['per_sqft_fee']}');
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
      for (var focusNode in _agentNameFocusNodes.values) {
        focusNode.dispose();
      }
      _agentNameFocusNodes.clear();
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

      if (!mounted) return;
      setState(() {
        if (agents.isNotEmpty) {
          _agents = agents.map((agent) {
            // Map earning type correctly from the start
            final dbEarningType = (agent['earning_type'] ?? '').toString();
            final compensationType =
                (agent['compensation_type'] ?? '').toString();
            String mappedEarningType = dbEarningType;
            if (compensationType == 'Percentage Bonus') {
              final lowerEarningType = dbEarningType.toLowerCase();
              if (lowerEarningType == 'profit per plot') {
                mappedEarningType = '% of Profit on Each Sold Plot';
              } else if (lowerEarningType == 'selling price per plot' ||
                  lowerEarningType == '% of selling price per plot') {
                mappedEarningType = '% of Selling Price per Plot';
              } else if (lowerEarningType == 'lump sum' ||
                  lowerEarningType == '% of total project profit') {
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
          _agents = [
            <String, dynamic>{'name': '', 'compensation': '', 'earningType': ''}
          ];
        }

        // Create new controllers and maps
        for (int i = 0; i < _agents.length; i++) {
          if (i < agents.length) {
            final agent = agents[i];
            _agentNameControllers[i] =
                TextEditingController(text: (agent['name'] ?? '').toString());
            _agentCompensation[i] =
                (agent['compensation_type'] ?? '').toString();
            // Use the already-mapped earning type from _agents
            _agentEarningType[i] = _agents[i]['earningType'] as String? ?? '';
            _agentPercentage[i] = agent['percentage'] != null
                ? agent['percentage'].toString()
                : '';
            _agentFixedFee[i] = agent['fixed_fee'] != null
                ? _formatInputAmount(agent['fixed_fee'])
                : '';
            _agentMonthlyFee[i] = agent['monthly_fee'] != null
                ? _formatInputAmount(agent['monthly_fee'])
                : '';
            _agentMonths[i] =
                agent['months'] != null ? agent['months'].toString() : '';
            final perSqftFromDb =
                (agent['per_sqft_fee'] as num?)?.toDouble() ?? 0.0;
            final perAreaDisplay = perSqftFromDb > 0
                ? AreaUnitUtils.rateFromSqftToDisplay(perSqftFromDb, _isSqm)
                : 0.0;
            _agentPerSqftFee[i] =
                perSqftFromDb > 0 ? _formatInputAmount(perAreaDisplay) : '';
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

          _agentPercentageControllers[i] =
              TextEditingController(text: _agentPercentage[i] ?? '');
          _agentFixedFeeControllers[i] =
              TextEditingController(text: _agentFixedFee[i] ?? '');
          _agentMonthlyFeeControllers[i] =
              TextEditingController(text: _agentMonthlyFee[i] ?? '');
          _agentMonthsControllers[i] =
              TextEditingController(text: _agentMonths[i] ?? '');
          _agentPerSqftFeeControllers[i] =
              TextEditingController(text: _agentPerSqftFee[i] ?? '');
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
            print(
                'Loading blocks for agent $index: $blocks (length: ${blocks.length})');
            _agentSelectedBlocks[index] = List<String>.from(blocks);
            print(
                'Stored blocks for agent $index: ${_agentSelectedBlocks[index]}');
          });
        });
        print(
            'After setState, _agentSelectedBlocks keys: ${_agentSelectedBlocks.keys.toList()}');
      }

      print('_loadProjectData: Successfully loaded all project data');
      print('  - Non-sellable areas: ${_nonSellableAreas.length}');
      print('  - Partners: ${_partners.length}');
      print('  - Expenses: ${_expenses.length}');
      print('  - Layouts: ${_layouts.length}');
      print('  - Project managers: ${_projectManagers.length}');
      print('  - Agents: ${_agents.length}');

      // Only show default empty non-sellable area on FIRST load if no areas exist
      // Once user sees and potentially removes it, never show it again (even if all areas deleted later)
      if (!_hasLoadedDataOnce &&
          _nonSellableAreas.isEmpty &&
          !hideDefaultNonSellable) {
        setState(() {
          _nonSellableAreas = [
            {'name': '', 'area': ''}
          ];
          _nonSellableNameControllers[0] = TextEditingController();
          _nonSellableAreaControllers[0] = TextEditingController();
          print(
              'First load with no non-sellable areas - added default empty template');
        });
      }

      // Mark that we've loaded data once and persist to local storage
      _hasLoadedDataOnce = true;
      _projectsLoadedThisSession.add(widget.projectId!);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('project_${widget.projectId}_has_loaded_once', true);
      print(
          '_loadProjectData: Set _hasLoadedDataOnce=true and persisted to local storage');
    } catch (e, stackTrace) {
      print('Error loading project data: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isAreaDataLoading = false;
        });
      } else {
        _isAreaDataLoading = false;
      }
    } finally {
      // Always reset the loading flag, even if there was an error
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      } else {
        _isLoadingData = false;
      }
      print('_loadProjectData: Finished loading, _isLoadingData set to false');
      // Recalculate errors after data has been loaded
      _notifyErrorState();
    }
  }

  Future<void> _setHideDefaultNonSellableTemplate(bool hide) async {
    final projectId = widget.projectId;
    if (projectId == null || projectId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('project_${projectId}_hide_default_non_sellable', hide);
  }

  String _formatDecimal(dynamic value) {
    if (value == null) return '0';

    double numValue;
    if (value is String) {
      numValue = double.tryParse(value) ?? 0.0;
    } else if (value is num) {
      numValue = value.toDouble();
    } else {
      return '0';
    }

    // Use smart formatting helper
    return _formatAmountDisplay(numValue, decimalPlaces: 2);
  }

  /// Map UI expense category labels to database values enforced by expenses_category_check.
  String _mapExpenseCategoryForDatabase(String category) {
    return category.trim();
  }

  /// Map database expense category back to UI label for display.
  String _mapExpenseCategoryFromDatabase(String category) {
    return category.trim();
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
    // Calculate area errors from current controller values
    _hasAreaErrors = _calculateAreaErrors();
    _hasPartnerErrors = _hasPartnerValidationErrors;
    _hasExpenseErrors = _hasExpenseValidationErrors;
    // Site errors would be checked separately if needed
    _hasSiteErrors = false;
    _hasProjectManagerErrors = _hasProjectManagerValidationErrors;
    _hasAgentErrors = _hasAgentValidationErrors;
    _hasAboutErrors = _hasAboutValidationErrors;

    // Notify section callbacks
    widget.onAreaErrorsChanged?.call(_hasAreaErrors);
    widget.onPartnerErrorsChanged?.call(_hasPartnerErrors);
    widget.onExpenseErrorsChanged?.call(_hasExpenseErrors);
    widget.onSiteErrorsChanged?.call(_hasSiteErrors);
    widget.onProjectManagerErrorsChanged?.call(_hasProjectManagerErrors);
    widget.onAgentErrorsChanged?.call(_hasAgentErrors);
    widget.onAboutErrorsChanged?.call(_hasAboutErrors);

    // Notify if there are any validation errors (partners, expenses, project managers, agents, or about)
    widget.onErrorStateChanged?.call(_hasPartnerValidationErrors ||
        _hasExpenseValidationErrors ||
        _hasProjectManagerValidationErrors ||
        _hasAgentValidationErrors ||
        _hasAboutValidationErrors);
  }

  bool _calculateAreaErrors() {
    final totalArea = double.tryParse(_totalAreaController.text
            .replaceAll(',', '')
            .replaceAll(' ', '')) ??
        0;
    final sellingArea = double.tryParse(_sellingAreaController.text
            .replaceAll(',', '')
            .replaceAll(' ', '')) ??
        0;
    final hasRedShadow = totalArea == 0 || sellingArea == 0;
    final sellingExceedsTotal = sellingArea > totalArea && totalArea > 0;

    // Check if any non-sellable area blocks have empty values (red shadows)
    bool hasNonSellableRedShadows = false;
    for (var area in _nonSellableAreas) {
      final areaValue =
          double.tryParse(area['area']?.replaceAll(',', '') ?? '0') ?? 0;
      final nameValue = area['name'] ?? '';
      if (areaValue == 0 || nameValue.isEmpty) {
        hasNonSellableRedShadows = true;
        break;
      }
    }

    return hasRedShadow || sellingExceedsTotal || hasNonSellableRedShadows;
  }

  String _projectStorageKey() {
    return widget.projectId?.trim().isNotEmpty == true
        ? widget.projectId!
        : 'local_project';
  }

  Future<void> _loadProjectAboutFromStorage() async {
    final stored = await LayoutStorageService.loadProjectAbout(
      projectKey: _projectStorageKey(),
    );

    if (_projectAddressController.text.trim().isEmpty &&
        stored['address'] != null) {
      _projectAddressController.text = stored['address'] ?? '';
    }
    if (_googleMapsLinkController.text.trim().isEmpty &&
        stored['mapsLink'] != null) {
      _googleMapsLinkController.text = stored['mapsLink'] ?? '';
    }
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
    LayoutStorageService.saveProjectAbout(
      projectKey: _projectStorageKey(),
      projectAddress: _projectAddressController.text.trim(),
      googleMapsLink: _googleMapsLinkController.text.trim(),
    );

    // Debounce both error state and save status callbacks to prevent rebuilds on every keystroke
    _dataChangedDebounceTimer?.cancel();
    _dataChangedDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      // Prevent focus drops while editing percentage cells in PM/Agent tables.
      // We'll save once focus leaves the field.
      if (_isAnyPercentageFieldFocused()) {
        return;
      }

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

  bool _isAnyPercentageFieldFocused() {
    for (final node in _projectManagerPercentageFocusNodes.values) {
      if (node.hasFocus) return true;
    }
    for (final node in _agentPercentageFocusNodes.values) {
      if (node.hasFocus) return true;
    }
    return false;
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
        final layoutName = layoutNameController?.text ??
            layout['name'] ??
            'Layout ${layoutIndex + 1}';

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
          final allInCost = _approvedSellingArea > 0
              ? _totalExpenses / _approvedSellingArea
              : 0.0;

          // Calculate Total Plot Cost = Area (sqft) * All-in Cost. Convert display area to sqft.
          final areaDisplay = double.tryParse(plotAreaController?.text
                      .replaceAll(',', '')
                      .replaceAll(' ', '')
                      .trim() ??
                  '0') ??
              0.0;
          final areaSqft =
              AreaUnitUtils.areaFromDisplayToSqft(areaDisplay, _isSqm);
          final totalPlotCost = areaSqft * allInCost;

          // Debug logging for first plot only
          if (plotIndex == 0 && layoutIndex == 0) {
            print(
                'All-in Cost calculation: _totalExpenses=$_totalExpenses, _approvedSellingArea=$_approvedSellingArea, allInCost=$allInCost');
          }

          print(
              'DEBUG: Saving plot ${plotNumber}: partners=$plotPartners (${plotPartners.length} partners)');

          plotsData.add({
            'plotNumber': plotNumber,
            'area': _formatDecimal(areaSqft),
            'purchaseRate':
                allInCost.toStringAsFixed(2), // Save calculated all-in cost
            'totalPlotCost': totalPlotCost
                .toStringAsFixed(2), // Save calculated total plot cost
            'partners': plotPartners,
            'status': plots[plotIndex]['status']?.toString() ?? 'available',
            'salePrice': plots[plotIndex]['salePrice']?.toString(),
            'buyerName': plots[plotIndex]['buyerName']?.toString(),
            'saleDate': plots[plotIndex]['saleDate']?.toString(),
            'agent': plots[plotIndex]['agent']?.toString(),
            'payments': plots[plotIndex]['payments'] ?? [],
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
        final percentage =
            _projectManagerPercentageControllers[i]?.text.replaceAll(',', '') ??
                _projectManagerPercentage[i] ??
                '';
        final fixedFee =
            _projectManagerFixedFeeControllers[i]?.text.replaceAll(',', '') ??
                _projectManagerFixedFee[i] ??
                '';
        final monthlyFee =
            _projectManagerMonthlyFeeControllers[i]?.text.replaceAll(',', '') ??
                _projectManagerMonthlyFee[i] ??
                '';
        final months = _projectManagerMonthsControllers[i]?.text ??
            _projectManagerMonths[i] ??
            '';

        print(
            'Saving Project Manager $i: name=$name, compensation=$compensation, earningType=$earningType, percentage=$percentage, fixedFee=$fixedFee, monthlyFee=$monthlyFee, months=$months');

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
        final compensation = _agentCompensation[i] ??
            _agents[i]['compensation']?.toString() ??
            '';
        final earningType =
            _agentEarningType[i] ?? _agents[i]['earningType']?.toString() ?? '';
        final percentage =
            _agentPercentageControllers[i]?.text.replaceAll(',', '') ??
                _agentPercentage[i] ??
                '';
        final fixedFee =
            _agentFixedFeeControllers[i]?.text.replaceAll(',', '') ??
                _agentFixedFee[i] ??
                '';
        final monthlyFee =
            _agentMonthlyFeeControllers[i]?.text.replaceAll(',', '') ??
                _agentMonthlyFee[i] ??
                '';
        final months =
            _agentMonthsControllers[i]?.text ?? _agentMonths[i] ?? '';
        final perSqftDisplay = double.tryParse(_agentPerSqftFeeControllers[i]
                    ?.text
                    .replaceAll(',', '')
                    .replaceAll(' ', '') ??
                _agentPerSqftFee[i] ??
                '0') ??
            0.0;
        final perSqftFee = (perSqftDisplay > 0)
            ? AreaUnitUtils.rateFromDisplayToSqft(perSqftDisplay, _isSqm)
                .toStringAsFixed(2)
            : '';

        print(
            'Saving Agent $i: name=$name, compensation=$compensation (from map: ${_agentCompensation[i]}, from data: ${_agents[i]['compensation']}), earningType=$earningType, percentage=$percentage, fixedFee=$fixedFee, monthlyFee=$monthlyFee, months=$months, perSqftFee=$perSqftFee (display=$perSqftDisplay)');

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
      print(
          'Preparing non-sellable areas: _nonSellableAreas.length=${_nonSellableAreas.length}, controllers.length=${_nonSellableNameControllers.length}');
      for (int i = 0; i < _nonSellableAreas.length; i++) {
        final nameController = _nonSellableNameControllers[i];
        final areaController = _nonSellableAreaControllers[i];
        final name = nameController?.text.trim() ??
            _nonSellableAreas[i]['name']?.toString().trim() ??
            '';
        final areaDisplay = double.tryParse(areaController?.text
                    .replaceAll(',', '')
                    .replaceAll(' ', '')
                    .trim() ??
                _nonSellableAreas[i]['area']
                    ?.toString()
                    .replaceAll(',', '')
                    .replaceAll(' ', '')
                    .trim() ??
                '0.00') ??
            0.0;
        final areaSqft =
            AreaUnitUtils.areaFromDisplayToSqft(areaDisplay, _isSqm);
        print(
            'Non-sellable area $i: name="$name", area display=$areaDisplay -> sqft=$areaSqft');
        if (name.isNotEmpty) {
          nonSellableAreasData
              .add({'name': name, 'area': _formatDecimal(areaSqft)});
        }
      }
      print('Prepared ${nonSellableAreasData.length} non-sellable areas');

      // Prepare partners data
      final partnersData = <Map<String, dynamic>>[];
      print(
          'Preparing partners: _partners.length=${_partners.length}, controllers.length=${_partnerNameControllers.length}');
      for (int i = 0; i < _partners.length; i++) {
        final nameController = _partnerNameControllers[i];
        final amountController = _partnerAmountControllers[i];
        // Use controller text if available, otherwise fall back to data structure
        final name = nameController?.text.trim() ??
            _partners[i]['name']?.toString().trim() ??
            '';
        final amount = amountController?.text
                .replaceAll(',', '')
                .replaceAll(' ', '')
                .trim() ??
            _partners[i]['amount']
                ?.toString()
                .replaceAll(',', '')
                .replaceAll(' ', '')
                .trim() ??
            '0.00';
        print(
            'Partner $i: name="$name", amount="$amount", controller exists=${nameController != null}');
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
      print(
          'Preparing expenses: _expenses.length=${_expenses.length}, controllers.length=${_expenseItemControllers.length}');
      for (int i = 0; i < _expenses.length; i++) {
        final itemController = _expenseItemControllers[i];
        final amountController = _expenseAmountControllers[i];
        // Use controller text if available and non-empty, otherwise fall back to data structure
        final item = itemController?.text.trim() ??
            _expenses[i]['item']?.toString().trim() ??
            '';
        final controllerAmount = amountController?.text
                .replaceAll(',', '')
                .replaceAll(' ', '')
                .trim() ??
            '';
        final amount = controllerAmount.isNotEmpty
            ? controllerAmount
            : (_expenses[i]['amount']
                    ?.toString()
                    .replaceAll(',', '')
                    .replaceAll(' ', '')
                    .trim() ??
                '0.00');
        final rawCategory = _expenses[i]['category']?.toString().trim() ?? '';
        // Map UI category labels to database enum values (see expenses_category_check)
        final category = _mapExpenseCategoryForDatabase(rawCategory);
        print(
            'Expense $i: item="$item", amount="$amount", category="$category", controller exists=${itemController != null}');
        if (item.isNotEmpty && category.isNotEmpty) {
          expensesData
              .add({'item': item, 'amount': amount, 'category': category});
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

      print(
          'Project Managers safety check: controllers.length=${_projectManagerNameControllers.length}, _projectManagers.length=${_projectManagers.length}, canSafelySave=$canSafelySaveProjectManagers, projectManagersData.length=${projectManagersData.length}');

      List<Map<String, dynamic>>? finalProjectManagersData;
      if (canSafelySaveProjectManagers) {
        if (_projectManagers.isEmpty) {
          // Explicitly delete all if user removed them
          finalProjectManagersData = [];
          print('Project Managers: Setting to empty list (user removed all)');
        } else if (projectManagersData.isNotEmpty) {
          // Save valid data
          finalProjectManagersData = projectManagersData;
          print(
              'Project Managers: Will save ${projectManagersData.length} managers');
        } else {
          print(
              'Project Managers: Data is empty but _projectManagers is not empty, passing null to avoid deletion');
        }
        // If _projectManagers is NOT empty but projectManagersData IS empty (e.g. all filtered out),
        // we pass null to avoid accidental deletion of existing data.
      } else {
        print(
            'Project Managers: Safety check FAILED - controllers and data model out of sync, NOT saving');
      }

      // Agents safety check
      final canSafelySaveAgents =
          _agentNameControllers.length == _agents.length;

      print(
          'Agents safety check: controllers.length=${_agentNameControllers.length}, _agents.length=${_agents.length}, canSafelySave=$canSafelySaveAgents, agentsData.length=${agentsData.length}');

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
          print(
              'Agents: Data is empty but _agents is not empty, passing null to avoid deletion');
        }
        // Same safety logic as project managers
      } else {
        print(
            'Agents: Safety check FAILED - controllers and data model out of sync, NOT saving');
      }

      // Save all data to Supabase
      // Clean the area values by removing commas, spaces, and other formatting
      // Convert from display unit to sqft for storage
      final totalAreaDisplay = double.tryParse(_totalAreaController.text
              .replaceAll(',', '')
              .replaceAll(' ', '')
              .trim()) ??
          0.0;
      final sellingAreaDisplay = double.tryParse(_sellingAreaController.text
              .replaceAll(',', '')
              .replaceAll(' ', '')
              .trim()) ??
          0.0;
      final totalAreaSqft =
          AreaUnitUtils.areaFromDisplayToSqft(totalAreaDisplay, _isSqm);
      final sellingAreaSqft =
          AreaUnitUtils.areaFromDisplayToSqft(sellingAreaDisplay, _isSqm);
      final totalAreaText =
          totalAreaDisplay == 0 ? '' : _formatDecimal(totalAreaSqft);
      final sellingAreaText =
          sellingAreaDisplay == 0 ? '' : _formatDecimal(sellingAreaSqft);
      final estimatedCostText = _estimatedDevelopmentCostController.text
          .replaceAll(',', '')
          .replaceAll(' ', '')
          .trim();

      print('Saving project data: projectId=${widget.projectId}');
      print('  totalArea: display=$totalAreaDisplay -> sqft=$totalAreaSqft');
      print(
          '  sellingArea: display=$sellingAreaDisplay -> sqft=$sellingAreaSqft');
      print(
          '  nonSellableAreas=${nonSellableAreasData.length}, partners=${partnersData.length}, expenses=${expensesData.length}, layouts=${layoutsData.length}, projectManagers=${projectManagersData.length}, agents=${agentsData.length}');

      await ProjectStorageService.saveProjectData(
        projectId: widget.projectId!,
        projectName: _projectNameController.text.trim(),
        projectAddress: _projectAddressController.text.trim(),
        googleMapsLink: _googleMapsLinkController.text.trim(),
        totalArea: totalAreaText.isEmpty ? '' : totalAreaText,
        sellingArea: sellingAreaText.isEmpty ? '' : sellingAreaText,
        estimatedDevelopmentCost:
            estimatedCostText.isEmpty ? '' : estimatedCostText,
        nonSellableAreas: nonSellableAreasData,
        partners: shouldSavePartners
            ? partnersData
            : null, // Only pass partners if we should save them
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
      plotPartners: _plotPartners,
    );
  }

  void _saveAgentsData() {
    // Save agents data to local storage
    LayoutStorageService.saveAgentsData(_agents);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // If there's a pending debounce, cancel it and flush the save to Supabase.
    // Without this, partner/layout changes would only go to local storage and be lost on refresh.
    if (_dataChangedDebounceTimer?.isActive ?? false) {
      _dataChangedDebounceTimer?.cancel();
      _notifyErrorState();
      widget.onSaveStatusChanged?.call(ProjectSaveStatusType.saving);
      if (widget.projectId != null &&
          widget.projectId!.isNotEmpty &&
          !_isLoadingData) {
        _saveToSupabase(); // Flush pending save before dispose - reads controllers while still valid
      }
      _saveLayoutsData();
      _saveAgentsData();
    }

    _saveStatusTimer?.cancel();
    _dataChangedDebounceTimer?.cancel();
    _projectNameController.dispose();
    _projectAddressController.dispose();
    _googleMapsLinkController.dispose();
    _totalAreaController.dispose();
    _sellingAreaController.dispose();
    _projectNameFocusNode.removeListener(_aboutFocusRefreshListener);
    _projectAddressFocusNode.removeListener(_aboutFocusRefreshListener);
    _googleMapsLinkFocusNode.removeListener(_aboutFocusRefreshListener);
    _projectNameFocusNode.dispose();
    _projectAddressFocusNode.dispose();
    _googleMapsLinkFocusNode.dispose();
    _totalAreaFocusNode.dispose();
    _sellingAreaFocusNode.dispose();
    _estimatedDevelopmentCostFocusNode.dispose();
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
    for (var focusNode in _partnerNameFocusNodes.values) {
      focusNode.dispose();
    }
    _partnerNameFocusNodes.clear();
    for (var controller in _partnerAmountControllers.values) {
      controller.dispose();
    }
    _partnerAmountControllers.clear();
    for (var focusNode in _partnerAmountFocusNodes.values) {
      focusNode.dispose();
    }
    _partnerAmountFocusNodes.clear();
    // Dispose all expense controllers
    for (var controller in _expenseItemControllers.values) {
      controller.dispose();
    }
    _expenseItemControllers.clear();
    for (var focusNode in _expenseItemFocusNodes.values) {
      focusNode.dispose();
    }
    _expenseItemFocusNodes.clear();
    for (var controller in _expenseAmountControllers.values) {
      controller.dispose();
    }
    _expenseAmountControllers.clear();
    for (var focusNode in _expenseAmountFocusNodes.values) {
      focusNode.dispose();
    }
    _expenseAmountFocusNodes.clear();
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
    for (var focusNode in _plotNumberFocusNodes.values) {
      focusNode.dispose();
    }
    _plotNumberFocusNodes.clear();
    for (var controller in _plotAreaControllers.values) {
      controller.dispose();
    }
    _plotAreaControllers.clear();
    for (var focusNode in _plotAreaFocusNodes.values) {
      focusNode.dispose();
    }
    _plotAreaFocusNodes.clear();
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
    for (var focusNode in _projectManagerNameFocusNodes.values) {
      focusNode.dispose();
    }
    _projectManagerNameFocusNodes.clear();
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
    for (var focusNode in _agentNameFocusNodes.values) {
      focusNode.dispose();
    }
    _agentNameFocusNodes.clear();
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
    for (var controller in _plotsTableVerticalScrollControllers.values) {
      controller.dispose();
    }
    _plotsTableVerticalScrollControllers.clear();
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
    return Container(
      width: 178,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
            child: DecimalInputField(
              controller: _projectManagerFixedFeeControllers[index]!,
              focusNode: _projectManagerFixedFeeFocusNodes[index]!,
              hintText: '0',
              inputFormatters: [IndianNumberFormatter(maxIntegerDigits: 11)],
              onTap: () {
                // Clear '0.00' when field is tapped
                final cleaned = _projectManagerFixedFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '')
                    .trim();
                if (cleaned == '0' || cleaned == '0.00') {
                  _projectManagerFixedFeeControllers[index]!.text = '';
                  _projectManagerFixedFeeControllers[index]!.selection =
                      TextSelection.collapsed(offset: 0);
                }
              },
              onChanged: (value) {
                // Remove commas for storage (for real-time calculations)
                final rawValue = value
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                // Update values directly without setState or callbacks to avoid rebuild and focus loss
                _projectManagerFixedFee[index] =
                    rawValue.isEmpty ? '0' : rawValue;
                _projectManagers[index]['fixedFee'] =
                    rawValue.isEmpty ? '0' : rawValue;
                // Don't call _onDataChanged() here - it triggers parent rebuilds
                // Will be called in onEditingComplete instead
              },
              onEditingComplete: () {
                // Remove commas before formatting
                final cleaned = _projectManagerFixedFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                final formatted = _formatAmount(cleaned);
                FocusScope.of(context).unfocus();
                _projectManagerFixedFeeControllers[index]!.value =
                    TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
                setState(() {
                  _projectManagerFixedFee[index] =
                      formatted.replaceAll(',', '');
                  _projectManagers[index]['fixedFee'] =
                      formatted.replaceAll(',', '');
                });
                _onDataChanged();
              },
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
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
    return Container(
      width: 178,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
            child: DecimalInputField(
              controller: _projectManagerMonthlyFeeControllers[index]!,
              focusNode: _projectManagerMonthlyFeeFocusNodes[index]!,
              hintText: '0',
              inputFormatters: [IndianNumberFormatter(maxIntegerDigits: 11)],
              onTap: () {
                // Clear '0.00' when field is tapped
                final cleaned = _projectManagerMonthlyFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '')
                    .trim();
                if (cleaned == '0' || cleaned == '0.00') {
                  _projectManagerMonthlyFeeControllers[index]!.text = '';
                  _projectManagerMonthlyFeeControllers[index]!.selection =
                      TextSelection.collapsed(offset: 0);
                }
              },
              onChanged: (value) {
                // Remove commas for storage (for real-time calculations)
                final rawValue = value
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                // Update values directly without setState or callbacks to avoid rebuild and focus loss
                _projectManagerMonthlyFee[index] =
                    rawValue.isEmpty ? '0' : rawValue;
                _projectManagers[index]['monthlyFee'] =
                    rawValue.isEmpty ? '0' : rawValue;
                // Don't call _onDataChanged() here - it triggers parent rebuilds
                // Will be called in onEditingComplete instead
              },
              onEditingComplete: () {
                // Remove commas before formatting
                final cleaned = _projectManagerMonthlyFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                final formatted = _formatAmount(cleaned);
                FocusScope.of(context).unfocus();
                _projectManagerMonthlyFeeControllers[index]!.value =
                    TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
                setState(() {
                  _projectManagerMonthlyFee[index] =
                      formatted.replaceAll(',', '');
                  _projectManagers[index]['monthlyFee'] =
                      formatted.replaceAll(',', '');
                });
                _onDataChanged();
              },
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
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
    return Container(
      width: 178,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
            child: DecimalInputField(
              controller: _agentFixedFeeControllers[index]!,
              focusNode: _agentFixedFeeFocusNodes[index]!,
              hintText: '0',
              inputFormatters: [IndianNumberFormatter(maxIntegerDigits: 11)],
              onTap: () {
                // Clear '0.00' when field is tapped
                final cleaned = _agentFixedFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '')
                    .trim();
                if (cleaned == '0' || cleaned == '0.00') {
                  _agentFixedFeeControllers[index]!.text = '';
                  _agentFixedFeeControllers[index]!.selection =
                      TextSelection.collapsed(offset: 0);
                }
              },
              onChanged: (value) {
                // Remove commas for storage (for real-time calculations)
                final rawValue = value
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                // Update values directly without setState or callbacks to avoid rebuild and focus loss
                _agentFixedFee[index] = rawValue.isEmpty ? '0' : rawValue;
                _agents[index]['fixedFee'] = rawValue.isEmpty ? '0' : rawValue;
                // Don't call _onDataChanged() here - it triggers parent rebuilds
                // Will be called in onEditingComplete instead
              },
              onEditingComplete: () {
                // Remove commas before formatting
                final cleaned = _agentFixedFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                final formatted = _formatAmount(cleaned);
                FocusScope.of(context).unfocus();
                _agentFixedFeeControllers[index]!.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
                setState(() {
                  _agentFixedFee[index] = formatted.replaceAll(',', '');
                  _agents[index]['fixedFee'] = formatted.replaceAll(',', '');
                });
                _onDataChanged();
              },
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
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
    return Container(
      width: 178,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
            child: DecimalInputField(
              controller: _agentMonthlyFeeControllers[index]!,
              focusNode: _agentMonthlyFeeFocusNodes[index]!,
              hintText: '0',
              inputFormatters: [IndianNumberFormatter(maxIntegerDigits: 11)],
              onTap: () {
                // Clear '0.00' when field is tapped
                final cleaned = _agentMonthlyFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '')
                    .trim();
                if (cleaned == '0' || cleaned == '0.00') {
                  _agentMonthlyFeeControllers[index]!.text = '';
                  _agentMonthlyFeeControllers[index]!.selection =
                      TextSelection.collapsed(offset: 0);
                }
              },
              onChanged: (value) {
                // Remove commas for storage (for real-time calculations)
                final rawValue = value
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                // Update values directly without setState or callbacks to avoid rebuild and focus loss
                _agentMonthlyFee[index] = rawValue.isEmpty ? '0' : rawValue;
                _agents[index]['monthlyFee'] =
                    rawValue.isEmpty ? '0' : rawValue;
                // Don't call _onDataChanged() here - it triggers parent rebuilds
                // Will be called in onEditingComplete instead
              },
              onEditingComplete: () {
                // Remove commas before formatting
                final cleaned = _agentMonthlyFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                final formatted = _formatAmount(cleaned);
                FocusScope.of(context).unfocus();
                _agentMonthlyFeeControllers[index]!.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
                setState(() {
                  _agentMonthlyFee[index] = formatted.replaceAll(',', '');
                  _agents[index]['monthlyFee'] = formatted.replaceAll(',', '');
                });
                _onDataChanged();
              },
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
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
    return Container(
      width: 178,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
            child: DecimalInputField(
              controller: _agentPerSqftFeeControllers[index]!,
              focusNode: _agentPerSqftFeeFocusNodes[index]!,
              hintText: '0',
              inputFormatters: [IndianNumberFormatter(maxIntegerDigits: 11)],
              onTap: () {
                // Clear '0.00' when field is tapped
                final cleaned = _agentPerSqftFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '')
                    .trim();
                if (cleaned == '0' || cleaned == '0.00') {
                  _agentPerSqftFeeControllers[index]!.text = '';
                  _agentPerSqftFeeControllers[index]!.selection =
                      TextSelection.collapsed(offset: 0);
                }
              },
              onChanged: (value) {
                // Remove commas for storage (for real-time calculations)
                final rawValue = value
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                // Update values directly without setState or callbacks to avoid rebuild and focus loss
                _agentPerSqftFee[index] = rawValue.isEmpty ? '0' : rawValue;
                _agents[index]['perSqftFee'] =
                    rawValue.isEmpty ? '0' : rawValue;
                // Don't call _onDataChanged() here - it triggers parent rebuilds
                // Will be called in onEditingComplete instead
              },
              onEditingComplete: () {
                // Remove commas before formatting
                final cleaned = _agentPerSqftFeeControllers[index]!
                    .text
                    .replaceAll(',', '')
                    .replaceAll('₹', '')
                    .replaceAll(' ', '');
                final formatted = _formatAmount(cleaned);
                FocusScope.of(context).unfocus();
                _agentPerSqftFeeControllers[index]!.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
                setState(() {
                  _agentPerSqftFee[index] = formatted.replaceAll(',', '');
                  _agents[index]['perSqftFee'] = formatted.replaceAll(',', '');
                });
                _onDataChanged();
              },
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build project manager months field
  Widget _buildProjectManagerMonthsField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_projectManagerMonthsControllers[index] == null) {
      final currentMonthsValue = _projectManagerMonths[index] ?? '';
      _projectManagerMonthsControllers[index] =
          TextEditingController(text: currentMonthsValue);
    }
    if (_projectManagerMonthsFocusNodes[index] == null) {
      _projectManagerMonthsFocusNodes[index] = FocusNode();
    }
    return Container(
      width: 73,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Center(
        child: TextField(
          key: Key('pm_months_$index'),
          controller: _projectManagerMonthsControllers[index],
          focusNode: _projectManagerMonthsFocusNodes[index],
          keyboardType: TextInputType.number,
          textAlignVertical: TextAlignVertical.center,
          textAlign: TextAlign.center,
          inputFormatters: [MonthsInputFormatter()],
          onTap: () {
            // Ensure cursor is visible on tap
            if (!_projectManagerMonthsFocusNodes[index]!.hasFocus) {
              _projectManagerMonthsFocusNodes[index]!.requestFocus();
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_projectManagerMonthsFocusNodes[index]!.hasFocus) {
                final text = _projectManagerMonthsControllers[index]!.text;
                final cursorPosition = text.length;
                _projectManagerMonthsControllers[index]!.selection =
                    TextSelection.collapsed(offset: cursorPosition);
              }
            });
          },
          onChanged: (value) {
            // Update values directly without setState or callbacks to avoid rebuild and focus loss
            _projectManagerMonths[index] = value;
            _projectManagers[index]['months'] = value;
            // Don't call _onDataChanged() here - it triggers parent rebuilds
            // Will be called in onEditingComplete instead
          },
          onEditingComplete: () {
            setState(() {
              _projectManagerMonths[index] =
                  _projectManagerMonthsControllers[index]!.text;
              _projectManagers[index]['months'] =
                  _projectManagerMonthsControllers[index]!.text;
            });
            _onDataChanged();
            FocusScope.of(context).nextFocus();
          },
          decoration: InputDecoration(
            hintText: 'Months',
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color.fromARGB(191, 173, 173, 173),
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 11),
            isDense: true,
          ),
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  // Helper method to build agent months field
  Widget _buildAgentMonthsField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_agentMonthsControllers[index] == null) {
      final currentMonthsValue = _agentMonths[index] ?? '';
      _agentMonthsControllers[index] =
          TextEditingController(text: currentMonthsValue);
    }
    if (_agentMonthsFocusNodes[index] == null) {
      _agentMonthsFocusNodes[index] = FocusNode();
    }
    return Container(
      width: 73,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Center(
        child: TextField(
          key: Key('agent_months_$index'),
          controller: _agentMonthsControllers[index],
          focusNode: _agentMonthsFocusNodes[index],
          keyboardType: TextInputType.number,
          textAlignVertical: TextAlignVertical.center,
          textAlign: TextAlign.center,
          inputFormatters: [MonthsInputFormatter()],
          onTap: () {
            // Ensure cursor is visible on tap
            if (!_agentMonthsFocusNodes[index]!.hasFocus) {
              _agentMonthsFocusNodes[index]!.requestFocus();
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_agentMonthsFocusNodes[index]!.hasFocus) {
                final text = _agentMonthsControllers[index]!.text;
                final cursorPosition = text.length;
                _agentMonthsControllers[index]!.selection =
                    TextSelection.collapsed(offset: cursorPosition);
              }
            });
          },
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
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color.fromARGB(191, 173, 173, 173),
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 11),
            isDense: true,
          ),
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  // Helper method to build project manager percentage field
  Widget _buildProjectManagerPercentageField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_projectManagerPercentageControllers[index] == null) {
      final currentPercentageValue = _projectManagerPercentage[index] ?? '0';
      _projectManagerPercentageControllers[index] = TextEditingController(
          text: currentPercentageValue == '0' ? '' : currentPercentageValue);
    }
    if (_projectManagerPercentageFocusNodes[index] == null) {
      _projectManagerPercentageFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _projectManagerPercentageFocusNodes[index]!,
      height: 40,
      backgroundColor: Colors.white,
      onFocusLost: () {
        final numValue =
            _projectManagerPercentageControllers[index]!.text.isEmpty
                ? '0'
                : _projectManagerPercentageControllers[index]!.text;
        _projectManagerPercentage[index] = numValue;
        _projectManagers[index]['percentage'] = numValue;
        _onDataChanged();
      },
      child: Center(
        child: TextField(
          key: Key('pm_percentage_$index'),
          controller: _projectManagerPercentageControllers[index],
          focusNode: _projectManagerPercentageFocusNodes[index],
          keyboardType: TextInputType.number,
          textAlignVertical: TextAlignVertical.center,
          textAlign: TextAlign.center,
          showCursor: true,
          inputFormatters: [PercentageInputFormatter()],
          onTap: () => _requestFocusAndCursorAfterTap(
              _projectManagerPercentageFocusNodes[index]!,
              _projectManagerPercentageControllers[index]!),
          onChanged: (value) {
            // Update values directly without setState or callbacks to avoid rebuild and focus loss
            final numValue = value.isEmpty ? '0' : value;
            _projectManagerPercentage[index] = numValue;
            _projectManagers[index]['percentage'] = numValue;
          },
          onSubmitted: (_) {
            final numValue =
                _projectManagerPercentageControllers[index]!.text.isEmpty
                    ? '0'
                    : _projectManagerPercentageControllers[index]!.text;
            setState(() {
              _projectManagerPercentage[index] = numValue;
              _projectManagers[index]['percentage'] = numValue;
            });
            _onDataChanged();
          },
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color.fromARGB(191, 173, 173, 173),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            isDense: true,
          ),
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  // Helper method to build agent percentage field
  Widget _buildAgentPercentageField(int index, BuildContext context) {
    // Ensure controller and focus node exist
    if (_agentPercentageControllers[index] == null) {
      final currentPercentageValue = _agentPercentage[index] ?? '0';
      _agentPercentageControllers[index] = TextEditingController(
          text: currentPercentageValue == '0' ? '' : currentPercentageValue);
    }
    if (_agentPercentageFocusNodes[index] == null) {
      _agentPercentageFocusNodes[index] = FocusNode();
    }
    return _buildFocusAwareInputContainer(
      focusNode: _agentPercentageFocusNodes[index]!,
      height: 40,
      backgroundColor: Colors.white,
      onFocusLost: () {
        final numValue = _agentPercentageControllers[index]!.text.isEmpty
            ? '0'
            : _agentPercentageControllers[index]!.text;
        _agentPercentage[index] = numValue;
        _agents[index]['percentage'] = numValue;
        _onDataChanged();
      },
      child: TextField(
        key: Key('agent_percentage_$index'),
        controller: _agentPercentageControllers[index],
        focusNode: _agentPercentageFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlignVertical: TextAlignVertical.center,
        textAlign: TextAlign.center,
        showCursor: true,
        inputFormatters: [PercentageInputFormatter()],
        onTap: () => _requestFocusAndCursorAfterTap(
            _agentPercentageFocusNodes[index]!,
            _agentPercentageControllers[index]!),
        onChanged: (value) {
          // Update values directly without setState or callbacks to avoid rebuild and focus loss
          final numValue = value.isEmpty ? '0' : value;
          _agentPercentage[index] = numValue;
          _agents[index]['percentage'] = numValue;
          // Don't call _onDataChanged() here - it triggers parent rebuilds
          // Will be called in onSubmitted instead
        },
        onSubmitted: (_) {
          final numValue = _agentPercentageControllers[index]!.text.isEmpty
              ? '0'
              : _agentPercentageControllers[index]!.text;
          setState(() {
            _agentPercentage[index] = numValue;
            _agents[index]['percentage'] = numValue;
          });
          _onDataChanged();
        },
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: const Color.fromARGB(191, 173, 173, 173),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          isDense: true,
        ),
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black,
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
    Color? defaultShadowColor,
  }) {
    return _FocusAwareInputContainer(
      focusNode: focusNode,
      onFocusLost: onFocusLost,
      width: width,
      height: height,
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
      defaultShadowColor: defaultShadowColor,
      child: child,
    );
  }

  void _convertAllAreaValuesOnUnitChange(bool oldIsSqm, bool newIsSqm) {
    double toSqft(double v) => oldIsSqm ? v * AreaUnitUtils.sqmToSqft : v;
    double fromSqft(double sqft) =>
        newIsSqm ? sqft * AreaUnitUtils.sqftToSqm : sqft;
    double rateToSqft(double v) => oldIsSqm ? v / AreaUnitUtils.sqmToSqft : v;
    double rateFromSqft(double perSqft) =>
        newIsSqm ? perSqft * AreaUnitUtils.sqmToSqft : perSqft;

    final totalDisplay = double.tryParse(_totalAreaController.text
            .replaceAll(',', '')
            .replaceAll(' ', '')) ??
        0;
    _totalAreaController.text = totalDisplay == 0
        ? ''
        : _formatInputAmount(fromSqft(toSqft(totalDisplay)), decimalPlaces: 3);

    final sellingDisplay = double.tryParse(_sellingAreaController.text
            .replaceAll(',', '')
            .replaceAll(' ', '')) ??
        0;
    _sellingAreaController.text = sellingDisplay == 0
        ? ''
        : _formatInputAmount(fromSqft(toSqft(sellingDisplay)),
            decimalPlaces: 3);

    for (int i = 0; i < _nonSellableAreaControllers.length; i++) {
      final c = _nonSellableAreaControllers[i];
      if (c != null) {
        final v =
            double.tryParse(c.text.replaceAll(',', '').replaceAll(' ', '')) ??
                0;
        c.text = v == 0
            ? ''
            : _formatInputAmount(fromSqft(toSqft(v)), decimalPlaces: 3);
      }
    }
    for (int i = 0; i < _nonSellableAreas.length; i++) {
      final a = double.tryParse(
              _nonSellableAreas[i]['area']?.toString().replaceAll(',', '') ??
                  '0') ??
          0;
      _nonSellableAreas[i]['area'] =
          a == 0 ? '' : _formatDecimal(fromSqft(toSqft(a)));
    }
    for (final entry in _plotAreaControllers.entries) {
      final v = double.tryParse(
              entry.value.text.replaceAll(',', '').replaceAll(' ', '')) ??
          0;
      if (v > 0) {
        entry.value.text =
            _formatInputAmount(fromSqft(toSqft(v)), decimalPlaces: 3);
      }
    }
    // Convert agent per sqft/sqm fee (rates)
    for (final i in _agentPerSqftFeeControllers.keys) {
      final c = _agentPerSqftFeeControllers[i];
      if (c != null && (_agentCompensation[i] ?? '') == 'Per Sqft Fee') {
        final v =
            double.tryParse(c.text.replaceAll(',', '').replaceAll(' ', '')) ??
                0;
        if (v > 0) {
          c.text = _formatInputAmount(rateFromSqft(rateToSqft(v)));
        }
      }
    }
    for (final i in _agentPerSqftFee.keys) {
      if ((_agentCompensation[i] ?? '') == 'Per Sqft Fee') {
        final v = double.tryParse(
                (_agentPerSqftFee[i] ?? '0').toString().replaceAll(',', '')) ??
            0;
        if (v > 0) {
          _agentPerSqftFee[i] = _formatInputAmount(rateFromSqft(rateToSqft(v)));
          _agents[i]['perSqftFee'] = _agentPerSqftFee[i];
        }
      }
    }
  }

  Widget _buildAreaUnitSelector() {
    return AreaUnitSelector(
      selectedUnit: _selectedAreaUnit,
      projectId: widget.projectId,
      onUnitChanged: (newUnit) {
        final oldUnit = _selectedAreaUnit;
        if (oldUnit == newUnit) return;
        final oldIsSqm = AreaUnitUtils.isSqm(oldUnit);
        final newIsSqm = AreaUnitUtils.isSqm(newUnit);
        setState(() {
          _selectedAreaUnit = newUnit;
          _convertAllAreaValuesOnUnitChange(oldIsSqm, newIsSqm);
        });
        _onDataChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scaleMetrics = AppScaleMetrics.of(context);
    final tabLineWidth = scaleMetrics?.designViewportWidth ?? screenWidth;
    final extraTabLineWidth =
        tabLineWidth > screenWidth ? tabLineWidth - screenWidth : 0.0;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header section
        Padding(
          padding: const EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Details',
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        height:
                            1.25, // 40px line-height / 32px font-size = 1.25
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
              _buildAreaUnitSelector(),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Full-width TabBar
        SizedBox(
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: -extraTabLineWidth,
                bottom: 0,
                child: Container(
                  height: 0.5,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
              Row(
                children: [
                  const SizedBox(width: 24),
                  // Area tab
                  GestureDetector(
                    onTap: () => setState(() => _activeTab = ProjectTab.about),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Container(
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
                        Builder(
                          builder: (context) {
                            final totalArea = double.tryParse(
                                    _totalAreaController.text
                                        .replaceAll(',', '')
                                        .replaceAll(' ', '')) ??
                                0;
                            final sellingArea = double.tryParse(
                                    _sellingAreaController.text
                                        .replaceAll(',', '')
                                        .replaceAll(' ', '')) ??
                                0;
                            final hasRedShadow =
                                totalArea == 0 || sellingArea == 0;
                            final sellingExceedsTotal =
                                sellingArea > totalArea && totalArea > 0;

                            // Check if any non-sellable area blocks have empty values (red shadows)
                            bool hasNonSellableRedShadows = false;
                            for (var area in _nonSellableAreas) {
                              final areaValue = double.tryParse(
                                      area['area']?.replaceAll(',', '') ??
                                          '0') ??
                                  0;
                              final nameValue = area['name'] ?? '';
                              if (areaValue == 0 || nameValue.isEmpty) {
                                hasNonSellableRedShadows = true;
                                break;
                              }
                            }

                            // Check if remaining area is green or red
                            bool remainingAreaIsRed;
                            if (sellingExceedsTotal) {
                              remainingAreaIsRed = true;
                            } else if (_remainingArea == 0) {
                              remainingAreaIsRed = false;
                            } else if (_nonSellableAreas.isEmpty) {
                              remainingAreaIsRed = false;
                            } else if (_nonSellableAreas.length == 1 &&
                                (_nonSellableAreas[0]['area'] == '0.00' ||
                                    _nonSellableAreas[0]['area'] == '0' ||
                                    _nonSellableAreas[0]['area'] == '')) {
                              remainingAreaIsRed = false;
                            } else {
                              remainingAreaIsRed = true;
                            }

                            if (hasRedShadow ||
                                remainingAreaIsRed ||
                                hasNonSellableRedShadows) {
                              return Positioned(
                                top: -8,
                                child: SvgPicture.asset(
                                  'assets/images/Error_msg.svg',
                                  width: 17,
                                  height: 15,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    print(
                                        'Error loading Error_msg.svg: $error');
                                    return const SizedBox(
                                      width: 17,
                                      height: 15,
                                    );
                                  },
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 36),
                  // Partner(s) tab
                  GestureDetector(
                    onTap: () =>
                        setState(() => _activeTab = ProjectTab.partners),
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
                    onTap: () =>
                        setState(() => _activeTab = ProjectTab.expenses),
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
                    onTap: () =>
                        setState(() => _activeTab = ProjectTab.projectManagers),
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
                                fontWeight:
                                    _activeTab == ProjectTab.projectManagers
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
                              _isProjectManagerFirstRowWarningState
                                  ? 'assets/images/Warning.svg'
                                  : 'assets/images/Error_msg.svg',
                              width: 17,
                              height: 15,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                print(
                                    'Error loading project manager status icon: $error');
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
                              _isAgentFirstRowWarningState
                                  ? 'assets/images/Warning.svg'
                                  : 'assets/images/Error_msg.svg',
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
                  // About tab
                  GestureDetector(
                    onTap: () =>
                        setState(() => _activeTab = ProjectTab.aboutDetails),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: _activeTab == ProjectTab.aboutDetails
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
                              'About',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight:
                                    _activeTab == ProjectTab.aboutDetails
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                color: _activeTab == ProjectTab.aboutDetails
                                    ? const Color(0xFF0C8CE9)
                                    : const Color(0xFF5C5C5C),
                              ),
                            ),
                          ),
                        ),
                        if (_hasAboutValidationErrors)
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
                ],
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: ScrollbarTheme(
            data: ScrollbarThemeData(
              thickness: MaterialStateProperty.all(8),
              thumbVisibility: MaterialStateProperty.all(true),
              radius: const Radius.circular(4),
              minThumbLength: 233,
            ),
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                clipBehavior: Clip.hardEdge,
                padding: EdgeInsets.only(
                  top: 40,
                  left: 24,
                  right: 24,
                  bottom: 24,
                ),
                child: (_activeTab == ProjectTab.aboutDetails
                    ? _buildAboutContent()
                    : _activeTab == ProjectTab.about
                        ? ((_isAreaDataLoading && !_hasLoadedDataOnce)
                            ? _buildAreaLoadingSkeleton()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Site Area Details card
                                  Container(
                                    width: 600,
                                    margin: const EdgeInsets.only(bottom: 24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Fields container with header inside
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8F9FA),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.25),
                                                blurRadius: 2,
                                                offset: const Offset(0, 0),
                                                spreadRadius: 0,
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Header inside grey container
                                              Row(
                                                children: [
                                                  Text(
                                                    'Site Area Details',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.black,
                                                      height:
                                                          1.0, // line-height: normal
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                "Approved selling and non-sellable areas together make up the total project area.",
                                                style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.normal,
                                                  color: const Color(0xFF000000)
                                                      .withOpacity(0.8),
                                                  height:
                                                      1.0, // line-height: normal
                                                ),
                                              ),
                                              const SizedBox(height: 24),
                                              // Total Project Area field
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        'Total Project Area ',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Colors.black,
                                                        ),
                                                      ),
                                                      Text(
                                                        '*',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  _buildFocusAwareInputContainer(
                                                    focusNode:
                                                        _totalAreaFocusNode,
                                                    width: 184,
                                                    height: 40,
                                                    backgroundColor:
                                                        Colors.white,
                                                    defaultShadowColor:
                                                        (double.tryParse(_totalAreaController
                                                                        .text
                                                                        .replaceAll(
                                                                            ',',
                                                                            '')
                                                                        .replaceAll(
                                                                            ' ',
                                                                            '')) ??
                                                                    0) ==
                                                                0
                                                            ? Colors.red
                                                            : null,
                                                    onFocusLost: () {
                                                      final cleaned =
                                                          _totalAreaController
                                                              .text
                                                              .replaceAll(
                                                                  ',', '')
                                                              .replaceAll(
                                                                  ' ', '');
                                                      final formatted =
                                                          _formatAmount(cleaned,
                                                              decimalPlaces: 3);
                                                      _totalAreaController
                                                          .text = formatted;
                                                      setState(() {});
                                                      _onDataChanged();
                                                    },
                                                    child: Center(
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                DecimalInputField(
                                                              controller:
                                                                  _totalAreaController,
                                                              focusNode:
                                                                  _totalAreaFocusNode,
                                                              hintText: '0',
                                                              decimalPlaces: 3,
                                                              inputFormatters: [
                                                                IndianNumberFormatter(
                                                                    maxIntegerDigits:
                                                                        9)
                                                              ],
                                                              onTap: () {
                                                                final cleaned =
                                                                    _totalAreaController
                                                                        .text
                                                                        .replaceAll(
                                                                            ',',
                                                                            '')
                                                                        .replaceAll(
                                                                            ' ',
                                                                            '')
                                                                        .trim();
                                                                if (cleaned ==
                                                                        '0' ||
                                                                    cleaned ==
                                                                        '0.00') {
                                                                  _totalAreaController
                                                                      .text = '';
                                                                  _totalAreaController
                                                                          .selection =
                                                                      TextSelection.collapsed(
                                                                          offset:
                                                                              0);
                                                                  setState(
                                                                      () {});
                                                                }
                                                              },
                                                              onChanged: (_) {
                                                                setState(() {});
                                                                _onDataChanged();
                                                              },
                                                              onEditingComplete:
                                                                  () {
                                                                final cleaned =
                                                                    _totalAreaController
                                                                        .text
                                                                        .replaceAll(
                                                                            ',',
                                                                            '')
                                                                        .replaceAll(
                                                                            ' ',
                                                                            '');
                                                                final formatted =
                                                                    _formatAmount(
                                                                        cleaned,
                                                                        decimalPlaces:
                                                                            3);
                                                                _totalAreaFocusNode
                                                                    .unfocus();
                                                                _totalAreaController
                                                                        .value =
                                                                    TextEditingValue(
                                                                  text:
                                                                      formatted,
                                                                  selection: TextSelection
                                                                      .collapsed(
                                                                          offset:
                                                                              formatted.length),
                                                                );
                                                                setState(() {});
                                                                _onDataChanged();
                                                              },
                                                              contentPadding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      left: 0,
                                                                      right: 8,
                                                                      top: 8,
                                                                      bottom:
                                                                          8),
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    left: 8),
                                                            child: Text(
                                                              _areaUnitSuffix,
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .normal,
                                                                color: const Color(
                                                                    0xFF5C5C5C),
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        'Approved Selling Area ',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Colors.black,
                                                        ),
                                                      ),
                                                      Text(
                                                        '*',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  _buildFocusAwareInputContainer(
                                                    focusNode:
                                                        _sellingAreaFocusNode,
                                                    width: 184,
                                                    height: 40,
                                                    backgroundColor:
                                                        Colors.white,
                                                    defaultShadowColor:
                                                        (double.tryParse(_sellingAreaController
                                                                        .text
                                                                        .replaceAll(
                                                                            ',',
                                                                            '')
                                                                        .replaceAll(
                                                                            ' ',
                                                                            '')) ??
                                                                    0) ==
                                                                0
                                                            ? Colors.red
                                                            : null,
                                                    onFocusLost: () {
                                                      final cleaned =
                                                          _sellingAreaController
                                                              .text
                                                              .replaceAll(
                                                                  ',', '')
                                                              .replaceAll(
                                                                  ' ', '');
                                                      final formatted =
                                                          _formatAmount(cleaned,
                                                              decimalPlaces: 3);
                                                      _sellingAreaController
                                                          .text = formatted;
                                                      setState(() {});
                                                      _onDataChanged();
                                                    },
                                                    child: Center(
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                DecimalInputField(
                                                              controller:
                                                                  _sellingAreaController,
                                                              focusNode:
                                                                  _sellingAreaFocusNode,
                                                              hintText: '0',
                                                              decimalPlaces: 3,
                                                              inputFormatters: [
                                                                IndianNumberFormatter(
                                                                    maxIntegerDigits:
                                                                        9)
                                                              ],
                                                              onTap: () {
                                                                final cleaned =
                                                                    _sellingAreaController
                                                                        .text
                                                                        .replaceAll(
                                                                            ',',
                                                                            '')
                                                                        .replaceAll(
                                                                            ' ',
                                                                            '')
                                                                        .trim();
                                                                if (cleaned ==
                                                                        '0' ||
                                                                    cleaned ==
                                                                        '0.00') {
                                                                  _sellingAreaController
                                                                      .text = '';
                                                                  _sellingAreaController
                                                                          .selection =
                                                                      TextSelection.collapsed(
                                                                          offset:
                                                                              0);
                                                                  setState(
                                                                      () {});
                                                                }
                                                              },
                                                              onChanged: (_) {
                                                                setState(() {});
                                                                _onDataChanged();
                                                              },
                                                              onEditingComplete:
                                                                  () {
                                                                final cleaned =
                                                                    _sellingAreaController
                                                                        .text
                                                                        .replaceAll(
                                                                            ',',
                                                                            '')
                                                                        .replaceAll(
                                                                            ' ',
                                                                            '');
                                                                final formatted =
                                                                    _formatAmount(
                                                                        cleaned,
                                                                        decimalPlaces:
                                                                            3);
                                                                final sellingArea =
                                                                    double.tryParse(
                                                                            cleaned) ??
                                                                        0;
                                                                final totalArea = double.tryParse(_totalAreaController
                                                                        .text
                                                                        .replaceAll(
                                                                            ',',
                                                                            '')
                                                                        .replaceAll(
                                                                            ' ',
                                                                            '')) ??
                                                                    0;
                                                                _sellingAreaFocusNode
                                                                    .unfocus();
                                                                _sellingAreaController
                                                                        .value =
                                                                    TextEditingValue(
                                                                  text:
                                                                      formatted,
                                                                  selection: TextSelection
                                                                      .collapsed(
                                                                          offset:
                                                                              formatted.length),
                                                                );
                                                                setState(() {});
                                                                _onDataChanged();
                                                                // If selling area exceeds total area, don't move focus
                                                                if (!(sellingArea >
                                                                        totalArea &&
                                                                    totalArea >
                                                                        0)) {
                                                                  // Field already unfocused, no need to do anything
                                                                }
                                                              },
                                                              contentPadding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      left: 0,
                                                                      right: 8,
                                                                      top: 8,
                                                                      bottom:
                                                                          8),
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    left: 8),
                                                            child: Text(
                                                              _areaUnitSuffix,
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .normal,
                                                                color: const Color(
                                                                    0xFF5C5C5C),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  // Validation message when selling area exceeds total area
                                                  if ((double.tryParse(_sellingAreaController
                                                                  .text
                                                                  .replaceAll(
                                                                      ',', '')
                                                                  .replaceAll(
                                                                      ' ', '')) ??
                                                              0) >
                                                          (double.tryParse(_totalAreaController
                                                                  .text
                                                                  .replaceAll(
                                                                      ',', '')
                                                                  .replaceAll(
                                                                      ' ', '')) ??
                                                              0) &&
                                                      (double.tryParse(_totalAreaController
                                                                  .text
                                                                  .replaceAll(
                                                                      ',', '')
                                                                  .replaceAll(' ', '')) ??
                                                              0) >
                                                          0) ...[
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Text(
                                                          'Selling Area: ',
                                                          style:
                                                              GoogleFonts.inter(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: Colors.red,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${_formatAreaDisplay((double.tryParse(_totalAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ?? 0) - (double.tryParse(_sellingAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ?? 0))} $_areaUnitSuffix ',
                                                          style:
                                                              GoogleFonts.inter(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color: Colors.red,
                                                          ),
                                                        ),
                                                        Text(
                                                          '[Exceeding Total Project Area]',
                                                          style:
                                                              GoogleFonts.inter(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: Colors.red,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 24),
                                              // Non-Sellable Area(s) section
                                              Opacity(
                                                opacity: ((double.tryParse(_sellingAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                                0) >
                                                            (double.tryParse(_totalAreaController
                                                                    .text
                                                                    .replaceAll(
                                                                        ',', '')
                                                                    .replaceAll(
                                                                        ' ', '')) ??
                                                                0) &&
                                                        (double.tryParse(_totalAreaController
                                                                    .text
                                                                    .replaceAll(
                                                                        ',', '')
                                                                    .replaceAll(
                                                                        ' ',
                                                                        '')) ??
                                                                0) >
                                                            0)
                                                    ? 0.5
                                                    : 1.0,
                                                child: IgnorePointer(
                                                  ignoring: ((double.tryParse(
                                                                  _sellingAreaController
                                                                      .text
                                                                      .replaceAll(
                                                                          ',', '')
                                                                      .replaceAll(
                                                                          ' ',
                                                                          '')) ??
                                                              0) >
                                                          (double.tryParse(_totalAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                              0) &&
                                                      (double.tryParse(_totalAreaController
                                                                  .text
                                                                  .replaceAll(
                                                                      ',', '')
                                                                  .replaceAll(
                                                                      ' ', '')) ??
                                                              0) >
                                                          0),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Non-Sellable Area(s)',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Colors.black,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      RichText(
                                                        text: TextSpan(
                                                          children: [
                                                            TextSpan(
                                                              text:
                                                                  'Total Non-Sellable Area: ',
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: const Color(
                                                                    0xFF5C5C5C),
                                                              ),
                                                            ),
                                                            TextSpan(
                                                              text:
                                                                  '${_formatAreaDisplay(_totalNonSellableArea)} $_areaUnitSuffix',
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w400,
                                                                color: const Color(
                                                                    0xFF5C5C5C),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      // Non-sellable area entries
                                                      ..._nonSellableAreas
                                                          .asMap()
                                                          .entries
                                                          .map((entry) {
                                                        final index = entry.key;
                                                        final area =
                                                            entry.value;
                                                        return Padding(
                                                          padding: EdgeInsets.only(
                                                              top: 8,
                                                              bottom: index ==
                                                                      _nonSellableAreas
                                                                              .length -
                                                                          1
                                                                  ? 0
                                                                  : 0),
                                                          child: Row(
                                                            children: [
                                                              // Area field
                                                              Container(
                                                                width: 208,
                                                                height: 40,
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        8),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: Colors
                                                                      .white,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                  boxShadow: [
                                                                    BoxShadow(
                                                                      color:
                                                                          (() {
                                                                        final raw = (_nonSellableAreas[index]['area'] ??
                                                                                '')
                                                                            .toString()
                                                                            .replaceAll(',',
                                                                                '')
                                                                            .replaceAll(' ',
                                                                                '')
                                                                            .trim();
                                                                        return (raw.isEmpty ||
                                                                                raw == '0' ||
                                                                                raw == '0.0' ||
                                                                                raw == '0.00')
                                                                            ? Colors.red
                                                                            : Colors.black.withOpacity(0.15);
                                                                      })(),
                                                                      blurRadius:
                                                                          2,
                                                                      offset:
                                                                          const Offset(
                                                                              0,
                                                                              0),
                                                                      spreadRadius:
                                                                          0,
                                                                    ),
                                                                  ],
                                                                ),
                                                                child: Center(
                                                                  child: Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .spaceBetween,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      Expanded(
                                                                        child:
                                                                            Builder(
                                                                          builder:
                                                                              (context) {
                                                                            // Ensure controller exists
                                                                            if (_nonSellableAreaControllers[index] ==
                                                                                null) {
                                                                              _nonSellableAreaControllers[index] = TextEditingController();
                                                                            }
                                                                            return DecimalInputField(
                                                                              hintText: '0',
                                                                              controller: _nonSellableAreaControllers[index]!,
                                                                              decimalPlaces: 3,
                                                                              inputFormatters: [
                                                                                IndianNumberFormatter(maxIntegerDigits: 9)
                                                                              ],
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
                                                                                final formatted = _formatAmount(cleaned, decimalPlaces: 3);
                                                                                FocusScope.of(context).unfocus();
                                                                                _nonSellableAreaControllers[index]!.value = TextEditingValue(
                                                                                  text: formatted,
                                                                                  selection: TextSelection.collapsed(offset: formatted.length),
                                                                                );
                                                                                setState(() {
                                                                                  _nonSellableAreas[index]['area'] = formatted.replaceAll(',', '');
                                                                                });
                                                                                _onDataChanged();
                                                                              },
                                                                              contentPadding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
                                                                            );
                                                                          },
                                                                        ),
                                                                      ),
                                                                      Padding(
                                                                        padding: const EdgeInsets
                                                                            .only(
                                                                            left:
                                                                                8),
                                                                        child:
                                                                            Text(
                                                                          _areaUnitSuffix,
                                                                          style:
                                                                              GoogleFonts.inter(
                                                                            fontSize:
                                                                                14,
                                                                            fontWeight:
                                                                                FontWeight.normal,
                                                                            color:
                                                                                const Color(0xFF5C5C5C),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8),
                                                              // Name field
                                                              Container(
                                                                width: 250,
                                                                height: 40,
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        8),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: Colors
                                                                      .white,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                  boxShadow: [
                                                                    BoxShadow(
                                                                      color: (_nonSellableAreas[index]['name']?.isEmpty ??
                                                                              true)
                                                                          ? Colors
                                                                              .red
                                                                          : Colors
                                                                              .black
                                                                              .withOpacity(0.15),
                                                                      blurRadius:
                                                                          2,
                                                                      offset:
                                                                          const Offset(
                                                                              0,
                                                                              0),
                                                                      spreadRadius:
                                                                          0,
                                                                    ),
                                                                  ],
                                                                ),
                                                                child: Align(
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  child:
                                                                      TextField(
                                                                    textAlignVertical:
                                                                        TextAlignVertical
                                                                            .top,
                                                                    controller:
                                                                        _nonSellableNameControllers[
                                                                            index],
                                                                    onChanged:
                                                                        (value) {
                                                                      setState(
                                                                          () {
                                                                        _nonSellableAreas[index]['name'] =
                                                                            value;
                                                                      });
                                                                      _onDataChanged();
                                                                    },
                                                                    decoration:
                                                                        InputDecoration(
                                                                      hintText:
                                                                          'Roads & Utilities',
                                                                      hintStyle:
                                                                          GoogleFonts
                                                                              .inter(
                                                                        fontSize:
                                                                            14,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        color: const Color
                                                                            .fromARGB(
                                                                            191,
                                                                            173,
                                                                            173,
                                                                            173),
                                                                      ),
                                                                      border: InputBorder
                                                                          .none,
                                                                      contentPadding: const EdgeInsets
                                                                          .symmetric(
                                                                          vertical:
                                                                              0),
                                                                      isDense:
                                                                          true,
                                                                      alignLabelWithHint:
                                                                          false,
                                                                    ),
                                                                    style: GoogleFonts
                                                                        .inter(
                                                                      fontSize:
                                                                          14,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w500,
                                                                      color: Colors
                                                                          .black,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8),
                                                              // Remove button
                                                              GestureDetector(
                                                                onTap: () {
                                                                  setState(() {
                                                                    _nonSellableNameControllers[
                                                                            index]
                                                                        ?.dispose();
                                                                    _nonSellableAreaControllers[
                                                                            index]
                                                                        ?.dispose();
                                                                    _nonSellableAreas
                                                                        .removeAt(
                                                                            index);
                                                                    final oldNameControllers = Map<
                                                                            int,
                                                                            TextEditingController>.from(
                                                                        _nonSellableNameControllers);
                                                                    final oldAreaControllers = Map<
                                                                            int,
                                                                            TextEditingController>.from(
                                                                        _nonSellableAreaControllers);
                                                                    _nonSellableNameControllers
                                                                        .clear();
                                                                    _nonSellableAreaControllers
                                                                        .clear();
                                                                    for (int i =
                                                                            0;
                                                                        i < _nonSellableAreas.length;
                                                                        i++) {
                                                                      if (i <
                                                                          index) {
                                                                        _nonSellableNameControllers[i] =
                                                                            oldNameControllers[i]!;
                                                                        _nonSellableAreaControllers[i] =
                                                                            oldAreaControllers[i]!;
                                                                      } else {
                                                                        _nonSellableNameControllers[i] =
                                                                            oldNameControllers[i +
                                                                                1]!;
                                                                        _nonSellableAreaControllers[i] =
                                                                            oldAreaControllers[i +
                                                                                1]!;
                                                                      }
                                                                    }
                                                                  });
                                                                  if (_nonSellableAreas
                                                                      .isEmpty) {
                                                                    _setHideDefaultNonSellableTemplate(
                                                                        true);
                                                                  }
                                                                  _onDataChanged();
                                                                },
                                                                child:
                                                                    Container(
                                                                  height: 36,
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          16,
                                                                      vertical:
                                                                          4),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: Colors
                                                                        .white,
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(8),
                                                                    boxShadow: [
                                                                      BoxShadow(
                                                                        color: Colors
                                                                            .black
                                                                            .withOpacity(0.25),
                                                                        blurRadius:
                                                                            2,
                                                                        offset: const Offset(
                                                                            0,
                                                                            0),
                                                                        spreadRadius:
                                                                            0,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  child: Center(
                                                                    child: Text(
                                                                      'Remove',
                                                                      style: GoogleFonts
                                                                          .inter(
                                                                        fontSize:
                                                                            14,
                                                                        fontWeight:
                                                                            FontWeight.normal,
                                                                        color: Colors
                                                                            .red,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      }),
                                                      const SizedBox(height: 8),
                                                      // Total Remaining Area
                                                      Row(
                                                        children: [
                                                          Text(
                                                            'Total Remaining Area: ',
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: ((double.tryParse(_sellingAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                                              0) >
                                                                          (double.tryParse(_totalAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                                              0) &&
                                                                      (double.tryParse(_totalAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                                              0) >
                                                                          0)
                                                                  ? Colors
                                                                      .red // Red when showing NA
                                                                  : (_remainingArea !=
                                                                          0
                                                                      ? Colors
                                                                          .red // Red when remaining area is not 0
                                                                      : const Color(
                                                                          0xFF06AB00)), // Green when remaining area is exactly 0
                                                            ),
                                                          ),
                                                          Text(
                                                            ((double.tryParse(_sellingAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                                            0) >
                                                                        (double.tryParse(_totalAreaController.text.replaceAll(',', '').replaceAll(' ',
                                                                                '')) ??
                                                                            0) &&
                                                                    (double.tryParse(_totalAreaController.text.replaceAll(',', '').replaceAll(' ',
                                                                                '')) ??
                                                                            0) >
                                                                        0)
                                                                ? 'NA'
                                                                : (_remainingArea <
                                                                        0
                                                                    ? '${_formatAreaDisplay(_remainingArea)} $_areaUnitSuffix [Exceeding Approved Selling Area ($_areaUnitSuffix)]'
                                                                    : '${_formatAreaDisplay(_remainingArea)} $_areaUnitSuffix'),
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .normal,
                                                              color: ((double.tryParse(_sellingAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                                              0) >
                                                                          (double.tryParse(_totalAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                                              0) &&
                                                                      (double.tryParse(_totalAreaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
                                                                              0) >
                                                                          0)
                                                                  ? Colors
                                                                      .red // Red when showing NA
                                                                  : (_remainingArea !=
                                                                          0
                                                                      ? Colors
                                                                          .red // Red when remaining area is not 0
                                                                      : const Color(
                                                                          0xFF06AB00)), // Green when remaining area is exactly 0
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 8),
                                                      // Add Non-Sellable Area button
                                                      GestureDetector(
                                                        onTap: () {
                                                          setState(() {
                                                            final newIndex =
                                                                _nonSellableAreas
                                                                    .length;
                                                            _nonSellableAreas
                                                                .add({
                                                              'name': '',
                                                              'area': '0',
                                                            });
                                                            _nonSellableNameControllers[
                                                                    newIndex] =
                                                                TextEditingController();
                                                            _nonSellableAreaControllers[
                                                                    newIndex] =
                                                                TextEditingController();
                                                          });
                                                          _onDataChanged();
                                                        },
                                                        child: Container(
                                                          height: 36,
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      8),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                0xFF0C8CE9),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .black
                                                                    .withOpacity(
                                                                        0.25),
                                                                blurRadius: 2,
                                                                offset:
                                                                    const Offset(
                                                                        0, 0),
                                                                spreadRadius: 0,
                                                              ),
                                                            ],
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                'Add Non-Sellable Area',
                                                                style:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .normal,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8),
                                                              SvgPicture.asset(
                                                                'assets/images/Cretae_new_projet_white.svg',
                                                                width: 12,
                                                                height: 12,
                                                                fit: BoxFit
                                                                    .contain,
                                                                placeholderBuilder:
                                                                    (context) =>
                                                                        const SizedBox(
                                                                  width: 12,
                                                                  height: 12,
                                                                ),
                                                                errorBuilder:
                                                                    (context,
                                                                        error,
                                                                        stackTrace) {
                                                                  return const SizedBox(
                                                                    width: 12,
                                                                    height: 12,
                                                                    child: Icon(
                                                                        Icons
                                                                            .add,
                                                                        size:
                                                                            12,
                                                                        color: Colors
                                                                            .white),
                                                                  );
                                                                },
                                                              ),
                                                            ],
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
                                      ],
                                    ),
                                  ),
                                ],
                              ))
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
                                        : _activeTab ==
                                                ProjectTab.projectManagers
                                            ? _buildProjectManagersContent()
                                            : _activeTab == ProjectTab.agents
                                                ? _buildAgentsContent()
                                                : const SizedBox.shrink()))),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAreaLoadingSkeleton() {
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 600,
        child: Container(
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
              _buildSkeletonBlock(width: 180, height: 24),
              const SizedBox(height: 10),
              _buildSkeletonBlock(width: 470, height: 14),
              const SizedBox(height: 24),
              _buildSkeletonBlock(width: 140, height: 14),
              const SizedBox(height: 8),
              _buildSkeletonBlock(width: 184, height: 40),
              const SizedBox(height: 16),
              _buildSkeletonBlock(width: 160, height: 14),
              const SizedBox(height: 8),
              _buildSkeletonBlock(width: 184, height: 40),
              const SizedBox(height: 16),
              _buildSkeletonBlock(width: 140, height: 14),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildSkeletonBlock(width: 170, height: 40),
                  const SizedBox(width: 8),
                  _buildSkeletonBlock(width: 210, height: 40),
                  const SizedBox(width: 8),
                  _buildSkeletonBlock(width: 68, height: 40),
                ],
              ),
              const SizedBox(height: 16),
              _buildSkeletonBlock(width: 200, height: 14),
              const SizedBox(height: 8),
              _buildSkeletonBlock(width: 160, height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonBlock({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE3E7EB),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildAboutContent() {
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 564,
        child: Container(
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
                'Project Identity',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Defines the project's name, address, and location.",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: Colors.black.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 16),
              _buildAboutFieldLabel('Project Name', isRequired: true),
              const SizedBox(height: 8),
              _buildAboutInputField(
                controller: _projectNameController,
                focusNode: _projectNameFocusNode,
                hintText: 'The Imperial Gardens Park, Residency, Sport Complex',
                onChanged: (_) => _onDataChanged(),
                showCornerIcon: true,
                maxLength: 75,
                multiline: true,
              ),
              const SizedBox(height: 16),
              _buildAboutFieldLabel('Project Address'),
              const SizedBox(height: 8),
              _buildAboutInputField(
                controller: _projectAddressController,
                focusNode: _projectAddressFocusNode,
                hintText: 'Enter address of the project',
                onChanged: (_) => _onDataChanged(),
                showCornerIcon: true,
                maxLength: 150,
                multiline: true,
              ),
              const SizedBox(height: 16),
              _buildAboutFieldLabel('Location (Google Maps Link)'),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final locationValue = _googleMapsLinkController.text;
                  final link = locationValue.trim();
                  final uri = Uri.tryParse(link);
                  final validMapPattern = RegExp(
                      r'^(https?://)?(www\.)?(google\.com/maps|goo\.gl/maps|maps\.app\.goo\.gl|share\.google/)[\w\-]+',
                      caseSensitive: false);
                  final isGoogleSearchLocation = uri != null &&
                      uri.host.contains('google.com') &&
                      uri.path.contains('search') &&
                      (uri.queryParameters.containsKey('kgmid') ||
                          uri.queryParameters.containsKey('kgs'));
                  final isMapsAppGooGl =
                      uri != null && uri.host.contains('maps.app.goo.gl');
                  final isShareGoogle =
                      uri != null && uri.host.contains('share.google');
                  final simpleValid = link.isNotEmpty &&
                      (isGoogleSearchLocation ||
                          isMapsAppGooGl ||
                          isShareGoogle ||
                          validMapPattern.hasMatch(link));
                  // Show a red box-shadow around the container when link is empty/invalid;
                  // otherwise show the normal subtle shadow.
                  // Outer wrapper should only show the normal subtle shadow when valid.
                  // The red shadow for invalid state is applied to the inner input/icon individually.
                  final boxShadows = simpleValid
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 2,
                            offset: const Offset(0, 0),
                            spreadRadius: 0,
                          ),
                        ]
                      : null;

                  return Container(
                    // move input slightly to the left by reducing left padding
                    padding: const EdgeInsets.only(left: 4, right: 8),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: null,
                      boxShadow: null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildAboutInputField(
                            controller: _googleMapsLinkController,
                            focusNode: _googleMapsLinkFocusNode,
                            hintText: 'https://www.google.com/maps',
                            onChanged: (_) => _onDataChanged(),
                            showInvalidBoxShadow: !simpleValid,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            // reuse previous icon logic
                            bool isValidLocation = false;
                            if (link.isNotEmpty &&
                                uri != null &&
                                (uri.scheme == 'http' ||
                                    uri.scheme == 'https') &&
                                uri.host.isNotEmpty) {
                              if (isGoogleSearchLocation ||
                                  isMapsAppGooGl ||
                                  isShareGoogle) {
                                isValidLocation = true;
                              } else if (!validMapPattern.hasMatch(link)) {
                                isValidLocation = false;
                              } else {
                                // fallback to network check
                                return FutureBuilder<http.Response>(
                                  future: http.get(Uri.parse(link)),
                                  builder: (context, snapshot) {
                                    bool isValid = false;
                                    if (snapshot.connectionState ==
                                            ConnectionState.done &&
                                        snapshot.hasData) {
                                      final response = snapshot.data!;
                                      final body = response.body;
                                      final finalUrl =
                                          response.request?.url.toString() ??
                                              link;
                                      if (response.statusCode == 200) {
                                        if (finalUrl.contains('google.com')) {
                                          isValid = true;
                                        } else {
                                          isValid = body
                                                  .contains('google.com') ||
                                              body.contains('google-maps') ||
                                              body.contains('place_id') ||
                                              body.contains('share');
                                        }
                                      }
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 0),
                                      child: GestureDetector(
                                        onTap: isValid
                                            ? () =>
                                                html.window.open(link, '_blank')
                                            : null,
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: null,
                                            boxShadow: simpleValid
                                                ? [
                                                    BoxShadow(
                                                      color:
                                                          _googleMapsLinkFocusNode
                                                                  .hasFocus
                                                              ? const Color(
                                                                  0xFF0C8CE9)
                                                              : Colors.black
                                                                  .withOpacity(
                                                                      0.25),
                                                      blurRadius: 2,
                                                      offset:
                                                          const Offset(0, 0),
                                                      spreadRadius: 0,
                                                    ),
                                                  ]
                                                : [
                                                    BoxShadow(
                                                      color:
                                                          _googleMapsLinkFocusNode
                                                                  .hasFocus
                                                              ? const Color(
                                                                  0xFF0C8CE9)
                                                              : Colors.red,
                                                      blurRadius: 2,
                                                      offset:
                                                          const Offset(0, 0),
                                                      spreadRadius: 0,
                                                    ),
                                                  ],
                                          ),
                                          child: Center(
                                            child: SvgPicture.asset(
                                              isValid
                                                  ? '/Users/prajna/Documents/Location_active.svg'
                                                  : '/Users/prajna/Documents/location_inactive.svg',
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.contain,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  const SizedBox(
                                                      width: 40, height: 40),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }
                            }
                            return Padding(
                              padding: const EdgeInsets.only(left: 0),
                              child: GestureDetector(
                                onTap: isValidLocation
                                    ? () => html.window.open(link, '_blank')
                                    : null,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: null,
                                    boxShadow: simpleValid
                                        ? [
                                            BoxShadow(
                                              color: _googleMapsLinkFocusNode
                                                      .hasFocus
                                                  ? const Color(0xFF0C8CE9)
                                                  : Colors.black
                                                      .withOpacity(0.25),
                                              blurRadius: 2,
                                              offset: const Offset(0, 0),
                                              spreadRadius: 0,
                                            ),
                                          ]
                                        : [
                                            BoxShadow(
                                              color: _googleMapsLinkFocusNode
                                                      .hasFocus
                                                  ? const Color(0xFF0C8CE9)
                                                  : Colors.red,
                                              blurRadius: 2,
                                              offset: const Offset(0, 0),
                                              spreadRadius: 0,
                                            ),
                                          ],
                                  ),
                                  child: Center(
                                    child: SvgPicture.asset(
                                      isValidLocation
                                          ? '/Users/prajna/Documents/Location_active.svg'
                                          : '/Users/prajna/Documents/location_inactive.svg',
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error,
                                              stackTrace) =>
                                          const SizedBox(width: 40, height: 40),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutFieldLabel(String label, {bool isRequired = false}) {
    return RichText(
      text: TextSpan(
        text: label,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
        children: [
          if (isRequired)
            TextSpan(
              text: ' *',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.red,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAboutInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required ValueChanged<String> onChanged,
    bool showCornerIcon = false,
    int? maxLength,
    bool multiline = false,
    bool showInvalidBoxShadow = false,
  }) {
    // Special case: Project Name field should be single-line and vertically centered
    final isProjectName =
        hintText == 'The Imperial Gardens Park, Residency, Sport Complex';
    final isLocation = hintText == 'https://www.google.com/maps';
    final isAddress = hintText == 'Enter address of the project';
    bool isLocationField = isLocation;
    String locationValue = controller.text;
    bool isValidLocation = isLocationField &&
        (locationValue.startsWith('https://www.google.com/maps') ||
            locationValue.startsWith('http://www.google.com/maps'));

    final isProjectNameEmpty = isProjectName && controller.text.trim().isEmpty;
    final showInvalidShadow = showInvalidBoxShadow || isProjectNameEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: null,
        boxShadow: [
          BoxShadow(
            color: focusNode.hasFocus
                ? const Color(0xFF0C8CE9)
                : (showInvalidShadow
                    ? const Color(0xFFFF0000)
                    : Colors.black.withOpacity(0.25)),
            blurRadius: 2,
            offset: const Offset(0, 0),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment:
            isProjectName ? CrossAxisAlignment.center : CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLength: maxLength,
              minLines: (isProjectName || multiline) ? 1 : 1,
              maxLines: (isProjectName || multiline) ? 8 : 1,
              keyboardType: (isProjectName || multiline)
                  ? TextInputType.multiline
                  : (isLocation ? TextInputType.text : TextInputType.text),
              textAlignVertical: isAddress
                  ? TextAlignVertical.center
                  : (isProjectName
                      ? TextAlignVertical.center
                      : (multiline
                          ? TextAlignVertical.top
                          : (isLocation
                              ? TextAlignVertical.center
                              : TextAlignVertical.center))),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black.withOpacity(0.75),
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFC1C1C1),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: isAddress
                    ? const EdgeInsets.symmetric(vertical: 13)
                    : ((isProjectName || multiline)
                        ? const EdgeInsets.symmetric(vertical: 13)
                        : (isLocation
                            ? const EdgeInsets.only(top: 3, bottom: 13)
                            : const EdgeInsets.symmetric(vertical: 12))),
                counterText: '',
              ),
              onChanged: (value) {
                if (onChanged != null) onChanged(value);
                // Force rebuild to update icon color/state and project name shadow
                if (mounted) setState(() {});
              },
            ),
          ),
          if (isLocationField)
            // Removed icon inside input field
            if (!isLocationField && showCornerIcon)
              Padding(
                padding: const EdgeInsets.only(left: 0),
                child: SizedBox(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Transform.translate(
                      offset: const Offset(0, -2),
                      child: SvgPicture.asset(
                        'assets/images/Enter.svg',
                        width: 16,
                        height: 16,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const SizedBox(
                            width: 12,
                            height: 12,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildAboutActionButton() {
    return Container(
      width: 40,
      height: 40,
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
      child: const Icon(
        Icons.near_me,
        size: 20,
        color: Color(0xFF0C8CE9),
      ),
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
                    'Estimated Project Cost (₹) ',
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: _estimatedDevelopmentCostFocusNode.hasFocus
                          ? const Color(0xFF0C8CE9)
                          : (_estimatedDevelopmentCost == 0
                              ? Colors.red
                              : Colors.black.withOpacity(0.15)),
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
                        focusNode: _estimatedDevelopmentCostFocusNode,
                        hintText: '0',
                        inputFormatters: [
                          IndianNumberFormatter(maxIntegerDigits: 11)
                        ],
                        onTap: () {
                          // Clear '0.00' when field is tapped
                          final cleaned = _estimatedDevelopmentCostController
                              .text
                              .replaceAll(',', '')
                              .replaceAll('₹', '')
                              .replaceAll(' ', '')
                              .trim();
                          if (cleaned == '0' || cleaned == '0.00') {
                            _estimatedDevelopmentCostController.text = '';
                            _estimatedDevelopmentCostController.selection =
                                TextSelection.collapsed(offset: 0);
                            setState(() {});
                          }
                        },
                        onChanged: (_) {
                          setState(() {});
                          _onDataChanged();
                        },
                        onEditingComplete: () {
                          // Remove commas before formatting
                          final cleaned = _estimatedDevelopmentCostController
                              .text
                              .replaceAll(',', '')
                              .replaceAll('₹', '')
                              .replaceAll(' ', '');
                          final formatted = _formatAmount(cleaned);
                          FocusScope.of(context).unfocus();
                          _estimatedDevelopmentCostController.value =
                              TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                                offset: formatted.length),
                          );
                          setState(() {});
                          _onDataChanged();
                        },
                        contentPadding:
                            const EdgeInsets.only(top: 8, bottom: 8),
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
              // Partners table with vertical scrolling
              Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: _buildPartnersTable(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Summary - Total Capital Contributed
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Total Capital Contributed: ',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    TextSpan(
                      text: '₹ ${_formatAmountForDisplay(_totalPartnerAmount)}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.black,
                      ),
                    ),
                  ],
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
                    _partnerAmountControllers[newIndex] =
                        TextEditingController();
                  });
                  _onDataChanged();
                  // Ensure error state is updated after state change
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _notifyErrorState();
                  });
                },
                child: Container(
                  height: 36,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                      // Check if partners have any data entered
                      final hasPartnerData = _partners.any((p) =>
                          (p['name']?.toString().trim().isNotEmpty ?? false) ||
                          ((double.tryParse((p['amount'] ?? '0')
                                      .toString()
                                      .replaceAll(',', '')) ??
                                  0) >
                              0));

                      final noDevelopmentCost =
                          _estimatedDevelopmentCost == 0 && hasPartnerData;
                      final exceedsAmount =
                          _totalPartnerAmount > _estimatedDevelopmentCost &&
                              _estimatedDevelopmentCost > 0;
                      final remaining = _remainingPartnerAmount;
                      String formattedAmount =
                          _formatAmountForDisplay(remaining.abs());

                      final isRed = (noDevelopmentCost ||
                          remaining != 0 ||
                          exceedsAmount);
                      final valueColor =
                          isRed ? Colors.red : const Color(0xFF06AB00);

                      final valueText = noDevelopmentCost
                          ? '₹ NA [Enter Estimated Project Cost (₹)]'
                          : (exceedsAmount
                              ? '- ₹ $formattedAmount [ Exceeding Estimated Project Cost (₹) ]'
                              : '₹ $formattedAmount');

                      return RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Remaining Budget to Allocate: ',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: valueColor,
                              ),
                            ),
                            TextSpan(
                              text: valueText,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: valueColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      // Check if partners have any data entered
                      final hasPartnerData = _partners.any((p) =>
                          (p['name']?.toString().trim().isNotEmpty ?? false) ||
                          ((double.tryParse((p['amount'] ?? '0')
                                      .toString()
                                      .replaceAll(',', '')) ??
                                  0) >
                              0));
                      final noDevelopmentCost =
                          _estimatedDevelopmentCost == 0 && hasPartnerData;
                      final exceedsAmount =
                          _totalPartnerAmount > _estimatedDevelopmentCost &&
                              _estimatedDevelopmentCost > 0;

                      final isRed = (noDevelopmentCost ||
                          exceedsAmount ||
                          _totalSharePercentage != 100);
                      final valueColor =
                          isRed ? Colors.red : const Color(0xFF06AB00);

                      final valueText = (noDevelopmentCost || exceedsAmount)
                          ? 'NA'
                          : '${_totalSharePercentage % 1 == 0 ? _totalSharePercentage.toStringAsFixed(0) : _totalSharePercentage.toStringAsFixed(2)}%';

                      return RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Total Share Allocated: ',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: valueColor,
                              ),
                            ),
                            TextSpan(
                              text: valueText,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: valueColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
                          fontSize: 14,
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
                          left:
                              const BorderSide(color: Colors.black, width: 1.0),
                          right:
                              const BorderSide(color: Colors.black, width: 1.0),
                          bottom:
                              const BorderSide(color: Colors.black, width: 1.0),
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
                            fontSize: 14,
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
                          right:
                              const BorderSide(color: Colors.black, width: 1.0),
                          bottom:
                              const BorderSide(color: Colors.black, width: 1.0),
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
                                color: _partnerNameFocusNodes
                                        .putIfAbsent(index, () => FocusNode())
                                        .hasFocus
                                    ? const Color(0xFF0C8CE9)
                                    : ((_partners[index]['name'] ?? '')
                                            .toString()
                                            .trim()
                                            .isEmpty
                                        ? Colors.red
                                        : Colors.black.withOpacity(0.15)),
                                blurRadius: 2,
                                offset: const Offset(0, 0),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _partnerNameControllers[index],
                                  focusNode: _partnerNameFocusNodes.putIfAbsent(
                                      index, () => FocusNode()),
                                  textAlignVertical: TextAlignVertical.center,
                                  textAlign: TextAlign.left,
                                  maxLines: 1,
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
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    isDense: true,
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
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
                            'Capital Contribution (₹) ',
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
                          right:
                              const BorderSide(color: Colors.black, width: 1.0),
                          bottom:
                              const BorderSide(color: Colors.black, width: 1.0),
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
                                color: _partnerAmountFocusNodes
                                        .putIfAbsent(index, () => FocusNode())
                                        .hasFocus
                                    ? const Color(0xFF0C8CE9)
                                    : () {
                                        final amount = double.tryParse(
                                                (_partners[index]['amount'] ??
                                                        '0')
                                                    .toString()
                                                    .replaceAll(',', '')) ??
                                            0;
                                        final hasPartnerData = (_partners[index]
                                                        ['name']
                                                    ?.toString()
                                                    .trim()
                                                    .isNotEmpty ??
                                                false) ||
                                            amount > 0;
                                        final noDevelopmentCost =
                                            _estimatedDevelopmentCost == 0 &&
                                                hasPartnerData;
                                        return (amount == 0 ||
                                                noDevelopmentCost)
                                            ? Colors.red
                                            : Colors.black.withOpacity(0.15);
                                      }(),
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
                                    if (_partnerAmountControllers[index] ==
                                        null) {
                                      _partnerAmountControllers[index] =
                                          TextEditingController();
                                    }
                                    return DecimalInputField(
                                      controller:
                                          _partnerAmountControllers[index]!,
                                      focusNode:
                                          _partnerAmountFocusNodes.putIfAbsent(
                                              index, () => FocusNode()),
                                      hintText: '0',
                                      inputFormatters: [
                                        IndianNumberFormatter(
                                            maxIntegerDigits: 11)
                                      ],
                                      onTap: () {
                                        // Clear '0.00' when field is tapped
                                        final cleaned =
                                            _partnerAmountControllers[index]!
                                                .text
                                                .replaceAll(',', '')
                                                .replaceAll('₹', '')
                                                .replaceAll(' ', '')
                                                .trim();
                                        if (cleaned == '0' ||
                                            cleaned == '0.00') {
                                          _partnerAmountControllers[index]!
                                              .text = '';
                                          _partnerAmountControllers[index]!
                                                  .selection =
                                              TextSelection.collapsed(
                                                  offset: 0);
                                          setState(() {});
                                        }
                                      },
                                      onChanged: (value) {
                                        // Remove commas for storage (for real-time calculations)
                                        final rawValue = value
                                            .replaceAll(',', '')
                                            .replaceAll('₹', '')
                                            .replaceAll(' ', '');
                                        setState(() {
                                          _partners[index]['amount'] =
                                              rawValue.isEmpty
                                                  ? '0.00'
                                                  : rawValue;
                                        });
                                        _onDataChanged();
                                      },
                                      onEditingComplete: () {
                                        // Remove commas before formatting
                                        final cleaned =
                                            _partnerAmountControllers[index]!
                                                .text
                                                .replaceAll(',', '')
                                                .replaceAll('₹', '')
                                                .replaceAll(' ', '');
                                        final formatted =
                                            _formatAmount(cleaned);
                                        FocusScope.of(context).unfocus();
                                        _partnerAmountControllers[index]!
                                            .value = TextEditingValue(
                                          text: formatted,
                                          selection: TextSelection.collapsed(
                                              offset: formatted.length),
                                        );
                                        setState(() {
                                          _partners[index]['amount'] =
                                              formatted.replaceAll(',', '');
                                        });
                                        _onDataChanged();
                                      },
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 8),
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
                          fontSize: 14,
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
                    // Check if ANY partner has data entered (not just current row)
                    final anyPartnerHasData = _partners.any((p) =>
                        (p['name']?.toString().trim().isNotEmpty ?? false) ||
                        ((double.tryParse((p['amount'] ?? '0')
                                    .toString()
                                    .replaceAll(',', '')) ??
                                0) >
                            0));
                    final noDevelopmentCost =
                        _estimatedDevelopmentCost == 0 && anyPartnerHasData;
                    final exceedsAmount =
                        _totalPartnerAmount > _estimatedDevelopmentCost &&
                            _estimatedDevelopmentCost > 0;
                    final shareValue = _getPartnerShare(index);
                    final shareDisplay = shareValue % 1 == 0
                        ? shareValue.toStringAsFixed(0)
                        : shareValue.toStringAsFixed(2);
                    final displayText = (noDevelopmentCost || exceedsAmount)
                        ? 'NA'
                        : '$shareDisplay %';
                    return Container(
                      width: 120,
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          right:
                              const BorderSide(color: Colors.black, width: 1.0),
                          bottom:
                              const BorderSide(color: Colors.black, width: 1.0),
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
                            color: (shareValue == 0 &&
                                    !exceedsAmount &&
                                    !noDevelopmentCost)
                                ? Color.fromARGB(191, 173, 173,
                                    173) // Grey placeholder when 0%
                                : ((exceedsAmount || noDevelopmentCost)
                                    ? const Color(0xFFFF0000)
                                    : const Color(
                                        0xFF5D5D5D)), // Dark grey when has value
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
                    final canRemove = _partners.length > 1;
                    return Container(
                      width: 120,
                      height: index == 0 ? 49 : 48,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          top: index == 0
                              ? const BorderSide(
                                  color: Colors.black, width: 1.0)
                              : BorderSide.none,
                          right:
                              const BorderSide(color: Colors.black, width: 1.0),
                          bottom:
                              const BorderSide(color: Colors.black, width: 1.0),
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
                            if (canRemove) {
                              setState(() {
                                _partnerNameControllers[index]?.dispose();
                                _partnerAmountControllers[index]?.dispose();
                                _partners.removeAt(index);
                                // Rebuild controllers maps
                                final oldNameControllers =
                                    Map<int, TextEditingController>.from(
                                        _partnerNameControllers);
                                final oldAmountControllers =
                                    Map<int, TextEditingController>.from(
                                        _partnerAmountControllers);
                                _partnerNameControllers.clear();
                                _partnerAmountControllers.clear();
                                for (int i = 0; i < _partners.length; i++) {
                                  if (i < index) {
                                    _partnerNameControllers[i] =
                                        oldNameControllers[i]!;
                                    _partnerAmountControllers[i] =
                                        oldAmountControllers[i]!;
                                  } else {
                                    _partnerNameControllers[i] =
                                        oldNameControllers[i + 1]!;
                                    _partnerAmountControllers[i] =
                                        oldAmountControllers[i + 1]!;
                                  }
                                }
                              });
                              _onDataChanged();
                            }
                          },
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
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
                                  color: canRemove
                                      ? Colors.red
                                      : Colors.red.withOpacity(0.5),
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
              const SizedBox(height: 8),
              // Total Expenses
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Total Expenses: ',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    TextSpan(
                      text: '₹ ${_formatAmountForDisplay(_totalExpenses)}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Add Expenses button
              GestureDetector(
                onTap: () {
                  setState(() {
                    final newIndex = _expenses.length;
                    _expenses
                        .add({'item': '', 'amount': '0.00', 'category': ''});
                    _expenseItemControllers[newIndex] = TextEditingController();
                    _expenseAmountControllers[newIndex] =
                        TextEditingController();
                  });
                  _onDataChanged();
                },
                child: Container(
                  height: 36,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Estimated Development Cost [Budget]: ',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            '₹ ${_formatAmountForDisplay(_estimatedDevelopmentCost)} ',
                            style: GoogleFonts.inter(
                              fontSize: 14,
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
                                fontSize: 14,
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
                          String formattedAmount =
                              _formatAmountForDisplay(remaining.abs());

                          String displayValue;
                          Color textColor;

                          if (remaining < 0) {
                            // Negative (over budget) - red
                            displayValue = '- ₹ $formattedAmount [Over Budget]';
                            textColor = Colors.red;
                          } else if (remaining == 0) {
                            // Zero - current color (black)
                            displayValue = '₹ $formattedAmount';
                            textColor = Colors.black;
                          } else {
                            // Positive - green
                            displayValue = '₹ $formattedAmount';
                            textColor = const Color(0xFF06AB00);
                          }

                          return RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Remaining Budget: ',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                                TextSpan(
                                  text: displayValue,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: textColor,
                                  ),
                                ),
                              ],
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
    final numberOfLayouts =
        int.tryParse(controllerText.isEmpty ? '0' : controllerText) ?? 0;

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
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Define layouts and add plots for this project.',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.black.withOpacity(0.8),
                height: 1.0,
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
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(
                                maxWidth: 552, minHeight: 226),
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
                                      'Create Number of Layouts ',
                                      style: GoogleFonts.inter(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                        height: 1.0,
                                      ),
                                    ),
                                    Text(
                                      '*',
                                      style: GoogleFonts.inter(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red,
                                        height: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Enter the total number of layouts to create sections for adding plots.',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.black.withOpacity(0.8),
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    _buildFocusAwareInputContainer(
                                      focusNode: _numberOfLayoutsFocusNode,
                                      backgroundColor: Colors.white,
                                      onFocusLost: () {
                                        _processNumberOfLayouts();
                                      },
                                      width: 96,
                                      child: TextField(
                                        controller: _numberOfLayoutsController,
                                        focusNode: _numberOfLayoutsFocusNode,
                                        keyboardType: TextInputType.number,
                                        textAlignVertical:
                                            TextAlignVertical.center,
                                        textAlign: TextAlign.left,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        onTap: () {
                                          // Clear '0' when field is tapped
                                          final cleaned =
                                              _numberOfLayoutsController.text
                                                  .trim();
                                          if (cleaned == '0') {
                                            _numberOfLayoutsController.text =
                                                '';
                                            _numberOfLayoutsController
                                                    .selection =
                                                TextSelection.collapsed(
                                                    offset: 0);
                                            setState(() {
                                              _isCreateTableEnabled = false;
                                            });
                                          }
                                        },
                                        onChanged: (value) {
                                          // Check if a valid number > 0 is entered
                                          final numValue =
                                              int.tryParse(value) ?? 0;

                                          setState(() {
                                            _isCreateTableEnabled =
                                                numValue > 0;
                                          });
                                          _onDataChanged();
                                        },
                                        onEditingComplete: () {
                                          _processNumberOfLayouts();
                                        },
                                        decoration: InputDecoration(
                                          hintText: '0',
                                          hintStyle: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Color.fromARGB(
                                                191, 173, 173, 173),
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.only(
                                              left: 0, top: 0, bottom: 18),
                                        ),
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Create Table / Add Layouts button
                                    GestureDetector(
                                      onTap: _isCreateTableEnabled
                                          ? () {
                                              _processNumberOfLayouts();
                                            }
                                          : null,
                                      child: Container(
                                        height: 40,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.25),
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
                                              _layouts.isEmpty
                                                  ? 'Create Table'
                                                  : 'Add Layouts',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.normal,
                                                color: _isCreateTableEnabled
                                                    ? const Color(0xFF0C8CE9)
                                                    : const Color(0xFF0C8CE9)
                                                        .withOpacity(0.4),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _isCreateTableEnabled
                                                ? SvgPicture.asset(
                                                    'assets/images/Active_create_table.svg',
                                                    width: 16,
                                                    height: 16,
                                                    fit: BoxFit.contain,
                                                    placeholderBuilder:
                                                        (context) =>
                                                            const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                    ),
                                                  )
                                                : SvgPicture.asset(
                                                    'assets/images/Inactive_create_table.svg',
                                                    width: 16,
                                                    height: 16,
                                                    fit: BoxFit.contain,
                                                    placeholderBuilder:
                                                        (context) =>
                                                            const SizedBox(
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
                        ],
                      ),
                      Positioned(
                        left: 16,
                        bottom: 16,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // "X layouts" text
                            Text(
                              '${_layouts.length} layout${_layouts.length != 1 ? 's' : ''}',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Black dot
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // "X plots" text
                            Text(
                              '${_layouts.fold<int>(0, (sum, layout) => sum + ((layout['plots'] as List?)?.length ?? 0))} plot${_layouts.fold<int>(0, (sum, layout) => sum + ((layout['plots'] as List?)?.length ?? 0)) != 1 ? 's' : ''}',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: Builder(
                          builder: (context) {
                            return GestureDetector(
                              onTap: () {
                                if (_openLayoutMenuIndex == -1) {
                                  // Close menu if already open
                                  _currentLayoutMenuEntry?.remove();
                                  _currentLayoutMenuBackdropEntry?.remove();
                                  _openLayoutMenuIndex = null;
                                  _currentLayoutMenuEntry = null;
                                  _currentLayoutMenuBackdropEntry = null;
                                } else {
                                  // Close previous menu if any
                                  _currentLayoutMenuEntry?.remove();
                                  _currentLayoutMenuBackdropEntry?.remove();
                                  // Show menu
                                  _showDeleteAllLayoutsMenu(
                                      context, _deleteAllLayoutsMenuAnchorKey);
                                }
                              },
                              child: Container(
                                key: _deleteAllLayoutsMenuAnchorKey,
                                height: 36,
                                width: 52,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.white,
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
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // First dot
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Second dot
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Third dot
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black,
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
                  ),
                ),
                const SizedBox(width: 36),
                // Overall summary card
                Flexible(
                  flex: 1,
                  child: Container(
                    width: double.infinity,
                    constraints:
                        const BoxConstraints(maxWidth: 552, minHeight: 226),
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
                          'Overview',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF5C5C5C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Area information
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 24,
                              alignment: Alignment.centerLeft,
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text:
                                          'Approved Selling Area ($_areaUnitSuffix): ',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          '${_formatAmountForDisplay(AreaUnitUtils.areaFromSqftToDisplay(_approvedSellingArea, _isSqm), decimalPlaces: 3)} $_areaUnitSuffix ',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.black,
                                      ),
                                    ),
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() =>
                                              _activeTab = ProjectTab.about);
                                        },
                                        child: Text(
                                          '[Edit]',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            color: const Color(0xFF0C8CE9),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 24,
                              alignment: Alignment.centerLeft,
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Total Allocated Area: ',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: _allocatedArea >
                                                _approvedSellingArea
                                            ? Colors.red
                                            : Colors.black,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _allocatedArea >
                                              _approvedSellingArea
                                          ? '${_formatAmountForDisplay(AreaUnitUtils.areaFromSqftToDisplay(_allocatedArea, _isSqm), decimalPlaces: 3)} $_areaUnitSuffix [Exceeding Approved Selling Area ($_areaUnitSuffix)]'
                                          : '${_formatAmountForDisplay(AreaUnitUtils.areaFromSqftToDisplay(_allocatedArea, _isSqm), decimalPlaces: 3)} $_areaUnitSuffix',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: _allocatedArea >
                                                _approvedSellingArea
                                            ? Colors.red
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 24,
                              alignment: Alignment.centerLeft,
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Total Remaining Area: ',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: _remainingSiteArea != 0
                                            ? Colors.red
                                            : const Color(0xFF06AB00),
                                      ),
                                    ),
                                    TextSpan(
                                      text: _remainingSiteArea < 0
                                          ? '${_formatAmountForDisplay(AreaUnitUtils.areaFromSqftToDisplay(_remainingSiteArea, _isSqm), decimalPlaces: 3)} $_areaUnitSuffix [Exceeding Approved Selling Area ($_areaUnitSuffix)]'
                                          : '${_formatAmountForDisplay(AreaUnitUtils.areaFromSqftToDisplay(_remainingSiteArea, _isSqm), decimalPlaces: 3)} $_areaUnitSuffix',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: _remainingSiteArea != 0
                                            ? Colors.red
                                            : const Color(0xFF06AB00),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Cost information
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 24,
                              alignment: Alignment.centerLeft,
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'All-in Cost: ',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          '₹ ${_formatAmountForDisplay(_approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0, decimalPlaces: 3)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 24,
                              alignment: Alignment.centerLeft,
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Total Plot Cost: ',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          '₹ ${_formatAmountForDisplay(_totalPlotCost, decimalPlaces: 3)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.black,
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
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                        color: Colors.black.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Layouts header with buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Layouts',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      Row(
                        children: [
                          // Expand all layouts button
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _collapsedLayouts.clear();
                              });
                            },
                            child: Container(
                              width: 188,
                              height: 36,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.white,
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
                                  Expanded(
                                    child: Text(
                                      'Expand all layouts',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 14,
                                    height: 7,
                                    child: Center(
                                      child: SvgPicture.asset(
                                        'assets/images/Expand.svg',
                                        width: 14,
                                        height: 7,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) =>
                                            const SizedBox(
                                          width: 14,
                                          height: 7,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // Collapse all layouts button
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _collapsedLayouts.clear();
                                // Add all layout indices to collapsed set
                                for (int i = 0; i < _layouts.length; i++) {
                                  _collapsedLayouts.add(i);
                                }
                              });
                            },
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.white,
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
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Collapse all layouts',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 14,
                                    height: 7,
                                    child: Center(
                                      child: SvgPicture.asset(
                                        'assets/images/Collapse.svg',
                                        width: 14,
                                        height: 7,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) =>
                                            const SizedBox(
                                          width: 14,
                                          height: 7,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Text(
                            'Zoom',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                // Decrease zoom by 10% (minimum 50%)
                                _tableZoomLevel =
                                    (_tableZoomLevel - 0.1).clamp(0.5, 1.2);
                              });
                            },
                            child: Container(
                              width: 36,
                              height: 36,
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
                              child: SvgPicture.asset(
                                'assets/images/Zoom_out.svg',
                                width: 36,
                                height: 36,
                                fit: BoxFit.contain,
                                placeholderBuilder: (context) => SizedBox(
                                  width: 36,
                                  height: 36,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(_tableZoomLevel * 100).toInt()}%',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                // Increase zoom by 10% (maximum 120%)
                                _tableZoomLevel =
                                    (_tableZoomLevel + 0.1).clamp(0.5, 1.2);
                              });
                            },
                            child: Container(
                              width: 36,
                              height: 36,
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
                              child: SvgPicture.asset(
                                'assets/images/Zoom_in.svg',
                                width: 36,
                                height: 36,
                                fit: BoxFit.contain,
                                placeholderBuilder: (context) => SizedBox(
                                  width: 36,
                                  height: 36,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Layouts list
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _layouts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final layout = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: _buildLayoutCard(index, layout),
                      );
                    }).toList(),
                  ),
                ],
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
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
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Row(
                    children: [
                      Text(
                        'Zoom',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            // Decrease zoom by 10% (minimum 50%)
                            _tableZoomLevel =
                                (_tableZoomLevel - 0.1).clamp(0.5, 1.2);
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
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
                          child: SvgPicture.asset(
                            'assets/images/Zoom_out.svg',
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            placeholderBuilder: (context) => SizedBox(
                              width: 36,
                              height: 36,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_tableZoomLevel * 100).toInt()}%',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            // Increase zoom by 10% (maximum 120%)
                            _tableZoomLevel =
                                (_tableZoomLevel + 0.1).clamp(0.5, 1.2);
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
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
                          child: SvgPicture.asset(
                            'assets/images/Zoom_in.svg',
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            placeholderBuilder: (context) => SizedBox(
                              width: 36,
                              height: 36,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildProjectManagersTable(),
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
        _projectManagers = [
          {'name': '', 'compensation': '', 'earningType': ''}
        ];
      }
    } catch (e) {
      // If _projectManagers is undefined, initialize it
      _projectManagers = [
        {'name': '', 'compensation': '', 'earningType': ''}
      ];
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

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
          right: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
          top: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
          bottom: 8 +
              (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)) +
              (50 *
                  (_tableZoomLevel - 1.0).clamp(0.0,
                      0.2)), // Extra bottom padding for scaled content to prevent border clipping
        ), // Add extra padding when zoomed to show borders
        clipBehavior: Clip.hardEdge,
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
            Builder(
              builder: (context) {
                // Calculate dynamic height based on number of project managers
                // Header row: 48px, each manager row: 48px
                double baseHeaderHeight = 48.0;
                double baseRowHeight = 48.0;
                double calculatedHeight =
                    baseHeaderHeight + (projectManagers.length * baseRowHeight);
                // Store base height (same as when zoom = 1.0)
                final baseHeight = calculatedHeight;
                // Calculate scaled height for outer container
                double scaledHeight = calculatedHeight * _tableZoomLevel;
                // Only apply minimum height if calculated height is very small (less than header + 1 row)
                final minHeight =
                    (baseHeaderHeight + baseRowHeight) * _tableZoomLevel;
                if (scaledHeight < minHeight) {
                  scaledHeight = minHeight;
                }
                // Add buffer for scaled border to prevent clipping
                final borderBuffer = _tableZoomLevel > 1.0 ? 5.0 : 0.0;
                scaledHeight = scaledHeight + borderBuffer;

                return SizedBox(
                  width: double.infinity,
                  height: scaledHeight,
                  child: Scrollbar(
                    controller: _projectManagersTableScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _projectManagersTableScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      clipBehavior: Clip.none,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left:
                              ((_tableZoomLevel - 1.0) * 10.0).clamp(0.0, 10.0),
                          right: ((_tableZoomLevel - 1.0) * 10.0)
                                  .clamp(0.0, 10.0) +
                              ((_tableZoomLevel - 1.0) * 1350.0).clamp(0.0,
                                  1350.0), // Extra right padding when zoomed to allow full scrolling to last column
                          top:
                              ((_tableZoomLevel - 1.0) * 10.0).clamp(0.0, 10.0),
                          bottom: ((_tableZoomLevel - 1.0) * 10.0)
                                  .clamp(0.0, 10.0) +
                              ((_tableZoomLevel - 1.0) * 100.0).clamp(0.0,
                                  100.0), // Extra bottom padding for scaled borders to prevent clipping
                        ),
                        child: Transform.scale(
                          scale: _tableZoomLevel,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            height:
                                baseHeight, // Use base height (same as when zoom = 1.0), Transform.scale will handle scaling
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
                                        color: const Color(0xFF707070)
                                            .withOpacity(0.2),
                                        border: Border.all(
                                            color: Colors.black, width: 1.0),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(8),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Sl. No.',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                    // Rows
                                    ...List.generate(projectManagers.length,
                                        (index) {
                                      // Get selected blocks to calculate same height as other columns
                                      List<String> selectedBlocks = [];
                                      try {
                                        if (_projectManagerSelectedBlocks !=
                                            null) {
                                          selectedBlocks =
                                              _projectManagerSelectedBlocks[
                                                      index] ??
                                                  [];
                                        }
                                      } catch (e) {
                                        selectedBlocks = [];
                                      }
                                      final isLast =
                                          index == projectManagers.length - 1;
                                      return Container(
                                        width: 60,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            left: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            top: BorderSide.none,
                                          ),
                                          borderRadius: isLast
                                              ? const BorderRadius.only(
                                                  bottomLeft:
                                                      Radius.circular(8),
                                                )
                                              : null,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF707070)
                                            .withOpacity(0.2),
                                        border: const Border(
                                          top: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          right: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          bottom: BorderSide(
                                              color: Colors.black, width: 1.0),
                                        ),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Project Manager(s) ',
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
                                      ),
                                    ),
                                    // Rows
                                    ...List.generate(projectManagers.length,
                                        (index) {
                                      // Safely get controller, ensuring map is initialized
                                      TextEditingController controller;
                                      final focusNode =
                                          _projectManagerNameFocusNodes
                                              .putIfAbsent(index, () {
                                        final node = FocusNode();
                                        node.addListener(() {
                                          if (mounted) setState(() {});
                                        });
                                        return node;
                                      });
                                      try {
                                        final map =
                                            _projectManagerNameControllers;
                                        controller = map[index] ??
                                            TextEditingController();
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
                                        selectedBlocks =
                                            _projectManagerSelectedBlocks[
                                                    index] ??
                                                [];
                                      } catch (e) {
                                        selectedBlocks = [];
                                      }
                                      final isLast =
                                          index == projectManagers.length - 1;
                                      return Container(
                                        width: 320,
                                        height: 48,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            top: BorderSide.none,
                                            left: BorderSide.none,
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            height: 32,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: focusNode.hasFocus
                                                      ? const Color(0xFF0C8CE9)
                                                      : (((controller.text
                                                                  .trim()
                                                                  .isEmpty) ||
                                                              (_projectManagers[
                                                                              index]
                                                                          [
                                                                          'name'] ==
                                                                      null ||
                                                                  _projectManagers[
                                                                              index]
                                                                          [
                                                                          'name']
                                                                      .toString()
                                                                      .trim()
                                                                      .isEmpty))
                                                          ? (index == 0 &&
                                                                  _isProjectManagerFirstRowWarningState
                                                              ? const Color(
                                                                  0xFFFFC107)
                                                              : Colors.red)
                                                          : Colors.black
                                                              .withOpacity(
                                                                  0.15)),
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 0),
                                                  spreadRadius: 0,
                                                ),
                                              ],
                                            ),
                                            child: TextField(
                                              controller: controller,
                                              focusNode: focusNode,
                                              textAlignVertical:
                                                  TextAlignVertical.center,
                                              onChanged: (value) {
                                                setState(() {
                                                  _projectManagers[index]
                                                      ['name'] = value;
                                                });
                                                _onDataChanged();
                                              },
                                              decoration: InputDecoration(
                                                hintText: 'Enter a name',
                                                hintStyle: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: const Color.fromARGB(
                                                      191, 173, 173, 173),
                                                ),
                                                border: InputBorder.none,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 0,
                                                        vertical: 0),
                                                isDense: true,
                                              ),
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF707070)
                                            .withOpacity(0.2),
                                        border: const Border(
                                          top: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          right: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          bottom: BorderSide(
                                              color: Colors.black, width: 1.0),
                                        ),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Compensation ',
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
                                      ),
                                    ),
                                    // Rows
                                    ...List.generate(projectManagers.length,
                                        (index) {
                                      // Safely get compensation value
                                      String selectedCompensation = '';
                                      try {
                                        selectedCompensation =
                                            _projectManagerCompensation[
                                                    index] ??
                                                '';
                                      } catch (e) {
                                        // If map is null, use empty string
                                        selectedCompensation = '';
                                      }
                                      // Get selected blocks for this project manager
                                      List<String> selectedBlocks = [];
                                      try {
                                        if (_projectManagerSelectedBlocks !=
                                                null &&
                                            _projectManagerSelectedBlocks
                                                .containsKey(index)) {
                                          final blocks =
                                              _projectManagerSelectedBlocks[
                                                  index];
                                          if (blocks != null) {
                                            // Ensure it's a list of strings
                                            selectedBlocks = blocks
                                                .map((b) => b.toString())
                                                .toList();
                                            print(
                                                'Displaying blocks for manager $index: $selectedBlocks, joined: ${selectedBlocks.join(",")}');
                                          }
                                        }
                                      } catch (e) {
                                        selectedBlocks = [];
                                      }
                                      final hasSelectedBlocks =
                                          selectedBlocks.isNotEmpty;
                                      final blocksDisplayText =
                                          hasSelectedBlocks
                                              ? selectedBlocks.join(",")
                                              : '';
                                      final compensationKey = GlobalKey();
                                      return Container(
                                        key: compensationKey,
                                        width: 350,
                                        height: 48,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            top: BorderSide.none,
                                            left: BorderSide.none,
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            constraints: const BoxConstraints(
                                                minHeight: 48),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 7),
                                            child: Builder(
                                              builder: (builderContext) {
                                                return Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Flexible(
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          _showCompensationDropdown(
                                                              builderContext,
                                                              index,
                                                              compensationKey);
                                                        },
                                                        child:
                                                            selectedCompensation
                                                                    .isNotEmpty
                                                                ? Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      IntrinsicWidth(
                                                                        child:
                                                                            Container(
                                                                          height:
                                                                              32,
                                                                          padding: const EdgeInsets
                                                                              .symmetric(
                                                                              horizontal: 8),
                                                                          decoration:
                                                                              BoxDecoration(
                                                                            color:
                                                                                _getCompensationColor(selectedCompensation),
                                                                            borderRadius:
                                                                                BorderRadius.circular(8),
                                                                            boxShadow: [
                                                                              BoxShadow(
                                                                                color: Colors.black.withOpacity(0.25),
                                                                                blurRadius: 2,
                                                                                offset: const Offset(0, 0),
                                                                                spreadRadius: 0,
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          child:
                                                                              Center(
                                                                            child:
                                                                                Align(
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
                                                                          padding: const EdgeInsets
                                                                              .only(
                                                                              top: 4),
                                                                          child:
                                                                              Text(
                                                                            'Blocks: $blocksDisplayText',
                                                                            style:
                                                                                GoogleFonts.inter(
                                                                              fontSize: 12,
                                                                              fontWeight: FontWeight.normal,
                                                                              color: const Color(0xFF5D5D5D),
                                                                            ),
                                                                            maxLines:
                                                                                2,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                          ),
                                                                        ),
                                                                    ],
                                                                  )
                                                                : Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Container(
                                                                        width:
                                                                            230,
                                                                        height:
                                                                            32,
                                                                        padding: const EdgeInsets
                                                                            .symmetric(
                                                                            horizontal:
                                                                                8),
                                                                        decoration:
                                                                            BoxDecoration(
                                                                          color:
                                                                              Colors.white,
                                                                          borderRadius:
                                                                              BorderRadius.circular(4),
                                                                          boxShadow: [
                                                                            BoxShadow(
                                                                              color: (index == 0 && _isProjectManagerFirstRowWarningState) ? const Color(0xFFFFC107) : Colors.red,
                                                                              blurRadius: 2,
                                                                              offset: const Offset(0, 0),
                                                                              spreadRadius: 0,
                                                                            ),
                                                                          ],
                                                                        ),
                                                                        child:
                                                                            Center(
                                                                          child:
                                                                              Text(
                                                                            'Select the Compensation Type',
                                                                            style:
                                                                                GoogleFonts.inter(
                                                                              fontSize: 14,
                                                                              fontWeight: FontWeight.w500,
                                                                              color: _openProjectManagerCompensationDropdownIndex == index ? Colors.black : const Color.fromARGB(191, 173, 173, 173),
                                                                            ),
                                                                            textAlign:
                                                                                TextAlign.left,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      if (hasSelectedBlocks)
                                                                        Padding(
                                                                          padding: const EdgeInsets
                                                                              .only(
                                                                              top: 4),
                                                                          child:
                                                                              Text(
                                                                            'Blocks: $blocksDisplayText',
                                                                            style:
                                                                                GoogleFonts.inter(
                                                                              fontSize: 12,
                                                                              fontWeight: FontWeight.normal,
                                                                              color: const Color(0xFF5D5D5D),
                                                                            ),
                                                                            maxLines:
                                                                                2,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                          ),
                                                                        ),
                                                                    ],
                                                                  ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          _showCompensationDropdown(
                                                              builderContext,
                                                              index,
                                                              compensationKey);
                                                        },
                                                        child: SvgPicture.asset(
                                                          'assets/images/Drrrop_down.svg',
                                                          width: 14,
                                                          height: 7,
                                                          fit: BoxFit.contain,
                                                          colorFilter: selectedCompensation
                                                                  .isNotEmpty
                                                              ? const ColorFilter
                                                                  .mode(
                                                                  Colors.black,
                                                                  BlendMode
                                                                      .srcIn)
                                                              : ColorFilter.mode(
                                                                  (index == 0 &&
                                                                          _isProjectManagerFirstRowWarningState)
                                                                      ? Colors
                                                                          .black
                                                                      : Colors
                                                                          .red,
                                                                  BlendMode
                                                                      .srcIn),
                                                          placeholderBuilder:
                                                              (context) =>
                                                                  const SizedBox(
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF707070)
                                            .withOpacity(0.2),
                                        border: const Border(
                                          top: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          right: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          bottom: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          left: BorderSide.none,
                                        ),
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(8),
                                        ),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Earning Type ',
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
                                      ),
                                    ),
                                    // Rows
                                    ...List.generate(projectManagers.length,
                                        (index) {
                                      // Safely get earning type value
                                      String selectedEarningType = '';
                                      try {
                                        selectedEarningType =
                                            _projectManagerEarningType[index] ??
                                                '';
                                      } catch (e) {
                                        // If map is null, use empty string
                                        selectedEarningType = '';
                                      }
                                      // Get compensation type
                                      String compensationType = '';
                                      try {
                                        compensationType =
                                            _projectManagerCompensation[
                                                    index] ??
                                                '';
                                      } catch (e) {
                                        compensationType = '';
                                      }
                                      final isPercentageBonus =
                                          compensationType ==
                                              'Percentage Bonus';
                                      final isFixedFee =
                                          compensationType == 'Fixed Fee';
                                      final isMonthlyFee =
                                          compensationType == 'Monthly Fee';
                                      final hasEarningType =
                                          selectedEarningType.isNotEmpty;
                                      // Get percentage value
                                      String percentageValue = '';
                                      try {
                                        percentageValue =
                                            _projectManagerPercentage[index] ??
                                                '0';
                                      } catch (e) {
                                        percentageValue = '0';
                                      }
                                      // Get Fixed Fee amount value
                                      String fixedFeeValue = '';
                                      try {
                                        fixedFeeValue =
                                            _projectManagerFixedFee[index] ??
                                                '0';
                                      } catch (e) {
                                        fixedFeeValue = '0';
                                      }
                                      // Get Monthly Fee amount value
                                      String monthlyFeeValue = '';
                                      try {
                                        monthlyFeeValue =
                                            _projectManagerMonthlyFee[index] ??
                                                '0';
                                      } catch (e) {
                                        monthlyFeeValue = '0';
                                      }
                                      // Get Months value
                                      String monthsValue = '';
                                      try {
                                        monthsValue =
                                            _projectManagerMonths[index] ?? '';
                                      } catch (e) {
                                        monthsValue = '';
                                      }
                                      final isLast =
                                          index == projectManagers.length - 1;
                                      final earningTypeKey = GlobalKey();
                                      return Container(
                                        key: earningTypeKey,
                                        width: 365,
                                        height: 48,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            top: BorderSide.none,
                                            left: BorderSide.none,
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            constraints: const BoxConstraints(
                                                minHeight: 48),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 7),
                                            child: Builder(
                                              builder: (context) {
                                                final row = Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Row(
                                                        children: [
                                                          // Percentage input field (only show if percentage bonus and earning type selected)
                                                          if (isPercentageBonus &&
                                                              hasEarningType)
                                                            SizedBox(
                                                              width: 48,
                                                              child: Builder(
                                                                builder: (context) =>
                                                                    _buildProjectManagerPercentageField(
                                                                        index,
                                                                        context),
                                                              ),
                                                            ),
                                                          if (isPercentageBonus &&
                                                              hasEarningType)
                                                            const SizedBox(
                                                                width: 8),
                                                          // Earning type display (only for Percentage Bonus)
                                                          if (hasEarningType &&
                                                              isPercentageBonus)
                                                            GestureDetector(
                                                              onTap: () {
                                                                _showEarningTypeDropdown(
                                                                    context,
                                                                    index,
                                                                    earningTypeKey);
                                                              },
                                                              child:
                                                                  IntrinsicWidth(
                                                                child:
                                                                    Container(
                                                                  constraints:
                                                                      const BoxConstraints(
                                                                          minHeight:
                                                                              38),
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          8),
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: const Color(
                                                                        0xFFECF6FD),
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(8),
                                                                    boxShadow: [
                                                                      BoxShadow(
                                                                        color: Colors
                                                                            .black
                                                                            .withOpacity(0.25),
                                                                        blurRadius:
                                                                            2,
                                                                        offset: const Offset(
                                                                            0,
                                                                            0),
                                                                        spreadRadius:
                                                                            0,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  child: Text(
                                                                    selectedEarningType,
                                                                    style: GoogleFonts
                                                                        .inter(
                                                                      fontSize:
                                                                          14,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .normal,
                                                                      color: Colors
                                                                          .black,
                                                                    ),
                                                                    textAlign:
                                                                        TextAlign
                                                                            .left,
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                          // Fixed Fee amount input - show when Fixed Fee is selected (similar to partners section)
                                                          else if (isFixedFee)
                                                            Builder(
                                                              builder: (context) =>
                                                                  _buildProjectManagerFixedFeeField(
                                                                      index,
                                                                      context),
                                                            )
                                                          // Monthly Fee amount input - show when Monthly Fee is selected
                                                          else if (isMonthlyFee)
                                                            Row(
                                                              children: [
                                                                Builder(
                                                                  builder: (context) =>
                                                                      _buildProjectManagerMonthlyFeeField(
                                                                          index,
                                                                          context),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Text(
                                                                  '*',
                                                                  style:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontSize:
                                                                        14,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .normal,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Builder(
                                                                  builder: (context) =>
                                                                      _buildProjectManagerMonthsField(
                                                                          index,
                                                                          context),
                                                                ),
                                                              ],
                                                            )
                                                          else
                                                            Expanded(
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .spaceBetween,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Container(
                                                                    width: 180,
                                                                    height: 32,
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            8),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: hasEarningType
                                                                          ? const Color(
                                                                              0xFFECF6FD)
                                                                          : Colors
                                                                              .white,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              4),
                                                                      boxShadow: [
                                                                        BoxShadow(
                                                                          color: (compensationType.isNotEmpty && compensationType != 'None' && selectedEarningType.isEmpty)
                                                                              ? Colors.red
                                                                              : Colors.black.withOpacity(0.15),
                                                                          blurRadius:
                                                                              2,
                                                                          offset: const Offset(
                                                                              0,
                                                                              0),
                                                                          spreadRadius:
                                                                              0,
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    child:
                                                                        Align(
                                                                      alignment:
                                                                          Alignment
                                                                              .centerLeft,
                                                                      child:
                                                                          Text(
                                                                        compensationType ==
                                                                                'None'
                                                                            ? 'NA'
                                                                            : (selectedEarningType.isEmpty
                                                                                ? 'Select Earning Type'
                                                                                : selectedEarningType),
                                                                        style: GoogleFonts
                                                                            .inter(
                                                                          fontSize:
                                                                              14,
                                                                          fontWeight: selectedEarningType.isEmpty
                                                                              ? FontWeight.w500
                                                                              : FontWeight.normal,
                                                                          color: compensationType == 'None'
                                                                              ? Colors.black
                                                                              : (selectedEarningType.isEmpty ? (_openProjectManagerEarningDropdownIndex == index ? Colors.black : const Color.fromARGB(191, 173, 173, 173)) : Colors.black),
                                                                        ),
                                                                        textAlign:
                                                                            TextAlign.left,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        softWrap:
                                                                            false,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  if (compensationType
                                                                          .isNotEmpty &&
                                                                      compensationType !=
                                                                          'None') ...[
                                                                    const SizedBox(
                                                                        width:
                                                                            4),
                                                                    Center(
                                                                      child: SvgPicture
                                                                          .asset(
                                                                        'assets/images/Drrrop_down.svg',
                                                                        width:
                                                                            14,
                                                                        height:
                                                                            7,
                                                                        fit: BoxFit
                                                                            .contain,
                                                                        colorFilter: ColorFilter.mode(
                                                                            (compensationType.isNotEmpty && compensationType != 'None' && selectedEarningType.isEmpty)
                                                                                ? Colors.red
                                                                                : Colors.black,
                                                                            BlendMode.srcIn),
                                                                        placeholderBuilder:
                                                                            (context) =>
                                                                                const SizedBox(
                                                                          width:
                                                                              14,
                                                                          height:
                                                                              7,
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
                                                    if (isPercentageBonus &&
                                                        hasEarningType)
                                                      const SizedBox(width: 8),
                                                    if (isPercentageBonus &&
                                                        hasEarningType)
                                                      Container(
                                                        constraints:
                                                            const BoxConstraints(
                                                                minHeight: 38),
                                                        alignment:
                                                            Alignment.center,
                                                        child: SvgPicture.asset(
                                                          'assets/images/Drrrop_down.svg',
                                                          width: 14,
                                                          height: 7,
                                                          fit: BoxFit.contain,
                                                          placeholderBuilder:
                                                              (context) =>
                                                                  const SizedBox(
                                                            width: 14,
                                                            height: 7,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                );
                                                if (isPercentageBonus &&
                                                    hasEarningType) {
                                                  return row;
                                                }
                                                if (compensationType.isEmpty ||
                                                    compensationType ==
                                                        'None') {
                                                  return row;
                                                }
                                                return GestureDetector(
                                                  onTap: () {
                                                    _showEarningTypeDropdown(
                                                        context,
                                                        index,
                                                        earningTypeKey);
                                                  },
                                                  child: row,
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
                                    // Spacer to align Remove buttons with project manager data rows
                                    const SizedBox(
                                      width: 120,
                                      height: 47,
                                    ),
                                    // Rows with Remove buttons
                                    ...List.generate(projectManagers.length,
                                        (index) {
                                      final isLast =
                                          index == projectManagers.length - 1;
                                      return Container(
                                        width: 120,
                                        height: index == 0 ? 49 : 48,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            top: index == 0
                                                ? const BorderSide(
                                                    color: Colors.black,
                                                    width: 1.0)
                                                : BorderSide.none,
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            left: BorderSide.none,
                                          ),
                                          borderRadius: index == 0 &&
                                                  projectManagers.length == 1
                                              ? const BorderRadius.only(
                                                  topRight: Radius.circular(8),
                                                  bottomRight:
                                                      Radius.circular(8),
                                                )
                                              : (index == 0
                                                  ? const BorderRadius.only(
                                                      topRight:
                                                          Radius.circular(8),
                                                    )
                                                  : (isLast
                                                      ? const BorderRadius.only(
                                                          bottomRight:
                                                              Radius.circular(
                                                                  8),
                                                        )
                                                      : null)),
                                        ),
                                        child: Center(
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                try {
                                                  // Dispose the controller at this index
                                                  _projectManagerNameControllers[
                                                          index]
                                                      ?.dispose();

                                                  // Remove all data for this index
                                                  _projectManagerNameControllers
                                                      .remove(index);
                                                  _projectManagerCompensation
                                                      .remove(index);
                                                  _projectManagerEarningType
                                                      .remove(index);
                                                  _projectManagerPercentageControllers[
                                                          index]
                                                      ?.dispose();
                                                  _projectManagerFixedFeeControllers[
                                                          index]
                                                      ?.dispose();
                                                  _projectManagerMonthlyFeeControllers[
                                                          index]
                                                      ?.dispose();
                                                  _projectManagerMonthsControllers[
                                                          index]
                                                      ?.dispose();
                                                  _projectManagerPercentageControllers
                                                      .remove(index);
                                                  _projectManagerFixedFeeControllers
                                                      .remove(index);
                                                  _projectManagerMonthlyFeeControllers
                                                      .remove(index);
                                                  _projectManagerMonthsControllers
                                                      .remove(index);
                                                  _projectManagerPercentage
                                                      .remove(index);
                                                  _projectManagerFixedFee
                                                      .remove(index);
                                                  _projectManagerMonthlyFee
                                                      .remove(index);
                                                  _projectManagerMonths
                                                      .remove(index);
                                                  _projectManagerSelectedBlocks
                                                      .remove(index);

                                                  // Remove from the main list
                                                  _projectManagers
                                                      .removeAt(index);

                                                  // Reindex all controllers and maps to be sequential starting from 0
                                                  final newControllers = <int,
                                                      TextEditingController>{};
                                                  final newCompensation =
                                                      <int, String>{};
                                                  final newEarningType =
                                                      <int, String>{};
                                                  final newPercentageControllers =
                                                      <int,
                                                          TextEditingController>{};
                                                  final newFixedFeeControllers =
                                                      <int,
                                                          TextEditingController>{};
                                                  final newMonthlyFeeControllers =
                                                      <int,
                                                          TextEditingController>{};
                                                  final newMonthsControllers =
                                                      <int,
                                                          TextEditingController>{};
                                                  final newPercentage =
                                                      <int, String>{};
                                                  final newFixedFee =
                                                      <int, String>{};
                                                  final newMonthlyFee =
                                                      <int, String>{};
                                                  final newMonths =
                                                      <int, String>{};
                                                  final newSelectedBlocks =
                                                      <int, List<String>>{};

                                                  int newIndex = 0;
                                                  for (int oldIndex = 0;
                                                      oldIndex <
                                                          _projectManagerNameControllers
                                                                  .length +
                                                              1;
                                                      oldIndex++) {
                                                    if (oldIndex == index)
                                                      continue; // Skip the deleted index

                                                    if (_projectManagerNameControllers
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newControllers[newIndex] =
                                                          _projectManagerNameControllers[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerCompensation
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newCompensation[
                                                              newIndex] =
                                                          _projectManagerCompensation[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerEarningType
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newEarningType[newIndex] =
                                                          _projectManagerEarningType[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerPercentageControllers
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newPercentageControllers[
                                                              newIndex] =
                                                          _projectManagerPercentageControllers[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerFixedFeeControllers
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newFixedFeeControllers[
                                                              newIndex] =
                                                          _projectManagerFixedFeeControllers[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerMonthlyFeeControllers
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newMonthlyFeeControllers[
                                                              newIndex] =
                                                          _projectManagerMonthlyFeeControllers[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerMonthsControllers
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newMonthsControllers[
                                                              newIndex] =
                                                          _projectManagerMonthsControllers[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerPercentage
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newPercentage[newIndex] =
                                                          _projectManagerPercentage[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerFixedFee
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newFixedFee[newIndex] =
                                                          _projectManagerFixedFee[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerMonthlyFee
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newMonthlyFee[newIndex] =
                                                          _projectManagerMonthlyFee[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerMonths
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newMonths[newIndex] =
                                                          _projectManagerMonths[
                                                              oldIndex]!;
                                                    }
                                                    if (_projectManagerSelectedBlocks
                                                        .containsKey(
                                                            oldIndex)) {
                                                      newSelectedBlocks[
                                                              newIndex] =
                                                          _projectManagerSelectedBlocks[
                                                              oldIndex]!;
                                                    }

                                                    newIndex++;
                                                  }

                                                  // Replace with reindexed maps
                                                  _projectManagerNameControllers
                                                      .clear();
                                                  for (var focusNode
                                                      in _projectManagerNameFocusNodes
                                                          .values) {
                                                    focusNode.dispose();
                                                  }
                                                  _projectManagerNameFocusNodes
                                                      .clear();
                                                  _projectManagerCompensation
                                                      .clear();
                                                  _projectManagerEarningType
                                                      .clear();
                                                  _projectManagerPercentageControllers
                                                      .clear();
                                                  _projectManagerFixedFeeControllers
                                                      .clear();
                                                  _projectManagerMonthlyFeeControllers
                                                      .clear();
                                                  _projectManagerMonthsControllers
                                                      .clear();
                                                  _projectManagerPercentage
                                                      .clear();
                                                  _projectManagerFixedFee
                                                      .clear();
                                                  _projectManagerMonthlyFee
                                                      .clear();
                                                  _projectManagerMonths.clear();
                                                  _projectManagerSelectedBlocks
                                                      .clear();

                                                  _projectManagerNameControllers
                                                      .addAll(newControllers);
                                                  _projectManagerCompensation
                                                      .addAll(newCompensation);
                                                  _projectManagerEarningType
                                                      .addAll(newEarningType);
                                                  _projectManagerPercentageControllers
                                                      .addAll(
                                                          newPercentageControllers);
                                                  _projectManagerFixedFeeControllers
                                                      .addAll(
                                                          newFixedFeeControllers);
                                                  _projectManagerMonthlyFeeControllers
                                                      .addAll(
                                                          newMonthlyFeeControllers);
                                                  _projectManagerMonthsControllers
                                                      .addAll(
                                                          newMonthsControllers);
                                                  _projectManagerPercentage
                                                      .addAll(newPercentage);
                                                  _projectManagerFixedFee
                                                      .addAll(newFixedFee);
                                                  _projectManagerMonthlyFee
                                                      .addAll(newMonthlyFee);
                                                  _projectManagerMonths
                                                      .addAll(newMonths);
                                                  _projectManagerSelectedBlocks
                                                      .addAll(
                                                          newSelectedBlocks);
                                                } catch (e) {
                                                  print(
                                                      'Error deleting project manager: $e');
                                                  // If maps are null, just remove from _projectManagers
                                                  _projectManagers
                                                      .removeAt(index);
                                                }
                                              });
                                              _onDataChanged();
                                            },
                                            child: Container(
                                              height: 36,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.25),
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
                                                    fontWeight:
                                                        FontWeight.normal,
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
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            // Add Project Manager button
            GestureDetector(
              onTap: () {
                setState(() {
                  final newIndex = _projectManagers.length;
                  _projectManagers.add({
                    'name': '',
                    'compensation': '',
                    'earningType': '',
                  });
                  _projectManagerNameControllers[newIndex] =
                      TextEditingController();
                  _projectManagerCompensation[newIndex] = '';
                  _projectManagerEarningType[newIndex] = '';
                  _projectManagerPercentage[newIndex] = '';
                  _projectManagerFixedFee[newIndex] = '';
                  _projectManagerMonthlyFee[newIndex] = '';
                  _projectManagerMonths[newIndex] = '';
                  _projectManagerPercentageControllers[newIndex] =
                      TextEditingController();
                  _projectManagerFixedFeeControllers[newIndex] =
                      TextEditingController();
                  _projectManagerMonthlyFeeControllers[newIndex] =
                      TextEditingController();
                  _projectManagerMonthsControllers[newIndex] =
                      TextEditingController();
                });
                _onDataChanged();
              },
              child: Container(
                height: 36,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    ),
                  ],
                ),
              ),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
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
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Row(
                    children: [
                      Text(
                        'Zoom',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            // Decrease zoom by 10% (minimum 50%)
                            _tableZoomLevel =
                                (_tableZoomLevel - 0.1).clamp(0.5, 1.2);
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
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
                          child: SvgPicture.asset(
                            'assets/images/Zoom_out.svg',
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            placeholderBuilder: (context) => SizedBox(
                              width: 36,
                              height: 36,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_tableZoomLevel * 100).toInt()}%',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            // Increase zoom by 10% (maximum 120%)
                            _tableZoomLevel =
                                (_tableZoomLevel + 0.1).clamp(0.5, 1.2);
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
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
                          child: SvgPicture.asset(
                            'assets/images/Zoom_in.svg',
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            placeholderBuilder: (context) => SizedBox(
                              width: 36,
                              height: 36,
                            ),
                          ),
                        ),
                      ),
                    ],
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
                    _agentPercentageControllers[newIndex] =
                        TextEditingController();
                    _agentFixedFeeControllers[newIndex] =
                        TextEditingController();
                    _agentMonthlyFeeControllers[newIndex] =
                        TextEditingController();
                    _agentMonthsControllers[newIndex] = TextEditingController();
                    _agentPerSqftFeeControllers[newIndex] =
                        TextEditingController();
                  });
                  _saveAgentsData(); // Save agents immediately
                  _onDataChanged();
                },
                child: Container(
                  height: 36,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
        _agents = [
          {'name': '', 'compensation': '', 'earningType': ''}
        ];
      }
    } catch (e) {
      _agents = [
        {'name': '', 'compensation': '', 'earningType': ''}
      ];
    }

    try {
      if (_agentNameControllers == null) {
        // This shouldn't happen, but handle it if it does
      }
    } catch (e) {
      // Maps might be undefined, but we'll handle it in access points
    }

    final agents = _agents;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
          right: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
          top: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
          bottom: 8 +
              (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)) +
              (50 *
                  (_tableZoomLevel - 1.0).clamp(0.0,
                      0.2)), // Extra bottom padding for scaled content to prevent border clipping
        ), // Add extra padding when zoomed to show borders
        clipBehavior: Clip.hardEdge,
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
            Builder(
              builder: (context) {
                // Calculate dynamic height based on number of agents
                // Header row: 48px, each agent row: 48px
                double baseHeaderHeight = 48.0;
                double baseRowHeight = 48.0;
                double calculatedHeight =
                    baseHeaderHeight + (agents.length * baseRowHeight);
                // Store base height (same as when zoom = 1.0)
                final baseHeight = calculatedHeight;
                // Calculate scaled height for outer container
                double scaledHeight = calculatedHeight * _tableZoomLevel;
                // Only apply minimum height if calculated height is very small (less than header + 1 row)
                final minHeight =
                    (baseHeaderHeight + baseRowHeight) * _tableZoomLevel;
                if (scaledHeight < minHeight) {
                  scaledHeight = minHeight;
                }
                // Add buffer for scaled border to prevent clipping
                final borderBuffer = _tableZoomLevel > 1.0 ? 5.0 : 0.0;
                scaledHeight = scaledHeight + borderBuffer;

                return SizedBox(
                  width: double.infinity,
                  height: scaledHeight,
                  child: Scrollbar(
                    controller: _agentsTableScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _agentsTableScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      clipBehavior: Clip.none,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left:
                              ((_tableZoomLevel - 1.0) * 10.0).clamp(0.0, 10.0),
                          right: ((_tableZoomLevel - 1.0) * 10.0)
                                  .clamp(0.0, 10.0) +
                              ((_tableZoomLevel - 1.0) * 1350.0).clamp(0.0,
                                  1350.0), // Extra right padding when zoomed to allow full scrolling to last column
                          top:
                              ((_tableZoomLevel - 1.0) * 10.0).clamp(0.0, 10.0),
                          bottom: ((_tableZoomLevel - 1.0) * 10.0)
                                  .clamp(0.0, 10.0) +
                              ((_tableZoomLevel - 1.0) * 100.0).clamp(0.0,
                                  100.0), // Extra bottom padding for scaled borders to prevent clipping
                        ),
                        child: Transform.scale(
                          scale: _tableZoomLevel,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            height:
                                baseHeight, // Use base height (same as when zoom = 1.0), Transform.scale will handle scaling
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
                                        color: const Color(0xFF707070)
                                            .withOpacity(0.2),
                                        border: Border.all(
                                            color: Colors.black, width: 1.0),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(8),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Sl. No.',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
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
                                          selectedBlocks =
                                              _agentSelectedBlocks[index] ?? [];
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
                                            left: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            top: BorderSide.none,
                                          ),
                                          borderRadius: isLast
                                              ? const BorderRadius.only(
                                                  bottomLeft:
                                                      Radius.circular(8),
                                                )
                                              : null,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF707070)
                                            .withOpacity(0.2),
                                        border: const Border(
                                          top: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          right: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          bottom: BorderSide(
                                              color: Colors.black, width: 1.0),
                                        ),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Agent(s) ',
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
                                      ),
                                    ),
                                    // Rows
                                    ...List.generate(agents.length, (index) {
                                      TextEditingController controller;
                                      final focusNode = _agentNameFocusNodes
                                          .putIfAbsent(index, () {
                                        final node = FocusNode();
                                        node.addListener(() {
                                          if (mounted) setState(() {});
                                        });
                                        return node;
                                      });
                                      try {
                                        final map = _agentNameControllers;
                                        controller = map[index] ??
                                            TextEditingController();
                                        if (map[index] == null) {
                                          map[index] = controller;
                                        }
                                      } catch (e) {
                                        controller = TextEditingController();
                                      }
                                      List<String> selectedBlocks = [];
                                      try {
                                        selectedBlocks =
                                            _agentSelectedBlocks[index] ?? [];
                                      } catch (e) {
                                        selectedBlocks = [];
                                      }
                                      final isLast = index == agents.length - 1;
                                      return Container(
                                        width: 320,
                                        height: 48,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            top: BorderSide.none,
                                            left: BorderSide.none,
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            height: 32,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: focusNode.hasFocus
                                                      ? const Color(0xFF0C8CE9)
                                                      : (((controller.text
                                                                  .trim()
                                                                  .isEmpty) ||
                                                              (_agents[index][
                                                                          'name'] ==
                                                                      null ||
                                                                  _agents[index]
                                                                          [
                                                                          'name']
                                                                      .toString()
                                                                      .trim()
                                                                      .isEmpty))
                                                          ? (index == 0 &&
                                                                  _isAgentFirstRowWarningState
                                                              ? const Color(
                                                                  0xFFFFC107)
                                                              : Colors.red)
                                                          : Colors.black
                                                              .withOpacity(
                                                                  0.15)),
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 0),
                                                  spreadRadius: 0,
                                                ),
                                              ],
                                            ),
                                            child: TextField(
                                              controller: controller,
                                              focusNode: focusNode,
                                              textAlignVertical:
                                                  TextAlignVertical.center,
                                              onChanged: (value) {
                                                setState(() {
                                                  _agents[index]['name'] =
                                                      value;
                                                });
                                                _onDataChanged();
                                              },
                                              decoration: InputDecoration(
                                                hintText: 'Enter a name',
                                                hintStyle: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: const Color.fromARGB(
                                                      191, 173, 173, 173),
                                                ),
                                                border: InputBorder.none,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 0,
                                                        vertical: 0),
                                                isDense: true,
                                              ),
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF707070)
                                            .withOpacity(0.2),
                                        border: const Border(
                                          top: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          right: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          bottom: BorderSide(
                                              color: Colors.black, width: 1.0),
                                        ),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Compensation ',
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
                                      ),
                                    ),
                                    // Rows
                                    ...List.generate(agents.length, (index) {
                                      String selectedCompensation = '';
                                      try {
                                        selectedCompensation =
                                            _agentCompensation[index] ?? '';
                                      } catch (e) {
                                        selectedCompensation = '';
                                      }
                                      List<String> selectedBlocks = [];
                                      try {
                                        if (_agentSelectedBlocks != null &&
                                            _agentSelectedBlocks
                                                .containsKey(index)) {
                                          final blocks =
                                              _agentSelectedBlocks[index];
                                          if (blocks != null) {
                                            // Ensure it's a list of strings
                                            selectedBlocks = blocks
                                                .map((b) => b.toString())
                                                .toList();
                                            print(
                                                'Displaying blocks for agent $index: $selectedBlocks, joined: ${selectedBlocks.join(",")}');
                                          }
                                        }
                                      } catch (e) {
                                        selectedBlocks = [];
                                      }
                                      final hasSelectedBlocks =
                                          selectedBlocks.isNotEmpty;
                                      final blocksDisplayText =
                                          hasSelectedBlocks
                                              ? selectedBlocks.join(",")
                                              : '';
                                      final compensationKey = GlobalKey();
                                      return Container(
                                        key: compensationKey,
                                        width: 350,
                                        height: 48,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            top: BorderSide.none,
                                            left: BorderSide.none,
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            constraints: const BoxConstraints(
                                                minHeight: 48),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 7),
                                            child: Builder(
                                              builder: (builderContext) {
                                                return Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Flexible(
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          _showAgentCompensationDropdown(
                                                              builderContext,
                                                              index,
                                                              compensationKey);
                                                        },
                                                        child:
                                                            selectedCompensation
                                                                    .isNotEmpty
                                                                ? Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      IntrinsicWidth(
                                                                        child:
                                                                            Container(
                                                                          height:
                                                                              32,
                                                                          padding: const EdgeInsets
                                                                              .symmetric(
                                                                              horizontal: 8),
                                                                          decoration:
                                                                              BoxDecoration(
                                                                            color:
                                                                                _getCompensationColor(selectedCompensation),
                                                                            borderRadius:
                                                                                BorderRadius.circular(8),
                                                                            boxShadow: [
                                                                              BoxShadow(
                                                                                color: Colors.black.withOpacity(0.25),
                                                                                blurRadius: 2,
                                                                                offset: const Offset(0, 0),
                                                                                spreadRadius: 0,
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          child:
                                                                              Center(
                                                                            child:
                                                                                Align(
                                                                              alignment: Alignment.centerLeft,
                                                                              child: Text(
                                                                                selectedCompensation == 'Per Sqft Fee' ? AreaUnitUtils.perAreaFeeLabel(_isSqm) : selectedCompensation,
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
                                                                          padding: const EdgeInsets
                                                                              .only(
                                                                              top: 4),
                                                                          child:
                                                                              Text(
                                                                            'Blocks: $blocksDisplayText',
                                                                            style:
                                                                                GoogleFonts.inter(
                                                                              fontSize: 12,
                                                                              fontWeight: FontWeight.normal,
                                                                              color: const Color(0xFF5D5D5D),
                                                                            ),
                                                                            maxLines:
                                                                                2,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                          ),
                                                                        ),
                                                                    ],
                                                                  )
                                                                : Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Container(
                                                                        width:
                                                                            230,
                                                                        height:
                                                                            32,
                                                                        padding: const EdgeInsets
                                                                            .symmetric(
                                                                            horizontal:
                                                                                8),
                                                                        decoration:
                                                                            BoxDecoration(
                                                                          color:
                                                                              Colors.white,
                                                                          borderRadius:
                                                                              BorderRadius.circular(4),
                                                                          boxShadow: [
                                                                            BoxShadow(
                                                                              color: (index == 0 && _isAgentFirstRowWarningState) ? const Color(0xFFFFC107) : Colors.red,
                                                                              blurRadius: 2,
                                                                              offset: const Offset(0, 0),
                                                                              spreadRadius: 0,
                                                                            ),
                                                                          ],
                                                                        ),
                                                                        child:
                                                                            Center(
                                                                          child:
                                                                              Text(
                                                                            'Select the Compensation Type',
                                                                            style:
                                                                                GoogleFonts.inter(
                                                                              fontSize: 14,
                                                                              fontWeight: FontWeight.w500,
                                                                              color: _openAgentCompensationDropdownIndex == index ? Colors.black : const Color.fromARGB(191, 173, 173, 173),
                                                                            ),
                                                                            textAlign:
                                                                                TextAlign.left,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      if (hasSelectedBlocks)
                                                                        Padding(
                                                                          padding: const EdgeInsets
                                                                              .only(
                                                                              top: 4),
                                                                          child:
                                                                              Text(
                                                                            'Blocks: $blocksDisplayText',
                                                                            style:
                                                                                GoogleFonts.inter(
                                                                              fontSize: 12,
                                                                              fontWeight: FontWeight.normal,
                                                                              color: const Color(0xFF5D5D5D),
                                                                            ),
                                                                            maxLines:
                                                                                2,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                          ),
                                                                        ),
                                                                    ],
                                                                  ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          _showAgentCompensationDropdown(
                                                              builderContext,
                                                              index,
                                                              compensationKey);
                                                        },
                                                        child: SvgPicture.asset(
                                                          'assets/images/Drrrop_down.svg',
                                                          width: 14,
                                                          height: 7,
                                                          fit: BoxFit.contain,
                                                          colorFilter: selectedCompensation
                                                                  .isNotEmpty
                                                              ? const ColorFilter
                                                                  .mode(
                                                                  Colors.black,
                                                                  BlendMode
                                                                      .srcIn)
                                                              : ColorFilter.mode(
                                                                  (index == 0 &&
                                                                          _isAgentFirstRowWarningState)
                                                                      ? Colors
                                                                          .black
                                                                      : Colors
                                                                          .red,
                                                                  BlendMode
                                                                      .srcIn),
                                                          placeholderBuilder:
                                                              (context) =>
                                                                  const SizedBox(
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF707070)
                                            .withOpacity(0.2),
                                        border: const Border(
                                          top: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          right: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          bottom: BorderSide(
                                              color: Colors.black, width: 1.0),
                                          left: BorderSide.none,
                                        ),
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(8),
                                        ),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Earning Type ',
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
                                      ),
                                    ),
                                    // Rows
                                    ...List.generate(agents.length, (index) {
                                      String selectedEarningType = '';
                                      try {
                                        selectedEarningType =
                                            _agentEarningType[index] ?? '';
                                      } catch (e) {
                                        selectedEarningType = '';
                                      }
                                      String compensationType = '';
                                      try {
                                        compensationType =
                                            _agentCompensation[index] ?? '';
                                      } catch (e) {
                                        compensationType = '';
                                      }
                                      final isPercentageBonus =
                                          compensationType ==
                                              'Percentage Bonus';
                                      final isFixedFee =
                                          compensationType == 'Fixed Fee';
                                      final isMonthlyFee =
                                          compensationType == 'Monthly Fee';
                                      final isPerSqftFee =
                                          compensationType == 'Per Sqft Fee';
                                      final hasEarningType =
                                          selectedEarningType.isNotEmpty;
                                      String percentageValue = '';
                                      try {
                                        percentageValue =
                                            _agentPercentage[index] ?? '0';
                                      } catch (e) {
                                        percentageValue = '0';
                                      }
                                      String fixedFeeValue = '';
                                      try {
                                        fixedFeeValue =
                                            _agentFixedFee[index] ?? '0';
                                      } catch (e) {
                                        fixedFeeValue = '0';
                                      }
                                      String monthlyFeeValue = '';
                                      try {
                                        monthlyFeeValue =
                                            _agentMonthlyFee[index] ?? '0';
                                      } catch (e) {
                                        monthlyFeeValue = '0';
                                      }
                                      String perSqftFeeValue = '';
                                      try {
                                        perSqftFeeValue =
                                            _agentPerSqftFee[index] ?? '0';
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            top: BorderSide.none,
                                            left: BorderSide.none,
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            constraints: const BoxConstraints(
                                                minHeight: 48),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 7),
                                            child: Builder(
                                              builder: (context) {
                                                final row = Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      child: Row(
                                                        children: [
                                                          if (isPercentageBonus &&
                                                              hasEarningType)
                                                            SizedBox(
                                                              width: 48,
                                                              child: Builder(
                                                                builder: (context) =>
                                                                    _buildAgentPercentageField(
                                                                        index,
                                                                        context),
                                                              ),
                                                            ),
                                                          if (isPercentageBonus &&
                                                              hasEarningType)
                                                            const SizedBox(
                                                                width: 8),
                                                          if (hasEarningType &&
                                                              isPercentageBonus)
                                                            GestureDetector(
                                                              onTap: () {
                                                                _showAgentEarningTypeDropdown(
                                                                    context,
                                                                    index,
                                                                    earningTypeKey);
                                                              },
                                                              child:
                                                                  IntrinsicWidth(
                                                                child:
                                                                    Container(
                                                                  constraints:
                                                                      const BoxConstraints(
                                                                          minHeight:
                                                                              38),
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          8),
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: const Color(
                                                                        0xFFECF6FD),
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(8),
                                                                    boxShadow: [
                                                                      BoxShadow(
                                                                        color: Colors
                                                                            .black
                                                                            .withOpacity(0.25),
                                                                        blurRadius:
                                                                            2,
                                                                        offset: const Offset(
                                                                            0,
                                                                            0),
                                                                        spreadRadius:
                                                                            0,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  child: Text(
                                                                    selectedEarningType,
                                                                    style: GoogleFonts
                                                                        .inter(
                                                                      fontSize:
                                                                          14,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .normal,
                                                                      color: Colors
                                                                          .black,
                                                                    ),
                                                                    textAlign:
                                                                        TextAlign
                                                                            .left,
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                          else if (isFixedFee)
                                                            Builder(
                                                              builder: (context) =>
                                                                  _buildAgentFixedFeeField(
                                                                      index,
                                                                      context),
                                                            )
                                                          else if (isMonthlyFee)
                                                            Row(
                                                              children: [
                                                                Builder(
                                                                  builder: (context) =>
                                                                      _buildAgentMonthlyFeeField(
                                                                          index,
                                                                          context),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Text(
                                                                  '*',
                                                                  style:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontSize:
                                                                        14,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .normal,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Builder(
                                                                  builder: (context) =>
                                                                      _buildAgentMonthsField(
                                                                          index,
                                                                          context),
                                                                ),
                                                              ],
                                                            )
                                                          else if (isPerSqftFee)
                                                            Builder(
                                                              builder: (context) =>
                                                                  _buildAgentPerSqftFeeField(
                                                                      index,
                                                                      context),
                                                            )
                                                          else
                                                            Expanded(
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .spaceBetween,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Container(
                                                                    width: 180,
                                                                    height: 32,
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            8),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: hasEarningType
                                                                          ? const Color(
                                                                              0xFFECF6FD)
                                                                          : Colors
                                                                              .white,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              4),
                                                                      boxShadow: [
                                                                        BoxShadow(
                                                                          color: (compensationType.isNotEmpty && compensationType != 'None' && selectedEarningType.isEmpty)
                                                                              ? Colors.red
                                                                              : Colors.black.withOpacity(0.15),
                                                                          blurRadius:
                                                                              2,
                                                                          offset: const Offset(
                                                                              0,
                                                                              0),
                                                                          spreadRadius:
                                                                              0,
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    child:
                                                                        Align(
                                                                      alignment:
                                                                          Alignment
                                                                              .centerLeft,
                                                                      child:
                                                                          Text(
                                                                        compensationType ==
                                                                                'None'
                                                                            ? 'NA'
                                                                            : (selectedEarningType.isEmpty
                                                                                ? 'Select Earning Type'
                                                                                : selectedEarningType),
                                                                        style: GoogleFonts
                                                                            .inter(
                                                                          fontSize:
                                                                              14,
                                                                          fontWeight: selectedEarningType.isEmpty
                                                                              ? FontWeight.w500
                                                                              : FontWeight.normal,
                                                                          color: compensationType == 'None'
                                                                              ? Colors.black
                                                                              : (selectedEarningType.isEmpty ? (_openAgentEarningDropdownIndex == index ? Colors.black : const Color.fromARGB(191, 173, 173, 173)) : Colors.black),
                                                                        ),
                                                                        textAlign:
                                                                            TextAlign.left,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        softWrap:
                                                                            false,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  if (compensationType
                                                                          .isNotEmpty &&
                                                                      compensationType !=
                                                                          'None') ...[
                                                                    const SizedBox(
                                                                        width:
                                                                            4),
                                                                    Center(
                                                                      child: SvgPicture
                                                                          .asset(
                                                                        'assets/images/Drrrop_down.svg',
                                                                        width:
                                                                            14,
                                                                        height:
                                                                            7,
                                                                        fit: BoxFit
                                                                            .contain,
                                                                        colorFilter: ColorFilter.mode(
                                                                            (compensationType.isNotEmpty && compensationType != 'None' && selectedEarningType.isEmpty)
                                                                                ? Colors.red
                                                                                : Colors.black,
                                                                            BlendMode.srcIn),
                                                                        placeholderBuilder:
                                                                            (context) =>
                                                                                const SizedBox(
                                                                          width:
                                                                              14,
                                                                          height:
                                                                              7,
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
                                                    if (isPercentageBonus &&
                                                        hasEarningType)
                                                      const SizedBox(width: 8),
                                                    if (isPercentageBonus &&
                                                        hasEarningType)
                                                      Container(
                                                        constraints:
                                                            const BoxConstraints(
                                                                minHeight: 38),
                                                        alignment:
                                                            Alignment.center,
                                                        child: SvgPicture.asset(
                                                          'assets/images/Drrrop_down.svg',
                                                          width: 14,
                                                          height: 7,
                                                          fit: BoxFit.contain,
                                                          placeholderBuilder:
                                                              (context) =>
                                                                  const SizedBox(
                                                            width: 14,
                                                            height: 7,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                );
                                                if (isPercentageBonus &&
                                                    hasEarningType) {
                                                  return row;
                                                }
                                                if (compensationType.isEmpty ||
                                                    compensationType ==
                                                        'None') {
                                                  return row;
                                                }
                                                return GestureDetector(
                                                  onTap: () {
                                                    _showAgentEarningTypeDropdown(
                                                        context,
                                                        index,
                                                        earningTypeKey);
                                                  },
                                                  child: row,
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
                                    const SizedBox(
                                      width: 120,
                                      height: 47,
                                    ),
                                    ...List.generate(agents.length, (index) {
                                      final isLast = index == agents.length - 1;
                                      return Container(
                                        width: 120,
                                        height: index == 0 ? 49 : 48,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            top: index == 0
                                                ? const BorderSide(
                                                    color: Colors.black,
                                                    width: 1.0)
                                                : BorderSide.none,
                                            right: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            bottom: const BorderSide(
                                                color: Colors.black,
                                                width: 1.0),
                                            left: BorderSide.none,
                                          ),
                                          borderRadius: index == 0 &&
                                                  agents.length == 1
                                              ? const BorderRadius.only(
                                                  topRight: Radius.circular(8),
                                                  bottomRight:
                                                      Radius.circular(8),
                                                )
                                              : (index == 0
                                                  ? const BorderRadius.only(
                                                      topRight:
                                                          Radius.circular(8),
                                                    )
                                                  : (isLast
                                                      ? const BorderRadius.only(
                                                          bottomRight:
                                                              Radius.circular(
                                                                  8),
                                                        )
                                                      : null)),
                                        ),
                                        child: Center(
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                try {
                                                  // Save old data before removal
                                                  Map<int,
                                                          TextEditingController>
                                                      oldControllers = Map<int,
                                                              TextEditingController>.from(
                                                          _agentNameControllers);
                                                  Map<int, String>
                                                      oldCompensation =
                                                      Map<int, String>.from(
                                                          _agentCompensation);
                                                  Map<int, String>
                                                      oldEarningType =
                                                      Map<int, String>.from(
                                                          _agentEarningType);

                                                  // Dispose the controller for the row being removed
                                                  _agentNameControllers[index]
                                                      ?.dispose();

                                                  // Remove the agent
                                                  _agents.removeAt(index);

                                                  // Clear and rebuild controllers with correct indices
                                                  _agentNameControllers.clear();
                                                  for (var focusNode
                                                      in _agentNameFocusNodes
                                                          .values) {
                                                    focusNode.dispose();
                                                  }
                                                  _agentNameFocusNodes.clear();
                                                  _agentCompensation.clear();
                                                  _agentEarningType.clear();

                                                  // Reindex: keep indices before removed index, shift indices after removed index
                                                  for (int i = 0;
                                                      i < _agents.length;
                                                      i++) {
                                                    if (i < index) {
                                                      // Keep indices before removed index as they are
                                                      if (oldControllers
                                                          .containsKey(i)) {
                                                        _agentNameControllers[
                                                                i] =
                                                            oldControllers[i]!;
                                                      }
                                                      if (oldCompensation
                                                          .containsKey(i)) {
                                                        _agentCompensation[i] =
                                                            oldCompensation[i]!;
                                                      }
                                                      if (oldEarningType
                                                          .containsKey(i)) {
                                                        _agentEarningType[i] =
                                                            oldEarningType[i]!;
                                                      }
                                                    } else {
                                                      // Shift indices after removed index down by 1
                                                      if (oldControllers
                                                          .containsKey(i + 1)) {
                                                        _agentNameControllers[
                                                                i] =
                                                            oldControllers[
                                                                i + 1]!;
                                                      }
                                                      if (oldCompensation
                                                          .containsKey(i + 1)) {
                                                        _agentCompensation[i] =
                                                            oldCompensation[
                                                                i + 1]!;
                                                      }
                                                      if (oldEarningType
                                                          .containsKey(i + 1)) {
                                                        _agentEarningType[i] =
                                                            oldEarningType[
                                                                i + 1]!;
                                                      }
                                                    }
                                                  }
                                                } catch (e) {
                                                  // Fallback: just remove the agent if reindexing fails
                                                  if (index < _agents.length) {
                                                    _agentNameControllers[index]
                                                        ?.dispose();
                                                    _agentNameControllers
                                                        .remove(index);
                                                    _agentCompensation
                                                        .remove(index);
                                                    _agentEarningType
                                                        .remove(index);
                                                    _agents.removeAt(index);
                                                  }
                                                }
                                              });
                                              _onDataChanged();
                                            },
                                            child: Container(
                                              height: 36,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.25),
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
                                                    fontWeight:
                                                        FontWeight.normal,
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
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAgentCompensationDropdown(
      BuildContext context, int index, GlobalKey cellKey) {
    if (_openAgentCompensationDropdownIndex == index &&
        _currentAgentCompensationDropdownEntry != null) {
      _currentAgentCompensationDropdownEntry?.remove();
      _currentAgentCompensationBackdropEntry?.remove();
      _setStateSafe(() {
        _openAgentCompensationDropdownIndex = null;
        _currentAgentCompensationDropdownEntry = null;
        _currentAgentCompensationBackdropEntry = null;
      });
      return;
    }
    _currentProjectManagerCompensationDropdownEntry?.remove();
    _currentProjectManagerCompensationBackdropEntry?.remove();
    _setStateSafe(() {
      _openProjectManagerCompensationDropdownIndex = null;
      _currentProjectManagerCompensationDropdownEntry = null;
      _currentProjectManagerCompensationBackdropEntry = null;
    });
    _currentProjectManagerEarningDropdownEntry?.remove();
    _currentProjectManagerEarningBackdropEntry?.remove();
    _setStateSafe(() {
      _openProjectManagerEarningDropdownIndex = null;
      _currentProjectManagerEarningDropdownEntry = null;
      _currentProjectManagerEarningBackdropEntry = null;
    });
    _currentAgentEarningDropdownEntry?.remove();
    _currentAgentEarningBackdropEntry?.remove();
    _setStateSafe(() {
      _openAgentEarningDropdownIndex = null;
      _currentAgentEarningDropdownEntry = null;
      _currentAgentEarningBackdropEntry = null;
    });

    final RenderBox? renderBox =
        cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    _showAgentCompensationDropdownOverlay(context, index, cellKey);
  }

  void _showAgentCompensationDropdownOverlay(
      BuildContext context, int index, GlobalKey cellKey) {
    final RenderBox? renderBox =
        cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;

    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
      _setStateSafe(() {
        _openAgentCompensationDropdownIndex = null;
        _currentAgentCompensationDropdownEntry = null;
        _currentAgentCompensationBackdropEntry = null;
      });
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
        // Show header only after a value has already been selected for this row/column.
        // First open (empty value) keeps the menu body only, like expense category.
        //
        // Compensation is considered selected when non-empty and not "None".
        //
        //
        //
        left: offset.dx,
        top: offset.dy + renderBox.size.height + 8,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 270,
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
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (((_agentCompensation[index] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) &&
                        (_agentCompensation[index] ?? '') != 'None')
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
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
                                overflow: TextOverflow.visible,
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
                          ..._agentCompensationTypes
                              .asMap()
                              .entries
                              .map((entry) {
                            final typeIndex = entry.key;
                            final type = entry.value;
                            final displayType = type == 'Per Sqft Fee'
                                ? AreaUnitUtils.perAreaFeeLabel(_isSqm)
                                : type;
                            final isLast =
                                typeIndex == _agentCompensationTypes.length - 1;
                            final currentCompensation =
                                _agentCompensation[index] ?? '';
                            final isSelected = type == currentCompensation;
                            final labelToShow = displayType;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  try {
                                    _agentCompensation[index] = type;
                                    _agents[index]['compensation'] = type;
                                    if (type == 'Fixed Fee') {
                                      if (_agentFixedFee[index] == null ||
                                          _agentFixedFee[index]!.isEmpty) {
                                        _agentFixedFee[index] = '0';
                                        _agents[index]['fixedFee'] = '0';
                                      }
                                      if (_agentFixedFeeControllers[index] ==
                                          null) {
                                        _agentFixedFeeControllers[index] =
                                            TextEditingController();
                                      }
                                    }
                                    if (type == 'Monthly Fee') {
                                      if (_agentMonthlyFee[index] == null ||
                                          _agentMonthlyFee[index]!.isEmpty) {
                                        _agentMonthlyFee[index] = '0';
                                        _agents[index]['monthlyFee'] = '0';
                                      }
                                      if (_agentMonths[index] == null ||
                                          _agentMonths[index]!.isEmpty) {
                                        _agentMonths[index] = '';
                                        _agents[index]['months'] = '';
                                      }
                                      if (_agentMonthlyFeeControllers[index] ==
                                          null) {
                                        _agentMonthlyFeeControllers[index] =
                                            TextEditingController();
                                      }
                                      if (_agentMonthsControllers[index] ==
                                          null) {
                                        final currentMonthsValue =
                                            _agentMonths[index] ?? '';
                                        _agentMonthsControllers[index] =
                                            TextEditingController(
                                          text: currentMonthsValue,
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    _agents[index]['compensation'] = type;
                                    if (type == 'Fixed Fee') {
                                      _agentFixedFee[index] = '0';
                                      _agents[index]['fixedFee'] = '0';
                                      if (_agentFixedFeeControllers[index] ==
                                          null) {
                                        _agentFixedFeeControllers[index] =
                                            TextEditingController(text: '');
                                      }
                                    }
                                    if (type == 'Monthly Fee') {
                                      _agentMonthlyFee[index] = '0';
                                      _agents[index]['monthlyFee'] = '0';
                                      _agentMonths[index] = '';
                                      _agents[index]['months'] = '';
                                      if (_agentMonthlyFeeControllers[index] ==
                                          null) {
                                        _agentMonthlyFeeControllers[index] =
                                            TextEditingController(text: '');
                                      }
                                      if (_agentMonthsControllers[index] ==
                                          null) {
                                        _agentMonthsControllers[index] =
                                            TextEditingController(text: '');
                                      }
                                    }
                                    if (type == 'Per Sqft Fee') {
                                      if (_agentPerSqftFee[index] == null ||
                                          _agentPerSqftFee[index]!.isEmpty) {
                                        _agentPerSqftFee[index] = '0';
                                        _agents[index]['perSqftFee'] = '0';
                                      }
                                      if (_agentPerSqftFeeControllers[index] ==
                                          null) {
                                        _agentPerSqftFeeControllers[index] =
                                            TextEditingController();
                                      }
                                    }
                                  } catch (e) {
                                    _agents[index]['compensation'] = type;
                                    if (type == 'Fixed Fee') {
                                      _agentFixedFee[index] = '0';
                                      _agents[index]['fixedFee'] = '0';
                                      if (_agentFixedFeeControllers[index] ==
                                          null) {
                                        _agentFixedFeeControllers[index] =
                                            TextEditingController(text: '');
                                      }
                                    }
                                    if (type == 'Monthly Fee') {
                                      _agentMonthlyFee[index] = '0';
                                      _agents[index]['monthlyFee'] = '0';
                                      _agentMonths[index] = '';
                                      _agents[index]['months'] = '';
                                      if (_agentMonthlyFeeControllers[index] ==
                                          null) {
                                        _agentMonthlyFeeControllers[index] =
                                            TextEditingController();
                                      }
                                      if (_agentMonthsControllers[index] ==
                                          null) {
                                        _agentMonthsControllers[index] =
                                            TextEditingController(text: '');
                                      }
                                    }
                                    if (type == 'Per Sqft Fee') {
                                      _agentPerSqftFee[index] = '0';
                                      _agents[index]['perSqftFee'] = '0';
                                      if (_agentPerSqftFeeControllers[index] ==
                                          null) {
                                        _agentPerSqftFeeControllers[index] =
                                            TextEditingController();
                                      }
                                    }
                                  }
                                });
                                _onDataChanged();
                                closeDropdown();
                              },
                              child: Padding(
                                padding:
                                    EdgeInsets.only(bottom: isLast ? 0 : 16),
                                child: IntrinsicWidth(
                                  child: Container(
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFD8EDFB)
                                          : const Color(0xFFF5FAFE),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: isSelected
                                          ? const [
                                              BoxShadow(
                                                color: Color(0xFF0C8CE9),
                                                blurRadius: 2,
                                                offset: Offset(0, 0),
                                                spreadRadius: 0,
                                              ),
                                            ]
                                          : [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.25),
                                                blurRadius: 2,
                                                offset: const Offset(0, 0),
                                                spreadRadius: 0,
                                              ),
                                            ],
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        labelToShow,
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
      ),
    );

    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
    _setStateSafe(() {
      _openAgentCompensationDropdownIndex = index;
      _currentAgentCompensationBackdropEntry = backdropEntry;
      _currentAgentCompensationDropdownEntry = overlayEntry;
    });
  }

  void _showCompensationDropdown(
      BuildContext context, int index, GlobalKey cellKey) {
    if (_openProjectManagerCompensationDropdownIndex == index &&
        _currentProjectManagerCompensationDropdownEntry != null) {
      _currentProjectManagerCompensationDropdownEntry?.remove();
      _currentProjectManagerCompensationBackdropEntry?.remove();
      _setStateSafe(() {
        _openProjectManagerCompensationDropdownIndex = null;
        _currentProjectManagerCompensationDropdownEntry = null;
        _currentProjectManagerCompensationBackdropEntry = null;
      });
      return;
    }
    _currentProjectManagerEarningDropdownEntry?.remove();
    _currentProjectManagerEarningBackdropEntry?.remove();
    _setStateSafe(() {
      _openProjectManagerEarningDropdownIndex = null;
      _currentProjectManagerEarningDropdownEntry = null;
      _currentProjectManagerEarningBackdropEntry = null;
    });
    _currentAgentCompensationDropdownEntry?.remove();
    _currentAgentCompensationBackdropEntry?.remove();
    _setStateSafe(() {
      _openAgentCompensationDropdownIndex = null;
      _currentAgentCompensationDropdownEntry = null;
      _currentAgentCompensationBackdropEntry = null;
    });
    _currentAgentEarningDropdownEntry?.remove();
    _currentAgentEarningBackdropEntry?.remove();
    _setStateSafe(() {
      _openAgentEarningDropdownIndex = null;
      _currentAgentEarningDropdownEntry = null;
      _currentAgentEarningBackdropEntry = null;
    });

    final RenderBox? renderBox =
        cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;

    // Function to show the dropdown
    void showDropdown() {
      // Recalculate position after potential scroll
      final RenderBox? updatedRenderBox =
          cellKey.currentContext?.findRenderObject() as RenderBox?;
      if (updatedRenderBox == null) return;
      final updatedOffset =
          updatedRenderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
      final finalDropdownTop =
          updatedOffset.dy + updatedRenderBox.size.height + 8;

      OverlayEntry? backdropEntry;
      OverlayEntry? overlayEntry;

      void closeDropdown() {
        overlayEntry?.remove();
        backdropEntry?.remove();
        _setStateSafe(() {
          _openProjectManagerCompensationDropdownIndex = null;
          _currentProjectManagerCompensationDropdownEntry = null;
          _currentProjectManagerCompensationBackdropEntry = null;
        });
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
          left: updatedOffset.dx,
          top: finalDropdownTop,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 270,
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
              child: ClipRect(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header section
                      if (((_projectManagerCompensation[index] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty) &&
                          (_projectManagerCompensation[index] ?? '') != 'None')
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Select the Compensation Type',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.visible,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 14,
                                height: 7,
                                child: Transform.rotate(
                                  angle: 180 *
                                      3.14159 /
                                      180, // Rotate 180 degrees (upward arrow)
                                  child: SvgPicture.asset(
                                    'assets/images/Drrrop_down.svg',
                                    width: 14,
                                    height: 7,
                                    fit: BoxFit.contain,
                                    placeholderBuilder: (context) =>
                                        const SizedBox(
                                      width: 14,
                                      height: 7,
                                    ),
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
                              final isLast =
                                  typeIndex == _compensationTypes.length - 1;
                              final currentCompensation =
                                  _projectManagerCompensation[index] ?? '';
                              final isSelected = type == currentCompensation;
                              return Padding(
                                padding:
                                    EdgeInsets.only(bottom: isLast ? 0 : 16),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      try {
                                        _projectManagerCompensation[index] =
                                            type;
                                        _projectManagers[index]
                                            ['compensation'] = type;
                                        // Initialize Fixed Fee amount if Fixed Fee is selected
                                        if (type == 'Fixed Fee') {
                                          if (_projectManagerFixedFee[index] ==
                                                  null ||
                                              _projectManagerFixedFee[index]!
                                                  .isEmpty) {
                                            _projectManagerFixedFee[index] =
                                                '0';
                                            _projectManagers[index]
                                                ['fixedFee'] = '0';
                                          }
                                          // Initialize controller if it doesn't exist
                                          if (_projectManagerFixedFeeControllers[
                                                  index] ==
                                              null) {
                                            _projectManagerFixedFeeControllers[
                                                    index] =
                                                TextEditingController();
                                          }
                                        }
                                        // Initialize Monthly Fee amount if Monthly Fee is selected
                                        if (type == 'Monthly Fee') {
                                          if (_projectManagerMonthlyFee[
                                                      index] ==
                                                  null ||
                                              _projectManagerMonthlyFee[index]!
                                                  .isEmpty) {
                                            _projectManagerMonthlyFee[index] =
                                                '0';
                                            _projectManagers[index]
                                                ['monthlyFee'] = '0';
                                          }
                                          if (_projectManagerMonths[index] ==
                                                  null ||
                                              _projectManagerMonths[index]!
                                                  .isEmpty) {
                                            _projectManagerMonths[index] = '';
                                            _projectManagers[index]['months'] =
                                                '';
                                          }
                                          // Initialize controllers if they don't exist
                                          if (_projectManagerMonthlyFeeControllers[
                                                  index] ==
                                              null) {
                                            _projectManagerMonthlyFeeControllers[
                                                    index] =
                                                TextEditingController();
                                          }
                                          if (_projectManagerMonthsControllers[
                                                  index] ==
                                              null) {
                                            final currentMonthsValue =
                                                _projectManagerMonths[index] ??
                                                    '';
                                            _projectManagerMonthsControllers[
                                                index] = TextEditingController(
                                              text: currentMonthsValue,
                                            );
                                          }
                                        }
                                      } catch (e) {
                                        // If map is null, just update _projectManagers
                                        _projectManagers[index]
                                            ['compensation'] = type;
                                        if (type == 'Fixed Fee') {
                                          _projectManagerFixedFee[index] = '0';
                                          _projectManagers[index]['fixedFee'] =
                                              '0';
                                          // Initialize controller if it doesn't exist
                                          if (_projectManagerFixedFeeControllers[
                                                  index] ==
                                              null) {
                                            _projectManagerFixedFeeControllers[
                                                    index] =
                                                TextEditingController();
                                          }
                                        }
                                        if (type == 'Monthly Fee') {
                                          _projectManagerMonthlyFee[index] =
                                              '0';
                                          _projectManagers[index]
                                              ['monthlyFee'] = '0';
                                          _projectManagerMonths[index] = '';
                                          _projectManagers[index]['months'] =
                                              '';
                                          // Initialize controllers if they don't exist
                                          if (_projectManagerMonthlyFeeControllers[
                                                  index] ==
                                              null) {
                                            _projectManagerMonthlyFeeControllers[
                                                    index] =
                                                TextEditingController();
                                          }
                                          if (_projectManagerMonthsControllers[
                                                  index] ==
                                              null) {
                                            _projectManagerMonthsControllers[
                                                    index] =
                                                TextEditingController(text: '');
                                          }
                                        }
                                      }
                                    });
                                    _onDataChanged();
                                    closeDropdown();
                                  },
                                  child: IntrinsicWidth(
                                    child: Container(
                                      height: 36,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFFD8EDFB)
                                            : const Color(0xFFF5FAFE),
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: isSelected
                                            ? const [
                                                BoxShadow(
                                                  color: Color(0xFF0C8CE9),
                                                  blurRadius: 2,
                                                  offset: Offset(0, 0),
                                                  spreadRadius: 0,
                                                ),
                                              ]
                                            : [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.25),
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 0),
                                                  spreadRadius: 0,
                                                ),
                                              ],
                                      ),
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
                                  Future.delayed(
                                      const Duration(milliseconds: 100), () {
                                    _showBlockSelectionDropdown(
                                        context, index, cellKey);
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
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
        ),
      );

      overlay.insert(backdropEntry);
      overlay.insert(overlayEntry);
      _setStateSafe(() {
        _openProjectManagerCompensationDropdownIndex = index;
        _currentProjectManagerCompensationBackdropEntry = backdropEntry;
        _currentProjectManagerCompensationDropdownEntry = overlayEntry;
      });
    }

    showDropdown();
  }

  void _showAgentEarningTypeDropdown(
      BuildContext context, int index, GlobalKey cellKey) {
    if (_openAgentEarningDropdownIndex == index &&
        _currentAgentEarningDropdownEntry != null) {
      _currentAgentEarningDropdownEntry?.remove();
      _currentAgentEarningBackdropEntry?.remove();
      _setStateSafe(() {
        _openAgentEarningDropdownIndex = null;
        _currentAgentEarningDropdownEntry = null;
        _currentAgentEarningBackdropEntry = null;
      });
      return;
    }
    _currentProjectManagerCompensationDropdownEntry?.remove();
    _currentProjectManagerCompensationBackdropEntry?.remove();
    _setStateSafe(() {
      _openProjectManagerCompensationDropdownIndex = null;
      _currentProjectManagerCompensationDropdownEntry = null;
      _currentProjectManagerCompensationBackdropEntry = null;
    });
    _currentProjectManagerEarningDropdownEntry?.remove();
    _currentProjectManagerEarningBackdropEntry?.remove();
    _setStateSafe(() {
      _openProjectManagerEarningDropdownIndex = null;
      _currentProjectManagerEarningDropdownEntry = null;
      _currentProjectManagerEarningBackdropEntry = null;
    });
    _currentAgentCompensationDropdownEntry?.remove();
    _currentAgentCompensationBackdropEntry?.remove();
    _setStateSafe(() {
      _openAgentCompensationDropdownIndex = null;
      _currentAgentCompensationDropdownEntry = null;
      _currentAgentCompensationBackdropEntry = null;
    });

    final RenderBox? renderBox =
        cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    _showAgentEarningTypeDropdownOverlay(context, index, cellKey);
  }

  void _showAgentEarningTypeDropdownOverlay(
      BuildContext context, int index, GlobalKey cellKey) {
    final RenderBox? renderBox =
        cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;

    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
      _setStateSafe(() {
        _openAgentEarningDropdownIndex = null;
        _currentAgentEarningDropdownEntry = null;
        _currentAgentEarningBackdropEntry = null;
      });
    }

    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeDropdown,
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    final compensationType = _agentCompensation[index] ?? '';
    final isPercentageBonus = compensationType == 'Percentage Bonus';
    final isFixedFee = compensationType == 'Fixed Fee';
    final earningTypesToShow =
        isPercentageBonus ? _percentageBonusEarningTypes : _earningTypes;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: offset.dx,
          top: offset.dy + renderBox.size.height + 8,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 349,
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
                          if ((_agentEarningType[index] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            Container(
                              padding: const EdgeInsets.only(
                                  top: 4, left: 8, right: 8, bottom: 0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Select the Earning Type',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                  Transform.rotate(
                                    angle: 180 * 3.14159 / 180,
                                    child: SvgPicture.asset(
                                      'assets/images/Drrrop_down.svg',
                                      width: 14,
                                      height: 7,
                                      fit: BoxFit.contain,
                                      placeholderBuilder: (context) =>
                                          const SizedBox(
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
                                ...earningTypesToShow
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                  final typeIndex = entry.key;
                                  final type = entry.value;
                                  final isLast = typeIndex ==
                                      earningTypesToShow.length - 1;
                                  final currentEarningType =
                                      _agentEarningType[index] ?? '';
                                  final isSelected = type == currentEarningType;
                                  return Padding(
                                    padding:
                                        EdgeInsets.only(bottom: isLast ? 0 : 8),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          try {
                                            _agentEarningType[index] = type;
                                            _agents[index]['earningType'] =
                                                type;
                                            if (isPercentageBonus &&
                                                (_agentPercentage[index] ==
                                                        null ||
                                                    _agentPercentage[index]!
                                                        .isEmpty)) {
                                              _agentPercentage[index] = '0';
                                              _agents[index]['percentage'] =
                                                  '0';
                                            }
                                            if (isFixedFee &&
                                                (_agentFixedFee[index] ==
                                                        null ||
                                                    _agentFixedFee[index]!
                                                        .isEmpty)) {
                                              _agentFixedFee[index] = '0';
                                              _agents[index]['fixedFee'] = '0';
                                            }
                                          } catch (e) {
                                            _agents[index]['earningType'] =
                                                type;
                                            if (isPercentageBonus) {
                                              _agentPercentage[index] = '0';
                                              _agents[index]['percentage'] =
                                                  '0';
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
                                      child: IntrinsicWidth(
                                        child: Container(
                                          height: 36,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFFD8EDFB)
                                                : const Color(0xFFF5FAFE),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            boxShadow: isSelected
                                                ? const [
                                                    BoxShadow(
                                                      color: Color(0xFF0C8CE9),
                                                      blurRadius: 2,
                                                      offset: Offset(0, 0),
                                                      spreadRadius: 0,
                                                    ),
                                                  ]
                                                : [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.25),
                                                      blurRadius: 2,
                                                      offset:
                                                          const Offset(0, 0),
                                                      spreadRadius: 0,
                                                    ),
                                                  ],
                                          ),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              type,
                                              style: GoogleFonts.inter(
                                                fontSize: 16,
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
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((_agentEarningType[index] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            Container(
                              padding: const EdgeInsets.only(
                                  top: 4, left: 8, right: 8, bottom: 0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Select the Earning Type',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                  Transform.rotate(
                                    angle: 180 * 3.14159 / 180,
                                    child: SvgPicture.asset(
                                      'assets/images/Drrrop_down.svg',
                                      width: 14,
                                      height: 7,
                                      fit: BoxFit.contain,
                                      placeholderBuilder: (context) =>
                                          const SizedBox(
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
                              children: _earningTypes.map((type) {
                                final currentEarningType =
                                    _agentEarningType[index] ?? '';
                                final isSelected = type == currentEarningType;
                                final isLast = type == _earningTypes.last;
                                return Padding(
                                  padding:
                                      EdgeInsets.only(bottom: isLast ? 0 : 8),
                                  child: GestureDetector(
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
                                        height: 36,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFFD8EDFB)
                                              : const Color(0xFFF5FAFE),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          boxShadow: isSelected
                                              ? const [
                                                  BoxShadow(
                                                    color: Color(0xFF0C8CE9),
                                                    blurRadius: 2,
                                                    offset: Offset(0, 0),
                                                    spreadRadius: 0,
                                                  ),
                                                ]
                                              : [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.25),
                                                    blurRadius: 2,
                                                    offset: const Offset(0, 0),
                                                    spreadRadius: 0,
                                                  ),
                                                ],
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            type,
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
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
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );

    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);
    _setStateSafe(() {
      _openAgentEarningDropdownIndex = index;
      _currentAgentEarningBackdropEntry = backdropEntry;
      _currentAgentEarningDropdownEntry = overlayEntry;
    });
  }

  void _showEarningTypeDropdown(
      BuildContext context, int index, GlobalKey cellKey) {
    if (_openProjectManagerEarningDropdownIndex == index &&
        _currentProjectManagerEarningDropdownEntry != null) {
      _currentProjectManagerEarningDropdownEntry?.remove();
      _currentProjectManagerEarningBackdropEntry?.remove();
      _setStateSafe(() {
        _openProjectManagerEarningDropdownIndex = null;
        _currentProjectManagerEarningDropdownEntry = null;
        _currentProjectManagerEarningBackdropEntry = null;
      });
      return;
    }
    _currentProjectManagerCompensationDropdownEntry?.remove();
    _currentProjectManagerCompensationBackdropEntry?.remove();
    _setStateSafe(() {
      _openProjectManagerCompensationDropdownIndex = null;
      _currentProjectManagerCompensationDropdownEntry = null;
      _currentProjectManagerCompensationBackdropEntry = null;
    });
    _currentAgentCompensationDropdownEntry?.remove();
    _currentAgentCompensationBackdropEntry?.remove();
    _setStateSafe(() {
      _openAgentCompensationDropdownIndex = null;
      _currentAgentCompensationDropdownEntry = null;
      _currentAgentCompensationBackdropEntry = null;
    });
    _currentAgentEarningDropdownEntry?.remove();
    _currentAgentEarningBackdropEntry?.remove();
    _setStateSafe(() {
      _openAgentEarningDropdownIndex = null;
      _currentAgentEarningDropdownEntry = null;
      _currentAgentEarningBackdropEntry = null;
    });

    final RenderBox? renderBox =
        cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

    // Function to show the dropdown
    void showDropdown() {
      // Recalculate position after potential scroll
      final RenderBox? updatedRenderBox =
          cellKey.currentContext?.findRenderObject() as RenderBox?;
      if (updatedRenderBox == null) return;
      final updatedOffset =
          updatedRenderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
      final finalDropdownTop =
          updatedOffset.dy + updatedRenderBox.size.height + 8;

      OverlayEntry? backdropEntry;
      OverlayEntry? overlayEntry;

      void closeDropdown() {
        overlayEntry?.remove();
        backdropEntry?.remove();
        _setStateSafe(() {
          _openProjectManagerEarningDropdownIndex = null;
          _currentProjectManagerEarningDropdownEntry = null;
          _currentProjectManagerEarningBackdropEntry = null;
        });
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
          final earningTypesToShow =
              isPercentageBonus ? _percentageBonusEarningTypes : _earningTypes;

          return Positioned(
            left: updatedOffset.dx,
            top: finalDropdownTop,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 349,
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
                            if ((_projectManagerEarningType[index] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty)
                              Container(
                                padding: const EdgeInsets.only(
                                    top: 4, left: 8, right: 8, bottom: 0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Select the Earning Type',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          color: Colors.black,
                                        ),
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                    Transform.rotate(
                                      angle: 180 * 3.14159 / 180,
                                      child: SvgPicture.asset(
                                        'assets/images/Drrrop_down.svg',
                                        width: 14,
                                        height: 7,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) =>
                                            const SizedBox(
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
                                  ...earningTypesToShow
                                      .asMap()
                                      .entries
                                      .map((entry) {
                                    final typeIndex = entry.key;
                                    final type = entry.value;
                                    final isLast = typeIndex ==
                                        earningTypesToShow.length - 1;
                                    final currentEarningType =
                                        _projectManagerEarningType[index] ?? '';
                                    final isSelected =
                                        type == currentEarningType;
                                    return Padding(
                                      padding: EdgeInsets.only(
                                          bottom: isLast ? 0 : 8),
                                      child: GestureDetector(
                                        onTap: () {
                                          // If "Per Plot" is selected, show block selection
                                          if (type == 'Per Plot' &&
                                              !isPercentageBonus) {
                                            closeDropdown();
                                            Future.delayed(
                                                const Duration(
                                                    milliseconds: 100), () {
                                              _showBlockSelectionDropdown(
                                                  context, index, cellKey);
                                            });
                                            return;
                                          }
                                          setState(() {
                                            try {
                                              _projectManagerEarningType[
                                                  index] = type;
                                              _projectManagers[index]
                                                  ['earningType'] = type;
                                              // Initialize percentage value if it doesn't exist for percentage bonus types
                                              if (isPercentageBonus &&
                                                  (_projectManagerPercentage[
                                                              index] ==
                                                          null ||
                                                      _projectManagerPercentage[
                                                              index]!
                                                          .isEmpty)) {
                                                _projectManagerPercentage[
                                                    index] = '0';
                                                _projectManagers[index]
                                                    ['percentage'] = '0';
                                              }
                                              // Initialize Fixed Fee amount if it doesn't exist for Fixed Fee types
                                              if (isFixedFee &&
                                                  (_projectManagerFixedFee[
                                                              index] ==
                                                          null ||
                                                      _projectManagerFixedFee[
                                                              index]!
                                                          .isEmpty)) {
                                                _projectManagerFixedFee[index] =
                                                    '0';
                                                _projectManagers[index]
                                                    ['fixedFee'] = '0';
                                              }
                                            } catch (e) {
                                              // If map is null, just update _projectManagers
                                              _projectManagers[index]
                                                  ['earningType'] = type;
                                              if (isPercentageBonus) {
                                                _projectManagerPercentage[
                                                    index] = '0';
                                                _projectManagers[index]
                                                    ['percentage'] = '0';
                                              }
                                              if (isFixedFee) {
                                                _projectManagerFixedFee[index] =
                                                    '0';
                                                _projectManagers[index]
                                                    ['fixedFee'] = '0';
                                              }
                                            }
                                          });
                                          _onDataChanged();
                                          closeDropdown();
                                        },
                                        child: IntrinsicWidth(
                                          child: Container(
                                            height: 36,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? const Color(0xFFD8EDFB)
                                                  : const Color(0xFFF5FAFE),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              boxShadow: isSelected
                                                  ? const [
                                                      BoxShadow(
                                                        color:
                                                            Color(0xFF0C8CE9),
                                                        blurRadius: 2,
                                                        offset: Offset(0, 0),
                                                        spreadRadius: 0,
                                                      ),
                                                    ]
                                                  : [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.25),
                                                        blurRadius: 2,
                                                        offset:
                                                            const Offset(0, 0),
                                                        spreadRadius: 0,
                                                      ),
                                                    ],
                                            ),
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
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((_projectManagerEarningType[index] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty)
                              Container(
                                padding: const EdgeInsets.only(
                                    top: 4, left: 8, right: 8, bottom: 0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Select the Earning Type',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          color: Colors.black,
                                        ),
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                    Transform.rotate(
                                      angle: 180 * 3.14159 / 180,
                                      child: SvgPicture.asset(
                                        'assets/images/Drrrop_down.svg',
                                        width: 14,
                                        height: 7,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) =>
                                            const SizedBox(
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
                                children: _earningTypes.map((type) {
                                  final currentEarningType =
                                      _projectManagerEarningType[index] ?? '';
                                  final isSelected = type == currentEarningType;
                                  final isLast = type == _earningTypes.last;
                                  return Padding(
                                    padding:
                                        EdgeInsets.only(bottom: isLast ? 0 : 8),
                                    child: GestureDetector(
                                      onTap: () {
                                        if (type == 'Per Plot') {
                                          closeDropdown();
                                          Future.delayed(
                                              const Duration(milliseconds: 100),
                                              () {
                                            _showBlockSelectionDropdown(
                                                context, index, cellKey);
                                          });
                                          return;
                                        }
                                        setState(() {
                                          try {
                                            _projectManagerEarningType[index] =
                                                type;
                                            _projectManagers[index]
                                                ['earningType'] = type;
                                          } catch (e) {
                                            _projectManagers[index]
                                                ['earningType'] = type;
                                          }
                                        });
                                        _onDataChanged();
                                        closeDropdown();
                                      },
                                      child: IntrinsicWidth(
                                        child: Container(
                                          height: 36,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFFD8EDFB)
                                                : const Color(0xFFF5FAFE),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            boxShadow: isSelected
                                                ? const [
                                                    BoxShadow(
                                                      color: Color(0xFF0C8CE9),
                                                      blurRadius: 2,
                                                      offset: Offset(0, 0),
                                                      spreadRadius: 0,
                                                    ),
                                                  ]
                                                : [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.25),
                                                      blurRadius: 2,
                                                      offset:
                                                          const Offset(0, 0),
                                                      spreadRadius: 0,
                                                    ),
                                                  ],
                                          ),
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
                                            ),
                                          ),
                                        ),
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
          );
        },
      );

      overlay.insert(backdropEntry);
      overlay.insert(overlayEntry);
      _setStateSafe(() {
        _openProjectManagerEarningDropdownIndex = index;
        _currentProjectManagerEarningBackdropEntry = backdropEntry;
        _currentProjectManagerEarningDropdownEntry = overlayEntry;
      });
    }

    showDropdown();
  }

  void _showAgentPercentageInputDialog(BuildContext context, int index) {
    String currentValue = '0';
    try {
      currentValue = _agentPercentage[index] ?? '0';
    } catch (e) {
      currentValue = '0';
    }
    final controller =
        TextEditingController(text: currentValue == '0' ? '' : currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Enter Percentage',
          style: GoogleFonts.inter(
            fontSize: 14,
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

  void _showBlockSelectionDropdown(
      BuildContext context, int projectManagerIndex, GlobalKey cellKey) {
    // Get all available blocks/plots from layouts
    List<String> availableBlocks = [];
    for (int layoutIndex = 0; layoutIndex < _layouts.length; layoutIndex++) {
      final layout = _layouts[layoutIndex];
      final plots = layout['plots'] as List<Map<String, dynamic>>? ?? [];
      final layoutName = _layoutNameControllers[layoutIndex]?.text ??
          layout['name'] ??
          'Layout ${layoutIndex + 1}';

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

    final RenderBox? renderBox =
        cellKey.currentContext?.findRenderObject() as RenderBox?;
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
      currentlySelected =
          _projectManagerSelectedBlocks[projectManagerIndex] ?? [];
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
                        bottom: BorderSide(
                            color: Colors.grey.withOpacity(0.3), width: 1),
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
                                  selected = _projectManagerSelectedBlocks[
                                          projectManagerIndex] ??
                                      [];
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
                                _projectManagerSelectedBlocks[
                                    projectManagerIndex] = selected;
                              }
                            });
                            _onDataChanged();
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFECF6FD)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF2196F3)
                                    : Colors.grey.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 20,
                                  color: isSelected
                                      ? const Color(0xFF2196F3)
                                      : Colors.grey,
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
            fontSize: 14,
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
    final controller =
        TextEditingController(text: currentValue == '0' ? '' : currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Enter Fixed Fee Amount',
          style: GoogleFonts.inter(
            fontSize: 14,
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
        TextEditingController(
            text: layout['name'] ?? 'Layout ${layoutIndex + 1}');
    if (_layoutNameControllers[layoutIndex] == null) {
      _layoutNameControllers[layoutIndex] = layoutNameController;
    }

    // Calculate totals for this layout
    double totalArea = 0.0;
    double totalAllInCost = 0.0;
    double totalPlotCost = 0.0;
    // Calculate All-in Cost as Total Expenses / Approved selling area
    final allInCost =
        _approvedSellingArea > 0 ? _totalExpenses / _approvedSellingArea : 0.0;

    int plotCount = 0;
    for (int i = 0; i < plots.length; i++) {
      final areaKey = '${layoutIndex}_$i';
      final areaController = _plotAreaControllers[areaKey];
      if (areaController != null) {
        final area = double.tryParse(
                areaController.text.replaceAll(',', '').replaceAll(' ', '')) ??
            0.0;
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
      clipBehavior: Clip.none,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              _buildFocusAwareInputContainer(
                focusNode: _layoutNameFocusNodes.putIfAbsent(
                    layoutIndex, () => FocusNode()),
                backgroundColor: Colors.white,
                defaultShadowColor:
                    layoutNameController.text.isEmpty ? Colors.red : null,
                width: 304,
                child: Stack(
                  children: [
                    TextField(
                      controller: layoutNameController,
                      textAlign: TextAlign.left,
                      textAlignVertical: TextAlignVertical.center,
                      focusNode: _layoutNameFocusNodes.putIfAbsent(
                          layoutIndex, () => FocusNode()),
                      onChanged: (value) {
                        _layouts[layoutIndex]['name'] = value;
                        setState(() {});
                        _onDataChanged();
                      },
                      decoration: InputDecoration(
                        hintText: '',
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                        isDense: true,
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 14,
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
                                  fontSize: 14,
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
              const Spacer(),
              // Collapse/Expand button at right end with 8px from border
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      final isCollapsed =
                          _collapsedLayouts.contains(layoutIndex);
                      if (isCollapsed) {
                        _collapsedLayouts.remove(layoutIndex);
                      } else {
                        _collapsedLayouts.add(layoutIndex);
                      }
                    });
                  },
                  child: SvgPicture.asset(
                    _collapsedLayouts.contains(layoutIndex)
                        ? 'assets/images/Indi_expand.svg'
                        : 'assets/images/Indi_collapse.svg',
                    width: 12,
                    height: 12,
                    fit: BoxFit.contain,
                    placeholderBuilder: (context) => const SizedBox(
                      width: 12,
                      height: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Summary row: plots count, Total Area, Total Plot Cost
          Row(
            children: [
              // Plots count (no white container)
              Text(
                '${plots.length} plot${plots.length != 1 ? 's' : ''}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              // Dot separator
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              // Total Area
              Row(
                children: [
                  Text(
                    'Total Area: ',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '${_formatAmountForDisplay(totalArea, decimalPlaces: 3)} $_areaUnitSuffix',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: Colors.black.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Dot separator
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              // Total Plot Cost
              Row(
                children: [
                  Text(
                    'Total Plot Cost: ',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '₹ ${_formatAmountForDisplay(totalPlotCost, decimalPlaces: 3)}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: Colors.black.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
              // Three dots menu in same line when collapsed
              if (_collapsedLayouts.contains(layoutIndex)) ...[
                const Spacer(),
                Builder(
                  builder: (context) {
                    return GestureDetector(
                      onTap: () {
                        if (_openLayoutMenuIndex == layoutIndex) {
                          // Close menu if already open
                          _currentLayoutMenuEntry?.remove();
                          _currentLayoutMenuBackdropEntry?.remove();
                          _openLayoutMenuIndex = null;
                          _currentLayoutMenuEntry = null;
                          _currentLayoutMenuBackdropEntry = null;
                        } else {
                          // Close previous menu if any
                          _currentLayoutMenuEntry?.remove();
                          _currentLayoutMenuBackdropEntry?.remove();
                          // Show menu
                          _showLayoutMenu(
                              context,
                              layoutIndex,
                              layoutNameController.text,
                              _layoutMenuAnchorKeyFor(layoutIndex));
                        }
                      },
                      child: Container(
                        key: _layoutMenuAnchorKeyFor(layoutIndex),
                        height: 36,
                        width: 52,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
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
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // First dot
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Second dot
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Third dot
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          // Spacing before table (only when expanded)
          if (!_collapsedLayouts.contains(layoutIndex))
            const SizedBox(height: 16),
          // Plots table wrapped in styled container (conditionally visible)
          if (!_collapsedLayouts.contains(layoutIndex))
            Material(
              color: Colors.transparent,
              elevation: 0,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  left: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
                  right: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
                  top: 8 + (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)),
                  bottom: 8 +
                      (12 * (_tableZoomLevel - 1.0).clamp(0.0, 0.2)) +
                      (50 *
                          (_tableZoomLevel - 1.0).clamp(0.0,
                              0.2)), // Extra bottom padding for scaled content to prevent border clipping
                ), // Add extra padding when zoomed to show borders
                clipBehavior: Clip.none,
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
                    Builder(
                      builder: (context) {
                        // Ensure scroll controller exists for this layout
                        if (!_plotsTableScrollControllers
                            .containsKey(layoutIndex)) {
                          _plotsTableScrollControllers[layoutIndex] =
                              ScrollController();
                        }
                        // Ensure vertical scroll controller exists for this layout
                        if (!_plotsTableVerticalScrollControllers
                            .containsKey(layoutIndex)) {
                          _plotsTableVerticalScrollControllers[layoutIndex] =
                              ScrollController();
                        }

                        // Calculate dynamic height based on number of plots
                        // Header row: 48px, each plot row: ~48px (or more if partners selected)
                        double baseHeaderHeight = 48.0;
                        double baseRowHeight = 48.0;
                        double calculatedHeight =
                            baseHeaderHeight + (plots.length * baseRowHeight);
                        // Add extra height for plots with multiple partners
                        for (int i = 0; i < plots.length; i++) {
                          final key = '${layoutIndex}_$i';
                          final selectedPartners = _plotPartners[key] ?? [];
                          if (selectedPartners.length > 1) {
                            calculatedHeight +=
                                (selectedPartners.length - 1) * 36.0;
                          }
                        }
                        // Store base height (same as when zoom = 1.0)
                        final baseHeight = calculatedHeight;
                        // Calculate scaled height for outer container
                        double scaledHeight =
                            calculatedHeight * _tableZoomLevel;
                        // Only apply minimum height if calculated height is very small (less than header + 1 row)
                        // This prevents extra gap when there's a single row with single member
                        final minHeight = (baseHeaderHeight + baseRowHeight) *
                            _tableZoomLevel;
                        if (scaledHeight < minHeight) {
                          scaledHeight = minHeight;
                        }
                        // Add buffer for scaled border to prevent clipping
                        final borderBuffer = _tableZoomLevel > 1.0 ? 5.0 : 0.0;
                        scaledHeight = scaledHeight + borderBuffer;

                        return SizedBox(
                          width: double.infinity,
                          height: scaledHeight,
                          child: ScrollbarTheme(
                            data: ScrollbarThemeData(
                              thickness: MaterialStateProperty.all(
                                  8.0), // Increased scrollbar thickness
                              radius: const Radius.circular(2.0),
                            ),
                            child: Scrollbar(
                              controller:
                                  _plotsTableScrollControllers[layoutIndex],
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller:
                                    _plotsTableScrollControllers[layoutIndex],
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                clipBehavior: Clip.none,
                                child: IntrinsicWidth(
                                  child: SizedBox(
                                    height:
                                        baseHeight, // Use base height (same as when zoom = 1.0), Transform.scale will handle scaling
                                    child: ScrollbarTheme(
                                      data: ScrollbarThemeData(
                                        thickness: MaterialStateProperty.all(
                                            4.0), // Thinner scrollbar
                                        radius: const Radius.circular(2.0),
                                      ),
                                      child: Scrollbar(
                                        controller:
                                            _plotsTableVerticalScrollControllers[
                                                layoutIndex],
                                        thumbVisibility: true,
                                        child: SingleChildScrollView(
                                          controller:
                                              _plotsTableVerticalScrollControllers[
                                                  layoutIndex],
                                          scrollDirection: Axis.vertical,
                                          physics:
                                              const BouncingScrollPhysics(),
                                          clipBehavior: Clip.none,
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              left: ((_tableZoomLevel - 1.0) *
                                                      10.0)
                                                  .clamp(0.0, 10.0),
                                              right: ((_tableZoomLevel - 1.0) *
                                                          10.0)
                                                      .clamp(0.0, 10.0) +
                                                  ((_tableZoomLevel - 1.0) *
                                                          1350.0)
                                                      .clamp(0.0,
                                                          1350.0), // Extra right padding when zoomed to allow full scrolling to last column
                                              top: ((_tableZoomLevel - 1.0) *
                                                      10.0)
                                                  .clamp(0.0, 10.0),
                                              bottom: ((_tableZoomLevel - 1.0) *
                                                          10.0)
                                                      .clamp(0.0, 10.0) +
                                                  ((_tableZoomLevel - 1.0) *
                                                          100.0)
                                                      .clamp(0.0,
                                                          100.0), // Extra bottom padding for scaled borders to prevent clipping
                                            ),
                                            child: Transform.scale(
                                              scale: _tableZoomLevel,
                                              alignment: Alignment.topLeft,
                                              child: _buildPlotsTable(
                                                  layoutIndex, plots),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    // Add Plot button
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          final newPlotIndex = plots.length;
                          // Create a new list to ensure state update is detected
                          final updatedPlots =
                              List<Map<String, dynamic>>.from(plots);
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
                          _plotPurchaseRateControllers[key] =
                              TextEditingController();
                        });
                        _onDataChanged();
                      },
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Three dots menu aligned to the right (only show when not collapsed)
          if (!_collapsedLayouts.contains(layoutIndex)) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Builder(
                builder: (context) {
                  return GestureDetector(
                    onTap: () {
                      if (_openLayoutMenuIndex == layoutIndex) {
                        // Close menu if already open
                        _currentLayoutMenuEntry?.remove();
                        _currentLayoutMenuBackdropEntry?.remove();
                        _openLayoutMenuIndex = null;
                        _currentLayoutMenuEntry = null;
                        _currentLayoutMenuBackdropEntry = null;
                      } else {
                        // Close previous menu if any
                        _currentLayoutMenuEntry?.remove();
                        _currentLayoutMenuBackdropEntry?.remove();
                        // Show menu
                        _showLayoutMenu(
                            context,
                            layoutIndex,
                            layoutNameController.text,
                            _layoutMenuAnchorKeyFor(layoutIndex));
                      }
                    },
                    child: Container(
                      key: _layoutMenuAnchorKeyFor(layoutIndex),
                      height: 36,
                      width: 52,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // First dot
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Second dot
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Third dot
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black,
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
                      fontSize: 14,
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
                final dynamicHeight =
                    selectedPartners.isEmpty || selectedPartners.length == 1
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
                        fontSize: 14,
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
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Plot Number ',
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
                ),
              ),
              ...List.generate(plots.length, (index) {
                final isLast = index == plots.length - 1;
                final key = '${layoutIndex}_$index';
                final selectedPartners = _plotPartners[key] ?? [];
                // Calculate dynamic height to match Partner(s) column
                final dynamicHeight =
                    selectedPartners.isEmpty || selectedPartners.length == 1
                        ? 48.0
                        : 48.0 + (selectedPartners.length - 1) * 36.0;
                final controller =
                    _plotNumberControllers[key] ?? TextEditingController();
                if (_plotNumberControllers[key] == null) {
                  _plotNumberControllers[key] = controller;
                }
                final focusNode =
                    _plotNumberFocusNodes.putIfAbsent(key, () => FocusNode());
                final plotNumberEmpty = controller.text.trim().isEmpty ||
                    (plots[index]['plotNumber']?.toString().trim().isEmpty ??
                        true);
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
                                color: focusNode.hasFocus
                                    ? const Color(0xFF0C8CE9)
                                    : (plotNumberEmpty
                                        ? Colors.red
                                        : Colors.black.withOpacity(0.15)),
                                blurRadius: 2,
                                offset: const Offset(0, 0),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            textAlignVertical: TextAlignVertical.center,
                            onChanged: (value) {
                              plots[index]['plotNumber'] = value;
                              setState(() {}); // Update shadow color
                              _onDataChanged();
                            },
                            decoration: InputDecoration(
                              hintText: 'Enter Plot Number',
                              hintStyle: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: const Color.fromARGB(191, 173, 173, 173),
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
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
                        'Area ($_areaUnitSuffix) ',
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
                ),
              ),
              ...List.generate(plots.length, (index) {
                final key = '${layoutIndex}_$index';
                final selectedPartners = _plotPartners[key] ?? [];
                // Calculate dynamic height to match Partner(s) column
                final dynamicHeight =
                    selectedPartners.isEmpty || selectedPartners.length == 1
                        ? 48.0
                        : 48.0 + (selectedPartners.length - 1) * 36.0;
                final controller =
                    _plotAreaControllers[key] ?? TextEditingController();
                if (_plotAreaControllers[key] == null) {
                  _plotAreaControllers[key] = controller;
                }
                final focusNode =
                    _plotAreaFocusNodes.putIfAbsent(key, () => FocusNode());
                final cleanedAreaText = controller.text
                    .replaceAll(',', '')
                    .replaceAll(' ', '')
                    .trim();
                final areaIsEmpty = cleanedAreaText.isEmpty ||
                    cleanedAreaText == '0' ||
                    cleanedAreaText == '0.00';
                final areaEmpty = areaIsEmpty ||
                    (plots[index]['area']?.toString().trim().isEmpty ?? true) ||
                    plots[index]['area'] == '0.00';
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
                                color: focusNode.hasFocus
                                    ? const Color(0xFF0C8CE9)
                                    : (areaEmpty
                                        ? Colors.red
                                        : Colors.black.withOpacity(0.15)),
                                blurRadius: 2,
                                offset: const Offset(0, 0),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Builder(
                            builder: (context) {
                              final cleanedText = controller.text
                                  .replaceAll(',', '')
                                  .replaceAll(' ', '')
                                  .trim();
                              final isEmpty = cleanedText.isEmpty ||
                                  cleanedText == '0' ||
                                  cleanedText == '0.00';
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
                                          '$_areaUnitSuffix ',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: DecimalInputField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        hintText: '0',
                                        decimalPlaces: 3,
                                        inputFormatters: [
                                          IndianNumberFormatter(
                                              maxIntegerDigits: 9)
                                        ],
                                        onTap: () {
                                          // Clear '0.00' when field is tapped
                                          final cleaned = controller.text
                                              .replaceAll(',', '')
                                              .replaceAll(' ', '')
                                              .trim();
                                          if (cleaned == '0' ||
                                              cleaned == '0.00') {
                                            controller.text = '';
                                            controller.selection =
                                                TextSelection.collapsed(
                                                    offset: 0);
                                            setState(() {});
                                          }
                                        },
                                        onChanged: (value) {
                                          final cleaned = value
                                              .replaceAll(',', '')
                                              .replaceAll(' ', '');
                                          plots[index]['area'] = cleaned.isEmpty
                                              ? '0.00'
                                              : cleaned;
                                          setState(
                                              () {}); // Recalculate totals and update shadow
                                          _onDataChanged();
                                        },
                                        onEditingComplete: () {
                                          // Remove commas before formatting
                                          final cleaned = controller.text
                                              .replaceAll(',', '')
                                              .replaceAll(' ', '')
                                              .trim();
                                          final formatted = _formatAmount(
                                              cleaned,
                                              decimalPlaces: 3);
                                          controller.text = formatted;
                                          plots[index]['area'] =
                                              formatted.replaceAll(',', '');
                                          setState(() {});
                                          _onDataChanged();
                                          FocusScope.of(context).nextFocus();
                                        },
                                        onTapOutside: () {
                                          // Remove commas before formatting
                                          final cleaned = controller.text
                                              .replaceAll(',', '')
                                              .replaceAll(' ', '')
                                              .trim();
                                          final formatted = _formatAmount(
                                              cleaned,
                                              decimalPlaces: 3);
                                          controller.text = formatted;
                                          plots[index]['area'] =
                                              formatted.replaceAll(',', '');
                                          setState(() {});
                                          _onDataChanged();
                                        },
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                vertical: 8),
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
                    'All-in Cost (₹/$_areaUnitSuffix)',
                    style: GoogleFonts.inter(
                      fontSize: 14,
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
                final dynamicHeight =
                    selectedPartners.isEmpty || selectedPartners.length == 1
                        ? 48.0
                        : 48.0 + (selectedPartners.length - 1) * 36.0;
                // Calculate All-in Cost as Total Expenses / Approved selling area
                final allInCost = _approvedSellingArea > 0
                    ? _totalExpenses / _approvedSellingArea
                    : 0.0;
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
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                            children: [
                              TextSpan(text: '₹/$_areaUnitSuffix '),
                              TextSpan(
                                text: isEmpty
                                    ? '0.00'
                                    : _formatAmountForDisplay(allInCost,
                                        decimalPlaces: 5),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: isEmpty
                                      ? const Color(0xFF5D5D5D)
                                      : Colors.black,
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
                      fontSize: 14,
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
                final dynamicHeight =
                    selectedPartners.isEmpty || selectedPartners.length == 1
                        ? 48.0
                        : 48.0 + (selectedPartners.length - 1) * 36.0;

                // Get Area (column 3) and All-in Cost (column 4) to calculate Total Plot Cost
                final areaController = _plotAreaControllers[key];
                final area = double.tryParse(areaController?.text
                            .replaceAll(',', '')
                            .replaceAll(' ', '')
                            .trim() ??
                        '0') ??
                    0.0;

                // Calculate All-in Cost as Total Expenses / Approved selling area
                final allInCost = _approvedSellingArea > 0
                    ? _totalExpenses / _approvedSellingArea
                    : 0.0;

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
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                            children: [
                              const TextSpan(text: '₹ '),
                              TextSpan(
                                text: totalPlotCost == 0.0
                                    ? '0.000'
                                    : _formatAmountForDisplay(totalPlotCost,
                                        decimalPlaces: 3),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: totalPlotCost == 0.0
                                      ? const Color(0xFF5D5D5D)
                                      : Colors.black,
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
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                  ),
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
                final dynamicHeight =
                    selectedPartners.isEmpty || selectedPartners.length == 1
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
                            _showPartnerDropdown(context, layoutIndex, index,
                                key, partnerCellKey);
                          },
                          child: Row(
                            children: [
                              selectedPartners.isEmpty
                                  ? Container(
                                      constraints: const BoxConstraints(
                                          minHeight: 32, maxHeight: 32),
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: partnersEmpty
                                                ? Colors.red
                                                : Colors.black
                                                    .withOpacity(0.25),
                                            blurRadius: 2,
                                            offset: const Offset(0, 0),
                                            spreadRadius: 0,
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Select Partner(s)',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: const Color.fromARGB(
                                              191, 173, 173, 173),
                                        ),
                                      ),
                                    )
                                  : (selectedPartners.length == 1
                                      ? Container(
                                          height: 32,
                                          alignment: Alignment.center,
                                          child: Text(
                                            selectedPartners[0],
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.black,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            for (int partnerIndex = 0;
                                                partnerIndex <
                                                    selectedPartners.length;
                                                partnerIndex++)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top:
                                                      partnerIndex == 0 ? 8 : 8,
                                                ),
                                                child: Text(
                                                  selectedPartners[
                                                      partnerIndex],
                                                  textAlign: TextAlign.center,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.black,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                        )),
                              Spacer(),
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: selectedPartners.isEmpty
                                    ? SvgPicture.asset(
                                        'assets/images/Drrrop_down.svg',
                                        width: 14,
                                        height: 7,
                                        fit: BoxFit.contain,
                                        colorFilter: const ColorFilter.mode(
                                          Colors.red,
                                          BlendMode.srcIn,
                                        ),
                                        placeholderBuilder: (context) =>
                                            const SizedBox(
                                          width: 14,
                                          height: 7,
                                        ),
                                      )
                                    : SvgPicture.asset(
                                        'assets/images/Add_more_member.svg',
                                        width: 14,
                                        height: 14,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) =>
                                            const SizedBox(
                                          width: 14,
                                          height: 14,
                                        ),
                                      ),
                              ),
                            ],
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
                final dynamicHeight =
                    selectedPartners.isEmpty || selectedPartners.length == 1
                        ? (index == 0 ? 49.0 : 48.0)
                        : (index == 0 ? 49.0 : 48.0) +
                            (selectedPartners.length - 1) * 36.0;
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
                            _plotNumberControllers[newKey] =
                                _plotNumberControllers.remove(oldKey)!;
                            _plotAreaControllers[newKey] =
                                _plotAreaControllers.remove(oldKey)!;
                            _plotPurchaseRateControllers[newKey] =
                                _plotPurchaseRateControllers.remove(oldKey)!;
                            _plotPartners[newKey] =
                                _plotPartners.remove(oldKey) ?? [];
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
                              ? const BorderSide(
                                  color: Colors.black, width: 1.0)
                              : BorderSide.none,
                          right:
                              const BorderSide(color: Colors.black, width: 1.0),
                          bottom:
                              const BorderSide(color: Colors.black, width: 1.0),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
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

  void _showPartnerDropdown(BuildContext context, int layoutIndex,
      int plotIndex, String key, GlobalKey cellKey) {
    // Get available partners (filter out empty names)
    final availablePartners = _partners
        .where(
            (partner) => partner['name']?.toString().trim().isNotEmpty == true)
        .map((partner) => partner['name']?.toString().trim() ?? '')
        .toList();

    if (availablePartners.isEmpty) {
      return;
    }

    final RenderBox? renderBox =
        cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

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

    final double left = offset.dx;
    final double top = offset.dy + renderBox.size.height + 8;
    final double dropdownWidth = renderBox.size.width;
    final bool showHeader = (_plotPartners[key] ?? []).isNotEmpty;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dropdownWidth,
            constraints: const BoxConstraints(maxHeight: 220),
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
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showHeader) ...[
                    Container(
                      height: 32,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Select Partner(s)',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 144),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: availablePartners.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, itemIndex) {
                        final partnerName = availablePartners[itemIndex];
                        final selectedPartners = _plotPartners[key] ?? [];
                        final isSelected =
                            selectedPartners.contains(partnerName);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              final currentPartners =
                                  List<String>.from(_plotPartners[key] ?? []);
                              if (isSelected) {
                                currentPartners.remove(partnerName);
                              } else {
                                currentPartners.add(partnerName);
                              }
                              _plotPartners[key] = currentPartners;
                            });
                            _onDataChanged();
                            closeDropdown();
                          },
                          child: Container(
                            alignment: Alignment.centerLeft,
                            child: IntrinsicWidth(
                              child: Container(
                                height: 32,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F9FA),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected
                                          ? const Color(0xFF0C8CE9)
                                          : Colors.black.withOpacity(0.25),
                                      blurRadius: 2,
                                      offset: const Offset(0, 0),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  partnerName,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
                        fontSize: 14,
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
                        right:
                            const BorderSide(color: Colors.black, width: 1.0),
                        bottom:
                            const BorderSide(color: Colors.black, width: 1.0),
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
                          fontSize: 14,
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
                        right:
                            const BorderSide(color: Colors.black, width: 1.0),
                        bottom:
                            const BorderSide(color: Colors.black, width: 1.0),
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
                          boxShadow: isFirstRow
                              ? []
                              : [
                                  BoxShadow(
                                    color: _expenseItemFocusNodes
                                            .putIfAbsent(
                                                index, () => FocusNode())
                                            .hasFocus
                                        ? const Color(0xFF0C8CE9)
                                        : ((_expenses[index]['item']
                                                    ?.toString()
                                                    .trim()
                                                    .isEmpty ??
                                                true)
                                            ? Colors.red
                                            : Colors.black.withOpacity(0.15)),
                                    blurRadius: 2,
                                    offset: const Offset(0, 0),
                                    spreadRadius: 0,
                                  ),
                                ],
                        ),
                        child: TextField(
                          controller: _expenseItemControllers[index],
                          focusNode: _expenseItemFocusNodes.putIfAbsent(
                              index, () => FocusNode()),
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
                                  _expenseItemControllers[index] =
                                      TextEditingController(text: value);
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
                            contentPadding:
                                const EdgeInsets.only(left: 8, top: 11),
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
                        right:
                            const BorderSide(color: Colors.black, width: 1.0),
                        bottom:
                            const BorderSide(color: Colors.black, width: 1.0),
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
                              color: _expenseAmountFocusNodes
                                      .putIfAbsent(index, () => FocusNode())
                                      .hasFocus
                                  ? const Color(0xFF0C8CE9)
                                  : ((double.tryParse((_expenses[index]
                                                          ['amount'] ??
                                                      '0')
                                                  .toString()
                                                  .replaceAll(',', '')) ??
                                              0) ==
                                          0
                                      ? Colors.red
                                      : Colors.black.withOpacity(0.15)),
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
                                  if (_expenseAmountControllers[index] ==
                                      null) {
                                    _expenseAmountControllers[index] =
                                        TextEditingController();
                                  }
                                  return DecimalInputField(
                                    controller:
                                        _expenseAmountControllers[index]!,
                                    focusNode: _expenseAmountFocusNodes
                                        .putIfAbsent(index, () => FocusNode()),
                                    hintText: '0',
                                    inputFormatters: [
                                      IndianNumberFormatter(
                                          maxIntegerDigits: 11)
                                    ],
                                    onTap: () {
                                      // Clear '0.00' when field is tapped
                                      final cleaned =
                                          _expenseAmountControllers[index]!
                                              .text
                                              .replaceAll(',', '')
                                              .replaceAll('₹', '')
                                              .replaceAll(' ', '')
                                              .trim();
                                      if (cleaned == '0' || cleaned == '0.00') {
                                        _expenseAmountControllers[index]!.text =
                                            '';
                                        _expenseAmountControllers[index]!
                                                .selection =
                                            TextSelection.collapsed(offset: 0);
                                        setState(() {});
                                      }
                                    },
                                    onChanged: (value) {
                                      // Remove commas for storage (for real-time calculations)
                                      final rawValue = value
                                          .replaceAll(',', '')
                                          .replaceAll('₹', '')
                                          .replaceAll(' ', '');
                                      setState(() {
                                        _expenses[index]['amount'] =
                                            rawValue.isEmpty
                                                ? '0.00'
                                                : rawValue;
                                      });
                                      _onDataChanged();
                                    },
                                    onEditingComplete: () {
                                      // Remove commas before formatting
                                      final cleaned =
                                          _expenseAmountControllers[index]!
                                              .text
                                              .replaceAll(',', '')
                                              .replaceAll('₹', '')
                                              .replaceAll(' ', '');
                                      final formatted = _formatAmount(cleaned);
                                      FocusScope.of(context).unfocus();
                                      _expenseAmountControllers[index]!.value =
                                          TextEditingValue(
                                        text: formatted,
                                        selection: TextSelection.collapsed(
                                            offset: formatted.length),
                                      );
                                      setState(() {
                                        _expenses[index]['amount'] =
                                            formatted.replaceAll(',', '');
                                      });
                                      _onDataChanged();
                                    },
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 8),
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
                  ),
                ),
                // Rows
                ...List.generate(expenses.length, (index) {
                  final isLast = index == expenses.length - 1;
                  final isFirstRow = index == 0;
                  final selectedCategory =
                      (_expenses[index]['category']?.toString() ?? '').trim();
                  final hasCategory = selectedCategory.isNotEmpty;
                  return Container(
                    width: 300,
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        right:
                            const BorderSide(color: Colors.black, width: 1.0),
                        bottom:
                            const BorderSide(color: Colors.black, width: 1.0),
                        top: BorderSide.none,
                        left: BorderSide.none,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Builder(
                          builder: (builderContext) {
                            final key = GlobalKey();
                            return GestureDetector(
                              onTap: isFirstRow
                                  ? null
                                  : () {
                                      if (_openCategoryDropdownIndex == index) {
                                        _currentCategoryDropdownEntry?.remove();
                                        _currentCategoryBackdropEntry?.remove();
                                        if (mounted) {
                                          setState(() {
                                            _openCategoryDropdownIndex = null;
                                            _currentCategoryDropdownEntry =
                                                null;
                                            _currentCategoryBackdropEntry =
                                                null;
                                          });
                                        } else {
                                          _openCategoryDropdownIndex = null;
                                          _currentCategoryDropdownEntry = null;
                                          _currentCategoryBackdropEntry = null;
                                        }
                                      } else {
                                        _currentCategoryDropdownEntry?.remove();
                                        _currentCategoryBackdropEntry?.remove();
                                        _showCategoryDropdown(
                                            builderContext, index, key);
                                      }
                                    },
                              child: Container(
                                key: key,
                                height: 32,
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: hasCategory
                                      ? _getCategoryColor(selectedCategory)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: hasCategory
                                          ? Colors.black.withOpacity(0.25)
                                          : Colors.red,
                                      blurRadius: 2,
                                      offset: const Offset(0, 0),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        hasCategory
                                            ? selectedCategory
                                            : 'Select category',
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: hasCategory
                                              ? FontWeight.normal
                                              : FontWeight.w500,
                                          color: hasCategory
                                              ? Colors.black
                                              : (_openCategoryDropdownIndex ==
                                                      index
                                                  ? Colors.black
                                                  : const Color.fromARGB(
                                                      191, 173, 173, 173)),
                                        ),
                                      ),
                                    ),
                                    if (!isFirstRow)
                                      SvgPicture.asset(
                                        'assets/images/Drrrop_down.svg',
                                        width: 7,
                                        height: 7,
                                        fit: BoxFit.contain,
                                        colorFilter: const ColorFilter.mode(
                                          Color(0xFF000000),
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
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
                  height: 46,
                ),
                // Rows with Remove buttons
                ...List.generate(expenses.length, (index) {
                  final isLast = index == expenses.length - 1;
                  final isFirstRow = index == 0;
                  if (isFirstRow) {
                    return const SizedBox(
                      width: 120,
                      height: 49,
                    );
                  }
                  return Container(
                    width: 120,
                    height: index == 1 ? 49 : 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: index == 1
                            ? const BorderSide(color: Colors.black, width: 1.0)
                            : BorderSide.none,
                        right:
                            const BorderSide(color: Colors.black, width: 1.0),
                        bottom:
                            const BorderSide(color: Colors.black, width: 1.0),
                        left: BorderSide.none,
                      ),
                      borderRadius: index == 1 && isLast
                          ? const BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            )
                          : (index == 1
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
                          if (_expenses.length > 1) {
                            setState(() {
                              _expenseItemControllers[index]?.dispose();
                              _expenseAmountControllers[index]?.dispose();
                              _expenses.removeAt(index);
                              // Rebuild controllers maps
                              final oldItemControllers =
                                  Map<int, TextEditingController>.from(
                                      _expenseItemControllers);
                              final oldAmountControllers =
                                  Map<int, TextEditingController>.from(
                                      _expenseAmountControllers);
                              _expenseItemControllers.clear();
                              _expenseAmountControllers.clear();
                              for (int i = 0; i < _expenses.length; i++) {
                                if (i < index) {
                                  _expenseItemControllers[i] =
                                      oldItemControllers[i]!;
                                  _expenseAmountControllers[i] =
                                      oldAmountControllers[i]!;
                                } else {
                                  _expenseItemControllers[i] =
                                      oldItemControllers[i + 1]!;
                                  _expenseAmountControllers[i] =
                                      oldAmountControllers[i + 1]!;
                                }
                              }
                            });
                            _onDataChanged();
                          }
                        },
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
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
    final RenderBox? renderBox =
        key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;
    void closeDropdown() {
      overlayEntry?.remove();
      backdropEntry?.remove();
      if (mounted) {
        setState(() {
          _currentCategoryDropdownEntry = null;
          _currentCategoryBackdropEntry = null;
          _openCategoryDropdownIndex = null;
        });
      } else {
        _currentCategoryDropdownEntry = null;
        _currentCategoryBackdropEntry = null;
        _openCategoryDropdownIndex = null;
      }
    }

    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeDropdown,
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    const double menuPadding = 4;
    final double left = offset.dx;
    final double top = offset.dy + renderBox.size.height + 8;
    final double dropdownWidth = renderBox.size.width;
    final int optionCount = _expenseCategories.length;
    final bool showHeader =
        (_expenses[index]['category']?.toString() ?? '').trim().isNotEmpty;
    final double calculatedMenuHeight = (menuPadding * 2) +
        (optionCount * 32) +
        ((optionCount - 1) * 8) +
        (showHeader ? 40 : 0);
    final screenHeight = MediaQuery.of(context).size.height;
    final availableHeight = screenHeight - top - 8;
    final maxMenuHeight = min(calculatedMenuHeight, availableHeight);

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dropdownWidth,
            height: maxMenuHeight,
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
            child: Padding(
              padding: const EdgeInsets.all(menuPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showHeader) ...[
                    Container(
                      height: 32,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Select category',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _expenseCategories.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, itemIndex) {
                        final category = _expenseCategories[itemIndex];
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
                            alignment: Alignment.centerLeft,
                            child: IntrinsicWidth(
                              child: Container(
                                height: 32,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: categoryColor,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 2,
                                      offset: const Offset(0, 0),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  category,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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

    // Store references to the open dropdown
    if (mounted) {
      setState(() {
        _currentCategoryBackdropEntry = backdropEntry;
        _currentCategoryDropdownEntry = overlayEntry;
        _openCategoryDropdownIndex = index;
      });
    } else {
      _currentCategoryBackdropEntry = backdropEntry;
      _currentCategoryDropdownEntry = overlayEntry;
      _openCategoryDropdownIndex = index;
    }
  }

  void _showLayoutMenu(BuildContext context, int layoutIndex, String layoutName,
      GlobalKey anchorKey) {
    final RenderBox? renderBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;

    // Function to close menu
    void closeMenu() {
      overlayEntry?.remove();
      backdropEntry?.remove();
      _openLayoutMenuIndex = null;
      _currentLayoutMenuEntry = null;
      _currentLayoutMenuBackdropEntry = null;
    }

    // Create backdrop
    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeMenu,
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    // Calculate menu position (below and aligned to right of three dots button)
    final menuWidth = 148.0;
    final leftPosition = offset.dx + renderBox.size.width - menuWidth;
    final topPosition = offset.dy + renderBox.size.height + 8;

    // Create menu
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: leftPosition,
        top: topPosition,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: menuWidth,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
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
            child: GestureDetector(
              onTap: () {
                closeMenu();
                _showDeleteLayoutDialog(context, layoutIndex, layoutName);
              },
              child: Container(
                width: menuWidth - 16,
                height: 36,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    'Delete layout',
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
      ),
    );

    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);

    _currentLayoutMenuEntry = overlayEntry;
    _currentLayoutMenuBackdropEntry = backdropEntry;
    _openLayoutMenuIndex = layoutIndex;
  }

  void _showDeleteLayoutDialog(
      BuildContext context, int layoutIndex, String layoutName) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 100),
        alignment: Alignment.topCenter,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
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
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title and close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Delete Layout?',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 22.627,
                        height: 22.627,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: const Color(0xFF0C8CE9),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Layout name
                Text(
                  '${layoutIndex + 1}. Layout: ${layoutName.isEmpty ? 'NA' : layoutName}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: Colors.black.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                // Warning messages
                Text(
                  'This will permanently delete this layout and all plots inside it, including their area, cost, and partner assignments.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: Colors.black.withOpacity(0.8),
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
                const SizedBox(height: 16),
                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
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
                    GestureDetector(
                      onTap: () async {
                        Navigator.of(context).pop();
                        // Delete the layout
                        if (layoutIndex < _layouts.length) {
                          final layout = _layouts[layoutIndex];
                          final layoutNameController =
                              _layoutNameControllers[layoutIndex];
                          final layoutNameToDelete =
                              layoutNameController?.text.trim() ??
                                  layout['name']?.toString().trim() ??
                                  '';

                          // Delete from database if layout has a name and project ID
                          if (layoutNameToDelete.isNotEmpty &&
                              widget.projectId != null) {
                            try {
                              // Find layout by name
                              final existingLayouts = await _supabase
                                  .from('layouts')
                                  .select('id')
                                  .eq('project_id', widget.projectId!)
                                  .eq('name', layoutNameToDelete)
                                  .maybeSingle();

                              if (existingLayouts != null &&
                                  existingLayouts['id'] != null) {
                                final layoutId =
                                    existingLayouts['id'] as String;

                                // Delete all plots in this layout first
                                await _supabase
                                    .from('plots')
                                    .delete()
                                    .eq('layout_id', layoutId);

                                // Delete the layout
                                await _supabase
                                    .from('layouts')
                                    .delete()
                                    .eq('id', layoutId);
                              }
                            } catch (e) {
                              print('Error deleting layout from database: $e');
                            }
                          }

                          // Remove from local state
                          setState(() {
                            // Dispose the controller and focus node for the deleted layout
                            _layoutNameControllers[layoutIndex]?.dispose();
                            _layoutNameFocusNodes[layoutIndex]?.dispose();

                            _layouts.removeAt(layoutIndex);

                            // Reindex remaining layouts - move controllers and focus nodes down
                            final controllersToMove =
                                <int, TextEditingController>{};
                            final focusNodesToMove = <int, FocusNode>{};

                            // Collect controllers and focus nodes that need to be moved
                            for (int i = layoutIndex + 1;
                                i < _layouts.length + 1;
                                i++) {
                              if (_layoutNameControllers.containsKey(i)) {
                                controllersToMove[i] =
                                    _layoutNameControllers[i]!;
                              }
                              if (_layoutNameFocusNodes.containsKey(i)) {
                                focusNodesToMove[i] = _layoutNameFocusNodes[i]!;
                              }
                            }

                            // Remove the deleted layout's controllers
                            _layoutNameControllers.remove(layoutIndex);
                            _layoutNameFocusNodes.remove(layoutIndex);

                            // Remove old entries for layouts that need to be reindexed
                            for (int i = layoutIndex + 1;
                                i < _layouts.length + 1;
                                i++) {
                              _layoutNameControllers.remove(i);
                              _layoutNameFocusNodes.remove(i);
                            }

                            // Add back with new indices (shifted down by 1)
                            for (var entry in controllersToMove.entries) {
                              _layoutNameControllers[entry.key - 1] =
                                  entry.value;
                            }
                            for (var entry in focusNodesToMove.entries) {
                              _layoutNameFocusNodes[entry.key - 1] =
                                  entry.value;
                            }
                          });
                          _onDataChanged();
                        }
                      },
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
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
                              'Delete Layout',
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
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 13,
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
        ),
      ),
    );
  }

  void _showDeleteAllLayoutsMenu(BuildContext context, GlobalKey anchorKey) {
    final RenderBox? renderBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

    OverlayEntry? backdropEntry;
    OverlayEntry? overlayEntry;

    // Function to close menu
    void closeMenu() {
      overlayEntry?.remove();
      backdropEntry?.remove();
      _openLayoutMenuIndex = null;
      _currentLayoutMenuEntry = null;
      _currentLayoutMenuBackdropEntry = null;
    }

    // Create backdrop
    backdropEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          onTap: closeMenu,
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    // Match "Select category" dropdown placement: open directly below trigger.
    final menuWidth = 180.0;
    final leftPosition = offset.dx + renderBox.size.width - menuWidth;
    final topPosition = offset.dy + renderBox.size.height + 8;

    // Create menu
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: leftPosition,
        top: topPosition,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
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
            child: GestureDetector(
              onTap: () {
                closeMenu();
                _showDeleteAllLayoutsDialog(context);
              },
              child: Container(
                width: menuWidth - 16,
                height: 36,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    'Delete all layouts',
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
      ),
    );

    overlay.insert(backdropEntry);
    overlay.insert(overlayEntry);

    _currentLayoutMenuEntry = overlayEntry;
    _currentLayoutMenuBackdropEntry = backdropEntry;
    _openLayoutMenuIndex = -1; // Use -1 to indicate "delete all" menu
  }

  void _showDeleteAllLayoutsDialog(BuildContext context) {
    final TextEditingController confirmController = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 100),
          alignment: Alignment.topCenter,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
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
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with icon, title and close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning,
                            size: 16,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Delete All Layout?',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          confirmController.dispose();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 22.627,
                          height: 22.627,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: const Color(0xFF0C8CE9),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Warning messages
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This will permanently delete all layouts and all plots in this project.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.black.withOpacity(0.8),
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
                  const SizedBox(height: 16),
                  // Confirmation input
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                          ),
                          children: [
                            TextSpan(
                              text: 'Type ',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: const Color(0xFF323232),
                              ),
                            ),
                            TextSpan(
                              text: 'delete ',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            TextSpan(
                              text: 'to confirm.',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: const Color(0xFF323232),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 150,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(1.0),
                              blurRadius: 2,
                              offset: const Offset(0, 0),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: confirmController,
                          onChanged: (value) {
                            setDialogState(() {});
                          },
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 12),
                            hintText: '',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () {
                          confirmController.dispose();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
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
                      GestureDetector(
                        onTap: confirmController.text.toLowerCase().trim() ==
                                'delete'
                            ? () async {
                                confirmController.dispose();
                                Navigator.of(context).pop();
                                // Delete all layouts from database
                                if (widget.projectId != null) {
                                  try {
                                    // Get all layouts for this project
                                    final existingLayouts = await _supabase
                                        .from('layouts')
                                        .select('id')
                                        .eq('project_id', widget.projectId!);

                                    // Delete all plots first
                                    for (var layout in existingLayouts) {
                                      final layoutId = layout['id'] as String;
                                      await _supabase
                                          .from('plots')
                                          .delete()
                                          .eq('layout_id', layoutId);
                                    }

                                    // Delete all layouts
                                    await _supabase
                                        .from('layouts')
                                        .delete()
                                        .eq('project_id', widget.projectId!);
                                  } catch (e) {
                                    print(
                                        'Error deleting all layouts from database: $e');
                                  }
                                }

                                // Clear local state
                                setState(() {
                                  _layouts.clear();
                                  _layoutNameControllers.clear();
                                  _layoutNameFocusNodes.clear();
                                  _numberOfLayoutsController.text = '0';
                                  _isCreateTableEnabled = false;
                                });
                                _onDataChanged();
                              }
                            : null,
                        child: Opacity(
                          opacity:
                              confirmController.text.toLowerCase().trim() ==
                                      'delete'
                                  ? 1.0
                                  : 0.5,
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
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
                            child: Center(
                              child: Text(
                                'Delete all layouts',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: confirmController.text
                                              .toLowerCase()
                                              .trim() ==
                                          'delete'
                                      ? Colors.red
                                      : Colors.red.withOpacity(0.5),
                                ),
                              ),
                            ),
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
      ),
    );
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
  final Color? defaultShadowColor;

  const _FocusAwareInputContainer({
    required this.focusNode,
    required this.child,
    this.onFocusLost,
    this.width = double.infinity,
    this.height = 40,
    this.backgroundColor = const Color(0xFFF8F9FA),
    this.borderRadius = 8,
    this.defaultShadowColor,
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
      if (_hadFocus &&
          !widget.focusNode.hasFocus &&
          widget.onFocusLost != null) {
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
                : (widget.defaultShadowColor ??
                    Colors.black.withOpacity(0.15)), // Default color
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
