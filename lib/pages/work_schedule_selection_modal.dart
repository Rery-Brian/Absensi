import 'package:flutter/material.dart';
import '../models/attendance_model.dart';
import '../helpers/localization_helper.dart';
import '../helpers/flushbar_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkScheduleSelectionModal extends StatefulWidget {
  final String organizationId;
  final String organizationName;
  final bool isRequired;

  const WorkScheduleSelectionModal({
    super.key,
    required this.organizationId,
    required this.organizationName,
    this.isRequired = false,
  });

  @override
  State<WorkScheduleSelectionModal> createState() => _WorkScheduleSelectionModalState();
}

class _WorkScheduleSelectionModalState extends State<WorkScheduleSelectionModal> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<WorkSchedule> _workSchedules = [];
  List<Shift> _shifts = [];
  List<dynamic> _allItems = []; // Combined list for display
  
  WorkSchedule? _selectedWorkSchedule;
  Shift? _selectedShift;
  bool _isLoading = true;
  bool _isSaving = false;
  String _selectedType = 'work_schedule'; // 'work_schedule' or 'shift'

  static const Color primaryColor = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    try {
      setState(() => _isLoading = true);

      // Load work schedules and shifts in parallel
      final results = await Future.wait([
        _supabase
            .from('work_schedules')
            .select('*')
            .eq('organization_id', widget.organizationId)
            .eq('is_active', true)
            .order('name'),
        _supabase
            .from('shifts')
            .select('*')
            .eq('organization_id', widget.organizationId)
            .eq('is_active', true)
            .order('name'),
      ]);

      final workSchedulesData = results[0] as List;
      final shiftsData = results[1] as List;

      setState(() {
        _workSchedules = workSchedulesData
            .map((json) => WorkSchedule.fromJson(json))
            .toList();
        _shifts = shiftsData
            .map((json) => Shift.fromJson(json))
            .toList();
        
        // Combine for display
        _allItems = [..._workSchedules, ..._shifts];
        _isLoading = false;
      });

      debugPrint('Loaded ${_workSchedules.length} work schedules and ${_shifts.length} shifts');
    } catch (e) {
      debugPrint('Error loading schedules: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_load')} ${LocalizationHelper.getText('work_schedule')}: $e',
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectSchedule(dynamic item) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      if (item is WorkSchedule) {
        _selectedWorkSchedule = item;
        _selectedShift = null;
        _selectedType = 'work_schedule';
      } else if (item is Shift) {
        _selectedShift = item;
        _selectedWorkSchedule = null;
        _selectedType = 'shift';
      }
    });

    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final user = _supabase.auth.currentUser;
      
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Get organization member ID
      final memberResponse = await _supabase
          .from('organization_members')
          .select('id')
          .eq('user_id', user.id)
          .eq('organization_id', widget.organizationId)
          .eq('is_active', true)
          .maybeSingle();

      if (memberResponse == null) {
        throw Exception('Organization member not found');
      }

      final organizationMemberId = memberResponse['id'].toString();

      // Check if there's an existing active schedule
      final existingSchedule = await _supabase
          .from('member_schedules')
          .select('id')
          .eq('organization_member_id', organizationMemberId)
          .lte('effective_date', today)
          .or('end_date.is.null,end_date.gte.$today')
          .eq('is_active', true)
          .maybeSingle();

      if (existingSchedule != null && existingSchedule['id'] != 'default' && existingSchedule['id'] != 'default_shift') {
        // End the current schedule
        await _supabase
            .from('member_schedules')
            .update({
              'end_date': today,
              'is_active': false,
            })
            .eq('id', existingSchedule['id']);
      }

      // Insert new schedule
      final Map<String, dynamic> insertData = {
        'organization_member_id': organizationMemberId,
        'effective_date': today,
        'is_active': true,
      };

      if (item is WorkSchedule) {
        insertData['work_schedule_id'] = int.parse(item.id);
        // Don't set shift_id, let it be null in database
      } else if (item is Shift) {
        insertData['shift_id'] = int.parse(item.id);
        // Don't set work_schedule_id, let it be null in database
      }

      await _supabase.from('member_schedules').insert(insertData);

      await Future.delayed(const Duration(milliseconds: 400));

      if (mounted) {
        Navigator.of(context).pop({
          'success': true,
          'workSchedule': _selectedWorkSchedule,
          'shift': _selectedShift,
          'type': _selectedType,
        });
      }
    } catch (e) {
      debugPrint('Error selecting schedule: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_save')} ${LocalizationHelper.getText('work_schedule')}: $e',
        );
      }
      setState(() {
        _selectedWorkSchedule = null;
        _selectedShift = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatTime(String timeString) {
    try {
      if (timeString.contains(':')) {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute = int.tryParse(parts[1]) ?? 0;
          return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        }
      }
      return timeString;
    } catch (e) {
      return timeString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColor.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.schedule, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LocalizationHelper.getText('select_work_schedule'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          LocalizationHelper.getText('choose_your_work_schedule'),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.isRequired)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop({'success': false}),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_allItems.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      LocalizationHelper.getText('no_schedules_available'),
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: _allItems.map((item) {
                        final isSelected = (item is WorkSchedule && _selectedWorkSchedule?.id == item.id) ||
                            (item is Shift && _selectedShift?.id == item.id);
                        final isSaving = _isSaving && isSelected;
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildScheduleOption(item, isSelected, isSaving),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleOption(dynamic item, bool isSelected, bool isSaving) {
    final isWorkSchedule = item is WorkSchedule;
    final isShift = item is Shift;

    return InkWell(
      onTap: isSaving ? null : () => _selectSchedule(item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? primaryColor.withOpacity(0.05) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected 
                    ? primaryColor.withOpacity(0.2)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isWorkSchedule ? Icons.calendar_today : Icons.access_time,
                color: isSelected ? primaryColor : Colors.grey.shade600,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? primaryColor : Colors.black87,
                          ),
                        ),
                      ),
                      if (isSaving)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (isSelected)
                        Icon(Icons.check_circle, color: primaryColor, size: 24),
                    ],
                  ),
                  if (item.description != null && item.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isWorkSchedule ? Colors.blue : Colors.orange).shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isWorkSchedule
                              ? LocalizationHelper.getText('work_schedule')
                              : LocalizationHelper.getText('shift'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: (isWorkSchedule ? Colors.blue : Colors.orange).shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.assignment,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.code,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      if (isShift) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.schedule,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatTime(item.startTime)} - ${_formatTime(item.endTime)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
