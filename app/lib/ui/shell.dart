import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'data_page.dart';
import 'format.dart';
import 'home_page.dart';
import 'nodos_page.dart';
import 'settings_page.dart';
import 'tokens.dart';
import 'widgets/common.dart';

/// Disposición de la pantalla según tamaño y orientación.
class Disposicion {
  const Disposicion(this.ancho, this.alto);
  final double ancho;
  final double alto;
  bool get horizontal => ancho > alto;

  /// Navegación lateral: tablet/escritorio o teléfono acostado.
  bool get lateral => ancho >= 900 || (horizontal && ancho >= 560);

  /// Dos columnas de contenido.
  bool get dosColumnas => ancho >= 760 || (horizontal && ancho >= 560);

  /// Teléfono acostado: poca altura, todo más compacto.
  bool get compacto => horizontal && alto < 500;

  static Disposicion of(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return Disposicion(s.width, s.height);
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  StreamSubscription<Aviso>? _sub;
  AppState? _state;

  static const _items = [
    (Icons.water_drop_outlined, Icons.water_drop, 'Inicio'),
    (Icons.insights_outlined, Icons.insights, 'Datos'),
    (Icons.hub_outlined, Icons.hub, 'Nodos'),
    (Icons.tune_outlined, Icons.tune, 'Ajustes'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (!identical(s, _state)) {
      _sub?.cancel();
      _state = s;
      _sub = s.avisos.listen(_mostrarAviso);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Avisos visuales distintos por tipo (duplican los pitidos del equipo).
  void _mostrarAviso(Aviso a) {
    if (!mounted) return;
    final (Color color, IconData icon) = switch (a.tipo) {
      TipoAviso.inicio => (Palette.dosificando, Icons.play_circle_fill),
      TipoAviso.fin => (Palette.normal, Icons.check_circle),
      TipoAviso.error => (Palette.error, Icons.error),
      TipoAviso.fueraNorma => (Palette.error, Icons.warning_rounded),
      TipoAviso.rechazo => (Palette.error, Icons.block),
      TipoAviso.advertencia => (Palette.precaucion, Icons.warning_amber_rounded),
      TipoAviso.info => (const Color(0xFF2B3237), Icons.info),
    };
    final fg = Palette.textoSobre(color);
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      backgroundColor: color,
      elevation: 0,
      duration: Duration(seconds: a.tipo == TipoAviso.rechazo ? 6 : 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Row(children: [
        Icon(icon, color: fg),
        const SizedBox(width: Esp.m),
        Expanded(
          child: Text(a.mensaje,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg)),
        ),
      ]),
    ));
  }

  void _ir(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final d = Disposicion.of(context);
    final ahora = s.ahora;
    final titulos = [saludo(ahora), 'Datos', 'Nodos', 'Ajustes'];
    final pages = [
      const HomePage(),
      const DataPage(),
      NodosPage(abrirInicio: () => _ir(0)),
      const SettingsPage(),
    ];
    final detener = mostrarDetener(s);
    final pad = d.compacto ? Esp.l : Esp.xl - 4;

    final contenido = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          pad, Esp.m, pad, d.lateral ? Esp.xxl + (detener ? 90 : 0) : 150),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PageHeader(
              titulo: titulos[_tab],
              subtitulo: fechaLarga(ahora),
              compacto: d.compacto,
              trailing: RolChip(tecnico: s.esTecnico, onTap: () => _ir(3)),
            ),
            AnimatedSwitcher(
              duration: animDur(context, 220),
              child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
            ),
          ]),
        ),
      ),
    );

    final barraDetener = detener
        ? Padding(
            padding: const EdgeInsets.fromLTRB(Esp.l, 0, Esp.l, Esp.s),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: const BarraDetener(),
            ),
          )
        : const SizedBox.shrink();

    if (d.lateral) {
      return Scaffold(
        body: SafeArea(
          child: Row(children: [
            _NavLateral(items: _items, actual: _tab, onTap: _ir, compacto: d.compacto),
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: contenido),
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: Esp.s,
                    child: Center(child: barraDetener)),
              ]),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: contenido),
      bottomNavigationBar: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          barraDetener,
          Padding(
            padding: const EdgeInsets.fromLTRB(Esp.m, 0, Esp.m, Esp.s),
            child: _NavInferior(items: _items, actual: _tab, onTap: _ir),
          ),
        ]),
      ),
    );
  }
}

typedef _Item = (IconData, IconData, String);

class _NavInferior extends StatelessWidget {
  const _NavInferior({required this.items, required this.actual, required this.onTap});
  final List<_Item> items;
  final int actual;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.superficie,
        borderRadius: BorderRadius.circular(28),
        border: c.oscuro ? Border.all(color: c.linea) : null,
        boxShadow: c.oscuro
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 24)],
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: _NavBoton(item: items[i], activo: i == actual, onTap: () => onTap(i)),
          ),
      ]),
    );
  }
}

class _NavLateral extends StatelessWidget {
  const _NavLateral({
    required this.items,
    required this.actual,
    required this.onTap,
    required this.compacto,
  });
  final List<_Item> items;
  final int actual;
  final ValueChanged<int> onTap;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return Container(
      width: compacto ? 84 : 104,
      margin: EdgeInsets.all(compacto ? Esp.s : Esp.l),
      padding: const EdgeInsets.symmetric(vertical: Esp.m, horizontal: 6),
      decoration: BoxDecoration(
        color: c.superficie,
        borderRadius: BorderRadius.circular(28),
        border: c.oscuro ? Border.all(color: c.linea) : null,
      ),
      child: Column(children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _NavBoton(item: items[i], activo: i == actual, onTap: () => onTap(i)),
          ),
      ]),
    );
  }
}

class _NavBoton extends StatelessWidget {
  const _NavBoton({required this.item, required this.activo, required this.onTap});
  final _Item item;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final color = activo ? Theme.of(context).colorScheme.primary : c.texto2;
    return Semantics(
      selected: activo,
      button: true,
      label: item.$3,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: animDur(context, 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: activo ? c.seleccion : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(activo ? item.$2 : item.$1, color: color, size: 24),
            const SizedBox(height: 3),
            Text(item.$3,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
