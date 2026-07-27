import 'dart:math';
import 'package:http/http.dart' as http;

/// Defines retry rules, delay math, and condition checks for HTTP requests.
class RetryPolicy {
  /// Maximum number of retry attempts allowed per request.
  final int maxRetries;

  /// Initial delay before the first retry attempt.
  final Duration initialDelay;

  /// Maximum cap for delay between retries.
  final Duration maxDelay;

  /// Multiplier for exponential backoff calculations.
  final double backoffFactor;

  /// Whether to add randomized jitter to backoff delay to prevent thundering herd.
  final bool useJitter;

  /// HTTP status codes that trigger a retry.
  final Set<int> retryStatusCodes;

  /// Custom evaluator function for deciding whether a request should be retried based on response.
  final bool Function(http.BaseResponse response)? shouldRetryResponse;

  /// Custom evaluator function for deciding whether an exception/error should trigger a retry.
  final bool Function(Object error)? shouldRetryError;

  const RetryPolicy({
    this.maxRetries = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 10),
    this.backoffFactor = 2.0,
    this.useJitter = true,
    this.retryStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.shouldRetryResponse,
    this.shouldRetryError,
  });

  /// Calculates the backoff delay for a given attempt number (1-indexed).
  Duration calculateDelay(int attempt) {
    if (attempt <= 0) return Duration.zero;

    final double rawDelayMs =
        (initialDelay.inMilliseconds * pow(backoffFactor, attempt - 1)).toDouble();
    double delayMs = min(rawDelayMs, maxDelay.inMilliseconds.toDouble());

    if (useJitter) {
      final Random random = Random();
      // Apply jitter between 75% and 125% of calculated delay
      final double jitterFactor = 0.75 + (random.nextDouble() * 0.5);
      delayMs = delayMs * jitterFactor;
    }

    return Duration(milliseconds: delayMs.round());
  }

  /// Determines if an HTTP response qualifies for a retry.
  bool evaluateResponse(http.BaseResponse response) {
    if (shouldRetryResponse != null) {
      return shouldRetryResponse!(response);
    }
    return retryStatusCodes.contains(response.statusCode);
  }

  /// Determines if an exception qualifies for a retry.
  bool evaluateError(Object error) {
    if (shouldRetryError != null) {
      return shouldRetryError!(error);
    }
    // By default, network level errors (e.g. SocketException, ClientException) trigger retries
    return true;
  }
}
