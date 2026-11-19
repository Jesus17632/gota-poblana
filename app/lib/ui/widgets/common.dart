import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';
import '../tokens.dart';

/// Tarjeta base: superficie redondeada, sombra mínima en claro, ninguna en oscuro.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(Esp.l + 2),
    this.borde,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;
  final Color? borde;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.superficie,
        borderRadius: BorderRadius.circular(Esp.radio),
        border: borde != null
            ? Border.all(color: borde!, width: 1.5)
            : (c.oscuro ? Border.all(color: c.linea) : null),
        boxShadow: c.oscuro
            ? null
            : [BoxShadow(color: c.sombra, blurRadius: 18, offset: const Offset(0, 4))],
      ),
      // Material transparente: las filas tocables muestran el efecto al tocar.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(Esp.radio),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(children: [
                  Expanded(
                    child: Text(title!.toUpperCase(),
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                            color: c.texto2)),
                  ),
                  if (trailing != null) trailing!,
                ]),
                const SizedBox(height: Esp.m),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Punto (o ícono) de color + texto. El color nunca va solo.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.color,
    required this.text,
    this.icon,
    this.bold = true,
    this.size = 16,
  });

  final Color color;
  final String text;
  final IconData? icon;
  final bool bold;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final ic = Palette.legible(color, oscuro: c.oscuro);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null)
        Icon(icon, size: size + 2, color: ic)
      else
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      if (text.isNotEmpty) ...[
        const SizedBox(width: Esp.s),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: c.texto,
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Métrica: etiqueta pequeña, valor grande, nota opcional.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.nota,
    this.notaColor,
    this.icon,
  });

  final String label;
  final String value;
  final String? nota;
  final Color? notaColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return SectionCard(
      padding: const EdgeInsets.all(Esp.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: c.texto2),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c.texto2)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: c.texto)),
        if (nota != null) ...[
          const SizedBox(height: 4),
          StatusDot(
              color: notaColor ?? c.texto2, text: nota!, bold: false, size: 13),
        ],
      ]),
    );
  }
}

/// Encabezado: fecha pequeña, título grande y un chip a la derecha.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.titulo,
    required this.subtitulo,
    this.trailing,
    this.compacto = false,
  });

  final String titulo;
  final String subtitulo;
  final Widget? trailing;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, compacto ? 0 : Esp.s, 2, compacto ? Esp.m : Esp.xl),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(subtitulo,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.texto2)),
            const SizedBox(height: 2),
            Text(titulo, style: compacto ? t.headlineSmall : t.headlineLarge),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Logo de Gota Poblana (circular).
class LogoGota extends StatelessWidget {
  const LogoGota({super.key, this.size = 40, this.borde = 0});
  final double size;
  final double borde;

  static const asset = 'assets/logo_gota.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(borde),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.ag.superficie,
      ),
      child: ClipOval(
        child: Image.asset(asset, fit: BoxFit.cover, width: size, height: size,
            semanticLabel: 'Gota Poblana'),
      ),
    );
  }
}

/// Chip de perfil en el encabezado: foto (logo) + rol. Toca para ir a Ajustes.
class RolChip extends StatelessWidget {
  const RolChip({super.key, required this.tecnico, this.onTap});
  final bool tecnico;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: c.seleccion,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const LogoGota(size: 32),
            const SizedBox(width: 8),
            Text(tecnico ? 'Técnico' : 'Ciudadano',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          ]),
        ),
      ),
    );
  }
}

/// Aviso en una línea (ícono + texto) con fondo suave del color.
class AvisoLinea extends StatelessWidget {
  const AvisoLinea({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: c.oscuro ? 0.16 : 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(icon, size: 19, color: Palette.legible(color, oscuro: c.oscuro)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.texto))),
      ]),
    );
  }
}

/// Separador fino entre filas de una tarjeta.
class Linea extends StatelessWidget {
  const Linea({super.key});
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.ag.linea);
}

/// Acción para [BotonGrid].
class BotonAccion {
  const BotonAccion({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.cargando = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed; // null = deshabilitado
  final Color? color; // p. ej. Palette.error para acciones destructivas
  final bool cargando; // muestra "Enviando…"
}

/// Cuadrícula de botones: todos del MISMO ancho y alto, ícono arriba y
/// texto abajo. Se adapta a 2, 3 o 4 columnas según el ancho.
class BotonGrid extends StatelessWidget {
  const BotonGrid({super.key, required this.botones, this.alto = 84});
  final List<BotonAccion> botones;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final cols = w >= 640 ? 4 : (w >= 420 ? 3 : 2);
      const gap = Esp.s;
      final ancho = (w - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final b in botones)
          SizedBox(width: ancho, height: alto, child: _BotonTile(b: b)),
      ]);
    });
  }
}

class _BotonTile extends StatelessWidget {
  const _BotonTile({required this.b});
  final BotonAccion b;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final activo = b.onPressed != null && !b.cargando;
    final color = b.color ?? Theme.of(context).colorScheme.primary;
    final fg = Palette.legible(color, oscuro: c.oscuro);
    return Opacity(
      opacity: activo || b.cargando ? 1 : 0.45,
      child: Material(
        color: c.superficie2,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: activo ? b.onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Esp.s, vertical: Esp.s),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (b.cargando)
                SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
              else
                Icon(b.icon, size: 24, color: fg),
              const SizedBox(height: 6),
              Text(
                b.cargando ? 'Enviando…' : b.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: c.texto, height: 1.15),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
