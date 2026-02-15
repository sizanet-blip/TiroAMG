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

  /// Detecta las 4 esquinas de un objeto rectangular (diana) en la imagen
  /// usando detección de bordes Canny + contornos + aproximación poligonal.
  /// No necesita marcas de color.
  /// Retorna [TL, TR, BL, BR] en coordenadas de imagen, o null si no detecta.
  static Future<List<Offset>?> detectTargetCorners(File imageFile) async {
    cv.Mat? src, gray, blurred, edges, kernel, dilated;
    cv.VecVec4i? hierarchy;

    try {
      final bytes = await imageFile.readAsBytes();
      src = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      // Preprocesamiento
      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      blurred = cv.gaussianBlur(gray, (5, 5), 0);
      edges = cv.canny(blurred, 50, 150);

      // Dilatar bordes para cerrar pequeños gaps
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      dilated = cv.dilate(edges, kernel);

      // Encontrar contornos externos
      final result = cv.findContours(
        dilated, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE,
      );
      final contours = result.$1;
      hierarchy = result.$2;

      final imageArea = (src.rows * src.cols).toDouble();
      double maxArea = 0;
      cv.VecPoint? bestApprox;

      for (int i = 0; i < contours.length; i++) {
        final contour = contours[i];
        final area = cv.contourArea(contour);

        // Ignorar contornos demasiado pequeños (< 10% del área de imagen)
        if (area < imageArea * 0.1) continue;

        final peri = cv.arcLength(contour, true);
        final approx = cv.approxPolyDP(contour, 0.02 * peri, true);

        // Buscamos un cuadrilátero (4 vértices)
        if (approx.length == 4 && area > maxArea) {
          maxArea = area;
          bestApprox = approx;
        }
      }

      if (bestApprox == null) return null;

      // Extraer coordenadas de los 4 puntos
      final points = <Offset>[];
      for (int i = 0; i < bestApprox.length; i++) {
        final pt = bestApprox[i];
        points.add(Offset(pt.x.toDouble(), pt.y.toDouble()));
      }

      return _orderCorners(points);
    } catch (e) {
      debugPrint('OpenCV detectTargetCorners error: $e');
      return null;
    } finally {
      src?.dispose();
      gray?.dispose();
      blurred?.dispose();
      edges?.dispose();
      kernel?.dispose();
      dilated?.dispose();
      hierarchy?.dispose();
    }
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
      // Usar solo los anillos centrales (los más fiables) para calcular
      // el espaciado. Excluimos el primero (puede ser el borde de la zona
      // negra) y el último (puede ser el borde de la diana).
      if (detectedRadii.length < 3) {
        return {
          'center': Offset(centerX, centerY),
          'circles': <Map<String, double>>[],
          'ringContours': <List<Map<String, dynamic>>>[],
          'message': 'Pocas transiciones detectadas (${detectedRadii.length})',
        };
      }

      // Calcular espaciado entre anillos consecutivos de la zona fiable
      // (del 2º al penúltimo detectado)
      final reliableStart = 1; // Saltar el primero
      final reliableEnd = detectedRadii.length - 1; // Excluir el último
      final spacings = <double>[];
      for (int i = reliableStart + 1; i <= reliableEnd; i++) {
        spacings.add(detectedRadii[i] - detectedRadii[i - 1]);
      }

      if (spacings.isEmpty) {
        // Fallback: usar todos los espaciados disponibles
        for (int i = 1; i < detectedRadii.length; i++) {
          spacings.add(detectedRadii[i] - detectedRadii[i - 1]);
        }
      }

      spacings.sort();
      final spacing = spacings[spacings.length ~/ 2]; // Mediana

      debugPrint('Espaciado ISSF calculado: ${spacing.toStringAsFixed(1)} px');

      // Encontrar el primer radio fiable (el anillo más interno claramente detectado)
      // Usamos el segundo detectado como referencia (más fiable que el primero)
      final referenceRadius = detectedRadii[reliableStart];
      debugPrint('Radio de referencia (2ª transición): ${referenceRadius.toStringAsFixed(1)}');

      // ================================================================
      // FASE 4: Generar TODOS los anillos matemáticamente
      // ================================================================
      // Desde el centro hacia fuera, generamos anillos con espaciado uniforme.
      // Empezamos desde el radio de referencia y vamos en ambas direcciones.
      final generatedRadii = <double>[];

      // Hacia el interior (desde referencia hacia el centro)
      double r = referenceRadius;
      while (r > spacing * 0.5) {
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
