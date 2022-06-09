import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:open_bsp/bloc%20/current_path/geometric_calculations_service.dart';

import '../../model/segment2.dart';
import '../../model/segment_offset.dart';

class ConstructingSketcher extends CustomPainter {
  // final List<Segment> lines;
  final List<Segment2> lines2;

  ConstructingSketcher({required this.lines2});

  PictureRecorder pictureRecorder = new PictureRecorder();

  String lastDrawnText = '';

  GeometricCalculationsService _calculationsService =
      new GeometricCalculationsService();

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    if (lines2.isNotEmpty) {
      List<SegmentOffset> path = lines2.first.path;
      for (int i = 0; i < lines2.first.path.length - 1; ++i) {
        canvas.drawLine(path[i].offset, path[i + 1].offset, paint);

        String text =
            '${(path[i].offset - path[i + 1].offset).distance.toStringAsFixed(1)} cm';

        Offset middle =
            _calculationsService.getMiddle(path[i].offset, path[i + 1].offset);
        Offset offset = new Offset(middle.dx - 30, middle.dy - 20);

        drawText(
            canvas, text, offset, Colors.black, Colors.white.withOpacity(0.8));
      }

      lines2.first.path.forEach((o) {
        paint.color = Colors.blue;
        canvas.drawCircle(o.offset, 7, paint);

        String text =
            '${o.offset.dx.toStringAsFixed(1)} / ${o.offset.dy.toStringAsFixed(1)}';

        Offset offset = new Offset(o.offset.dx - 35, o.offset.dy - 30);
        drawText(
            canvas, text, offset, Colors.black, Colors.green.withOpacity(0.4));
      });
    }
  }

  void drawText(Canvas canvas, String text, Offset offset, Color color,
      Color? backgroundColor) {
    TextStyle style = TextStyle(
        color: Colors.black,
        backgroundColor: backgroundColor,
        decorationColor: Colors.green,
        decorationThickness: 0.25);

    TextPainter textPainter = TextPainter(
        text: TextSpan(text: text, style: style),
        // TextSpan could be whole TextSpans tree :)
        textAlign: TextAlign.start,
        //maxLines: 25, // In both TextPainter and Paragraph there is no option to define max height, but there is `maxLines`
        textDirection: TextDirection
            .ltr // It is necessary for some weird reason... IMO should be LTR for default since well-known international languages (english, esperanto) are written left to right.
        )
      ..layout(
          maxWidth:
              500); // TextPainter doesn't need to have specified width (would use infinity if not defined).
    // BTW: using the TextPainter you can check size the text take to be rendered (without `paint`ing it).
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(ConstructingSketcher oldDelegate) {
    return true;
  }
}
