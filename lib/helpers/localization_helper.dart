// helpers/localization_helper.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationHelper {
  static const String _languageKey = 'selected_language';
  static const String defaultLanguage = 'id'; // Indonesian sebagai default

  static String _currentLanguage = defaultLanguage;

  static String get currentLanguage => _currentLanguage;

  // Load saved language preference
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentLanguage = prefs.getString(_languageKey) ?? defaultLanguage;
      debugPrint('Language initialized: $_currentLanguage');
    } catch (e) {
      debugPrint('Error initializing language: $e');
      _currentLanguage = defaultLanguage;
    }
  }

  // Save language preference
  static Future<void> setLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, languageCode);
      _currentLanguage = languageCode;
      debugPrint('Language changed to: $languageCode');
    } catch (e) {
      debugPrint('Error saving language: $e');
    }
  }

  // Get text based on current language
  static String getText(String key) {
    return _translations[_currentLanguage]?[key] ??
        _translations[defaultLanguage]?[key] ??
        key;
  }

  // Translations map
  static final Map<String, Map<String, String>> _translations = {
    'id': _indonesianTranslations,
    'en': _englishTranslations,
  };

  // Indonesian translations
  static final Map<String, String> _indonesianTranslations = {
    // Main Dashboard
    'verifying_organization': 'Memverifikasi organisasi...',
    'home': 'Beranda',
    'report': 'Laporan',
    'profile': 'Profil',

    // Months
    'january': 'Januari',
    'february': 'Februari',
    'march': 'Maret',
    'april': 'April',
    'may': 'Mei',
    'june': 'Juni',
    'july': 'Juli',
    'august': 'Agustus',
    'september': 'September',
    'october': 'Oktober',
    'november': 'November',
    'december': 'Desember',

    // Month abbreviations
    'jan': 'Jan',
    'feb': 'Feb',
    'mar': 'Mar',
    'apr': 'Apr',
    'may_short': 'Mei',
    'jun': 'Jun',
    'jul': 'Jul',
    'aug': 'Agu',
    'sep': 'Sep',
    'oct': 'Okt',
    'nov': 'Nov',
    'dec': 'Des',

    // Days of week
    'monday': 'Senin',
    'tuesday': 'Selasa',
    'wednesday': 'Rabu',
    'thursday': 'Kamis',
    'friday': 'Jumat',
    'saturday': 'Sabtu',
    'sunday': 'Minggu',

    // Day abbreviations
    'mon': 'Sen',
    'tue': 'Sel',
    'wed': 'Rab',
    'thu': 'Kam',
    'fri': 'Jum',
    'sat': 'Sab',
    'sun': 'Min',

    // Date/Time related
    'select_month_year': 'Pilih Bulan & Tahun',
    'apply': 'Terapkan',
    'year': 'Tahun',
    'month': 'Bulan',
    'day': 'Hari',
    'today': 'Hari Ini',
    'yesterday': 'Kemarin',
    'tomorrow': 'Besok',

    'work_time': 'Waktu Kerja',
    'work_period': 'Waktu Kerja',
    'break_time': 'Waktu Istirahat',
    'break_period': 'Waktu Istirahat',
    // Common
    'ok': 'OK',
    'cancel': 'Batal',
    'save': 'Simpan',
    'edit': 'Ubah',
    'delete': 'Hapus',
    'confirm': 'Konfirmasi',
    'close': 'Tutup',
    'refresh': 'Muat Ulang',
    'loading': 'Memuat...',
    'error': 'Kesalahan',
    'success': 'Berhasil',
    'warning': 'Peringatan',
    'info': 'Informasi',
    'retry': 'Coba Lagi',
    'continue': 'Lanjutkan',

    // Login & Auth
    'login': 'Masuk',
    'signup': 'Daftar',
    'logout': 'Keluar',
    'email': 'Email',
    'password': 'Kata Sandi',
    'full_name': 'Nama Lengkap',
    'welcome_back': 'Selamat Datang Kembali',
    'sign_in_to_continue': 'Masuk untuk melanjutkan',
    'create_account': 'Buat Akun',
    'already_have_account': 'Sudah punya akun?',
    'dont_have_account': 'Belum punya akun?',
    'sign_in': 'Masuk',
    'sign_up': 'Daftar',
    'continue_with_google': 'Lanjutkan dengan Google',
    'or_sign_in_with_email': 'atau masuk dengan email',
    'enter_your_email': 'Masukkan email Anda',
    'enter_your_password': 'Masukkan kata sandi Anda',
    'enter_your_full_name': 'Masukkan nama lengkap Anda',
    'smart_attendance_system': 'Sistem Absensi Pintar',
    'registration_successful': 'Pendaftaran Berhasil!',
    'account_created_successfully': 'Akun Anda telah berhasil dibuat',
    'continue_to_login': 'Lanjutkan ke Login',
    'fill_in_your_details': 'Isi detail Anda untuk memulai',
    'processing': 'Memproses...',
    'creating_account': 'Membuat akun Anda...',
    'confirm_logout': 'Konfirmasi Keluar',
    'are_you_sure_logout': 'Apakah Anda yakin ingin keluar?',

    // Dashboard
    'hello': 'Halo',
    'ready_to_start': 'Siap untuk memulai',
    'currently_working': 'Sedang bekerja',
    'on_break': 'Sedang istirahat',
    'ready_to_check_in_again': 'Siap untuk check in lagi',
    'waiting_for_status': 'Menunggu status...',
    'overview': 'Ringkasan',
    'presence': 'Kehadiran',
    'absence': 'Ketidakhadiran',
    'lateness': 'Keterlambatan',
    'todays_schedule': 'Jadwal Hari Ini',
    'no_schedule_available': 'Tidak ada jadwal untuk hari ini',
    'check_in': 'Check In',
    'check_out': 'Check Out',
    'break': 'Istirahat',
    'start_work_day': 'Mulai hari kerja',
    'end_work_day': 'Akhiri hari kerja',
    'take_a_break': 'Ambil istirahat',
    'completed': 'Selesai',
    'available_now': 'Tersedia sekarang',
    'not_yet_available': 'Belum tersedia',
    'getting_location': 'Mendapatkan lokasi Anda...',
    'location_not_configured': 'Lokasi absensi belum dikonfigurasi',
    'select_location': 'Pilih Lokasi',
    'no_location': 'Tidak Ada Lokasi',
    'field_work': 'Kerja Lapangan',
    'office': 'Kantor',
    'gps_not_required': 'GPS tidak diperlukan',
    'ready': 'Siap',
    'move_closer': 'Silakan bergerak lebih dekat ke lokasi absensi',
    'checking': 'Memeriksa...',
    'check_again': 'Periksa Lagi',
    'organization_member_not_found': 'Data anggota organisasi tidak ditemukan.',

    // NEW: Dashboard Status & Location
    'field_work_in': 'Kerja lapangan di',
    'field_work_gps_not_required': 'Kerja lapangan - GPS tidak diperlukan',
    'no_attendance_location_selected': 'Tidak ada lokasi absensi yang dipilih',
    'configuration_error': 'Kesalahan konfigurasi.',
    'office_worker_mode': 'Mode pekerja kantor - memvalidasi GPS dan radius',
    'field_worker_mode': 'Mode pekerja lapangan - validasi GPS dilewati',
    'attendance_location_not_configured':
        'Lokasi absensi belum dikonfigurasi. Silakan hubungi admin.',
    'getting_your_location': 'Mendapatkan lokasi Anda...',
    'unable_to_get_location_gps':
        'Tidak dapat mendapatkan lokasi Anda. Silakan aktifkan GPS dan coba lagi.',
    'you_are_away_from': 'Anda berada',
    'please_move_closer': 'Silakan bergerak lebih dekat ke lokasi absensi.',
    'unknown_distance': 'Jarak tidak diketahui',
    'within_radius': 'dalam radius',

    // NEW: Checkout Confirmation
    'confirm_check_out': 'Konfirmasi Check-out',
    'sure_to_check_out': 'Apakah Anda yakin ingin check out?',
    'end_work_session': 'Ini akan mengakhiri sesi kerja Anda untuk hari ini.',
    'yes_check_out': 'Ya',

    // NEW: Photo & Upload
    'photo_required_check_in': 'Foto diperlukan untuk check-in',
    'uploading_photo': 'Mengunggah foto...',
    'failed_upload_photo': 'Gagal mengunggah foto. Silakan coba lagi.',

    // NEW: Attendance Success
    'attendance_successful': 'Absensi Berhasil!',
    'check_in_completed': 'Check-in selesai',
    'check_out_completed': 'Check-out selesai',
    'break_started': 'Istirahat dimulai',
    'work_resumed': 'Kerja dilanjutkan',
    'attendance_recorded': 'Absensi tercatat',

    // NEW: Errors
    'failed_to_perform_attendance': 'Gagal melakukan absensi',
    'location_error': 'Kesalahan lokasi',
    'schedule_error': 'Kesalahan jadwal',
    'camera_not_available': 'Kamera tidak tersedia.',
    'camera_permission_required': 'Izin kamera diperlukan.',
    'failed_to_take_photo': 'Gagal mengambil foto',

    // NEW: Break
    'on_break_indicator': 'Sedang Istirahat',
    'stop_break': 'Hentikan Istirahat',
    'break_ended_duration': 'Istirahat berakhir - Durasi',
    'failed_to_end_break': 'Gagal mengakhiri istirahat',
    'break_start_time_not_found': 'Waktu mulai istirahat tidak ditemukan',
    'invalid_break_duration': 'Durasi istirahat tidak valid',
    'invalid_member_id': 'ID anggota tidak valid',

    // NEW: Organization & Device Selection
    'organization': 'Organisasi',
    'location_changed_to': 'Lokasi diubah ke',
    'unknown_device': 'Tidak Diketahui',
    'failed_to_reload_data': 'Gagal memuat ulang data',

    // Attendance
    'stop_break': 'Hentikan Istirahat',
    'break_ended': 'Istirahat berakhir',
    'duration': 'Durasi',

    // Profile
    'profile': 'Profil',
    'personal_information': 'Informasi Pribadi',
    'display_name': 'Nama Tampilan',
    'phone_number': 'Nomor Telepon',
    'gender': 'Jenis Kelamin',
    'male': 'Laki-laki',
    'female': 'Perempuan',
    'date_of_birth': 'Tanggal Lahir',
    'employee_id': 'ID Karyawan',
    'position': 'Posisi',
    'department': 'Departemen',
    'not_provided': 'Tidak tersedia',
    'not_assigned': 'Belum ditugaskan',
    'not_specified': 'Tidak ditentukan',
    'save_changes': 'Simpan Perubahan',
    'saving': 'Menyimpan...',
    'profile_updated': 'Profil berhasil diperbarui!',
    'photo_updated': 'Foto profil berhasil diperbarui!',
    'account_settings': 'Pengaturan',
    'security': 'Keamanan',
    'notifications': 'Notifikasi',
    'language': 'Bahasa',
    'appearance': 'Tampilan',
    'support_information': 'Dukungan & Informasi',
    'help_center': 'Pusat Bantuan',
    'contact_support': 'Hubungi Dukungan',
    'about': 'Tentang',
    'privacy_policy': 'Kebijakan Privasi',
    'terms_of_service': 'Ketentuan Layanan',
    'coming_soon': 'Segera Hadir',
    'feature_under_development':
        'Fitur ini sedang dalam pengembangan dan akan tersedia di pembaruan mendatang.',
    'password_and_authentication': 'Kata sandi dan autentikasi',
    'manage_notification_preferences': 'Kelola preferensi notifikasi Anda',
    'english_default': 'Inggris (Default)',
    'indonesian': 'Indonesia',
    'theme_and_display': 'Tema dan tampilan',
    'get_help_and_answers': 'Dapatkan bantuan dan temukan jawaban',
    'contact_our_team': 'Hubungi tim kami',
    'app_version_info': 'Versi aplikasi dan informasi',
    'learn_data_protection': 'Pelajari cara kami melindungi data Anda',
    'read_terms_and_conditions': 'Baca syarat dan ketentuan kami',
    'sign_out_account': 'Keluar dari akun Anda',
    'about_this_app': 'Tentang Aplikasi Ini',
    'attendance_app_version': 'Aplikasi Absensi v1.0.0',
    'app_description':
        'Aplikasi ini membantu Anda mengelola absensi dan tugas terkait organisasi dengan mudah.',

    // History
    'attendance_history': 'Riwayat Absensi',
    'attendance_summary': 'Ringkasan Absensi',
    'check_ins': 'Check In',
    'check_outs': 'Check Out',
    'records': 'Catatan',
    'calendar_view': 'Tampilan Kalender',
    'daily_events': 'Aktivitas Harian',
    'no_attendance_data': 'Tidak ada data absensi untuk',
    'date': 'Tanggal',
    'time': 'Waktu',
    'late': 'Terlambat',
    'early_leave': 'Pulang Awal',
    'work_duration': 'Durasi Kerja',
    'location': 'Lokasi',
    'minutes': 'menit',
    'hours': 'jam',
    'record': 'Catatan',
    'present': 'Hadir',
    'absent': 'Tidak Hadir',

    // Device Selection
    'select_attendance_location': 'Pilih Lokasi Absensi',
    'choose_attendance_location': 'Pilih lokasi absensi Anda',
    'location_detected': 'Lokasi terdeteksi',
    'location_not_available': 'Lokasi tidak tersedia',
    'search_location': 'Cari lokasi...',
    'no_locations_found': 'Lokasi tidak ditemukan',
    'try_different_search': 'Coba istilah pencarian lain',
    'no_locations_available': 'Tidak Ada Lokasi Tersedia',
    'no_locations_configured':
        'Belum ada lokasi absensi yang dikonfigurasi untuk organisasi Anda.',
    'change_location_anytime':
        'Anda dapat mengubah lokasi Anda kapan saja dari pengaturan profil.',
    'radius': 'radius',
    'away': 'jauhnya',
    'attendance_location_required': 'Lokasi Absensi Diperlukan',
    'select_location_to_continue':
        'Silakan pilih lokasi absensi untuk melanjutkan menggunakan sistem absensi.',

    // Organization
    'organization_setup_required': 'Pengaturan Organisasi Diperlukan',
    'need_organization_member':
        'Anda perlu terdaftar sebagai anggota organisasi untuk menggunakan sistem absensi ini.',
    'contact_hr_admin':
        'Hubungi administrator HR Anda untuk ditambahkan ke organisasi Anda.',
    'account_setup_required': 'Pengaturan Akun Diperlukan',
    'location_setup_required': 'Pengaturan Lokasi Diperlukan',
    'unknown_organization': 'Organisasi Tidak Diketahui',

    // Errors & Messages
    'failed_to_load': 'Gagal memuat',
    'failed_to_update': 'Gagal memperbarui',
    'failed_to_save': 'Gagal menyimpan',
    'failed_to_delete': 'Gagal menghapus',
    'no_data_found': 'Tidak ada data ditemukan',
    'invalid_input': 'Input tidak valid',
    'required_field': 'Bidang wajib diisi',
    'please_try_again': 'Silakan coba lagi',
    'something_went_wrong': 'Terjadi kesalahan',
    'no_internet_connection': 'Tidak ada koneksi internet',
    'unable_to_get_precise_location':
        'Tidak dapat mendapatkan lokasi yang presisi.',
    'enable_gps_and_try_again': 'Silakan aktifkan GPS dan coba lagi',
    'out_of_range': 'Di luar jangkauan',
    'locating': 'Menemukan lokasi...',
    'failed_to_refresh_data': 'Gagal memuat ulang data.',
    'failed_to_load_user_data':
        'Gagal memuat data pengguna. Silakan coba lagi.',
    'no_user_profile_found':
        'Tidak ada profil pengguna atau organisasi. Hubungi admin.',
    'failed_to_check_location': 'Gagal memeriksa konfigurasi lokasi.',
    'failed_to_initialize_services':
        'Gagal menginisialisasi layanan. Silakan restart aplikasi.',
    'failed_to_open_break_page': 'Gagal membuka halaman istirahat.',
    'user': 'Pengguna',

    // Performance Page (NEW)
    'attendance_performance': 'Kinerja Kehadiran',
    'monitor_attendance_stats': 'Pantau statistik dan kinerja kehadiran kamu',
    'present': 'Hadir',
    'absent': 'Tidak Hadir',
    'late': 'Terlambat',
    'early_leave': 'Pulang Awal',
    'avg_work_hours': 'Rata-rata Jam Kerja',
    'total_minutes_late': 'Total Menit Terlambat',
    'attendance_rate': 'Tingkat Kehadiran',
    'present_label': 'Hadir',
    'absent_label': 'Tidak Hadir',
    'total_days': 'Total Hari',
    'attendance_details': 'Rincian Kehadiran',
    'no_records_found': 'Tidak ada catatan',
    'no_records_month': 'Tidak ada catatan kehadiran bulan ini',

    'join_organization_to_continue':
        'Bergabung dengan organisasi untuk melanjutkan',
    'invitation_code': 'Kode Undangan',
    'ask_hr_for_invitation_code': 'Tanyakan kode undangan kepada HR Anda',
    'join_organization': 'Bergabung dengan Organisasi',
    'please_enter_invitation_code': 'Silakan masukkan kode undangan',
    'invalid_invitation_code': 'Kode undangan tidak valid',
    'already_member_of_organization':
        'Anda sudah menjadi anggota organisasi ini',
    'successfully_joined': 'Berhasil bergabung dengan',
    'failed_to_join_organization': 'Gagal bergabung dengan organisasi',
    'user_not_authenticated': 'Pengguna tidak terautentikasi',

    // Map Preview Dialog
    'verify_your_location': 'Verifikasi Lokasi Anda',
    'make_sure_within_office_area': 'Pastikan Anda berada di dalam area kantor',
    'cancel': 'Batal',
    'confirm_location': 'Konfirmasi Lokasi',

    // Map Widget
    'within_range': 'Dalam Jangkauan',
    'outside_range': 'Di Luar Jangkauan',
    'meters': 'm',
    'kilometers': 'km',
    'from_office': 'dari kantor',
    'my_location': 'Lokasi Saya',
    'zoom_in': 'Perbesar',
    'zoom_out': 'Perkecil',

    // General
    'loading': 'Memuat...',
    'apply': 'Terapkan',
    'date': 'Tanggal',
    'time': 'Waktu',
    'location': 'Lokasi',
    'hours': 'jam',
    'minutes': 'menit',

    // Attendance Page
    'attendance': 'Kehadiran',
    'unknown_organization': 'Organisasi Tidak Diketahui',
    'attendance_rate': 'Tingkat Kehadiran',
    'present_label': 'Hadir',
    'absent_label': 'Tidak Hadir',
    'late': 'Terlambat',
    'early_leave': 'Pulang Cepat',
    'work_duration': 'Durasi Kerja',

    // Calendar & Tabs
    'calendar_view': 'Kalender',
    'attendance_details': 'Detail',
    'daily_events': 'Kegiatan Harian',

    // Status
    'check_in': 'Masuk',
    'check_out': 'Keluar',

    // Messages
    'no_attendance_data': 'Tidak ada data kehadiran untuk tanggal ini',
    'no_records_found': 'Tidak ada catatan untuk bulan ini',

    // Error Messages
    'error_loading_data': 'Gagal memuat data',
    'add_location': 'Tambah Lokasi',
    'location_set': 'Siap',
    'field_work_at': 'Kerja di',
    'registration_failed': 'Pendaftaran Gagal',
    'name_email_password_required': 'Nama, email, dan kata sandi wajib diisi',
    'invalid_email_format': 'Format email tidak valid',
    'password_min_6_characters': 'Kata sandi minimal 6 karakter',
    'failed_create_account': 'Gagal membuat akun',
    'email_already_registered': 'Email sudah terdaftar',
    'password_too_weak': 'Kata sandi terlalu lemah',
    'login_failed': 'Login Gagal',
    'email_password_required': 'Email dan kata sandi wajib diisi',
    'incorrect_email_or_password': 'Email atau kata sandi salah',
  };

  // English translations
  static final Map<String, String> _englishTranslations = {
    'registration_failed': 'Registration Failed',
    'name_email_password_required': 'Name, email, and password are required',
    'invalid_email_format': 'Invalid email format',
    'password_min_6_characters': 'Password must be at least 6 characters',
    'failed_create_account': 'Failed to create account',
    'email_already_registered': 'Email already registered',
    'password_too_weak': 'Password too weak',
    'login_failed': 'Login Failed',
    'email_password_required': 'Email and password are required',
    'incorrect_email_or_password': 'Incorrect email or password',
    // Main Dashboard
    'verifying_organization': 'Verifying organization...',
    'home': 'Home',
    'report': 'Report',
    'profile': 'Profile',

    'add_location': 'Add Location',
    'location_set': 'Ready',
    'field_work_at': 'Work in',
    // Months
    'january': 'January',
    'february': 'February',
    'march': 'March',
    'april': 'April',
    'may': 'May',
    'june': 'June',
    'july': 'July',
    'august': 'August',
    'september': 'September',
    'october': 'October',
    'november': 'November',
    'december': 'December',

    // Month abbreviations
    'jan': 'Jan',
    'feb': 'Feb',
    'mar': 'Mar',
    'apr': 'Apr',
    'may_short': 'May',
    'jun': 'Jun',
    'jul': 'Jul',
    'aug': 'Aug',
    'sep': 'Sep',
    'oct': 'Oct',
    'nov': 'Nov',
    'dec': 'Dec',

    // Days of week
    'monday': 'Monday',
    'tuesday': 'Tuesday',
    'wednesday': 'Wednesday',
    'thursday': 'Thursday',
    'friday': 'Friday',
    'saturday': 'Saturday',
    'sunday': 'Sunday',

    // Day abbreviations
    'mon': 'Mon',
    'tue': 'Tue',
    'wed': 'Wed',
    'thu': 'Thu',
    'fri': 'Fri',
    'sat': 'Sat',
    'sun': 'Sun',

    // Date/Time related
    'select_month_year': 'Select Month & Year',
    'apply': 'Apply',
    'year': 'Year',
    'month': 'Month',
    'day': 'Day',
    'today': 'Today',
    'yesterday': 'Yesterday',
    'tomorrow': 'Tomorrow',

    'join_organization_to_continue': 'Join your organization to continue',
    'invitation_code': 'Invitation Code',
    'ask_hr_for_invitation_code': 'Ask your HR for the invitation code',
    'join_organization': 'Join Organization',
    'please_enter_invitation_code': 'Please enter invitation code',
    'invalid_invitation_code': 'Invalid invitation code',
    'already_member_of_organization':
        'You are already a member of this organization',
    'successfully_joined': 'Successfully joined',
    'failed_to_join_organization': 'Failed to join organization',
    'user_not_authenticated': 'User not authenticated',

    'work_time': 'Work Time',
    'work_period': 'Work Period',
    'break_time': 'Break Time',
    'break_period': 'Break Period',
    // Common
    'ok': 'OK',
    'cancel': 'Cancel',
    'save': 'Save',
    'edit': 'Edit',
    'delete': 'Delete',
    'confirm': 'Confirm',
    'close': 'Close',
    'refresh': 'Refresh',
    'loading': 'Loading...',
    'error': 'Error',
    'success': 'Success',
    'warning': 'Warning',
    'info': 'Info',
    'retry': 'Retry',
    'continue': 'Continue',

    // Login & Auth
    'login': 'Login',
    'signup': 'Sign Up',
    'logout': 'Logout',
    'email': 'Email',
    'password': 'Password',
    'full_name': 'Full Name',
    'welcome_back': 'Welcome ',
    'sign_in_to_continue': 'Sign in to continue',
    'create_account': 'Create Account',
    'already_have_account': 'Already have an account?',
    'dont_have_account': "Don't have an account?",
    'sign_in': 'Sign In',
    'sign_up': 'Sign Up',
    'continue_with_google': 'Continue with Google',
    'or_sign_in_with_email': 'or sign in with email',
    'enter_your_email': 'Enter your email',
    'enter_your_password': 'Enter your password',
    'enter_your_full_name': 'Enter your full name',
    'smart_attendance_system': 'Smart Attendance System',
    'registration_successful': 'Registration Successful!',
    'account_created_successfully':
        'Your account has been created successfully',
    'continue_to_login': 'Continue to Login',
    'fill_in_your_details': 'Fill in your details to get started',
    'processing': 'Processing...',
    'creating_account': 'Creating your account...',
    'confirm_logout': 'Confirm Logout',
    'are_you_sure_logout': 'Are you sure you want to logout?',

    // Dashboard
    'hello': 'Hello',
    'ready_to_start': 'Ready to start',
    'currently_working': 'Currently working',
    'on_break': 'On break',
    'ready_to_check_in_again': 'Ready to check in again',
    'waiting_for_status': 'Waiting for status...',
    'overview': 'Overview',
    'presence': 'Presence',
    'absence': 'Absence',
    'lateness': 'Lateness',
    'todays_schedule': "Today's Schedule",
    'no_schedule_available': 'No schedule available for today',
    'check_in': 'Check In',
    'check_out': 'Check Out',
    'break': 'Break',
    'start_work_day': 'Start work day',
    'end_work_day': 'End work day',
    'take_a_break': 'Take a break',
    'completed': 'Completed',
    'available_now': 'Available now',
    'not_yet_available': 'Not yet available',
    'getting_location': 'Getting your location...',
    'location_not_configured': 'Attendance location not configured',
    'select_location': 'Select Location',
    'no_location': 'No Location',
    'field_work': 'Field Work',
    'office': 'Office',
    'gps_not_required': 'GPS not required',
    'ready': 'Ready',
    'move_closer': 'Please move closer to the attendance location',
    'organization_member_not_found': 'Organization member data not found.',
    'checking': 'Checking...',
    'check_again': 'Check Again',

    // NEW: Dashboard Status & Location
    'field_work_in': 'Field work in',
    'field_work_gps_not_required': 'Field work - GPS not required',
    'no_attendance_location_selected': 'No attendance location selected',
    'configuration_error': 'Configuration error.',
    'office_worker_mode': 'Office worker mode - validating GPS and radius',
    'field_worker_mode': 'Field worker mode - GPS validation skipped',
    'attendance_location_not_configured':
        'Attendance location not configured. Please contact admin.',
    'getting_your_location': 'Getting your location...',
    'unable_to_get_location_gps':
        'Unable to get your location. Please enable GPS and try again.',
    'you_are_away_from': 'You are',
    'please_move_closer': 'Please move closer to the attendance location.',
    'unknown_distance': 'Unknown distance',
    'within_radius': 'within radius',

    // NEW: Checkout Confirmation
    'confirm_check_out': 'Confirm Check-out',
    'sure_to_check_out': 'Are you sure you want to check out?',
    'end_work_session': 'This will end your work session for today.',
    'yes_check_out': 'Yes',

    // NEW: Photo & Upload
    'photo_required_check_in': 'Photo required for check-in',
    'uploading_photo': 'Uploading photo...',
    'failed_upload_photo': 'Failed to upload photo. Please try again.',

    // NEW: Attendance Success
    'attendance_successful': 'Attendance Successful!',
    'check_in_completed': 'Check-in completed',
    'check_out_completed': 'Check-out completed',
    'break_started': 'Break started',
    'work_resumed': 'Work resumed',
    'attendance_recorded': 'Attendance recorded',

    // NEW: Errors
    'failed_to_perform_attendance': 'Failed to perform attendance',
    'location_error': 'Location error',
    'schedule_error': 'Schedule error',
    'camera_not_available': 'Camera not available.',
    'camera_permission_required': 'Camera permission required.',
    'failed_to_take_photo': 'Failed to take photo',

    // NEW: Break
    'on_break_indicator': 'On Break',
    'stop_break': 'Stop Break',
    'break_ended_duration': 'Break ended - Duration',
    'failed_to_end_break': 'Failed to end break',
    'break_start_time_not_found': 'Break start time not found',
    'invalid_break_duration': 'Invalid break duration',
    'invalid_member_id': 'Invalid member ID',

    // NEW: Organization & Device Selection
    'organization': 'Organization',
    'location_changed_to': 'Location changed to',
    'unknown_device': 'Unknown',
    'failed_to_reload_data': 'Failed to reload data',

    // Attendance
    'stop_break': 'Stop Break',
    'break_ended': 'Break ended',
    'duration': 'Duration',

    // Profile
    'profile': 'Profile',
    'personal_information': 'Personal Information',
    'display_name': 'Display Name',
    'phone_number': 'Phone Number',
    'gender': 'Gender',
    'male': 'Male',
    'female': 'Female',
    'date_of_birth': 'Date of Birth',
    'employee_id': 'Employee ID',
    'position': 'Position',
    'department': 'Department',
    'not_provided': 'Not provided',
    'not_assigned': 'Not assigned',
    'not_specified': 'Not specified',
    'save_changes': 'Save Changes',
    'saving': 'Saving...',
    'profile_updated': 'Profile updated successfully!',
    'photo_updated': 'Profile photo updated successfully!',
    'account_settings': 'Settings',
    'security': 'Security',
    'notifications': 'Notifications',
    'language': 'Language',
    'appearance': 'Appearance',
    'support_information': 'Support & Information',
    'help_center': 'Help Center',
    'contact_support': 'Contact Support',
    'about': 'About',
    'privacy_policy': 'Privacy Policy',
    'terms_of_service': 'Terms of Service',
    'coming_soon': 'Coming Soon',
    'feature_under_development':
        'This feature is currently under development and will be available in a future update.',
    'password_and_authentication': 'Password and authentication',
    'manage_notification_preferences': 'Manage your notification preferences',
    'english_default': 'English (Default)',
    'indonesian': 'Indonesian',
    'theme_and_display': 'Theme and display settings',
    'get_help_and_answers': 'Get help and find answers',
    'contact_our_team': 'Get in touch with our team',
    'app_version_info': 'App version and information',
    'learn_data_protection': 'Learn how we protect your data',
    'read_terms_and_conditions': 'Read our terms and conditions',
    'sign_out_account': 'Sign out from your account',
    'about_this_app': 'About This App',
    'attendance_app_version': 'Attendance App v1.0.0',
    'app_description':
        'This app helps you manage your attendance and organization-related tasks with ease.',

    // History
    'attendance_history': 'Attendance History',
    'attendance_summary': 'Attendance Summary',
    'check_ins': 'Check Ins',
    'check_outs': 'Check Outs',
    'records': 'Records',
    'calendar_view': 'Calendar View',
    'daily_events': 'Daily Events',
    'no_attendance_data': 'No attendance data for',
    'date': 'Date',
    'time': 'Time',
    'late': 'Late',
    'early_leave': 'Early Leave',
    'work_duration': 'Work Duration',
    'location': 'Location',
    'minutes': 'minutes',
    'hours': 'hours',
    'record': 'Record',
    'present': 'Present',
    'absent': 'Absent',

    // Device Selection
    'select_attendance_location': 'Select Attendance Location',
    'choose_attendance_location': 'Choose your attendance location',
    'location_detected': 'Location detected',
    'location_not_available': 'Location not available',
    'search_location': 'Search location...',
    'no_locations_found': 'No locations found',
    'try_different_search': 'Try a different search term',
    'no_locations_available': 'No Locations Available',
    'no_locations_configured':
        'No attendance locations have been configured for your organization yet.',
    'change_location_anytime':
        'You can change your location anytime from the profile settings.',
    'radius': 'radius',
    'away': 'away',
    'attendance_location_required': 'Attendance Location Required',
    'select_location_to_continue':
        'Please select an attendance location to continue using the attendance system.',

    // Organization
    'organization_setup_required': 'Organization Setup Required',
    'need_organization_member':
        'You need to be registered as a member of an organization to use this attendance system.',
    'contact_hr_admin':
        'Contact your HR administrator to get added to your organization.',
    'account_setup_required': 'Account Setup Required',
    'location_setup_required': 'Location Setup Required',
    'unknown_organization': 'Unknown Organization',

    // Errors & Messages
    'failed_to_load': 'Failed to load',
    'failed_to_update': 'Failed to update',
    'failed_to_save': 'Failed to save',
    'failed_to_delete': 'Failed to delete',
    'no_data_found': 'No data found',
    'invalid_input': 'Invalid input',
    'required_field': 'Required field',
    'please_try_again': 'Please try again',
    'something_went_wrong': 'Something went wrong',
    'no_internet_connection': 'No internet connection',
    'unable_to_get_precise_location': 'Unable to get precise location.',
    'enable_gps_and_try_again': 'Please enable GPS and try again',
    'out_of_range': 'Out of range',
    'locating': 'Locating...',
    'failed_to_refresh_data': 'Failed to refresh data.',
    'failed_to_load_user_data': 'Failed to load user data. Please try again.',
    'no_user_profile_found':
        'No user profile or organization found. Contact admin.',
    'failed_to_check_location': 'Failed to check location configuration.',
    'failed_to_initialize_services':
        'Failed to initialize services. Please restart the app.',
    'failed_to_open_break_page': 'Failed to open break page.',
    'user': 'User',

    'attendance_performance': 'Attendance Performance',
    'monitor_attendance_stats':
        'Monitor your attendance statistics and performance',
    'present': 'Present',
    'absent': 'Absent',
    'late': 'Late',
    'early_leave': 'Early Leave',
    'avg_work_hours': 'Avg Work Hours',
    'total_minutes_late': 'Total Minutes Late',
    'attendance_rate': 'Attendance Rate',
    'present_label': 'Present',
    'absent_label': 'Absent',
    'total_days': 'Total Days',
    'attendance_details': 'Attendance Details',
    'no_records_found': 'No records found',
    'no_records_month': 'No attendance records for this month',

    // Map Preview Dialog
    'verify_your_location': 'Verify Your Location',
    'make_sure_within_office_area': 'Make sure you are within the office area',
    'confirm_location': 'Confirm Location',
    'cancel': 'Cancel',

    // Map Widget
    'within_range': 'Within range',
    'outside_range': 'Outside range',
    'meters': 'm',
    'kilometers': 'km',
    'from_office': 'From office',
    'my_location': 'My location',
    'zoom_in': 'Zoom in',
    'zoom_out': 'Zoom out',

    // General
    'loading': 'Loading...',
    'apply': 'Apply',
    'date': 'Date',
    'time': 'Time',
    'location': 'Location',
    'hours': 'hours',
    'minutes': 'minutes',

    // Attendance Page
    'attendance': 'Attendance',
    'unknown_organization': 'Unknown Organization',
    'attendance_rate': 'Attendance Rate',
    'present_label': 'Present',
    'absent_label': 'Absent',
    'late': 'Late',
    'early_leave': 'Early Leave',
    'work_duration': 'Work Duration',

    // Calendar & Tabs
    'calendar_view': 'Calendar',
    'attendance_details': 'Details',
    'daily_events': 'Daily Events',

    // Status
    'check_in': 'Check In',
    'check_out': 'Check Out',

    // Messages
    'no_attendance_data': 'No attendance data for this date',
    'no_records_found': 'No records found for this month',

    // Error Messages
    'error_loading_data': 'Error loading data',
  };

  // Helper method untuk get text dengan fallback
  static String tr(String key, {String? fallback}) {
    return getText(key);
  }

  // Get month name
  static String getMonthName(int month) {
    const months = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    if (month >= 1 && month <= 12) {
      return getText(months[month - 1]);
    }
    return month.toString();
  }

  // Get month abbreviation
  static String getMonthAbbr(int month) {
    const months = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may_short',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];
    if (month >= 1 && month <= 12) {
      return getText(months[month - 1]);
    }
    return month.toString();
  }

  // Get day name
  static String getDayName(int weekday) {
    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    if (weekday >= 1 && weekday <= 7) {
      return getText(days[weekday - 1]);
    }
    return weekday.toString();
  }

  // Get day abbreviation
  static String getDayAbbr(int weekday) {
    const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    if (weekday >= 1 && weekday <= 7) {
      return getText(days[weekday - 1]);
    }
    return weekday.toString();
  }
}
