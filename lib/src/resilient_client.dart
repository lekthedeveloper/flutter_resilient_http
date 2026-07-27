import 'dart:async';
import 'package:http/http.dart' as http;

import 'circuit_breaker.dart';
import 'offline_queue.dart';
import 'retry_policy.dart';

/// Exception thrown when a request cannot be sent due to offline status.
class OfflineRequestException implements Exception {
  final String message;
  final bool wasQueued;

  OfflineRequestException(this.message, {this.wasQueued = false});

  @override
  String toString() =>
      'OfflineRequestException: $message (Queued: $wasQueued)';
}

/// A resilient HTTP client wrapping standard [http.Client] with retries, circuit breaker,
/// and offline request queueing.
class ResilientHttpClient extends http.BaseClient {
  final http.Client _innerClient;
  final RetryPolicy retryPolicy;
  final CircuitBreaker? circuitBreaker;
  final OfflineRequestQueue? offlineQueue;

  /// Callback function to query network status. Returns true if device is offline.
  final bool Function()? isOffline;

  /// Optional logging handler.
  final void Function(String message)? onLog;

  ResilientHttpClient({
    http.Client? innerClient,
    this.retryPolicy = const RetryPolicy(),
    this.circuitBreaker,
    this.offlineQueue,
    this.isOffline,
    this.onLog,
  }) : _innerClient = innerClient ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 1. Check network connectivity status
    if (isOffline != null && isOffline!()) {
      onLog?.call('[ResilientHttpClient] Offline detected for ${request.method} ${request.url}');
      bool queued = false;

      if (offlineQueue != null && _isMutationMethod(request.method)) {
        final String requestId =
            '${DateTime.now().millisecondsSinceEpoch}_${request.url.path.hashCode}';
        final QueuedRequest queuedReq =
            await QueuedRequest.fromBaseRequest(request, requestId);
        queued = offlineQueue!.enqueue(queuedReq);
        if (queued) {
          onLog?.call('[ResilientHttpClient] Request enqueued for offline replay (ID: $requestId)');
        }
      }

      throw OfflineRequestException(
        'Device is currently offline.',
        wasQueued: queued,
      );
    }

    // 2. Wrap request execution inside CircuitBreaker if configured
    if (circuitBreaker != null) {
      return await circuitBreaker!.execute(() => _sendWithRetries(request));
    }

    return await _sendWithRetries(request);
  }

  /// Sends request with exponential backoff retries according to [retryPolicy].
  Future<http.StreamedResponse> _sendWithRetries(http.BaseRequest request) async {
    int attempt = 0;

    while (true) {
      attempt++;
      onLog?.call('[ResilientHttpClient] Executing ${request.method} ${request.url} (Attempt $attempt)');

      try {
        // Clone request for potential retry attempt (since streams cannot be re-read)
        final http.BaseRequest clonedRequest = _cloneRequest(request);
        final http.StreamedResponse response =
            await _innerClient.send(clonedRequest);

        if (attempt <= retryPolicy.maxRetries &&
            retryPolicy.evaluateResponse(response)) {
          final Duration delay = retryPolicy.calculateDelay(attempt);
          onLog?.call(
              '[ResilientHttpClient] Received status ${response.statusCode}. Retrying in ${delay.inMilliseconds}ms...');
          await Future<void>.delayed(delay);
          continue;
        }

        return response;
      } catch (error) {
        if (attempt <= retryPolicy.maxRetries &&
            retryPolicy.evaluateError(error)) {
          final Duration delay = retryPolicy.calculateDelay(attempt);
          onLog?.call(
              '[ResilientHttpClient] Request error ($error). Retrying in ${delay.inMilliseconds}ms...');
          await Future<void>.delayed(delay);
          continue;
        }
        rethrow;
      }
    }
  }

  /// Replays all queued offline requests sequentially.
  Future<int> flushOfflineQueue() async {
    if (offlineQueue == null || offlineQueue!.isEmpty) return 0;
    onLog?.call('[ResilientHttpClient] Flushing ${offlineQueue!.length} offline requests...');

    return await offlineQueue!.processQueue((QueuedRequest queuedReq) async {
      try {
        final http.Request httpRequest = queuedReq.toHttpRequest();
        final http.StreamedResponse response = await send(httpRequest);
        return response.statusCode >= 200 && response.statusCode < 300;
      } catch (e) {
        onLog?.call('[ResilientHttpClient] Offline queue replay error: $e');
        return false;
      }
    });
  }

  /// Helper to clone HTTP requests for retry streams.
  http.BaseRequest _cloneRequest(http.BaseRequest request) {
    if (request is http.Request) {
      final http.Request clone = http.Request(request.method, request.url);
      clone.headers.addAll(request.headers);
      clone.bodyBytes = request.bodyBytes;
      clone.encoding = request.encoding;
      clone.followRedirects = request.followRedirects;
      clone.maxRedirects = request.maxRedirects;
      clone.persistentConnection = request.persistentConnection;
      return clone;
    }
    return request;
  }

  bool _isMutationMethod(String method) {
    final String m = method.toUpperCase();
    return m == 'POST' || m == 'PUT' || m == 'DELETE' || m == 'PATCH';
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}
