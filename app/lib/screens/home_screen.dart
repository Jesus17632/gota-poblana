import 'package:material_ui/material_ui.dart';
import '../services/esp32_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _hostCtrl = TextEditingController(text: '192.168.4.1');

  Esp32Service? _service; // null = no conectado
  bool _busy = false;
  bool _blinking = false;
  double _interval = 500;
  String? _error;

  bool get _connected => _service != null;

  /// Envuelve cualquier llamada: maneja loading y errores en un solo sitio.
  Future<void> _run(Future<Esp32Status> Function(Esp32Service s) action,
      {Esp32Service? using}) async {
    final service = using ?? _service;
    if (service == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await action(service);
      setState(() {
        _service = service;
        _blinking = status.blinking;
        _interval = status.interval.toDouble().clamp(100, 2000);
      });
    } catch (e) {
      setState(() => _error = 'No se pudo comunicar: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _connect() => _run((s) => s.getStatus(),
      using: Esp32Service(_hostCtrl.text.trim()));

  void _disconnect() => setState(() {
        _service = null;
        _blinking = false;
      });

  void _sendBlink(bool on) =>
      _run((s) => s.setBlink(on: on, interval: _interval.round()));

  @override
  void dispose() {
    _hostCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32 Blink')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Conexión ---
          TextField(
            controller: _hostCtrl,
            enabled: !_connected,
            decoration: const InputDecoration(
              labelText: 'IP del ESP32',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : (_connected ? _disconnect : _connect),
            icon: Icon(_connected ? Icons.link_off : Icons.link),
            label: Text(_connected ? 'Desconectar' : 'Conectar'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.circle,
                size: 12, color: _connected ? Colors.green : Colors.grey),
            const SizedBox(width: 8),
            Text(_connected ? 'Conectado' : 'Desconectado'),
            if (_busy) ...[
              const SizedBox(width: 12),
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ]),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const Divider(height: 32),

          // --- Control del blink ---
          SwitchListTile(
            title: const Text('Blink'),
            value: _blinking,
            onChanged: _connected && !_busy ? _sendBlink : null,
          ),
          ListTile(
            title: Text('Intervalo: ${_interval.round()} ms'),
            subtitle: Slider(
              min: 100,
              max: 2000,
              divisions: 19,
              value: _interval,
              onChanged: _connected ? (v) => setState(() => _interval = v) : null,
              // Al soltar el slider, si está parpadeando, aplica el nuevo intervalo
              onChangeEnd: (_) {
                if (_connected && _blinking) _sendBlink(true);
              },
            ),
          ),
        ],
      ),
    );
  }
}
