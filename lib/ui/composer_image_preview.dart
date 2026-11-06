import 'dart:io';

import 'package:flutter/material.dart';

/// The pending attachment stays above the input until explicitly sent.
class ComposerImagePreview extends StatelessWidget {
  const ComposerImagePreview({
    super.key,
    required this.path,
    required this.onRemove,
  });
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: '已附加图片',
        child: SizedBox(
          key: const ValueKey('composer-image-preview'),
          width: 80,
          height: 80,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1f243c32),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xffe8ede4),
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    tooltip: '移除图片',
                    onPressed: onRemove,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    padding: const EdgeInsets.all(8),
                    icon: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: Color(0xff243c32),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
