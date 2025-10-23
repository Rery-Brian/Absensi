import 'package:flutter/material.dart';
import 'package:absensiwajah/pages/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../helpers/localization_helper.dart';

final supabase = Supabase.instance.client;

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Theme colors matching dashboard and login
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  // Function untuk split nama menjadi first_name dan last_name
  Map<String, String> _splitName(String fullName) {
    List<String> nameParts = fullName.trim().split(' ').where((n) => n.isNotEmpty).toList();
    
    if (nameParts.isEmpty) {
      return {'first_name': 'User', 'last_name': ''};
    } else if (nameParts.length == 1) {
      return {'first_name': nameParts[0], 'last_name': ''};
    } else {
      String firstName = nameParts[0];
      String lastName = nameParts.sublist(1).join(' ');
      return {'first_name': firstName, 'last_name': lastName};
    }
  }

 // Function untuk create user profile setelah signup
Future<bool> _createUserProfile(String userId, String fullName, String email) async {
  try {
    print('Creating user profile for: $userId');
    
    final nameParts = _splitName(fullName);
    final firstName = nameParts['first_name']!;
    final lastName = nameParts['last_name']!;
    
    // Wait a bit untuk memastikan trigger selesai
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Check apakah profile sudah ada dari trigger
    final existingProfile = await supabase
        .from('user_profiles')
        .select('id, email')
        .eq('id', userId)
        .maybeSingle();

    if (existingProfile != null) {
      // Update profile yang sudah dibuat oleh trigger, ALWAYS include email
      print('Updating existing profile created by trigger...');
      await supabase
          .from('user_profiles')
          .update({
            'first_name': firstName,
            'last_name': lastName,
            'display_name': fullName,
            'email': email,  // Always update email
            'is_active': true,
          })
          .eq('id', userId);
    } else {
      // Create new profile jika trigger gagal
      print('Creating new user profile...');
      await supabase
          .from('user_profiles')
          .insert({
            'id': userId,
            'first_name': firstName,
            'last_name': lastName,
            'display_name': fullName,
            'email': email,  // Include email
            'is_active': true,
          });
    }

    print('User profile created/updated successfully with email: $email');
    return true;
  } catch (e) {
    print('Error creating user profile: $e');
    return false;
  }
}

  // Function untuk menampilkan dialog
  void _showDialog({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  color: isSuccess ? Colors.green : Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(LocalizationHelper.getText('ok')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showDialog(
        title: LocalizationHelper.getText('registration_failed'),
        message: LocalizationHelper.getText('name_email_password_required'),
        isSuccess: false,
      );
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showDialog(
        title: LocalizationHelper.getText('registration_failed'),
        message: LocalizationHelper.getText('invalid_email_format'),
        isSuccess: false,
      );
      return;
    }

    if (password.length < 6) {
      _showDialog(
        title: LocalizationHelper.getText('registration_failed'),
        message: LocalizationHelper.getText('password_min_6_characters'),
        isSuccess: false,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Sign up dengan metadata nama
      final AuthResponse res = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          'display_name': name,
        },
      );

      if (res.user != null) {
        print('Signup successful, user ID: ${res.user!.id}');
        
        // Create/update user profile
        final profileSuccess = await _createUserProfile(
          res.user!.id,
          name,
          email,
        );

        if (!profileSuccess) {
          print('Warning: Failed to create user profile');
        }

        if (mounted) {
          _showSuccessDialog();
        }
      } else {
        if (mounted) {
          _showDialog(
            title: LocalizationHelper.getText('registration_failed'),
            message: LocalizationHelper.getText('failed_create_account'),
            isSuccess: false,
          );
        }
      }
    } catch (e) {
      String errorMessage;

      if (e.toString().contains('already registered')) {
        errorMessage = LocalizationHelper.getText('email_already_registered');
      } else if (e.toString().contains('invalid email')) {
        errorMessage = LocalizationHelper.getText('invalid_email_format');
      } else if (e.toString().contains('weak password')) {
        errorMessage = LocalizationHelper.getText('password_too_weak');
      } else {
        errorMessage = e.toString();
      }

      if (mounted) {
        _showDialog(
          title: LocalizationHelper.getText('error'),
          message: errorMessage,
          isSuccess: false,
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

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 30,
                    horizontal: 20,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          size: 40,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        LocalizationHelper.getText('registration_successful'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        LocalizationHelper.getText('account_created_successfully'),
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _nameController.clear();
                      _emailController.clear();
                      _passwordController.clear();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const Login()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      LocalizationHelper.getText('continue_to_login'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    final isSmallScreen = size.width < 360;

    double headerHeight = isLandscape
        ? 180.0
        : (isSmallScreen ? size.height * 0.30 : size.height * 0.35);

    double logoSize = isLandscape ? 50 : (isSmallScreen ? 70 : 80);
    double titleFontSize = isLandscape ? 20 : (isSmallScreen ? 24 : 28);
    double cardTopOffset = isLandscape ? -15 : -20;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                height: headerHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      backgroundColor,
                      backgroundColor.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: isLandscape ? 10 : 20),
                    Container(
                      width: logoSize,
                      height: logoSize,
                      padding: EdgeInsets.all(logoSize * 0.2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Image(
                        image: AssetImage("images/logo.png"),
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: isLandscape ? 8 : 16),
                    Text(
                      "Absensi",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: titleFontSize,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Form card
              Transform.translate(
                offset: Offset(0, cardTopOffset),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildSignupForm(
                    isSmallScreen: isSmallScreen,
                    isLandscape: isLandscape,
                  ),
                ),
              ),

              if (isLandscape) const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignupForm({
    required bool isSmallScreen,
    required bool isLandscape,
  }) {
    double welcomeFontSize = isLandscape ? 16 : (isSmallScreen ? 18 : 20);
    double labelFontSize = isLandscape ? 11 : (isSmallScreen ? 12 : 13);
    double hintFontSize = isLandscape ? 12 : (isSmallScreen ? 13 : 14);
    double buttonFontSize = isLandscape ? 13 : (isSmallScreen ? 14 : 15);
    double dividerFontSize = isLandscape ? 10 : (isSmallScreen ? 11 : 12);
    double cardPadding = isLandscape ? 14 : (isSmallScreen ? 16 : 20);

    double verticalSpacing = isLandscape ? 6 : (isSmallScreen ? 8 : 10);
    double sectionSpacing = isLandscape ? 8 : (isSmallScreen ? 12 : 15);
    double buttonVerticalPadding = isLandscape ? 8 : (isSmallScreen ? 10 : 12);

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            LocalizationHelper.getText('create_account'),
            style: TextStyle(
              fontSize: welcomeFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: isLandscape ? 2 : 4),
          Text(
            LocalizationHelper.getText('fill_in_your_details'),
            style: TextStyle(
              fontSize: hintFontSize,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: sectionSpacing + (isLandscape ? 0 : 5)),

          // Name Field
          _buildTextField(
            controller: _nameController,
            label: LocalizationHelper.getText('full_name'),
            hint: LocalizationHelper.getText('enter_your_full_name'),
            icon: Icons.person_outline,
            labelFontSize: labelFontSize,
            hintFontSize: hintFontSize,
            isLandscape: isLandscape,
          ),
          SizedBox(height: verticalSpacing),

          // Email Field
          _buildTextField(
            controller: _emailController,
            label: LocalizationHelper.getText('email'),
            hint: LocalizationHelper.getText('enter_your_email'),
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            labelFontSize: labelFontSize,
            hintFontSize: hintFontSize,
            isLandscape: isLandscape,
          ),
          SizedBox(height: verticalSpacing),

          // Password Field
          _buildTextField(
            controller: _passwordController,
            label: LocalizationHelper.getText('password'),
            hint: LocalizationHelper.getText('enter_your_password'),
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            labelFontSize: labelFontSize,
            hintFontSize: hintFontSize,
            isLandscape: isLandscape,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.grey.shade500,
                size: isLandscape ? 18 : 20,
              ),
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
            ),
          ),
          SizedBox(height: sectionSpacing),

          // Create Account Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: buttonVerticalPadding),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? SizedBox(
                      width: isLandscape ? 16 : 18,
                      height: isLandscape ? 16 : 18,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      LocalizationHelper.getText('create_account'),
                      style: TextStyle(
                        fontSize: buttonFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),

          // Loading indicator
          if (_isLoading) ...[
            SizedBox(height: verticalSpacing),
            Container(
              padding: EdgeInsets.all(
                isLandscape ? 6 : (isSmallScreen ? 8 : 10),
              ),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: isLandscape ? 12 : 14,
                    height: isLandscape ? 12 : 14,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                  ),
                  SizedBox(width: isLandscape ? 8 : 10),
                  Expanded(
                    child: Text(
                      LocalizationHelper.getText('creating_account'),
                      style: TextStyle(
                        fontSize: dividerFontSize,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Login Link
          Padding(
            padding: EdgeInsets.only(
              top: isLandscape ? 8 : (isSmallScreen ? 12 : 16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  LocalizationHelper.getText('already_have_account'),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: hintFontSize,
                  ),
                ),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const Login()),
                          );
                        },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isLandscape ? 2 : 4,
                    ),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    LocalizationHelper.getText('sign_in'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                      fontSize: hintFontSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required double labelFontSize,
    required double hintFontSize,
    required bool isLandscape,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelFontSize,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: isLandscape ? 4 : 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          enabled: !_isLoading,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: hintFontSize,
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            prefixIcon: Icon(
              icon,
              color: Colors.grey.shade500,
              size: isLandscape ? 18 : 20,
            ),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: primaryColor, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 10 : 12,
              vertical: isLandscape ? 10 : 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}