import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';

/// Tarjeta blanca redondeada estilo iOS.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Palette.tarjeta,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // Material transparente: las filas tocables muestran el efecto al tocar.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Text(title!,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Palette.textoSecundario)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 12),
          ],
          child,
        ],
          ),
        ),
      ),
    );
  }
}

/// Punto de color + ícono opcional + texto. El color nunca va solo.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.color,
    required this.text,
    this.icon,
    this.bold = true,
  });

  final Color color;
  final String text;
  final IconData? icon;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null)
        Icon(icon, size: 18, color: _iconColor(color))
      else
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 17,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: Palette.texto, // texto siempre oscuro (contraste)
          ),
        ),
      ),
    ]);
  }

  // Los amarillos no sirven como ícono sobre blanco: se oscurecen.
  static Color _iconColor(Color c) => c.computeLuminance() > 0.6
      ? Color.lerp(c, Colors.black, 0.45)!
      : c;
}

/// Tarjeta de métrica: etiqueta, valor grande y nota opcional.
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
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Palette.textoSecundario),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Palette.textoSecundario)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Palette.texto)),
          if (nota != null) ...[
            const SizedBox(height: 4),
            StatusDot(
                color: notaColor ?? Palette.textoSecundario,
                text: nota!,
                bold: false),
          ],
        ],
      ),
    );
  }
}

/// Encabezado de página como en el diseño: fecha pequeña, título grande, avatar.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.iniciales,
    this.onAvatar,
  });

  final String titulo;
  final String subtitulo;
  final String iniciales;
  final VoidCallback? onAvatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(subtitulo,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Palette.textoSecundario)),
            const SizedBox(height: 2),
            Text(titulo, style: Theme.of(context).textTheme.headlineLarge),
          ]),
        ),
        InkWell(
          onTap: onAvatar,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: Palette.seleccion, shape: BoxShape.circle),
            child: Text(iniciales,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: Palette.normal)),
          ),
        ),
      ]),
    );
  }
}

/// Banda de aviso dentro de una tarjeta (icono + texto).
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: StatusDot._iconColor(color)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Palette.texto))),
      ]),
    );
  }
}
