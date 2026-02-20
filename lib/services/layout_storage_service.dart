import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LayoutStorageService {
  static const String _layoutsKey = 'project_layouts_data';
  static const String _projectNameKey = 'current_project_name';
  static const String _projectAddressKeyPrefix = 'project_address_';
  static const String _projectMapsLinkKeyPrefix = 'project_maps_link_';
  static const String _agentsKey = 'project_agents_data';

  /// Save layout data to local storage (from project details page with controllers)
  static Future<void> saveLayoutsData(
    List<Map<String, dynamic>> layouts,
    Map<int, TextEditingController> layoutNameControllers,
    Map<String, TextEditingController> plotNumberControllers,
    Map<String, TextEditingController> plotAreaControllers,
    Map<String, TextEditingController> plotPurchaseRateControllers, {
    Map<String, List<String>>? plotPartners,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Extract actual values from controllers and build the data structure
      final layoutsData = <Map<String, dynamic>>[];
      
      for (int layoutIndex = 0; layoutIndex < layouts.length; layoutIndex++) {
        final layout = layouts[layoutIndex];
        final layoutNameController = layoutNameControllers[layoutIndex];
        final layoutName = layoutNameController?.text ?? layout['name'] ?? 'Layout ${layoutIndex + 1}';
        
        final plots = layout['plots'] as List<dynamic>? ?? [];
        final plotsData = <Map<String, dynamic>>[];
        
        for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
          final key = '${layoutIndex}_$plotIndex';
          final plotNumberController = plotNumberControllers[key];
          final plotAreaController = plotAreaControllers[key];
          final plotPurchaseRateController = plotPurchaseRateControllers[key];
          
          plotsData.add({
            'plotNumber': plotNumberController?.text ?? '',
            'area': plotAreaController?.text ?? '0.00',
            'purchaseRate': plotPurchaseRateController?.text ?? '0.00',
            'totalPlotCost': '0.00', // Will be calculated when saving to database
            'status': 'available', // Default status
            'salePrice': '0.00',
            'buyerName': '',
            'agent': '',
            'saleDate': '',
            'partners': plotPartners?[key] ?? [],
          });
        }
        
        layoutsData.add({
          'name': layoutName,
          'plots': plotsData,
        });
      }
      
      // Convert to JSON string and save
      final jsonString = jsonEncode(layoutsData);
      await prefs.setString(_layoutsKey, jsonString);
    } catch (e) {
      print('Error saving layouts data: $e');
    }
  }

  /// Load layout data from local storage
  static Future<List<Map<String, dynamic>>> loadLayoutsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_layoutsKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error loading layouts data: $e');
      return [];
    }
  }

  /// Save current project name
  static Future<void> saveProjectName(String projectName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_projectNameKey, projectName);
    } catch (e) {
      print('Error saving project name: $e');
    }
  }

  /// Load current project name
  static Future<String?> loadProjectName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_projectNameKey);
    } catch (e) {
      print('Error loading project name: $e');
      return null;
    }
  }

  /// Save project about details (address and maps link)
  static Future<void> saveProjectAbout({
    required String projectKey,
    required String projectAddress,
    required String googleMapsLink,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_projectAddressKeyPrefix}$projectKey', projectAddress);
      await prefs.setString('${_projectMapsLinkKeyPrefix}$projectKey', googleMapsLink);
    } catch (e) {
      print('Error saving project about details: $e');
    }
  }

  /// Load project about details (address and maps link)
  static Future<Map<String, String>> loadProjectAbout({
    required String projectKey,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString('${_projectAddressKeyPrefix}$projectKey') ?? '';
      final mapsLink = prefs.getString('${_projectMapsLinkKeyPrefix}$projectKey') ?? '';
      return {
        'address': address,
        'mapsLink': mapsLink,
      };
    } catch (e) {
      print('Error loading project about details: $e');
      return {
        'address': '',
        'mapsLink': '',
      };
    }
  }

  /// Save layout data directly (from plot status page with status info)
  static Future<void> saveLayoutsDataDirect(List<Map<String, dynamic>> layouts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(layouts);
      await prefs.setString(_layoutsKey, jsonString);
    } catch (e) {
      print('Error saving layouts data directly: $e');
    }
  }

  /// Clear all saved layout data
  static Future<void> clearLayoutsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_layoutsKey);
    } catch (e) {
      print('Error clearing layouts data: $e');
    }
  }

  /// Save agents data to local storage
  static Future<void> saveAgentsData(List<Map<String, dynamic>> agents) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Filter out empty agents and extract only name
      final agentsToSave = agents
          .where((agent) {
            final name = agent['name']?.toString().trim() ?? '';
            return name.isNotEmpty;
          })
          .map((agent) => {
                'name': agent['name']?.toString().trim() ?? '',
              })
          .toList();
      
      final jsonString = jsonEncode(agentsToSave);
      await prefs.setString(_agentsKey, jsonString);
    } catch (e) {
      print('Error saving agents data: $e');
    }
  }

  /// Load agents data from local storage
  static Future<List<Map<String, dynamic>>> loadAgentsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_agentsKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error loading agents data: $e');
      return [];
    }
  }
}
