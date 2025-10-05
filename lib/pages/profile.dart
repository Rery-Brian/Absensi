// screens/profile_page.dart
import 'package:absensiwajah/pages/login.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/attendance_model.dart';
import '../services/attendance_service.dart';
import '../helpers/flushbar_helper.dart';
import '../helpers/localization_helper.dart'; // ADD THIS

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
  bool _isLoading = true;

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

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _userProfile = await _attendanceService.loadUserProfile();
      _populateControllers();
      
      if (_userProfile != null) {
        _organizationMember = await _attendanceService.loadOrganizationMember();
        
        if (_organizationMember != null) {
          await _loadOrganizationInfo();
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

  // === LANGUAGE DIALOG ===
  Future<void> _showLanguageDialog() async {
    final currentLang = LocalizationHelper.currentLanguage;
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.language, color: primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(LocalizationHelper.getText('language')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLanguageOption('id', 'Indonesia', '🇮🇩', currentLang == 'id'),
              const SizedBox(height: 12),
              _buildLanguageOption('en', 'English', '🇬🇧', currentLang == 'en'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LocalizationHelper.getText('cancel')),
            ),
          ],
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
          setState(() {}); // Rebuild with new language
          FlushbarHelper.showSuccess(
            context,
            'Language changed to $name',
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
                            Text(LocalizationHelper.currentLanguage == 'id' ? 'Kamera' : 'Camera'),
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
                            Text(LocalizationHelper.currentLanguage == 'id' ? 'Galeri' : 'Gallery'),
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
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            await Supabase.instance.client
                .from('user_profiles')
                .update({
                  'profile_photo_url': imageUrl,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', user.id);
            
            await _loadUserData();
            
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
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await Supabase.instance.client
          .from('user_profiles')
          .update({
            'display_name': _fullNameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'gender': _selectedGender,
            'date_of_birth': _selectedDateOfBirth?.toIso8601String().split('T')[0],
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      await _loadUserData();
      
      setState(() {
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
      return Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
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
        onRefresh: _loadUserData,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(displayName, email),
              _buildProfileInfo(context),
              if (!_isEditMode) ...[
                _buildAccountSection(context),
                _buildSupportSection(context),
                _buildLogoutSection(context),
              ],
              const SizedBox(height: 100),
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
          Text(
            LocalizationHelper.getText('profile'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              email,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
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
                  Text(
                    _organization!.name,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
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

  Widget _buildGenderField() {
    final canEdit = _isEditMode;
    final genderDisplay = _selectedGender == 'male' 
        ? LocalizationHelper.getText('male')
        : LocalizationHelper.getText('female');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
        ? '${_selectedDateOfBirth!.day}/${_selectedDateOfBirth!.month}/${_selectedDateOfBirth!.year}'
        : LocalizationHelper.getText('not_provided');
    return InkWell(
      onTap: canEdit ? _selectDate : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
            icon: Icons.security_outlined,
            title: LocalizationHelper.getText('security'),
            subtitle: LocalizationHelper.getText('password_and_authentication'),
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.notifications_outlined,
            title: LocalizationHelper.getText('notifications'),
            subtitle: LocalizationHelper.getText('manage_notification_preferences'),
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.language_outlined,
            title: LocalizationHelper.getText('language'),
            subtitle: LocalizationHelper.currentLanguage == 'en' 
                ? 'English' 
                : 'Indonesia',
            onTap: () => _showLanguageDialog(),
          ),
          _buildMenuItem(
            icon: Icons.dark_mode_outlined,
            title: LocalizationHelper.getText('appearance'),
            subtitle: LocalizationHelper.getText('theme_and_display'),
            onTap: () => _showComingSoon(context),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSupportSection(BuildContext context) {
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
              LocalizationHelper.getText('support_information'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          _buildMenuItem(
            icon: Icons.help_outline,
            title: LocalizationHelper.getText('help_center'),
            subtitle: LocalizationHelper.getText('get_help_and_answers'),
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.contact_support_outlined,
            title: LocalizationHelper.getText('contact_support'),
            subtitle: LocalizationHelper.getText('contact_our_team'),
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.info_outline,
            title: LocalizationHelper.getText('about'),
            subtitle: LocalizationHelper.getText('app_version_info'),
            onTap: () => _showAboutDialog(context),
          ),
          _buildMenuItem(
            icon: Icons.privacy_tip_outlined,
            title: LocalizationHelper.getText('privacy_policy'),
            subtitle: LocalizationHelper.getText('learn_data_protection'),
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.article_outlined,
            title: LocalizationHelper.getText('terms_of_service'),
            subtitle: LocalizationHelper.getText('read_terms_and_conditions'),
            onTap: () => _showComingSoon(context),
            isLast: true,
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

  void _showComingSoon(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.schedule, color: primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            Text(LocalizationHelper.getText('coming_soon')),
          ],
        ),
        content: Text(LocalizationHelper.getText('feature_under_development')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocalizationHelper.getText('ok')),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.info_outline, color: primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            Text(LocalizationHelper.getText('about_this_app')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              LocalizationHelper.getText('attendance_app_version'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text(LocalizationHelper.getText('app_description')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocalizationHelper.getText('close').toUpperCase()),
          ),
        ],
      ),
    );
  }
}