import 'dart:math' as math;

import 'package:flutter/material.dart';

/// رسوم بيانية خفيفة بلا مكتبات خارجية، تعمل في المظهرين.
class ChartColors {
  static const green = Color(0xFF18C894);
  static const amber = Color(0xFFE8A33D);
  static const coral = Color(0xFFE07A5F);
  static const blue = Color(0xFF3B82C4);
  static const slate = Color(0xFF8A8D99);
}

/// تلميح موحّد يظهر عند مرور الماوس (أو الضغط المطوّل في الجوال)
class ChartTip extends StatelessWidget {
  const ChartTip({super.key, required this.message, required this.child});
  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return child;
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 250),
      showDuration: const Duration(seconds: 4),
      preferBelow: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
      decoration: BoxDecoration(color: const Color(0xF02A2A33), borderRadius: BorderRadius.circular(10)),
      child: child,
    );
  }
}

/// منحنى مساحة مع خط هدف اختياري، وتتبّع للماوس يُظهر قيمة كل نقطة
class AreaChart extends StatefulWidget {
  const AreaChart({
    super.key,
    required this.values,
    this.target,
    this.height = 120,
    this.color = ChartColors.green,
    this.gridColor = const Color(0x22888888),
    this.strokeWidth = 3,
    this.semanticLabel,
    this.tooltipBuilder,
  });
  final List<num> values;
  final num? target;
  final double height;
  final Color color;
  final Color gridColor;
  final double strokeWidth;
  final String? semanticLabel;

  /// نص التلميح لكل نقطة (اختياري)
  final String Function(int index)? tooltipBuilder;

  @override
  State<AreaChart> createState() => _AreaChartState();
}

class _AreaChartState extends State<AreaChart> {
  int? _hover;

  void _track(Offset p, double width) {
    final n = widget.values.length;
    if (n == 0 || widget.tooltipBuilder == null) return;
    const pad = 6.0;
    final w = width - pad * 2;
    final int i = n == 1 ? 0 : (((p.dx - pad) / w) * (n - 1)).round().clamp(0, n - 1).toInt();
    if (i != _hover) setState(() => _hover = i);
  }

  void _clear() {
    if (_hover != null) setState(() => _hover = null);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: LayoutBuilder(builder: (context, c) {
          final width = c.maxWidth;
          final chart = CustomPaint(
            size: Size(width, widget.height),
            painter: _AreaPainter(widget.values, widget.target, widget.color, widget.gridColor, widget.strokeWidth, _hover),
          );
          if (widget.tooltipBuilder == null) return chart;
          final n = widget.values.length;
          const pad = 6.0;
          final hx = _hover == null ? 0.0 : pad + (n == 1 ? (width - pad * 2) / 2 : _hover! * (width - pad * 2) / (n - 1));
          const tipW = 170.0;
          return MouseRegion(
            onHover: (e) => _track(e.localPosition, width),
            onExit: (_) => _clear(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (e) => _track(e.localPosition, width),
              onLongPressStart: (e) => _track(e.localPosition, width),
              onLongPressMoveUpdate: (e) => _track(e.localPosition, width),
              onLongPressEnd: (_) => _clear(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  chart,
                  if (_hover != null && _hover! < n)
                    Positioned(
                      left: (hx - tipW / 2).clamp(0.0, (width - tipW) < 0 ? 0.0 : (width - tipW)).toDouble(),
                      top: 0,
                      width: tipW,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xF02A2A33),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
                          ),
                          child: Text(
                            widget.tooltipBuilder!(_hover!),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.45),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter(this.values, this.target, this.color, this.grid, this.stroke, this.hover);
  final int? hover;
  final List<num> values;
  final num? target;
  final Color color;
  final Color grid;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = math.max(values.fold<num>(0, (a, b) => math.max(a, b)), target ?? 0) * 1.15;
    final top = maxV <= 0 ? 1 : maxV;
    const pad = 6.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    // الزمن من اليسار (الأقدم) إلى اليمين (الأحدث) حتى في الواجهة العربية
    Offset pt(int i) => Offset(
          pad + (values.length == 1 ? w / 2 : i * w / (values.length - 1)),
          pad + h * (1 - values[i] / top),
        );
    canvas.drawLine(Offset(0, size.height - pad), Offset(size.width, size.height - pad), Paint()..color = grid);
    if (target != null) {
      final y = pad + h * (1 - target! / top);
      final p = Paint()
        ..color = ChartColors.amber
        ..strokeWidth = 1.6;
      for (double x = 0; x < size.width; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 6, size.width), y), p);
      }
    }
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(pt(values.length - 1).dx, size.height - pad)
      ..lineTo(pt(0).dx, size.height - pad)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final last = pt(values.length - 1);
    canvas.drawCircle(last, stroke + 1.5, Paint()..color = color);
    if (hover != null && hover! < values.length) {
      final h = pt(hover!);
      canvas.drawLine(Offset(h.dx, pad), Offset(h.dx, size.height - pad), Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 1.2);
      canvas.drawCircle(h, stroke + 3.5, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(h, stroke + 1.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) =>
      old.values != values || old.target != target || old.color != color || old.grid != grid || old.hover != hover;
}

/// خط اتجاه صغير داخل بطاقة المؤشر
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.color = ChartColors.green, this.width = 64, this.height = 24});
  final List<num> values;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(painter: _SparkPainter(values, color)),
        ),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color);
  final List<num> v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final mx = v.reduce(math.max), mn = v.reduce(math.min);
    final range = (mx - mn) == 0 ? 1 : (mx - mn);
    final p = Path();
    for (var i = 0; i < v.length; i++) {
      final o = Offset(i * size.width / (v.length - 1), size.height - 2 - (size.height - 4) * (v[i] - mn) / range);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.v != v || old.color != color;
}

/// حلقة (دونات) بأجزاء ملوّنة ونص في المنتصف
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.parts,
    required this.size,
    this.thickness = 16,
    this.center,
    this.trackColor = const Color(0x22888888),
    this.semanticLabel,
    this.tooltip,
  });
  final String? tooltip;
  final List<(num, Color)> parts;
  final double size;
  final double thickness;
  final Widget? center;
  final Color trackColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => ChartTip(
        message: tooltip,
        child: Semantics(
        label: semanticLabel,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(size: Size.square(size), painter: _DonutPainter(parts, thickness, trackColor)),
              if (center != null) center!,
            ],
          ),
        ),
      ),
      );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts, this.t, this.track);
  final List<(num, Color)> parts;
  final double t;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(t / 2, t / 2, size.width - t, size.height - t);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    final total = parts.fold<num>(0, (a, b) => a + b.$1);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final (v, c) in parts) {
      final sweep = math.pi * 2 * v / total;
      if (sweep > 0) canvas.drawArc(rect, start, sweep, false, base..color = c);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.parts != parts || old.track != track;
}

/// شريط واحد مقسّم بالنسب (للتوزيع على الحالات)
class StackedBar extends StatelessWidget {
  const StackedBar({super.key, required this.parts, this.height = 16, this.trackColor = const Color(0x22888888), this.tips});
  final List<(num, Color)> parts;

  /// تلميح لكل جزء (بنفس ترتيب parts)
  final List<String>? tips;
  final double height;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<num>(0, (a, b) => a + b.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: total <= 0
            ? Container(color: trackColor)
            : Row(
                children: [
                  for (var i = 0; i < parts.length; i++)
                    if (parts[i].$1 > 0)
                      Expanded(
                        flex: (parts[i].$1 * 1000 / total).round().clamp(1, 1000000),
                        child: ChartTip(
                          message: tips != null && i < tips!.length ? tips![i] : null,
                          child: Container(color: parts[i].$2),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}

/// شريط أفقي بنسبة من أقصى قيمة
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.ratio, required this.color, this.height = 8, this.trackColor = const Color(0x22888888)});
  final double ratio;
  final Color color;
  final double height;
  final Color trackColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Container(color: trackColor),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: ratio.isNaN ? 0 : ratio.clamp(0, 1).toDouble(),
                child: Container(color: color),
              ),
            ],
          ),
        ),
      );
}

/// أعمدة متجاورة (مثل المفوتر والمحصّل لكل شهر)
class PairedColumns extends StatelessWidget {
  const PairedColumns({
    super.key,
    required this.labels,
    required this.a,
    required this.b,
    required this.colorA,
    required this.colorB,
    this.height = 120,
    this.labelStyle,
    this.tooltipBuilder,
  });
  final String Function(int index)? tooltipBuilder;
  final List<String> labels;
  final List<num> a;
  final List<num> b;
  final Color colorA;
  final Color colorB;
  final double height;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final mx = [...a, ...b].fold<num>(0, (x, y) => math.max(x, y));
    final top = mx <= 0 ? 1 : mx;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: ChartTip(
                message: tooltipBuilder?.call(i),
                child: Column(
                children: [
                  SizedBox(
                    height: height,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _col(b[i] / top, colorB),
                        const SizedBox(width: 3),
                        _col(a[i] / top, colorA),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i], style: labelStyle ?? const TextStyle(fontSize: 10), maxLines: 1),
                ],
              ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _col(num r, Color c) => FractionallySizedBox(
        heightFactor: r.clamp(0.02, 1).toDouble(),
        child: Container(
          width: 12,
          decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        ),
      );
}
