import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../services/esp32_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _pollEvery = Duration(seconds: 2);

  final _hostCtrl = TextEditingController(text: '172.20.10.9');
  final _pathCtrl = TextEditingController(text: '/datos');

  Esp32Service? _service; // null = no conectado
  Timer? _pollTimer;
  bool _connecting = false;
  bool _polling = false; // evita peticiones encimadas
  SensorData? _datos;
  DateTime? _lastUpdate;
  // El firmware no reporta el estado del LED: lo recordamos localmente.
  // Al conectar se asume apagado.
  bool _ledOn = false;
  bool _ledBusy = false;
  String? _error;
  String _rawResult = '';

  bool get _connected => _service != null;

  // ---------- Conexión ----------

  Future<void> _connect() async {
    final service = Esp32Service(_hostCtrl.text.trim());
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final datos = await service.getDatos();
      setState(() {
        _service = service;
        _datos = datos;
        _lastUpdate = DateTime.now();
        _ledOn = false;
      });
      _pollTimer = Timer.periodic(_pollEvery, (_) => _refresh());
    } catch (e) {
      setState(() => _error = 'No se pudo conectar: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() {
      _service = null;
      _datos = null;
      _lastUpdate = null;
      _error = null;
    });
  }

  /// Llamado por el timer. Si falla, muestra el error pero sigue intentando.
  Future<void> _refresh() async {
    final service = _service;
    if (service == null || _polling) return;
    _polling = true;
    try {
      final datos = await service.getDatos();
      if (!mounted || _service != service) return;
      setState(() {
        _datos = datos;
        _lastUpdate = DateTime.now();
        _error = null;
      });
    } catch (e) {
      if (mounted && _service == service) {
        setState(() => _error = 'Sin respuesta del ESP32: $e');
      }
    } finally {
      _polling = false;
    }
  }

  // ---------- LED ----------

  Future<void> _setLed(bool on) async {
    final service = _service;
    if (service == null) return;
    setState(() => _ledBusy = true);
    try {
      await service.setLed(on);
      setState(() {
        _ledOn = on;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'No se pudo cambiar el LED: $e');
    } finally {
      if (mounted) setState(() => _ledBusy = false);
    }
  }

  // ---------- Debug ----------

  /// No requiere "Conectar"; usa la IP escrita en el campo.
  Future<void> _sendRaw() async {
    setState(() => _rawResult = 'Enviando...');
    final service = Esp32Service(_hostCtrl.text.trim());
    var path = _pathCtrl.text.trim();
    if (!path.startsWith('/')) path = '/$path';
    try {
      final r = await service.getRaw(path);
      setState(() => _rawResult = 'HTTP ${r.code}\n\n${r.body}');
    } catch (e) {
      setState(() => _rawResult = 'Error: $e');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pathCtrl.dispose();
    _hostCtrl.dispose();
    super.dispose();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    return Scaffold(
      appBar: AppBar(title: const Text('Cloración Agua')),
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
            onPressed:
                _connecting ? null : (_connected ? _disconnect : _connect),
            icon: Icon(_connected ? Icons.link_off : Icons.link),
            label: Text(_connected ? 'Desconectar' : 'Conectar'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.circle,
                size: 12, color: _connected ? Colors.green : Colors.grey),
            const SizedBox(width: 8),
            Text(_connected ? 'Conectado' : 'Desconectado'),
            if (_connecting) ...[
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

          // --- Datos del sensor ---
          Row(children: [
            Expanded(
                child: _DatoCard(
                    label: 'Temperatura',
                    value: datos == null
                        ? '--'
                        : '${datos.temperatura.toStringAsFixed(1)} °C')),
            const SizedBox(width: 8),
            Expanded(
                child: _DatoCard(
                    label: 'Humedad',
                    value: datos == null ? '--' : '${datos.humedad} %')),
            const SizedBox(width: 8),
            Expanded(
                child: _DatoCard(
                    label: 'Uptime',
                    value: datos == null ? '--' : '${datos.uptime} s')),
          ]),
          if (_lastUpdate != null) ...[
            const SizedBox(height: 4),
            Text(
              'Actualizado: ${TimeOfDay.fromDateTime(_lastUpdate!).format(context)}'
              ' · cada ${_pollEvery.inSeconds} s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),

          // --- LED ---
          SwitchListTile(
            title: const Text('LED'),
            subtitle: const Text('Estado recordado por la app'),
            value: _ledOn,
            onChanged: _connected && !_ledBusy ? _setLed : null,
          ),
          const Divider(height: 32),

          // --- Debug: explorar endpoints del firmware ---
          Text('Debug: GET manual',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pathCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ruta (ej. /datos, /led?estado=1)',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _sendRaw(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _sendRaw, child: const Text('GET')),
          ]),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _rawResult.isEmpty ? 'Sin respuesta aún' : _rawResult,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoCard extends StatelessWidget {
  const _DatoCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ]),
      ),
    );
  }
}
