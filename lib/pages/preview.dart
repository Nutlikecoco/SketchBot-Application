import 'dart:typed_data';
import 'package:flutter/material.dart';

class PreviewPage extends StatelessWidget {
  final Uint8List imageBytes;

  const PreviewPage({super.key, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Preview Sketch")),
      body: Center(
        child: Image.memory(imageBytes),
      ),
    );
  }
}
