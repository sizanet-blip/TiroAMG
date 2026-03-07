import 'dart:io';
import 'dart:math'; // Para min y max
import 'package:image/image.dart' as img; // Alias para el paquete 'image'
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart' show Offset;

// 🚨 CORRECCIÓN: Esta clase debe estar fuera de TargetAnalyzerService 🚨
class IntPoint {
  final int x;
  final int y;
  IntPoint(this.x, this.y);
}


// Esta clase maneja la lógica de procesamiento de imágenes usando un paquete simple y estable (image)
class TargetAnalyzerService {

  // Método para realizar un recorte rectangular simple (Bounding Box Crop)
  // [originalFile]: La imagen tomada por el usuario.
  // [normalizedPoints]: Lista de 4 Offset (0.0 a 1.0) definidos por el usuario (esquinas).
  Future<File?> rectifyImage({
    required File originalFile,
    required List<Offset> normalizedPoints,
    required double dianaSizeMm,
  }) async {
    try {
      // 1. Leer y decodificar la imagen
      final bytes = await originalFile.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      
      if (originalImage == null) {
        debugPrint("Error: No se pudo decodificar la imagen.");
        return null;
      }

      final int imgWidth = originalImage.width;
      final int imgHeight = originalImage.height;

      // 2. Convertir las coordenadas normalizadas (0.0 a 1.0) a píxeles enteros
      final List<IntPoint> actualPoints = normalizedPoints.map((p) {
        return IntPoint(
          (p.dx * imgWidth).round(),
          (p.dy * imgHeight).round(),
        );
      }).toList();

      // 3. Determinar el Bounding Box (recorte rectangular simple)
      // Encontramos los límites mínimo y máximo de los 4 puntos seleccionados
      int minX = actualPoints.map((p) => p.x).reduce(min);
      int minY = actualPoints.map((p) => p.y).reduce(min);
      int maxX = actualPoints.map((p) => p.x).reduce(max);
      int maxY = actualPoints.map((p) => p.y).reduce(max);

      int cropWidth = maxX - minX;
      int cropHeight = maxY - minY;
      
      // 4. Aplicar el recorte
      final croppedImage = img.copyCrop(
        originalImage, 
        x: minX, 
        y: minY, 
        width: cropWidth, 
        height: cropHeight
      );

      // 5. Guardar la imagen recortada en un archivo temporal
      final directory = await getTemporaryDirectory();
      final String tempPath = '${directory.path}/cropped_diana_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      await File(tempPath).writeAsBytes(img.encodeJpg(croppedImage, quality: 90));

      // 6. Devolver el nuevo archivo recortado
      return File(tempPath);

    } catch (e) {
      debugPrint("Error durante el recorte: $e");
      return null;
    }
  }

  // Método para la detección automática de esquinas (futura implementación)
  // Devolvemos puntos simulados (ejemplo)
  Future<List<Offset>?> detectCornersAutomatically({required File originalFile}) async {
    await Future.delayed(const Duration(milliseconds: 500)); // Simulación de procesamiento
    
    return [
      const Offset(0.05, 0.05), // TL
      const Offset(0.95, 0.05), // TR
      const Offset(0.95, 0.95), // BR
      const Offset(0.05, 0.95), // BL
    ];
  }
}