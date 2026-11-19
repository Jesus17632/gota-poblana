// Introducción interactiva (< 50 s): qué es la pecera, qué pH es seguro,
// qué pasa si algo falla y elección de rol. "Omitir" salta a elegir el rol;
// tocar un rol entra a la app.
import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'tokens.dart';
import 'widgets/common.dart';
import 'widgets/ph_escala.dart';
import 'widgets/ph_gauge.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key});

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final _pages = PageController();
  int _i = 0;
  static const _total = 4;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _ir(int i) {
    final dur = animDur(context, 320);
    if (dur == Duration.zero) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i, duration: dur, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final ultima = _i == _total - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Progreso + Omitir
          Padding(
            padding: const EdgeInsets.fromLTRB(Esp.xl, Esp.m, Esp.s, 0),
            child: Row(children: [
              Expanded(
                child: Row(children: [
                  for (var k = 0; k < _total; k++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: animDur(context, 250),
                        height: 4,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: k <= _i ? Theme.of(context).colorScheme.primary : c.linea,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: Esp.s),
              AnimatedOpacity(
                duration: animDur(context, 200),
                opacity: ultima ? 0 : 1,
                child: TextButton(
                  onPressed: ultima ? null : () => _ir(_total - 1),
                  child: const Text('Omitir'),
                ),
              ),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _i = i),
              children: const [
                _PaginaBienvenida(),
                _PaginaEscala(),
                _PaginaFalla(),
                _PaginaRol(),
              ],
            ),
          ),
          if (!ultima)
            Padding(
              padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.l),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _ir(_i + 1),
                    child: const Text('Siguiente'),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Esqueleto de cada página: visual + título + texto. En horizontal, lado a lado.
class _Pagina extends StatelessWidget {
  const _Pagina({required this.visual, required this.titulo, required this.texto, this.extra});
  final Widget visual;
  final String titulo;
  final String texto;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final textos = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: Esp.s),
        Text(texto, style: TextStyle(fontSize: 16, height: 1.4, color: c.texto2)),
        if (extra != null) ...[const SizedBox(height: Esp.l), extra!],
      ],
    );
    return LayoutBuilder(builder: (context, cons) {
      final horizontal = cons.maxWidth > cons.maxHeight && cons.maxWidth >= 560;
      if (horizontal) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Esp.xl),
          child: Row(children: [
            Expanded(child: Center(child: visual)),
            const SizedBox(width: Esp.xl),
            Expanded(child: SingleChildScrollView(child: textos)),
          ]),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Esp.xl, vertical: Esp.l),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              visual,
              const SizedBox(height: Esp.xl),
              textos,
            ]),
          ),
        ),
      );
    });
  }
}

double _tamPecera(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  final horizontal = s.width > s.height;
  return horizontal ? (s.height * 0.5).clamp(140, 260).toDouble() : (s.width * 0.6).clamp(160, 260).toDouble();
}

// 1 ---------------------------------------------------------------------------
class _PaginaBienvenida extends StatelessWidget {
  const _PaginaBienvenida();

  @override
  Widget build(BuildContext context) {
    final t = _tamPecera(context);
    return _Pagina(
      visual: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF2BBBD7).withValues(alpha: 0.35),
                blurRadius: t * 0.25,
                spreadRadius: t * 0.02),
          ],
        ),
        child: LogoGota(size: t),
      ),
      titulo: 'Bienvenido a Gota Poblana',
      texto: 'Vigila el pH del agua en tiempo real y entérate al instante si '
          'algo necesita atención. Son 3 pasos rápidos.',
    );
  }
}

// 2 ---------------------------------------------------------------------------
class _PaginaEscala extends StatefulWidget {
  const _PaginaEscala();

  @override
  State<_PaginaEscala> createState() => _PaginaEscalaState();
}

class _PaginaEscalaState extends State<_PaginaEscala> {
  double _ph = 7.2;

  @override
  Widget build(BuildContext context) {
    final fuera = _ph < 6.5 || _ph > 8.5;
    return _Pagina(
      visual: PhGauge(
        ph: _ph,
        vidrio: fuera ? Palette.error : Palette.normal,
        aguaConColor: true,
        atenuado: false,
        size: _tamPecera(context) * 0.85,
      ),
      titulo: 'La pecera muestra el pH',
      texto: 'Su color cambia con el pH, como el papel indicador. Mueve el '
          'control: entre 6.5 y 8.5 está dentro de la norma; fuera, la app avisa.',
      extra: Column(children: [
        Slider(
          min: 4,
          max: 10,
          divisions: 60,
          value: _ph,
          label: _ph.toStringAsFixed(1),
          onChanged: (v) => setState(() => _ph = v),
        ),
        PhEscala(ph: _ph),
      ]),
    );
  }
}

// 3 ---------------------------------------------------------------------------
class _PaginaFalla extends StatefulWidget {
  const _PaginaFalla();

  @override
  State<_PaginaFalla> createState() => _PaginaFallaState();
}

class _PaginaFallaState extends State<_PaginaFalla> {
  static const _lineas = [
    ('Conexión con el equipo', true),
    ('Sonda de pH', true),
    ('Bomba: desconectada', false),
  ];
  int _visibles = 0;
  bool _corriendo = false;

  Future<void> _probar() async {
    if (_corriendo) return;
    setState(() {
      _corriendo = true;
      _visibles = 0;
    });
    for (var k = 1; k <= _lineas.length; k++) {
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() => _visibles = k);
    }
    if (mounted) setState(() => _corriendo = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return _Pagina(
      visual: PhGauge(
        ph: 7.1,
        vidrio: Palette.error,
        aguaConColor: true,
        atenuado: false,
        error: true,
        accion: 'Toca aquí',
        onTap: _probar,
        size: _tamPecera(context) * 0.85,
      ),
      titulo: 'Si algo falla, te avisa',
      texto: 'Cuando el equipo detecta un problema, la pecera se pone roja. '
          'Tócala y la app revisa todo el hardware. Pruébalo.',
      extra: AnimatedSize(
        duration: animDur(context, 200),
        child: Column(children: [
          for (var k = 0; k < _visibles; k++)
            Padding(
              padding: const EdgeInsets.only(bottom: Esp.s),
              child: Row(children: [
                Container(
                  width: 70,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _lineas[k].$2 ? Palette.normal : Palette.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_lineas[k].$2 ? 'OK' : 'FALLA',
                      style: const TextStyle(
                          color: Palette.blanco,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ),
                const SizedBox(width: Esp.m),
                Text(_lineas[k].$1,
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.texto)),
              ]),
            ),
        ]),
      ),
    );
  }
}

// 4 ---------------------------------------------------------------------------
class _PaginaRol extends StatelessWidget {
  const _PaginaRol();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Esp.xl, vertical: Esp.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('¿Cómo usarás la app?', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Esp.s),
            Text('Puedes cambiarlo cuando quieras en Ajustes.',
                style: TextStyle(fontSize: 16, color: c.texto2)),
            const SizedBox(height: Esp.xl),
            _OpcionRol(
              icono: Icons.person_outline,
              titulo: 'Solo quiero ver',
              texto: 'Estado del agua, escala de pH e historial.',
              onTap: () => s.terminarOnboarding(Rol.ciudadano),
            ),
            const SizedBox(height: Esp.m),
            _OpcionRol(
              icono: Icons.engineering_outlined,
              titulo: 'Soy técnico',
              texto: 'Controlo la bomba, los dispositivos y los diagnósticos.',
              onTap: () => s.terminarOnboarding(Rol.tecnico),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OpcionRol extends StatelessWidget {
  const _OpcionRol({
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.onTap,
  });
  final IconData icono;
  final String titulo;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final p = Theme.of(context).colorScheme.primary;
    return Material(
      color: c.superficie,
      borderRadius: BorderRadius.circular(Esp.radio),
      child: InkWell(
        borderRadius: BorderRadius.circular(Esp.radio),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Esp.l + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Esp.radio),
            border: Border.all(color: c.linea, width: 1.2),
          ),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.seleccion, shape: BoxShape.circle),
              child: Icon(icono, color: p),
            ),
            const SizedBox(width: Esp.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.texto)),
                const SizedBox(height: 2),
                Text(texto, style: TextStyle(fontSize: 14, color: c.texto2)),
              ]),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: c.texto2),
          ]),
        ),
      ),
    );
  }
}
