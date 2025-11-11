import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service untuk mendeteksi fake GPS atau mock location
class FakeGpsDetector {
  /// Deteksi apakah GPS yang digunakan adalah fake/mock
  /// 
  /// Returns:
  /// - true jika terdeteksi fake GPS
  /// - false jika GPS tampak valid
  static Future<bool> isFakeGps(Position position) async {
    try {
      // 1. Cek apakah mock location enabled (Android)
      if (Platform.isAndroid) {
        final isMockLocation = await _checkMockLocationAndroid();
        if (isMockLocation) {
          debugPrint('⚠️ Fake GPS Detected: Mock location enabled');
          return true;
        }
      }

      // 2. Cek akurasi GPS (fake GPS sering memiliki akurasi yang tidak realistis)
      if (position.accuracy <= 0 || position.accuracy > 1000) {
        debugPrint('⚠️ Fake GPS Detected: Unrealistic accuracy (${position.accuracy}m)');
        return true;
      }

      // 3. Cek apakah posisi terlalu sempurna (akurasi terlalu baik tanpa satelit)
      if (position.accuracy < 5 && position.speed == 0 && position.heading == 0) {
        // Posisi terlalu sempurna tanpa pergerakan - kemungkinan fake
        debugPrint('⚠️ Fake GPS Detected: Too perfect position without movement');
        return true;
      }

      // 4. Cek timestamp (fake GPS bisa memiliki timestamp yang tidak sesuai)
      final now = DateTime.now();
      final timeDiff = now.difference(position.timestamp).abs().inSeconds;
      if (timeDiff > 300) { // Lebih dari 5 menit perbedaan
        debugPrint('⚠️ Fake GPS Detected: Timestamp mismatch ($timeDiff seconds)');
        return true;
      }

      // 5. Cek apakah posisi di tengah laut atau lokasi tidak mungkin
      if (_isImpossibleLocation(position.latitude, position.longitude)) {
        debugPrint('⚠️ Fake GPS Detected: Impossible location (${position.latitude}, ${position.longitude})');
        return true;
      }

      // 6. Cek kecepatan yang tidak realistis
      if (position.speed > 0 && position.speed < 1000) {
        // Kecepatan dalam m/s, jika lebih dari 1000 m/s (3600 km/h) = tidak mungkin
        if (position.speed > 1000) {
          debugPrint('⚠️ Fake GPS Detected: Impossible speed (${position.speed} m/s)');
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error detecting fake GPS: $e');
      // Jika error, anggap tidak fake (biarkan validasi lain yang menangani)
      return false;
    }
  }

  /// Cek apakah mock location enabled di Android
  static Future<bool> _checkMockLocationAndroid() async {
    try {
      if (!Platform.isAndroid) return false;

      // Cek permission untuk membaca setting
      final status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        return false; // Tidak bisa cek tanpa permission
      }

      // Untuk Android, kita bisa cek beberapa indikator:
      // 1. Cek apakah ada app mock location yang terdeteksi
      // 2. Cek setting mock location (memerlukan akses ke Settings)
      
      // Teknik 1: Cek akurasi yang terlalu sempurna tanpa satelit
      // (Ini sudah ditangani di isFakeGps)
      
      // Teknik 2: Cek apakah posisi berubah terlalu cepat atau tidak realistis
      // (Ini juga sudah ditangani)
      
      // Untuk deteksi yang lebih akurat, kita bisa menggunakan package tambahan
      // atau membuat native code. Untuk sekarang, kita mengandalkan validasi lainnya.
      
      return false;
    } catch (e) {
      debugPrint('Error checking mock location: $e');
      return false;
    }
  }

  /// Cek apakah lokasi tidak mungkin (di tengah laut, dll)
  static bool _isImpossibleLocation(double latitude, double longitude) {
    // Cek apakah di tengah laut (tidak ada daratan)
    // Ini adalah heuristik sederhana - bisa diperluas dengan data geografis
    
    // Koordinat yang tidak mungkin (di tengah samudra tanpa pulau)
    // Contoh: Tengah Samudra Pasifik
    if (latitude >= -20 && latitude <= 20 && 
        longitude >= 150 && longitude <= 180) {
      // Area tengah samudra pasifik - kemungkinan besar fake jika tidak ada kapal
      return false; // Tidak langsung return true karena bisa jadi kapal
    }
    
    // Cek apakah koordinat 0,0 (null island) - sering digunakan sebagai fake
    if (latitude == 0.0 && longitude == 0.0) {
      return true;
    }
    
    // Cek apakah koordinat di luar range valid
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return true;
    }
    
    return false;
  }

  /// Validasi posisi GPS dengan multiple checks
  /// 
  /// Returns:
  /// - Map dengan hasil validasi:
  ///   - 'isValid': bool - apakah GPS valid
  ///   - 'isFake': bool - apakah terdeteksi fake
  ///   - 'warnings': List<String> - daftar warning
  ///   - 'confidence': double - tingkat kepercayaan (0-1)
  static Future<Map<String, dynamic>> validateGpsPosition(Position position) async {
    final warnings = <String>[];
    double confidence = 1.0;
    bool isFake = false;

    // 1. Cek mock location
    if (Platform.isAndroid) {
      final isMock = await _checkMockLocationAndroid();
      if (isMock) {
        isFake = true;
        confidence = 0.0;
        warnings.add('Mock location terdeteksi');
      }
    }

    // 2. Cek akurasi
    if (position.accuracy <= 0) {
      isFake = true;
      confidence = 0.0;
      warnings.add('Akurasi GPS tidak valid');
    } else if (position.accuracy > 500) {
      confidence -= 0.3;
      warnings.add('Akurasi GPS rendah (${position.accuracy.toStringAsFixed(0)}m)');
    } else if (position.accuracy < 5 && position.speed == 0) {
      confidence -= 0.2;
      warnings.add('Akurasi terlalu sempurna tanpa pergerakan');
    }

    // 3. Cek timestamp
    final now = DateTime.now();
    final timeDiff = now.difference(position.timestamp).abs().inSeconds;
    if (timeDiff > 300) {
      confidence -= 0.3;
      warnings.add('Timestamp GPS tidak sesuai (${timeDiff}s)');
    } else if (timeDiff > 60) {
      confidence -= 0.1;
      warnings.add('Data GPS sudah lama (${timeDiff}s)');
    }

    // 4. Cek lokasi tidak mungkin
    if (_isImpossibleLocation(position.latitude, position.longitude)) {
      isFake = true;
      confidence = 0.0;
      warnings.add('Lokasi tidak mungkin');
    }

    // 5. Cek kecepatan tidak realistis
    if (position.speed > 1000) {
      isFake = true;
      confidence = 0.0;
      warnings.add('Kecepatan tidak realistis (${position.speed.toStringAsFixed(0)} m/s)');
    }

    // Jika confidence terlalu rendah, anggap fake
    if (confidence < 0.5 && !isFake) {
      isFake = true;
      warnings.add('Tingkat kepercayaan GPS rendah');
    }

    return {
      'isValid': !isFake && confidence >= 0.5,
      'isFake': isFake,
      'warnings': warnings,
      'confidence': confidence.clamp(0.0, 1.0),
      'accuracy': position.accuracy,
      'timestamp': position.timestamp,
    };
  }

  /// Cek apakah device memiliki developer options enabled (indikator potensial fake GPS)
  /// Note: Ini hanya indikator, bukan bukti pasti
  static Future<bool> checkDeveloperOptionsEnabled() async {
    // Implementasi ini memerlukan native code
    // Untuk sekarang return false (tidak bisa deteksi)
    return false;
  }

  /// Get pesan error untuk fake GPS
  static String getFakeGpsErrorMessage(List<String> warnings) {
    if (warnings.isEmpty) {
      return 'GPS tidak valid. Pastikan GPS asli aktif dan aplikasi fake GPS dimatikan.';
    }
    
    final mainWarning = warnings.first;
    return 'GPS tidak valid: $mainWarning. Pastikan GPS asli aktif dan aplikasi fake GPS dimatikan.';
  }
}