// Formateo de valores para la UI. "—" cuando falta un dato.
const String sinValor = '—';

String fmtPh(double? v) => v == null ? sinValor : v.toStringAsFixed(2);

String fmtNum(num? v, {int dec = 1, String unidad = ''}) {
  if (v == null) return sinValor;
  final s = v.toStringAsFixed(dec);
  return unidad.isEmpty ? s : '$s $unidad';
}

String haceTiempo(DateTime? t, DateTime ahora) {
  if (t == null) return sinValor;
  final d = ahora.difference(t);
  if (d.inSeconds < 60) return 'hace ${d.inSeconds.clamp(0, 59)} s';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} d';
}

String duracion(int? segundos) {
  if (segundos == null) return sinValor;
  final m = segundos ~/ 60, s = segundos % 60;
  return m == 0 ? '$s s' : '$m min ${s.toString().padLeft(2, '0')} s';
}

String _2(int v) => v.toString().padLeft(2, '0');
String hhmm(DateTime t) => '${_2(t.hour)}:${_2(t.minute)}';
String ddmm(DateTime t) => '${_2(t.day)}/${_2(t.month)}';

const _dias = [
  'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
  'septiembre', 'octubre', 'noviembre', 'diciembre'
];

String fechaLarga(DateTime t) =>
    '${_dias[t.weekday - 1]}, ${t.day} de ${_meses[t.month - 1]}';

String saludo(DateTime t) => t.hour < 12
    ? 'Buenos días'
    : (t.hour < 19 ? 'Buenas tardes' : 'Buenas noches');
