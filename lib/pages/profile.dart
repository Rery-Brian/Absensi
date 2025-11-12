// screens/profile_page.dart - Updated with clean layout
import 'package:absensiwajah/pages/login.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/attendance_model.dart';
import '../services/attendance_service.dart';
import '../helpers/flushbar_helper.dart';
import '../helpers/localization_helper.dart';
import 'profile_skeleton_widgets.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback? onProfileUpdated;
  
  const ProfilePage({
    super.key,
    this.onProfileUpdated,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AttendanceService _attendanceService = AttendanceService();
  
  UserProfile? _userProfile;
  OrganizationMember? _organizationMember;
  Organization? _organization;
  MemberSchedule? _currentSchedule;
  List<WorkSchedule> _availableSchedules = [];
  WorkSchedule? _selectedSchedule;
  bool _isLoading = true;
  bool _isLoadingSchedules = false;

  // Form controllers for editing
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameController;
  late TextEditingController _phoneController;
  late TextEditingController _mobileController;
  String _selectedGender = 'male';
  DateTime? _selectedDateOfBirth;
  File? _selectedImage;
  bool _isEditMode = false;
  bool _isSaving = false;
  bool _isUploadingImage = false;

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadUserData();
  }

  void _initializeControllers() {
    _fullNameController = TextEditingController();
    _phoneController = TextEditingController();
    _mobileController = TextEditingController();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  void _populateControllers() {
    _fullNameController.text = _userProfile?.displayName ?? _userProfile?.fullName ?? '';
    _phoneController.text = _userProfile?.phone ?? '';
    _mobileController.text = _userProfile?.mobile ?? '';
    _selectedGender = _userProfile?.gender ?? 'male';
    _selectedDateOfBirth = _userProfile?.dateOfBirth;
  }

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // ✅ OPTIMIZATION: Gunakan cache dari service, atau force refresh jika diperlukan
      _userProfile = await _attendanceService.loadUserProfile(forceRefresh: forceRefresh);
      _populateControllers();
      
      if (_userProfile != null) {
        _organizationMember = await _attendanceService.loadOrganizationMember(forceRefresh: forceRefresh);
        
        if (_organizationMember != null) {
          await _loadOrganizationInfo();
          await _loadCurrentSchedule();
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_load'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadOrganizationInfo() async {
    if (_organizationMember == null) return;

    try {
      final response = await Supabase.instance.client
          .from('organizations')
          .select('id, name, logo_url')
          .eq('id', _organizationMember!.organizationId)
          .single();

      if (response != null && mounted) {
        setState(() {
          _organization = Organization(
            id: response['id'].toString(),
            name: response['name'] ?? LocalizationHelper.getText('unknown_organization'),
            code: '', 
            countryCode: '',
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading organization info: $e');
    }
  }

  Future<void> _loadCurrentSchedule() async {
    if (_organizationMember == null) return;

    try {
      _currentSchedule = await _attendanceService.loadCurrentSchedule(
        _organizationMember!.id
      );
      
      if (_currentSchedule?.workScheduleId != null) {
        _selectedSchedule = _currentSchedule!.workSchedule;
      }
      
      setState(() {});
    } catch (e) {
      debugPrint('Error loading current schedule: $e');
    }
  }

  Future<void> _loadAvailableSchedules() async {
    if (_organizationMember == null) return;

    setState(() {
      _isLoadingSchedules = true;
    });

    try {
      final response = await Supabase.instance.client
          .from('work_schedules')
          .select('*')
          .eq('organization_id', _organizationMember!.organizationId)
          .eq('is_active', true)
          .order('name');

      if (response != null) {
        _availableSchedules = (response as List)
            .map((json) => WorkSchedule.fromJson(json))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading schedules: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.currentLanguage == 'id'
              ? 'Gagal memuat jadwal kerja'
              : 'Failed to load work schedules',
        );
      }
    } finally {
      setState(() {
        _isLoadingSchedules = false;
      });
    }
  }

  Future<void> _showScheduleSelectionDialog() async {
    await _loadAvailableSchedules();

    if (_availableSchedules.isEmpty) {
      FlushbarHelper.showError(
        context,
        LocalizationHelper.currentLanguage == 'id'
            ? 'Tidak ada jadwal kerja tersedia'
            : 'No work schedules available',
      );
      return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
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
                              LocalizationHelper.currentLanguage == 'id'
                                  ? 'Pilih Jadwal Kerja'
                                  : 'Select Work Schedule',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              LocalizationHelper.currentLanguage == 'id'
                                  ? 'Pilih jadwal kerja Anda'
                                  : 'Choose your work schedule',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isLoadingSchedules)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: _availableSchedules.map((schedule) {
                            final isSelected = _selectedSchedule?.id == schedule.id;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildScheduleOption(
                                schedule,
                                isSelected,
                              ),
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
      },
    );
  }

  Widget _buildScheduleOption(WorkSchedule schedule, bool isSelected) {
    return InkWell(
      onTap: () async {
        await _updateMemberSchedule(schedule);
        if (mounted) {
          Navigator.pop(context);
        }
      },
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
                Icons.calendar_today,
                color: isSelected ? primaryColor : Colors.grey.shade600,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? primaryColor : Colors.black87,
                    ),
                  ),
                  if (schedule.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      schedule.description!,
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
                      Icon(
                        Icons.assignment,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        schedule.code,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: primaryColor, size: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _updateMemberSchedule(WorkSchedule schedule) async {
    if (_organizationMember == null) return;

    try {
      setState(() {
        _isSaving = true;
      });

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Check if there's an existing active schedule
      if (_currentSchedule != null && _currentSchedule!.id != 'default') {
        // End the current schedule
        await Supabase.instance.client
            .from('member_schedules')
            .update({
              'end_date': today,
              'is_active': false,
            })
            .eq('id', _currentSchedule!.id);
      }

      // Insert new schedule
      await Supabase.instance.client
          .from('member_schedules')
          .insert({
            'organization_member_id': _organizationMember!.id,
            'work_schedule_id': schedule.id,
            'effective_date': today,
            'is_active': true,
          });

      // ✅ OPTIMIZATION: Invalidate schedule cache setelah update
      _attendanceService.invalidateScheduleCache(_organizationMember!.id);
      
      // Reload schedule dengan force refresh
      await _loadCurrentSchedule();

      if (mounted) {
        setState(() {
          _selectedSchedule = schedule;
        });

        FlushbarHelper.showSuccess(
          context,
          LocalizationHelper.currentLanguage == 'id'
              ? 'Jadwal kerja berhasil diperbarui'
              : 'Work schedule updated successfully',
        );

        if (widget.onProfileUpdated != null) {
          widget.onProfileUpdated!();
        }
      }
    } catch (e) {
      debugPrint('Error updating schedule: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.currentLanguage == 'id'
              ? 'Gagal memperbarui jadwal kerja'
              : 'Failed to update work schedule',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showLanguageDialog() async {
    final currentLang = LocalizationHelper.currentLanguage;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
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
                        child: const Icon(Icons.language, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LocalizationHelper.getText('language'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              LocalizationHelper.getText('choose_your_preferred_language'),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildLanguageOption('en', 'English', '🇬🇧', currentLang == 'en'),
                  const SizedBox(height: 12),
                  _buildLanguageOption('id', 'Indonesia', '🇮🇩', currentLang == 'id'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLanguageOption(String code, String name, String flag, bool isSelected) {
    return InkWell(
      onTap: () async {
        await LocalizationHelper.setLanguage(code);
        if (mounted) {
          Navigator.pop(context);
          setState(() {}); // ✅ Rebuild profile page
          // ✅ Notify callback untuk refresh halaman lain (dashboard)
          if (widget.onProfileUpdated != null) {
            widget.onProfileUpdated!();
          }
          FlushbarHelper.showSuccess(
            context,
            LocalizationHelper.getText('language_changed_successfully'),
          );
        }
      },
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
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? primaryColor : Colors.black87,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: primaryColor, size: 24),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadProfileImage(File imageFile) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;

      final bytes = await imageFile.readAsBytes();
      final fileName = '${user.id}/${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      if (_userProfile?.profilePhotoUrl != null) {
        try {
          final oldFileName = _userProfile!.profilePhotoUrl!
              .split('/profile-photos/profiles')[1];
          await Supabase.instance.client.storage
              .from('profile-photos/profiles')
              .remove([oldFileName]);
        } catch (e) {
          debugPrint('Could not delete old photo: $e');
        }
      }
      
      await Supabase.instance.client.storage
          .from('profile-photos/profiles')
          .uploadBinary(fileName, bytes, 
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      final imageUrl = Supabase.instance.client.storage
          .from('profile-photos/profiles')
          .getPublicUrl(fileName);

      return imageUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _pickImage() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                LocalizationHelper.currentLanguage == 'id' 
                    ? 'Pilih Sumber Foto' 
                    : 'Select Photo Source',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.pop(context, ImageSource.camera),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 32,
                              color: primaryColor,
                            ),
                            const SizedBox(height: 8),
                            Text(LocalizationHelper.getText('camera')),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.pop(context, ImageSource.gallery),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.photo_library_outlined,
                              size: 32,
                              color: primaryColor,
                            ),
                            const SizedBox(height: 8),
                            Text(LocalizationHelper.getText('gallery')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(LocalizationHelper.getText('cancel')),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _isUploadingImage = true;
        });

        final imageUrl = await _uploadProfileImage(_selectedImage!);
        
        if (imageUrl != null) {
          // ✅ OPTIMIZATION: Gunakan service method yang otomatis invalidate cache
          final updatedProfile = await _attendanceService.updateUserProfile(
            profilePhotoUrl: imageUrl,
          );
          
          if (updatedProfile != null) {
            setState(() {
              _userProfile = updatedProfile;
            });
            
            if (mounted) {
              FlushbarHelper.showSuccess(
                context,
                LocalizationHelper.getText('photo_updated'),
              );
            }
            
            if (widget.onProfileUpdated != null) {
              widget.onProfileUpdated!();
            }
          }
        } else {
          if (mounted) {
            FlushbarHelper.showError(
              context,
              LocalizationHelper.currentLanguage == 'id'
                  ? 'Gagal mengunggah gambar'
                  : 'Failed to upload image',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.currentLanguage == 'id'
              ? 'Gagal memilih gambar'
              : 'Failed to pick image',
        );
      }
    } finally {
      setState(() {
        _isUploadingImage = false;
        _selectedImage = null;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // ✅ OPTIMIZATION: Gunakan service method yang otomatis invalidate cache
      final updatedProfile = await _attendanceService.updateUserProfile(
        displayName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        gender: _selectedGender,
        dateOfBirth: _selectedDateOfBirth,
      );

      if (updatedProfile != null) {
        setState(() {
          _userProfile = updatedProfile;
          _populateControllers();
          _isEditMode = false;
        });

        if (mounted) {
          FlushbarHelper.showSuccess(
            context,
            LocalizationHelper.getText('profile_updated'),
          );
        }
        
        if (widget.onProfileUpdated != null) {
          widget.onProfileUpdated!();
        }
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_update')}: $e',
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (_isEditMode) {
        _populateControllers();
      }
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditMode = false;
    });
    _populateControllers();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateOfBirth ?? DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _selectedDateOfBirth = picked;
      });
    }
  }

  Future<void> _performLogout() async {
    try {
      await _attendanceService.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const Login()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_load')}: $e',
        );
      }
    }
  }

  Future<void> _showLogoutConfirmation(BuildContext context) async {
    if (!mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(LocalizationHelper.getText('confirm_logout')),
          content: Text(LocalizationHelper.getText('are_you_sure_logout')),
          actions: <Widget>[
            TextButton(
              child: Text(LocalizationHelper.getText('cancel')),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                LocalizationHelper.getText('logout'),
                style: const TextStyle(color: Colors.white),
              ),
              onPressed: () async {
                Navigator.of(context).pop(); 
                await _performLogout(); 
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return ProfileSkeletonWidgets.buildFullPageSkeleton();
    }

    if (_isSaving) {
      return Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              ProfileSkeletonWidgets.buildSkeletonHeader(),
              ProfileSkeletonWidgets.buildSkeletonEditMode(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    }

    final user = Supabase.instance.client.auth.currentUser;
    final displayName = _userProfile?.displayName ?? _userProfile?.fullName ?? user?.email?.split('@')[0] ?? 'User';
    final email = user?.email ?? 'No email';

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: RefreshIndicator(
        onRefresh: () => _loadUserData(forceRefresh: true), // ✅ Force refresh saat pull to refresh
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(displayName, email),
              _buildProfileInfo(context),
              if (!_isEditMode) ...[
                _buildScheduleSection(context),
                _buildAccountSection(context),
                _buildLogoutSection(context),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String displayName, String email) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [backgroundColor, backgroundColor.withOpacity(0.8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.orange.shade400,
                backgroundImage: _userProfile?.profilePhotoUrl != null
                    ? NetworkImage('${_userProfile!.profilePhotoUrl!}?t=${DateTime.now().millisecondsSinceEpoch}')
                    : null,
                child: _userProfile?.profilePhotoUrl == null
                    ? const Icon(Icons.person, color: Colors.white, size: 50)
                    : null,
              ),
              if (_isUploadingImage)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                right: 0,
                child: InkWell(
                  onTap: _isUploadingImage ? null : _pickImage,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              email,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ),
          if (_organization != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.business,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _organization!.name,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileInfo(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      LocalizationHelper.getText('personal_information'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (!_isEditMode)
                      OutlinedButton.icon(
                        onPressed: _toggleEditMode,
                        icon: const Icon(Icons.edit, size: 16),
                        label: Text(LocalizationHelper.getText('edit')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: BorderSide(color: primaryColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      ),
                  ],
                ),
              ),
              if (_isEditMode)
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : _cancelEdit,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey[600],
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(LocalizationHelper.getText('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(LocalizationHelper.getText('saving')),
                                  ],
                                )
                              : Text(LocalizationHelper.getText('save_changes')),
                        ),
                      ),
                    ],
                  ),
                ),
              _buildProfileField(
                icon: Icons.person_outline,
                title: LocalizationHelper.getText('display_name'),
                controller: _fullNameController,
                currentValue: _userProfile?.displayName ?? _userProfile?.fullName ?? LocalizationHelper.getText('not_provided'),
                isEditable: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return LocalizationHelper.currentLanguage == 'id' 
                        ? 'Nama tampilan wajib diisi'
                        : 'Display name is required';
                  }
                  if (value.trim().length > 20) {
                    return LocalizationHelper.currentLanguage == 'id'
                        ? 'Nama tampilan maksimal 20 karakter'
                        : 'Display name maximum 20 characters';
                  }
                  return null;
                },
                maxLength: 20,
              ),
              _buildProfileField(
                icon: Icons.phone_outlined,
                title: LocalizationHelper.getText('phone_number'),
                controller: _phoneController,
                currentValue: _userProfile?.phone ?? LocalizationHelper.getText('not_provided'),
                isEditable: true,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty && value.trim().length > 12) {
                    return LocalizationHelper.currentLanguage == 'id'
                        ? 'Nomor telepon maksimal 12 karakter'
                        : 'Phone number maximum 12 characters';
                  }
                  return null;
                },
                maxLength: 12,
              ),
              _buildGenderField(),
              _buildDateOfBirthField(),
              _buildProfileField(
                icon: Icons.badge_outlined,
                title: LocalizationHelper.getText('employee_id'),
                controller: null,
                currentValue: _organizationMember?.employeeId ?? LocalizationHelper.getText('not_assigned'),
                isEditable: false,
              ),
              _buildProfileField(
                icon: Icons.work_outline,
                title: LocalizationHelper.getText('position'),
                controller: null,
                currentValue: _organizationMember?.position?.title ?? LocalizationHelper.getText('not_specified'),
                isEditable: false,
              ),
              _buildProfileField(
                icon: Icons.business_outlined,
                title: LocalizationHelper.getText('department'),
                controller: null,
                currentValue: _organizationMember?.department?.name ?? LocalizationHelper.getText('not_specified'),
                isEditable: false,
                isLast: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Text(
              LocalizationHelper.currentLanguage == 'id'
                  ? 'Jadwal Kerja'
                  : 'Work Schedule',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          _buildScheduleMenuItem(),
        ],
      ),
    );
  }

  Widget _buildScheduleMenuItem() {
    final scheduleName = _selectedSchedule?.name ?? 
        (_currentSchedule?.shift?.name ?? 
        LocalizationHelper.getText('not_set'));
    
    final scheduleSubtitle = _selectedSchedule?.description ?? 
        LocalizationHelper.getText('tap_to_select_work_schedule');

    return InkWell(
      onTap: _showScheduleSelectionDialog,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.calendar_today, color: primaryColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scheduleName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    scheduleSubtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderField() {
    final canEdit = _isEditMode;
    final genderDisplay = _selectedGender == 'male' 
        ? LocalizationHelper.getText('male')
        : LocalizationHelper.getText('female');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.person_pin, color: primaryColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocalizationHelper.getText('gender'),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                if (canEdit)
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text(LocalizationHelper.getText('male')),
                          value: 'male',
                          groupValue: _selectedGender,
                          activeColor: primaryColor,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _selectedGender = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text(LocalizationHelper.getText('female')),
                          value: 'female',
                          groupValue: _selectedGender,
                          activeColor: primaryColor,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _selectedGender = v!),
                        ),
                      ),
                    ],
                  )
                else
                  Text(genderDisplay, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateOfBirthField() {
    final canEdit = _isEditMode;
    final dateDisplay = _selectedDateOfBirth != null
        ? '${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}/${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}/${_selectedDateOfBirth!.year}'
        : LocalizationHelper.getText('not_provided');
    return InkWell(
      onTap: canEdit ? _selectDate : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.cake_outlined, color: primaryColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocalizationHelper.getText('date_of_birth'),
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(dateDisplay, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(canEdit ? Icons.calendar_today : Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileField({
    required IconData icon,
    required String title,
    TextEditingController? controller,
    required String currentValue,
    required bool isEditable,
    VoidCallback? onTap,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool isLast = false,
    int? maxLength,
  }) {
    final canEdit = _isEditMode && isEditable && controller != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primaryColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                if (canEdit)
                  TextFormField(
                    controller: controller,
                    keyboardType: keyboardType,
                    validator: validator,
                    maxLength: maxLength,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      counterText: maxLength != null ? '' : null,
                    ),
                  )
                else
                  Text(currentValue, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Text(
              LocalizationHelper.getText('account_settings'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          _buildMenuItem(
            icon: Icons.language_outlined,
            title: LocalizationHelper.getText('language'),
            subtitle: LocalizationHelper.currentLanguage == 'en' 
                ? LocalizationHelper.getText('english')
                : LocalizationHelper.getText('indonesian'),
            onTap: () => _showLanguageDialog(),
          ),
          _buildMenuItem(
            icon: Icons.info_outline,
            title: LocalizationHelper.getText('about'),
            subtitle: LocalizationHelper.getText('app_version_info'),
            onTap: () => _showAboutDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: _buildMenuItem(
        icon: Icons.logout,
        title: LocalizationHelper.getText('logout'),
        subtitle: LocalizationHelper.getText('sign_out_account'),
        onTap: () => _showLogoutConfirmation(context),
        textColor: Colors.red,
        iconColor: Colors.red,
        isLast: true,
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (iconColor ?? primaryColor).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor ?? primaryColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor ?? Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    final horizontalPadding = screenWidth * 0.06;
    final titleFontSize = screenWidth < 360 ? 16.0 : 18.0;
    final contentFontSize = screenWidth < 360 ? 14.0 : 16.0;
    final descriptionFontSize = screenWidth < 360 ? 13.0 : 14.0;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: screenHeight * 0.05,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: screenHeight * 0.7,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(screenWidth < 360 ? 16.0 : 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: screenWidth < 360 ? 36 : 40,
                        height: screenWidth < 360 ? 36 : 40,
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.info_outline,
                          color: primaryColor,
                          size: screenWidth < 360 ? 18 : 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          LocalizationHelper.getText('about_this_app'),
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth < 360 ? 16 : 20),
                  Container(
                    width: screenWidth < 360 ? 60 : 70,
                    height: screenWidth < 360 ? 60 : 70,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.face_retouching_natural,
                      size: screenWidth < 360 ? 32 : 40,
                      color: primaryColor,
                    ),
                  ),
                  SizedBox(height: screenWidth < 360 ? 12 : 16),
                  Text(
                    LocalizationHelper.getText('attendance_app_version'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: contentFontSize,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: primaryColor.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      'v1.0.0',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: descriptionFontSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(height: screenWidth < 360 ? 16 : 20),
                  Text(
                    LocalizationHelper.getText('app_description'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: descriptionFontSize,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: screenWidth < 360 ? 20 : 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: screenWidth < 360 ? 12 : 14,
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        LocalizationHelper.getText('close').toUpperCase(),
                        style: TextStyle(
                          fontSize: descriptionFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
}