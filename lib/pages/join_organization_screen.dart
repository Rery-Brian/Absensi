import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../helpers/flushbar_helper.dart';
import '../helpers/localization_helper.dart';
import '../services/attendance_service.dart';
import '../models/attendance_model.dart';
import 'main_dashboard.dart';
import 'login.dart';

class JoinOrganizationScreen extends StatefulWidget {
  const JoinOrganizationScreen({super.key});

  @override
  State<JoinOrganizationScreen> createState() => _JoinOrganizationScreenState();
}

class _JoinOrganizationScreenState extends State<JoinOrganizationScreen> {
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color secondaryColor = Color(0xFF8B5CF6);
  
  final TextEditingController _invCodeController = TextEditingController();
  final AttendanceService _attendanceService = AttendanceService();
  
  bool _isJoining = false;
  bool _isLoadingProfile = true;
  UserProfile? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _invCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final profile = await _attendanceService.loadUserProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  String _getDisplayName() {
    final user = Supabase.instance.client.auth.currentUser;

    if (_userProfile?.displayName != null && _userProfile!.displayName!.isNotEmpty) {
      return _userProfile!.displayName!;
    }
    if (_userProfile?.fullName != null && _userProfile!.fullName!.isNotEmpty) {
      return _userProfile!.fullName!;
    }
    if (_userProfile?.firstName != null && _userProfile!.firstName!.isNotEmpty) {
      return _userProfile!.firstName!;
    }
    if (user?.email != null) {
      return user!.email!.split('@')[0];
    }
    return LocalizationHelper.getText('user');
  }

  Future<void> _joinOrganizationWithCode() async {
    final invCode = _invCodeController.text.trim();
    
    if (invCode.isEmpty) {
      FlushbarHelper.showError(
        context,
        LocalizationHelper.getText('please_enter_invitation_code'),
      );
      return;
    }

    setState(() => _isJoining = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception(LocalizationHelper.getText('user_not_authenticated'));
      }

      final orgResponse = await Supabase.instance.client
          .from('organizations')
          .select('id, name, inv_code')
          .eq('inv_code', invCode)
          .eq('is_active', true)
          .maybeSingle();

      if (orgResponse == null) {
        throw Exception('invalid_invitation_code');
      }

      final orgId = orgResponse['id'];
      final orgName = orgResponse['name'];

      final existingMember = await Supabase.instance.client
          .from('organization_members')
          .select('id')
          .eq('organization_id', orgId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingMember != null) {
        throw Exception('already_member_of_organization');
      }

      await Supabase.instance.client.from('organization_members').insert({
        'organization_id': orgId,
        'user_id': user.id,
        'hire_date': DateTime.now().toIso8601String().split('T')[0],
        'employment_status': 'active',
        'is_active': true,
      });

      if (mounted) {
        FlushbarHelper.showSuccess(
          context,
          '${LocalizationHelper.getText('successfully_joined')} $orgName',
        );
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (!mounted) return;
        
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainDashboard()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error joining organization: $e');
      if (mounted) {
        String errorMessage = LocalizationHelper.getText('failed_to_join_organization');
        
        if (e.toString().contains('invalid_invitation_code')) {
          errorMessage = LocalizationHelper.getText('invalid_invitation_code');
        } else if (e.toString().contains('already_member_of_organization')) {
          errorMessage = LocalizationHelper.getText('already_member_of_organization');
        } else {
          errorMessage = e.toString();
        }
        
        FlushbarHelper.showError(context, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _getDisplayName();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Responsive sizing
    final bool isSmallPhone = screenWidth < 360;
    final bool isMobile = screenWidth < 600;
    final bool isTablet = screenWidth >= 600 && screenWidth < 1024;
    
    final double horizontalPadding = isSmallPhone ? 16 : (isMobile ? 20 : (isTablet ? 40 : 60));
    final double verticalPadding = isSmallPhone ? 12 : 20;
    final double logoSize = isSmallPhone ? 50 : (isMobile ? 60 : 70);
    final double avatarRadius = isSmallPhone ? 32 : (isMobile ? 40 : 48);
    final double titleFontSize = isSmallPhone ? 18 : (isMobile ? 22 : 26);
    final double subtitleFontSize = isSmallPhone ? 12 : (isMobile ? 14 : 15);
    final double cardPadding = isSmallPhone ? 20 : (isMobile ? 24 : 32);
    final double maxCardWidth = isTablet ? 600 : 500;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoadingProfile
            ? Center(
                child: CircularProgressIndicator(
                  valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
                  strokeWidth: 3,
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryColor.withOpacity(0.08),
                      secondaryColor.withOpacity(0.04),
                    ],
                  ),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: logoSize,
                            height: logoSize,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [primaryColor, secondaryColor],
                              ),
                              borderRadius: BorderRadius.circular(logoSize * 0.3),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.business,
                              color: Colors.white,
                              size: logoSize * 0.53,
                            ),
                          ),
                          
                          SizedBox(height: isSmallPhone ? 16 : 24),
                          
                          Container(
                            constraints: BoxConstraints(maxWidth: maxCardWidth),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(isSmallPhone ? 20 : 24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            padding: EdgeInsets.all(cardPadding),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        primaryColor.withOpacity(0.2),
                                        secondaryColor.withOpacity(0.1),
                                      ],
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: avatarRadius,
                                    backgroundColor: Colors.transparent,
                                    backgroundImage: _userProfile?.profilePhotoUrl != null
                                        ? NetworkImage(_userProfile!.profilePhotoUrl!)
                                        : null,
                                    child: _userProfile?.profilePhotoUrl == null
                                        ? Icon(
                                            Icons.person,
                                            color: primaryColor,
                                            size: avatarRadius * 1,
                                          )
                                        : null,
                                  ),
                                ),
                                
                                SizedBox(height: isSmallPhone ? 12 : 16),
                                
                                Text(
                                  '${LocalizationHelper.getText('welcome_back')}, $displayName!',
                                  style: TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                
                                const SizedBox(height: 8),
                                
                                Text(
                                  LocalizationHelper.getText('join_organization_to_continue'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: subtitleFontSize,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                
                                SizedBox(height: isSmallPhone ? 20 : 24),
                                
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      LocalizationHelper.getText('invitation_code'),
                                      style: TextStyle(
                                        fontSize: isSmallPhone ? 13 : 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _invCodeController,
                                      enabled: !_isJoining,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: isSmallPhone ? 18 : 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: isSmallPhone ? 2 : 4,
                                        color: Colors.black87,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'ENTER-CODE',
                                        hintStyle: TextStyle(
                                          color: Colors.grey.shade400,
                                          letterSpacing: isSmallPhone ? 2 : 4,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 2,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(
                                            color: primaryColor,
                                            width: 2.5,
                                          ),
                                        ),
                                        disabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 2,
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: isSmallPhone ? 14 : 16,
                                          horizontal: isSmallPhone ? 16 : 20,
                                        ),
                                      ),
                                      textCapitalization: TextCapitalization.characters,
                                      onSubmitted: _isJoining ? null : (value) => _joinOrganizationWithCode(),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 16),
                                
                                Container(
                                  padding: EdgeInsets.all(isSmallPhone ? 10 : 12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_rounded,
                                        color: Colors.blue.shade700,
                                        size: isSmallPhone ? 18 : 20,
                                      ),
                                      SizedBox(width: isSmallPhone ? 8 : 10),
                                      Expanded(
                                        child: Text(
                                          LocalizationHelper.getText('ask_hr_for_invitation_code'),
                                          style: TextStyle(
                                            color: Colors.blue.shade900,
                                            fontSize: isSmallPhone ? 11 : 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                SizedBox(height: isSmallPhone ? 20 : 24),
                                
                                SizedBox(
                                  width: double.infinity,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [primaryColor, secondaryColor],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: primaryColor.withOpacity(0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: _isJoining ? null : _joinOrganizationWithCode,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        disabledBackgroundColor: Colors.grey.shade300,
                                        disabledForegroundColor: Colors.grey.shade600,
                                        padding: EdgeInsets.symmetric(vertical: isSmallPhone ? 14 : 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                      ),
                                      child: _isJoining
                                          ? SizedBox(
                                              width: isSmallPhone ? 20 : 24,
                                              height: isSmallPhone ? 20 : 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.business_center, size: isSmallPhone ? 18 : 20, color: Colors.white),
                                                SizedBox(width: isSmallPhone ? 8 : 10),
                                                Text(
                                                  LocalizationHelper.getText('join_organization'),
                                                  style: TextStyle(
                                                    fontSize: isSmallPhone ? 14 : 16,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.5,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
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
  }
}