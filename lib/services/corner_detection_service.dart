import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';

/// Servicio para detectar esquinas rojas en una imagen de diana
class CornerDetectionService {
  /// Color de referencia para detectar esquinas (opcional)
  /// Si se proporciona, se usa este color en lugar de detectar automáticamente
  img.ColorRgb8? referenceColor;
  
  /// Tolerancia para comparar colores (0-255)
  int colorTolerance = 50;

  /// Detecta las 4 esquinas rojas de la diana
  /// Retorna una lista de 4 Offset en el orden: top-left, top-right, bottom-left, bottom-right
  /// Si no se detectan 4 esquinas, retorna null
  /// [referenceColor] es opcional: si se proporciona, se usa ese color como referencia
  Future<List<Offset>?> detectRedCorners(
    File imageFile, {
    img.ColorRgb8? referenceColor,
    int colorTolerance = 50,
  }) async {
    this.referenceColor = referenceColor;
    this.colorTolerance = colorTolerance;
    try {
      final bytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) throw Exception('No se pudo decodificar la imagen');

      // Buscar píxeles rojos
      final redRegions = <List<Point<int>>>[];
      final visited = List.generate(
        originalImage.height,
        (_) => List.generate(originalImage.width, (_) => false),
      );

      // Detectar regiones rojas usando flood fill
      for (int y = 0; y < originalImage.height; y++) {
        for (int x = 0; x < originalImage.width; x++) {
          if (!visited[y][x]) {
            final pixel = originalImage.getPixel(x, y);
            if (_matchesColor(pixel)) {
              final region = _floodFillRed(originalImage, visited, x, y);
              if (region.length >= 20) { // Mínimo tamaño para considerar una esquina
                redRegions.add(region);
              }
            }
          }
        }
      }

      if (redRegions.length < 4) {
        debugPrint('Solo se detectaron ${redRegions.length} regiones rojas, se necesitan 4');
        return null;
      }

      // Calcular el centroide de cada región roja
      final centroids = redRegions.map((region) {
        double sumX = 0, sumY = 0;
        for (var point in region) {
          sumX += point.x;
          sumY += point.y;
        }
        return Offset(sumX / region.length, sumY / region.length);
      }).toList();

      // Ordenar por posición: top-left, top-right, bottom-left, bottom-right
      // Usar el tamaño de la imagen para determinar mejor las esquinas
      final imageWidth = originalImage.width.toDouble();
      final imageHeight = originalImage.height.toDouble();
      final centerX = imageWidth / 2;
      final centerY = imageHeight / 2;
      
      // Separar en cuadrantes basándose en el centro de la imagen
      final topLeft = centroids.where((c) => c.dy < centerY && c.dx < centerX).toList();
      final topRight = centroids.where((c) => c.dy < centerY && c.dx >= centerX).toList();
      final bottomLeft = centroids.where((c) => c.dy >= centerY && c.dx < centerX).toList();
      final bottomRight = centroids.where((c) => c.dy >= centerY && c.dx >= centerX).toList();
      
      // Si algún cuadrante tiene más de una esquina, elegir la más cercana a la esquina del cuadrante
      Offset? getClosestToCorner(List<Offset> corners, bool isTop, bool isLeft) {
        if (corners.isEmpty) return null;
        if (corners.length == 1) return corners[0];
        
        // Calcular distancia a la esquina ideal del cuadrante
        corners.sort((a, b) {
          final distA = (isLeft ? a.dx : imageWidth - a.dx) + (isTop ? a.dy : imageHeight - a.dy);
          final distB = (isLeft ? b.dx : imageWidth - b.dx) + (isTop ? b.dy : imageHeight - b.dy);
          return distA.compareTo(distB);
        });
        
        return corners[0];
      }
      
      final tl = getClosestToCorner(topLeft, true, true);
      final tr = getClosestToCorner(topRight, true, false);
      final bl = getClosestToCorner(bottomLeft, false, true);
      final br = getClosestToCorner(bottomRight, false, false);
      
      // Si el nuevo método no encuentra todas las esquinas, usar el método anterior
      if (tl == null || tr == null || bl == null || br == null) {
        debugPrint('Método de cuadrantes no encontró todas las esquinas, usando método alternativo');
        centroids.sort((a, b) => a.dy.compareTo(b.dy));
        final topCorners = centroids.take(2).toList();
        final bottomCorners = centroids.skip(2).take(2).toList();
        topCorners.sort((a, b) => a.dx.compareTo(b.dx));
        bottomCorners.sort((a, b) => a.dx.compareTo(b.dx));
        
        final result = [
          topCorners[0],    // top-left
          topCorners[1],    // top-right
          bottomCorners[0], // bottom-left
          bottomCorners[1], // bottom-right
        ];
        
        debugPrint('Esquinas ordenadas (método alternativo):');
        debugPrint('  TL: (${result[0].dx.toStringAsFixed(1)}, ${result[0].dy.toStringAsFixed(1)})');
        debugPrint('  TR: (${result[1].dx.toStringAsFixed(1)}, ${result[1].dy.toStringAsFixed(1)})');
        debugPrint('  BL: (${result[2].dx.toStringAsFixed(1)}, ${result[2].dy.toStringAsFixed(1)})');
        debugPrint('  BR: (${result[3].dx.toStringAsFixed(1)}, ${result[3].dy.toStringAsFixed(1)})');
        
        return result;
      }
      
      final result = [
        tl!,    // top-left
        tr!,    // top-right
        bl!,    // bottom-left
        br!,    // bottom-right
      ];
      
      debugPrint('Esquinas ordenadas (método de cuadrantes):');
      debugPrint('  TL: (${result[0].dx.toStringAsFixed(1)}, ${result[0].dy.toStringAsFixed(1)})');
      debugPrint('  TR: (${result[1].dx.toStringAsFixed(1)}, ${result[1].dy.toStringAsFixed(1)})');
      debugPrint('  BL: (${result[2].dx.toStringAsFixed(1)}, ${result[2].dy.toStringAsFixed(1)})');
      debugPrint('  BR: (${result[3].dx.toStringAsFixed(1)}, ${result[3].dy.toStringAsFixed(1)})');
      
      return result;
    } catch (e) {
      debugPrint('Error al detectar esquinas rojas: $e');
      return null;
    }
  }

  /// Verifica si un píxel coincide con el color de referencia o es rojo
  bool _matchesColor(img.Pixel pixel) {
    // Si hay un color de referencia, comparar con tolerancia
    if (referenceColor != null) {
      final dr = (pixel.r - referenceColor!.r).abs();
      final dg = (pixel.g - referenceColor!.g).abs();
      final db = (pixel.b - referenceColor!.b).abs();
      
      // Usar distancia euclidiana en RGB
      final distance = (dr * dr + dg * dg + db * db).toDouble();
      final maxDistance = colorTolerance * colorTolerance * 3; // Tolerancia al cuadrado * 3 canales
      
      return distance <= maxDistance;
    }
    
    // Fallback: detección automática de rojo
    final r = pixel.r;
    final g = pixel.g;
    final b = pixel.b;
    
    // Un píxel es rojo si:
    // - R es alto (>150)
    // - G y B son bajos (<100)
    // - R es significativamente mayor que G y B
    return r > 150 && g < 100 && b < 100 && r > (g + b);
  }

  /// Flood fill para encontrar regiones rojas conectadas
  List<Point<int>> _floodFillRed(
    img.Image image,
    List<List<bool>> visited,
    int startX,
    int startY,
  ) {
    final List<Point<int>> stack = [Point(startX, startY)];
    final List<Point<int>> region = [];

    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      final x = point.x;
      final y = point.y;

      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      if (visited[y][x]) continue;

      final pixel = image.getPixel(x, y);
      if (!_matchesColor(pixel)) continue;

      visited[y][x] = true;
      region.add(point);

      // 8-conectividad para capturar mejor las esquinas
      stack.add(Point(x + 1, y));
      stack.add(Point(x - 1, y));
      stack.add(Point(x, y + 1));
      stack.add(Point(x, y - 1));
      stack.add(Point(x + 1, y + 1));
      stack.add(Point(x - 1, y - 1));
      stack.add(Point(x + 1, y - 1));
      stack.add(Point(x - 1, y + 1));
    }

    return region;
  }
}

// Clase auxiliar Point
class Point<T> {
  final T x;
  final T y;
  Point(this.x, this.y);
}
