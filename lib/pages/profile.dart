import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

// =======================================================
// 💾 บันทึก UID ปัจจุบันลงไฟล์ (ให้ ROS อ่านได้)
// =======================================================
Future<void> _saveCurrentUidForRos() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final file = File('/media/sf_Downloads/current_uid.txt');
    await file.writeAsString(user.uid);
    debugPrint("✅ UID saved for ROS: ${user.uid}");
  } catch (e) {
    debugPrint("⚠️ Save UID failed: $e");
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

Future<void> _deleteInvalidImage(String imageUrl) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final galleryRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('my_images');

    // หา doc ที่มี url ตรงกัน
    final snapshot = await galleryRef.where('url', isEqualTo: imageUrl).get();

    for (final doc in snapshot.docs) {
      await doc.reference.delete();
      debugPrint("🧹 ลบข้อมูลรูปที่ไม่มีใน Storage แล้ว: ${doc.id}");
    }
  } catch (e) {
    debugPrint("⚠️ ลบข้อมูลไม่สำเร็จ: $e");
  }
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  String _email = "";

  File? _imageFile;
  String? _imageUrl;

  bool _isSaving = false;
  List<String> _galleryImages = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadMyGallery();
    _saveCurrentUidForRos();
  }

  // =======================================================
  // 🔹 โหลดข้อมูลผู้ใช้
  // =======================================================
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _email = user.email ?? "");

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists && mounted) {
      final data = doc.data() ?? {};
      setState(() {
        _nameController.text = data['name'] ?? "";
        _dobController.text = data['dob'] ?? "";
        _imageUrl = data['imageUrl'];
      });
    }
  }

  // =======================================================
  // 🖼️ โหลด My Gallery (ภาพจาก ROS ใน Firebase)
  // =======================================================
  Future<void> _loadMyGallery() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final galleryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.email)
          .collection('my_images');

      final snapshot =
          await galleryRef.orderBy('timestamp', descending: true).get();
      setState(() {
        _galleryImages = snapshot.docs.map((d) => d['url'] as String).toList();
      });
    } catch (e) {
      debugPrint("⚠️ loadMyGallery error: $e");
    }
  }

  // =======================================================
  // 📤 เลือกรูปโปรไฟล์ใหม่
  // =======================================================
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  // =======================================================
  // 💾 บันทึกข้อมูลโปรไฟล์
  // =======================================================
  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;

    String? imageUrl = _imageUrl;
    if (_imageFile != null) {
      try {
        final ref = FirebaseStorage.instance.ref().child('profiles/$uid.jpg');
        await ref.putFile(_imageFile!);
        imageUrl = await ref.getDownloadURL();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("อัปโหลดรูปผิดพลาด: $e")),
          );
        }
      }
    }

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      "name": _nameController.text,
      "dob": _dobController.text,
      "email": _email,
      "imageUrl": imageUrl,
    }, SetOptions(merge: true));

    if (mounted) {
      setState(() {
        _isSaving = false;
        _imageUrl = imageUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated ✅")),
      );
    }
  }

  // =======================================================
  // 🚪 ออกจากระบบ
  // =======================================================
  Future<void> _logout() async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Logged out successfully ✅")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logout failed: $e")),
      );
    }
  }

  // =======================================================
  // 🧱 UI หลัก
  // =======================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF13208C),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white, size: 28),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("ออกจากระบบ"),
                  content: const Text("คุณแน่ใจหรือไม่ว่าต้องการออกจากระบบ?"),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("ยกเลิก")),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("ออกจากระบบ")),
                  ],
                ),
              );
              if (confirm == true) _logout();
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ===================== Header =====================
            Container(
              height: 220,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF13208C), Color(0xFF4055C8)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 55,
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!)
                          : (_imageUrl != null && _imageUrl!.isNotEmpty
                              ? NetworkImage(_imageUrl!)
                              : null) as ImageProvider?,
                      child: (_imageFile == null &&
                              (_imageUrl == null || _imageUrl!.isEmpty))
                          ? const Icon(Icons.person,
                              size: 55, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _nameController.text.isNotEmpty
                        ? _nameController.text
                        : "Your Name",
                    style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // ===================== Form =====================
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                                labelText: "Name",
                                prefixIcon: Icon(Icons.person)),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _dobController,
                            readOnly: true,
                            decoration: const InputDecoration(
                                labelText: "Date of Birth",
                                prefixIcon: Icon(Icons.cake)),
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now(),
                              );
                              if (pickedDate != null) {
                                _dobController.text = pickedDate
                                    .toIso8601String()
                                    .split('T')
                                    .first;
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: "Email",
                              prefixIcon: const Icon(Icons.email),
                              hintText: _email,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ListTile(
                            leading: const Icon(Icons.photo_library,
                                color: Color(0xFF13208C)),
                            title: const Text(
                              "My Gallery",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios,
                                size: 16, color: Colors.grey),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MyGalleryPage(images: _galleryImages),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF13208C),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("Save",
                              style:
                                  TextStyle(fontSize: 20, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// 🖼️ My Gallery Page (เลือกหลายรูป + ถังขยะลบพร้อมกัน)
// =======================================================
class MyGalleryPage extends StatefulWidget {
  final List<String> images;
  const MyGalleryPage({super.key, required this.images});

  @override
  State<MyGalleryPage> createState() => _MyGalleryPageState();
}

class _MyGalleryPageState extends State<MyGalleryPage> {
  Set<String> _selectedImages = {}; // ✅ เก็บรูปที่เลือก
  bool _selectionMode = false; // ✅ เปิด/ปิดโหมดเลือกหลายรูป

  // 🧩 ฟังก์ชันลบหลายรูปพร้อมกัน
  // 🧩 ฟังก์ชันลบหลายรูปพร้อมกัน (เวอร์ชันแก้ไข)
  
  Future<void> _deleteSelectedImages() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedImages.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ลบรูปที่เลือก?"),
        content: Text("คุณต้องการลบรูป ${_selectedImages.length} รูปหรือไม่?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("ลบ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      for (final imageUrl in _selectedImages) {
        // 🔹 1️⃣ พยายามลบจาก Firebase Storage ก่อน
        try {
          final ref = FirebaseStorage.instance.refFromURL(imageUrl);
          await ref.delete();
          debugPrint("✅ ลบรูปจาก Storage แล้ว: $imageUrl");
        } catch (e) {
          debugPrint("⚠️ รูปนี้ไม่มีอยู่ใน Storage แล้ว: $imageUrl");
        }

        // 🔹 2️⃣ ลบจาก Firestore ต่อให้ไฟล์ไม่อยู่แล้ว
        final galleryRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.email)
            .collection('my_images');

        final snapshot =
            await galleryRef.where('url', isEqualTo: imageUrl).get();
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
          debugPrint("🧹 ลบเอกสาร Firestore แล้ว: ${doc.id}");
        }
      }

      if (mounted) {
        setState(() {
          _selectedImages.clear();
          _selectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ ลบรูปสำเร็จ ")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ ลบรูปไม่สำเร็จ: $e")),
      );
    }
  }

  // 🧩 ยกเลิกโหมดเลือก
  void _cancelSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedImages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("⚠️ ยังไม่ได้เข้าสู่ระบบ")),
      );
    }

    final galleryStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.email)
        .collection('my_images')
        .orderBy('timestamp', descending: true)
        .snapshots();

    // ✅ ดัก Back เพื่อยกเลิกโหมดเลือก
    return WillPopScope(
      onWillPop: () async {
        if (_selectionMode) {
          _cancelSelectionMode();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _selectionMode
                ? "เลือกแล้ว ${_selectedImages.length}"
                : "My Gallery",
            style: const TextStyle(
              color: Colors.white, // สีตัวอักษร
              fontWeight: FontWeight.bold, // ตัวหนา
              fontSize: 20, // ขนาด
            ),
          ),
          backgroundColor: const Color(0xFF13208C),
          centerTitle: true,
          actions: [
            if (_selectionMode)
              IconButton(
                icon: Icon(
                  Icons.delete,
                  color: _selectedImages.isEmpty
                      ? Colors.white.withOpacity(0.4)
                      : Colors.redAccent,
                ),
                onPressed:
                    _selectedImages.isEmpty ? null : _deleteSelectedImages,
                tooltip: 'ลบรูปที่เลือก',
              ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: galleryStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text("ยังไม่มีภาพใน Gallery",
                    style: TextStyle(color: Colors.black54)),
              );
            }

            final images =
                snapshot.data!.docs.map((d) => d['url'] as String).toList();

            return GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) {
                final url = images[index];
                final isSelected = _selectedImages.contains(url);

                return GestureDetector(
                  onLongPress: () {
                    setState(() {
                      _selectionMode = true;
                      _selectedImages.add(url);
                    });
                  },
                  onTap: () {
                    if (_selectionMode) {
                      setState(() {
                        if (isSelected) {
                          _selectedImages.remove(url);
                          if (_selectedImages.isEmpty) _selectionMode = false;
                        } else {
                          _selectedImages.add(url);
                        }
                      });
                    } else {
                      _showFullScreenImage(url);
                    }
                  },
                  child: Stack(
                    children: [
                      Hero(
                        tag: url,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ColorFiltered(
                            colorFilter: isSelected
                                ? const ColorFilter.mode(
                                    Colors.black26, BlendMode.darken)
                                : const ColorFilter.mode(
                                    Colors.transparent, BlendMode.multiply),
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(Icons.check_circle,
                                color: Colors.blueAccent, size: 22),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // 🖼️ แสดงภาพเต็มจอ
  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.black,
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              // ✅ ภาพเต็มจอ
              InteractiveViewer(
                child: Center(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                  ),
                ),
              ),

              // ✅ ปุ่มปิด
              Positioned(
                top: 30,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),

              // ✅ ปุ่มบันทึกลงเครื่อง
              Positioned(
                bottom: 30,
                right: 20,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      // 1) โหลดรูปจาก URL
                      final response = await http.get(Uri.parse(imageUrl));
                      final bytes = response.bodyBytes;

                      // 2) เซฟลงโฟลเดอร์ชั่วคราวของแอป
                      final tempDir = await getTemporaryDirectory();
                      final file = File(
                        '${tempDir.path}/sketch_${DateTime.now().millisecondsSinceEpoch}.jpg',
                      );
                      await file.writeAsBytes(bytes);

                      // 3) เปิด share sheet ของระบบ
                      await Share.shareFiles(
                        [file.path],
                        text: "🖼️ My sketch from SketchBot",
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("❌ แชร์ไม่สำเร็จ: $e")),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.ios_share, size: 20),
                  label: const Text(
                    "แชร์ / บันทึก",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
