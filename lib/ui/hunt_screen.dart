import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_state.dart';
import '../theme.dart';
import 'book_screen.dart';
import 'mark.dart';
import 'rail.dart';
import 'result_screen.dart';

/// The viewfinder. Point it at a wall of cards and press the ring.
class HuntScreen extends StatefulWidget {
  const HuntScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HuntScreen> createState() => _HuntScreenState();
}

enum _CamStatus { starting, ready, denied, missing, failed }

class _HuntScreenState extends State<HuntScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  var _status = _CamStatus.starting;
  var _torch = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final cam = _cam;
    if (s == AppLifecycleState.inactive) {
      _cam = null;
      _torch = false;
      cam?.dispose();
      if (mounted) setState(() => _status = _CamStatus.starting);
    } else if (s == AppLifecycleState.resumed && cam == null) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _status = _CamStatus.missing);
        return;
      }
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      // Full sensor resolution: collector numbers are small and OCR needs pixels.
      final cam = CameraController(back, ResolutionPreset.max, enableAudio: false);
      await cam.initialize();
      await cam.setFlashMode(FlashMode.off);
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _status = _CamStatus.ready;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.code.contains('AccessDenied') ? _CamStatus.denied : _CamStatus.failed);
    }
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (cam == null || _busy || cam.value.isTakingPicture) return;
    setState(() => _busy = true);
    try {
      final shot = await cam.takePicture();
      if (_torch) {
        await cam.setFlashMode(FlashMode.off);
        _torch = false;
      }
      if (mounted) await _open(shot.path, fromCamera: true);
    } on CameraException catch (e) {
      _say('Could not take the photo (${e.code}).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null && mounted) await _open(picked.path);
  }

  Future<void> _open(String path, {bool fromCamera = false}) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultScreen(imagePath: path, state: widget.state, fromCamera: fromCamera)),
      );

  Future<void> _toggleTorch() async {
    final cam = _cam;
    if (cam == null) return;
    final on = !_torch;
    try {
      await cam.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      setState(() => _torch = on);
    } on CameraException {
      _say('This camera has no torch.');
    }
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SideRail(
            leading: const PeghuntMark(size: 34),
            label: 'Peghunt',
            bottom: [
              RailButton(
                icon: _torch ? Icons.flashlight_on : Icons.flashlight_off_outlined,
                tooltip: 'Torch',
                active: _torch,
                onTap: _status == _CamStatus.ready ? _toggleTorch : null,
              ),
              RailButton(icon: Icons.photo_library_outlined, tooltip: 'Scan a saved photo', onTap: _pick),
              RailButton(
                icon: Icons.menu_book_outlined,
                tooltip: 'Hunt book',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BookScreen(state: widget.state)),
                ),
              ),
            ],
          ),
          Expanded(child: _viewfinder()),
        ],
      ),
    );
  }

  Widget _viewfinder() {
    final cam = _cam;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (_status == _CamStatus.ready && cam != null)
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                // previewSize is reported landscape; the phone is portrait.
                width: cam.value.previewSize!.height,
                height: cam.value.previewSize!.width,
                child: CameraPreview(cam),
              ),
            ),
          )
        else
          _CameraMessage(status: _status, onRetry: _start, onPick: _pick),
        Positioned(
          left: 20,
          top: MediaQuery.paddingOf(context).top + 20,
          right: 20,
          child: Text('FILL THE FRAME WITH CARDS. CLOSER READS BETTER.',
              style: mono(11, color: Tone.bone.withValues(alpha: 0.8))),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom + 28,
          child: Center(
            child: _Shutter(
              enabled: _status == _CamStatus.ready && !_busy,
              busy: _busy,
              onTap: _shoot,
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.status, required this.onRetry, required this.onPick});
  final _CamStatus status;
  final VoidCallback onRetry;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    if (status == _CamStatus.starting) return const SizedBox.shrink();
    final (title, body) = switch (status) {
      _CamStatus.denied => ('Camera is off.', 'Peghunt reads the cards through the camera. Allow it in Settings, or scan a photo you already took.'),
      _CamStatus.missing => ('No camera.', 'This device has no camera Peghunt can use. You can still scan a saved photo.'),
      _ => ('Camera failed.', 'Something stopped the camera from starting. Try again, or scan a saved photo.'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 140),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: syne(34)),
          const SizedBox(height: 12),
          Text(body, style: manrope(15, color: Tone.dim, height: 1.45)),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _FlatButton(label: 'Try again', onTap: onRetry),
            _FlatButton(label: 'Scan a photo', onTap: onPick, filled: false),
          ]),
        ],
      ),
    );
  }
}

class _FlatButton extends StatelessWidget {
  const _FlatButton({required this.label, required this.onTap, this.filled = true});
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: filled ? Tone.bone : Colors.transparent,
            border: Border.all(color: Tone.bone, width: 1.5),
          ),
          child: Text(label, style: manrope(14, weight: FontWeight.w700, color: filled ? Tone.black : Tone.bone)),
        ),
      );
}

/// The shutter is the brand's ring. It spins while the photo is being taken.
class _Shutter extends StatefulWidget {
  const _Shutter({required this.enabled, required this.busy, required this.onTap});
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  var _down = false;

  @override
  void didUpdateWidget(_Shutter old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_spin.isAnimating) _spin.repeat();
    if (!widget.busy && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take photo and scan',
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _down = false);
                widget.onTap();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 90),
          child: SizedBox.square(
            dimension: 84,
            child: AnimatedBuilder(
              animation: _spin,
              builder: (_, _) => CustomPaint(
                painter: _ShutterPainter(enabled: widget.enabled || widget.busy, busy: widget.busy, t: _spin.value),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterPainter extends CustomPainter {
  _ShutterPainter({required this.enabled, required this.busy, required this.t});
  final bool enabled;
  final bool busy;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ink = enabled ? Tone.bone : Tone.faint;
    final ring = Paint()
      ..color = busy ? Tone.gold : ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (busy) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - 2), t * 6.2832, 4.4, false, ring);
    } else {
      canvas.drawCircle(c, r - 2, ring);
    }
    canvas.drawCircle(c, r - 12, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_ShutterPainter o) => o.enabled != enabled || o.busy != busy || o.t != t;
}
