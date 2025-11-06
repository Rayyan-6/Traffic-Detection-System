import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:image/image.dart' as img;

class LiveCameraPage extends StatefulWidget {
  const LiveCameraPage({super.key});

  @override
  State<LiveCameraPage> createState() => _LiveCameraPageState();
}

class _LiveCameraPageState extends State<LiveCameraPage> {
  CameraController? _cameraController;
  late WebSocketChannel _channel;
  bool _isSending = false;
  int frameSkip = 0;

  int smallCount = 0;
  int bigCount = 0;
  int totalCount = 0;
  List<dynamic> detectedBoxes = [];
  Size? previewSize;
  double frameW = 0, frameH = 0;



  // Added for better error handling
  bool _isInitialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _isInitialized = false;
    _initError = null;
    initWebSocket();
    // ✅ Request permissions first, then init camera
    requestPermissions().then((granted) {
      print("Initial permission result: $granted");  // ✅ Debug log
      if (granted && mounted) {
        initCamera();
      } else if (mounted) {
        setState(() {
          _initError = "Camera permission denied. Please grant access to use live detection.";
        });
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _channel.sink.close();
    super.dispose();
  }

  // ✅ Enhanced: Request camera permission with rationale dialog
  Future<bool> requestPermissions() async {
    try {
      // Check current status
      var status = await Permission.camera.status;
      print("Current camera status: $status");  // ✅ Debug log

      if (status.isGranted) {
        print("Camera permission already granted");
        return true;
      }

      if (status.isDenied) {
        // ✅ Show rationale dialog before requesting
        final shouldRequest = await _showPermissionRationale();
        if (!shouldRequest) return false;

        // Now request
        status = await Permission.camera.request();
        print("After request status: $status");  // ✅ Debug log
      }

      if (status.isPermanentlyDenied) {
        print("Permission permanently denied, opening settings");
        await openAppSettings();
        // Wait a bit for user to return, then re-check
        await Future.delayed(const Duration(seconds: 2));
        status = await Permission.camera.status;
        print("Status after settings: $status");  // ✅ Debug log
      }

      return status.isGranted;
    } catch (e) {
      print("Permission request error: $e");
      return false;
    }
  }

  // ✅ Fixed: Show user-friendly rationale dialog (explicit await and null handling)
  Future<bool> _showPermissionRationale() async {
    // ✅ Explicitly await the dialog and handle null as false
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,  // Force user to decide
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Camera Access Needed"),
          content: const Text(
            "This app requires camera permission to perform live vehicle detection from your camera feed. "
            "The video is processed securely on your device and sent to the backend for analysis. "
            "Without this, live mode won't work.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),  // Deny
              child: const Text("Deny"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),  // Allow
              child: const Text("Grant Permission"),
            ),
          ],
        );
      },
    );

    // ✅ Coerce null (dismissed) to false for non-nullable return
    return result ?? false;
  }

  // ✅ Initialize WebSocket (unchanged)
  void initWebSocket() {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse("ws://192.168.10.4:8000/ws"),  // Change to your PC IP if on physical device
      );

      _channel.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data);

            if (mounted) {
              setState(() {
                smallCount = decoded["small"] ?? 0;
                bigCount = decoded["big"] ?? 0;
                totalCount = decoded["total"] ?? 0;
                frameW = decoded["frame_width"]?.toDouble() ?? 0;
                frameH = decoded["frame_height"]?.toDouble() ?? 0;
                detectedBoxes = decoded["boxes"];  
              });
            }
          } catch (e) {
            print("JSON decode error: $e");
          }
        },
        onError: (error) {
          print("WebSocket error: $error");
          if (mounted && _initError == null) {
            setState(() {
              _initError = "WebSocket connection failed: $error";
            });
          }
        },
        onDone: () {
          print("WebSocket closed");
        },
      );

    } catch (e) {
      print("WebSocket init error: $e");
      if (mounted) {
        setState(() {
          _initError = "Failed to connect to WebSocket: $e";
        });
      }
    }
  }

  // ✅ Initialize Camera (unchanged but with log)
  Future<void> initCamera() async {
    try {
      // Double-check permission before proceeding
      if (!await Permission.camera.isGranted) {
        throw Exception("Camera permission not granted");
      }

      print("Starting camera initialization...");  // ✅ Debug log

      // Check for available cameras
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception("No cameras available. Try a physical device.");
      }
      final camera = cameras.first;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      previewSize = Size(
  _cameraController!.value.previewSize!.height,
  _cameraController!.value.previewSize!.width,
);

      if (!mounted) return;

      print("Camera initialized successfully!");  // ✅ Debug log

      setState(() {
        _isInitialized = true;
        _initError = null; // Clear any previous errors
      });

      // ✅ Start streaming with delay (prevents freeze)
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _isInitialized) {
          startImageStream();
        }
      });

    } catch (e) {
      print("Camera init error: $e");
      if (mounted) {
        setState(() {
          _initError = "Camera initialization failed: $e\n\nTips:\n- Ensure permissions are granted.\n- Use a physical device (emulators often fail).\n- Check AndroidManifest.xml for camera permission.";
          _isInitialized = false;
        });
      }
    }
  }

  // ✅ Start image stream safely (unchanged)
  void startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print("Camera not ready");
      return;
    }

    print("Starting image stream...");  // ✅ Debug log

    _cameraController!.startImageStream((CameraImage image) async {
      // ✅ Skip some frames to avoid overloading backend (every 3rd frame)
      frameSkip++;
      if (frameSkip % 3 != 0) return;

      if (_isSending) return;
      _isSending = true;

      try {
        Uint8List jpeg = await convertYUV420toJPEG(image);

        if (jpeg.isNotEmpty) {
          final base64Image = base64Encode(jpeg);
          _channel.sink.add(base64Image);
        }
      } catch (e) {
        print("Frame send error: $e");
      }

      _isSending = false;
    });
  }

  // ✅ YUV420 to JPEG conversion (unchanged)
  Future<Uint8List> convertYUV420toJPEG(CameraImage image) async {
    try {
      final int width = image.width;
      final int height = image.height;

      // Plane Y (luminance)
      final Plane planeY = image.planes[0];
      final Plane planeU = image.planes[1];
      final Plane planeV = image.planes[2];

      final Uint8List yBuffer = planeY.bytes;
      final Uint8List uBuffer = planeU.bytes;
      final Uint8List vBuffer = planeV.bytes;

      // Create empty RGB image
      final img.Image rgbImage =
          img.Image(width: width, height: height);

      int uvRowStride = planeU.bytesPerRow;
      int uvPixelStride = planeU.bytesPerPixel!;

      // YUV420 → RGB conversion
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          int yIndex = y * planeY.bytesPerRow + x;

          int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          int yp = yBuffer[yIndex];
          int up = uBuffer[uvIndex];
          int vp = vBuffer[uvIndex];

          // Convert YUV to RGB
          int r = (yp + 1.402 * (vp - 128)).clamp(0, 255).toInt();
          int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128))
              .clamp(0, 255)
              .toInt();
          int b = (yp + 1.772 * (up - 128)).clamp(0, 255).toInt();

          rgbImage.setPixelRgb(x, y, r, g, b);
        }
      }

      // Convert to JPEG
      final jpeg = img.encodeJpg(rgbImage, quality: 50);

      return Uint8List.fromList(jpeg);
    } catch (e) {
      print("YUV conversion error: $e");
      return Uint8List(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show error if initialization failed
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Live Camera Detection")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  "Initialization Error",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(_initError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    print("Retry button pressed");  // ✅ Debug log
                    setState(() {
                      _initError = null;
                      _isInitialized = false;
                      _cameraController?.dispose();
                      _cameraController = null;
                    });
                    // ✅ Retry with fresh permission request + rationale
                    final granted = await requestPermissions();
                    if (granted && mounted) {
                      await initCamera();
                    } else if (mounted) {
                      setState(() {
                        _initError = "Permission still denied. Check device settings and try again.";
                      });
                    }
                  },
                  child: const Text("Retry & Request Permissions"),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    print("Opening app settings");  // ✅ Debug log
                    await openAppSettings();
                  },
                  child: const Text("Open App Settings"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show loading if not initialized
    if (!_isInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Live Camera Detection")),
      body: Stack(
        children: [
          CameraPreview(_cameraController!),

          // ✅ Draw bounding boxes
        if (previewSize != null && frameW != 0)
      CustomPaint(
        painter: BoxPainter(
          detectedBoxes,
          previewSize!,
          frameW,
          frameH,
        ),
        size: Size.infinite,
      ),
      ////////////////////////////////
      ///
      ///
          Positioned(
            top: 30,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Total: $totalCount\nSmall: $smallCount\nBig: $bigCount",
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          )
        ],
      ),
    );
  }
}


class BoxPainter extends CustomPainter {
  final List<dynamic> boxes;
  final Size previewSize;
  final double frameW;
  final double frameH;

  BoxPainter(this.boxes, this.previewSize, this.frameW, this.frameH);

  @override
  void paint(Canvas canvas, Size size) {
    if (frameW == 0 || frameH == 0) return;

    // ✅ Scale factors to convert YOLO → camera preview
    double scaleX = size.width / frameW;
    double scaleY = size.height / frameH;

    Paint boxPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    Paint textBg = Paint()
      ..color = Colors.black.withOpacity(0.6);

    for (var box in boxes) {
      double x1 = box["x1"] * scaleX;
      double y1 = box["y1"] * scaleY;
      double x2 = box["x2"] * scaleX;
      double y2 = box["y2"] * scaleY;

      // ✅ Draw box
      Rect rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, boxPaint);

      // ✅ Draw label
      final label = "${box['class']} ${(box['conf'] * 100).toInt()}%";
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      // Background
      canvas.drawRect(
        Rect.fromLTWH(x1, y1 - 20, textPainter.width + 6, 20),
        textBg,
      );

      textPainter.paint(canvas, Offset(x1 + 3, y1 - 18));
    }
  }

  @override
  bool shouldRepaint(BoxPainter oldDelegate) => true;
}
















