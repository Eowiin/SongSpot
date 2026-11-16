import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/services/app_update_service.dart';

void main() {
  group('isOlderVersion', () {
    test('an earlier release is older', () {
      expect(isOlderVersion('2.3.3', '2.3.4'), isTrue);
      expect(isOlderVersion('2.2.9', '2.3.0'), isTrue);
      expect(isOlderVersion('1.9.9', '2.0.0'), isTrue);
    });

    test('compares numerically, not as text', () {
      expect(isOlderVersion('2.9.0', '2.10.0'), isTrue);
      expect(isOlderVersion('2.10.0', '2.9.0'), isFalse);
    });

    test('the same or a newer release is current', () {
      expect(isOlderVersion('2.3.4', '2.3.4'), isFalse);
      expect(isOlderVersion('2.4.0', '2.3.4'), isFalse);
    });

    test('ignores the build number', () {
      expect(isOlderVersion('2.3.4+57', '2.3.4'), isFalse);
      expect(isOlderVersion('2.3.3+99', '2.3.4'), isTrue);
    });

    test('anything unparseable never blocks', () {
      expect(isOlderVersion('', '2.3.4'), isFalse);
      expect(isOlderVersion('2.3.3', 'latest'), isFalse);
    });
  });
}
