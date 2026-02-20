import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'edit.dart';
import 'robot_page.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class CategoryPage extends StatefulWidget {
  final String category;
  final List<dynamic> images;
  final Set<String> favorites;
  final Function(String url) onFavoriteToggle;

  const CategoryPage({
    super.key,
    required this.category,
    required this.images,
    required this.favorites,
    required this.onFavoriteToggle,
  });

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  List<dynamic> localImages = [];

  @override
  void initState() {
    super.initState();
    if (widget.category == "My Self") {
      _reloadMySelfImages();
    } else {
      localImages = List.from(widget.images);
    }
  }

  Future<void> _reloadMySelfImages() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('my_images')
          .get();

      final newImages =
          snapshot.docs.map((doc) => doc['url'] as String).toList();

      setState(() {
        localImages = newImages;
      });
    } catch (e) {
      debugPrint("❌ โหลดข้อมูล My Self ล้มเหลว: $e");
    }
  }

  Widget buildImage(String path, {BoxFit fit = BoxFit.cover}) {
    if (path.startsWith("http")) {
      return Image.network(
        path,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, color: Colors.grey, size: 48),
      );
    } else if (path.startsWith("assets/")) {
      return Image.asset(
        path,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      return Image.file(
        File(path),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, color: Colors.grey, size: 48),
      );
    }
  }

  Future<void> uploadImageToFirebase(String imagePath,
      {String? customFileName}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in");

      // ✅ โหลดไฟล์จาก assets หรือ path จริง
      File file;
      if (imagePath.startsWith('assets/')) {
        final byteData = await DefaultAssetBundle.of(context).load(imagePath);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${imagePath.split('/').last}');
        await tempFile.writeAsBytes(byteData.buffer.asUint8List());
        file = tempFile;
      } else {
        file = File(imagePath);
      }

      final fileName = customFileName ??
          "drawn_result_${DateTime.now().millisecondsSinceEpoch}.png";

      // ✅ ใช้ email เป็น path เหมือน MyGallery
      final emailFolder = user.email!;
      final ref =
          FirebaseStorage.instance.ref().child("$emailFolder/$fileName");

      // ✅ อัปโหลดขึ้น Firebase Storage
      await ref.putFile(file);
      final downloadURL = await ref.getDownloadURL();

      // ✅ บันทึก metadata ลง Firestore
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
      debugPrint("❌ Firebase upload failed: $e");
      debugPrintStack(stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Upload failed: $e")),
        );
      }
    }
  }

  Future<String> _prepareImagePath(BuildContext context, String url) async {
    try {
      // ✅ Asset
      if (url.startsWith("assets/")) {
        final byteData = await DefaultAssetBundle.of(context).load(url);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${url.split('/').last}');
        await tempFile.writeAsBytes(byteData.buffer.asUint8List());
        return tempFile.path;
      }

      // ✅ HTTP (Firebase)
      else if (url.startsWith("http")) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final fileName = const Uuid().v4() + ".jpg";
          final file = File("${tempDir.path}/$fileName");
          await file.writeAsBytes(response.bodyBytes);
          return file.path;
        } else {
          debugPrint("❌ Download failed: ${response.statusCode}");
        }
      }

      // ✅ Local File
      return url;
    } catch (e) {
      debugPrint("❌ Error preparing image path: $e");
      return url;
    }
  }

  Future<void> _confirmDeleteImage(BuildContext context, String url) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยืนยันการลบรูปภาพ"),
        content: const Text("คุณต้องการลบรูปภาพนี้ออกหรือไม่?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("ยกเลิก")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ลบ"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('my_images')
            .where('url', isEqualTo: url)
            .get();

        for (var doc in snapshot.docs) {
          await doc.reference.delete();
        }

        if (url.startsWith('http')) {
          try {
            await FirebaseStorage.instance.refFromURL(url).delete();
          } catch (e) {
            debugPrint("⚠️ ไม่สามารถลบจาก Storage ได้: $e");
          }
        }

        setState(() => localImages.remove(url));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("✅ ลบรูปภาพสำเร็จ")));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ เกิดข้อผิดพลาดในการลบ: $e")));
      }
    }
  }

  void showFullImagePopup(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: buildImage(imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = localImages;

    final Map<String, Map<String, String>> imageToVideos = {
      'assets/images/capybara_cake.jpg': {
        'main': 'assets/videos/capybara_cake.mp4',
        'small': 'assets/videos/capybara_cakeup.mp4'
      },
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: images.isEmpty
          ? const Center(child: Text("ยังไม่มีรูปในหมวดนี้"))
          : Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                itemCount: images.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 3 / 4,
                ),
                itemBuilder: (context, index) {
                  final url = images[index];
                  final isFavorite = widget.favorites.contains(url);
                  final fileName = url.split('/').last;
                  final videos = imageToVideos[url];

                  return Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                            child: Stack(
                              children: [
                                GestureDetector(
                                  onTap: () => showFullImagePopup(url),
                                  child: buildImage(url),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: () {
                                      widget.onFavoriteToggle(url);
                                      setState(() {});
                                    },
                                    child: Icon(
                                      isFavorite
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: isFavorite
                                          ? Colors.red
                                          : Colors.white,
                                      size: 28,
                                      shadows: const [
                                        Shadow(
                                            blurRadius: 3,
                                            color: Colors.black45,
                                            offset: Offset(1, 1))
                                      ],
                                    ),
                                  ),
                                ),
                                if (widget.category == "My Self")
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: GestureDetector(
                                      onTap: () =>
                                          _confirmDeleteImage(context, url),
                                      child: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                                icon: const Icon(Icons.edit,
                                    color: Color(0xFF074A81)),
                                iconSize: 30,
                                onPressed: () async {
                                  try {
                                    final pathToSend =
                                        await _prepareImagePath(context, url);
                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EditPage(imagePath: pathToSend),
                                      ),
                                    );
                                  } catch (e) {
                                    debugPrint("❌ Error: $e");
                                  }
                                }),
                            IconButton(
                              icon: const Icon(Icons.play_arrow,
                                  color: Colors.green),
                              iconSize: 40,
                              onPressed: () async {
                                String rosPath = "";
                                String? videoUrl;
                                String? videoUrlSmall;
                                try {
                                  final fileName =
                                      url.split('/').last.toLowerCase();

                                  // ---------------------- 🎞️ ANIME ----------------------
                                  if (fileName.contains("lufy")) {
                                    videoUrl = "assets/videos/lufy.mp4";
                                    videoUrlSmall = "assets/videos/lufyup.mp4";
                                  } else if (fileName.contains("naruto")) {
                                    videoUrl = "assets/videos/naruto.mp4";
                                    videoUrlSmall =
                                        "assets/videos/narutoup.mp4";
                                  } else if (fileName.contains("hoshina")) {
                                    videoUrl = "assets/videos/hoshina.mp4";
                                    videoUrlSmall =
                                        "assets/videos/hoshinaup.mp4";
                                  }

                                  // ---------------------- 🦫 CAPYBARA ----------------------
                                  else if (fileName.contains("capybara_cake")) {
                                    videoUrl =
                                        "assets/videos/capybara_cake.mp4";
                                    videoUrlSmall =
                                        "assets/videos/capybara_cakeup.mp4";
                                  } else if (fileName
                                      .contains("capybara_pudding")) {
                                    videoUrl =
                                        "assets/videos/capybara_pudding.mp4";
                                    videoUrlSmall =
                                        "assets/videos/capybara_puddingup.mp4";
                                  } else if (fileName
                                      .contains("capybara_mac")) {
                                    videoUrl = "assets/videos/capybara_mac.mp4";
                                    videoUrlSmall =
                                        "assets/videos/capybara_macup.mp4";
                                  }

                                  // ---------------------- 🧸 CARTOON ----------------------
                                  else if (fileName.contains("cartoon1")) {
                                    videoUrl = "assets/videos/cartoon1.mp4";
                                    videoUrlSmall =
                                        "assets/videos/cartoon1up.mp4";
                                  } else if (fileName.contains("cartoon2")) {
                                    videoUrl = "assets/videos/cartoon2.mp4";
                                    videoUrlSmall =
                                        "assets/videos/cartoon2up.mp4";
                                  } else if (fileName.contains("cartoon3")) {
                                    videoUrl = "assets/videos/cartoon3.mp4";
                                    videoUrlSmall =
                                        "assets/videos/cartoon3up.mp4";
                                  } else if (fileName.contains("cartoon4")) {
                                    videoUrl = "assets/videos/cartoon4.mp4";
                                    videoUrlSmall =
                                        "assets/videos/cartoon4up.mp4";
                                  }

                                  // ====================================================
                                  // ✅ ถ้ามีวิดีโอใน assets → ให้ upload รูป preset เข้า MyGallery
                                  // ====================================================
                                  if (videoUrl != null) {
                                    // 👇 โหลดรูปผลลัพธ์จาก assets แล้วอัปโหลดเข้า My Gallery
                                    final presetName = switch (fileName) {
                                      var n when n.contains("lufy") => "lu.png",
                                      var n when n.contains("naruto") =>
                                        "naru.png",
                                      var n when n.contains("hoshina") =>
                                        "hoho.png",
                                      var n when n.contains("capybara_cake") =>
                                        "cakena.png",
                                      var n
                                          when n.contains("capybara_pudding") =>
                                        "pudd.png",
                                      var n when n.contains("capybara_mac") =>
                                        "macc.png",
                                      var n when n.contains("cartoon1") =>
                                        "rabbit.png",
                                      var n when n.contains("cartoon2") =>
                                        "meowza.png",
                                      var n when n.contains("cartoon3") =>
                                        "fire.png",
                                      var n when n.contains("cartoon4") =>
                                        "poji.png",
                                      _ => null
                                    };

                                    if (presetName != null) {
                                      await uploadImageToFirebase(
                                          'assets/images/$presetName',
                                          customFileName: presetName);
                                    }

                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RobotPage(
                                          videoUrl: videoUrl,
                                          videoUrlSmall: videoUrlSmall,
                                          categoryName: widget.category,
                                          imagePath: url,
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  // ====================================================
                                  // 🧠 ถ้าไม่มีวิดีโอ → เชื่อมต่อ ROS ตามเดิม
                                  // ====================================================
                                  if (url.startsWith('http')) {
                                    rosPath = url;
                                    debugPrint(
                                        "🌐 ใช้ Firebase URL โดยตรงสำหรับ ROS: $rosPath");
                                  } else if (url.startsWith('/data/')) {
                                    final file = File(url);
                                    if (await file.exists()) {
                                      const serverBase =
                                          'http://192.168.1.177:8000/images';
                                      final fileName =
                                          file.path.split('/').last;
                                      final request = http.MultipartRequest(
                                          'POST',
                                          Uri.parse('$serverBase/upload'));
                                      request.files.add(
                                          await http.MultipartFile.fromPath(
                                              'file', file.path));
                                      final response = await request.send();
                                      if (response.statusCode == 200) {
                                        rosPath = '$serverBase/$fileName';
                                        debugPrint(
                                            "✅ Uploaded and ready for ROS: $rosPath");
                                      } else {
                                        throw Exception(
                                            "Upload failed ${response.statusCode}");
                                      }
                                    }
                                  } else {
                                    rosPath =
                                        '/media/sf_Downloads/${url.split('/').last}';
                                  }

                                  if (!mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RobotPage(
                                        categoryName: widget.category,
                                        imagePath: rosPath,
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  debugPrint(
                                      "❌ Error preparing ROS image path: $e");
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text("โหลดรูปไม่สำเร็จ")),
                                  );
                                }
                              },
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
