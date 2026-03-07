import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/disparo_model.dart';

class HoleDetectionService {
  // Almacenar información de agujeros por número de disparo (temporal para visualización)
  static final Map<int, Map<String, dynamic>> _holeInfo = {}; // {numero: {centerX, centerY, radius}}
  
  // Almacenar la imagen binaria generada (para visualización)
  static File? _binaryImageFile;
  
  /// Obtiene la información de un agujero por su número de disparo
  /// Retorna un mapa con: centerX, centerY, radius
  static Map<String, dynamic>? getHoleInfo(int numero) {
    return _holeInfo[numero];
  }
  
  /// Obtiene el contorno de un agujero por su número de disparo (deprecated, usar getHoleInfo)
  static List<Point<int>>? getContourForDisparo(int numero) {
    // Mantener compatibilidad temporal
    return null;
  }
  
  /// Obtiene el archivo de la imagen binaria generada
  static File? getBinaryImageFile() {
    return _binaryImageFile;
  }
  
  /// Establece el archivo de la imagen binaria generada
  static void setBinaryImageFile(File? file) {
    _binaryImageFile = file;
  }
  
  /// Calcula el umbral óptimo usando el método de Otsu
  /// Retorna el umbral que maximiza la varianza entre clases (blanco/negro)
  int _calculateOtsuThreshold(img.Image image) {
    // Calcular histograma de intensidades (0-255)
    final histogram = List<int>.filled(256, 0);
    int totalPixels = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Calcular intensidad (escala de grises)
        final intensity = (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b).round();
        histogram[intensity.clamp(0, 255)]++;
        totalPixels++;
      }
    }
    
    // Calcular probabilidades
    final probabilities = histogram.map((count) => count / totalPixels).toList();
    
    // Encontrar umbral óptimo que maximiza varianza entre clases
    double maxVariance = 0;
    int optimalThreshold = 128; // Valor por defecto
    
    for (int t = 1; t < 255; t++) {
      // Probabilidad de clase 0 (píxeles < umbral)
      double w0 = 0;
      for (int i = 0; i < t; i++) {
        w0 += probabilities[i];
      }
      
      // Probabilidad de clase 1 (píxeles >= umbral)
      double w1 = 1 - w0;
      
      if (w0 == 0 || w1 == 0) continue;
      
      // Media de clase 0
      double mean0 = 0;
      for (int i = 0; i < t; i++) {
        mean0 += i * probabilities[i];
      }
      mean0 /= w0;
      
      // Media de clase 1
      double mean1 = 0;
      for (int i = t; i < 256; i++) {
        mean1 += i * probabilities[i];
      }
      mean1 /= w1;
      
      // Varianza entre clases
      final variance = w0 * w1 * (mean0 - mean1) * (mean0 - mean1);
      
      if (variance > maxVariance) {
        maxVariance = variance;
        optimalThreshold = t;
      }
    }
    
    return optimalThreshold;
  }
  
  /// Aplica sharpening a la imagen usando un kernel de Laplaciano
  img.Image _applySharpening(img.Image image, double strength) {
    final kernel = [
      [0.0, -strength, 0.0],
      [-strength, 1.0 + 4.0 * strength, -strength],
      [0.0, -strength, 0.0],
    ];
    final result = img.copyResize(image, width: image.width, height: image.height);
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        double r = 0, g = 0, b = 0;
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final pixel = image.getPixel(x + kx, y + ky);
            final weight = kernel[ky + 1][kx + 1];
            r += pixel.r * weight;
            g += pixel.g * weight;
            b += pixel.b * weight;
          }
        }
        result.setPixel(x, y, img.ColorRgb8(
          r.clamp(0, 255).round(),
          g.clamp(0, 255).round(),
          b.clamp(0, 255).round(),
        ));
      }
    }
    return result;
  }

  /// Convierte imagen a blanco/negro usando umbral Otsu
  img.Image _convertToBinary(img.Image image, int threshold) {
    final binaryImage = img.copyResize(
      image,
      width: image.width,
      height: image.height,
    );
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final intensity = (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b).round();
        
        // Píxeles oscuros (< umbral) → negro (agujeros)
        // Píxeles claros (>= umbral) → blanco (fondo)
        if (intensity < threshold) {
          binaryImage.setPixel(x, y, img.ColorRgb8(0, 0, 0)); // Negro = agujero
        } else {
          binaryImage.setPixel(x, y, img.ColorRgb8(255, 255, 255)); // Blanco = fondo
        }
      }
    }
    
    return binaryImage;
  }

  /// Detecta agujeros usando procesamiento simplificado: imagen → blur → Otsu → binario
  /// [detectInLightZone]: Si es true, solo detecta en zona clara (6-1), si es false detecta en toda la diana
  /// [shotEstimationFactor]: Factor multiplicador para estimar disparos por agujero (default: 1.0)
  /// [detectedCircleRadii]: Lista de radios de los círculos detectados (normalizados, de menor a mayor)
  Future<List<Disparo>> detectHoles({
    required File imageFile,
    required Offset dianaCenter,
    required double dianaRadius,
    int minHoleSize = 1,      // Tamaño mínimo del agujero en píxeles
    int maxHoleSize = 200,    // Tamaño máximo del agujero en píxeles
    double blurRadius = 3.0,  // Radio del filtro Gaussiano (negativo = sharpening)
    bool detectInLightZone = true, // Por defecto detectar solo en zona clara
    double shotEstimationFactor = 1.0, // Factor para estimar disparos
    List<double>? detectedCircleRadii, // Radios de los círculos detectados (normalizados)
  }) async {
    try {
      // 1. Cargar imagen
      final bytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) throw Exception('No se pudo decodificar la imagen');
      

      // 2. Filtrar píxeles rojos de las esquinas antes de procesar
      // Color por defecto de esquinas: R:247 G:28 B:108
      final cornerColor = img.ColorRgb8(247, 28, 108);
      final colorTolerance = 60;
      
      // Crear máscara para excluir píxeles rojos de esquinas
      final excludeMask = List.generate(
        originalImage.height,
        (_) => List.generate(originalImage.width, (_) => false),
      );
      
      for (int y = 0; y < originalImage.height; y++) {
        for (int x = 0; x < originalImage.width; x++) {
          final pixel = originalImage.getPixel(x, y);
          final dr = (pixel.r - cornerColor.r).abs();
          final dg = (pixel.g - cornerColor.g).abs();
          final db = (pixel.b - cornerColor.b).abs();
          final distance = sqrt(dr * dr + dg * dg + db * db);
          
          if (distance <= colorTolerance) {
            excludeMask[y][x] = true;
            // Cambiar píxeles rojos a blanco para que no interfieran
            originalImage.setPixel(x, y, img.ColorRgb8(255, 255, 255));
          }
        }
      }

      // 3. Aplicar filtro Gaussiano o sharpening según el valor
      img.Image processedImage;
      if (blurRadius < 0) {
        // Sharpening (desenfoque negativo)
        processedImage = _applySharpening(originalImage, blurRadius.abs());
      } else if (blurRadius > 0) {
        // Blur (desenfoque positivo)
        processedImage = img.gaussianBlur(originalImage, radius: blurRadius.round());
      } else {
        // Sin procesamiento
        processedImage = originalImage;
      }

      // 4. Convertir directamente a blanco/negro usando método Otsu
      final otsuThreshold = _calculateOtsuThreshold(processedImage);
      var binaryImage = _convertToBinary(processedImage, otsuThreshold);
      
      // Asegurar que los píxeles excluidos permanezcan blancos
      for (int y = 0; y < binaryImage.height; y++) {
        for (int x = 0; x < binaryImage.width; x++) {
          if (excludeMask[y][x]) {
            binaryImage.setPixel(x, y, img.ColorRgb8(255, 255, 255)); // Blanco = excluido
          }
        }
      }
      
      // Guardar imagen binaria para visualización
      try {
        final Uint8List encodedBytes = img.encodeJpg(binaryImage, quality: 100);
        final tempDir = await getTemporaryDirectory();
        final binaryFilePath = '${tempDir.path}/binary_diana_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(binaryFilePath).writeAsBytes(encodedBytes);
        _binaryImageFile = File(binaryFilePath);
      } catch (e) {
        // Error silencioso
      }
      

      // 5. Detectar contornos (áreas negras conectadas)
      // Usar un rango muy amplio para detectar todos los contornos
      // Luego filtraremos por radio
      final allHoles = _findContours(binaryImage, 5, binaryImage.width * binaryImage.height);
      
      // Filtrar directamente por área (píxeles) - mínimo y máximo
      final holes = allHoles.where((hole) {
        final area = (hole['area'] as num).toInt();
        return area >= minHoleSize && area <= maxHoleSize;
      }).toList();

      // 6. Calcular centro de cada agujero y convertir a coordenadas normalizadas
      final List<Disparo> disparos = [];
      
      // Limpiar información anterior
      _holeInfo.clear();
      
      // PASO 1: Identificar la zona central (agujero más grande cerca del centro)
      // y calcular el radio base (el más pequeño excluyendo la zona central)
      double? baseRadius;
      double? centralZoneRadius;
      
      // Primero, identificar la zona central
      for (var hole in holes) {
        final centerX = hole['centerX']!;
        final centerY = hole['centerY']!;
        final radius = hole['radius'] as double;
        
        // Convertir a coordenadas normalizadas
        final normalizedX = (centerX - dianaCenter.dx) / dianaRadius;
        final normalizedY = (centerY - dianaCenter.dy) / dianaRadius;
        final distancia = sqrt(normalizedX * normalizedX + normalizedY * normalizedY);
        
        // La zona central es el agujero más grande cerca del centro (distancia < 0.3)
        if (distancia < 0.3) {
          if (centralZoneRadius == null || radius > centralZoneRadius) {
            centralZoneRadius = radius;
          }
        }
      }
      
      // PASO 2: Encontrar el radio más pequeño excluyendo la zona central
      for (var hole in holes) {
        final centerX = hole['centerX']!;
        final centerY = hole['centerY']!;
        final radius = hole['radius'] as double;
        
        // Convertir a coordenadas normalizadas
        final normalizedX = (centerX - dianaCenter.dx) / dianaRadius;
        final normalizedY = (centerY - dianaCenter.dy) / dianaRadius;
        final distancia = sqrt(normalizedX * normalizedX + normalizedY * normalizedY);
        
        // Excluir la zona central del cálculo del radio base
        if (centralZoneRadius != null && distancia < 0.3 && radius == centralZoneRadius) {
          continue; // Saltar la zona central
        }
        
        // El radio base es el más pequeño de los agujeros reales
        if (baseRadius == null || radius < baseRadius) {
          baseRadius = radius;
        }
      }
      
      // Si no se encontró radio base (solo hay zona central), usar un valor por defecto
      if (baseRadius == null || baseRadius <= 0) {
        baseRadius = sqrt(minHoleSize / pi); // Radio mínimo basado en el área mínima
      }
      
      // PASO 3: Procesar cada agujero y calcular múltiples impactos basándose en el radio
      for (var hole in holes) {
        final centerX = hole['centerX']!;
        final centerY = hole['centerY']!;
        final radius = hole['radius'] as double;
        
        // Convertir a coordenadas normalizadas relativas al centro de la diana
        final normalizedX = (centerX - dianaCenter.dx) / dianaRadius;
        final normalizedY = (centerY - dianaCenter.dy) / dianaRadius;
        
        // Calcular cuántos disparos hay en este agujero basándose en el área
        // Si el área es N veces el área base, probablemente hay N disparos
        // Usar área en lugar de radio porque es más representativa del número de impactos
        final baseArea = pi * baseRadius * baseRadius;
        final holeArea = pi * radius * radius;
        final estimatedShots = ((holeArea / baseArea) * shotEstimationFactor).round().clamp(1, 10);
        
        // Calcular el radio de separación para distribuir los impactos alrededor del centro
        // Colocar los impactos cerca del borde del agujero grande para abarcar todo el radio
        // Usar un porcentaje mayor del radio del agujero para que estén más externos
        final separacionNormalizada = (radius / dianaRadius) * 0.6; // 60% del radio del agujero (más cerca del borde)
        
        // Normalizar el radio de un impacto individual
        final baseRadiusNormalizado = baseRadius / dianaRadius;
        
        // Crear los disparos correspondientes, distribuidos alrededor del centro
        for (int i = 0; i < estimatedShots; i++) {
          final numero = disparos.length + 1;
          
          // Calcular la posición de este disparo distribuida alrededor del centro
          double offsetX = normalizedX;
          double offsetY = normalizedY;
          
          if (estimatedShots > 1) {
            // Distribuir los impactos en un círculo alrededor del centro del agujero
            final angle = (2 * pi * i) / estimatedShots; // Ángulo uniforme
            offsetX = normalizedX + separacionNormalizada * cos(angle);
            offsetY = normalizedY + separacionNormalizada * sin(angle);
          }
          
          // Calcular la distancia del disparo individual al centro
          final distanciaDisparo = sqrt(offsetX * offsetX + offsetY * offsetY);
          
          // Verificar si este impacto individual toca la línea de algún círculo verde
          double? puntuacionDisparoTocaLinea;
          if (detectedCircleRadii != null && detectedCircleRadii.isNotEmpty) {
            // Umbral estricto para detectar solo cuando realmente toca la línea
            // Ser más estricto para evitar falsos positivos
            const double umbralTocaLinea = 0.018; // 1.8% del radio de la diana (estricto)
            final numCircles = detectedCircleRadii.length;
            
            // Calcular las distancias del borde más cercano y más lejano del impacto individual
            final distanciaBordeCercanoDisparo = (distanciaDisparo - baseRadiusNormalizado).clamp(0.0, 1.0);
            final distanciaBordeLejanoDisparo = (distanciaDisparo + baseRadiusNormalizado).clamp(0.0, 1.0);
            
            // Buscar el círculo más pequeño (zona más alta) que está siendo tocado por este impacto
            int? indiceCirculoTocadoDisparo;
            for (int j = 0; j < numCircles; j++) {
              final radioCirculo = detectedCircleRadii[j];
              
              // Verificar si el impacto toca el círculo
              final distanciaAlCirculoDesdeBordeCercano = (distanciaBordeCercanoDisparo - radioCirculo).abs();
              final distanciaAlCirculoDesdeCentro = (distanciaDisparo - radioCirculo).abs();
              
              // El impacto toca el círculo si:
              // 1. El borde más cercano está cerca del círculo (dentro del umbral), O
              // 2. El centro está cerca del círculo (dentro del umbral), O
              // 3. El círculo está dentro del rango del impacto (cruza el círculo)
              // NO usar el borde lejano porque puede dar falsos positivos
              final tocaPorBordeCercano = distanciaAlCirculoDesdeBordeCercano <= umbralTocaLinea;
              final tocaPorCentro = distanciaAlCirculoDesdeCentro <= umbralTocaLinea;
              final cruzaElCirculo = distanciaBordeCercanoDisparo <= radioCirculo && 
                                     distanciaBordeLejanoDisparo >= radioCirculo;
              
              // Considerar que toca si cumple cualquiera de las condiciones
              if (tocaPorBordeCercano || tocaPorCentro || cruzaElCirculo) {
                // Guardar el índice del círculo más pequeño que toca (zona más alta)
                if (indiceCirculoTocadoDisparo == null || j < indiceCirculoTocadoDisparo) {
                  indiceCirculoTocadoDisparo = j;
                }
              }
            }
            
            // Si este impacto toca un círculo, usar su zona
            if (indiceCirculoTocadoDisparo != null) {
              final zonaTocaLinea = numCircles - indiceCirculoTocadoDisparo;
              puntuacionDisparoTocaLinea = zonaTocaLinea.clamp(1, 10).toDouble();
            }
          }
          
          // Calcular la puntuación para este impacto individual
          final puntuacionDisparo = _calcularPuntuacion(distanciaDisparo, detectedCircleRadii: detectedCircleRadii);
          
          // Si este impacto toca la línea, usar la puntuación más alta
          // Si no, usar la puntuación calculada normalmente
          final puntuacionFinal = puntuacionDisparoTocaLinea != null && puntuacionDisparoTocaLinea > puntuacionDisparo
              ? puntuacionDisparoTocaLinea 
              : puntuacionDisparo;
          
          disparos.add(Disparo(
            numero: numero,
            x: offsetX,
            y: offsetY,
            puntuacion: puntuacionFinal,
            esMosca: distanciaDisparo < 0.05,
          ));
          
          // Almacenar información del agujero individual (centro del disparo y radio individual)
          // Cada disparo tiene su propia posición y el radio de un agujero individual
          final disparoCenterX = dianaCenter.dx + (offsetX * dianaRadius);
          final disparoCenterY = dianaCenter.dy + (offsetY * dianaRadius);
          
          _holeInfo[numero] = {
            'centerX': disparoCenterX,
            'centerY': disparoCenterY,
            'radius': baseRadius, // Radio de un agujero individual
          };
        }
      }
      
      return disparos;
      
    } catch (e) {
      rethrow;
    }
  }

  /// Encuentra contornos (agujeros) en la imagen binaria usando flood fill
  List<Map<String, dynamic>> _findContours(
    img.Image binaryImage, 
    int minSize, 
    int maxSize
  ) {
    final List<Map<String, dynamic>> holes = [];
    final visited = List.generate(
      binaryImage.height,
      (_) => List.generate(binaryImage.width, (_) => false),
    );

    for (int y = 0; y < binaryImage.height; y++) {
      for (int x = 0; x < binaryImage.width; x++) {
        if (!visited[y][x]) {
          final pixel = binaryImage.getPixel(x, y);
          final isBlack = pixel.r < 128; // Asumimos que agujeros son negros

          if (isBlack) {
            // Flood fill para encontrar el área conectada
            final region = _floodFill(binaryImage, visited, x, y, minSize, maxSize);
            if (region != null) {
              holes.add(region);
            }
          }
        }
      }
    }

    return holes;
  }

  /// Flood fill para encontrar regiones conectadas
  Map<String, dynamic>? _floodFill(
    img.Image image,
    List<List<bool>> visited,
    int startX,
    int startY,
    int minSize,
    int maxSize,
  ) {
    final List<Point<int>> stack = [Point(startX, startY)];
    final List<Point<int>> region = [];
    final Set<String> regionSet = {}; // Para búsqueda rápida
    
    int minX = startX, maxX = startX;
    int minY = startY, maxY = startY;

    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      final x = point.x;
      final y = point.y;

      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      if (visited[y][x]) continue;

      final pixel = image.getPixel(x, y);
      if (pixel.r >= 128) continue; // No es negro

      visited[y][x] = true;
      region.add(point);
      regionSet.add('$x,$y'); // Agregar a set para búsqueda rápida

      minX = min(minX, x);
      maxX = max(maxX, x);
      minY = min(minY, y);
      maxY = max(maxY, y);

      // Agregar vecinos (4-conectividad)
      stack.add(Point(x + 1, y));
      stack.add(Point(x - 1, y));
      stack.add(Point(x, y + 1));
      stack.add(Point(x, y - 1));
    }

    final area = region.length;
    
    // Filtrar solo por tamaño mínimo para evitar ruido (píxeles aislados)
    if (area < 5) { // Mínimo muy bajo para capturar todo
      return null;
    }
    
    // Calcular centroide
    double sumX = 0, sumY = 0;
    for (var point in region) {
      sumX += point.x;
      sumY += point.y;
    }
    
    // Calcular radio basado en el área: radio = sqrt(área / π)
    // Esto asume que el agujero es aproximadamente circular
    final radius = sqrt(area / pi);

    // Calcular puntos del contorno (píxeles que están en el borde)
    // Usar un algoritmo mejorado que capture TODOS los píxeles del borde
    final List<Point<int>> contourPoints = [];
    final Set<String> contourSet = {}; // Para evitar duplicados
    
    // Crear una matriz de la imagen para verificar píxeles vecinos más eficientemente
    final imagePixels = List.generate(
      image.height,
      (y) => List.generate(image.width, (x) => false),
    );
    
    // Marcar todos los píxeles de la región
    for (var point in region) {
      if (point.y >= 0 && point.y < image.height && point.x >= 0 && point.x < image.width) {
        imagePixels[point.y][point.x] = true;
      }
    }
    
    // Encontrar todos los píxeles del contorno
    for (var point in region) {
      final x = point.x;
      final y = point.y;
      final key = '$x,$y';
      
      if (contourSet.contains(key)) continue;
      
      // Un píxel está en el contorno si tiene al menos un vecino que no está en la región
      bool isContour = false;
      
      if (x == 0 || x >= image.width - 1 || y == 0 || y >= image.height - 1) {
        isContour = true; // Borde de la imagen
      } else {
        // Verificar los 8 vecinos (8-conectividad)
        // Si alguno de los vecinos NO está en la región, este píxel es contorno
        if (!imagePixels[y][x + 1] ||     // Este
            !imagePixels[y][x - 1] ||     // Oeste
            !imagePixels[y + 1][x] ||     // Sur
            !imagePixels[y - 1][x] ||     // Norte
            !imagePixels[y + 1][x + 1] || // Sureste
            !imagePixels[y - 1][x - 1] || // Noroeste
            !imagePixels[y - 1][x + 1] ||  // Noreste
            !imagePixels[y + 1][x - 1]) { // Suroeste
          isContour = true;
        }
      }
      
      if (isContour) {
        contourPoints.add(point);
        contourSet.add(key);
      }
    }
    

    return {
      'centerX': sumX / area,
      'centerY': sumY / area,
      'area': area.toDouble(),
      'radius': radius, // Radio calculado basado en el área
      'contourPoints': contourPoints, // Puntos del contorno (para referencia, pero usaremos círculo perfecto)
    };
  }

  /// Calcula la puntuación basada en la distancia normalizada
  double _calcularPuntuacion(double distanciaNormalizada, {List<double>? detectedCircleRadii}) {
    if (distanciaNormalizada > 1.0) return 0.0;
    
    // Si tenemos círculos detectados, usarlos para determinar la zona
    if (detectedCircleRadii != null && detectedCircleRadii.isNotEmpty) {
      // Los radios están ordenados de menor a mayor (círculo interior a exterior)
      // Solo detectamos círculos en la zona blanca (zonas 1-6)
      // El círculo más pequeño (índice 0) es la zona 6, el más grande (último índice) es la zona 1
      final numCircles = detectedCircleRadii.length;
      
      // Umbral para considerar que un agujero "toca" un círculo (en distancia normalizada)
      // Si está dentro de este umbral del círculo, se le asigna la zona más alta
      // Aumentado para detectar mejor cuando toca la línea
      const double umbralTocaLinea = 0.025; // ~2.5% del radio de la diana
      
      // Buscar el círculo más pequeño que contiene el agujero o que está siendo tocado
      for (int i = 0; i < numCircles; i++) {
        final radioCirculo = detectedCircleRadii[i];
        final distanciaAlCirculo = (distanciaNormalizada - radioCirculo).abs();
        
        // Si el agujero está dentro del círculo
        if (distanciaNormalizada <= radioCirculo) {
          // El agujero está dentro del círculo i
          // Círculo 0 (más pequeño) → zona 6
          // Círculo 1 → zona 5
          // ...
          // Círculo (numCircles-1) (más grande) → zona 1
          final zona = numCircles - i;
          return zona.clamp(1, 10).toDouble();
        }
        
        // Si el agujero está tocando la línea del círculo (muy cerca pero fuera)
        // Verificar tanto si está justo fuera como si está dentro del umbral
        if (distanciaNormalizada > radioCirculo && distanciaAlCirculo <= umbralTocaLinea) {
          // Está tocando la línea desde fuera, asignar la zona más alta (zona interior)
          // Si toca la línea del círculo i, cuenta como si estuviera dentro (zona más alta)
          final zona = numCircles - i;
          return zona.clamp(1, 10).toDouble();
        }
      }
      
      // También verificar si está muy cerca de algún círculo desde cualquier lado
      // (por si acaso el agujero está justo en el borde)
      for (int i = 0; i < numCircles; i++) {
        final radioCirculo = detectedCircleRadii[i];
        final distanciaAlCirculo = (distanciaNormalizada - radioCirculo).abs();
        
        // Si está muy cerca del círculo (dentro del umbral), asignar la zona más alta
        if (distanciaAlCirculo <= umbralTocaLinea) {
          final zona = numCircles - i;
          return zona.clamp(1, 10).toDouble();
        }
      }
      
      // Si está fuera de todos los círculos detectados pero dentro de la diana, está en zona 1
      // (o fuera de la diana si distancia > 1.0)
      if (distanciaNormalizada <= 1.0) {
        return 1.0;
      }
      
      return 0.0;
    }
    
    // Si no hay círculos detectados, usar la fórmula lineal original
    // Usar la misma fórmula que en sesion_disparo_screen
    // totalZonas = 11 - valorMinimo, donde valorMinimo = 1
    const totalZonas = 10; // 11 - 1 = 10
    final calculo = 11 - (distanciaNormalizada * totalZonas);
    // Usar floor() para redondear hacia abajo, igual que en sesion_disparo_screen
    final valor = calculo.floor();
    // Asegurar que esté entre 0 y 10
    if (valor < 0) return 0.0;
    if (valor > 10) return 10.0;
    return valor.toDouble();
  }
}

// Clase auxiliar Point
class Point<T> {
  final T x;
  final T y;
  Point(this.x, this.y);
}
