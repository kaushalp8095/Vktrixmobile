// API wrapper ka error mapping — network/proxy ke saath kya dikhta hai.
//
// Bug: `jsonDecode` par seedha bharosa tha. Render/Cloudflare ka HTML 502 page
// screen par `FormatException: Unexpected character` dikhata tha, aur JSON array
// body par `body['error']` NoSuchMethodError dekar asli status chhupa deta tha.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_shop/api.dart';

Object _error(void Function() run) {
  try {
    run();
  } on Exception catch (e) {
    return e;
  }
  throw StateError('expected an exception');
}

void main() {
  test('an HTML error page keeps the real HTTP status', () {
    final e = _error(() => Api.parseResponse(http.Response('<html>Bad Gateway</html>', 502)));
    expect('$e', contains('Error 502'));
    expect('$e', isNot(contains('FormatException')));
  });

  test('a JSON array body does not mask the error', () {
    final e = _error(() => Api.parseResponse(http.Response('[]', 400)));
    expect('$e', contains('Error 400'));
  });

  test('a JSON error object keeps the server message', () {
    final e = _error(() => Api.parseResponse(
        http.Response(jsonEncode({'error': 'Shop band hai. Admin se contact karein.'}), 403)));
    expect('$e', contains('Shop band hai'));
  });

  test('a structured error keeps its status and machine code', () {
    try {
      Api.parseResponse(http.Response(
          jsonEncode({'error': 'This shop has history.', 'code': 'shop_has_history'}), 409));
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 409);
      expect(e.code, 'shop_has_history');
      // Purana behaviour: `Exception: <message>` — har screen `'$e'` dikhati hai.
      expect('$e', 'Exception: This shop has history.');
    }
  });

  test('an empty body error still reports the status', () {
    final e = _error(() => Api.parseResponse(http.Response('', 500)));
    expect('$e', contains('Error 500'));
  });

  test('a successful object body is returned as a map', () {
    final body = Api.parseResponse(http.Response(jsonEncode({'ok': true, 'id': 7}), 200));
    expect(body, isA<Map>());
    expect(body['id'], 7);
  });

  test('server address must be a full https URL', () {
    expect(Api.validateServer('https://vktrixmobile.onrender.com'), isNull);
    expect(Api.validateServer('  https://example.com/  '), isNull);
    expect(Api.validateServer('https://'), isNotNull); // host nahi hai
    expect(Api.validateServer('vktrixmobile.onrender.com'), isNotNull); // scheme nahi
    expect(Api.validateServer('http://example.com'), isNotNull); // cleartext
    expect(Api.validateServer(''), isNotNull);
  });
}
