import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_shop/documents/document_photo.dart';

void main() {
  test('document scan targets 100 KB, retains detail and always produces JPEG', () {
    final scan = img.Image(width: 2000, height: 1300);
    img.fill(scan, color: img.ColorRgb8(250, 250, 250));
    for (var y = 150; y < 1150; y += 90) {
      img.fillRect(scan, x1: 120, y1: y, x2: 1750, y2: y + 12, color: img.ColorRgb8(35, 35, 35));
    }
    final compressed = compressDocumentPhoto(img.encodePng(scan));
    final output = img.decodeJpg(compressed)!;
    expect(compressed.length, lessThanOrEqualTo(documentPhotoTargetBytes));
    expect(output.width, inInclusiveRange(1280, 1800));
    expect(output.width / output.height, closeTo(scan.width / scan.height, .005));
    expect(compressed.take(2), [0xff, 0xd8]);
    expect(output.getPixel(10, 10).r, greaterThan(240));
    // A black line remains distinguishable from the light background.
    expect(output.getPixel((300 * output.width / 2000).round(),
      (155 * output.height / 1300).round()).r, lessThan(80));
  });

  test('small transparent images are not enlarged and get a white background', () {
    final small = img.Image(width: 160, height: 100, numChannels: 4);
    final output = img.decodeJpg(compressDocumentPhoto(img.encodePng(small)))!;
    expect(output.width, 160);
    expect(output.height, 100);
    expect(output.getPixel(0, 0).r, greaterThan(245));
  });

  test('camera EXIF orientation is baked in and metadata is removed', () {
    final source = img.Image(width: 240, height: 120);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(source, x1: 0, y1: 0, x2: 100, y2: 119, color: img.ColorRgb8(0, 0, 0));
    source.exif.imageIfd.orientation = 6;
    final result = img.decodeJpg(compressDocumentPhoto(img.encodeJpg(source)))!;
    expect(result.width, 120);
    expect(result.height, 240);
    expect(result.exif.isEmpty, isTrue);
    expect(result.getPixel(60, 30).r, lessThan(30));
  });

  test('noisy photo keeps readability floor rather than forcing tiny dimensions', () {
    final noise = img.Image(width: 1300, height: 900);
    final random = Random(42);
    for (final pixel in noise) {
      pixel.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
    }
    final bytes = compressDocumentPhoto(img.encodePng(noise));
    final output = img.decodeJpg(bytes)!;
    expect(output.width, greaterThanOrEqualTo(1280));
    expect(bytes.length, greaterThan(documentPhotoTargetBytes));
    expect(bytes.length, lessThanOrEqualTo(documentPhotoMaxBytes));
  });

  test('invalid and oversized input is rejected', () {
    for (final bytes in [Uint8List(0), Uint8List.fromList([1, 2, 3]), Uint8List(documentPhotoMaxInputBytes + 1)]) {
      expect(() => compressDocumentPhoto(bytes), throwsFormatException);
    }
  });
}
