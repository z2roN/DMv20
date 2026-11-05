import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

/// 이미지 크게 보기 (확대/축소 가능)
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: '다른 앱으로 열기',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => OpenFilex.open(path),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(
            File(path),
            errorBuilder: (_, __, ___) =>
                const Text('이미지를 열 수 없습니다', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ),
    );
  }
}
