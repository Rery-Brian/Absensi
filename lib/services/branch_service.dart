// services/branch_service.dart - Fixed version with proper type handling
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/branch_model.dart';

class BranchService {
  final SupabaseClient _supabase = Supabase.instance.client;
  Branch? _selectedBranch;
  
  static const String _selectedBranchKey = 'selected_branch_id';

  Branch? get selectedBranch => _selectedBranch;

  /// Load all branches for the given organization
  Future<List<Branch>> loadBranches(String organizationId) async {
    try {
      final response = await _supabase
          .from('branches')
          .select('*')
          .eq('organization_id', int.parse(organizationId)) // Parse to int for database query
          .eq('is_active', true)
          .order('name');

      final branches = List<Map<String, dynamic>>.from(response)
          .map((json) => Branch.fromJson(json))
          .toList();

      return branches;
    } catch (e) {
      throw Exception('Error loading branches: $e');
    }
  }

  /// Load a specific branch by ID
  Future<Branch?> loadBranchById(String branchId) async {
    try {
      final response = await _supabase
          .from('branches')
          .select('*')
          .eq('id', int.parse(branchId)) // Parse to int for database query
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        return Branch.fromJson(response);
      }
      return null;
    } catch (e) {
      throw Exception('Error loading branch: $e');
    }
  }

  /// Set the selected branch and save to preferences
  Future<void> setSelectedBranch(Branch branch) async {
    try {
      _selectedBranch = branch;
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedBranchKey, branch.id);
    } catch (e) {
      throw Exception('Error setting selected branch: $e');
    }
  }

  /// Load the previously selected branch from preferences
  Future<Branch?> loadSelectedBranch(String organizationId) async {
    try {
      // Try to get from memory first
      if (_selectedBranch != null && _selectedBranch!.organizationId == organizationId) {
        return _selectedBranch;
      }

      // Load from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedBranchId = prefs.getString(_selectedBranchKey);
      
      if (savedBranchId != null) {
        final branch = await loadBranchById(savedBranchId);
        if (branch != null && branch.organizationId == organizationId) {
          _selectedBranch = branch;
          return branch;
        } else {
          // Clean up invalid selection
          await clearSelectedBranch();
        }
      }

      return null;
    } catch (e) {
      throw Exception('Error loading selected branch: $e');
    }
  }

  /// Clear the selected branch
  Future<void> clearSelectedBranch() async {
    try {
      _selectedBranch = null;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_selectedBranchKey);
    } catch (e) {
      throw Exception('Error clearing selected branch: $e');
    }
  }

  /// Check if a branch selection is required for the organization
  Future<bool> isSelectionRequired(String organizationId) async {
    try {
      final branches = await loadBranches(organizationId);
      
      // If there are multiple branches, selection is required
      if (branches.length > 1) {
        return true;
      }
      
      // If there's exactly one branch, auto-select it
      if (branches.length == 1) {
        await setSelectedBranch(branches.first);
        return false;
      }
      
      // No branches available - selection required (will show error)
      return true;
    } catch (e) {
      throw Exception('Error checking selection requirement: $e');
    }
  }

  /// Get the default branch (first available branch) for auto-selection
  Future<Branch?> getDefaultBranch(String organizationId) async {
    try {
      final branches = await loadBranches(organizationId);
      return branches.isNotEmpty ? branches.first : null;
    } catch (e) {
      throw Exception('Error getting default branch: $e');
    }
  }

  /// Check if current selected branch is still valid
  Future<bool> validateSelectedBranch() async {
    if (_selectedBranch == null) return false;
    
    try {
      final branch = await loadBranchById(_selectedBranch!.id);
      if (branch == null || !branch.isActive) {
        await clearSelectedBranch();
        return false;
      }
      return true;
    } catch (e) {
      await clearSelectedBranch();
      return false;
    }
  }

  /// Load branches with additional filtering options
  Future<List<Branch>> loadBranchesWithFilter({
    required String organizationId,
    bool? isActive,
    String? searchQuery,
  }) async {
    try {
      var query = _supabase
          .from('branches')
          .select('*')
          .eq('organization_id', int.parse(organizationId));

      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('name.ilike.%$searchQuery%,code.ilike.%$searchQuery%');
      }

      final response = await query.order('name');

      final branches = List<Map<String, dynamic>>.from(response)
          .map((json) => Branch.fromJson(json))
          .toList();

      return branches;
    } catch (e) {
      throw Exception('Error loading branches with filter: $e');
    }
  }

  /// Check if user has access to specific branch
  Future<bool> hasAccessToBranch(String branchId, String userId) async {
    try {
      // This would depend on your access control logic
      // For now, assume all users have access to all branches in their organization
      final branch = await loadBranchById(branchId);
      return branch != null && branch.isActive;
    } catch (e) {
      return false;
    }
  }

  /// Get branch statistics
  Future<Map<String, dynamic>> getBranchStats(String branchId) async {
    try {
      // Get basic branch info
      final branch = await loadBranchById(branchId);
      if (branch == null) {
        throw Exception('Branch not found');
      }

      // You can add more statistics here based on your needs
      // For example: member count, attendance records, etc.
      
      return {
        'id': branch.id,
        'name': branch.name,
        'code': branch.code,
        'has_coordinates': branch.hasValidCoordinates,
        'radius_meters': branch.radiusMeters,
        'is_active': branch.isActive,
        'created_at': branch.createdAt.toIso8601String(),
        'updated_at': branch.updatedAt.toIso8601String(),
      };
    } catch (e) {
      throw Exception('Error getting branch stats: $e');
    }
  }

  /// Refresh selected branch data
  Future<void> refreshSelectedBranch() async {
    if (_selectedBranch == null) return;
    
    try {
      final refreshedBranch = await loadBranchById(_selectedBranch!.id);
      if (refreshedBranch != null) {
        _selectedBranch = refreshedBranch;
      } else {
        await clearSelectedBranch();
      }
    } catch (e) {
      throw Exception('Error refreshing selected branch: $e');
    }
  }
}