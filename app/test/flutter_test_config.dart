import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (goldenFileComparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      (goldenFileComparator as LocalFileComparator).basedir,
    );
  }
  await testMain();
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.basedir);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (!result.passed && result.diffPercent <= 0.05) {
      debugPrint(
        'A tolerance of 5% is allowed. Actual diff: ${(result.diffPercent * 100).toStringAsFixed(2)}% '
        'for ${golden.path}',
      );
      return true;
    }

    if (!result.passed) {
      final error = await generateFailureOutput(result, golden, basedir);
      throw FlutterError(error);
    }
    return result.passed;
  }
}
