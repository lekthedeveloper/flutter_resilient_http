import 'dart:async';

/// States of a circuit breaker pattern.
enum CircuitState {
  /// Circuit operating normally; requests pass through.
  closed,

  /// Circuit tripped due to repeated failures; requests fail fast.
  open,

  /// Trial state after timeout; a single request is allowed to verify system recovery.
  halfOpen,
}

/// Thrown when a request is blocked because the CircuitBreaker is open.
class CircuitBreakerOpenException implements Exception {
  final String message;
  final Duration timeRemaining;

  CircuitBreakerOpenException(this.message, this.timeRemaining);

  @override
  String toString() =>
      'CircuitBreakerOpenException: $message (Retry after ${timeRemaining.inSeconds}s)';
}

/// Manages circuit health, tripping open on failures to protect remote services.
class CircuitBreaker {
  /// Number of consecutive failures before tripping the circuit open.
  final int failureThreshold;

  /// Duration to stay in the open state before transitioning to half-open.
  final Duration resetTimeout;

  /// Callback executed when circuit state changes.
  final void Function(CircuitState oldState, CircuitState newState)? onStateChange;

  CircuitState _state = CircuitState.closed;
  int _consecutiveFailures = 0;
  DateTime _lastStateChange = DateTime.now();

  CircuitBreaker({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 30),
    this.onStateChange,
  });

  /// Current state of the circuit breaker.
  CircuitState get state {
    _checkHalfOpenTransition();
    return _state;
  }

  /// Number of current consecutive failures.
  int get failureCount => _consecutiveFailures;

  /// Time when the last state transition occurred.
  DateTime get lastStateChange => _lastStateChange;

  /// Checks if the timeout has expired while open and moves to halfOpen.
  void _checkHalfOpenTransition() {
    if (_state == CircuitState.open) {
      final Duration elapsed = DateTime.now().difference(_lastStateChange);
      if (elapsed >= resetTimeout) {
        _transitionTo(CircuitState.halfOpen);
      }
    }
  }

  /// Transitions the circuit breaker state and invokes listener callbacks.
  void _transitionTo(CircuitState newState) {
    if (_state == newState) return;
    final CircuitState oldState = _state;
    _state = newState;
    _lastStateChange = DateTime.now();

    if (newState == CircuitState.closed) {
      _consecutiveFailures = 0;
    }

    onStateChange?.call(oldState, newState);
  }

  /// Records a successful operation outcome.
  void recordSuccess() {
    _checkHalfOpenTransition();
    if (_state == CircuitState.halfOpen || _state == CircuitState.open) {
      _transitionTo(CircuitState.closed);
    } else {
      _consecutiveFailures = 0;
    }
  }

  /// Records a failure outcome.
  void recordFailure() {
    _checkHalfOpenTransition();
    _consecutiveFailures++;

    if (_state == CircuitState.halfOpen ||
        _consecutiveFailures >= failureThreshold) {
      _transitionTo(CircuitState.open);
    }
  }

  /// Wraps an async action with circuit breaker protection.
  Future<T> execute<T>(Future<T> Function() action) async {
    _checkHalfOpenTransition();

    if (_state == CircuitState.open) {
      final Duration elapsed = DateTime.now().difference(_lastStateChange);
      final Duration timeRemaining = resetTimeout - elapsed;
      throw CircuitBreakerOpenException(
        'Circuit breaker is OPEN. Requests blocked to allow downstream recovery.',
        timeRemaining.isNegative ? Duration.zero : timeRemaining,
      );
    }

    try {
      final T result = await action();
      recordSuccess();
      return result;
    } catch (e) {
      recordFailure();
      rethrow;
    }
  }

  /// Manually resets the circuit breaker to closed state.
  void reset() {
    _transitionTo(CircuitState.closed);
  }
}
