import 'package:flutter/material.dart';
import 'package:flutter_resilient_http/flutter_resilient_http.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resilient HTTP Demo',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ResilientHttpClient _resilientClient;
  late final CircuitBreaker _circuitBreaker;
  late final OfflineRequestQueue _offlineQueue;

  final List<String> _logs = <String>[];
  bool _isSimulatedOffline = false;
  String _statusText = 'Ready';

  @override
  void initState() {
    super.initState();
    _circuitBreaker = CircuitBreaker(
      failureThreshold: 3,
      resetTimeout: const Duration(seconds: 10),
      onStateChange: (CircuitState oldState, CircuitState newState) {
        _log('⚡ Circuit State changed: $oldState ➡️ $newState');
      },
    );

    _offlineQueue = OfflineRequestQueue();

    _resilientClient = ResilientHttpClient(
      retryPolicy: const RetryPolicy(
        maxRetries: 3,
        initialDelay: Duration(milliseconds: 500),
        useJitter: true,
      ),
      circuitBreaker: _circuitBreaker,
      offlineQueue: _offlineQueue,
      isOffline: () => _isSimulatedOffline,
      onLog: (String message) => _log(message),
    );
  }

  void _log(String msg) {
    setState(() {
      _logs.insert(0, '[${DateTime.now().toString().split(' ').last}] $msg');
    });
  }

  Future<void> _fetchData() async {
    setState(() => _statusText = 'Fetching data...');
    try {
      final response = await _resilientClient.get(
        Uri.parse('https://jsonplaceholder.typicode.com/todos/1'),
      );
      setState(() => _statusText = 'Success! Code: ${response.statusCode}');
    } catch (e) {
      setState(() => _statusText = 'Failed: $e');
    }
  }

  Future<void> _sendMutation() async {
    setState(() => _statusText = 'Posting data...');
    try {
      final response = await _resilientClient.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        body: {'title': 'Resilient HTTP', 'body': 'Offline replay test'},
      );
      setState(() => _statusText = 'Success! Post Created (${response.statusCode})');
    } on OfflineRequestException catch (e) {
      setState(() => _statusText = 'Offline! Request Queued: ${e.wasQueued}');
    } catch (e) {
      setState(() => _statusText = 'Error: $e');
    }
  }

  Future<void> _flushQueue() async {
    final count = await _resilientClient.flushOfflineQueue();
    _log('Flushed $count requests successfully.');
  }

  @override
  void dispose() {
    _resilientClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_resilient_http Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text('Status: $_statusText', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Circuit State: ${_circuitBreaker.state.name.toUpperCase()}'),
                    Text('Offline Queue Length: ${_offlineQueue.length}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Simulate Offline'),
                    value: _isSimulatedOffline,
                    onChanged: (val) => setState(() => _isSimulatedOffline = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(onPressed: _fetchData, child: const Text('GET Request')),
                ElevatedButton(onPressed: _sendMutation, child: const Text('POST Request')),
                ElevatedButton(onPressed: _flushQueue, child: const Text('Flush Offline Queue')),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Event Logs:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Text(
                    _logs[index],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
