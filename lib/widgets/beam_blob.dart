import 'package:blobs/blobs.dart';
import 'package:flutter/material.dart';

class BeamBlob extends StatefulWidget {
  final bool beaming;
  final VoidCallback onBeamToggle;
  const BeamBlob({super.key, this.beaming = true, required this.onBeamToggle});

  @override
  State<BeamBlob> createState() => _BeamBlobState();
}

class _BeamBlobState extends State<BeamBlob> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onBeamToggle,
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 500),
        crossFadeState:
            widget.beaming
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
        firstChild: Stack(
          children: [
            Center(
              child: Blob.animatedRandom(
                size: 400,
                styles: BlobStyles(
                  fillType: BlobFillType.stroke,
                  gradient: LinearGradient(
                    colors: [Colors.green, Colors.black, Colors.white],
                  ).createShader(Rect.fromLTWH(0, 0, 400, 400)),
                ),
                duration: Duration(seconds: 1),
                loop: true,
              ),
            ),
            Center(
              child: Blob.animatedRandom(
                size: 400,
                styles: BlobStyles(
                  fillType: BlobFillType.stroke,
                  gradient: LinearGradient(
                    colors: [Colors.green, Colors.black, Colors.white],
                  ).createShader(Rect.fromLTWH(0, 0, 400, 400)),
                ),
                duration: Duration(seconds: 1),
                loop: true,
              ),
            ),
          ],
        ),
        secondChild: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Blob.random(
                size: 400,
                styles: BlobStyles(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Text(
                'Start',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
