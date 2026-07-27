import 'package:flutter_resilient_http/flutter_resilient_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RetryPolicy Tests', () {
    test('calculateDelay should apply exponential backoff', () {
      final policy = const RetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        backoffFactor: 2.0,
        useJitter: false,
      );

      expect(policy.calculateDelay(1).inMilliseconds, equals(100));
      expect(policy.calculateDelay(2).inMilliseconds, equals(200));
      expect(policy.calculateDelay(3).inMilliseconds, equals(400));
    });

    test('calculateDelay should respect maxDelay cap', () {
      final policy = const RetryPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 3),
        backoffFactor: 5.0,
        useJitter: false,
      );

      expect(policy.calculateDelay(3).inMilliseconds, equals(3000));
    });
  });

  group('OfflineRequestQueue Tests', () {
    test('enqueue and dequeue should maintain FIFO order', () {
      final queue = OfflineRequestQueue();
      final req1 = QueuedRequest(
        id: '1',
        url: Uri.parse('https://example.com/api/1'),
        method: 'POST',
      );
      final req2 = QueuedRequest(
        id: '2',
        url: Uri.parse('https://example.com/api/2'),
        method: 'POST',
      );

      queue.enqueue(req1);
      queue.enqueue(req2);

      expect(queue.length, equals(2));
      expect(queue.dequeue()?.id, equals('1'));
      expect(queue.dequeue()?.id, equals('2'));
      expect(queue.isEmpty, isTrue);
    });

    test('should respect maxCapacity constraint', () {
      final queue = OfflineRequestQueue(maxCapacity: 2);
      final req = QueuedRequest(
        id: '1',
        url: Uri.parse('https://example.com'),
        method: 'POST',
      );

      expect(queue.enqueue(req), isTrue);
      expect(queue.enqueue(req), isTrue);
      expect(queue.enqueue(req), isFalse);
      expect(queue.length, equals(2));
    });

    test('processQueue should clear items when processor succeeds', () async {
      final queue = OfflineRequestQueue();
      queue.enqueue(QueuedRequest(
        id: '1',
        url: Uri.parse('https://example.com'),
        method: 'POST',
      ));

      final processed = await queue.processQueue((req) async => true);
      expect(processed, equals(1));
      expect(queue.isEmpty, isTrue);
    });
  });

  group('ResilientHttpClient Offline Tests', () {
    test('should throw OfflineRequestException when offline', () async {
      final client = ResilientHttpClient(
        isOffline: () => true,
        offlineQueue: OfflineRequestQueue(),
      );

      final req = Uri.parse('https://example.com/data');
      expect(
        () => client.get(req),
        throwsA(isA<OfflineRequestException>()),
      );
    });

    test('should enqueue POST request when offline', () async {
      final queue = OfflineRequestQueue();
      final client = ResilientHttpClient(
        isOffline: () => true,
        offlineQueue: queue,
      );

      try {
        await client.post(Uri.parse('https://example.com/item'), body: 'test');
      } catch (e) {
        expect(e, isA<OfflineRequestException>());
        expect((e as OfflineRequestException).wasQueued, isTrue);
      }

      expect(queue.length, equals(1));
      expect(queue.peek()?.method, equals('POST'));
    });
  });
}
