import 'dart:async';
import 'dart:collection';
import 'package:http/http.dart' as http;

/// Data model representing a queued HTTP request for offline replay.
class QueuedRequest {
  /// Unique request identifier.
  final String id;

  /// Target URL.
  final Uri url;

  /// HTTP verb (e.g. POST, PUT, DELETE, PATCH).
  final String method;

  /// HTTP headers map.
  final Map<String, String> headers;

  /// Request body payload as bytes.
  final List<int> bodyBytes;

  /// Timestamp when the request was enqueued.
  final DateTime createdAt;

  QueuedRequest({
    required this.id,
    required this.url,
    required this.method,
    Map<String, String>? headers,
    List<int>? bodyBytes,
    DateTime? createdAt,
  })  : headers = headers ?? <String, String>{},
        bodyBytes = bodyBytes ?? <int>[],
        createdAt = createdAt ?? DateTime.now();

  /// Converts a standard [http.BaseRequest] to a [QueuedRequest].
  static Future<QueuedRequest> fromBaseRequest(
      http.BaseRequest request, String id) async {
    List<int> bytes = <int>[];
    if (request is http.Request) {
      bytes = request.bodyBytes;
    }

    return QueuedRequest(
      id: id,
      url: request.url,
      method: request.method,
      headers: request.headers,
      bodyBytes: bytes,
    );
  }

  /// Recreates a ready-to-send [http.Request] from this queued item.
  http.Request toHttpRequest() {
    final http.Request request = http.Request(method, url);
    request.headers.addAll(headers);
    request.bodyBytes = bodyBytes;
    return request;
  }
}

/// In-memory queue for offline HTTP requests with replay capabilities.
class OfflineRequestQueue {
  final Queue<QueuedRequest> _queue = Queue<QueuedRequest>();

  /// Maximum queue capacity.
  final int maxCapacity;

  OfflineRequestQueue({this.maxCapacity = 100});

  /// Enqueues a request for future replay. Returns false if queue is full.
  bool enqueue(QueuedRequest request) {
    if (_queue.length >= maxCapacity) {
      return false;
    }
    _queue.addLast(request);
    return true;
  }

  /// Removes and returns the oldest queued request.
  QueuedRequest? dequeue() {
    if (_queue.isEmpty) return null;
    return _queue.removeFirst();
  }

  /// Views the next request in queue without removing it.
  QueuedRequest? peek() {
    if (_queue.isEmpty) return null;
    return _queue.first;
  }

  /// Current number of queued items.
  int get length => _queue.length;

  /// Whether the queue is currently empty.
  bool get isEmpty => _queue.isEmpty;

  /// Clears all queued items.
  void clear() {
    _queue.clear();
  }

  /// Sequentially processes queued items using a provided processor callback.
  /// If the processor returns true, the request is removed from the queue.
  /// If false, processing stops to preserve request order.
  Future<int> processQueue(
      Future<bool> Function(QueuedRequest request) processor) async {
    int processedCount = 0;
    while (_queue.isNotEmpty) {
      final QueuedRequest current = _queue.first;
      final bool success = await processor(current);
      if (success) {
        _queue.removeFirst();
        processedCount++;
      } else {
        break; // Stop on first failure to maintain request sequence integrity
      }
    }
    return processedCount;
  }
}
