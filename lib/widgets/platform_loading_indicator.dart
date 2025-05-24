import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io' show Platform;

class PlatformLoadingIndicator extends StatelessWidget {
  final double? size;
  final Color? color;
  final double? strokeWidth;

  const PlatformLoadingIndicator({
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final defaultSize = 20.0;
    final effectiveSize = size ?? defaultSize;

    if (Platform.isIOS) {
      // CupertinoActivityIndicator uses radius which is half of the size
      return CupertinoActivityIndicator(
        radius: effectiveSize / 2,
        color: color,
      );
    }

    return SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth ?? (effectiveSize * 0.1), // 10% of size
        valueColor:
            color != null ? AlwaysStoppedAnimation<Color>(color!) : null,
      ),
    );
  }
}
