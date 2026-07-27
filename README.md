# flutter_resilient_http

[![pub package](https://img.shields.io/pub/v/flutter_resilient_http.svg)](https://pub.dev/packages/flutter_resilient_http)
[![Build Status](https://img.shields.io/github/actions/workflow/status/lekthedeveloper/flutter_resilient_http/ci.yml?branch=main)](https://github.com/lekthedeveloper/flutter_resilient_http)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)](https://flutter.dev)

A production-ready, highly resilient HTTP client wrapper for **Flutter & Dart**. Built over standard `http.Client`, it provides **exponential backoff retries with jitter**, an enterprise **circuit breaker pattern**, and an **offline request queueing & replay engine**.

---

## 🌟 Key Features

- 🔄 **Exponential Backoff & Jitter:** Automatically retries failing requests with configurable backoff timing and randomized jitter to prevent server overload.
- ⚡ **Circuit Breaker Pattern:** Prevents cascading backend failures by tripping into `OPEN` state after repeated HTTP 5xx or connection errors.
- 📶 **Offline Request Queueing:** Intercepts POST/PUT/DELETE mutations while offline, stores them, and replays them when connectivity restores.
- 🛠️ **Seamless `http` Drop-In:** Directly extends `http.BaseClient`, making it fully compatible with existing Dart/Flutter network codebases.
- 📊 **Telemetry & Logging:** Configurable hooks for tracking network attempt metrics, circuit state changes, and queue processing events.

---

## 📦 Installation

Add `flutter_resilient_http` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_resilient_http: ^1.0.0
```

Then run:

```bash
flutter pub get
```

---

## 🚀 Quick Start

### 1. Basic Usage with Retries

```dart
import 'package:flutter_resilient_http/flutter_resilient_http.dart';

final client = ResilientHttpClient(
  retryPolicy: const RetryPolicy(
    maxRetries: 3,
    initialDelay: Duration(milliseconds: 500),
    useJitter: true,
  ),
);

// Use like standard http client
final response = await client.get(Uri.parse('https://api.example.com/data'));
print('Response: ${response.statusCode}');
```

---

### 2. Full Enterprise Configuration (Retries + Circuit Breaker + Offline Queue)

```dart
import 'package:flutter_resilient_http/flutter_resilient_http.dart';

// Create Circuit Breaker
final circuitBreaker = CircuitBreaker(
  failureThreshold: 5,
  resetTimeout: Duration(seconds: 30),
  onStateChange: (oldState, newState) {
    print('Circuit Breaker transitioned from $oldState to $newState');
  },
);

// Create Offline Queue
final offlineQueue = OfflineRequestQueue(maxCapacity: 50);

// Initialize ResilientHttpClient
final client = ResilientHttpClient(
  retryPolicy: const RetryPolicy(
    maxRetries: 3,
    retryStatusCodes: {408, 429, 500, 502, 503, 504},
  ),
  circuitBreaker: circuitBreaker,
  offlineQueue: offlineQueue,
  isOffline: () => checkConnectivityStatus(), // Connect your connectivity_plus logic
  onLog: (msg) => print('[HTTP Log] $msg'),
);

// Send request
try {
  final response = await client.post(
    Uri.parse('https://api.example.com/orders'),
    body: {'item': 'widget'},
  );
} on OfflineRequestException catch (e) {
  print('Device is offline! Request queued for replay: ${e.wasQueued}');
} on CircuitBreakerOpenException catch (e) {
  print('Circuit is OPEN. Try again in ${e.timeRemaining.inSeconds} seconds.');
}

// When network restores, replay queued requests
await client.flushOfflineQueue();
```

---

## 🏛️ Architecture Overview

```
                      +-----------------------------+
                      |    ResilientHttpClient      |
                      +--------------+--------------+
                                     |
             +-----------------------+-----------------------+
             |                                               |
   [ Network Check ]                               [ Circuit Breaker ]
   Is Device Offline?                              Is Circuit Open?
    /             \                                 /            \
  YES              NO                             YES             NO
  /                 \                             /                \
[Queue Mutation]   [Execute Request]   [Throw CircuitOpen]  [Run Retries]
```

---

## 🧪 Testing

`flutter_resilient_http` comes with comprehensive unit tests:

```bash
flutter test
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Developed with ❤️ by [Olamilekan Adeyemi (@lekthedeveloper)](https://github.com/lekthedeveloper).
