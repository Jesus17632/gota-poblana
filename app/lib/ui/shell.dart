import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'data_page.dart';
import 'format.dart';
import 'home_page.dart';
import 'settings_page.dart';
import 'widgets/common.dart';

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
    (Icons.home_outlined, Icons.home_rounded, 'Inicio'),
    (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Datos'),
    (Icons.tune_outlined, Icons.tune_rounded, 'Ajustes'),
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

  /// Avisos visuales distintos para inicio / fin / error (duplican los
  /// pitidos del equipo).
  void _mostrarAviso(Aviso a) {
    if (!mounted) return;
    final (Color color, IconData icon) = switch (a.tipo) {
      TipoAviso.inicio => (Palette.dosificando, Icons.play_circle_fill),
      TipoAviso.fin => (Palette.normal, Icons.check_circle),
      TipoAviso.error => (Palette.error, Icons.error),
      TipoAviso.fueraNorma => (Palette.error, Icons.warning_rounded),
      TipoAviso.rechazo => (Palette.error, Icons.block),
      TipoAviso.advertencia => (Palette.precaucion, Icons.warning_amber_rounded),
      TipoAviso.info => (Palette.texto, Icons.info),
    };
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      backgroundColor: color,
      duration: Duration(seconds: a.tipo == TipoAviso.rechazo ? 6 : 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Row(children: [
        Icon(icon, color: Palette.textoSobre(color)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(a.mensaje,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Palette.textoSobre(color))),
        ),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ahora = s.ahora;
    final titulos = [saludo(ahora), 'Datos', 'Ajustes'];
    final pages = const [HomePage(), DataPage(), SettingsPage()];
    final detener = mostrarDetener(s);

    final contenido = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PageHeader(
              titulo: titulos[_tab],
              subtitulo: fechaLarga(ahora),
              iniciales: s.esTecnico ? 'TÉ' : 'CI',
              onAvatar: () => setState(() => _tab = 2),
            ),
            AnimatedSwitcher(
              duration: animDur(context, 250),
              child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
            ),
          ]),
        ),
      ),
    );

    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth >= 900;
      final barraDetener = detener
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: const BarraDetener(),
              ),
            )
          : const SizedBox.shrink();

      if (ancho) {
        return Scaffold(
          body: SafeArea(
            child: Row(children: [
              _NavLateral(
                items: _items,
                actual: _tab,
                onTap: (i) => setState(() => _tab = i),
              ),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(child: contenido),
                  Positioned(
                      left: 0, right: 0, bottom: 12,
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _NavInferior(
                items: _items,
                actual: _tab,
                onTap: (i) => setState(() => _tab = i),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

typedef _Item = (IconData, IconData, String);

class _NavInferior extends StatelessWidget {
  const _NavInferior(
      {required this.items, required this.actual, required this.onTap});
  final List<_Item> items;
  final int actual;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Palette.tarjeta,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: _NavBoton(
              item: items[i],
              activo: i == actual,
              onTap: () => onTap(i),
            ),
          ),
      ]),
    );
  }
}

class _NavLateral extends StatelessWidget {
  const _NavLateral(
      {required this.items, required this.actual, required this.onTap});
  final List<_Item> items;
  final int actual;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Palette.tarjeta,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _NavBoton(
              item: items[i],
              activo: i == actual,
              onTap: () => onTap(i),
            ),
          ),
      ]),
    );
  }
}

class _NavBoton extends StatelessWidget {
  const _NavBoton(
      {required this.item, required this.activo, required this.onTap});
  final _Item item;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = activo ? Palette.normal : Palette.sinDatos;
    return Semantics(
      selected: activo,
      button: true,
      label: item.$3,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: AnimatedContainer(
          duration: animDur(context, 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: activo ? Palette.seleccion : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(activo ? item.$2 : item.$1, color: color, size: 26),
            const SizedBox(height: 4),
            Text(item.$3,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}
