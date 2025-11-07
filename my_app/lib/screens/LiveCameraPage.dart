import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  WebSocketChannel? _channel;
  bool _isSending = false;
  int frameSkip = 0;

  int smallCount = 0;
  int bigCount = 0;
  int totalCount = 0;

  List<dynamic> detectedBoxes = [];
  double frameW = 0, frameH = 0;

  bool _isInitialized = false;
  String? _initError;
  bool _isConnecting = true;

  @override
  void initState() {
    super.initState();
    // Force landscape orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    
    initWebSocket();
    requestPermissions().then((granted) {
      if (granted) initCamera();
      else setState(() => _initError = "Camera permission denied.");
    });
  }

  @override
  void dispose() {
    // Reset orientation when leaving
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    _cameraController?.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  void initWebSocket() {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse("ws://192.168.10.4:8000/ws"),
      );
      print("WebSocket connecting...");

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data);
            print("Received: total=${decoded['total']}, boxes=${decoded['boxes']?.length}, frameW=${decoded['frame_width']}, frameH=${decoded['frame_height']}");
            if (mounted) {
              setState(() {
                smallCount = decoded["small"] ?? 0;
                bigCount = decoded["big"] ?? 0;
                totalCount = decoded["total"] ?? 0;
                frameW = decoded["frame_width"]?.toDouble() ?? 0;
                frameH = decoded["frame_height"]?.toDouble() ?? 0;
                detectedBoxes = decoded["boxes"] ?? [];
                _isConnecting = false;
              });
            }
          } catch (e) {
            print("JSON error: $e");
          }
        },
        onError: (error) {
          print("WebSocket error: $error");
          if (mounted) {
            setState(() {
              _initError = "Connection lost: $error. Check backend IP/port.";
              _isConnecting = false;
            });
          }
        },
        onDone: () {
          print("WebSocket closed");
          if (mounted) setState(() => _isConnecting = false);
        },
      );
    } catch (e) {
      print("WebSocket init error: $e");
      if (mounted) setState(() => _initError = "WebSocket failed: $e");
    }
  }

  Future<bool> requestPermissions() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;
    status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<void> initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw "No cameras available.";

      final camera = cameras.first;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      print("Camera initialized - Sensor orientation: ${camera.sensorOrientation}");
      print("Preview size: ${_cameraController!.value.previewSize}");

      if (!mounted) return;

      setState(() => _isInitialized = true);

      Future.delayed(const Duration(milliseconds: 300), startImageStream);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = "Camera initialization error: $e";
        });
      }
    }
  }

  void startImageStream() {
    if (_cameraController == null) return;

    _cameraController!.startImageStream((CameraImage image) async {
      frameSkip++;
      if (frameSkip % 3 != 0) return;
      if (_isSending) return;

      _isSending = true;

      try {
        Uint8List jpeg = await convertYUV420toJPEG(image);
        if (jpeg.isNotEmpty) {
          final base64Image = base64Encode(jpeg);
          _channel?.sink.add(base64Image);
        }
      } catch (e) {
        print("Frame send error: $e");
      }

      _isSending = false;
    });
  }

  Future<Uint8List> convertYUV420toJPEG(CameraImage image) async {
    try {
      final width = image.width;
      final height = image.height;

      final y = image.planes[0].bytes;
      final u = image.planes[1].bytes;
      final v = image.planes[2].bytes;

      final rgb = img.Image(width: width, height: height);

      int uvRow = image.planes[1].bytesPerRow;
      int uvPixel = image.planes[1].bytesPerPixel!;

      for (int yPos = 0; yPos < height; yPos++) {
        for (int xPos = 0; xPos < width; xPos++) {
          int yp = y[yPos * image.planes[0].bytesPerRow + xPos];
          int up = u[(yPos ~/ 2) * uvRow + (xPos ~/ 2) * uvPixel];
          int vp = v[(yPos ~/ 2) * uvRow + (xPos ~/ 2) * uvPixel];

          int r = (yp + 1.402 * (vp - 128)).clamp(0, 255).toInt();
          int g = (yp - 0.344 * (up - 128) - 0.714 * (vp - 128)).clamp(0, 255).toInt();
          int b = (yp + 1.772 * (up - 128)).clamp(0, 255).toInt();

          rgb.setPixelRgb(xPos, yPos, r, g, b);
        }
      }

      return Uint8List.fromList(img.encodeJpg(rgb, quality: 50));
    } catch (e) {
      print("YUV conversion error: $e");
      return Uint8List(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    "Error: $_initError",
                    style: const TextStyle(color: Colors.redAccent, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _initError = null;
                        _isInitialized = false;
                        _isConnecting = true;
                        _cameraController?.dispose();
                        _cameraController = null;
                        detectedBoxes.clear();
                        smallCount = bigCount = totalCount = 0;
                      });
                      initWebSocket();
                      requestPermissions().then((granted) {
                        if (granted) initCamera();
                      });
                    },
                    child: const Text("Retry"),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text("Initializing camera...", style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview - Full screen
          Positioned.fill(
            child: CameraPreview(_cameraController!),
          ),

          // Bounding Boxes Overlay
          if (frameW > 0 && frameH > 0 && detectedBoxes.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: BoxPainter(
                  detectedBoxes,
                  frameW,
                  frameH,
                ),
              ),
            ),

          // Glass App Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildGlassAppBar(context),
          ),

          // Stats Card
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: _buildStatsCard(_isConnecting),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.65),
            Colors.black.withOpacity(0.1),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: _glassCircle(Icons.arrow_back),
            ),
            Expanded(
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Live Detection ",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const CircleAvatar(radius: 5, backgroundColor: Colors.green),
                  ],
                ),
              ),
            ),
            _glassCircle(Icons.settings),
          ],
        ),
      ),
    );
  }

  Widget _glassCircle(IconData icon) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      );

  Widget _buildStatsCard(bool isConnecting) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: isConnecting
          ? const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text("Connecting...", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem("Total", totalCount, Colors.orangeAccent),
                _statItem("Small", smallCount, Colors.greenAccent),
                _statItem("Large", bigCount, Colors.redAccent),
              ],
            ),
    );
  }

  Widget _statItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          "$value",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.85),
          ),
        ),
      ],
    );
  }
}

class BoxPainter extends CustomPainter {
  final List<dynamic> boxes;
  final double frameW;
  final double frameH;

  BoxPainter(this.boxes, this.frameW, this.frameH);

  @override
  void paint(Canvas canvas, Size size) {
    if (frameW == 0 || frameH == 0 || boxes.isEmpty) {
      print("BoxPainter: Skipping - frameW=$frameW, frameH=$frameH, boxes=${boxes.length}");
      return;
    }

    print("BoxPainter: Drawing ${boxes.length} boxes on canvas ${size.width}x${size.height}, frame ${frameW}x$frameH");

    // Calculate scale factors
    final scaleX = size.width / frameW;
    final scaleY = size.height / frameH;

    print("BoxPainter: Scale factors - scaleX=$scaleX, scaleY=$scaleY");

    final boxPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final textBg = Paint()..color = Colors.black.withOpacity(0.7);

    for (int i = 0; i < boxes.length; i++) {
      var box = boxes[i];
      
      final x1 = (box["x1"] as num).toDouble() * scaleX;
      final y1 = (box["y1"] as num).toDouble() * scaleY;
      final x2 = (box["x2"] as num).toDouble() * scaleX;
      final y2 = (box["y2"] as num).toDouble() * scaleY;

      if (i == 0) {
        print("BoxPainter: Box 0 - original: (${box["x1"]}, ${box["y1"]}, ${box["x2"]}, ${box["y2"]})");
        print("BoxPainter: Box 0 - scaled: ($x1, $y1, $x2, $y2)");
      }

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, boxPaint);

      final className = box['class_name'] ?? box['class'] ?? 'Unknown';
      final conf = ((box['confidence'] ?? box['conf'] ?? 0.0) as num).toDouble() * 100;
      final label = "$className ${conf.toInt()}%";

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout(minWidth: 0, maxWidth: x2 - x1);
      
      final bgRect = Rect.fromLTWH(
        x1,
        y1 - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        textBg,
      );
      
      textPainter.paint(canvas, Offset(x1 + 4, y1 - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(BoxPainter oldDelegate) => true;
}