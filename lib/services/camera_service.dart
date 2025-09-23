// services/camera_service.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class CameraService {
  static List<CameraDescription>? _cameras;
  static bool _isInitialized = false;
  static CameraController? _controller;

  // ================== INITIALIZATION ==================

  /// Initialize cameras and get available camera descriptions
  static Future<List<CameraDescription>> initializeCameras() async {
    if (_isInitialized && _cameras != null) {
      return _cameras!;
    }

    try {
      print('Initializing cameras...');
      _cameras = await availableCameras();
      _isInitialized = true;
      
      print('Cameras initialized successfully: ${_cameras!.length} cameras found');
      for (int i = 0; i < _cameras!.length; i++) {
        final camera = _cameras![i];
        print('Camera $i: ${camera.name} - ${camera.lensDirection}');
      }
      
      return _cameras!;
    } catch (e) {
      print('Error initializing cameras: $e');
      _isInitialized = false;
      throw CameraException('initialization_failed', 'Failed to initialize cameras: $e');
    }
  }

  /// Check if cameras are initialized
  static bool get isInitialized => _isInitialized && _cameras != null;

  /// Get available cameras (must call initializeCameras first)
  static List<CameraDescription> get cameras {
    if (!isInitialized) {
      throw CameraException('not_initialized', 'Cameras not initialized. Call initializeCameras() first.');
    }
    return _cameras!;
  }

  /// Reset initialization state
  static void reset() {
    _cameras = null;
    _isInitialized = false;
    _controller?.dispose();
    _controller = null;
    print('Camera service reset');
  }

  // ================== CAMERA INFORMATION ==================

  /// Get camera count
  static int get cameraCount {
    if (!isInitialized) return 0;
    return _cameras!.length;
  }

  /// Check if any cameras are available
  static bool get hasCameras => cameraCount > 0;

  /// Get front camera if available
  static CameraDescription? get frontCamera {
    if (!isInitialized) return null;
    
    try {
      return _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
    } catch (e) {
      print('No front camera found');
      return null;
    }
  }

  /// Get back camera if available
  static CameraDescription? get backCamera {
    if (!isInitialized) return null;
    
    try {
      return _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
    } catch (e) {
      print('No back camera found');
      return null;
    }
  }

  /// Check if front camera is available
  static bool get hasFrontCamera => frontCamera != null;

  /// Check if back camera is available
  static bool get hasBackCamera => backCamera != null;

  /// Get camera description by index
  static CameraDescription? getCameraByIndex(int index) {
    if (!isInitialized || index < 0 || index >= _cameras!.length) {
      return null;
    }
    return _cameras![index];
  }

  /// Get preferred camera index (front camera preferred for selfies)
  static int getPreferredCameraIndex() {
    if (!isInitialized || _cameras!.isEmpty) return 0;
    
    final frontIndex = _cameras!.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    
    return frontIndex >= 0 ? frontIndex : 0;
  }

  /// Get camera index by lens direction
  static int? getCameraIndexByDirection(CameraLensDirection direction) {
    if (!isInitialized) return null;
    
    final index = _cameras!.indexWhere(
      (camera) => camera.lensDirection == direction,
    );
    
    return index >= 0 ? index : null;
  }

  // ================== PERMISSIONS ==================

  /// Check current camera permission status
  static Future<PermissionStatus> checkCameraPermission() async {
    try {
      final status = await Permission.camera.status;
      print('Camera permission status: $status');
      return status;
    } catch (e) {
      print('Error checking camera permission: $e');
      throw CameraException('permission_check_failed', 'Failed to check camera permission: $e');
    }
  }

  /// Request camera permission
  static Future<bool> requestCameraPermission() async {
    try {
      print('Requesting camera permission...');
      final status = await Permission.camera.request();
      final granted = status == PermissionStatus.granted;
      
      print('Camera permission ${granted ? 'granted' : 'denied'}: $status');
      return granted;
    } catch (e) {
      print('Error requesting camera permission: $e');
      throw CameraException('permission_request_failed', 'Failed to request camera permission: $e');
    }
  }

  /// Check if camera permission is granted
  static Future<bool> hasPermission() async {
    final status = await checkCameraPermission();
    return status == PermissionStatus.granted;
  }

  /// Ensure camera permission is granted
  static Future<bool> ensurePermission() async {
    if (await hasPermission()) {
      return true;
    }
    
    return await requestCameraPermission();
  }

  // ================== CAMERA CONTROLLER ==================

  /// Create and initialize camera controller
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
      print('Camera controller initialized successfully');
      
      return controller;
    } catch (e) {
      print('Error creating camera controller: $e');
      throw CameraException('controller_creation_failed', 'Failed to create camera controller: $e');
    }
  }

  /// Get default camera controller (front camera preferred)
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

  /// Take picture with given controller
  static Future<XFile> takePicture(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) {
        throw CameraException('controller_not_initialized', 'Camera controller not initialized');
      }

      print('Taking picture...');
      final XFile photo = await controller.takePicture();
      
      print('Picture taken successfully: ${photo.path}');
      print('File size: ${await File(photo.path).length()} bytes');
      
      return photo;
    } catch (e) {
      print('Error taking picture: $e');
      throw CameraException('capture_failed', 'Failed to take picture: $e');
    }
  }

  /// Take picture and save to specific directory
  static Future<String> takePictureToPath(
    CameraController controller,
    String fileName,
  ) async {
    try {
      final photo = await takePicture(controller);
      
      // Get app documents directory
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String dirPath = '${appDocDir.path}/attendance_photos';
      
      // Create directory if not exists
      final Directory photoDir = Directory(dirPath);
      if (!await photoDir.exists()) {
        await photoDir.create(recursive: true);
      }
      
      // Create file path
      final String filePath = '$dirPath/$fileName';
      
      // Copy file to new location
      await File(photo.path).copy(filePath);
      
      // Delete original temp file
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

  /// Get available resolution presets for camera
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

  /// Get recommended resolution preset for attendance photos
  static ResolutionPreset getRecommendedResolution() {
    return ResolutionPreset.medium; // Good balance of quality and file size
  }

  /// Generate unique filename for attendance photo
  static String generateAttendancePhotoName(String userId, String type) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${userId}_${type}_$timestamp.jpg';
  }

  /// Validate camera configuration
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

  /// Get camera info string for debugging
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
    
    for (int i = 0; i < _cameras!.length; i++) {
      final camera = _cameras![i];
      buffer.writeln('- Camera $i: ${camera.name} (${camera.lensDirection})');
    }
    
    return buffer.toString();
  }

  // ================== ERROR HANDLING ==================

  /// Handle camera exceptions
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