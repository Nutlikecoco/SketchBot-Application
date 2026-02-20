import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import 'robot_page.dart';
import 'api_config.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditPage extends StatefulWidget {
  final String imagePath;
  final String? category;

  const EditPage({super.key, required this.imagePath, this.category});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late String currentImagePath;
  Uint8List? currentImageBytes;
  bool isProcessing = false;
  late String originalImagePath;
  @override
  void initState() {
    super.initState();
    currentImagePath = widget.imagePath;
    originalImagePath = widget.imagePath;
  }

  Future<void> uploadImageToFirebase(String imagePath,
      {String? customFileName}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in");

      // ✅ โหลดไฟล์จาก assets หรือ path จริง
      File file;
      if (imagePath.startsWith('assets/')) {
        final byteData = await rootBundle.load(imagePath);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${imagePath.split('/').last}');
        await tempFile.writeAsBytes(byteData.buffer.asUint8List());
        file = tempFile;
      } else {
        file = File(imagePath);
      }

      final fileName = customFileName ??
          "drawn_result_${DateTime.now().millisecondsSinceEpoch}.png";

      // ✅ ใช้ email เป็นชื่อโฟลเดอร์หลัก (ตรงกับ MyGallery)
      final emailFolder = user.email!;
      final ref =
          FirebaseStorage.instance.ref().child("$emailFolder/$fileName");

      // ✅ อัปโหลดไฟล์ขึ้น Firebase Storage
      await ref.putFile(file);
      final downloadURL = await ref.getDownloadURL();

      // ✅ บันทึก metadata ไปยัง Firestore ที่ MyGallery ใช้อยู่
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.email)
          .collection("my_images")
          .add({
        "url": downloadURL,
        "timestamp": DateTime.now().toIso8601String(),
        "filename": fileName,
      });
    } catch (e, st) {
      debugPrintStack(stackTrace: st);
    }
  }

  // =========================================================
  // 🔹 REMOVE BACKGROUND
  // =========================================================
  Future<void> removeBackground() async {
    debugPrint("✅ removeBackground called (local Flask API)");
    try {
      setState(() => isProcessing = true);

      // ✅ ส่งภาพไปยัง Flask server
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.removeBgLocal),
      );

      // ชื่อ field ต้องตรงกับ Flask → request.files['image']
      request.files
          .add(await http.MultipartFile.fromPath('image', currentImagePath));

      final response = await request.send();

      if (response.statusCode == 200) {
        // ✅ รับไฟล์ภาพที่ลบพื้นหลังแล้ว (PNG โปร่งใส)
        final respBytes = await response.stream.toBytes();

        // เก็บเป็นไฟล์ชั่วคราว
        final tempDir = await getTemporaryDirectory();
        final uniqueName = const Uuid().v4();
        final newFile = File('${tempDir.path}/removed_bg_$uniqueName.png');
        await newFile.writeAsBytes(respBytes);

        if (!mounted) return;
        setState(() {
          currentImagePath = newFile.path;
          currentImageBytes = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ ลบพื้นหลังสำเร็จ")),
        );
      } else {
        final errorMsg = await response.stream.bytesToString();
        if (!mounted) return;
        _showLogDialog("❌ Remove BG error: $errorMsg");
      }
    } catch (e) {
      if (!mounted) return;
      _showLogDialog("เกิดข้อผิดพลาด: $e");
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _showLogDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Log / Error"),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ปิด"),
          ),
        ],
      ),
    );
  }

  Future<String?> uploadImageToROS(String imagePath) async {
    try {
      final uri = Uri.parse("http://192.168.1.177:8001/upload"); // 🌐 IP Ubuntu
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));

      final response = await request.send();
      if (response.statusCode == 200) {
        final respBody = await response.stream.bytesToString();
        final json = jsonDecode(respBody);
        debugPrint("✅ Upload OK: ${json['path']}");
        return json['path']; // ✅ คืน path ที่ ROS เข้าถึงได้
      } else {
        debugPrint("❌ Upload failed: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("⚠️ Upload exception: $e");
      return null;
    }
  }

  // =========================================================
  // 🎨 CONVERT TO SKETCH
  // =========================================================
  Future<File> convertToSketch(String path, {String mode = "basic"}) async {
    String realPath = path;
    if (path.startsWith('assets/') && !kIsWeb) {
      final byteData = await rootBundle.load(path);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/asset_copy.png');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());
      realPath = tempFile.path;
    }

    final bytes = await File(realPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return File(realPath);

    img.Image gray = img.grayscale(image);
    gray = img.gaussianBlur(gray, radius: 1); // soften edges
    late img.Image processed;

    if (mode == "basic") {
      processed = _smartSketch(gray); // ✅ auto threshold
    } else if (mode == "anime") {
      processed = _adaptiveThreshold(gray, blockSize: 9, C: 2);
    } else if (mode == "portrait") {
      final edges = _cannyEdge(gray, low: 60, high: 150);
      processed = _dilate(edges, kernelSize: 1, iterations: 2);
    } else {
      processed = _smartSketch(gray);
    }

    final tempDir = await getTemporaryDirectory();
    final sketchFile = File('${tempDir.path}/sketch_${const Uuid().v4()}.png');
    await sketchFile.writeAsBytes(img.encodePng(processed));
    return sketchFile;
  }

  // =========================================================
  // 🧠 IMAGE PROCESSING HELPERS
  // =========================================================
  img.Image _smartSketch(img.Image gray) {
    // 🔹 ขั้นแรก: ทำ Blur เล็กน้อยให้เรียบก่อน
    img.Image smooth = img.gaussianBlur(gray, radius: 2);

    // 🔹 ขั้นที่สอง: หาขอบด้วย Sobel (เส้นจะเด่นเฉพาะส่วน contrast)
    img.Image sobel = img.sobel(smooth);

    // 🔹 ขั้นที่สาม: ทำ normalization ให้ contrast สูงขึ้น
    int minLum = 255, maxLum = 0;
    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        if (lum < minLum) minLum = lum;
        if (lum > maxLum) maxLum = lum;
      }
    }

    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        num normalized =
            ((lum - minLum) * 255 / (maxLum - minLum + 1)).clamp(0, 255);
        int newVal = normalized.toInt();
        sobel.setPixelRgb(x, y, newVal, newVal, newVal);
      }
    }

    // 🔹 ขั้นที่สี่: Threshold → พื้นขาว เส้นดำ
    final result = sobel.clone();
    int threshold = 100;
    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        int val = (lum > threshold) ? 0 : 255; // ✅ พื้นขาว เส้นดำ
        result.setPixelRgb(x, y, val, val, val);
      }
    }

    // 🔹 ขั้นที่ห้า: ขยายเส้นให้ต่อเนื่องขึ้นเล็กน้อย
    return _dilate(result, kernelSize: 1, iterations: 1);
  }

  img.Image _adaptiveThreshold(img.Image gray, {int blockSize = 9, int C = 2}) {
    final result = gray.clone();

    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        int sum = 0;
        int count = 0;

        for (int j = -blockSize ~/ 2; j <= blockSize ~/ 2; j++) {
          for (int i = -blockSize ~/ 2; i <= blockSize ~/ 2; i++) {
            final int px = (x + i).clamp(0, gray.width - 1);
            final int py = (y + j).clamp(0, gray.height - 1);
            final pixel = gray.getPixel(px, py);
            sum += ((pixel.r + pixel.g + pixel.b) / 3).toInt();
            count++;
          }
        }

        final int mean = (sum / count).toInt();
        final pixel = gray.getPixel(x, y);
        final int luminance = ((pixel.r + pixel.g + pixel.b) / 3).toInt();
        final int newVal = (luminance < mean - C) ? 0 : 255;
        result.setPixelRgb(x, y, newVal, newVal, newVal);
      }
    }
    return _dilate(result, kernelSize: 1, iterations: 1);
  }

// =========================================================
// 🖋️ ปรับโหมด SKETCH ให้เส้นคมและครบมากขึ้น (แบบละเอียด)
// =========================================================
  img.Image _cannyEdge(img.Image gray, {int low = 25, int high = 110}) {
    // ✅ 1. ลด noise และทำให้แสงเงานุ่มขึ้น
    img.Image smooth = img.gaussianBlur(gray, radius: 2);

    // ✅ 2. คำนวณ Laplacian of Gaussian (จับขอบ + เงา)
    final kernel = [
      [0, 1, 0],
      [1, -4, 1],
      [0, 1, 0],
    ];
    final result = img.Image.from(smooth);
    final width = smooth.width;
    final height = smooth.height;

    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    final response =
        List.generate(height, (_) => List<double>.filled(width, 0));

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        double val = 0;
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            final px = smooth.getPixel(x + i, y + j);
            final lum = ((px.r + px.g + px.b) / 3);
            val += lum * kernel[j + 1][i + 1];
          }
        }
        response[y][x] = val;
        if (val < minVal) minVal = val;
        if (val > maxVal) maxVal = val;
      }
    }

    // ✅ 3. Normalize และ invert เพื่อให้เส้นชัด
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final norm = ((response[y][x] - minVal) / (maxVal - minVal + 1)) * 255;
        final val = (255 - norm).clamp(0, 255).toInt();
        result.setPixelRgb(x, y, val, val, val);
      }
    }

    // ✅ 4. Adaptive threshold (ทำให้เส้นชัดขึ้น)
    final out = result.clone();
    const block = 9;
    const C = 4;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int sum = 0, count = 0;
        for (int j = -block ~/ 2; j <= block ~/ 2; j++) {
          for (int i = -block ~/ 2; i <= block ~/ 2; i++) {
            final xi = (x + i).clamp(0, width - 1);
            final yj = (y + j).clamp(0, height - 1);
            final p = result.getPixel(xi, yj);
            sum += ((p.r + p.g + p.b) ~/ 3);
            count++;
          }
        }
        final mean = (sum / count).toInt();
        final p = result.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) ~/ 3);
        final val = (lum < mean - C) ? 0 : 255;
        out.setPixelRgb(x, y, val, val, val);
      }
    }
    img.Image _erode(img.Image src, {int kernelSize = 1, int iterations = 1}) {
      img.Image out = src.clone();

      for (int n = 0; n < iterations; n++) {
        for (int y = 1; y < src.height - 1; y++) {
          for (int x = 1; x < src.width - 1; x++) {
            int minVal = 255;
            for (int j = -kernelSize; j <= kernelSize; j++) {
              for (int i = -kernelSize; i <= kernelSize; i++) {
                final int xi = (x + i).clamp(0, src.width - 1);
                final int yj = (y + j).clamp(0, src.height - 1);
                final pixel = src.getPixel(xi, yj);
                final int lum = ((pixel.r + pixel.g + pixel.b) / 3).toInt();
                if (lum < minVal) minVal = lum;
              }
            }
            out.setPixelRgb(x, y, minVal, minVal, minVal);
          }
        }
      }
      return out;
    }

    final closed = _erode(_dilate(out, kernelSize: 1, iterations: 1),
        kernelSize: 1, iterations: 1);

    return closed;
  }

  img.Image _dilate(img.Image src, {int kernelSize = 1, int iterations = 1}) {
    img.Image out = src.clone();

    for (int n = 0; n < iterations; n++) {
      for (int y = 1; y < src.height - 1; y++) {
        for (int x = 1; x < src.width - 1; x++) {
          int maxVal = 0;
          for (int j = -kernelSize; j <= kernelSize; j++) {
            for (int i = -kernelSize; i <= kernelSize; i++) {
              final int xi = (x + i).clamp(0, src.width - 1);
              final int yj = (y + j).clamp(0, src.height - 1);
              final pixel = src.getPixel(xi, yj);
              final int luminance = ((pixel.r + pixel.g + pixel.b) / 3).toInt();
              if (luminance > maxVal) maxVal = luminance;
            }
          }
          out.setPixelRgb(x, y, maxVal, maxVal, maxVal);
        }
      }
    }
    return out;
  }

  // =========================================================
// ✨ SPECIAL PREVIEW AFTER REMOVE BACKGROUND
// =========================================================
  Future<File> convertToSketchAfterRemoveBg(String path) async {
    final bytes = await File(path).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return File(path);

    // ✅ 1. แยกเฉพาะพิกเซลที่ไม่โปร่งใส (วัตถุ)
    final img.Image mask = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 4,
    );
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final alpha = pixel.a; // transparency channel
        if (alpha > 50) {
          mask.setPixel(x, y, pixel); // keep object pixel
        } else {
          mask.setPixelRgb(x, y, 255, 255, 255); // background → white
        }
      }
    }

    // ✅ 2. ทำ grayscale + edge detection แบบเดิม
    img.Image gray = img.grayscale(mask);
    img.Image smooth = img.gaussianBlur(gray, radius: 2);
    img.Image sobel = img.sobel(smooth);

    // ✅ 3. Normalize ความสว่าง
    int minLum = 255, maxLum = 0;
    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        if (lum < minLum) minLum = lum;
        if (lum > maxLum) maxLum = lum;
      }
    }

    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        final normalized =
            ((lum - minLum) * 255 / (maxLum - minLum + 1)).clamp(0, 255);
        sobel.setPixelRgb(
            x, y, normalized.toInt(), normalized.toInt(), normalized.toInt());
      }
    }

// ✅ 4. Threshold → พื้นขาวเส้นดำ
    final result = sobel.clone();
    const threshold = 100;
    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        final val = (lum > threshold) ? 255 : 0;
        result.setPixelRgb(x, y, val, val, val);
      }
    }

// ✅ 5. Invert ให้เส้นดำพื้นขาว
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final p = result.getPixel(x, y);
        final inv = 255 - ((p.r + p.g + p.b) ~/ 3);
        result.setPixelRgb(x, y, inv, inv, inv);
      }
    }

// ✅ 6. ขยายเส้นให้คมขึ้น
    final finalImage = _dilate(result, kernelSize: 1, iterations: 1);

// ✅ 7. เซฟไฟล์
    final tempDir = await getTemporaryDirectory();
    final sketchFile =
        File('${tempDir.path}/sketch_removed_${const Uuid().v4()}.png');
    await sketchFile.writeAsBytes(img.encodePng(finalImage));
    return sketchFile;
  }

  // =========================================================
  // 🖼️ UI
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final isAsset = currentImagePath.startsWith('assets/');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Edit Image'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow, color: Colors.black),
            iconSize: 40,
            tooltip: "Start",
            onPressed: () async {
              String? videoUrl;
              String? videoUrlSmall;
              String? resultImageFileName;

              final fileName = currentImagePath.split('/').last.toLowerCase();

              // ----------------------
              // 🎞️ ANIME
              // ----------------------
              if (fileName.contains("lufy")) {
                videoUrl = "assets/videos/lufy.mp4";
                videoUrlSmall = "assets/videos/lufyup.mp4";
                resultImageFileName = "lu.png";
              } else if (fileName.contains("naruto")) {
                videoUrl = "assets/videos/naruto.mp4";
                videoUrlSmall = "assets/videos/narutoup.mp4";
                resultImageFileName = "naru.png";
              } else if (fileName.contains("hoshina")) {
                videoUrl = "assets/videos/hoshina.mp4";
                videoUrlSmall = "assets/videos/hoshinaup.mp4";
                resultImageFileName = "hoho.png";
              }

              // ----------------------
              // 🦫 CAPYBARA
              // ----------------------
              else if (fileName.contains("capybara_cake")) {
                videoUrl = "assets/videos/capybara_cake.mp4";
                videoUrlSmall = "assets/videos/capybara_cakeup.mp4";
                resultImageFileName = "cakena.png";
              } else if (fileName.contains("capybara_pudding")) {
                videoUrl = "assets/videos/capybara_pudding.mp4";
                videoUrlSmall = "assets/videos/capybara_puddingup.mp4";
                resultImageFileName = "pudd.png";
              } else if (fileName.contains("capybara_mac")) {
                videoUrl = "assets/videos/capybara_mac.mp4";
                videoUrlSmall = "assets/videos/capybara_macup.mp4";
                resultImageFileName = "macc.png";
              }

              // ----------------------
              // 🧸 CARTOON
              // ----------------------
              else if (fileName.contains("cartoon1")) {
                videoUrl = "assets/videos/cartoon1.mp4";
                videoUrlSmall = "assets/videos/cartoon1up.mp4";
                resultImageFileName = "rabbit.png";
              } else if (fileName.contains("cartoon2")) {
                videoUrl = "assets/videos/cartoon2.mp4";
                videoUrlSmall = "assets/videos/cartoon2up.mp4";
                resultImageFileName = "meowza.png";
              } else if (fileName.contains("cartoon3")) {
                videoUrl = "assets/videos/cartoon3.mp4";
                videoUrlSmall = "assets/videos/cartoon3up.mp4";
                resultImageFileName = "fire.png";
              } else if (fileName.contains("cartoon4")) {
                videoUrl = "assets/videos/cartoon4.mp4";
                videoUrlSmall = "assets/videos/cartoon4up.mp4";
                resultImageFileName = "poji.png";
              }

              try {
                setState(() => isProcessing = true);

                // ✅ ถ้ามีวิดีโอ → ให้อัปโหลดภาพสำเร็จรูปขึ้น Firebase โดยใช้ชื่อไฟล์ที่กำหนด
                if (videoUrl != null && resultImageFileName != null) {
                  try {
                    // ✅ โหลดรูปจาก assets ตามชื่อ preset (lu.png, naru.png ฯลฯ)
                    final byteData = await rootBundle
                        .load('assets/images/$resultImageFileName');
                    final tempDir = await getTemporaryDirectory();
                    final tempFile =
                        File('${tempDir.path}/$resultImageFileName');
                    await tempFile.writeAsBytes(byteData.buffer.asUint8List());

                    // ✅ อัปโหลดภาพ preset นี้ขึ้น Firebase My Gallery
                    await uploadImageToFirebase(tempFile.path,
                        customFileName: resultImageFileName);

                    // ✅ เปิดหน้า RobotPage ต่อ
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RobotPage(
                          videoUrl: videoUrl,
                          videoUrlSmall: videoUrlSmall,
                          imagePath: tempFile.path, // ใช้ path ของภาพจริง
                          categoryName: widget.category,
                        ),
                      ),
                    );
                  } catch (e) {
                    debugPrint("❌ Upload preset image failed: $e");
                    _showLogDialog(
                        "อัปโหลดภาพ $resultImageFileName ไม่สำเร็จ: $e");
                  }
                } else {
                  // 🔄 ถ้าไม่มีวิดีโอ → ส่งภาพไป ROS ตามปกติ
                  final uploadedPath = await uploadImageToROS(currentImagePath);
                  if (uploadedPath == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("❌ Upload ล้มเหลว!")),
                    );
                    setState(() => isProcessing = false);
                    return;
                  }

                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RobotPage(
                        videoUrl: videoUrl,
                        videoUrlSmall: videoUrlSmall,
                        imagePath: uploadedPath,
                        categoryName: widget.category,
                      ),
                    ),
                  );
                }
              } catch (e) {
                _showLogDialog("❌ Upload error: $e");
              } finally {
                setState(() => isProcessing = false);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: currentImageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child:
                          Image.memory(currentImageBytes!, fit: BoxFit.contain),
                    )
                  : isAsset
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(currentImagePath,
                              fit: BoxFit.contain),
                        )
                      : File(currentImagePath).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.file(File(currentImagePath),
                                  fit: BoxFit.contain),
                            )
                          : const Text('ไม่พบไฟล์รูปภาพ'),
            ),
          ),
          if (isProcessing)
            const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 30, top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _editIconButton(
                  icon: Icons.remove_circle_outline,
                  label: 'Remove background',
                  textColor: Colors.black,
                  onTap: removeBackground,
                ),
                _editIconButton(
                  icon: Icons.visibility_outlined,
                  label: 'Preview Line Art',
                  textColor: Colors.black,
                  backgroundColor: Colors.white,
                  onTap: () async {
                    if (kIsWeb) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text("ยังไม่รองรับ Preview Line Art บน Web")),
                      );
                      return;
                    }

                    try {
                      setState(() => isProcessing = true);

                      // ✅ เตรียมคำขอไปยัง Flask API
                      final uri = Uri.parse(
                          "http://192.168.1.117:8100/preview_line"); 
                      final request = http.MultipartRequest('POST', uri);
                      request.files.add(await http.MultipartFile.fromPath(
                          'image', currentImagePath));

                     
                      final cat = widget.category?.toLowerCase() ?? "";
                      String mode;
                      if (cat.contains("pet")) {
                        mode = "pet";
                      } else if (cat.contains("anime") ||
                          cat.contains("cartoon")) {
                        mode = "anime";
                      } else {
                        mode = "portrait";
                      }
                      request.fields['mode'] = mode;

                      // ✅ ส่งไปยัง Flask
                      final response = await request.send();

                      if (response.statusCode == 200) {
                        final respBytes = await response.stream.toBytes();

                        // ✅ เก็บไฟล์พรีวิวไว้ใน temp directory
                        final tempDir = await getTemporaryDirectory();
                        final previewPath =
                            '${tempDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.png';
                        final previewFile = File(previewPath);
                        await previewFile.writeAsBytes(respBytes);

                        if (!mounted) return;
                        showDialog(
                          context: context,
                          builder: (context) => Dialog(
                            insetPadding: const EdgeInsets.all(10),
                            backgroundColor: Colors.black,
                            child: InteractiveViewer(
                                child: Image.file(previewFile)),
                          ),
                        );
                      } else {
                        final errorText = await response.stream.bytesToString();
                        _showLogDialog(
                            "❌ Flask API error: ${response.statusCode}\n$errorText");
                      }
                    } catch (e) {
                      _showLogDialog(
                          "⚠️ เกิดข้อผิดพลาดในการเชื่อมต่อ Flask API: $e");
                    } finally {
                      if (mounted) setState(() => isProcessing = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<File> convertToSketchIgnoreBg(String path) async {
    final bytes = await File(path).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return File(path);

    // ✅ ใช้ Gaussian blur เพื่อลด noise
    img.Image gray = img.grayscale(image);
    img.Image blur = img.gaussianBlur(gray, radius: 2);

    // ✅ ใช้ Sobel หาขอบ
    img.Image sobel = img.sobel(blur);

    // ✅ Normalize brightness
    int minLum = 255, maxLum = 0;
    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        if (lum < minLum) minLum = lum;
        if (lum > maxLum) maxLum = lum;
      }
    }

    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        final normalized =
            ((lum - minLum) * 255 / (maxLum - minLum + 1)).clamp(0, 255);
        sobel.setPixelRgb(
            x, y, normalized.toInt(), normalized.toInt(), normalized.toInt());
      }
    }

    // ✅ Threshold พื้นขาว เส้นดำ
    const threshold = 100;
    final result = sobel.clone();
    for (int y = 0; y < sobel.height; y++) {
      for (int x = 0; x < sobel.width; x++) {
        final p = sobel.getPixel(x, y);
        final lum = ((p.r + p.g + p.b) / 3).toInt();
        final val = (lum > threshold) ? 255 : 0;
        result.setPixelRgb(x, y, val, val, val);
      }
    }

    // ✅ Invert เส้นดำพื้นขาว
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final p = result.getPixel(x, y);
        final inv = 255 - ((p.r + p.g + p.b) ~/ 3);
        result.setPixelRgb(x, y, inv, inv, inv);
      }
    }

    final finalImage = _dilate(result, kernelSize: 1, iterations: 1);
    final tempDir = await getTemporaryDirectory();
    final sketchFile =
        File('${tempDir.path}/sketch_ignorebg_${const Uuid().v4()}.png');
    await sketchFile.writeAsBytes(img.encodePng(finalImage));
    return sketchFile;
  }

  Widget _editIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color backgroundColor = Colors.white,
    Color textColor = Colors.black,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: backgroundColor,
            foregroundColor: Colors.black,
            radius: 28,
            child: Icon(icon, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(fontSize: 13, color: textColor),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
