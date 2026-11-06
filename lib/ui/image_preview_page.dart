import 'dart:io';

import 'package:flutter/material.dart';

class ImagePreviewPage extends StatelessWidget {
  const ImagePreviewPage({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('图片预览')),
    body: SafeArea(
      child: Center(
        child: InteractiveViewer(
          minScale: .5,
          maxScale: 5,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text('图片文件不可用'),
          ),
        ),
      ),
    ),
  );
}
