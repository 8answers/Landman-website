import 'package:supabase_flutter/supabase_flutter.dart';

class ProjectStorageService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Save complete project data to Supabase
  static Future<void> saveProjectData({
    required String projectId,
    required String projectName,
    String? totalArea,
    String? sellingArea,
    String? estimatedDevelopmentCost,
    List<Map<String, String>>? nonSellableAreas,
    List<Map<String, dynamic>>? partners,
    List<Map<String, dynamic>>? expenses,
    List<Map<String, dynamic>>? layouts,
    List<Map<String, dynamic>>? projectManagers,
    List<Map<String, dynamic>>? agents,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Get current project to check existing name
      final currentProject = await _supabase
          .from('projects')
          .select('project_name')
          .eq('id', projectId)
          .eq('user_id', userId)
          .maybeSingle();

      // Build update map - only update fields if they are explicitly provided (not null/empty)
      // This prevents overwriting existing values when saving from other pages (e.g., plot_status_page)
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      // Only update total_area if explicitly provided
      if (totalArea != null && totalArea.trim().isNotEmpty) {
        final parsedTotalArea = _parseDecimal(totalArea);
        updateData['total_area'] = parsedTotalArea;
        print('ProjectStorageService.saveProjectData: Updating total_area: "$totalArea" -> $parsedTotalArea');
      }
      
      // Only update selling_area if explicitly provided
      if (sellingArea != null && sellingArea.trim().isNotEmpty) {
        final parsedSellingArea = _parseDecimal(sellingArea);
        updateData['selling_area'] = parsedSellingArea;
        print('ProjectStorageService.saveProjectData: Updating selling_area: "$sellingArea" -> $parsedSellingArea');
      }
      
      // Only update estimated_development_cost if explicitly provided
      if (estimatedDevelopmentCost != null && estimatedDevelopmentCost.trim().isNotEmpty) {
        final parsedEstimatedCost = _parseDecimal(estimatedDevelopmentCost);
        updateData['estimated_development_cost'] = parsedEstimatedCost;
        print('ProjectStorageService.saveProjectData: Updating estimated_development_cost: "$estimatedDevelopmentCost" -> $parsedEstimatedCost');
      }
      
      print('ProjectStorageService.saveProjectData: Update data map: $updateData');

      // Only update project_name if:
      // 1. It's not empty
      // 2. It's different from the current name
      // 3. It doesn't already exist for this user (unless it's the same project)
      final trimmedProjectName = projectName.trim();
      if (trimmedProjectName.isNotEmpty) {
        final currentName = currentProject?['project_name']?.toString().trim() ?? '';
        if (trimmedProjectName != currentName) {
          // Check if another project with this name exists for this user
          final existingProject = await _supabase
              .from('projects')
              .select('id')
              .eq('user_id', userId)
              .eq('project_name', trimmedProjectName)
              .maybeSingle();
          
          // Only update if no other project has this name (or if it's the same project)
          if (existingProject == null || existingProject['id'] == projectId) {
            updateData['project_name'] = trimmedProjectName;
          }
          // If another project has this name, skip updating project_name to avoid duplicate key error
        }
      }

      // Update project basic info
      print('ProjectStorageService.saveProjectData: Updating project with data: $updateData');
      final updateResult = await _supabase
          .from('projects')
          .update(updateData)
          .eq('id', projectId)
          .eq('user_id', userId)
          .select();
      print('ProjectStorageService.saveProjectData: Update result: $updateResult');

      // Save non-sellable areas - only if explicitly provided
      if (nonSellableAreas != null) {
        await _saveNonSellableAreas(projectId, nonSellableAreas);
      }

      // Save partners - only if explicitly provided (prevents deletion when saving from other pages)
      // If partners is null, we don't touch existing partners in the database
      if (partners != null) {
        await _savePartners(projectId, partners);
      }

      // Save expenses - only if explicitly provided
      if (expenses != null) {
        await _saveExpenses(projectId, expenses);
      }

      // Save layouts and plots
      if (layouts != null) {
        await _saveLayoutsAndPlots(projectId, layouts);
      }

      // Save project managers
      if (projectManagers != null) {
        await _saveProjectManagers(projectId, projectManagers);
      }

      // Save agents
      if (agents != null) {
        await _saveAgents(projectId, agents);
      }
    } catch (e) {
      print('Error saving project data: $e');
      rethrow;
    }
  }

  static Future<void> _saveNonSellableAreas(
    String projectId,
    List<Map<String, String>> nonSellableAreas,
  ) async {
    // Delete existing non-sellable areas
    await _supabase
        .from('non_sellable_areas')
        .delete()
        .eq('project_id', projectId);

    // Insert new ones
    final areasToInsert = nonSellableAreas
        .where((area) => (area['name'] ?? '').trim().isNotEmpty)
        .map((area) => {
              'project_id': projectId,
              'name': area['name']?.trim() ?? '',
              'area': _parseDecimal(area['area']),
            })
        .toList();

    if (areasToInsert.isNotEmpty) {
      await _supabase.from('non_sellable_areas').insert(areasToInsert);
    }
  }

  static Future<void> _savePartners(
    String projectId,
    List<Map<String, dynamic>> partners,
  ) async {
    // Delete existing partners
    await _supabase.from('partners').delete().eq('project_id', projectId);

    // Insert new ones
    final partnersToInsert = partners
        .where((partner) => (partner['name']?.toString().trim() ?? '').isNotEmpty)
        .map((partner) => {
              'project_id': projectId,
              'name': partner['name']?.toString().trim() ?? '',
              'amount': _parseDecimal(partner['amount']?.toString()),
            })
        .toList();

    if (partnersToInsert.isNotEmpty) {
      await _supabase.from('partners').insert(partnersToInsert);
    }
  }

  static Future<void> _saveExpenses(
    String projectId,
    List<Map<String, dynamic>> expenses,
  ) async {
    // Delete existing expenses
    await _supabase.from('expenses').delete().eq('project_id', projectId);

    // Insert new ones - use a Set to remove duplicates based on item and category
    final seenExpenses = <String>{};
    final expensesToInsert = expenses
        .where((expense) {
          final item = (expense['item']?.toString().trim() ?? '').toString();
          final category = (expense['category']?.toString().trim() ?? '').toString();
          if (item.isEmpty || category.isEmpty) return false;
          
          // Create a unique key for this expense
          final key = '$item|$category';
          if (seenExpenses.contains(key)) {
            print('Skipping duplicate expense: item="$item", category="$category"');
            return false;
          }
          seenExpenses.add(key);
          return true;
        })
        .map((expense) => {
              'project_id': projectId,
              'item': expense['item']?.toString().trim() ?? '',
              'amount': _parseDecimal(expense['amount']?.toString()),
              'category': expense['category']?.toString().trim() ?? '',
            })
        .toList();

    if (expensesToInsert.isNotEmpty) {
      await _supabase.from('expenses').insert(expensesToInsert);
    }
  }

  static Future<void> _saveLayoutsAndPlots(
    String projectId,
    List<Map<String, dynamic>> layouts,
  ) async {
    // Get existing layouts for this project
    final existingLayouts = await _supabase
        .from('layouts')
        .select('id, name')
        .eq('project_id', projectId);

    final existingLayoutMap = <String, String>{};
    for (var layout in existingLayouts) {
      final name = (layout['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        existingLayoutMap[name] = layout['id'];
      }
    }

    // Process each layout
    for (var layoutData in layouts) {
      final layoutName = (layoutData['name'] ?? '').toString().trim();
      if (layoutName.isEmpty) continue;

      String layoutId;
      if (existingLayoutMap.containsKey(layoutName)) {
        layoutId = existingLayoutMap[layoutName]!;
      } else {
        // Check if layout already exists (handle race condition)
        try {
          final existingCheck = await _supabase
              .from('layouts')
              .select('id')
              .eq('project_id', projectId)
              .eq('name', layoutName)
              .maybeSingle();
          
          if (existingCheck != null && existingCheck['id'] != null) {
            layoutId = existingCheck['id'];
            existingLayoutMap[layoutName] = layoutId; // Update map for future reference
          } else {
            // Create new layout
            final newLayout = await _supabase
                .from('layouts')
                .insert({
                  'project_id': projectId,
                  'name': layoutName,
                })
                .select()
                .single();
            layoutId = newLayout['id'];
            existingLayoutMap[layoutName] = layoutId; // Update map for future reference
          }
        } catch (e) {
          // If insert fails due to duplicate key, try to fetch existing
          if (e.toString().contains('duplicate key') || e.toString().contains('23505')) {
            final existingCheck = await _supabase
                .from('layouts')
                .select('id')
                .eq('project_id', projectId)
                .eq('name', layoutName)
                .maybeSingle();
            if (existingCheck != null && existingCheck['id'] != null) {
              layoutId = existingCheck['id'];
              existingLayoutMap[layoutName] = layoutId;
            } else {
              print('Error: Could not find or create layout: $layoutName');
              continue; // Skip this layout
            }
          } else {
            rethrow;
          }
        }
      }

      // Get plots for this layout
      final plots = layoutData['plots'] as List<dynamic>? ?? [];

      // Delete existing plots for this layout
      await _supabase.from('plots').delete().eq('layout_id', layoutId);

      // Insert new plots with explicit timestamps to preserve order
      final baseTime = DateTime.now();
      int insertedPlotIndex = 0; // Track actual inserted plots for timestamp ordering
      for (int plotIndex = 0; plotIndex < plots.length; plotIndex++) {
        final plotData = plots[plotIndex];
        final plotNumber = (plotData['plotNumber'] ?? '').toString().trim();
        if (plotNumber.isEmpty) continue; // Skip empty plots

        try {
          final purchaseRate = plotData['purchaseRate']?.toString() ?? '0.00';
          final allInCostPerSqft = _parseDecimal(purchaseRate);
          final totalPlotCost = _parseDecimal(plotData['totalPlotCost']?.toString());
          
          // Debug logging for first plot only
          if (insertedPlotIndex == 0) {
            print('Saving plot: plotNumber=$plotNumber, purchaseRate=$purchaseRate, allInCostPerSqft=$allInCostPerSqft, totalPlotCost=$totalPlotCost');
          }
          
          // Create sequential timestamps to preserve insertion order
          // Each plot gets a timestamp slightly after the previous one
          final plotTimestamp = baseTime.add(Duration(milliseconds: insertedPlotIndex * 10));
          
          final newPlot = await _supabase
              .from('plots')
              .insert({
                'layout_id': layoutId,
                'plot_number': plotNumber,
                'area': _parseDecimal(plotData['area']?.toString()),
                'all_in_cost_per_sqft': allInCostPerSqft,
                'total_plot_cost': totalPlotCost,
                'status': plotData['status']?.toString() ?? 'available',
                'sale_price': plotData['salePrice'] != null && plotData['salePrice'].toString().trim().isNotEmpty
                    ? _parseDecimal(plotData['salePrice']?.toString())
                    : null,
                'buyer_name': plotData['buyerName'] != null && plotData['buyerName'].toString().trim().isNotEmpty
                    ? plotData['buyerName'].toString().trim()
                    : null,
                'sale_date': plotData['saleDate'] != null && plotData['saleDate'].toString().trim().isNotEmpty
                    ? _parseDate(plotData['saleDate']?.toString())
                    : null,
                'agent_name': plotData['agent'] != null && plotData['agent'].toString().trim().isNotEmpty
                    ? plotData['agent'].toString().trim()
                    : null,
                'created_at': plotTimestamp.toIso8601String(),
              })
              .select()
              .single();

          insertedPlotIndex++; // Increment only for successfully inserted plots

          final plotId = newPlot['id'];

          // Save plot partners
          final plotPartners = plotData['partners'] as List<dynamic>? ?? [];
          print('DEBUG ProjectStorageService: Saving partners for plot ${newPlot['plot_number']}: $plotPartners (${plotPartners.length} partners)');
          if (plotPartners.isNotEmpty) {
            final partnersToInsert = plotPartners
                .where((p) => p.toString().trim().isNotEmpty)
                .map((partnerName) => {
                      'plot_id': plotId,
                      'partner_name': partnerName.toString().trim(),
                    })
                .toList();

            if (partnersToInsert.isNotEmpty) {
              print('DEBUG ProjectStorageService: Inserting ${partnersToInsert.length} partners into plot_partners table');
              await _supabase.from('plot_partners').insert(partnersToInsert);
            }
          }
        } catch (e) {
          // If insert fails due to duplicate key, the plot already exists (might be from concurrent save)
          // Since we delete all plots before inserting, this shouldn't happen, but handle it gracefully
          if (e.toString().contains('duplicate key') || e.toString().contains('23505')) {
            print('Warning: Plot $plotNumber already exists in layout, trying to update instead');
            // Try to get existing plot and update it instead
            try {
              final existingPlot = await _supabase
                  .from('plots')
                  .select('id')
                  .eq('layout_id', layoutId)
                  .eq('plot_number', plotNumber)
                  .maybeSingle();
              if (existingPlot != null && existingPlot['id'] != null) {
                final purchaseRate = plotData['purchaseRate']?.toString() ?? '0.00';
                final allInCostPerSqft = _parseDecimal(purchaseRate);
                final totalPlotCost = _parseDecimal(plotData['totalPlotCost']?.toString());
                print('Updating existing plot: plotNumber=$plotNumber, purchaseRate=$purchaseRate, allInCostPerSqft=$allInCostPerSqft, totalPlotCost=$totalPlotCost');
                await _supabase
                    .from('plots')
                    .update({
                      'area': _parseDecimal(plotData['area']?.toString()),
                      'all_in_cost_per_sqft': allInCostPerSqft,
                      'total_plot_cost': totalPlotCost,
                      'status': plotData['status']?.toString() ?? 'available',
                      'sale_price': plotData['salePrice'] != null && plotData['salePrice'].toString().trim().isNotEmpty
                          ? _parseDecimal(plotData['salePrice']?.toString())
                          : null,
                      'buyer_name': plotData['buyerName'] != null && plotData['buyerName'].toString().trim().isNotEmpty
                          ? plotData['buyerName'].toString().trim()
                          : null,
                      'sale_date': plotData['saleDate'] != null && plotData['saleDate'].toString().trim().isNotEmpty
                          ? _parseDate(plotData['saleDate']?.toString())
                          : null,
                      'agent_name': plotData['agent'] != null && plotData['agent'].toString().trim().isNotEmpty
                          ? plotData['agent'].toString().trim()
                          : null,
                    })
                    .eq('id', existingPlot['id']);
              }
            } catch (updateError) {
              print('Error updating existing plot: $updateError');
            }
          } else {
            rethrow;
          }
        }
      }
    }

    // Delete layouts that are no longer in the data
    final currentLayoutNames = layouts
        .map((l) => (l['name'] ?? '').toString().trim())
        .where((n) => n.isNotEmpty)
        .toSet();
    final layoutsToDelete = existingLayoutMap.entries
        .where((e) => !currentLayoutNames.contains(e.key))
        .map((e) => e.value)
        .toList();
    
    print('_saveLayoutsAndPlots: Current layout names: $currentLayoutNames');
    print('_saveLayoutsAndPlots: Existing layout map: $existingLayoutMap');
    print('_saveLayoutsAndPlots: Layouts to delete: ${layoutsToDelete.length}');
    
    if (layoutsToDelete.isNotEmpty) {
      for (var layoutId in layoutsToDelete) {
        print('Deleting layout: $layoutId');
        await _supabase.from('layouts').delete().eq('id', layoutId);
      }
    }
  }

  static Future<void> _saveProjectManagers(
    String projectId,
    List<Map<String, dynamic>> projectManagers,
  ) async {
    print('_saveProjectManagers: Saving ${projectManagers.length} project managers for project $projectId');
    
    // Get existing project managers to determine which ones to delete later
    final existingManagers = await _supabase
        .from('project_managers')
        .select('id')
        .eq('project_id', projectId);
    final existingManagerIds = existingManagers.map((m) => m['id'] as String).toSet();
    final processedManagerIds = <String>{};

    // Upsert new/updated project managers
    final errors = <String>[];
    for (var managerData in projectManagers) {
      final name = (managerData['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        print('_saveProjectManagers: Skipping manager with empty name');
        continue;
      }

      final compensationType = managerData['compensation']?.toString();
      final earningType = managerData['earningType']?.toString();

      print('_saveProjectManagers: Processing manager "$name": compensation="$compensationType", earningType="$earningType"');

      // Convert empty strings to null, but keep valid values (including 'None')
      final finalCompensationType = (compensationType == null || compensationType.trim().isEmpty) 
          ? null 
          : compensationType.trim();
      
      // Map UI earning type values to database values
      // Map UI earning type values to DB allowed values (Per Plot, Per Square Foot, Lump Sum)
      // Constraint requires earning_type to be null for non-percentage bonus rows
      final String? finalEarningType =
          finalCompensationType == 'Percentage Bonus'
              ? _mapEarningType(earningType)
              : null;

      print('_saveProjectManagers: Mapped values: compensation_type="$finalCompensationType", earning_type="$finalEarningType"');

      final dataToUpsert = {
        'project_id': projectId,
        'name': name,
        'compensation_type': finalCompensationType,
        'earning_type': finalEarningType,
        'percentage': finalCompensationType == 'Percentage Bonus'
            ? _parseDecimal(managerData['percentage']?.toString())
            : null,
        'fixed_fee': finalCompensationType == 'Fixed Fee'
            ? _parseDecimal(managerData['fixedFee']?.toString())
            : null,
        'monthly_fee': finalCompensationType == 'Monthly Fee'
            ? _parseDecimal(managerData['monthlyFee']?.toString())
            : null,
        'months': finalCompensationType == 'Monthly Fee'
            ? _parseInt(managerData['months']?.toString())
            : null,
      };

      print('_saveProjectManagers: Data to upsert: $dataToUpsert');

      // If ID exists, add it to update existing record
      if (managerData['id'] != null) {
        dataToUpsert['id'] = managerData['id'];
      }

      try {
        final upsertedManager = await _supabase
            .from('project_managers')
            .upsert(dataToUpsert)
            .select()
            .single();
        print('_saveProjectManagers: Successfully upserted manager: $upsertedManager');

        final managerId = upsertedManager['id'] as String;
        processedManagerIds.add(managerId);

        // Save selected blocks/plots (always delete existing blocks and re-insert for this manager)
        // First delete existing blocks for this manager
        await _supabase
            .from('project_manager_blocks')
            .delete()
            .eq('project_manager_id', managerId);

        final selectedBlocks = managerData['selectedBlocks'] as List<dynamic>? ?? [];
        if (selectedBlocks.isNotEmpty) {
          // Get all layouts and plots for this project to map block strings to plot IDs
          final layouts = await _supabase
              .from('layouts')
              .select('id, name')
              .eq('project_id', projectId);
          
          final plotIdsToInsert = <String>[];
          for (var blockString in selectedBlocks) {
            final block = blockString.toString().trim();
            if (block.isEmpty) continue;
            
            // Parse block string: "Layout Name - Plot Number" or "Layout Name - Plot 1"
            final parts = block.split(' - ');
            if (parts.length != 2) continue;
            
            final layoutName = parts[0].trim();
            final plotIdentifier = parts[1].trim();
            
            // Find layout by name
            final layout = layouts.firstWhere(
              (l) => (l['name'] ?? '').toString().trim() == layoutName,
              orElse: () => <String, dynamic>{},
            );
            
            if (layout.isEmpty || layout['id'] == null) continue;
            final layoutId = layout['id'];
            
            // Find plot by layout ID and plot number
            // Handle both "Plot 1" format and actual plot numbers
            String? plotNumber;
            if (plotIdentifier.startsWith('Plot ')) {
              // Extract number from "Plot 1" format
              final plotIndexStr = plotIdentifier.replaceAll('Plot ', '').trim();
              final plotIndex = int.tryParse(plotIndexStr);
              if (plotIndex != null) {
                // Get all plots for this layout and find by index
                final plots = await _supabase
                    .from('plots')
                    .select('id')
                    .eq('layout_id', layoutId)
                    .order('plot_number');
                if (plotIndex > 0 && plotIndex <= plots.length) {
                  plotIdsToInsert.add(plots[plotIndex - 1]['id']);
                }
              }
            } else {
              // Use plot number directly
              final plots = await _supabase
                  .from('plots')
                  .select('id')
                  .eq('layout_id', layoutId)
                  .eq('plot_number', plotIdentifier);
              if (plots.isNotEmpty) {
                plotIdsToInsert.add(plots[0]['id']);
              }
            }
          }
          
          // Insert block associations
          if (plotIdsToInsert.isNotEmpty) {
            final blocksToInsert = plotIdsToInsert.map((plotId) => {
                  'project_manager_id': managerId,
                  'plot_id': plotId,
                }).toList();
            await _supabase.from('project_manager_blocks').insert(blocksToInsert);
          }
        }
      } catch (e) {
        final errorMsg = '_saveProjectManagers: Error upserting manager "$name": $e';
        print(errorMsg);
        errors.add(errorMsg);
        // Continue processing remaining managers instead of stopping
        continue;
      }
    }
    
    // Log any errors that occurred
    if (errors.isNotEmpty) {
      print('_saveProjectManagers: ${errors.length} error(s) occurred while saving managers:');
      for (var error in errors) {
        print('  - $error');
      }
    }
    
    print('_saveProjectManagers: Successfully processed ${processedManagerIds.length} managers');

    // Delete project managers that were removed (present in DB but not in processed list)
    final idsToDelete = existingManagerIds.difference(processedManagerIds);
    if (idsToDelete.isNotEmpty) {
      for (var managerId in idsToDelete) {
        // Delete blocks first
        await _supabase
            .from('project_manager_blocks')
            .delete()
            .eq('project_manager_id', managerId);
        
        // Delete manager
        await _supabase
            .from('project_managers')
            .delete()
            .eq('id', managerId);
      }
    }
  }

  static Future<void> _saveAgents(
    String projectId,
    List<Map<String, dynamic>> agents,
  ) async {
    print('_saveAgents: Saving ${agents.length} agents for project $projectId');
    
    // Get existing agents to determine which ones to delete later
    final existingAgents = await _supabase
        .from('agents')
        .select('id')
        .eq('project_id', projectId);
    final existingAgentIds = existingAgents.map((a) => a['id'] as String).toSet();
    final processedAgentIds = <String>{};

    // Upsert new/updated agents
    final errors = <String>[];
    for (var agentData in agents) {
      final name = (agentData['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        print('_saveAgents: Skipping agent with empty name');
        continue;
      }

      final compensationType = agentData['compensation']?.toString();
      final earningType = agentData['earningType']?.toString();
      final percentage = agentData['percentage']?.toString();
      final fixedFee = agentData['fixedFee']?.toString();
      final monthlyFee = agentData['monthlyFee']?.toString();
      final months = agentData['months']?.toString();
      final perSqftFee = agentData['perSqftFee']?.toString();

      print('_saveAgents: Processing agent "$name": compensation="$compensationType", earningType="$earningType", percentage="$percentage", fixedFee="$fixedFee", monthlyFee="$monthlyFee", months="$months", perSqftFee="$perSqftFee"');

      // Convert empty strings to null, but keep valid values (including 'None')
      final finalCompensationType = (compensationType == null || compensationType.trim().isEmpty) 
          ? null 
          : compensationType.trim();
      
      // Map UI earning type values to database values
      // Map UI earning type values to DB allowed values (Per Plot, Per Square Foot, Lump Sum)
      // Constraint requires earning_type to be null for non-percentage bonus rows
      final String? finalEarningType =
          finalCompensationType == 'Percentage Bonus'
              ? _mapEarningType(earningType)
              : null;

      print('_saveAgents: Mapped values: compensation_type="$finalCompensationType", earning_type="$finalEarningType"');

      final dataToUpsert = {
        'project_id': projectId,
        'name': name,
        'compensation_type': finalCompensationType,
        'earning_type': finalEarningType,
        'percentage': finalCompensationType == 'Percentage Bonus'
            ? _parseDecimal(percentage)
            : null,
        'fixed_fee': finalCompensationType == 'Fixed Fee'
            ? _parseDecimal(fixedFee)
            : null,
        'monthly_fee': finalCompensationType == 'Monthly Fee'
            ? _parseDecimal(monthlyFee)
            : null,
        'months': finalCompensationType == 'Monthly Fee'
            ? _parseInt(months)
            : null,
        'per_sqft_fee': finalCompensationType == 'Per Sqft Fee'
            ? _parseDecimal(perSqftFee)
            : null,
      };

      print('_saveAgents: Data to upsert: $dataToUpsert');

      // If ID exists, add it to update existing record
      if (agentData['id'] != null) {
        dataToUpsert['id'] = agentData['id'];
      }

      try {
        final upsertedAgent = await _supabase
            .from('agents')
            .upsert(dataToUpsert)
            .select()
            .single();
        print('_saveAgents: Successfully upserted agent: $upsertedAgent');

        final agentId = upsertedAgent['id'] as String;
        processedAgentIds.add(agentId);

        // Save selected blocks/plots (always delete existing blocks and re-insert for this agent)
        // First delete existing blocks for this agent
        await _supabase.from('agent_blocks').delete().eq('agent_id', agentId);

        final selectedBlocks = agentData['selectedBlocks'] as List<dynamic>? ?? [];
        if (selectedBlocks.isNotEmpty) {
          // Get all layouts and plots for this project to map block strings to plot IDs
          final layouts = await _supabase
              .from('layouts')
              .select('id, name')
              .eq('project_id', projectId);
          
          final plotIdsToInsert = <String>[];
          for (var blockString in selectedBlocks) {
            final block = blockString.toString().trim();
            if (block.isEmpty) continue;
            
            // Parse block string: "Layout Name - Plot Number" or "Layout Name - Plot 1"
            final parts = block.split(' - ');
            if (parts.length != 2) continue;
            
            final layoutName = parts[0].trim();
            final plotIdentifier = parts[1].trim();
            
            // Find layout by name
            final layout = layouts.firstWhere(
              (l) => (l['name'] ?? '').toString().trim() == layoutName,
              orElse: () => <String, dynamic>{},
            );
            
            if (layout.isEmpty || layout['id'] == null) continue;
            final layoutId = layout['id'];
            
            // Find plot by layout ID and plot number
            // Handle both "Plot 1" format and actual plot numbers
            String? plotNumber;
            if (plotIdentifier.startsWith('Plot ')) {
              // Extract number from "Plot 1" format
              final plotIndexStr = plotIdentifier.replaceAll('Plot ', '').trim();
              final plotIndex = int.tryParse(plotIndexStr);
              if (plotIndex != null) {
                // Get all plots for this layout and find by index
                final plots = await _supabase
                    .from('plots')
                    .select('id')
                    .eq('layout_id', layoutId)
                    .order('plot_number');
                if (plotIndex > 0 && plotIndex <= plots.length) {
                  plotIdsToInsert.add(plots[plotIndex - 1]['id']);
                }
              }
            } else {
              // Use plot number directly
              final plots = await _supabase
                  .from('plots')
                  .select('id')
                  .eq('layout_id', layoutId)
                  .eq('plot_number', plotIdentifier);
              if (plots.isNotEmpty) {
                plotIdsToInsert.add(plots[0]['id']);
              }
            }
          }
          
          // Insert block associations
          if (plotIdsToInsert.isNotEmpty) {
            final blocksToInsert = plotIdsToInsert.map((plotId) => {
                  'agent_id': agentId,
                  'plot_id': plotId,
                }).toList();
            await _supabase.from('agent_blocks').insert(blocksToInsert);
          }
        }
      } catch (e) {
        final errorMsg = '_saveAgents: Error upserting agent "$name": $e';
        print(errorMsg);
        errors.add(errorMsg);
        // Continue processing remaining agents instead of stopping
        continue;
      }
    }
    
    // Log any errors that occurred
    if (errors.isNotEmpty) {
      print('_saveAgents: ${errors.length} error(s) occurred while saving agents:');
      for (var error in errors) {
        print('  - $error');
      }
    }
    
    print('_saveAgents: Successfully processed ${processedAgentIds.length} agents');

    // Delete agents that were removed (present in DB but not in processed list)
    final idsToDelete = existingAgentIds.difference(processedAgentIds);
    if (idsToDelete.isNotEmpty) {
      for (var agentId in idsToDelete) {
        // Delete blocks first
        await _supabase.from('agent_blocks').delete().eq('agent_id', agentId);
        
        // Delete agent
        await _supabase.from('agents').delete().eq('id', agentId);
      }
    }
  }

  static double _parseDecimal(String? value) {
    if (value == null || value.trim().isEmpty) return 0.0;
    // Remove commas and other formatting
    final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  static int? _parseInt(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(cleaned);
  }

  static String? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    
    // Try to parse DD/MM/YYYY format (most common in the app)
    final ddmmyyyyPattern = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
    final match = ddmmyyyyPattern.firstMatch(trimmed);
    if (match != null) {
      final day = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final year = int.tryParse(match.group(3) ?? '');
      
      if (day != null && month != null && year != null) {
        // Validate date ranges
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31 && year >= 1000 && year <= 9999) {
          // Convert to ISO format (YYYY-MM-DD)
          return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        }
      }
    }
    
    // Try to parse YYYY-MM-DD format (ISO format - already correct)
    final isoPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (isoPattern.hasMatch(trimmed)) {
      return trimmed;
    }
    
    // If format is not recognized, return null to avoid database errors
    print('Warning: Could not parse date format: $trimmed');
    return null;
  }

  // Map any UI earning type string to one of the allowed DB values.
  // Allowed values per schema: Per Plot, Per Square Foot, Lump Sum.
  // Note: We distinguish between "Profit Per Plot" and "Selling Price Per Plot" 
  // by checking for "profit" vs "selling price" keywords.
  static String? _mapEarningType(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;

    final lower = cleaned.toLowerCase();

    // Check for "selling price per plot" first (more specific)
    if (lower.contains('selling price') && lower.contains('plot')) {
      return 'Selling Price Per Plot';
    }

    // Check for "profit per plot" or "% of profit on each sold plot"
    if (lower.contains('profit') && (lower.contains('plot') || lower.contains('sold'))) {
      return 'Profit Per Plot';
    }

    // Generic "per plot" (fallback)
    if (lower.contains('per plot')) {
      return 'Per Plot';
    }

    if (lower.contains('square foot') || lower.contains('sqft') || lower.contains('sq ft')) {
      return 'Per Square Foot';
    }

    if (lower.contains('total project profit') || lower.contains('lump') || lower.contains('project profit')) {
      return 'Lump Sum';
    }

    // If we don't recognize it, return null to avoid check constraint violations.
    print('Warning: Unrecognized earning type "$cleaned", storing as null to satisfy DB constraint');
    return null;
  }
}
