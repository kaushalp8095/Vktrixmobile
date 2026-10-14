import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Target per photo (the base64 API representation is about one third larger).
const documentPhotoTargetBytes = 100 * 1024;
const documentPhotoMaxBytes = 3 * 1024 * 1024;
const documentPhotoMaxInputBytes = 20 * 1024 * 1024;

/// Decode/resize/encode away from the UI isolate. Photos never leave the device
/// until the purchase is saved; EXIF/GPS metadata is not copied to the output.
Future<Uint8List> prepareDocumentPhoto(Uint8List bytes) =>
    compute(compressDocumentPhoto, bytes);

/// Aim for 100 KB, not a hard size cap at the expense of legible ID text.
/// Keep at least 1280px on the long edge (unless the original is smaller) and
/// JPEG quality >= 80. Detailed/noisy photos may exceed the target; the UI shows
/// their actual size and lets the user inspect the compressed result.
Uint8List compressDocumentPhoto(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > documentPhotoMaxInputBytes) {
    throw const FormatException('Choose a photo smaller than 20 MB.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 24000000) {
    throw const FormatException('Photo unsupported or too large. Try a closer photo.');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('Could not read this photo. Try JPEG or PNG.');
  }
  final oriented = img.bakeOrientation(decoded);
  final longest = math.max(oriented.width, oriented.height);
  Uint8List? smallest;
  for (final edge in <int>{math.min(longest, 1800), math.min(longest, 1500), math.min(longest, 1280)}) {
    final resized = longest <= edge ? oriented : img.copyResize(
      oriented,
      width: math.max(1, (oriented.width * edge / longest).round()),
      height: math.max(1, (oriented.height * edge / longest).round()),
      interpolation: img.Interpolation.average,
    );
    // A fresh RGB canvas strips metadata and makes transparent scans white,
    // rather than black, when encoded as JPEG.
    final canvas = img.Image(width: resized.width, height: resized.height, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, resized);
    for (final quality in [94, 90, 86, 82, 80]) {
      final encoded = img.encodeJpg(canvas, quality: quality);
      if (smallest == null || encoded.length < smallest.length) smallest = encoded;
      if (encoded.length <= documentPhotoTargetBytes) return encoded;
    }
  }
  if (smallest == null || smallest.length > documentPhotoMaxBytes) {
    throw const FormatException('Photo too large. Crop the document and try again.');
  }
  return smallest;
}
