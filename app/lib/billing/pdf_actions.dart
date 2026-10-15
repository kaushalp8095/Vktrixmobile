import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

/// Android-native save/share keeps the actual PDF attachment and can target
/// WhatsApp specifically. Printing.sharePdf is a safe fallback for other
/// platforms and test environments where the native channel is unavailable.
class PdfActions {
  static const _channel = MethodChannel('com.vktrix.mobileapp/billing');

  static Future<String> savePdf(Uint8List bytes, String fileName) async {
    try {
      final result = await _channel.invokeMethod<String>('savePdf', {
        'bytes': bytes,
        'fileName': fileName,
      });
      return result ?? 'saved';
    } on MissingPluginException {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return 'shared';
    }
  }

  /// Returns `whatsapp_not_installed` when neither WhatsApp app is available.
  static Future<String> sharePdf(Uint8List bytes, String fileName,
      {required bool whatsapp, String? caption}) async {
    try {
      final result = await _channel.invokeMethod<String>('sharePdf', {
        'bytes': bytes,
        'fileName': fileName,
        'whatsapp': whatsapp,
        if (caption != null) 'caption': caption,
      });
      return result ?? 'started';
    } on MissingPluginException {
      await Printing.sharePdf(bytes: bytes, filename: fileName,
        subject: caption, body: caption);
      return 'started';
    }
  }

  static Future<String> shareReminder(String text, {bool whatsapp = true}) async {
    try {
      final result = await _channel.invokeMethod<String>('shareText', {
        'text': text,
        'whatsapp': whatsapp,
      });
      return result ?? 'started';
    } on MissingPluginException {
      return 'unsupported';
    }
  }
}
