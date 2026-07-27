import 'package:flutter_resilient_http/flutter_resilient_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CircuitBreaker Tests', () {
    test('initial state should be closed with zero failures', () {
      final cb = CircuitBreaker(failureThreshold: 3);
      expect(cb.state, equals(CircuitState.closed));
      expect(cb.failureCount, equals(0));
    });

    test('should open circuit after reaching failure threshold', () {
      final cb = CircuitBreaker(failureThreshold: 3);
      cb.recordFailure();
      cb.recordFailure();
      expect(cb.state, equals(CircuitState.closed));

      cb.recordFailure();
      expect(cb.state, equals(CircuitState.open));
    });

    test('should throw CircuitBreakerOpenException when open', () async {
      final cb = CircuitBreaker(failureThreshold: 2);
      cb.recordFailure();
      cb.recordFailure();
      expect(cb.state, equals(CircuitState.open));

      expect(
        () => cb.execute(() async => 'test'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });

    test('should transition to halfOpen after resetTimeout', () async {
      final cb = CircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 100),
      );

      cb.recordFailure();
      expect(cb.state, equals(CircuitState.open));

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(cb.state, equals(CircuitState.halfOpen));
    });

    test('should reset to closed on success during halfOpen state', () async {
      final cb = CircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 50),
      );

      cb.recordFailure();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cb.state, equals(CircuitState.halfOpen));

      final result = await cb.execute(() async => 'recovered');
      expect(result, equals('recovered'));
      expect(cb.state, equals(CircuitState.closed));
      expect(cb.failureCount, equals(0));
    });

    test('should notify onStateChange callback', () {
      final stateChanges = <CircuitState>[];
      final cb = CircuitBreaker(
        failureThreshold: 2,
        onStateChange: (oldState, newState) => stateChanges.add(newState),
      );

      cb.recordFailure();
      cb.recordFailure();

      expect(stateChanges, equals([CircuitState.open]));
    });
  });
}
