// screens/camera_selfie_screen.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';

class CameraSelfieScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraSelfieScreen({super.key, required this.cameras});

  @override
  State<CameraSelfieScreen> createState() => _CameraSelfieScreenState();
}

class _CameraSelfieScreenState extends State<CameraSelfieScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;
  int _selectedCameraIndex = 0;
  static const Color primaryColor = Color(0xFF009688);

  @override
  void initState() {
    super.initState();
    _selectedCameraIndex = CameraService.getPreferredCameraIndex();
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      final camera = widget.cameras[_selectedCameraIndex];
      await _controller?.dispose();

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Error initializing selfie camera: $e');
      if (mounted) {
        _showSnackBar('Gagal menginisialisasi kamera: $e');
      }
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    setState(() {
      _isInitialized = false;
    });
    _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    await _initializeController();
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile photo = await _controller!.takePicture();
      if (mounted) {
        Navigator.pop(context, photo.path);
      }
    } catch (e) {
      print('Error take picture: $e');
      if (mounted) {
        _showSnackBar('Gagal mengambil foto: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    final media = MediaQuery.of(context);
    final overlayWidth = media.size.width * 0.7;
    final overlayHeight = media.size.height * 0.45;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ambil Selfie untuk Absensi'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: widget.cameras.length > 1 ? _switchCamera : null,
            tooltip: 'Ganti kamera',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera Preview
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize!.height,
                height: _controller!.value.previewSize!.width,
                child: CameraPreview(_controller!),
              ),
            ),
          ),

          // Top Instructions
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.face, color: primaryColor, size: 28),
                  const SizedBox(height: 6),
                  const Text(
                    'Posisikan wajah Anda di dalam frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'untuk absensi',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // Face Frame Overlay
          Center(
            child: Container(
              width: overlayWidth,
              height: overlayHeight,
              decoration: BoxDecoration(
                border: Border.all(color: primaryColor, width: 3),
                borderRadius: BorderRadius.circular(18),
                color: Colors.transparent,
              ),
              child: Container(
                margin: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: primaryColor.withOpacity(0.4),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          // Bottom Control Buttons
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Cancel Button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.85),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                ),

                // Capture Button
                GestureDetector(
                  onTap: _isCapturing ? null : _takePicture,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: _isCapturing ? Colors.grey : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: primaryColor, width: 4),
                    ),
                    child: _isCapturing
                        ? CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              primaryColor,
                            ),
                          )
                        : Icon(Icons.camera_alt, size: 40, color: primaryColor),
                  ),
                ),

                // Switch Camera Button
                GestureDetector(
                  onTap: widget.cameras.length > 1 ? _switchCamera : null,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: widget.cameras.length > 1
                          ? primaryColor.withOpacity(0.85)
                          : Colors.grey.withOpacity(0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.flip_camera_ios,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Instructions
          Positioned(
            bottom: 140,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: primaryColor, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Pastikan wajah terlihat jelas dan dalam pencahayaan yang baik',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}