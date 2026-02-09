import 'dart:io';
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
