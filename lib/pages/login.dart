import 'package:absensiwajah/pages/join_organization_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'signup.dart';
import 'main_dashboard.dart';
import '../helpers/localization_helper.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

final supabase = Supabase.instance.client;

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Theme colors matching dashboard
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  // Function untuk extract nama dari email
  String _extractNameFromEmail(String email) {
    try {
      String namePart = email.split('@')[0];
      namePart = namePart.replaceAll(RegExp(r'[_.\-0-9]'), ' ').trim();
      
      List<String> words = namePart.split(' ').where((w) => w.isNotEmpty).toList();
      String capitalizedName = words
          .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
          .join(' ')
          .trim();
      
      return capitalizedName.isEmpty ? email.split('@')[0] : capitalizedName;
    } catch (e) {
      debugPrint('Error extracting name from email: $e');
      return email.split('@')[0];
    }
  }

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

  // Function untuk check apakah user profile sudah ada dan lengkap
  Future<Map<String, dynamic>?> _checkUserProfile(String userId) async {
    try {
      debugPrint('Checking user profile for ID: $userId');

      final response = await supabase
          .from('user_profiles')
          .select('id, first_name, last_name, display_name')
          .eq('id', userId)
          .maybeSingle();

      debugPrint('User profile data: $response');
      return response;
    } catch (e) {
      debugPrint('Error checking user profile: $e');
      return null;
    }
  }

 // Function untuk create atau update user profile
Future<bool> _ensureUserProfile(String userId, String email, {String? googleName}) async {
  try {
    debugPrint('Ensuring user profile for: $userId');
    
    final existingProfile = await _checkUserProfile(userId);
    
    String fullName;
    if (googleName != null && googleName.isNotEmpty) {
      fullName = googleName;
      debugPrint('Using Google name: $fullName');
    } else {
      fullName = _extractNameFromEmail(email);
      debugPrint('Extracted name from email: $fullName');
    }
    
    final nameParts = _splitName(fullName);
    final firstName = nameParts['first_name']!;
    final lastName = nameParts['last_name']!;
    final displayName = fullName;

    if (existingProfile == null) {
      debugPrint('Creating new user profile...');
      
      final response = await supabase
          .from('user_profiles')
          .insert({
            'id': userId,
            'first_name': firstName,
            'last_name': lastName,
            'display_name': displayName,
            'email': email,  // Include email
            'is_active': true,
          })
          .select()
          .single();

      debugPrint('User profile created: $response');
      return true;
    } else {
      // Check if update is needed (name or email)
      final needsUpdate = existingProfile['first_name'] == null || 
                         existingProfile['first_name'].toString().isEmpty ||
                         existingProfile['first_name'] == 'User' ||
                         existingProfile['email'] == null ||
                         existingProfile['email'].toString().isEmpty;

      if (needsUpdate) {
        debugPrint('Updating existing user profile...');
        
        final response = await supabase
            .from('user_profiles')
            .update({
              'first_name': firstName,
              'last_name': lastName,
              'display_name': displayName,
              'email': email,  // Always update email
            })
            .eq('id', userId)
            .select();

        debugPrint('User profile updated: $response');
      } else {
        debugPrint('User profile already complete, skipping update');
      }
      
      return true;
    }
  } catch (e) {
    debugPrint('Error ensuring user profile: $e');
    return false;
  }
}
  // Function untuk check apakah user sudah punya organisasi
  Future<bool> _userHasOrganization(String userId) async {
    try {
      debugPrint('Checking if user has organization...');

      final response = await supabase
          .from('organization_members')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        debugPrint('User already has organization');
        return true;
      } else {
        debugPrint('User does not have organization');
        return false;
      }
    } catch (e) {
      debugPrint('Error checking user organization: $e');
      return false;
    }
  }

  // Function untuk navigate ke halaman yang sesuai
  Future<void> _navigateAfterLogin(BuildContext context, String userId) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
        ),
      ),
    );

    try {
      final hasOrganization = await _userHasOrganization(userId);
      
      if (!mounted) return;
      Navigator.of(context).pop();
      
      if (!mounted) return;

      if (hasOrganization) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainDashboard()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const JoinOrganizationScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error checking organization: $e');
      
      if (!mounted) return;
      
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      _showDialog(
        title: LocalizationHelper.getText('error'),
        message: '${LocalizationHelper.getText('failed_to_check_location')}: ${e.toString()}',
        isSuccess: false,
      );
    }
  }

  Future<void> _nativeGoogleSignIn() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      const webClientId =
          '210380129521-4qnge4hlqjphmjahj79d4tv5h67gjc5s.apps.googleusercontent.com';

      const androidClientId =
          '210380129521-9qcqse1mqa96aqo6liereotg82bquv8d.apps.googleusercontent.com';

      final googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        clientId: androidClientId,
        scopes: ['email', 'profile'],
      );

      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final googleAuth = await googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw Exception(LocalizationHelper.getText('google_signin_no_token'));
      }

      debugPrint('Google User: ${googleUser.email}');
      debugPrint('Google Display Name: ${googleUser.displayName}');

      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );

      if (response.user != null) {
        debugPrint('Google login successful, user ID: ${response.user!.id}');

        final profileSuccess = await _ensureUserProfile(
          response.user!.id,
          response.user!.email!,
          googleName: googleUser.displayName,
        );

        if (!profileSuccess) {
          debugPrint('Warning: Failed to ensure user profile, but continuing');
        }

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', response.user!.email!);

        if (!mounted) return;

        _navigateAfterLogin(context, response.user!.id);
      } else {
        throw Exception(LocalizationHelper.getText('google_signin_failed'));
      }
    } catch (e) {
      debugPrint('Google Sign-in Error: $e');
      if (!mounted) return;
      _showDialog(
        title: LocalizationHelper.getText('google_signin_error'),
        message: '${LocalizationHelper.getText('google_signin_failed')}: ${e.toString()}',
        isSuccess: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void signIn() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showDialog(
        title: LocalizationHelper.getText('login_failed'),
        message: LocalizationHelper.getText('email_password_required'),
        isSuccess: false,
      );
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showDialog(
        title: LocalizationHelper.getText('login_failed'),
        message: LocalizationHelper.getText('invalid_email_format'),
        isSuccess: false,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = res.user;
      if (user != null) {
        debugPrint('Email login successful, user ID: ${user.id}');

        final profileSuccess = await _ensureUserProfile(
          user.id,
          user.email!,
        );

        if (!profileSuccess) {
          debugPrint('Warning: Failed to ensure user profile, but continuing');
        }

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', user.email!);

        if (!mounted) return;

        _navigateAfterLogin(context, user.id);
      } else {
        if (!mounted) return;
        _showDialog(
          title: LocalizationHelper.getText('login_failed'),
          message: LocalizationHelper.getText('incorrect_email_or_password'),
          isSuccess: false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showDialog(
        title: LocalizationHelper.getText('error'), 
        message: e.toString(), 
        isSuccess: false
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

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
    double subtitleFontSize = isLandscape ? 11 : (isSmallScreen ? 13 : 14);
    double cardTopOffset = isLandscape ? -15 : -20;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
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
              Transform.translate(
                offset: Offset(0, cardTopOffset),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildLoginForm(
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

  Widget _buildLoginForm({
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
            LocalizationHelper.getText('welcome_back'),
            style: TextStyle(
              fontSize: welcomeFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: isLandscape ? 2 : 4),
          Text(
            LocalizationHelper.getText('sign_in_to_continue'),
            style: TextStyle(
              fontSize: hintFontSize,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: sectionSpacing + (isLandscape ? 2 : 5)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _nativeGoogleSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                disabledBackgroundColor: Colors.grey.shade100,
                side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                padding: EdgeInsets.symmetric(
                  vertical: buttonVerticalPadding + 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? SizedBox(
                      width: isLandscape ? 18 : 20,
                      height: isLandscape ? 18 : 20,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/logo/logo_google.png',
                          height: isLandscape ? 18 : 20,
                          width: isLandscape ? 18 : 20,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: isLandscape ? 18 : 20,
                              height: isLandscape ? 18 : 20,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: Colors.grey.shade300,
                              ),
                              child: Icon(
                                Icons.g_mobiledata,
                                size: isLandscape ? 16 : 18,
                                color: Colors.grey.shade600,
                              ),
                            );
                          },
                        ),
                        SizedBox(width: isLandscape ? 10 : 12),
                        Text(
                          LocalizationHelper.getText('continue_with_google'),
                          style: TextStyle(
                            fontSize: buttonFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          SizedBox(height: sectionSpacing),
          Row(
            children: [
              Expanded(
                child: Divider(thickness: 1, color: Colors.grey.shade300),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isLandscape ? 8 : 12),
                child: Text(
                  LocalizationHelper.getText('or_sign_in_with_email'),
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: dividerFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Divider(thickness: 1, color: Colors.grey.shade300),
              ),
            ],
          ),
          SizedBox(height: sectionSpacing),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: buttonVerticalPadding),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
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
                      LocalizationHelper.getText('sign_in'),
                      style: TextStyle(
                        fontSize: buttonFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              top: isLandscape ? 6 : (isSmallScreen ? 10 : 12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  LocalizationHelper.getText('dont_have_account'),
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
                            MaterialPageRoute(builder: (_) => const Signup()),
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
                    LocalizationHelper.getText('sign_up'),
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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}