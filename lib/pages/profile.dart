// screens/profile_page.dart
import 'package:absensiwajah/pages/login.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/attendance_model.dart';
import '../services/attendance_service.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback? onProfileUpdated; // Add callback parameter
  
  const ProfilePage({
    super.key,
    this.onProfileUpdated, // Add to constructor
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
      _showSnackBar('Failed to load user data', isError: true);
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
            name: response['name'] ?? 'Unknown Organization',
            code: '', countryCode: '', // Code not needed for display
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading organization info: $e');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<String?> _uploadProfileImage(File imageFile) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;

      final bytes = await imageFile.readAsBytes();
      // Use user ID as folder structure for better organization and security
      final fileName = '${user.id}/${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Delete old profile photo if exists
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
      
      // Upload new photo
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
      // Show source selection dialog
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
              const Text(
                'Select Photo Source',
                style: TextStyle(
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
                            const Text('Camera'),
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
                            const Text('Gallery'),
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
                child: const Text('Cancel'),
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

        // Upload image immediately
        final imageUrl = await _uploadProfileImage(_selectedImage!);
        
        if (imageUrl != null) {
          // Update profile photo URL in database
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            await Supabase.instance.client
                .from('user_profiles')
                .update({
                  'profile_photo_url': imageUrl,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', user.id);
            
            // Reload user data to reflect changes
            await _loadUserData();
            _showSnackBar('Profile photo updated successfully!');
            
            // Call the callback to notify parent widget
            if (widget.onProfileUpdated != null) {
              debugPrint('Calling profile update callback');
              widget.onProfileUpdated!();
            }
          }
        } else {
          _showSnackBar('Failed to upload image', isError: true);
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (e.toString().contains('channel-error')) {
        _showSnackBar('Image picker not available. Please check app permissions.', isError: true);
      } else {
        _showSnackBar('Failed to pick image. Please try again.', isError: true);
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

      // Update user_profiles table
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

      // Refresh user data
      await _loadUserData();
      
      setState(() {
        _isEditMode = false;
      });

      _showSnackBar('Profile updated successfully!');
      
      // Call the callback to notify parent widget about profile update
      if (widget.onProfileUpdated != null) {
        debugPrint('Calling profile update callback after saving profile');
        widget.onProfileUpdated!();
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      _showSnackBar('Failed to update profile: $e', isError: true);
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
    _populateControllers(); // Reset form data
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

  /// ====== LOGOUT FUNCTION ======
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
        _showSnackBar('Failed to logout: $e', isError: true);
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
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
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
    // Use display_name from user profile instead of parsing email
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
              const SizedBox(height: 100), // Space for bottom navigation
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
          colors: [backgroundColor, backgroundColor.withValues(alpha: 0.8)],
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
          // Header title
          const Text(
            'Profile',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          // Profile photo with edit functionality
          Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.orange.shade400,
                // Add timestamp to prevent caching issues
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
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            email,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
          if (_organization != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
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
              color: Colors.black.withValues(alpha: 0.1),
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
              // Header with action buttons
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Personal Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (!_isEditMode)
                      // Edit button with better styling
                      OutlinedButton.icon(
                        onPressed: _toggleEditMode,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit'),
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
              // Action buttons when in edit mode
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
                          child: const Text('Cancel'),
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
                                  children: const [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Saving...'),
                                  ],
                                )
                              : const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              // Profile fields
              _buildProfileField(
                icon: Icons.person_outline,
                title: 'Display Name',
                controller: _fullNameController,
                currentValue: _userProfile?.displayName ?? _userProfile?.fullName ?? 'Not provided',
                isEditable: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Display name is required';
                  }
                  return null;
                },
              ),
              _buildProfileField(
                icon: Icons.phone_outlined,
                title: 'Phone Number',
                controller: _phoneController,
                currentValue: _userProfile?.phone ?? 'Not provided',
                isEditable: true,
                keyboardType: TextInputType.phone,
              ),
              _buildGenderField(),
              _buildDateOfBirthField(),
              _buildProfileField(
                icon: Icons.badge_outlined,
                title: 'Employee ID',
                controller: null,
                currentValue: _organizationMember?.employeeId ?? 'Not assigned',
                isEditable: false,
              ),
              _buildProfileField(
                icon: Icons.work_outline,
                title: 'Position',
                controller: null,
                currentValue: _organizationMember?.position?.title ?? 'Not specified',
                isEditable: false,
              ),
              _buildProfileField(
                icon: Icons.business_outlined,
                title: 'Department',
                controller: null,
                currentValue: _organizationMember?.department?.name ?? 'Not specified',
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
    final genderDisplay = _selectedGender == 'male' ? 'Male' : 'Female';

    return InkWell(
      onTap: canEdit ? null : ((){
        if (!_isEditMode) _toggleEditMode();
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.person_pin,
                color: primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gender',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (canEdit) ...[
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Male'),
                            value: 'male',
                            groupValue: _selectedGender,
                            activeColor: primaryColor,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) {
                              setState(() {
                                _selectedGender = value!;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Female'),
                            value: 'female',
                            groupValue: _selectedGender,
                            activeColor: primaryColor,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) {
                              setState(() {
                                _selectedGender = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      genderDisplay,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!canEdit)
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateOfBirthField() {
    final canEdit = _isEditMode;
    final dateDisplay = _selectedDateOfBirth != null
        ? '${_selectedDateOfBirth!.day}/${_selectedDateOfBirth!.month}/${_selectedDateOfBirth!.year}'
        : 'Not provided';

    return InkWell(
      onTap: canEdit ? _selectDate : ((){
        if (!_isEditMode) _toggleEditMode();
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.cake_outlined,
                color: primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Date of Birth',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateDisplay,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              canEdit ? Icons.calendar_today : Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
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
  }) {
    final canEdit = _isEditMode && isEditable && controller != null;
    final showTapIndicator = !_isEditMode && (onTap != null || (isEditable && controller != null));

    return InkWell(
      onTap: canEdit ? null : (onTap ?? (_isEditMode ? null : (isEditable ? _toggleEditMode : null))),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: isLast ? null : Border(
            bottom: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (canEdit) ...[
                    // Improved text field styling for edit mode
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextFormField(
                        controller: controller,
                        keyboardType: keyboardType,
                        validator: validator,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: primaryColor, width: 2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      currentValue,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showTapIndicator)
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: const Text(
              'Account Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          _buildMenuItem(
            icon: Icons.security_outlined,
            title: 'Security',
            subtitle: 'Password and authentication',
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Manage your notification preferences',
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.language_outlined,
            title: 'Language',
            subtitle: 'English (Default)',
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.dark_mode_outlined,
            title: 'Appearance',
            subtitle: 'Theme and display settings',
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: const Text(
              'Support & Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          _buildMenuItem(
            icon: Icons.help_outline,
            title: 'Help Center',
            subtitle: 'Get help and find answers',
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.contact_support_outlined,
            title: 'Contact Support',
            subtitle: 'Get in touch with our team',
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.info_outline,
            title: 'About',
            subtitle: 'App version and information',
            onTap: () => _showAboutDialog(context),
          ),
          _buildMenuItem(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'Learn how we protect your data',
            onTap: () => _showComingSoon(context),
          ),
          _buildMenuItem(
            icon: Icons.article_outlined,
            title: 'Terms of Service',
            subtitle: 'Read our terms and conditions',
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _buildMenuItem(
        icon: Icons.logout,
        title: 'Logout',
        subtitle: 'Sign out from your account',
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
          border: isLast ? null : Border(
            bottom: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (iconColor ?? primaryColor).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor ?? primaryColor,
                size: 20,
              ),
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
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
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
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.schedule,
                color: primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Coming Soon'),
          ],
        ),
        content: const Text(
          'This feature is currently under development and will be available in a future update.',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: primaryColor,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: const Text('OK'),
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
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.info_outline,
                color: primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('About This App'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Attendance App v1.0.0',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'This app helps you manage your attendance and organization-related tasks with ease.',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: primaryColor,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
}