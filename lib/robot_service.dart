import 'package:roslibdart/roslibdart.dart';

class RosService {
  late Ros ros;
  Topic? pub;

  void connect() {
    ros = Ros(url: 'ws://192.168.1.177:9090');

    ros.connect();
    print("🚀 Trying to connect...");

    // init topic หลัง connect (roslibdart ไม่ต้องรอ Future)
    pub = Topic(
      ros: ros,
      name: '/arm_target_pose',
      type: 'geometry_msgs/PoseStamped',
    );
  }

  void sendPose() {
    if (pub == null) {
      print("⚠️ Cannot publish: Topic not initialized.");
      return;
    }

    final msg = {
      "header": {"frame_id": "base_link"},
      "pose": {
        "position": {"x": 0.3, "y": 0.0, "z": 0.2},
        "orientation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
      }
    };
    pub!.publish(msg);
    print("📤 Pose sent!");
  }
}