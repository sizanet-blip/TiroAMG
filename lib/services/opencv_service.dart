import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dartcv4/dartcv.dart' as cv;
import 'package:path_provider/path_provider.dart';

/// Servicio de procesamiento de imágenes usando OpenCV.
/// Proporciona detección de esquinas, transformación de perspectiva
/// y generación de imágenes binarias optimizadas.
class OpenCVService {

  // =========================================================================
  // DETECCIÓN DE ESQUINAS
  // =========================================================================

  /// Detecta las 4 esquinas de un objeto rectangular (diana) en la imagen.
  /// Combina dos métodos para máxima cobertura:
  ///   Método A: HoughLinesP (intersección de líneas - bordes parciales)
  ///   Método B: Contornos + approxPolyDP (bordes completos)
  /// Retorna [TL, TR, BL, BR] en coordenadas de imagen, o null si no detecta.
  static Future<List<Offset>?> detectTargetCorners(File imageFile) async {
    cv.Mat? src, gray, blurred;

    try {
      final bytes = await imageFile.readAsBytes();
      src = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      final int rows = src.rows;
      final int cols = src.cols;
      final int minDim = rows < cols ? rows : cols;

      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      blurred = cv.gaussianBlur(gray, (5, 5), 0);

      // ================================================================
      // MÉTODO A: HoughLinesP (funciona con bordes parciales)
      // ================================================================
      debugPrint('=== Método A: HoughLinesP ===');
      final houghResult = _detectWithHoughLines(blurred, rows, cols, minDim);
      if (houghResult != null) {
        debugPrint('Método A exitoso');
        return houghResult;
      }
      debugPrint('Método A falló, probando Método B...');

      // ================================================================
      // MÉTODO B: Contornos (funciona con bordes completos y buen contraste)
      // ================================================================
      debugPrint('=== Método B: Contornos ===');
      final contourResult = _detectWithContours(blurred, rows, cols);
      if (contourResult != null) {
        debugPrint('Método B exitoso');
        return contourResult;
      }
      debugPrint('Método B también falló');

      return null;
    } catch (e) {
      debugPrint('OpenCV detectTargetCorners error: $e');
      return null;
    } finally {
      src?.dispose();
      gray?.dispose();
      blurred?.dispose();
    }
  }

  /// Método A: Detectar esquinas usando HoughLinesP + intersecciones.
  static List<Offset>? _detectWithHoughLines(
    cv.Mat blurred, int rows, int cols, int minDim,
  ) {
    final allLines = <_HoughLine>[];

    final cannyParams = [
      (50.0, 150.0),
      (30.0, 100.0),
      (80.0, 200.0),
      (20.0, 60.0),
    ];

    for (final (low, high) in cannyParams) {
      if (allLines.length >= 20) break;

      final edges = cv.canny(blurred, low, high);
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      final dilated = cv.dilate(edges, kernel);

      final minLineLen = minDim * 0.12;
      final maxGap = minDim * 0.05;
      final threshold = (minDim * 0.12).round();

      final linesMat = cv.HoughLinesP(
        dilated, 1.0, math.pi / 180.0, threshold,
        minLineLength: minLineLen, maxLineGap: maxGap,
      );

      final reshaped = linesMat.reshape(1);
      for (int i = 0; i < reshaped.rows; i++) {
        final x1 = reshaped.at<int>(i, 0).toDouble();
        final y1 = reshaped.at<int>(i, 1).toDouble();
        final x2 = reshaped.at<int>(i, 2).toDouble();
        final y2 = reshaped.at<int>(i, 3).toDouble();
        final length = math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
        final angle = math.atan2(y2 - y1, x2 - x1);
        allLines.add(_HoughLine(x1, y1, x2, y2, length, angle));
      }

      reshaped.dispose(); linesMat.dispose();
      dilated.dispose(); kernel.dispose(); edges.dispose();
    }

    debugPrint('  Líneas totales: ${allLines.length}');
    if (allLines.length < 4) return null;

    // Clasificar en horizontales y verticales
    final horizontals = <_HoughLine>[];
    final verticals = <_HoughLine>[];

    for (final line in allLines) {
      var a = line.angle;
      while (a < 0) a += math.pi;
      while (a >= math.pi) a -= math.pi;
      final tolerance = math.pi / 6;
      if (a < tolerance || a > (math.pi - tolerance)) {
        horizontals.add(line);
      } else if ((a - math.pi / 2).abs() < tolerance) {
        verticals.add(line);
      }
    }

    debugPrint('  H=${horizontals.length}, V=${verticals.length}');
    if (horizontals.length < 2 || verticals.length < 2) return null;

    final bestH = _selectBestLinePair(horizontals, rows.toDouble(), isHorizontal: true);
    final bestV = _selectBestLinePair(verticals, cols.toDouble(), isHorizontal: false);
    if (bestH == null || bestV == null) return null;

    // Calcular intersecciones
    final corners = <Offset>[];
    for (final h in [bestH.$1, bestH.$2]) {
      for (final v in [bestV.$1, bestV.$2]) {
        final pt = _lineIntersection(h, v);
        if (pt != null) {
          final margin = minDim * 0.05;
          if (pt.dx >= -margin && pt.dx <= cols + margin &&
              pt.dy >= -margin && pt.dy <= rows + margin) {
            corners.add(pt);
          }
        }
      }
    }

    if (corners.length != 4) return null;

    final ordered = _orderCorners(corners);
    final area = _quadArea(ordered);
    final imageArea = rows.toDouble() * cols.toDouble();
    debugPrint('  Área: ${(area / imageArea * 100).toStringAsFixed(1)}%');

    if (area < imageArea * 0.05 || area > imageArea * 0.98) return null;
    return ordered;
  }

  /// Método B: Detectar esquinas usando contornos + approxPolyDP.
  /// Prueba múltiples umbrales Canny y Otsu para cubrir distintos fondos.
  static List<Offset>? _detectWithContours(
    cv.Mat blurred, int rows, int cols,
  ) {
    final imageArea = (rows * cols).toDouble();

    // Probar múltiples estrategias de binarización
    final strategies = <cv.Mat Function()>[
      // Canny estándar
      () => cv.canny(blurred, 50, 150),
      // Canny sensible
      () => cv.canny(blurred, 30, 100),
      // Canny muy sensible
      () => cv.canny(blurred, 20, 60),
      // Otsu invertido (fondo oscuro)
      () => cv.threshold(blurred, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU).$2,
      // Otsu normal (fondo claro)
      () => cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU).$2,
    ];

    for (int s = 0; s < strategies.length; s++) {
      cv.Mat? edges, kernel, dilated;
      cv.VecVec4i? hierarchy;

      try {
        edges = strategies[s]();
        kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
        dilated = cv.dilate(edges, kernel);

        final result = cv.findContours(
          dilated, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE,
        );
        final contours = result.$1;
        hierarchy = result.$2;

        double maxArea = 0;
        cv.VecPoint? bestApprox;

        for (int i = 0; i < contours.length; i++) {
          final contour = contours[i];
          final area = cv.contourArea(contour);

          if (area < imageArea * 0.05) continue;
          if (area > imageArea * 0.98) continue;

          final peri = cv.arcLength(contour, true);
          // Probar varios epsilon para approxPolyDP
          for (final eps in [0.02, 0.03, 0.04, 0.05]) {
            final approx = cv.approxPolyDP(contour, eps * peri, true);
            if (approx.length == 4 && area > maxArea) {
              maxArea = area;
              bestApprox = approx;
            }
          }
        }

        if (bestApprox != null) {
          final points = <Offset>[];
          for (int i = 0; i < bestApprox.length; i++) {
            final pt = bestApprox[i];
            points.add(Offset(pt.x.toDouble(), pt.y.toDouble()));
          }
          debugPrint('  Estrategia $s: encontrado (área=${(maxArea / imageArea * 100).toStringAsFixed(1)}%)');
          return _orderCorners(points);
        }
      } catch (e) {
        debugPrint('  Estrategia $s error: $e');
      } finally {
        edges?.dispose();
        kernel?.dispose();
        dilated?.dispose();
        hierarchy?.dispose();
      }
    }

    return null;
  }

  /// Selecciona el mejor par de líneas separadas (arriba/abajo o izq/der).
  /// Agrupa líneas cercanas y devuelve las 2 más separadas y fuertes.
  static (_HoughLine, _HoughLine)? _selectBestLinePair(
    List<_HoughLine> lines,
    double maxCoord, {
    required bool isHorizontal,
  }) {
    // Ordenar por posición: Y medio para horizontales, X medio para verticales
    final sorted = List<_HoughLine>.from(lines);
    sorted.sort((a, b) {
      final posA = isHorizontal ? (a.y1 + a.y2) / 2 : (a.x1 + a.x2) / 2;
      final posB = isHorizontal ? (b.y1 + b.y2) / 2 : (b.x1 + b.x2) / 2;
      return posA.compareTo(posB);
    });

    // Agrupar líneas cercanas (distancia < 5% de la dimensión)
    final groupThreshold = maxCoord * 0.05;
    final groups = <List<_HoughLine>>[];
    List<_HoughLine> currentGroup = [sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final prevPos = isHorizontal
          ? (currentGroup.last.y1 + currentGroup.last.y2) / 2
          : (currentGroup.last.x1 + currentGroup.last.x2) / 2;
      final currPos = isHorizontal
          ? (sorted[i].y1 + sorted[i].y2) / 2
          : (sorted[i].x1 + sorted[i].x2) / 2;

      if ((currPos - prevPos).abs() < groupThreshold) {
        currentGroup.add(sorted[i]);
      } else {
        groups.add(currentGroup);
        currentGroup = [sorted[i]];
      }
    }
    groups.add(currentGroup);

    if (groups.length < 2) return null;

    // De cada grupo, seleccionar la línea más larga como representante
    final representatives = groups.map((group) {
      group.sort((a, b) => b.length.compareTo(a.length));
      return group.first;
    }).toList();

    // Seleccionar los 2 grupos más separados
    double maxSep = 0;
    int bestI = 0, bestJ = 1;

    for (int i = 0; i < representatives.length; i++) {
      for (int j = i + 1; j < representatives.length; j++) {
        final posI = isHorizontal
            ? (representatives[i].y1 + representatives[i].y2) / 2
            : (representatives[i].x1 + representatives[i].x2) / 2;
        final posJ = isHorizontal
            ? (representatives[j].y1 + representatives[j].y2) / 2
            : (representatives[j].x1 + representatives[j].x2) / 2;
        final sep = (posJ - posI).abs();
        if (sep > maxSep) {
          maxSep = sep;
          bestI = i;
          bestJ = j;
        }
      }
    }

    // Verificar separación mínima (al menos 10% de la dimensión)
    if (maxSep < maxCoord * 0.10) return null;

    return (representatives[bestI], representatives[bestJ]);
  }

  /// Calcula la intersección de dos líneas definidas por segmentos.
  /// Usa las líneas extendidas (no solo el segmento).
  static Offset? _lineIntersection(_HoughLine l1, _HoughLine l2) {
    final x1 = l1.x1, y1 = l1.y1, x2 = l1.x2, y2 = l1.y2;
    final x3 = l2.x1, y3 = l2.y1, x4 = l2.x2, y4 = l2.y2;

    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-10) return null; // Líneas paralelas

    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;

    return Offset(
      x1 + t * (x2 - x1),
      y1 + t * (y2 - y1),
    );
  }

  /// Calcula el área de un cuadrilátero dado por [TL, TR, BL, BR].
  static double _quadArea(List<Offset> corners) {
    // Shoelace formula para el cuadrilátero TL→TR→BR→BL
    final pts = [corners[0], corners[1], corners[3], corners[2]]; // TL→TR→BR→BL
    double area = 0;
    for (int i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      area += pts[i].dx * pts[j].dy;
      area -= pts[j].dx * pts[i].dy;
    }
    return area.abs() / 2;
  }

  // =========================================================================
  // TRANSFORMACIÓN DE PERSPECTIVA (RECORTE)
  // =========================================================================

  /// Recorta la imagen con corrección de perspectiva usando OpenCV.
  /// [corners] debe contener [TL, TR, BL, BR] en coordenadas de imagen.
  /// Mucho más preciso y rápido que la interpolación bilineal manual.
  static Future<File?> cropWithPerspective(
    Uint8List imageBytes,
    List<Offset> corners,
    int outputWidth,
    int outputHeight,
  ) async {
    cv.Mat? src, transformMatrix, warped;

    try {
      src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      // Puntos origen (cuadrilátero en la imagen original)
      final srcPoints = cv.VecPoint.fromList([
        cv.Point(corners[0].dx.round(), corners[0].dy.round()), // TL
        cv.Point(corners[1].dx.round(), corners[1].dy.round()), // TR
        cv.Point(corners[2].dx.round(), corners[2].dy.round()), // BL
        cv.Point(corners[3].dx.round(), corners[3].dy.round()), // BR
      ]);

      // Puntos destino (rectángulo de salida)
      final dstPoints = cv.VecPoint.fromList([
        cv.Point(0, 0),                      // TL
        cv.Point(outputWidth, 0),             // TR
        cv.Point(0, outputHeight),            // BL
        cv.Point(outputWidth, outputHeight),  // BR
      ]);

      // Calcular matriz de transformación de perspectiva
      transformMatrix = cv.getPerspectiveTransform(srcPoints, dstPoints);

      // Aplicar la transformación
      warped = cv.warpPerspective(
        src, transformMatrix, (outputWidth, outputHeight),
      );

      // Codificar como JPEG
      final (success, encoded) = cv.imencode('.jpg', warped);
      if (!success) {
        throw Exception('Error al codificar la imagen recortada');
      }

      // Guardar resultado
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/cropped_diana_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(encoded);

      return File(path);
    } catch (e) {
      debugPrint('OpenCV cropWithPerspective error: $e');
      return null;
    } finally {
      src?.dispose();
      transformMatrix?.dispose();
      warped?.dispose();
    }
  }

  // =========================================================================
  // CORRECCIÓN DE DIANA DOBLADA (2 mitades)
  // =========================================================================

  /// Corrige una diana doblada dividiéndola en dos mitades y aplicando
  /// warpPerspective a cada una por separado, luego las une.
  ///
  /// [corners] = [TL, TR, BL, BR] — 4 esquinas externas
  /// [foldTop] y [foldBottom] — puntos superior e inferior de la línea de pliegue
  /// El resultado es una imagen plana donde ambas mitades están corregidas.
  static Future<File?> cropWithFoldCorrection(
    Uint8List imageBytes,
    List<Offset> corners,
    Offset foldTop,
    Offset foldBottom,
    int outputWidth,
    int outputHeight,
  ) async {
    cv.Mat? src, result;
    cv.Mat? tmLeft, tmRight, warpedLeft, warpedRight;

    try {
      src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      final tl = corners[0];
      final tr = corners[1];
      final bl = corners[2];
      final br = corners[3];

      // Mitad izquierda: TL, foldTop, BL, foldBottom → rectángulo izquierdo
      // Mitad derecha: foldTop, TR, foldBottom, BR → rectángulo derecho

      // Calcular ancho proporcional de cada mitad
      // Usar la distancia horizontal media del pliegue a cada lado
      final double leftWidthTop = (foldTop - tl).distance;
      final double leftWidthBottom = (foldBottom - bl).distance;
      final double rightWidthTop = (tr - foldTop).distance;
      final double rightWidthBottom = (br - foldBottom).distance;

      final double avgLeftWidth = (leftWidthTop + leftWidthBottom) / 2;
      final double avgRightWidth = (rightWidthTop + rightWidthBottom) / 2;
      final double totalWidth = avgLeftWidth + avgRightWidth;

      // Ancho proporcional en píxeles de salida
      final int leftOutW = (outputWidth * avgLeftWidth / totalWidth).round();
      final int rightOutW = outputWidth - leftOutW;

      // --- Mitad IZQUIERDA ---
      final srcLeft = cv.VecPoint.fromList([
        cv.Point(tl.dx.round(), tl.dy.round()),       // TL
        cv.Point(foldTop.dx.round(), foldTop.dy.round()),   // TR (pliegue arriba)
        cv.Point(bl.dx.round(), bl.dy.round()),       // BL
        cv.Point(foldBottom.dx.round(), foldBottom.dy.round()), // BR (pliegue abajo)
      ]);

      final dstLeft = cv.VecPoint.fromList([
        cv.Point(0, 0),
        cv.Point(leftOutW, 0),
        cv.Point(0, outputHeight),
        cv.Point(leftOutW, outputHeight),
      ]);

      tmLeft = cv.getPerspectiveTransform(srcLeft, dstLeft);
      warpedLeft = cv.warpPerspective(
        src, tmLeft, (leftOutW, outputHeight),
      );

      // --- Mitad DERECHA ---
      final srcRight = cv.VecPoint.fromList([
        cv.Point(foldTop.dx.round(), foldTop.dy.round()),   // TL (pliegue arriba)
        cv.Point(tr.dx.round(), tr.dy.round()),       // TR
        cv.Point(foldBottom.dx.round(), foldBottom.dy.round()), // BL (pliegue abajo)
        cv.Point(br.dx.round(), br.dy.round()),       // BR
      ]);

      final dstRight = cv.VecPoint.fromList([
        cv.Point(0, 0),
        cv.Point(rightOutW, 0),
        cv.Point(0, outputHeight),
        cv.Point(rightOutW, outputHeight),
      ]);

      tmRight = cv.getPerspectiveTransform(srcRight, dstRight);
      warpedRight = cv.warpPerspective(
        src, tmRight, (rightOutW, outputHeight),
      );

      // --- Unir las dos mitades horizontalmente ---
      debugPrint('Fold correction: left=${leftOutW}x$outputHeight, right=${rightOutW}x$outputHeight, total=${outputWidth}x$outputHeight');
      result = cv.hconcat(warpedLeft, warpedRight);

      // Codificar
      final (success, encoded) = cv.imencode('.jpg', result);
      if (!success) {
        throw Exception('Error al codificar la imagen corregida');
      }

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/fold_corrected_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(encoded);

      return File(path);
    } catch (e) {
      debugPrint('OpenCV cropWithFoldCorrection error: $e');
      return null;
    } finally {
      src?.dispose();
      tmLeft?.dispose();
      tmRight?.dispose();
      warpedLeft?.dispose();
      warpedRight?.dispose();
      result?.dispose();
    }
  }

  // =========================================================================
  // DETECCIÓN DEL CENTRO DE LA DIANA
  // =========================================================================

  /// Detecta el centro de la diana y genera anillos con espaciado ISSF.
  ///
  /// Estrategia híbrida (Opción 3):
  ///  1. Encontrar el centro usando la zona más oscura (bull/X)
  ///  2. Detectar 2-3 anillos fiables del perfil radial para CALIBRAR
  ///  3. Calcular el espaciado uniforme ISSF a partir de esos anillos
  ///  4. GENERAR todos los anillos matemáticamente con ese espaciado
  ///  5. Refinar cada anillo con detección per-ángulo (forma real)
  ///
  /// Retorna {center, circles, ringContours, spacing, message} o null.
  static Future<Map<String, dynamic>?> detectTargetCenter(
    Uint8List imageBytes,
  ) async {
    cv.Mat? src, gray, blurred, binary, morphKernel, cleaned;

    try {
      src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      blurred = cv.gaussianBlur(gray, (5, 5), 0);

      final int rows = src.rows;
      final int cols = src.cols;
      final int minDim = rows < cols ? rows : cols;

      // ================================================================
      // FASE 1: Encontrar el centro de la diana
      // ================================================================
      binary = cv.threshold(blurred, 80, 255, cv.THRESH_BINARY_INV).$2;
      morphKernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (15, 15));
      cleaned = cv.morphologyEx(binary, cv.MORPH_CLOSE, morphKernel);

      final contResult = cv.findContours(
        cleaned, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE,
      );
      final contours = contResult.$1;
      final hierarchy = contResult.$2;

      double maxArea = 0;
      int bestIdx = -1;
      for (int i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        if (area > maxArea) {
          maxArea = area;
          bestIdx = i;
        }
      }

      double centerX, centerY;

      if (bestIdx >= 0 && maxArea > (rows * cols * 0.01)) {
        final contour = contours[bestIdx];
        double sumX = 0, sumY = 0;
        for (int i = 0; i < contour.length; i++) {
          sumX += contour[i].x;
          sumY += contour[i].y;
        }
        centerX = sumX / contour.length;
        centerY = sumY / contour.length;
      } else {
        centerX = cols / 2.0;
        centerY = rows / 2.0;
      }

      hierarchy.dispose();
      debugPrint('Centro detectado: (${centerX.toStringAsFixed(1)}, ${centerY.toStringAsFixed(1)})');

      // ================================================================
      // FASE 2: Perfil radial para CALIBRACIÓN (no para todos los anillos)
      // ================================================================
      final maxRadius = (minDim * 0.48).round();
      final numAngles = 360;

      // 2a. Perfil radial promedio (media de todos los ángulos)
      final avgProfile = List<double>.filled(maxRadius, 0);
      final profileCount = List<int>.filled(maxRadius, 0);

      for (int angle = 0; angle < numAngles; angle++) {
        final rad = angle * math.pi / 180.0;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);

        for (int r = 1; r < maxRadius; r++) {
          final px = (centerX + r * cosA).round();
          final py = (centerY + r * sinA).round();

          if (px >= 0 && px < cols && py >= 0 && py < rows) {
            avgProfile[r] += gray.at<int>(py, px).toDouble();
            profileCount[r]++;
          }
        }
      }
      for (int r = 0; r < maxRadius; r++) {
        if (profileCount[r] > 0) avgProfile[r] /= profileCount[r];
      }

      // 2b. Suavizar y derivar
      final smoothed = List<double>.filled(maxRadius, 0);
      const smoothW = 5;
      for (int r = smoothW; r < maxRadius - smoothW; r++) {
        double s = 0;
        for (int w = -smoothW; w <= smoothW; w++) {
          s += avgProfile[r + w];
        }
        smoothed[r] = s / (2 * smoothW + 1);
      }

      final derivative = List<double>.filled(maxRadius, 0);
      for (int r = 1; r < maxRadius - 1; r++) {
        derivative[r] = smoothed[r + 1] - smoothed[r - 1];
      }

      // 2c. Detectar transiciones (solo para calibración)
      final detectedRadii = <double>[];
      final minPeakHeight = 5.0;
      final minRingGap = minDim * 0.02;

      for (int r = (minDim * 0.01).round(); r < maxRadius - 2; r++) {
        final absD = derivative[r].abs();
        if (absD > minPeakHeight &&
            absD >= derivative[r - 1].abs() &&
            absD >= derivative[r + 1].abs()) {
          if (detectedRadii.isEmpty || (r - detectedRadii.last) > minRingGap) {
            detectedRadii.add(r.toDouble());
          }
        }
      }

      debugPrint('Transiciones detectadas para calibración: ${detectedRadii.length} '
          '→ ${detectedRadii.map((r) => r.toStringAsFixed(0)).join(', ')}');

      // ================================================================
      // FASE 3: Calcular espaciado ISSF uniforme
      // ================================================================
      // Necesitamos al menos 1 transición para poder estimar el espaciado.
      if (detectedRadii.isEmpty) {
        return {
          'center': Offset(centerX, centerY),
          'circles': <Map<String, double>>[],
          'ringContours': <List<Map<String, dynamic>>>[],
          'message': 'Sin transiciones detectadas',
        };
      }

      double spacing;
      double referenceRadius;

      if (detectedRadii.length >= 3) {
        // Caso ideal: suficientes transiciones para calibrar con zona fiable
        final reliableStart = 1; // Saltar el primero
        final reliableEnd = detectedRadii.length - 1; // Excluir el último
        final spacings = <double>[];
        for (int i = reliableStart + 1; i <= reliableEnd; i++) {
          spacings.add(detectedRadii[i] - detectedRadii[i - 1]);
        }
        if (spacings.isEmpty) {
          for (int i = 1; i < detectedRadii.length; i++) {
            spacings.add(detectedRadii[i] - detectedRadii[i - 1]);
          }
        }
        spacings.sort();
        spacing = spacings[spacings.length ~/ 2]; // Mediana
        referenceRadius = detectedRadii[reliableStart];
      } else if (detectedRadii.length == 2) {
        // 2 transiciones: usar directamente su diferencia como espaciado
        spacing = (detectedRadii[1] - detectedRadii[0]).abs();
        referenceRadius = detectedRadii[0];
        debugPrint('Fallback 2 transiciones: spacing=${spacing.toStringAsFixed(1)}');
      } else {
        // 1 sola transición: estimar que es ~anillo 5 de 10 y usar maxRadius/10
        spacing = maxRadius / 10.0;
        referenceRadius = detectedRadii[0];
        debugPrint('Fallback 1 transición: spacing estimado=${spacing.toStringAsFixed(1)}');
      }

      // Validar spacing mínimo (solo para valores absurdos: <= 0)
      if (spacing <= 1.0) {
        spacing = maxRadius / 10.0;
        debugPrint('Spacing inválido, usando fallback: ${spacing.toStringAsFixed(1)}');
      }
      debugPrint('Espaciado ISSF calculado: ${spacing.toStringAsFixed(1)} px');
      debugPrint('Radio de referencia: ${referenceRadius.toStringAsFixed(1)}');

      // ================================================================
      // FASE 4: Generar TODOS los anillos matemáticamente
      // ================================================================
      // Desde el centro hacia fuera, generamos anillos con espaciado uniforme.
      // Empezamos desde el radio de referencia y vamos en ambas direcciones.
      final generatedRadii = <double>[];

      // Hacia el interior (desde referencia hacia el centro)
      // Aceptar anillos con radio > spacing * 0.2 para incluir la "mouche"
      double r = referenceRadius;
      while (r > spacing * 0.2) {
        generatedRadii.add(r);
        r -= spacing;
      }

      // Hacia el exterior (desde referencia + spacing hacia fuera)
      r = referenceRadius + spacing;
      while (r < maxRadius * 0.98) {
        generatedRadii.add(r);
        r += spacing;
      }

      // Ordenar de menor a mayor
      generatedRadii.sort();

      debugPrint('Anillos generados ISSF: ${generatedRadii.length} '
          '→ ${generatedRadii.map((r) => r.toStringAsFixed(0)).join(', ')}');

      // ================================================================
      // FASE 5: Refinar cada anillo con detección per-ángulo (forma real)
      // ================================================================
      final searchWindow = (spacing * 0.3).round().clamp(3, 20);
      const angleStep = 2;
      final numSamples = numAngles ~/ angleStep; // 180 puntos por anillo

      // Construir brillo per-ángulo (necesario para el refinamiento)
      final perAngleBrightness = List.generate(
        numAngles,
        (_) => List<double>.filled(maxRadius, 0),
      );
      for (int angle = 0; angle < numAngles; angle++) {
        final rad = angle * math.pi / 180.0;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);
        for (int r = 1; r < maxRadius; r++) {
          final px = (centerX + r * cosA).round();
          final py = (centerY + r * sinA).round();
          if (px >= 0 && px < cols && py >= 0 && py < rows) {
            perAngleBrightness[angle][r] = gray.at<int>(py, px).toDouble();
          }
        }
      }

      final ringContours = <List<Offset>>[];
      final ringAvgRadii = <double>[];

      for (final genR in generatedRadii) {
        // 5a. Detectar radio a cada ángulo buscando transición cercana
        final rawRadii = List<double>.filled(numSamples, genR);

        for (int idx = 0; idx < numSamples; idx++) {
          final angle = idx * angleStep;
          final bright = perAngleBrightness[angle];

          // Suavizar brillo local
          final smoothBright = List<double>.filled(maxRadius, 0);
          for (int r2 = 3; r2 < maxRadius - 3; r2++) {
            smoothBright[r2] = (bright[r2 - 3] + bright[r2 - 2] + bright[r2 - 1] +
                bright[r2] + bright[r2 + 1] + bright[r2 + 2] + bright[r2 + 3]) / 7.0;
          }

          // Buscar transición más cercana al radio generado
          final rMin = (genR - searchWindow).round().clamp(4, maxRadius - 4);
          final rMax = (genR + searchWindow).round().clamp(4, maxRadius - 4);

          int bestR = genR.round();
          double bestDist = double.infinity;

          for (int offset = 0; offset <= searchWindow; offset++) {
            for (final sign in [0, 1, -1]) {
              if (offset == 0 && sign != 0) continue;
              if (offset > 0 && sign == 0) continue;

              final r2 = genR.round() + (offset * (sign == 0 ? 1 : sign));
              if (r2 < rMin || r2 > rMax || r2 < 2 || r2 >= maxRadius - 2) continue;

              final localDeriv = (smoothBright[r2 + 1] - smoothBright[r2 - 1]).abs();
              if (localDeriv >= 3.0) {
                final dist = (r2 - genR).abs();
                if (dist < bestDist) {
                  bestDist = dist;
                  bestR = r2;
                }
              }
            }
            if (bestDist < double.infinity) break;
          }
          rawRadii[idx] = bestR.toDouble();
        }

        // 5b. Mediana + clamp + suavizado
        final medianRadii = _medianFilter(rawRadii, 15);

        final sortedForMedian = List<double>.from(medianRadii)..sort();
        final ringMedianR = sortedForMedian[sortedForMedian.length ~/ 2];
        // Desviación máxima basada en el ESPACIADO (no en el radio).
        // Así todos los anillos tienen el mismo margen absoluto,
        // evitando que los exteriores se separen más.
        final maxDev = spacing * 0.08; // Máx 8% del espaciado entre anillos

        final clamped = List<double>.filled(numSamples, 0);
        for (int i = 0; i < numSamples; i++) {
          clamped[i] = medianRadii[i].clamp(ringMedianR - maxDev, ringMedianR + maxDev);
        }

        final smoothRadii = _circularSmooth(clamped, 7);

        // 5c. Construir contorno
        final contourPoints = <Offset>[];
        double radiusSum = 0;
        for (int idx = 0; idx < numSamples; idx++) {
          final angle = idx * angleStep;
          final rad = angle * math.pi / 180.0;
          final r2 = smoothRadii[idx];
          contourPoints.add(Offset(
            centerX + r2 * math.cos(rad),
            centerY + r2 * math.sin(rad),
          ));
          radiusSum += r2;
        }

        if (contourPoints.isNotEmpty) {
          ringContours.add(contourPoints);
          ringAvgRadii.add(radiusSum / numSamples);
        }
      }

      debugPrint('Anillos con contorno real: ${ringContours.length}');
      for (int i = 0; i < ringAvgRadii.length; i++) {
        debugPrint('  Anillo ${i + 1}: radio = ${ringAvgRadii[i].toStringAsFixed(1)} px');
      }

      // Construir datos de retorno
      final detectedCircles = <Map<String, double>>[];
      for (final r in ringAvgRadii) {
        detectedCircles.add({'x': centerX, 'y': centerY, 'r': r});
      }

      final ringContoursAsListOfMaps = ringContours.map((contour) {
        return contour.map((p) => {'x': p.dx, 'y': p.dy}).toList();
      }).toList();

      return {
        'center': Offset(centerX, centerY),
        'circles': detectedCircles,
        'ringContours': ringContoursAsListOfMaps,
        'spacing': spacing,
        'message': '${ringContours.length} anillos (ISSF, esp=${spacing.toStringAsFixed(1)}px)',
      };
    } catch (e) {
      debugPrint('OpenCV detectTargetCenter error: $e');
      return {
        'center': null,
        'circles': <Map<String, double>>[],
        'message': 'Error: $e',
      };
    } finally {
      src?.dispose();
      gray?.dispose();
      blurred?.dispose();
      binary?.dispose();
      morphKernel?.dispose();
      cleaned?.dispose();
    }
  }

  // =========================================================================
  // DETECCIÓN DE IMPACTOS (AGUJEROS DE BALA)
  // =========================================================================

  /// Detecta impactos (agujeros) en la imagen recortada de la diana.
  ///
  /// Parámetros de prueba hardcoded para diana 10m aire comprimido:
  ///   spacingMm = 8.0 mm (espaciado entre anillos ISSF 10m)
  ///   caliberMm = 4.5 mm (perdigón)
  ///
  /// [imageBytes]: imagen recortada de la diana
  /// [center]: centro de la diana (en coordenadas de imagen)
  /// [ringRadii]: radios de los anillos detectados (ordenados menor→mayor)
  /// [spacingPx]: espaciado entre anillos en píxeles (del detectTargetCenter)
  ///
  /// Retorna lista de impactos: [{x, y, radius}]
  static Future<Map<String, dynamic>> detectImpacts(
    Uint8List imageBytes, {
    required Offset center,
    required List<double> ringRadii,
    required double spacingPx,
    double spacingMm = 8.0,   // Diana 10m aire comprimido ISSF
    double caliberMm = 4.5,   // Perdigón
  }) async {
    cv.Mat? src, gray, blurred, morphK;

    try {
      src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (src.isEmpty) {
        return {'impacts': <Map<String, double>>[], 'message': 'Error al cargar imagen'};
      }

      final int rows = src.rows;
      final int cols = src.cols;

      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      blurred = cv.medianBlur(gray, 5);

      // ================================================================
      // Calcular escala y tamaño esperado del agujero
      // ================================================================
      final double scale = spacingMm / spacingPx; // mm por pixel
      final double holeRadiusPx = (caliberMm / 2.0) / scale;
      final double holeAreaExpected = math.pi * holeRadiusPx * holeRadiusPx;

      // Rango de área:
      //   Individual: 0.3x - 1.5x del área esperada
      //   Grupo (solapados): 1.5x - 7.0x (hasta ~7 impactos agrupados)
      final double minArea = holeAreaExpected * 0.3;
      final double maxAreaSingle = holeAreaExpected * 1.5;
      final double maxAreaGroup = holeAreaExpected * 7.0;

      debugPrint('Escala: ${scale.toStringAsFixed(4)} mm/px');
      debugPrint('Radio esperado agujero: ${holeRadiusPx.toStringAsFixed(1)} px');
      debugPrint('Área esperada: ${holeAreaExpected.toStringAsFixed(0)} px² '
          '(individual: ${minArea.toStringAsFixed(0)} - ${maxAreaSingle.toStringAsFixed(0)}, '
          'grupo: hasta ${maxAreaGroup.toStringAsFixed(0)})');

      // ================================================================
      // DOBLE UMBRALIZACIÓN:
      // Pass 0: Adaptativo estándar (impactos en zona clara)
      // Pass 1: Adaptativo con blockSize grande (impactos en zona oscura)
      // ================================================================
      final impacts = <Map<String, double>>[];
      final foundPositions = <List<double>>[]; // Para evitar duplicados

      final maxDianaRadius = ringRadii.isNotEmpty
          ? ringRadii.last + spacingPx
          : (rows < cols ? rows : cols) * 0.48;

      morphK = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));

      // Configuración de las dos pasadas
      final passConfigs = [
        {'name': 'Estándar', 'blockSize': 21, 'C': 10.0},
        {'name': 'Amplio', 'blockSize': 51, 'C': 12.0},  // blockSize grande para zonas oscuras
      ];

      // Almacenar candidatos cercanos para debug
      final nearMisses = <Map<String, dynamic>>[];

      for (int pass = 0; pass < passConfigs.length; pass++) {
        final config = passConfigs[pass];
        final passName = config['name'] as String;
        final blockSize = config['blockSize'] as int;
        final cValue = config['C'] as double;

        cv.Mat? passThresh, passCleaned;
        try {
          passThresh = cv.adaptiveThreshold(
            blurred, 255.0,
            cv.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv.THRESH_BINARY_INV,
            blockSize,
            cValue,
          );

          passCleaned = cv.morphologyEx(passThresh, cv.MORPH_CLOSE, morphK);

          final contResult = cv.findContours(
            passCleaned, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE,
          );
          final contours = contResult.$1;
          final hierarchy = contResult.$2;

          debugPrint('Pass $pass ($passName, block=$blockSize, C=$cValue): '
              '${contours.length} contornos');

          int rejected_area = 0, rejected_pos = 0;
          int rejected_circ = 0, rejected_border = 0, rejected_dup = 0;

          for (int i = 0; i < contours.length; i++) {
            final contour = contours[i];
            final area = cv.contourArea(contour);

            // Filtro 1: Tamaño
            if (area < minArea || area > maxAreaGroup) {
              // Contornos "casi" válidos para debug
              if (area >= minArea * 0.3 && area <= maxAreaGroup * 2.0) {
                rejected_area++;
              }
              continue;
            }

            // Centroide
            double sumX = 0, sumY = 0;
            for (int j = 0; j < contour.length; j++) {
              sumX += contour[j].x;
              sumY += contour[j].y;
            }
            final cx = sumX / contour.length;
            final cy = sumY / contour.length;

            // Filtro 2: Dentro de la diana
            final distToCenter = _distance(cx, cy, center.dx, center.dy);
            if (distToCenter > maxDianaRadius) {
              rejected_pos++;
              continue;
            }

            // Filtro 3: Circularidad
            final perimeter = cv.arcLength(contour, true);
            if (perimeter <= 0) continue;
            final circularity = (4.0 * math.pi * area) / (perimeter * perimeter);

            final isGroup = area > maxAreaSingle;
            // Circularidad más permisiva (0.2) porque el filtro de contraste
            // se encarga de rechazar números/texto (que son poco circulares Y
            // bajo contraste). Esto permite impactos cerca de líneas de anillo
            // que deforman ligeramente el contorno.
            if (!isGroup && circularity < 0.2) {
              rejected_circ++;
              if (circularity >= 0.10 && nearMisses.length < 5) {
                nearMisses.add({
                  'pass': passName,
                  'reason': 'circ',
                  'x': cx, 'y': cy,
                  'area': area,
                  'circ': circularity,
                  'dist': distToCenter,
                });
              }
              continue;
            }
            if (isGroup && circularity < 0.10) {
              rejected_circ++;
              continue;
            }

            // Filtro 4: Borde imagen
            if (cx < 5 || cx > cols - 5 || cy < 5 || cy > rows - 5) {
              rejected_border++;
              continue;
            }

            // Filtro 4b: Contraste local (distinguir agujeros reales de números impresos)
            // Un agujero real tiene mucho más contraste con su entorno que un número.
            // Medimos la diferencia entre el brillo del contorno y su anillo circundante.
            if (!isGroup) {
              final intR = math.sqrt(area / math.pi).round().clamp(2, 50);
              final outerR = (intR * 2.5).round();
              int innerSum = 0, innerCount = 0;
              int outerSum = 0, outerCount = 0;
              final cxi = cx.round(), cyi = cy.round();
              for (int dy = -outerR; dy <= outerR; dy++) {
                for (int dx = -outerR; dx <= outerR; dx++) {
                  final px = cxi + dx, py = cyi + dy;
                  if (px < 0 || px >= cols || py < 0 || py >= rows) continue;
                  final dist = math.sqrt(dx * dx + dy * dy);
                  if (dist <= intR) {
                    innerSum += blurred.at<int>(py, px);
                    innerCount++;
                  } else if (dist <= outerR && dist > intR * 1.5) {
                    outerSum += blurred.at<int>(py, px);
                    outerCount++;
                  }
                }
              }
              if (innerCount > 0 && outerCount > 0) {
                final innerAvg = innerSum / innerCount;
                final outerAvg = outerSum / outerCount;
                final contrast = (outerAvg - innerAvg).abs();
                // Números impresos tienen contraste bajo (~10-25),
                // agujeros reales tienen contraste alto (>30)
                if (contrast < 25) {
                  debugPrint('  [$passName] Rechazado por contraste bajo: '
                      '(${cx.toStringAsFixed(0)}, ${cy.toStringAsFixed(0)}) '
                      'contraste=$contrast inner=${innerAvg.toStringAsFixed(0)} '
                      'outer=${outerAvg.toStringAsFixed(0)}');
                  continue;
                }
              }
            }

            // Filtro 5: No duplicar
            bool isDuplicate = false;
            for (final pos in foundPositions) {
              if (_distance(cx, cy, pos[0], pos[1]) < holeRadiusPx * 2) {
                isDuplicate = true;
                break;
              }
            }
            if (isDuplicate) {
              rejected_dup++;
              debugPrint('  [$passName] Duplicado rechazado: '
                  '(${cx.toStringAsFixed(0)}, ${cy.toStringAsFixed(0)}) '
                  'area=${area.toStringAsFixed(0)} circ=${circularity.toStringAsFixed(2)}');
              continue;
            }

            if (!isGroup) {
              final radius = math.sqrt(area / math.pi);
              impacts.add({
                'x': cx,
                'y': cy,
                'r': radius,
                'circularity': circularity,
                'distToCenter': distToCenter,
              });
              foundPositions.add([cx, cy]);
              debugPrint('  [$passName] Impacto: '
                  '(${cx.toStringAsFixed(0)}, ${cy.toStringAsFixed(0)}) '
                  'r=${radius.toStringAsFixed(1)} area=${area.toStringAsFixed(0)} '
                  'circ=${circularity.toStringAsFixed(2)} '
                  'dist=${distToCenter.toStringAsFixed(0)}');
            } else {
              debugPrint('  [$passName] Grupo: area=${area.toStringAsFixed(0)} '
                  '(${(area / holeAreaExpected).toStringAsFixed(1)}x esperada) '
                  'circ=${circularity.toStringAsFixed(2)}');

              final separated = _separateGroupedImpacts(
                passCleaned, contour, contours, i,
                holeRadiusPx, holeAreaExpected,
                center, maxDianaRadius,
                rows, cols,
              );

              // Verificar que el GRUPO (como bloque) no es duplicado de otro pass.
              // Usamos el centroide del grupo, no los impactos individuales.
              bool groupDup = false;
              for (final pos in foundPositions) {
                if (_distance(cx, cy, pos[0], pos[1]) < holeRadiusPx * 2) {
                  groupDup = true;
                  break;
                }
              }
              if (!groupDup) {
                // Añadir TODOS los impactos del grupo sin deduplicar entre ellos
                impacts.addAll(separated);
                // Registrar solo el centroide del grupo para deduplicación entre passes
                foundPositions.add([cx, cy]);
                debugPrint('    → ${separated.length} impactos del grupo');
              } else {
                rejected_dup++;
                debugPrint('    → Grupo duplicado (ya detectado en pass anterior)');
              }
            }
          }

          hierarchy.dispose();

          debugPrint('  [$passName] Rechazados → area: $rejected_area, '
              'pos: $rejected_pos, circ: $rejected_circ, '
              'borde: $rejected_border, dup: $rejected_dup');

        } finally {
          passThresh?.dispose();
          passCleaned?.dispose();
        }
      }

      // Mostrar near-misses para debug
      if (nearMisses.isNotEmpty) {
        debugPrint('Near-misses (casi válidos):');
        for (final nm in nearMisses) {
          debugPrint('  [${nm['pass']}] (${(nm['x'] as double).toStringAsFixed(0)}, '
              '${(nm['y'] as double).toStringAsFixed(0)}) '
              'area=${(nm['area'] as double).toStringAsFixed(0)} '
              'circ=${(nm['circ'] as double).toStringAsFixed(2)} '
              'razón: ${nm['reason']}');
        }
      }

      // Ordenar por distancia al centro (más cercano primero = mejor puntuación)
      impacts.sort((a, b) => a['distToCenter']!.compareTo(b['distToCenter']!));

      return {
        'impacts': impacts,
        'scale': scale,
        'holeRadiusPx': holeRadiusPx,
        'message': '${impacts.length} impactos detectados',
      };
    } catch (e) {
      debugPrint('OpenCV detectImpacts error: $e');
      return {
        'impacts': <Map<String, double>>[],
        'message': 'Error: $e',
      };
    } finally {
      src?.dispose();
      gray?.dispose();
      blurred?.dispose();
      morphK?.dispose();
    }
  }

  /// Separa un contorno grande (grupo de impactos solapados) en impactos
  /// individuales usando distanceTransform.
  ///
  /// Crea una máscara con el contorno, aplica distanceTransform,
  /// umbraliza para encontrar los "picos" (centros de cada agujero)
  /// y devuelve las posiciones individuales.
  static List<Map<String, double>> _separateGroupedImpacts(
    cv.Mat binaryImage,
    cv.VecPoint contour,
    cv.VecVecPoint allContours,
    int contourIdx,
    double holeRadiusPx,
    double holeAreaExpected,
    Offset dianaCenter,
    double maxDianaRadius,
    int rows,
    int cols,
  ) {
    cv.Mat? mask, distMap, distLabels, distThresh;

    try {
      // 1. Crear máscara con solo este contorno (relleno)
      mask = cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC1);
      cv.drawContours(
        mask, allContours, contourIdx,
        cv.Scalar(255, 255, 255),
        thickness: -1, // Relleno
      );

      // 2. Aplicar distanceTransform
      // Cada píxel obtiene su distancia al borde más cercano
      // Los centros de los agujeros tendrán valores altos
      final dtResult = cv.distanceTransform(
        mask,
        cv.DIST_L2,   // Distancia euclidiana
        5,             // Máscara 5x5
        0,             // DIST_LABEL_CCOMP
      );
      distMap = dtResult.$1;
      distLabels = dtResult.$2;

      // Estimar N por área.
      // Cuando los impactos se solapan mucho, el área combinada es menor
      // que N * áreaEsperada. Con 50% de solapamiento típico entre 2 agujeros,
      // el área combinada es ~1.5x en vez de 2.0x. Usamos factor de corrección.
      final contourArea = cv.contourArea(contour);
      final areaRatio = contourArea / holeAreaExpected;
      // Factor de solapamiento: asumir ~40% solapamiento entre impactos adyacentes
      // Para N impactos con 40% solapamiento: área ≈ esperada * (1 + 0.6*(N-1))
      // Despejando N: N ≈ 1 + (areaRatio - 1) / 0.6
      final expectedN = (1 + (areaRatio - 1) / 0.6).ceil().clamp(2, 7);
      debugPrint('    Grupo: areaRatio=${areaRatio.toStringAsFixed(2)} '
          '→ estimado $expectedN impactos (con corrección solapamiento)');

      // 3. Intentar separar con umbrales decrecientes
      // Empezar con umbral bajo para poder separar impactos muy solapados
      final results = <Map<String, double>>[];

      for (final threshFactor in [0.30, 0.25, 0.20]) {
        results.clear();
        final peakThreshold = holeRadiusPx * threshFactor;

        distThresh?.dispose();
        distThresh = cv.threshold(distMap, peakThreshold, 255, cv.THRESH_BINARY).$2;

        final distThresh8 = distThresh!.convertTo(cv.MatType.CV_8UC1);

        // Erosionar ligeramente para separar picos pegados
        final erodeK = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
        final eroded = cv.erode(distThresh8, erodeK);

        final peakResult = cv.findContours(
          eroded, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE,
        );
        final peaks = peakResult.$1;
        final peakHierarchy = peakResult.$2;

        for (int p = 0; p < peaks.length; p++) {
          final peak = peaks[p];
          final peakArea = cv.contourArea(peak);
          if (peakArea < 1) continue;

          double px = 0, py = 0;
          for (int k = 0; k < peak.length; k++) {
            px += peak[k].x;
            py += peak[k].y;
          }
          px /= peak.length;
          py /= peak.length;

          final dist = _distance(px, py, dianaCenter.dx, dianaCenter.dy);
          if (dist > maxDianaRadius) continue;

          results.add({
            'x': px,
            'y': py,
            'r': holeRadiusPx,
            'circularity': 1.0,
            'distToCenter': dist,
          });
        }

        peakHierarchy.dispose();
        erodeK.dispose();
        eroded.dispose();
        distThresh8.dispose();

        debugPrint('    distTransform umbral=${threshFactor}: ${results.length} picos '
            '(esperados ~$expectedN)');

        // Si encontramos al menos 2 picos, aceptar
        if (results.length >= 2) break;
      }

      // Si distanceTransform no separó bien, generar posiciones por área
      if (results.length < 2) {
        results.clear();
        // Calcular centroide del grupo
        double cx = 0, cy = 0;
        for (int k = 0; k < contour.length; k++) {
          cx += contour[k].x;
          cy += contour[k].y;
        }
        cx /= contour.length;
        cy /= contour.length;

        // Distribuir N impactos alrededor del centroide en un patrón circular
        final spreadRadius = holeRadiusPx * 0.3; // Ligero offset entre impactos
        for (int n = 0; n < expectedN; n++) {
          final angle = (n * 2 * math.pi) / expectedN;
          final px = cx + spreadRadius * math.cos(angle);
          final py = cy + spreadRadius * math.sin(angle);
          final dist = _distance(px, py, dianaCenter.dx, dianaCenter.dy);

          results.add({
            'x': px,
            'y': py,
            'r': holeRadiusPx,
            'circularity': 1.0,
            'distToCenter': dist,
          });
        }
        debugPrint('    Fallback: $expectedN impactos distribuidos en centroide');
      }

      return results;
    } catch (e) {
      debugPrint('Error separando grupo: $e');
      return [];
    } finally {
      mask?.dispose();
      distMap?.dispose();
      distLabels?.dispose();
      distThresh?.dispose();
    }
  }

  /// Distancia euclidiana entre dos puntos
  static double _distance(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Filtro de mediana circular (trata la lista como un anillo cerrado).
  /// Elimina picos aislados (números, imperfecciones) manteniendo la forma.
  static List<double> _medianFilter(List<double> data, int windowSize) {
    final n = data.length;
    final half = windowSize ~/ 2;
    final result = List<double>.filled(n, 0);

    for (int i = 0; i < n; i++) {
      // Recoger valores en la ventana (con wrap-around circular)
      final window = <double>[];
      for (int w = -half; w <= half; w++) {
        final idx = (i + w) % n;
        window.add(data[idx < 0 ? idx + n : idx]);
      }
      // Ordenar y tomar la mediana
      window.sort();
      result[i] = window[window.length ~/ 2];
    }
    return result;
  }

  /// Suavizado circular con media móvil (trata la lista como anillo cerrado).
  /// Produce un contorno suave sin aristas.
  static List<double> _circularSmooth(List<double> data, int windowSize) {
    final n = data.length;
    final half = windowSize ~/ 2;
    final result = List<double>.filled(n, 0);

    for (int i = 0; i < n; i++) {
      double sum = 0;
      int count = 0;
      for (int w = -half; w <= half; w++) {
        final idx = (i + w) % n;
        sum += data[idx < 0 ? idx + n : idx];
        count++;
      }
      result[i] = sum / count;
    }
    return result;
  }

  // =========================================================================
  // GENERACIÓN DE IMAGEN BINARIA
  // =========================================================================

  /// Genera una imagen binaria optimizada usando umbralización adaptativa
  /// y operaciones morfológicas de OpenCV.
  /// [blurRadius] > 0: desenfoque gaussiano, < 0: nitidez (unsharp mask), 0: sin filtro.
  /// [threshold] controla la sensibilidad del umbral adaptativo.
  /// [invertColors] true para zona negra (detectar líneas blancas), false para zona blanca.
  static Future<File?> generateBinaryImage(
    Uint8List imageBytes, {
    double blurRadius = 4.0,
    double threshold = 0.40,
    bool invertColors = false,
  }) async {
    cv.Mat? src, gray, processed, binary, morphKernel, cleaned;

    try {
      src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      // Convertir a escala de grises
      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);

      // Aplicar desenfoque o nitidez según parámetro
      if (blurRadius > 0) {
        int ksize = (blurRadius.round() * 2 + 1);
        if (ksize < 3) ksize = 3;
        if (ksize > 31) ksize = 31;
        if (ksize % 2 == 0) ksize++;
        processed = cv.gaussianBlur(gray, (ksize, ksize), 0);
      } else if (blurRadius < 0) {
        // Unsharp mask: imagen original + (original - desenfocada) * factor
        final tempBlurred = cv.gaussianBlur(gray, (5, 5), blurRadius.abs());
        processed = cv.addWeighted(gray, 1.5, tempBlurred, -0.5, 0);
        tempBlurred.dispose();
      } else {
        processed = gray.clone();
      }

      // Umbralización adaptativa gaussiana
      // Más robusta que umbral fijo: se adapta a variaciones de iluminación
      final threshType =
          invertColors ? cv.THRESH_BINARY : cv.THRESH_BINARY_INV;
      final blockSize = 11;
      final c = 2.0 + (threshold * 5);

      binary = cv.adaptiveThreshold(
        processed,
        255.0,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        threshType,
        blockSize,
        c,
      );

      // Limpieza morfológica: apertura (erosión + dilatación) para eliminar ruido
      morphKernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
      cleaned = cv.morphologyEx(binary, cv.MORPH_OPEN, morphKernel);

      // Codificar como JPEG de alta calidad
      final (success, encoded) = cv.imencode('.jpg', cleaned);
      if (!success) {
        throw Exception('Error al codificar la imagen binaria');
      }

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/binary_diana_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(encoded);

      return File(path);
    } catch (e) {
      debugPrint('OpenCV generateBinaryImage error: $e');
      return null;
    } finally {
      src?.dispose();
      gray?.dispose();
      processed?.dispose();
      binary?.dispose();
      morphKernel?.dispose();
      cleaned?.dispose();
    }
  }

  // =========================================================================
  // UTILIDADES
  // =========================================================================

  /// Ordena 4 puntos en el orden: TL, TR, BL, BR
  /// basándose en la posición relativa al centroide.
  static List<Offset> _orderCorners(List<Offset> points) {
    assert(points.length == 4);

    // Calcular centroide
    final cx = points.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    final cy = points.map((p) => p.dy).reduce((a, b) => a + b) / 4;

    // Clasificar por cuadrante relativo al centroide
    Offset? tl, tr, bl, br;
    for (final p in points) {
      if (p.dx < cx && p.dy < cy) {
        tl = p;
      } else if (p.dx >= cx && p.dy < cy) {
        tr = p;
      } else if (p.dx < cx && p.dy >= cy) {
        bl = p;
      } else {
        br = p;
      }
    }

    // Fallback: si algún cuadrante no tiene punto, usar método de sumas/diferencias
    if (tl == null || tr == null || bl == null || br == null) {
      final sorted = List<Offset>.from(points);
      // Menor suma x+y → TL, mayor suma → BR
      sorted.sort((a, b) => (a.dx + a.dy).compareTo(b.dx + b.dy));
      tl = sorted.first;
      br = sorted.last;
      // Menor diferencia y-x → TR, mayor diferencia → BL
      sorted.sort((a, b) => (a.dy - a.dx).compareTo(b.dy - b.dx));
      tr = sorted.first;
      bl = sorted.last;
    }

    return [tl!, tr!, bl!, br!];
  }
}

/// Segmento de línea detectado por HoughLinesP
class _HoughLine {
  final double x1, y1, x2, y2;
  final double length;
  final double angle; // radianes

  const _HoughLine(this.x1, this.y1, this.x2, this.y2, this.length, this.angle);
}
