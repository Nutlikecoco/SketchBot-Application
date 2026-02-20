import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:roslibdart/roslibdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'save.dart';

class RobotPage extends StatefulWidget {
  final String? videoUrl; // ✅ ถ้ามี → เข้าโหมดจำลอง
  final String? videoUrlSmall; // วิดีโอรอง (มุมขวา)

  final String? imagePath; // path ของภาพ (บนเครื่อง ROS หรือ URL)
  final String? categoryName; // หมวดหมู่ภาพ เช่น Anime, Pet, Cartoon

  const RobotPage({
    super.key,
    this.videoUrl,
    this.videoUrlSmall,
    this.imagePath,
    this.categoryName,
  });

  @override
  State<RobotPage> createState() => _RobotPageState();
}

class _RobotPageState extends State<RobotPage> {
  // ------------------- ROS CONFIG -------------------
  late Ros ros;
  Topic? poseTopic;
  Topic? cameraTopic;
  Topic? topCameraTopic;
  Topic? commandTopic;
  bool rosConnected = false;
  bool rosConnecting = false;
  final ValueNotifier<Uint8List?> cameraImageNotifier = ValueNotifier(null);
  final ValueNotifier<Uint8List?> topCameraImageNotifier = ValueNotifier(null);

  // ------------------- VIDEO CONFIG -------------------
  VideoPlayerController? _mainController;
  VideoPlayerController? _smallController;
  bool get isSimulationMode => widget.videoUrl != null;
  bool isSwapped = false;
  Future<String?> _findSimulationVideo(String imagePath) async {
    try {
      // 🔍 ดึงชื่อไฟล์จาก path เช่น 'dog.png' → 'dog.mp4'
      final fileName = imagePath.split('/').last.split('.').first;
      final dir = await getApplicationDocumentsDirectory();
      final simPath = '${dir.path}/sim_videos/$fileName.mp4';
      final file = File(simPath);
      if (await file.exists()) {
        debugPrint("🎬 พบวิดีโอจำลอง: $simPath");
        return simPath;
      }
    } catch (e) {
      debugPrint("⚠️ ตรวจวิดีโอจำลองล้มเหลว: $e");
    }
    return null;
  }

// =========================================================
// 💾 SAVE CURRENT STATE (กดปุ่มเซฟเอง ไม่เปลี่ยนหน้า)
// =========================================================
  Future<void> _saveCurrentState() async {
    if (rosConnected && commandTopic != null) {
      // ✅ ส่งคำสั่งให้ ROS บันทึก state ล่าสุด
      commandTopic!.publish({
        "data": jsonEncode({"cmd": "save"})
      });
      debugPrint("💾 Sent save command to ROS");

      // ✅ แสดง snackbar บอกว่ากำลังบันทึก
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("💾 กำลังบันทึกการวาด..."),
          backgroundColor: Colors.blueAccent,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ ROS ยังไม่เชื่อมต่อ ไม่สามารถบันทึกได้"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // =========================================================
  // 🧩 INIT STATE
  // =========================================================
  @override
  void initState() {
    super.initState();

    // ✅ ถ้ามี videoUrl ให้ใช้เลย (โหมดจำลอง)
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      _initVideoMode();
      return;
    }

    // ✅ ถ้าไม่มี videoUrl → ตรวจดูจาก imagePath ว่ามีวิดีโอจำลองในเครื่องไหม
    if (widget.imagePath != null && widget.imagePath!.isNotEmpty) {
      _findSimulationVideo(widget.imagePath!).then((simPath) {
        if (simPath != null && mounted) {
          debugPrint("🎥 Switching to simulation mode from Robot Control");
          setState(() {
            _mainController = VideoPlayerController.file(File(simPath));
          });
          _initVideoMode();
        } else {
          debugPrint("🦾 No simulation found → connecting to ROS");
          _connectRos();
        }
      }).catchError((e) {
        debugPrint("⚠️ Simulation check error: $e");
        _connectRos(); // ✅ fallback กรณีเกิด exception
      });
    } else {
      debugPrint("📡 No imagePath provided → connecting to ROS directly");
      _connectRos();
    }

    // ✅ fallback ป้องกันไม่ให้ ROS ค้างไม่เชื่อม (safety net)
    Future.delayed(const Duration(seconds: 3), () {
      if (!rosConnected && !rosConnecting && mounted) {
        debugPrint("🛠 Force connecting to ROS (fallback)");
        _connectRos();
      }
    });
  }


  //  INITIALIZE VIDEO MODE

  Future<void> _initVideoMode() async {
    //  จอหลัก
    _mainController = VideoPlayerController.asset(widget.videoUrl!)
      ..initialize().then((_) async {
        _mainController!.setLooping(false);
        final resumePos = await _loadResumePosition("main_${widget.videoUrl}");
        if (resumePos != null && resumePos < _mainController!.value.duration) {
          await _mainController!.seekTo(resumePos);
        }
        _mainController!.play();

        _mainController!.addListener(() async {
          if (!_mainController!.value.isInitialized) return;
          final pos = _mainController!.value.position;
          if (pos >= _mainController!.value.duration) {
            await _clearResumePosition("main_${widget.videoUrl}");
          }
        });

        setState(() {});
      });

    // 🎥 จอเล็ก
    if (widget.videoUrlSmall != null) {
      _smallController = VideoPlayerController.asset(widget.videoUrlSmall!)
        ..initialize().then((_) async {
          _smallController!.setLooping(false);
          final resumePos =
              await _loadResumePosition("small_${widget.videoUrlSmall}");
          if (resumePos != null &&
              resumePos < _smallController!.value.duration) {
            await _smallController!.seekTo(resumePos);
          }
          setState(() {});
        });
    }
  }

  // =========================================================
  // 🔖 Resume Save/Load
  // =========================================================
  Future<void> _saveResumePosition(Duration pos, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('resume_$key', pos.inMilliseconds);
    debugPrint("💾 Saved resume [$key] = ${pos.inSeconds}s");
  }

  Future<Duration?> _loadResumePosition(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('resume_$key');
    return ms != null ? Duration(milliseconds: ms) : null;
  }

  Future<void> _clearResumePosition(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('resume_$key');
    debugPrint("🧹 Cleared resume for $key");
  }

// =========================================================
// 🧭 map category → mode
// =========================================================
  String mapCategoryToMode(String? category) {
    switch (category) {
      case "Cartoon":
        return "anime";
      case "Anime":
        return "anime";
      case "Pet":
        return "pet";
      default:
        return "portrait";
    }
  }

  // CONNECT TO ROS SERVER

  Future<void> _connectRos() async {
    setState(() => rosConnecting = true);
    ros = Ros(url: 'ws://192.168.1.177:9090');

    try {
      ros.connect();
      setState(() {
        rosConnected = true;
        rosConnecting = false;
      });

      poseTopic = Topic(
        ros: ros,
        name: '/arm_target_pose',
        type: 'geometry_msgs/PoseStamped',
      );

      cameraTopic = Topic(
        ros: ros,
        name: '/camera/image_raw/compressed',
        type: 'sensor_msgs/CompressedImage',
      );

      commandTopic = Topic(
        ros: ros,
        name: '/sketchbot_command',
        type: 'std_msgs/String',
      );
      Topic poseSavedTopic = Topic(
        ros: ros,
        name: '/sketchbot/pose_saved',
        type: 'std_msgs/String',
      );
      await poseSavedTopic.subscribe((msg) {
        final data = msg['data']?.toString().trim() ?? '';
        if (data == "pose_saved") {
          debugPrint("💾 Pose saved confirmed from ROS");
          if (!mounted)
            return Future.value(); // ✅ ป้องกันก่อนเรียก setState หรือ pop

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Drawing complete, syncing gallery..."),
            ),
          );

          Navigator.pop(context, "refresh_gallery");
        }
        return Future.value();
      });
      Topic uploadStatusTopic = Topic(
        ros: ros,
        name: '/sketchbot/status',
        type: 'std_msgs/String',
      );
      await uploadStatusTopic.subscribe((msg) async {
        final data = msg['data']?.toString().trim() ?? '';
        if (data == "upload_complete") {
          debugPrint("📡 ROS: upload_complete received");
          await _handleDrawingComplete();
        }
        return Future.value();
      });
      _subscribeCamera();
      if (!isSimulationMode && widget.imagePath != null) {
        await commandTopic!.advertise();

        final mode = mapCategoryToMode(widget.categoryName);
        final payload = jsonEncode({
          "cmd": "draw",
          "mode": mode,
          "path": widget.imagePath,
        });

        commandTopic!.publish({"data": payload});
        debugPrint("🚀 Sent draw command to ROS → $payload");
      }
    } catch (e) {
      debugPrint("⚠️ Error: $e");
      setState(() {
        rosConnected = false;
        rosConnecting = false;
      });
    }
  }

  void _subscribeCamera() {
    cameraTopic?.subscribe((dynamic msg) {
      try {
        final map = msg as Map;
        final data = map["data"];
        if (data is String) {
          final decoded = base64Decode(data);
          if (mounted) {
            cameraImageNotifier.value = decoded;
          }
        }
      } catch (e) {
        debugPrint("⚠️ Camera decode error: $e");
      }
      return Future.value();
    });
  }

  void _disconnectRos() {
    try {
      cameraTopic?.unsubscribe();
      poseTopic?.unsubscribe();
      commandTopic?.unsubscribe();
      ros.close();
      debugPrint("🧹 ROS disconnected & topics unsubscribed.");
    } catch (e) {
      debugPrint("⚠️ Error while closing ROS: $e");
    }

    if (!mounted) return;
    try {
      setState(() => rosConnected = false);
    } catch (e) {
      debugPrint("⚠️ Safe ignore: setState after dispose ($e)");
    }
  }

  Future<void> _handleDrawingComplete() async {
    try {
      debugPrint("✅ Drawing finished — resetting UI");

      cameraTopic?.unsubscribe();
      rosConnected = false;

      await _mainController?.pause();
      await _smallController?.pause();

      if (!mounted) return;
      setState(() => cameraImageNotifier.value = null);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Drawing complete! Returning to Save Page..."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      Navigator.pop(context, "refresh_save"); // ✅ กลับหน้า SavePage พร้อมรีเฟรช
    } catch (e) {
      debugPrint("⚠️ Error during handleDrawingComplete: $e");
    }
  }

  @override
  void dispose() {
    if (rosConnected) {
      _disconnectRos();
    }
    _mainController?.dispose();
    _smallController?.dispose();
    super.dispose();
  }

  // =========================================================
  // 🖥️ BUILD MAIN SCREEN
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(isSimulationMode ? "Drawing Simulation" : "Robot Control"),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isSimulationMode) ...[
            IconButton(
              icon: const Icon(Icons.save, color: Colors.green),
              tooltip: "Save Simulation",
              onPressed: () async {
                if (_mainController != null) {
                  await _saveResumePosition(_mainController!.value.position,
                      "main_${widget.videoUrl}");
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("💾 ตำแหน่งวิดีโอจำลองถูกบันทึกแล้ว",
                          style: TextStyle(color: Colors.white)),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.power_settings_new, color: Colors.red),
              tooltip: "Exit Simulation",
              onPressed: () async {
                await _mainController?.pause();
                await _smallController?.pause();
                if (mounted) Navigator.pop(context);
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.save, color: Colors.green),
              tooltip: "Save Drawing",
              onPressed:
                  rosConnected ? _saveCurrentState : null, // ✅ ไม่มีวงเล็บ!
            ),
            IconButton(
              icon: const Icon(Icons.power_settings_new, color: Colors.red),
              tooltip: "Disconnect",
              onPressed: rosConnected
                  ? () {
                      _disconnectRos();
                      Navigator.pop(
                          context, "refresh_gallery"); // ✅ กลับพร้อม reload
                    }
                  : null,
            ),
          ],
        ],
      ),
      body: isSimulationMode ? _buildVideoSimulationUI() : _buildRosUI(),
    );
  }

// =========================================================
// 🎬 VIDEO SIMULATION MODE (เพิ่ม fullscreen + zoom)
// =========================================================
  Widget _buildVideoSimulationUI() {
    if (_mainController == null || !_mainController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        // 🎥 วิดีโอหลัก + ปุ่ม fullscreen มุมขวาล่างของวิดีโอ
        Positioned.fill(
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 3.0,
                panEnabled: true,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: Stack(
                    children: [
                      SizedBox(
                        width: _mainController!.value.size.width,
                        height: _mainController!.value.size.height,
                        child: VideoPlayer(_mainController!),
                      ),
                      // ✅ ปุ่ม fullscreen อยู่ในขอบของวิดีโอ
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              PageRouteBuilder(
                                pageBuilder: (_, __, ___) =>
                                    FullScreenVideoPage(
                                        controller: _mainController!),
                                transitionsBuilder: (_, animation, __, child) {
                                  return FadeTransition(
                                      opacity: animation, child: child);
                                },
                                transitionDuration:
                                    const Duration(milliseconds: 350),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.all(32),
                            child: const Icon(
                              Icons.fullscreen,
                              color: Colors.white,
                              size: 92,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 🧩 วิดีโอเล็ก (มุมขวาบน)
        if (_smallController != null && _smallController!.value.isInitialized)
          Positioned(
            top: MediaQuery.of(context).padding.top + 2,
            right: 10,
            child: GestureDetector(
              onTap: () async {
                if (_mainController == null || _smallController == null) return;

                await _saveResumePosition(
                    _mainController!.value.position, "main_${widget.videoUrl}");
                await _saveResumePosition(_smallController!.value.position,
                    "small_${widget.videoUrlSmall}");

                final temp = _mainController;
                _mainController = _smallController;
                _smallController = temp;

                setState(() {
                  isSwapped = !isSwapped;
                });

                final newKey = isSwapped
                    ? "small_${widget.videoUrlSmall}"
                    : "main_${widget.videoUrl}";
                final resumePos = await _loadResumePosition(newKey);

                if (resumePos != null &&
                    resumePos < _mainController!.value.duration) {
                  await _mainController!.seekTo(resumePos);
                }

                await _mainController!.play();
                await _smallController!.pause();

                setState(() {});
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white70, width: 1.2),
                ),
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: size.width * 0.25,
                  child: AspectRatio(
                    aspectRatio: _smallController!.value.aspectRatio,
                    child: VideoPlayer(_smallController!),
                  ),
                ),
              ),
            ),
          ),

        // 🎛 ปุ่มควบคุมด้านล่าง
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow, color: Colors.black),
                  label: const Text("Start"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    if (_mainController == null) return;
                    final controller = _mainController!;
                    final pos = controller.value.position;
                    final dur = controller.value.duration;
                    if (pos >= dur) {
                      await controller.seekTo(Duration.zero);
                      await controller.play();
                      await _clearResumePosition("main_${widget.videoUrl}");
                    } else if (!controller.value.isPlaying) {
                      await controller.play();
                    }
                    setState(() {});
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.stop, color: Colors.black),
                  label: const Text("Stop"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    await _mainController?.pause();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
// 🤖 ROS MODE (เวอร์ชันอัปเดต real-time + fullscreen + zoom)
// =========================================================
  Widget _buildRosUI() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400, width: 2),
                borderRadius: BorderRadius.circular(16),
                color: Colors.black,
              ),
              child: ValueListenableBuilder<Uint8List?>(
                valueListenable: cameraImageNotifier,
                builder: (context, imageBytes, _) {
                  if (imageBytes == null) {
                    return Center(
                      child: Text(
                        rosConnecting
                            ? "🔄 Connecting to ROS..."
                            : rosConnected
                                ? "✅ Waiting for camera stream..."
                                : "❌ Not connected",
                        style: TextStyle(
                          color: rosConnected
                              ? Colors.green
                              : rosConnecting
                                  ? Colors.orange
                                  : Colors.red,
                          fontSize: 18,
                        ),
                      ),
                    );
                  }

                  // ✅ ถ้ามีภาพจาก ROS → แสดงภาพพร้อมปุ่ม fullscreen
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        // 🔍 Zoom / Pan ได้
                        InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 3.0,
                          panEnabled: true,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: RepaintBoundary(
                              // ✅ ป้องกัน Flutter re-paint ทั้ง stack
                              child: Image.memory(
                                imageBytes,
                                gaplessPlayback:
                                    true, // ✅ ป้องกัน flicker ตอนเปลี่ยนเฟรม
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),

                        // 🔳 ปุ่ม fullscreen (มุมขวาล่างของภาพ)
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  pageBuilder: (_, __, ___) =>
                                      FullScreenImagePage(
                                          imageNotifier: cameraImageNotifier),
                                  transitionsBuilder:
                                      (_, animation, __, child) {
                                    return FadeTransition(
                                        opacity: animation, child: child);
                                  },
                                  transitionDuration:
                                      const Duration(milliseconds: 350),
                                ),
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(40),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: const Icon(
                                Icons.fullscreen,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // 🎛 ปุ่มควบคุม ROS
        if (rosConnected)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow, color: Colors.black),
                  label: const Text("Start"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _sendCommand("start"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.stop, color: Colors.black),
                  label: const Text("Stop"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _sendCommand("stop"),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // =========================================================
  // 💾 SAVE & GO TO SAVE PAGE
  // =========================================================

  void _sendCommand(dynamic cmd) {
    if (rosConnected && commandTopic != null) {
      if (cmd is String) {
        commandTopic!.publish({"data": cmd});
        debugPrint("🚀 Command sent: $cmd");
      } else if (cmd is Map<String, dynamic>) {
        final jsonCmd = jsonEncode(cmd);
        commandTopic!.publish({"data": jsonCmd});
        debugPrint("🚀 JSON Command sent: $jsonCmd");
      }
    } else {
      debugPrint("⚠️ Cannot send command: not connected to ROS");
    }
  }
}

// =========================================================
// 🖼️ FULLSCREEN IMAGE PAGE (ROS real-time + แนวนอน + zoom)
// =========================================================
class FullScreenImagePage extends StatefulWidget {
  final ValueNotifier<Uint8List?> imageNotifier;
  const FullScreenImagePage({super.key, required this.imageNotifier});

  @override
  State<FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<FullScreenImagePage> {
  Uint8List? _lastGoodFrame;
  DateTime _lastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // ✅ หมุนแนวนอนตอนเข้า fullscreen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);

    // ✅ ฟัง imageNotifier แบบ manual เพื่อควบคุม update rate
    widget.imageNotifier.addListener(_onNewFrame);
  }

  void _onNewFrame() {
    final now = DateTime.now();
    final diff = now.difference(_lastUpdate).inMilliseconds;

    // ⏱ จำกัดการอัปเดตภาพใหม่ทุก 150ms (~6–7 FPS)
    if (diff > 150) {
      final newBytes = widget.imageNotifier.value;
      if (newBytes != null && newBytes.isNotEmpty) {
        setState(() {
          _lastGoodFrame = newBytes;
        });
        _lastUpdate = now;
      }
    }
  }

  @override
  void dispose() {
    widget.imageNotifier.removeListener(_onNewFrame);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _lastGoodFrame == null
                  ? const CircularProgressIndicator(color: Colors.white)
                  : InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4.0,
                      panEnabled: true,
                      child: RepaintBoundary(
                        child: Image.memory(
                          _lastGoodFrame!,
                          gaplessPlayback: true, // ✅ ป้องกันภาพวูบดำ
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
            ),
            // ❌ ปุ่มปิด
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 36),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// 🖥️ FULLSCREEN VIDEO PAGE (พร้อม zoom)
// =========================================================
class FullScreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;

  const FullScreenVideoPage({super.key, required this.controller});

  @override
  State<FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 3.0,
                panEnabled: true,
                child: AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
