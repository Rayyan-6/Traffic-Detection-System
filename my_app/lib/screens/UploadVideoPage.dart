import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class UploadVideoPage extends StatefulWidget {
  const UploadVideoPage({super.key});

  @override
  State<UploadVideoPage> createState() => _UploadVideoPageState();
}

class _UploadVideoPageState extends State<UploadVideoPage> {
  File? _pickedFile;
  bool _isLoading = false;
  Map<String, dynamic>? _result;

  final picker = ImagePicker();

  // ✅ Pick Image from gallery
  Future<void> pickImage() async {
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _pickedFile = File(file.path);
      });
      uploadFile();
    }
  }

  // ✅ Pick Video from gallery
  Future<void> pickVideo() async {
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _pickedFile = File(file.path);
      });
      uploadFile();
    }
  }

  // ✅ Upload the file to FastAPI backend
  Future<void> uploadFile() async {
    if (_pickedFile == null) return;

    setState(() {
      _isLoading = true;
      _result = null;
    });

    final uri = Uri.parse("http://192.168.10.4:8000/upload");  // <-- YOUR SERVER IP

    final request = http.MultipartRequest("POST", uri);
    request.files.add(await http.MultipartFile.fromPath(
      "file",
      _pickedFile!.path,
    ));

    try {
      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        setState(() {
          _result = jsonDecode(respStr);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        print("Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print("Error uploading: $e");
    }
  }

  // ✅ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload Video or Image")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ✅ Upload Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text("Pick Image"),
                  onPressed: pickImage,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.video_library),
                  label: const Text("Pick Video"),
                  onPressed: pickVideo,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ✅ Show Selected File Preview
            if (_pickedFile != null)
              Column(
                children: [
                  Text("Selected: ${_pickedFile!.path.split('/').last}"),
                  const SizedBox(height: 10),
                  if (_pickedFile!.path.endsWith(".jpg") ||
                      _pickedFile!.path.endsWith(".png"))
                    Image.file(_pickedFile!, height: 150),
                ],
              ),

            const SizedBox(height: 20),

            // ✅ Show Loading
            if (_isLoading) const CircularProgressIndicator(),

            // ✅ Show Results
            if (_result != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        "Detection Result:",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(jsonEncode(_result), textAlign: TextAlign.left),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
