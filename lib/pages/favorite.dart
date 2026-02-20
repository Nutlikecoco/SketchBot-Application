import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'edit.dart';
import 'robot_page.dart';
import 'homescaffold.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FavoritePage extends StatelessWidget {
  final List<String> favorites;
  final Function(String) onFavoriteToggle;

  const FavoritePage({
    Key? key,
    required this.favorites,
    required this.onFavoriteToggle,
  }) : super(key: key);

  /// ✅ ฟังก์ชันเตรียม path (asset → temp file)
  Future<String> _prepareImagePath(BuildContext context, String url) async {
    // 🖼️ 1. ถ้าเป็น asset
    if (url.startsWith("assets/")) {
      final byteData = await DefaultAssetBundle.of(context).load(url);
      final tempDir = await Directory.systemTemp.createTemp();
      final tempFile = File('${tempDir.path}/${url.split('/').last}');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());
      return tempFile.path;
    }

    // 🌐 2. ถ้าเป็น URL (เช่นจาก Firebase)
    else if (url.startsWith("http")) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final tempDir = await Directory.systemTemp.createTemp();
          final tempFile =
              File('${tempDir.path}/${url.split('/').last.split('?').first}');
          await tempFile.writeAsBytes(response.bodyBytes);
          return tempFile.path;
        } else {
          debugPrint("❌ Download failed: ${response.statusCode}");
        }
      } catch (e) {
        debugPrint("❌ Error downloading image: $e");
      }
    }

    // 💾 3. ถ้าเป็นไฟล์ในเครื่องอยู่แล้ว
    return url;
  }

  Future<void> uploadImageToFirebase(BuildContext context, String imagePath,
      {String? customFileName}) async {
    try {
      // ✅ ตรวจสอบผู้ใช้
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in");

      // ✅ โหลดไฟล์จาก assets หรือ path จริง
      File file;
      if (imagePath.startsWith('assets/')) {
        final byteData = await DefaultAssetBundle.of(context).load(imagePath);
        final tempDir = await Directory.systemTemp.createTemp();
        final tempFile = File('${tempDir.path}/${imagePath.split('/').last}');
        await tempFile.writeAsBytes(byteData.buffer.asUint8List());
        file = tempFile;
      } else {
        file = File(imagePath);
      }

      final fileName = customFileName ??
          "drawn_result_${DateTime.now().millisecondsSinceEpoch}.png";

      // ✅ ใช้ email เป็น path หลัก (ตรงกับ MyGalleryPage)
      final emailFolder = user.email!;
      final ref =
          FirebaseStorage.instance.ref().child("$emailFolder/$fileName");

      // ✅ อัปโหลดขึ้น Firebase Storage
      await ref.putFile(file);
      final downloadURL = await ref.getDownloadURL();

      // ✅ บันทึกข้อมูลลง Firestore
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.email)
          .collection("my_images")
          .add({
        "url": downloadURL,
        "timestamp": DateTime.now().toIso8601String(),
        "filename": fileName,
      });



      debugPrint("✅ Uploaded $fileName for ${user.email}");
    } catch (e, st) {
      debugPrint("❌ Firebase upload failed: $e");
      debugPrintStack(stackTrace: st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Upload failed: $e")),
        );
      }
    }
  }

  /// ✅ ฟังก์ชันเปิดหน้า Edit
  void _editImage(BuildContext context, String imagePath) async {
    final pathToSend = await _prepareImagePath(context, imagePath);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditPage(imagePath: pathToSend),
      ),
    );
  }

  /// ✅ แสดงรูปภาพตามประเภท (asset, file, URL)
  Widget _buildImageWidget(String imagePath) {
    if (imagePath.startsWith('http')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, color: Colors.red, size: 40),
        ),
      );
    } else if (imagePath.startsWith('assets/')) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (File(imagePath).existsSync()) {
      return Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.red, size: 40),
      );
    }
  }

  /// ✅ แสดงภาพแบบขยาย (รองรับทั้ง URL, asset, file)
  void _showFullImageDialog(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: InteractiveViewer(
          child: _buildImageWidget(imagePath),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScaffold()),
        );
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Favorite Pictures',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color.fromARGB(255, 19, 31, 140),
          centerTitle: true,
        ),
        body: favorites.isEmpty
            ? const Center(child: Text('No favorites yet.'))
            : Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.builder(
                  itemCount: favorites.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 3 / 4,
                  ),
                  itemBuilder: (context, index) {
                    final imagePath = favorites[index];
                    final fileName = imagePath.split('/').last;
                    const isFavorite = true; // หน้า Favorite แสดงเป็น ❤️ เสมอ

                    return Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 🔹 รูปภาพ + หัวใจมุมขวาบน
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => _showFullImageDialog(
                                        context, imagePath),
                                    child: _buildImageWidget(imagePath),
                                  ),
                                  // ❤️ ไอคอนหัวใจมุมขวาบน
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () => onFavoriteToggle(imagePath),
                                      child: const Icon(
                                        Icons.favorite,
                                        color: Colors.red,
                                        size: 28,
                                        shadows: [
                                          Shadow(
                                            blurRadius: 3,
                                            color: Colors.black45,
                                            offset: Offset(1, 1),
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 🔹 ปุ่ม Edit + Start
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 4, right: 4, bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blue),
                                  iconSize: 30,
                                  onPressed: () =>
                                      _editImage(context, imagePath),
                                  tooltip: 'Edit picture',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.play_arrow,
                                      color: Colors.black),
                                  iconSize: 40,
                                  tooltip: "Start",
                                  onPressed: () async {
                                    String? videoUrl;
                                    String? videoUrlSmall;
                                    String? categoryName;

                                    final fileName =
                                        imagePath.split('/').last.toLowerCase();

                                    // ---------------------- ⚔️ ANIME ----------------------
                                    if (fileName.contains("lufy")) {
                                      videoUrl = "assets/videos/lufy.mp4";
                                      videoUrlSmall =
                                          "assets/videos/lufyup.mp4";
                                      categoryName = "Anime";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/lu.png',
                                          customFileName: 'lu.png');
                                    } else if (fileName.contains("naruto")) {
                                      videoUrl = "assets/videos/naruto.mp4";
                                      videoUrlSmall =
                                          "assets/videos/narutoup.mp4";
                                      categoryName = "Anime";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/naru.png',
                                          customFileName: 'naru.png');
                                    } else if (fileName.contains("hoshina")) {
                                      videoUrl = "assets/videos/hoshina.mp4";
                                      videoUrlSmall =
                                          "assets/videos/hoshinaup.mp4";
                                      categoryName = "Anime";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/hoho.png',
                                          customFileName: 'hoho.png');
                                    }

                                    // ---------------------- 🦫 CAPYBARA ----------------------
                                    else if (fileName
                                        .contains("capybara_cake")) {
                                      videoUrl =
                                          "assets/videos/capybara_cake.mp4";
                                      videoUrlSmall =
                                          "assets/videos/capybara_cakeup.mp4";
                                      categoryName = "Capybara";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/cakena.png',
                                          customFileName: 'cakena.png');
                                    } else if (fileName
                                        .contains("capybara_pudding")) {
                                      videoUrl =
                                          "assets/videos/capybara_pudding.mp4";
                                      videoUrlSmall =
                                          "assets/videos/capybara_puddingup.mp4";
                                      categoryName = "Capybara";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/pudd.png',
                                          customFileName: 'pudd.png');
                                    } else if (fileName
                                        .contains("capybara_mac")) {
                                      videoUrl =
                                          "assets/videos/capybara_mac.mp4";
                                      videoUrlSmall =
                                          "assets/videos/capybara_macup.mp4";
                                      categoryName = "Capybara";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/macc.png',
                                          customFileName: 'macc.png');
                                    }

                                    // ---------------------- 🧸 CARTOON ----------------------
                                    else if (fileName.contains("cartoon1")) {
                                      videoUrl = "assets/videos/cartoon1.mp4";
                                      videoUrlSmall =
                                          "assets/videos/cartoon1up.mp4";
                                      categoryName = "Cartoon";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/rabbit.png',
                                          customFileName: 'rabbit.png');
                                    } else if (fileName.contains("cartoon2")) {
                                      videoUrl = "assets/videos/cartoon2.mp4";
                                      videoUrlSmall =
                                          "assets/videos/cartoon2up.mp4";
                                      categoryName = "Cartoon";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/meowza.png',
                                          customFileName: 'meowza.png');
                                    } else if (fileName.contains("cartoon3")) {
                                      videoUrl = "assets/videos/cartoon3.mp4";
                                      videoUrlSmall =
                                          "assets/videos/cartoon3up.mp4";
                                      categoryName = "Cartoon";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/fire.png',
                                          customFileName: 'fire.png');
                                    } else if (fileName.contains("cartoon4")) {
                                      videoUrl = "assets/videos/cartoon4.mp4";
                                      videoUrlSmall =
                                          "assets/videos/cartoon4up.mp4";
                                      categoryName = "Cartoon";
                                      await uploadImageToFirebase(
                                          context, 'assets/images/poji.png',
                                          customFileName: 'poji.png');
                                    }

                                    // ---------------------- 🐾 PET ----------------------
                                    else if (fileName.contains("cat1")) {
                                      videoUrl = "assets/videos/cat1.mp4";
                                      videoUrlSmall =
                                          "assets/videos/cat1up.mp4";
                                      categoryName = "Pet";
                                    } else if (fileName.contains("cat2")) {
                                      videoUrl = "assets/videos/cat2.mp4";
                                      videoUrlSmall =
                                          "assets/videos/cat2up.mp4";
                                      categoryName = "Pet";
                                    } else if (fileName.contains("dog")) {
                                      videoUrl = "assets/videos/dog.mp4";
                                      videoUrlSmall = "assets/videos/dogup.mp4";
                                      categoryName = "Pet";
                                    }

                                    // ---------------------- 👤 MY SELF ----------------------
                                    else {
                                      categoryName = "My Self";
                                    }

                                    if (!context.mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => RobotPage(
                                          videoUrl: videoUrl,
                                          videoUrlSmall: videoUrlSmall,
                                          imagePath: imagePath,
                                          categoryName: categoryName,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
