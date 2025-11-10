// services/camera_service.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class CameraService {
  static List<CameraDescription>? _cameras;
  static bool _isInitialized = false;
  static CameraController? _controller;
  
  // ✅ OPTIMIZATION: Cache permission status
  static PermissionStatus? _cachedPermissionStatus;
  static DateTime? _permissionCheckTime;
  static const Duration _permissionCacheDuration = Duration(minutes: 5);

  // ================== INITIALIZATION ==================

  /// Initialize cameras with lazy initialization
  static Future<List<CameraDescription>> initializeCameras() async {
    if (_isInitialized && _cameras != null) {
      print('Cameras already initialized - returning cached');
      return _cameras!;
    }

    try {
      print('Initializing cameras...');
      _cameras = await availableCameras();
      _isInitialized = true;
      
      print('Cameras initialized: ${_cameras!.length} cameras found');
      return _cameras!;
    } catch (e) {
      print('Error initializing cameras: $e');
      _isInitialized = false;
      throw CameraException('initialization_failed', 'Failed to initialize cameras: $e');
    }
  }

  static bool get isInitialized => _isInitialized && _cameras != null;

  static List<CameraDescription> get cameras {
    if (!isInitialized) {
      throw CameraException('not_initialized', 'Cameras not initialized');
    }
    return _cameras!;
  }

  static void reset() {
    _cameras = null;
    _isInitialized = false;
    _controller?.dispose();
    _controller = null;
    _cachedPermissionStatus = null;
    _permissionCheckTime = null;
    print('Camera service reset');
  }

  // ================== CAMERA INFORMATION ==================

  static int get cameraCount => isInitialized ? _cameras!.length : 0;
  static bool get hasCameras => cameraCount > 0;

  static CameraDescription? get frontCamera {
    if (!isInitialized) return null;
    try {
      return _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
    } catch (e) {
      return null;
    }
  }

  static CameraDescription? get backCamera {
    if (!isInitialized) return null;
    try {
      return _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
    } catch (e) {
      return null;
    }
  }

  static bool get hasFrontCamera => frontCamera != null;
  static bool get hasBackCamera => backCamera != null;

  static CameraDescription? getCameraByIndex(int index) {
    if (!isInitialized || index < 0 || index >= _cameras!.length) {
      return null;
    }
    return _cameras![index];
  }

  static int getPreferredCameraIndex() {
    if (!isInitialized || _cameras!.isEmpty) return 0;
    
    final frontIndex = _cameras!.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    
    return frontIndex >= 0 ? frontIndex : 0;
  }

  static int? getCameraIndexByDirection(CameraLensDirection direction) {
    if (!isInitialized) return null;
    
    final index = _cameras!.indexWhere(
      (camera) => camera.lensDirection == direction,
    );
    
    return index >= 0 ? index : null;
  }

  // ================== PERMISSIONS ==================

  /// ✅ OPTIMIZATION: Check permission with caching
  static Future<PermissionStatus> checkCameraPermission() async {
    try {
      // Return cached status if still valid
      if (_cachedPermissionStatus != null && _permissionCheckTime != null) {
        final elapsed = DateTime.now().difference(_permissionCheckTime!);
        if (elapsed < _permissionCacheDuration) {
          print('Returning cached permission status: $_cachedPermissionStatus');
          return _cachedPermissionStatus!;
        }
      }

      final status = await Permission.camera.status;
      
      // Update cache
      _cachedPermissionStatus = status;
      _permissionCheckTime = DateTime.now();
      
      print('Camera permission status: $status (cached)');
      return status;
    } catch (e) {
      print('Error checking camera permission: $e');
      throw CameraException('permission_check_failed', 'Failed to check camera permission: $e');
    }
  }

  static Future<bool> requestCameraPermission() async {
    try {
      print('Requesting camera permission...');
      final status = await Permission.camera.request();
      final granted = status == PermissionStatus.granted;
      
      // Update cache
      _cachedPermissionStatus = status;
      _permissionCheckTime = DateTime.now();
      
      print('Camera permission ${granted ? 'granted' : 'denied'}: $status');
      return granted;
    } catch (e) {
      print('Error requesting camera permission: $e');
      throw CameraException('permission_request_failed', 'Failed to request camera permission: $e');
    }
  }

  static Future<bool> hasPermission() async {
    final status = await checkCameraPermission();
    return status == PermissionStatus.granted;
  }

  static Future<bool> ensurePermission() async {
    if (await hasPermission()) {
      return true;
    }
    return await requestCameraPermission();
  }

  /// ✅ OPTIMIZATION: Clear permission cache
  static void clearPermissionCache() {
    _cachedPermissionStatus = null;
    _permissionCheckTime = null;
  }

  // ================== CAMERA CONTROLLER ==================

  static Future<CameraController> createController(
    CameraDescription camera, {
    ResolutionPreset resolutionPreset = ResolutionPreset.medium,
    bool enableAudio = false,
  }) async {
    try {
      print('Creating camera controller for: ${camera.name}');
      
      final controller = CameraController(
        camera,
        resolutionPreset,
        enableAudio: enableAudio,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      print('Camera controller initialized');
      
      return controller;
    } catch (e) {
      print('Error creating camera controller: $e');
      throw CameraException('controller_creation_failed', 'Failed to create camera controller: $e');
    }
  }

  static Future<CameraController> getDefaultController({
    ResolutionPreset resolutionPreset = ResolutionPreset.medium,
    bool enableAudio = false,
  }) async {
    if (!isInitialized) {
      throw CameraException('not_initialized', 'Cameras not initialized');
    }

    final preferredIndex = getPreferredCameraIndex();
    final camera = _cameras![preferredIndex];
    
    return await createController(
      camera,
      resolutionPreset: resolutionPreset,
      enableAudio: enableAudio,
    );
  }

  // ================== PHOTO OPERATIONS ==================

  static Future<XFile> takePicture(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) {
        throw CameraException('controller_not_initialized', 'Camera controller not initialized');
      }

      print('Taking picture...');
      final XFile photo = await controller.takePicture();
      
      print('Picture taken: ${photo.path}');
      return photo;
    } catch (e) {
      print('Error taking picture: $e');
      throw CameraException('capture_failed', 'Failed to take picture: $e');
    }
  }

  static Future<String> takePictureToPath(
    CameraController controller,
    String fileName,
  ) async {
    try {
      final photo = await takePicture(controller);
      
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String dirPath = '${appDocDir.path}/attendance_photos';
      
      final Directory photoDir = Directory(dirPath);
      if (!await photoDir.exists()) {
        await photoDir.create(recursive: true);
      }
      
      final String filePath = '$dirPath/$fileName';
      await File(photo.path).copy(filePath);
      
      try {
        await File(photo.path).delete();
      } catch (e) {
        print('Warning: Could not delete temp file: $e');
      }
      
      print('Picture saved to: $filePath');
      return filePath;
    } catch (e) {
      print('Error taking picture to path: $e');
      throw CameraException('save_failed', 'Failed to save picture: $e');
    }
  }

  // ================== UTILITY METHODS ==================

  static List<ResolutionPreset> getAvailableResolutions() {
    return [
      ResolutionPreset.low,
      ResolutionPreset.medium,
      ResolutionPreset.high,
      ResolutionPreset.veryHigh,
      ResolutionPreset.ultraHigh,
      ResolutionPreset.max,
    ];
  }

  static ResolutionPreset getRecommendedResolution() {
    return ResolutionPreset.medium;
  }

  static String generateAttendancePhotoName(String userId, String type) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${userId}_${type}_$timestamp.jpg';
  }

  static bool validateCameraSetup() {
    if (!isInitialized) {
      print('Camera validation failed: Not initialized');
      return false;
    }
    
    if (!hasCameras) {
      print('Camera validation failed: No cameras available');
      return false;
    }
    
    if (!hasFrontCamera && !hasBackCamera) {
      print('Camera validation failed: No usable cameras found');
      return false;
    }
    
    print('Camera setup validation passed');
    return true;
  }

  static String getCameraInfoString() {
    if (!isInitialized) {
      return 'Cameras not initialized';
    }
    
    final buffer = StringBuffer();
    buffer.writeln('Camera Service Info:');
    buffer.writeln('- Total cameras: $cameraCount');
    buffer.writeln('- Has front camera: $hasFrontCamera');
    buffer.writeln('- Has back camera: $hasBackCamera');
    buffer.writeln('- Preferred index: ${getPreferredCameraIndex()}');
    
    return buffer.toString();
  }

  // ================== ERROR HANDLING ==================

  static String getErrorMessage(dynamic error) {
    if (error is CameraException) {
      switch (error.code) {
        case 'not_initialized':
          return 'Kamera belum diinisialisasi';
        case 'initialization_failed':
          return 'Gagal menginisialisasi kamera';
        case 'permission_check_failed':
          return 'Gagal memeriksa izin kamera';
        case 'permission_request_failed':
          return 'Gagal meminta izin kamera';
        case 'controller_creation_failed':
          return 'Gagal membuat controller kamera';
        case 'controller_not_initialized':
          return 'Controller kamera belum diinisialisasi';
        case 'capture_failed':
          return 'Gagal mengambil foto';
        case 'save_failed':
          return 'Gagal menyimpan foto';
        default:
          return 'Error kamera: ${error.description}';
      }
    }
    
    return 'Error tidak dikenal: $error';
  }
}