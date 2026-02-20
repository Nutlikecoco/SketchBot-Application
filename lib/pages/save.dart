import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:roslibdart/roslibdart.dart';
import 'robot_page.dart';

class SavePage extends StatefulWidget {
  const SavePage({super.key});

  @override
  State<SavePage> createState() => _SavePageState();
}

class _SavePageState extends State<SavePage> {
  late Ros ros;
  Topic? commandTopic;
  Topic? savedStatesTopic;
  bool rosConnected = false;
  List<String> savedFiles = [];

  @override
  void initState() {
    super.initState();
    _connectRos();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args == "refresh_save") {
      debugPrint("🔁 SavePage: รีเฟรชหลังกลับมาจาก RobotPage");
      _requestSavedStates();
    }
  }

  // =====================================================
  // 📡 เชื่อมต่อ ROS
  // =====================================================
  Future<void> _connectRos() async {
    ros = Ros(url: 'ws://192.168.1.177:9090'); // ✅ IP ROS ของคุณ

    try {
      ros.connect();
      debugPrint("✅ Connected to ROS successfully!");
      setState(() => rosConnected = true);

      // ✅ Topic สำหรับสั่งงาน ROS
      commandTopic = Topic(
        ros: ros,
        name: '/sketchbot_command',
        type: 'std_msgs/String',
      );
      await commandTopic!.advertise();

      // ✅ Topic สำหรับรับรายการ state ที่บันทึกไว้
      savedStatesTopic = Topic(
        ros: ros,
        name: '/sketchbot/saved_states',
        type: 'std_msgs/String',
      );

      // ✅ subscribe แบบ callback
      savedStatesTopic!.subscribe((msg) async {
        try {
          final raw = msg['data']?.toString() ?? '[]';
          // ✅ ใช้ isolate แยก thread
          final List<dynamic> data =
              await compute((raw) => jsonDecode(raw), raw);
          if (!mounted) return;
          setState(() => savedFiles = data.map((e) => e.toString()).toList());
          debugPrint("📥 Received saved states (${savedFiles.length})");
        } catch (e) {
          debugPrint("⚠️ Parse error from ROS saved_states: $e");
        }
        return Future.value();
      });

      _requestSavedStates();
    } catch (e) {
      debugPrint("❌ ROS connect failed: $e");
    }
  }

  // =====================================================
  // 📤 ขอรายการ state จาก ROS
  // =====================================================
  void _requestSavedStates() {
    if (!rosConnected || commandTopic == null) return;
    final cmd = {"cmd": "list_saves"};
    commandTopic!.publish({"data": jsonEncode(cmd)});
    debugPrint("📤 Requesting saved states from ROS...");
  }


  // =====================================================
// ▶️ Resume การวาดจากไฟล์ที่เลือก (Auto Start หลัง Resume)
// =====================================================
  Future<void> _resumeFromFile(String filePath) async {
    if (!rosConnected || commandTopic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ ยังไม่ได้เชื่อมต่อ ROS"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // 🧠 โหลดข้อมูลจาก state file เพื่อส่งโหมดและรูป
    String? imagePath;
    String categoryName = "Anime"; // ค่า default
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);

        if (data is Map) {
          // 📸 ดึง path ของรูป
          final rawPath = data["image_path"]?.toString();
          if (rawPath != null && rawPath.isNotEmpty) {
            imagePath = rawPath;
          }

          // 🎨 อ่าน mode เพื่อใช้ระบุ category
          final mode = data["mode"]?.toString();
          if (mode != null && mode.isNotEmpty) {
            if (mode == "anime")
              categoryName = "Anime";
            else if (mode == "sketch")
              categoryName = "Pet";
            else
              categoryName = "Cartoon";
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ อ่านข้อมูลจากไฟล์ state ไม่ได้: $e");
    }

    // 🧾 สร้างคำสั่ง resume_from_file
    final resumeCmd = {
      "cmd": "resume_from_file",
      "path": filePath,
      "include_image": true,
    };

    // 🔹 ส่งคำสั่ง resume
    commandTopic!.publish({"data": jsonEncode(resumeCmd)});
    debugPrint("▶️ Resume command sent: $resumeCmd");

    // ✅ แจ้งผู้ใช้
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("▶️ กำลังโหลดงานจาก ${filePath.split('/').last}"),
        backgroundColor: Colors.green,
      ),
    );

    // 🕐 หน่วง 5 วินาทีเพื่อให้ ROS โหลดเสร็จ แล้วค่อยส่ง start
    Future.delayed(const Duration(seconds: 5), () {
      if (rosConnected && commandTopic != null) {
        commandTopic!.publish("start");
        debugPrint("🎬 Auto-start drawing after resume (sent 'start')");
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🎨 หุ่นยนต์เริ่มวาดต่อ...")),
        );
      } else {
        debugPrint("⚠️ Cannot send 'start' — ROS not connected");
      }
    });

    // 🦾 เปิดหน้า RobotPage พร้อมข้อมูลจำเป็น
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RobotPage(
          imagePath: imagePath,
          categoryName: categoryName,
        ),
      ),
    ).then((result) {
      debugPrint("⬅️ กลับจาก RobotPage result=$result");
      if (!mounted) return;

      if (result == "refresh_save" || result == "refresh_gallery") {
        // ✅ โหลดรายการ state ใหม่ (รีเฟรช)
        _requestSavedStates();

        // ✅ แสดง snackbar ยืนยันว่าโหลดใหม่แล้ว
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ อัปเดตรายการบันทึกล่าสุดแล้ว"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  // =====================================================
  // 🖼️ อ่าน image_path จากไฟล์ JSON
  // =====================================================
  Future<String?> _getImagePathFromJson(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final data = jsonDecode(content);

      if (data is Map && data.containsKey('image_path')) {
        String imgPath = data['image_path']?.toString() ?? '';
        if (imgPath.isEmpty) return null;

        // ✅ ถ้าเป็น path จาก ROS (/media/sf_...) ให้ลองหาในมือถือ
        if (imgPath.startsWith("/media/") || imgPath.startsWith("/home/")) {
          final fileName = imgPath.split('/').last;
          final possibleDirs = [
            '/storage/emulated/0/Download',
            '/sdcard/Download',
            '/storage/emulated/0/Pictures'
          ];
          for (final dirPath in possibleDirs) {
            final dir = Directory(dirPath);
            if (await dir.exists()) {
              final guess = "${dir.path}/$fileName";
              if (File(guess).existsSync()) {
                debugPrint("📸 ใช้ภาพจากมือถือแทน: $guess");
                return guess;
              }
            }
          }
        }

        return imgPath;
      }
    } catch (e) {
      debugPrint("⚠️ อ่าน image_path จาก $filePath ไม่ได้: $e");
    }
    return null;
  }

  // =====================================================
  // ❌ ลบไฟล์ที่บันทึกไว้
  // =====================================================
  Future<void> _deleteFile(String filePath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("🗑️ ยืนยันการลบ"),
        content:
            Text("ต้องการลบไฟล์นี้หรือไม่?\n\n${filePath.split('/').last}"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("ยกเลิก")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ลบเลย"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (rosConnected && commandTopic != null) {
      final cmd = {"cmd": "delete_save", "path": filePath};
      commandTopic!.publish({"data": jsonEncode(cmd)});
      debugPrint("🗑️ Delete command sent: $cmd");
    }

    if (!mounted) return;
    setState(() => savedFiles.remove(filePath));
  }

  // =====================================================
  // 🔄 รีเฟรชรายการ
  // =====================================================
  Future<void> _refreshList() async {
    _requestSavedStates();
    await Future.delayed(const Duration(seconds: 1));
  }

  // =====================================================
  // 🧱 UI หลัก
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13208C),
        title: const Text("Saved Drawings",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshList,
          ),
        ],
      ),
      body: !rosConnected
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : savedFiles.isEmpty
              ? const Center(
                  child: Text("ยังไม่มีข้อมูลที่บันทึก",
                      style: TextStyle(fontSize: 16, color: Colors.black54)),
                )
              : RefreshIndicator(
                  onRefresh: _refreshList,
                  child: ListView.builder(
                    itemCount: savedFiles.length,
                    itemBuilder: (context, index) {
                      final path = savedFiles[index];
                      final fileName = path.split("/").last;

                      return FutureBuilder<String?>(
                        future: _getImagePathFromJson(path),
                        builder: (context, snapshot) {
                          final imagePath = snapshot.data;
                          Widget leadingWidget;

                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            leadingWidget = const SizedBox(
                              width: 50,
                              height: 50,
                              child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            );
                          } else if (imagePath != null &&
                              imagePath.isNotEmpty) {
                            if (imagePath.startsWith("http")) {
                              leadingWidget = ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imagePath,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image,
                                      color: Colors.redAccent),
                                ),
                              );
                            } else if (File(imagePath).existsSync()) {
                              leadingWidget = ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(imagePath),
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                ),
                              );
                            } else {
                              leadingWidget = const Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                                size: 40,
                              );
                            }
                          } else {
                            leadingWidget = const Icon(
                              Icons.insert_drive_file,
                              color: Color(0xFF13208C),
                              size: 40,
                            );
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: leadingWidget,
                              title: Text(fileName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              subtitle: Text(path,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                  overflow: TextOverflow.ellipsis),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.play_arrow,
                                        color: Colors.green),
                                    tooltip: "Resume Drawing",
                                    onPressed: () => _resumeFromFile(path),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.redAccent),
                                    tooltip: "Delete Save",
                                    onPressed: () => _deleteFile(path),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }

  // =====================================================
  // 🧹 ปิดการเชื่อมต่อ ROS
  // =====================================================
  @override
  void dispose() {
    try {
      savedStatesTopic?.unsubscribe();
      commandTopic?.unadvertise();
      ros.close();
    } catch (_) {}
    super.dispose();
  }
}
