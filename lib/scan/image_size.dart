import 'dart:ui' as ui;

/// The photo's size the way it is shown: a phone held upright writes a
/// landscape JPEG plus an EXIF note to turn it, and both ML Kit and
/// Flutter apply that note. The header alone gives the unturned size, so a
/// tiny decode tells whether to swap it.
Future<ui.Size> orientedImageSize(String path) async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final raw = ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  final codec = await descriptor.instantiateCodec(targetWidth: 48);
  final frame = await codec.getNextFrame();
  final shownWide = frame.image.width >= frame.image.height;
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  final rawWide = raw.width >= raw.height;
  return shownWide == rawWide || raw.width == raw.height ? raw : raw.flipped;
}
