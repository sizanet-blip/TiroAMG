import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img; 
import 'package:path_provider/path_provider.dart';
import '../services/hole_detection_service.dart' as hole_service;
import '../services/corner_detection_service.dart';
import '../models/disparo_model.dart';

// Clase auxiliar Point
class Point<T> {
  final T x;
  final T y;
  Point(this.x, this.y);
}

/// Pantalla principal para detectar agujeros en dianas automáticamente
class RecorteDianaScreen extends StatefulWidget {
  const RecorteDianaScreen({super.key});

  @override
  State<RecorteDianaScreen> createState() => _RecorteDianaScreenState();
}

class _RecorteDianaScreenState extends State<RecorteDianaScreen> {
  final ImagePicker _picker = ImagePicker();
  final hole_service.HoleDetectionService _detectionService = hole_service.HoleDetectionService();
  
  File? _croppedImage; // Imagen recortada
  File? _binaryImage; // Imagen en blanco y negro
  bool _showBinaryImage = false; // Toggle para mostrar imagen binaria
  bool _showCircles = false; // Toggle para mostrar/ocultar círculos de la diana (inicialmente oculto)
  int? _currentCircleIndex; // Índice del círculo actual a mostrar (null = todos)
  List<Disparo> _disparosDetectados = [];
  bool _isProcessing = false;
  bool _hasDetected = false;
  bool _showAdjustments = false;
  
  // Parámetros ajustables (ahora en radios en lugar de áreas)
  double _threshold = 0.40;
  double _minHoleRadius = 5.0; // Radio mínimo en píxeles
  double _maxHoleRadius = 50.0; // Radio máximo en píxeles
  double _blurRadius = 4.0; // Radio del filtro Gaussiano (negativo = sharpening)
  double _shotEstimationFactor = 1.0; // Factor para estimar disparos por agujero
  
  // Controllers para campos de texto de los sliders
  late final TextEditingController _thresholdController;
  late final TextEditingController _minHoleRadiusController;
  late final TextEditingController _maxHoleRadiusController;
  late final TextEditingController _blurRadiusController;
  late final TextEditingController _shotEstimationFactorController;
  
  @override
  void initState() {
    super.initState();
    _thresholdController = TextEditingController(text: _threshold.toStringAsFixed(2));
    _minHoleRadiusController = TextEditingController(text: _minHoleRadius.toStringAsFixed(1));
    _maxHoleRadiusController = TextEditingController(text: _maxHoleRadius.toStringAsFixed(1));
    _blurRadiusController = TextEditingController(text: _blurRadius.toStringAsFixed(1));
    _shotEstimationFactorController = TextEditingController(text: _shotEstimationFactor.toStringAsFixed(2));
  }
  
  @override
  void dispose() {
    _detectionTimer?.cancel();
    _thresholdController.dispose();
    _minHoleRadiusController.dispose();
    _maxHoleRadiusController.dispose();
    _blurRadiusController.dispose();
    _shotEstimationFactorController.dispose();
    super.dispose();
  }
  
  // Información de la diana
  Offset? _dianaCenter;
  double? _dianaRadius;
  Size? _imageSize;
  List<double>? _detectedLineRadii; // Radios de las líneas negras detectadas
  List<List<Offset>>? _detectedCirclePixels; // Píxeles de las líneas circulares detectadas
  Offset? _detectedCenter; // Centro estimado de los círculos detectados
  
  // Timer para detección automática con delay
  Timer? _detectionTimer;

  /// Captura o selecciona una imagen
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      
      if (pickedFile != null && mounted) {
        // Navegar a la pantalla de recorte
        final croppedFile = await Navigator.push<File>(
            context,
            MaterialPageRoute(
            builder: (context) => CropTargetScreen(imageFile: File(pickedFile.path)),
          ),
        );
        
        if (croppedFile != null && mounted) {
          setState(() {
            _croppedImage = croppedFile;
            _disparosDetectados = [];
            _hasDetected = false;
            _dianaCenter = null;
            _dianaRadius = null;
            _imageSize = null;
            _showBinaryImage = false; // Reset imagen B/N
            _showCircles = false; // Reset círculos
            _binaryImage = null; // Reset imagen binaria
            _detectedCirclePixels = null; // Reset círculos detectados
            _detectedLineRadii = null; // Reset radios detectados
            _currentCircleIndex = null; // Reset índice de círculo
          });
          
          // Calcular centro y radio de la diana en la imagen recortada
          _calcularDianaInfo();
        }
      }
    } catch (e) {
      if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e')),
        );
      }
    }
  }

  /// Calcula el centro y radio de la diana en la imagen recortada
  void _calcularDianaInfo() async {
    if (_croppedImage == null) return;
    
    try {
      final bytes = await _croppedImage!.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image != null) {
      setState(() {
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          _dianaCenter = Offset(image.width / 2.0, image.height / 2.0);
          _dianaRadius = min(image.width, image.height) / 2.0;
        });
      }
    } catch (e) {
      debugPrint('Error al calcular info de diana: $e');
    }
  }

  /// Genera la imagen binaria sin detectar agujeros
  /// Usa el mismo método que funciona bien para zona negra (umbral alto + contraste + limpieza)
  /// pero adaptado para detectar líneas negras sobre fondo blanco
  Future<void> _generarImagenBinaria() async {
    if (_croppedImage == null || _dianaCenter == null || _dianaRadius == null) {
      return;
    }

    try {
      // Cargar imagen
      final bytes = await _croppedImage!.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        throw Exception('No se pudo decodificar la imagen');
      }

      // Aplicar filtro según el parámetro de desenfoque
      img.Image processedImage;
      if (_blurRadius < 0) {
        // Sharpening
        processedImage = await _applySharpeningImage(originalImage, _blurRadius.abs());
      } else if (_blurRadius > 0) {
        processedImage = img.gaussianBlur(originalImage, radius: _blurRadius.round());
      } else {
        processedImage = originalImage;
      }

      // Para zona blanca: aplicar contraste fuerte para resaltar las líneas negras
      processedImage = _applyContrast(processedImage, 2.0); // Aumentar contraste 2x
      
      // Para zona blanca: usar umbral manual alto para capturar solo las líneas negras más definidas
      // El umbral _threshold (0.1-2.0) se convierte a 180-255
      // Usar un umbral alto (180-255) para que solo los píxeles muy oscuros sean negros
      // Mapeo: 0.1→180, 0.9→247.5, 2.0→255
      final thresholdValue = (180 + (_threshold * 75)).round().clamp(180, 255); // Rango 180-255
      
      // Convertir a binario: píxeles oscuros (< umbral) → negro (líneas negras)
      // Píxeles claros (>= umbral) → blanco (fondo blanco)
      var binaryImage = _convertToBinaryForWhiteZone(processedImage, thresholdValue);
      
      // Aplicar limpieza morfológica múltiple para eliminar ruido
      binaryImage = _cleanBinaryImage(binaryImage);
      binaryImage = _cleanBinaryImage(binaryImage); // Segunda pasada para mejor limpieza
      
      // Guardar imagen binaria
      final Uint8List encodedBytes = img.encodeJpg(binaryImage, quality: 100);
      final tempDir = await getTemporaryDirectory();
      final binaryFilePath = '${tempDir.path}/binary_diana_blanca_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(binaryFilePath).writeAsBytes(encodedBytes);
      hole_service.HoleDetectionService.setBinaryImageFile(File(binaryFilePath));

      // Obtener imagen binaria
      final binaryImageFile = hole_service.HoleDetectionService.getBinaryImageFile();
      
      // Detectar líneas negras en la imagen binaria
      if (binaryImageFile != null) {
        final result = await _detectarLineasNegras(
          binaryImageFile,
          agujeros: _disparosDetectados.isNotEmpty ? _disparosDetectados : null,
        );
        if (mounted) {
          setState(() {
            _binaryImage = binaryImageFile;
            _detectedCirclePixels = result['pixels'] as List<List<Offset>>?;
            _detectedCenter = result['center'] as Offset?;
            _detectedLineRadii = result['radii'] as List<double>?;
            _currentCircleIndex = null; // Reset al detectar nuevos círculos
          });
        }
      } else {
        if (mounted) {
      setState(() {
            _binaryImage = binaryImageFile;
          });
        }
      }
    } catch (e) {
      debugPrint('Error al generar imagen binaria: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar imagen B/N: $e')),
        );
      }
    }
  }

  /// Muestra la información del círculo actual en los logs
  void _logCircleInfo() {
    if (_currentCircleIndex == null || 
        _detectedCirclePixels == null || 
        _currentCircleIndex! >= _detectedCirclePixels!.length) {
      return;
    }
    
    final circle = _detectedCirclePixels![_currentCircleIndex!];
    final radius = _detectedLineRadii != null && _currentCircleIndex! < _detectedLineRadii!.length
        ? _detectedLineRadii![_currentCircleIndex!]
        : null;
    
    debugPrint('═══════════════════════════════════════');
    debugPrint('CÍRCULO ${_currentCircleIndex! + 1} de ${_detectedCirclePixels!.length}');
    debugPrint('Píxeles: ${circle.length}');
    if (radius != null) {
      debugPrint('Radio promedio: ${radius.toStringAsFixed(1)} píxeles');
    }
    debugPrint('═══════════════════════════════════════');
  }

  /// Detecta los píxeles de las líneas negras (círculos) en la imagen binaria
  /// Solo funciona cuando blur = 0 para detectar círculos claros
  /// Retorna un mapa con 'pixels' (lista de offsets de TODOS los píxeles negros) y 'center' (centro estimado)
  /// Usa los agujeros detectados para evitar conectar círculos que están unidos por agujeros
  Future<Map<String, dynamic>> _detectarLineasNegras(
    File binaryImageFile, {
    List<Disparo>? agujeros,
  }) async {
    try {
      // Detectar siempre, independientemente del blur
      // (pero funciona mejor cuando blur = 0)
      debugPrint('Detectando líneas con blur: $_blurRadius');

      final bytes = await binaryImageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('No se pudo decodificar la imagen binaria');
        return {'pixels': <List<Offset>>[], 'center': null};
      }


      // Detectar SOLO los BORDES de las líneas circulares
      // Buscar píxeles BLANCOS que están justo al lado de píxeles NEGROS
      // Esto detecta el borde interior de las líneas negras (la transición)
      final List<Offset> edgePixels = [];
      
      for (int y = 1; y < image.height - 1; y++) {
        for (int x = 1; x < image.width - 1; x++) {
          final pixel = image.getPixel(x, y);
          final intensity = (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b).round();
          
          // Solo considerar píxeles BLANCOS (estamos en la zona blanca, al lado de la línea negra)
          if (intensity >= 128) {
            // Contar vecinos negros en los 4 direcciones principales
            int blackNeighbors = 0;
            
            final neighbors = [
              (x, y - 1), // arriba
              (x, y + 1), // abajo
              (x - 1, y), // izquierda
              (x + 1, y), // derecha
            ];
            
            for (var (nx, ny) in neighbors) {
              if (nx >= 0 && nx < image.width && ny >= 0 && ny < image.height) {
                final neighborPixel = image.getPixel(nx, ny);
                final neighborIntensity = (0.2126 * neighborPixel.r + 0.7152 * neighborPixel.g + 0.0722 * neighborPixel.b).round();
                if (neighborIntensity < 128) {
                  blackNeighbors++;
                }
              }
            }
            
            // Solo agregar si tiene 1, 2 o 3 vecinos negros
            // Aceptar hasta 3 para capturar mejor líneas finas
            // Esto significa que está justo al lado de una línea, no en el interior de una zona negra
            if (blackNeighbors >= 1 && blackNeighbors <= 3) {
              // Verificar que no está rodeado de negros (no es un píxel blanco aislado dentro de un agujero)
              int totalWhite = 0;
              for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                  if (dx == 0 && dy == 0) continue;
                  final nx = x + dx;
                  final ny = y + dy;
                  if (nx >= 0 && nx < image.width && ny >= 0 && ny < image.height) {
                    final neighborPixel = image.getPixel(nx, ny);
                    final neighborIntensity = (0.2126 * neighborPixel.r + 0.7152 * neighborPixel.g + 0.0722 * neighborPixel.b).round();
                    if (neighborIntensity >= 128) {
                      totalWhite++;
                    }
                  }
                }
              }
              
              // Debe tener al menos 3 vecinos blancos (no está aislado en un agujero)
              if (totalWhite >= 3) {
                edgePixels.add(Offset(x.toDouble(), y.toDouble()));
              }
            }
          }
        }
      }
      
      
      if (edgePixels.isEmpty) {
        return {'pixels': <List<Offset>>[], 'center': null, 'radii': <double>[]};
      }
      
      // Convertir coordenadas de agujeros a píxeles de la imagen si están disponibles
      // También obtener el radio de cada agujero
      List<Map<String, dynamic>>? agujerosInfo;
      if (agujeros != null && agujeros.isNotEmpty && _dianaCenter != null && _dianaRadius != null) {
        agujerosInfo = [];
        for (var agujero in agujeros) {
          // Las coordenadas de agujero.x e agujero.y están normalizadas (-1 a 1)
          // Convertirlas a píxeles de la imagen
          final agujeroX = _dianaCenter!.dx + (agujero.x * _dianaRadius!);
          final agujeroY = _dianaCenter!.dy + (agujero.y * _dianaRadius!);
          
          // Obtener el radio real del agujero desde HoleDetectionService
          double agujeroRadio = 30.0; // Valor por defecto
          final holeInfo = hole_service.HoleDetectionService.getHoleInfo(agujero.numero);
          if (holeInfo != null && holeInfo.containsKey('radius')) {
            agujeroRadio = (holeInfo['radius'] as num).toDouble();
          }
          
          agujerosInfo.add({
            'position': Offset(agujeroX, agujeroY),
            'radius': agujeroRadio,
      });
    }
  }

      // Filtrar grupos pequeños (letras/números) agrupando píxeles cercanos
      final List<List<Offset>> filteredGroups = [];
      final List<bool> used = List.filled(edgePixels.length, false);
      
      for (int i = 0; i < edgePixels.length; i++) {
        if (used[i]) continue;
        
        final List<Offset> group = [];
        final List<int> toProcess = [i];
        
        while (toProcess.isNotEmpty) {
          final idx = toProcess.removeLast();
          if (used[idx]) continue;
          used[idx] = true;
          group.add(edgePixels[idx]);
          
          // Buscar píxeles cercanos (dentro de 5 píxeles para conectar mejor líneas finas)
          // Reducir la distancia de conexión si hay agujeros para evitar unir círculos
          final connectionDistance = (agujerosInfo != null && agujerosInfo.isNotEmpty) ? 3.0 : 5.0;
          for (int j = 0; j < edgePixels.length; j++) {
            if (used[j]) continue;
            final dist = (edgePixels[idx] - edgePixels[j]).distance;
            if (dist <= connectionDistance) {
              // Si hay agujeros detectados, verificar si la línea entre estos píxeles pasa por un agujero
              if (agujerosInfo != null && agujerosInfo.isNotEmpty) {
                final p1 = edgePixels[idx];
                final p2 = edgePixels[j];
                
                // Verificar si algún agujero está en la línea entre los dos píxeles
                bool hayAgujeroEnLaLinea = false;
                for (var agujeroInfo in agujerosInfo) {
                  final agujeroPos = agujeroInfo['position'] as Offset;
                  final agujeroRadio = agujeroInfo['radius'] as double;
                  
                  // Usar el radio del agujero + un margen de seguridad más grande (100% más = 2x)
                  final umbralDistancia = agujeroRadio * 2.0;
                  
                  // Calcular la distancia perpendicular del agujero a la línea entre p1 y p2
                  final lineVector = p2 - p1;
                  final toHoleVector = agujeroPos - p1;
                  
                  // Proyección del vector al agujero sobre la línea
                  final lineLength = lineVector.distance;
                  if (lineLength > 0) {
                    final dotProduct = toHoleVector.dx * lineVector.dx + toHoleVector.dy * lineVector.dy;
                    final projection = dotProduct / (lineLength * lineLength);
                    
                    // Si la proyección está dentro del segmento (entre 0 y 1) o cerca de los extremos
                    // Expandir el rango para capturar mejor agujeros cerca de los extremos
                    if (projection >= -0.2 && projection <= 1.2) {
                      // Calcular el punto más cercano en la línea al agujero
                      final closestPoint = p1 + Offset(
                        lineVector.dx * projection.clamp(0.0, 1.0),
                        lineVector.dy * projection.clamp(0.0, 1.0),
                      );
                      
                      // Distancia del agujero a la línea
                      final distToLine = (agujeroPos - closestPoint).distance;
                      
                      // Si el agujero está cerca de la línea (dentro del umbral), no conectar
                      if (distToLine < umbralDistancia) {
                        hayAgujeroEnLaLinea = true;
                        break;
                      }
                    }
                    
                    // También verificar si el agujero está muy cerca de uno de los extremos
                    final distToP1 = (agujeroPos - p1).distance;
                    final distToP2 = (agujeroPos - p2).distance;
                    
                    // Usar el radio del agujero para determinar si está bloqueando
                    if (distToP1 < umbralDistancia || distToP2 < umbralDistancia) {
                      // Verificar si el agujero está "entre" los píxeles en términos de dirección
                      final dirToHole1 = (agujeroPos - p1);
                      final dirToHole2 = (agujeroPos - p2);
                      final dirLine = lineVector;
                      
                      // Calcular el ángulo entre la línea y la dirección al agujero
                      final cosAngle1 = dirToHole1.distance > 0 && lineLength > 0
                          ? (dirToHole1.dx * dirLine.dx + dirToHole1.dy * dirLine.dy) / 
                            (dirToHole1.distance * lineLength)
                          : 0.0;
                      final cosAngle2 = dirToHole2.distance > 0 && lineLength > 0
                          ? (dirToHole2.dx * -dirLine.dx + dirToHole2.dy * -dirLine.dy) / 
                            (dirToHole2.distance * lineLength)
                          : 0.0;
                      
                      // Si el agujero está en la misma dirección que la línea, está bloqueando
                      // Ser más estricto: reducir el umbral del coseno
                      if (cosAngle1 > 0.5 || cosAngle2 > 0.5) {
                        hayAgujeroEnLaLinea = true;
                        break;
                      }
                    }
                  }
                }
                
                if (hayAgujeroEnLaLinea) {
                  continue; // No conectar estos píxeles, hay un agujero en la línea entre ellos
                }
              }
              
              toProcess.add(j);
            }
          }
        }
        
        // Filtrar solo grupos muy pequeños (letras/números tienen menos píxeles)
        // Reducir el umbral para no excluir líneas finas (el círculo exterior puede tener menos píxeles)
        if (group.length < 100) {
          continue; // Filtrar grupos muy pequeños
        }
        
        // Calcular las dimensiones del grupo (bounding box)
        double minX = group[0].dx, maxX = group[0].dx;
        double minY = group[0].dy, maxY = group[0].dy;
        for (var point in group) {
          if (point.dx < minX) minX = point.dx;
          if (point.dx > maxX) maxX = point.dx;
          if (point.dy < minY) minY = point.dy;
          if (point.dy > maxY) maxY = point.dy;
        }
        final width = maxX - minX;
        final height = maxY - minY;
        final aspectRatio = width > height ? width / height : height / width;
        
        // Filtrar solo grupos muy alargados (letras tienen aspect ratio muy alto)
        // Ser permisivo para no excluir líneas finas que pueden tener aspect ratio moderado
        if (aspectRatio > 4.0) {
          continue; // Filtrar letras muy alargadas
        }
        
        // Calcular el centroide del grupo
        double sumX = 0, sumY = 0;
        for (var point in group) {
          sumX += point.dx;
          sumY += point.dy;
        }
        final centroid = Offset(sumX / group.length, sumY / group.length);
        
        // Calcular el radio promedio desde el centroide
        double avgRadius = 0;
        for (var point in group) {
          avgRadius += (point - centroid).distance;
        }
        avgRadius /= group.length;
        
        // Calcular el radio máximo (distancia máxima desde el centroide)
        double maxRadius = 0;
        for (var point in group) {
          final dist = (point - centroid).distance;
          if (dist > maxRadius) maxRadius = dist;
        }
        
        // Los agujeros grandes tienen:
        // - Radio promedio pequeño (píxeles cerca del centro)
        // - Radio máximo pequeño (tamaño pequeño del agujero)
        // - Muchos píxeles en un área pequeña
        
        // Las líneas circulares tienen:
        // - Radio promedio grande (píxeles distribuidos a lo largo del perímetro)
        // - Radio máximo grande (círculo grande)
        
        // Filtrar agujeros: 
        // 1. Si el radio máximo es pequeño (< 100) pero tiene muchos píxeles (> 500)
        // 2. Si el radio promedio es muy pequeño (< 50) con muchos píxeles
        // 3. Si tiene muchos píxeles (> 700) pero radio promedio pequeño (< 200) - agujeros grandes
        // 4. Si tiene muchos píxeles (> 500) pero radio máximo pequeño (< 200) - agujeros grandes
        if ((maxRadius < 100 && group.length > 500) || 
            (avgRadius < 50 && group.length > 300) ||
            (avgRadius < 200 && group.length > 700) ||
            (maxRadius < 200 && group.length > 500 && avgRadius < 180)) {
          continue; // Filtrar agujeros grandes
        }
        
        // Detectar si el grupo tiene un "cuello" estrecho que conecta dos regiones (dos círculos unidos por un agujero)
        // Usar análisis de densidad local para encontrar regiones de baja densidad
        // Solo aplicar si el grupo es muy grande
        double variance = 0;
        for (var point in group) {
          final dist = (point - centroid).distance;
          variance += (dist - avgRadius) * (dist - avgRadius);
        }
        final stdDev = sqrt(variance / group.length);
        final coefficientOfVariation = avgRadius > 0 ? stdDev / avgRadius : 0;
        
        // Intentar separar si el grupo es grande (más de 5000 píxeles)
        // Y tiene alta variación de radio (coeficiente > 0.25), lo que sugiere dos círculos
        // Esto captura casos donde dos círculos están unidos
        if (group.length > 5000 && coefficientOfVariation > 0.25) {
          // Crear una cuadrícula para analizar la densidad local
          final gridSize = 25.0; // Tamaño de celda de la cuadrícula (más grande para ser más conservador)
          final gridWidth = (width / gridSize).ceil();
          final gridHeight = (height / gridSize).ceil();
          
          // Contar píxeles en cada celda
          final List<List<int>> grid = List.generate(
            gridHeight,
            (_) => List.generate(gridWidth, (_) => 0),
          );
          
          for (var point in group) {
            final gridX = ((point.dx - minX) / gridSize).floor();
            final gridY = ((point.dy - minY) / gridSize).floor();
            if (gridX >= 0 && gridX < gridWidth && gridY >= 0 && gridY < gridHeight) {
              grid[gridY][gridX]++;
            }
          }
          
          // Encontrar celdas con muy poca densidad (posibles "cuellos")
          final List<(int, int)> sparseCells = [];
          final avgCellDensity = group.length / (gridWidth * gridHeight);
          
          for (int y = 0; y < gridHeight; y++) {
            for (int x = 0; x < gridWidth; x++) {
              if (grid[y][x] < avgCellDensity * 0.15 && grid[y][x] > 0) {
                sparseCells.add((x, y));
              }
            }
          }
          
          // Siempre intentar separar grupos grandes usando k-means
          // Inicializar con dos puntos alejados basándose en la distribución de distancias
          final List<Offset> group1 = [];
          final List<Offset> group2 = [];
          
          // Encontrar dos puntos iniciales alejados
          // Usar puntos en extremos opuestos del bounding box
          final List<Offset> sortedByX = List<Offset>.from(group);
          sortedByX.sort((a, b) => a.dx.compareTo(b.dx));
          final leftPoint = sortedByX[sortedByX.length ~/ 4];
          final rightPoint = sortedByX[sortedByX.length * 3 ~/ 4];
          
          // Iterar k-means para separar
          Offset center1 = leftPoint;
          Offset center2 = rightPoint;
          
          for (int iter = 0; iter < 15; iter++) {
            group1.clear();
            group2.clear();
            
            for (var point in group) {
              final dist1 = (point - center1).distance;
              final dist2 = (point - center2).distance;
              if (dist1 < dist2) {
                group1.add(point);
              } else {
                group2.add(point);
              }
            }
            
            if (group1.isEmpty || group2.isEmpty) break;
            
            // Calcular nuevos centros
            double sumX1 = 0, sumY1 = 0;
            for (var p in group1) {
              sumX1 += p.dx;
              sumY1 += p.dy;
            }
            final newCenter1 = Offset(sumX1 / group1.length, sumY1 / group1.length);
            
            double sumX2 = 0, sumY2 = 0;
            for (var p in group2) {
              sumX2 += p.dx;
              sumY2 += p.dy;
            }
            final newCenter2 = Offset(sumX2 / group2.length, sumY2 / group2.length);
            
            // Si los centros no cambian mucho, convergimos
            if ((newCenter1 - center1).distance < 1.0 && (newCenter2 - center2).distance < 1.0) {
              break;
            }
            
            center1 = newCenter1;
            center2 = newCenter2;
          }
          
          // Validar que la separación sea válida
          if (group1.length >= 1000 && group2.length >= 1000) {
            // Calcular radios de cada grupo
            double radius1 = 0, radius2 = 0;
            for (var p in group1) {
              radius1 += (p - center1).distance;
            }
            radius1 /= group1.length;
            
            for (var p in group2) {
              radius2 += (p - center2).distance;
            }
            radius2 /= group2.length;
            
            // Calcular distancia entre centros
            final centerDistance = (center1 - center2).distance;
            
            // Separar solo si:
            // 1. Los radios son significativamente distintos (> 40 píxeles de diferencia)
            // 2. Y los centros están suficientemente separados (> 60 píxeles)
            // Esto evita separar un solo círculo en dos partes
            if ((radius1 - radius2).abs() > 40 && centerDistance > 60) {
              final aspect1 = _calculateAspectRatio(group1);
              final aspect2 = _calculateAspectRatio(group2);
              
              // Verificar que ambos grupos tengan formas razonables
              if (aspect1 < 2.5 && aspect2 < 2.5) {
                filteredGroups.add(group1);
                filteredGroups.add(group2);
                continue;
              }
            }
          }
        }
        
        // Verificar si el grupo podría ser dos círculos juntos por variación de radio
        // (variance, stdDev y coefficientOfVariation ya fueron calculados arriba)
        final List<double> distances = [];
        for (var point in group) {
          final dist = (point - centroid).distance;
          distances.add(dist);
        }
        
        // Si el coeficiente de variación es muy alto (> 0.35) y el grupo es grande, podría ser dos círculos juntos
        // Aumentado el umbral para evitar separar círculos grandes con variación natural
        if (coefficientOfVariation > 0.35 && group.length > 3000) {
          // Encontrar el punto de separación usando k-means simple (2 clusters)
          distances.sort();
          // Usar la mediana como punto de separación inicial
          final medianDist = distances[distances.length ~/ 2];
          
          // Iterar para encontrar mejor separación
          double threshold = medianDist;
          for (int iter = 0; iter < 5; iter++) {
            final List<Offset> innerGroup = [];
            final List<Offset> outerGroup = [];
            
            for (var point in group) {
              final dist = (point - centroid).distance;
              if (dist < threshold) {
                innerGroup.add(point);
              } else {
                outerGroup.add(point);
              }
            }
            
            if (innerGroup.isEmpty || outerGroup.isEmpty) break;
            
            // Calcular nuevos centroides y radios promedio
            double innerSumX = 0, innerSumY = 0;
            for (var p in innerGroup) {
              innerSumX += p.dx;
              innerSumY += p.dy;
            }
            final innerCentroid = Offset(innerSumX / innerGroup.length, innerSumY / innerGroup.length);
            double innerAvgRadius = 0;
            for (var p in innerGroup) {
              innerAvgRadius += (p - innerCentroid).distance;
            }
            innerAvgRadius /= innerGroup.length;
            
            double outerSumX = 0, outerSumY = 0;
            for (var p in outerGroup) {
              outerSumX += p.dx;
              outerSumY += p.dy;
            }
            final outerCentroid = Offset(outerSumX / outerGroup.length, outerSumY / outerGroup.length);
            double outerAvgRadius = 0;
            for (var p in outerGroup) {
              outerAvgRadius += (p - outerCentroid).distance;
            }
            outerAvgRadius /= outerGroup.length;
            
            // Nuevo umbral es el punto medio entre los dos radios
            threshold = (innerAvgRadius + outerAvgRadius) / 2;
          }
          
          // Separar usando el umbral final
          final List<Offset> innerGroup = [];
          final List<Offset> outerGroup = [];
          
          for (var point in group) {
            final dist = (point - centroid).distance;
            if (dist < threshold) {
              innerGroup.add(point);
            } else {
              outerGroup.add(point);
            }
          }
          
          // Solo separar si ambos grupos son suficientemente grandes y tienen radios muy distintos
          // Hacer más estricto para evitar separar círculos grandes
          if (innerGroup.length >= 1000 && outerGroup.length >= 1000) {
            // Verificar que los radios sean realmente distintos
            double innerRadius = 0, outerRadius = 0;
            for (var p in innerGroup) {
              innerRadius += (p - centroid).distance;
            }
            innerRadius /= innerGroup.length;
            for (var p in outerGroup) {
              outerRadius += (p - centroid).distance;
            }
            outerRadius /= outerGroup.length;
            
            // Calcular la diferencia relativa de radios
            final diferenciaAbsoluta = (outerRadius - innerRadius).abs();
            final radioPromedio = (innerRadius + outerRadius) / 2;
            final diferenciaRelativa = diferenciaAbsoluta / radioPromedio;
            
            // Separar solo si:
            // 1. La diferencia absoluta es > 50 píxeles (más estricto que antes)
            // 2. Y la diferencia relativa es > 15% (para evitar separar círculos grandes con pequeñas variaciones)
            if (diferenciaAbsoluta > 50 && diferenciaRelativa > 0.15) {
              filteredGroups.add(innerGroup);
              filteredGroups.add(outerGroup);
              continue;
            }
          }
        }
        
        // Si el grupo es grande, probablemente es una línea circular
        // Si es pequeño pero no muy alargado, también puede ser una línea fina
        filteredGroups.add(group);
      }
      
      if (filteredGroups.isEmpty) {
        return {'pixels': <List<Offset>>[], 'center': null, 'radii': <double>[]};
      }
      
      // Calcular el radio de cada grupo y mantenerlos separados
      final List<double> radii = [];
      double totalSumX = 0, totalSumY = 0;
      int totalPixels = 0;
      
      for (var group in filteredGroups) {
        // Calcular el centroide de este grupo
        double sumX = 0, sumY = 0;
        for (var point in group) {
          sumX += point.dx;
          sumY += point.dy;
        }
        final groupCentroid = Offset(sumX / group.length, sumY / group.length);
        
        // Calcular el radio promedio de este grupo
        double groupAvgRadius = 0;
        for (var point in group) {
          groupAvgRadius += (point - groupCentroid).distance;
        }
        groupAvgRadius /= group.length;
        radii.add(groupAvgRadius);
        
        // Acumular para el centro general
        totalSumX += sumX;
        totalSumY += sumY;
        totalPixels += group.length;
        
      }
      
      // Calcular el centro estimado como el centroide de todos los píxeles
      final estimatedCenter = Offset(totalSumX / totalPixels, totalSumY / totalPixels);
      
      // Ordenar los grupos por radio (de menor a mayor) para que correspondan con las zonas
      final indexedGroups = List.generate(filteredGroups.length, (i) => (i, filteredGroups[i], radii[i]));
      indexedGroups.sort((a, b) => a.$3.compareTo(b.$3));
      
      var sortedGroups = indexedGroups.map((e) => e.$2).toList();
      var sortedRadii = indexedGroups.map((e) => e.$3).toList();
      
      // Unir círculos que son parte del mismo círculo grande
      // Usar la distancia al centro estimado (cruz azul) para determinar si deben unirse
      final mergedGroups = <List<Offset>>[];
      final mergedRadii = <double>[];
      final usedIndices = <int>{};
      
      for (int i = 0; i < sortedGroups.length; i++) {
        if (usedIndices.contains(i)) continue;
        
        final group1 = sortedGroups[i];
        final radius1 = sortedRadii[i];
        
        // Calcular la distancia promedio desde el centro estimado para el grupo 1
        double sumDist1 = 0;
        for (var p in group1) {
          sumDist1 += (p - estimatedCenter).distance;
        }
        final avgDistFromCenter1 = sumDist1 / group1.length;
        
        // Buscar si hay otro círculo con distancia similar al centro pero radio muy diferente
        bool merged = false;
        for (int j = i + 1; j < sortedGroups.length; j++) {
          if (usedIndices.contains(j)) continue;
          
          final group2 = sortedGroups[j];
          final radius2 = sortedRadii[j];
          
          // Calcular la distancia promedio desde el centro estimado para el grupo 2
          double sumDist2 = 0;
          for (var p in group2) {
            sumDist2 += (p - estimatedCenter).distance;
          }
          final avgDistFromCenter2 = sumDist2 / group2.length;
          
          // Calcular diferencia en distancia al centro
          final diferenciaDistancia = (avgDistFromCenter1 - avgDistFromCenter2).abs();
          
          // Si las distancias al centro son similares (dentro de 30 píxeles)
          // y uno es mucho más grande que el otro, probablemente son parte del mismo círculo
          if (diferenciaDistancia < 30) {
            final radioMayor = radius1 > radius2 ? radius1 : radius2;
            final radioMenor = radius1 < radius2 ? radius1 : radius2;
            final distanciaMayor = avgDistFromCenter1 > avgDistFromCenter2 ? avgDistFromCenter1 : avgDistFromCenter2;
            final distanciaMenor = avgDistFromCenter1 < avgDistFromCenter2 ? avgDistFromCenter1 : avgDistFromCenter2;
            
            // Si la diferencia de radio es grande (> 100 píxeles) y el menor es pequeño (< 100 píxeles)
            // Y las distancias al centro son similares, unirlos
            if (radioMayor - radioMenor > 100 && radioMenor < 100 && distanciaMayor - distanciaMenor < 30) {
              // Unir los grupos (usar el más grande)
              final grupoUnido = radius1 > radius2 ? group1 : group2;
              final radioUnido = radius1 > radius2 ? radius1 : radius2;
              
              // Agregar píxeles del grupo más pequeño al grande
              final grupoPequeno = radius1 < radius2 ? group1 : group2;
              final grupoFinal = List<Offset>.from(grupoUnido);
              grupoFinal.addAll(grupoPequeno);
              
              mergedGroups.add(grupoFinal);
              mergedRadii.add(radioUnido);
              usedIndices.add(i);
              usedIndices.add(j);
              merged = true;
              break;
            }
          }
        }
        
        if (!merged) {
          mergedGroups.add(group1);
          mergedRadii.add(radius1);
          usedIndices.add(i);
        }
      }
      
      // Reordenar por radio después de la unión
      final finalIndexed = List.generate(mergedGroups.length, (i) => (i, mergedGroups[i], mergedRadii[i]));
      finalIndexed.sort((a, b) => a.$3.compareTo(b.$3));
      
      var finalGroups = finalIndexed.map((e) => e.$2).toList();
      var finalRadii = finalIndexed.map((e) => e.$3).toList();
      
      // Retornar los grupos sin completar (usar los detectados directamente)
      // Por el momento NO completar los círculos - todos se tratan igual
      return {
        'pixels': finalGroups,
        'center': estimatedCenter,
        'radii': finalRadii,
      };
    } catch (e, stackTrace) {
      debugPrint('Error al detectar líneas negras: $e');
      debugPrint('Stack trace: $stackTrace');
      return {'pixels': <List<Offset>>[], 'center': null, 'radii': <double>[]};
    }
  }

  /// Genera un círculo completo desde el centro con el radio dado
  // ignore: unused_element
  List<Offset> _generarCirculoCompleto(
    Offset center,
    double radius,
    int imageWidth,
    int imageHeight,
  ) {
    final circlePixels = <Offset>[];
    
    // Generar puntos alrededor del círculo completo
    // Usar 720 puntos (2 por grado) para tener un círculo suave
    final numPoints = 720;
    final angleStep = 2 * pi / numPoints;
    
    for (int i = 0; i < numPoints; i++) {
      final angle = i * angleStep;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      
      // Redondear a píxeles enteros
      final pixelX = x.round();
      final pixelY = y.round();
      
      // Verificar que esté dentro de los límites de la imagen
      if (pixelX >= 0 && pixelX < imageWidth && pixelY >= 0 && pixelY < imageHeight) {
        circlePixels.add(Offset(pixelX.toDouble(), pixelY.toDouble()));
      }
    }
    
    return circlePixels;
  }

  /// Completa un círculo incompleto usando el centro y radio estimados
  /// Rellena los huecos en la trayectoria del círculo
  // ignore: unused_element
  List<Offset> _completarCirculo(
    List<Offset> pixelsDetectados,
    Offset center,
    double radius,
    int imageWidth,
    int imageHeight,
  ) {
    final completedPixels = <Offset>[];
    final existingPixels = <String>{};
    
    // Agregar los píxeles ya detectados
    for (var pixel in pixelsDetectados) {
      final key = '${pixel.dx.toInt()},${pixel.dy.toInt()}';
      existingPixels.add(key);
      completedPixels.add(pixel);
    }
    
    // Calcular el perímetro esperado del círculo
    final perimetroEsperado = 2 * pi * radius;
    // Calcular qué porcentaje del círculo está detectado
    final porcentajeDetectado = pixelsDetectados.length / perimetroEsperado;
    
    // Para círculos grandes (radio > 300), completar si está menos del 95% completo
    // Para círculos pequeños, completar si está menos del 90% completo
    final umbralCompletar = radius > 300 ? 0.95 : 0.90;
    
    if (porcentajeDetectado < umbralCompletar) {
      // Generar puntos alrededor del círculo completo
      // Usar más puntos para círculos grandes (más precisión)
      final numPoints = radius > 300 ? 720 : 360; // 2 puntos por grado para círculos grandes
      final angleStep = 2 * pi / numPoints;
      
      for (int i = 0; i < numPoints; i++) {
        final angle = i * angleStep;
        final x = center.dx + radius * cos(angle);
        final y = center.dy + radius * sin(angle);
        
        // Redondear a píxeles enteros
        final pixelX = x.round();
        final pixelY = y.round();
        
        // Verificar que esté dentro de los límites de la imagen
        if (pixelX >= 0 && pixelX < imageWidth && pixelY >= 0 && pixelY < imageHeight) {
          final key = '$pixelX,$pixelY';
          
          // Si el píxel no está ya en la lista, verificar si debe agregarse
          if (!existingPixels.contains(key)) {
            // Verificar si el punto está en el círculo teórico
            // (distancia al círculo ideal dentro de un umbral)
            final distanciaAlCirculo = (Offset(pixelX.toDouble(), pixelY.toDouble()) - center).distance;
            final diferenciaRadio = (distanciaAlCirculo - radius).abs();
            
            // Umbral más permisivo para círculos grandes
            final umbralRadio = radius > 300 ? 3.0 : 2.0;
            final enElCirculo = diferenciaRadio <= umbralRadio;
            
            // Para círculos grandes, también verificar si está cerca de algún píxel detectado
            // pero ser más permisivo
            bool cercaDeDetectado = false;
            if (radius > 300) {
              // Para círculos grandes, usar distancia mayor
              final distanciaMaxima = 8.0;
              for (var detected in pixelsDetectados) {
                final distancia = (Offset(pixelX.toDouble(), pixelY.toDouble()) - detected).distance;
                if (distancia <= distanciaMaxima) {
                  cercaDeDetectado = true;
                  break;
                }
              }
            } else {
              // Para círculos pequeños, verificar cercanía más estricta
              final distanciaMaxima = 4.0;
              for (var detected in pixelsDetectados) {
                final distancia = (Offset(pixelX.toDouble(), pixelY.toDouble()) - detected).distance;
                if (distancia <= distanciaMaxima) {
                  cercaDeDetectado = true;
                  break;
                }
              }
            }
            
            // Agregar si está en el círculo teórico Y (está cerca de detectado O el círculo está bastante completo)
            if (enElCirculo && (cercaDeDetectado || porcentajeDetectado > 0.6)) {
              existingPixels.add(key);
              completedPixels.add(Offset(pixelX.toDouble(), pixelY.toDouble()));
            }
          }
        }
      }
    }
    
    return completedPixels;
  }

  /// Calcula el aspect ratio de un grupo de puntos
  double _calculateAspectRatio(List<Offset> group) {
    if (group.isEmpty) return 1.0;
    
    double minX = group[0].dx, maxX = group[0].dx;
    double minY = group[0].dy, maxY = group[0].dy;
    for (var point in group) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }
    final width = maxX - minX;
    final height = maxY - minY;
    return width > height ? width / height : height / width;
  }

  /// Flood fill para encontrar regiones negras conectadas
  // ignore: unused_element
  List<Point<int>> _floodFillBlack(
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
      final intensity = (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b).round();
      if (intensity >= 128) continue; // No es negro

      visited[y][x] = true;
      region.add(point);

      // 8-conectividad para capturar mejor las líneas
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

  /// Detecta agujeros en la imagen recortada
  /// Detecta agujeros en la zona negra (zonas 7-10)
  /// Paso 1: Mostrar la diana en blanco y negro centrada en la zona negra
  Future<void> _detectarZonaNegra() async {
    if (_croppedImage == null || _dianaCenter == null || _dianaRadius == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona y recorta una imagen primero')),
    );
      return;
  }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Cargar imagen
      final bytes = await _croppedImage!.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        throw Exception('No se pudo decodificar la imagen');
      }

      // Aplicar filtro según el parámetro de desenfoque
      img.Image processedImage;
      if (_blurRadius < 0) {
        // Sharpening
        processedImage = await _applySharpeningImage(originalImage, _blurRadius.abs());
      } else if (_blurRadius > 0) {
        processedImage = img.gaussianBlur(originalImage, radius: _blurRadius.round());
      } else {
        processedImage = originalImage;
      }

      // Para zona negra: aplicar contraste fuerte para resaltar las líneas blancas
      processedImage = _applyContrast(processedImage, 2.0); // Aumentar contraste 2x
      
      // Para zona negra: usar umbral manual ajustable
      // El umbral _threshold (0.1-2.0) se convierte a 180-255
      // Para zona negra, usar un umbral más alto para capturar solo las líneas más blancas
      // Mapeo: 0.1→180, 0.9→247.5, 2.0→255
      final thresholdValue = (180 + (_threshold * 75)).round().clamp(180, 255); // Rango 180-255 (más estricto)
      
      // Convertir a binario usando el umbral manual
      var binaryImage = _convertToBinaryManual(processedImage, thresholdValue);
      
      // Aplicar limpieza morfológica múltiple para eliminar ruido
      binaryImage = _cleanBinaryImage(binaryImage);
      binaryImage = _cleanBinaryImage(binaryImage); // Segunda pasada para mejor limpieza
      
      // Guardar imagen binaria
      final Uint8List encodedBytes = img.encodeJpg(binaryImage, quality: 100);
      final tempDir = await getTemporaryDirectory();
      final binaryFilePath = '${tempDir.path}/binary_diana_negra_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(binaryFilePath).writeAsBytes(encodedBytes);
      hole_service.HoleDetectionService.setBinaryImageFile(File(binaryFilePath));

    setState(() {
        _isProcessing = false;
        _binaryImage = hole_service.HoleDetectionService.getBinaryImageFile();
        // Mostrar la imagen en blanco y negro automáticamente
        _showBinaryImage = true;
        // No mostrar círculos todavía (solo imagen B/N)
        _showCircles = false;
        // Limpiar disparos detectados (aún no detectamos)
        _disparosDetectados = [];
        _hasDetected = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zona negra: Imagen en blanco y negro generada. Ajusta el umbral para resaltar las líneas blancas.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar imagen binaria: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Convierte imagen a binario usando un umbral manual (para zona negra)
  img.Image _convertToBinaryManual(img.Image image, int threshold) {
    final binaryImage = img.copyResize(
      image,
      width: image.width,
      height: image.height,
    );
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final intensity = (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b).round();
        
        // Para zona negra: píxeles claros (>= umbral) → blanco (líneas blancas)
        // Píxeles oscuros (< umbral) → negro (fondo negro)
        if (intensity >= threshold) {
          binaryImage.setPixel(x, y, img.ColorRgb8(255, 255, 255)); // Blanco = líneas
        } else {
          binaryImage.setPixel(x, y, img.ColorRgb8(0, 0, 0)); // Negro = fondo
        }
      }
    }
    
    return binaryImage;
  }

  /// Convierte imagen a binario para zona blanca (líneas negras sobre fondo blanco)
  /// Píxeles oscuros (< umbral) → negro (líneas negras)
  /// Píxeles claros (>= umbral) → blanco (fondo blanco)
  img.Image _convertToBinaryForWhiteZone(img.Image image, int threshold) {
    final binaryImage = img.copyResize(
      image,
      width: image.width,
      height: image.height,
    );
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final intensity = (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b).round();
        
        // Para zona blanca: píxeles oscuros (< umbral) → negro (líneas negras)
        // Píxeles claros (>= umbral) → blanco (fondo blanco)
        if (intensity < threshold) {
          binaryImage.setPixel(x, y, img.ColorRgb8(0, 0, 0)); // Negro (líneas)
        } else {
          binaryImage.setPixel(x, y, img.ColorRgb8(255, 255, 255)); // Blanco (fondo)
        }
      }
    }
    
    return binaryImage;
  }

  /// Aplica contraste a la imagen para resaltar las líneas blancas
  img.Image _applyContrast(img.Image image, double contrast) {
    final result = img.copyResize(image, width: image.width, height: image.height);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Aplicar contraste: nuevo = (pixel - 128) * contrast + 128
        final r = ((pixel.r - 128) * contrast + 128).clamp(0, 255).round();
        final g = ((pixel.g - 128) * contrast + 128).clamp(0, 255).round();
        final b = ((pixel.b - 128) * contrast + 128).clamp(0, 255).round();
        result.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }
    return result;
  }

  /// Limpia la imagen binaria eliminando ruido pequeño
  img.Image _cleanBinaryImage(img.Image image) {
    final result = img.copyResize(image, width: image.width, height: image.height);
    
    // Aplicar filtro de mediana 3x3 para eliminar ruido
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        final List<int> neighbors = [];
        // Recopilar vecinos 3x3
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final pixel = image.getPixel(x + dx, y + dy);
            neighbors.add(pixel.r.toInt()); // En binario, r=g=b
          }
        }
        // Ordenar y tomar la mediana
        neighbors.sort();
        final median = neighbors[4]; // Mediana de 9 valores (índice 4)
        
        // Eliminar píxeles aislados: si un píxel blanco tiene menos de 2 vecinos blancos, convertirlo a negro
        final centerPixel = image.getPixel(x, y).r.toInt();
        if (centerPixel == 255) { // Si es blanco
          int whiteNeighbors = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              if (image.getPixel(x + dx, y + dy).r.toInt() == 255) {
                whiteNeighbors++;
              }
            }
          }
          // Si tiene menos de 2 vecinos blancos, es ruido
          if (whiteNeighbors < 2) {
            result.setPixel(x, y, img.ColorRgb8(0, 0, 0)); // Convertir a negro
          } else {
            result.setPixel(x, y, img.ColorRgb8(median, median, median));
          }
        } else {
          result.setPixel(x, y, img.ColorRgb8(median, median, median));
        }
      }
    }
    
    return result;
  }

  /// Aplica sharpening a la imagen (helper method)
  Future<img.Image> _applySharpeningImage(img.Image image, double strength) async {
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

  /// Detecta agujeros en la zona blanca (zonas 1-6)
  /// Detecta agujeros en la zona blanca (zonas 1-6)
  /// Paso 1: Mostrar la diana en blanco y negro centrada en la zona blanca
  Future<void> _detectarZonaBlanca() async {
    if (_croppedImage == null || _dianaCenter == null || _dianaRadius == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona y recorta una imagen primero')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Cargar imagen
      final bytes = await _croppedImage!.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        throw Exception('No se pudo decodificar la imagen');
      }

      // Aplicar filtro según el parámetro de desenfoque
      img.Image processedImage;
      if (_blurRadius < 0) {
        // Sharpening
        processedImage = await _applySharpeningImage(originalImage, _blurRadius.abs());
      } else if (_blurRadius > 0) {
        processedImage = img.gaussianBlur(originalImage, radius: _blurRadius.round());
      } else {
        processedImage = originalImage;
      }

      // Para zona blanca: aplicar contraste fuerte para resaltar las líneas negras
      processedImage = _applyContrast(processedImage, 2.0); // Aumentar contraste 2x
      
      // Para zona blanca: usar umbral manual ajustable
      // El umbral _threshold (0.1-2.0) se convierte a 180-255
      // Para zona blanca, usar un umbral más alto para capturar solo las líneas negras más definidas
      // Mapeo: 0.1→180, 0.9→247.5, 2.0→255
      final thresholdValue = (180 + (_threshold * 75)).round().clamp(180, 255); // Rango 180-255 (más estricto)
      
      // Convertir a binario usando el umbral manual
      var binaryImage = _convertToBinaryForWhiteZone(processedImage, thresholdValue);
      
      // Aplicar limpieza morfológica múltiple para eliminar ruido
      binaryImage = _cleanBinaryImage(binaryImage);
      binaryImage = _cleanBinaryImage(binaryImage); // Segunda pasada para mejor limpieza
      
      // Guardar imagen binaria
      final Uint8List encodedBytes = img.encodeJpg(binaryImage, quality: 100);
      final tempDir = await getTemporaryDirectory();
      final binaryFilePath = '${tempDir.path}/binary_diana_blanca_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(binaryFilePath).writeAsBytes(encodedBytes);
      hole_service.HoleDetectionService.setBinaryImageFile(File(binaryFilePath));

      // Detectar líneas negras (círculos) en la imagen binaria
      final binaryImageFile = hole_service.HoleDetectionService.getBinaryImageFile();
      Map<String, dynamic>? lineResult;
      if (binaryImageFile != null) {
        lineResult = await _detectarLineasNegras(
          binaryImageFile,
          agujeros: null, // No hay agujeros detectados todavía
        );
      }

      setState(() {
        _isProcessing = false;
        _binaryImage = binaryImageFile;
        // Mostrar la imagen en blanco y negro automáticamente
        _showBinaryImage = true;
        // Mostrar círculos en verde
        _showCircles = true;
        // Limpiar disparos detectados (aún no detectamos)
        _disparosDetectados = [];
        _hasDetected = false;
        // Guardar los círculos detectados
        if (lineResult != null) {
          _detectedCirclePixels = lineResult['pixels'] as List<List<Offset>>?;
          _detectedCenter = lineResult['center'] as Offset?;
          _detectedLineRadii = lineResult['radii'] as List<double>?;
          _currentCircleIndex = null; // Mostrar todos los círculos
        }
      });

      if (mounted) {
        final numCircles = lineResult != null && lineResult['pixels'] != null 
            ? (lineResult['pixels'] as List).length 
            : 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zona blanca: $numCircles círculos detectados y dibujados en verde.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar imagen binaria: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _detectarAgujeros({bool showResults = true}) async {
    if (_croppedImage == null || _dianaCenter == null || _dianaRadius == null) {
      if (showResults) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, selecciona y recorta una imagen primero')),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _disparosDetectados = [];
      _hasDetected = false;
    });

    try {
      // Convertir radios a áreas: área = π * radio²
      final minHoleArea = (pi * _minHoleRadius * _minHoleRadius).round();
      final maxHoleArea = (pi * _maxHoleRadius * _maxHoleRadius).round();
      
      // Si no tenemos radios detectados, generar la imagen binaria primero para detectarlos
      List<double>? normalizedRadii;
      if (_detectedLineRadii == null || _detectedLineRadii!.isEmpty) {
        // Generar imagen binaria temporalmente para detectar círculos
        await _generarImagenBinaria();
        final binaryImage = hole_service.HoleDetectionService.getBinaryImageFile();
        if (binaryImage != null) {
          final lineResult = await _detectarLineasNegras(binaryImage);
          if (lineResult['radii'] != null) {
            final radii = lineResult['radii'] as List<double>;
            // Normalizar los radios dividiéndolos por el radio de la diana
            normalizedRadii = radii.map((r) => r / _dianaRadius!).toList();
          }
        }
          } else {
        // Usar los radios ya detectados, normalizándolos
        normalizedRadii = _detectedLineRadii!.map((r) => r / _dianaRadius!).toList();
      }
      
      final disparos = await _detectionService.detectHoles(
        imageFile: _croppedImage!,
        dianaCenter: _dianaCenter!,
        dianaRadius: _dianaRadius!,
        minHoleSize: minHoleArea,
        maxHoleSize: maxHoleArea,
        blurRadius: _blurRadius,
        detectInLightZone: false, // Detectar todo (incluyendo zona negra central)
        shotEstimationFactor: _shotEstimationFactor,
        detectedCircleRadii: normalizedRadii, // Pasar los radios normalizados
      );

      // Obtener imagen binaria si está disponible
      final binaryImage = hole_service.HoleDetectionService.getBinaryImageFile();
      
      // Detectar líneas negras en la imagen binaria (si no se detectaron antes)
      Map<String, dynamic>? lineResult;
      if (binaryImage != null && (_detectedLineRadii == null || _detectedLineRadii!.isEmpty)) {
        lineResult = await _detectarLineasNegras(
          binaryImage,
          agujeros: disparos.isNotEmpty ? disparos : null,
        );
      }
      
      setState(() {
        _disparosDetectados = disparos;
        _hasDetected = true;
        _isProcessing = false;
        _binaryImage = binaryImage;
        if (lineResult != null) {
          _detectedCirclePixels = lineResult['pixels'] as List<List<Offset>>?;
          _detectedCenter = lineResult['center'] as Offset?;
          _detectedLineRadii = lineResult['radii'] as List<double>?;
        }
      });

      // Mostrar resultados solo si se solicita
      // Comentado temporalmente durante las pruebas
      // if (showResults && mounted) {
      //   _mostrarResultados();
      // }
      
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      
      if (mounted && showResults) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en detección: $e')),
        );
      }
    }
  }

  /// Programa una detección automática con delay (para ajustes dinámicos)
  void _scheduleAutoDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer(const Duration(milliseconds: 500), () {
      if (_hasDetected) {
        _detectarAgujeros(showResults: false);
      }
    });
  }

  /// Actualiza un parámetro y programa detección automática
  void _updateParameter<T>(T Function() getter, void Function(T) setter, T value, {bool isBlur = false}) {
    setter(value);
    // Asegurar que min <= max para radios
    if (_minHoleRadius > _maxHoleRadius) {
      _maxHoleRadius = _minHoleRadius;
    }
    // Actualizar controllers de texto
    _thresholdController.text = _threshold.toStringAsFixed(2);
    _minHoleRadiusController.text = _minHoleRadius.toStringAsFixed(1);
    _maxHoleRadiusController.text = _maxHoleRadius.toStringAsFixed(1);
    _blurRadiusController.text = _blurRadius.toStringAsFixed(1);
    _shotEstimationFactorController.text = _shotEstimationFactor.toStringAsFixed(2);
    setState(() {});
    
    // Si cambió el blur y hay imagen binaria, regenerar y detectar líneas
    if (isBlur && _binaryImage != null && _croppedImage != null && _dianaCenter != null && _dianaRadius != null) {
      _generarImagenBinaria();
    }
    
    if (_hasDetected) {
      _scheduleAutoDetection();
    }
  }

  /// Widget helper para crear un slider con campo de texto
  Widget _buildSliderWithTextField({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Function(double) onChanged,
    required String Function(double) formatValue,
    required double? Function(String) parseValue,
    required TextEditingController controller,
    String? suffix,
  }) {
    // Actualizar el controller cuando el valor cambie externamente
    if (controller.text != formatValue(value)) {
      controller.text = formatValue(value);
    }
    
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text('$label${suffix != null ? ': $suffix' : ''}'),
        ),
        Expanded(
          flex: 4,
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (newValue) {
              onChanged(newValue);
              controller.text = formatValue(newValue);
            },
          ),
        ),
        Expanded(
          flex: 1,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onSubmitted: (text) {
              final parsed = parseValue(text);
              if (parsed != null && parsed >= min && parsed <= max) {
                onChanged(parsed);
          } else {
                controller.text = formatValue(value);
              }
            },
            onEditingComplete: () {
              final parsed = parseValue(controller.text);
              if (parsed != null && parsed >= min && parsed <= max) {
                onChanged(parsed);
              } else {
                controller.text = formatValue(value);
              }
            },
          ),
        ),
      ],
    );
  }

  /// Muestra un diálogo con los resultados
  // ignore: unused_element
  void _mostrarResultados() {
    final totalPuntos = _disparosDetectados.fold<int>(
      0, 
      (sum, disparo) => sum + disparo.puntuacion.round(),
    );
    
    final promedio = _disparosDetectados.isNotEmpty 
        ? (totalPuntos / _disparosDetectados.length).round()
        : 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resultados de Detección'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agujeros detectados: ${_disparosDetectados.length}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Puntuación total: $totalPuntos'),
              Text('Promedio: $promedio'),
              const SizedBox(height: 16),
              const Text('Detalles:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._disparosDetectados.take(10).map((d) => 
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'Disparo ${d.numero}: ${d.puntuacion.round()} pts '
                    '(${d.x.toStringAsFixed(2)}, ${d.y.toStringAsFixed(2)})'
                    '${d.esMosca ? " 🎯" : ""}',
                  ),
                ),
              ),
              if (_disparosDetectados.length > 10)
                Text('... y ${_disparosDetectados.length - 10} más'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detección Automática de Agujeros'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          if (_croppedImage != null) ...[
            // Botón para detectar zona blanca
            IconButton(
              icon: const Icon(Icons.brightness_1),
              onPressed: _isProcessing ? null : _detectarZonaBlanca,
              tooltip: 'Detectar Zona Blanca',
              color: Colors.white,
            ),
            // Botón para detectar zona negra
            IconButton(
              icon: const Icon(Icons.circle),
              onPressed: _isProcessing ? null : _detectarZonaNegra,
              tooltip: 'Detectar Zona Negra',
              color: Colors.black87,
            ),
            // Botón para mostrar/ocultar imagen en blanco y negro (solo visible después de detectar)
            if (_hasDetected) ...[
              IconButton(
                icon: Icon(_showBinaryImage ? Icons.image : Icons.filter_b_and_w),
                onPressed: () {
                  setState(() {
                    _showBinaryImage = !_showBinaryImage;
                  });
                },
                tooltip: _showBinaryImage ? 'Ver imagen original' : 'Ver imagen B/N',
              ),
              // Botón para mostrar/ocultar círculos
              IconButton(
                icon: Icon(_showCircles ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _showCircles = !_showCircles;
                    if (!_showCircles) {
                      _currentCircleIndex = null; // Reset al ocultar
                    }
                  });
                },
                tooltip: _showCircles ? 'Ocultar círculos' : 'Mostrar círculos',
              ),
            ],
            // Botón para navegar círculos uno a uno
            if (_showCircles && _detectedCirclePixels != null && _detectedCirclePixels!.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: () {
                  setState(() {
                    if (_currentCircleIndex == null) {
                      _currentCircleIndex = _detectedCirclePixels!.length - 1;
                    } else {
                      _currentCircleIndex = (_currentCircleIndex! - 1) % _detectedCirclePixels!.length;
                    }
                    _logCircleInfo();
                  });
                },
                tooltip: 'Círculo anterior',
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: () {
                  setState(() {
                    if (_currentCircleIndex == null) {
                      _currentCircleIndex = 0;
                    } else {
                      _currentCircleIndex = (_currentCircleIndex! + 1) % _detectedCirclePixels!.length;
                    }
                    _logCircleInfo();
                  });
                },
                tooltip: 'Siguiente círculo',
              ),
              IconButton(
                icon: const Icon(Icons.view_module),
                onPressed: () {
                  setState(() {
                    _currentCircleIndex = null; // Mostrar todos
                    if (_detectedCirclePixels != null) {
                      debugPrint('═══════════════════════════════════════');
                      debugPrint('MOSTRANDO TODOS LOS CÍRCULOS (${_detectedCirclePixels!.length})');
                      debugPrint('═══════════════════════════════════════');
                    }
                  });
                },
                tooltip: 'Mostrar todos',
              ),
            ],
            // Botón para ajustes
            IconButton(
              icon: Icon(_showAdjustments ? Icons.expand_less : Icons.tune),
              onPressed: () {
                setState(() {
                  _showAdjustments = !_showAdjustments;
                });
              },
              tooltip: _showAdjustments ? 'Ocultar ajustes' : 'Mostrar ajustes',
            ),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              // Botones de selección
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
              ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Tomar Foto'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galería'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
              
              // Panel de ajustes dinámicos
              if (_showAdjustments && _croppedImage != null)
                Flexible(
                  flex: 0,
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: (constraints.maxHeight - 200).clamp(150.0, 250.0),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        const Text(
                          'Ajustes en Tiempo Real',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        // Umbral
                        _buildSliderWithTextField(
                          label: 'Umbral',
                          value: _threshold,
                          min: 0.1,
                          max: 2.0,
                          divisions: 190,
                          onChanged: (value) {
                            _updateParameter(() => _threshold, (v) => _threshold = v, value);
                          },
                          formatValue: (v) => v.toStringAsFixed(2),
                          parseValue: (text) => double.tryParse(text),
                          controller: _thresholdController,
                        ),
                        const SizedBox(height: 8),
                        // Radio mínimo
                        _buildSliderWithTextField(
                          label: 'Radio Min',
                          value: _minHoleRadius,
                          min: 1,
                          max: 25,
                          divisions: 240,
                          onChanged: (value) {
                            _updateParameter(() => _minHoleRadius, (v) => _minHoleRadius = v, value);
                          },
                          formatValue: (v) => v.toStringAsFixed(1),
                          parseValue: (text) => double.tryParse(text),
                          controller: _minHoleRadiusController,
                          suffix: 'px',
                        ),
                        const SizedBox(height: 8),
                        // Radio máximo
                        _buildSliderWithTextField(
                          label: 'Radio Max',
                          value: _maxHoleRadius,
                          min: 1,
                          max: 150,
                          divisions: 1490,
                          onChanged: (value) {
                            _updateParameter(() => _maxHoleRadius, (v) => _maxHoleRadius = v, value);
                          },
                          formatValue: (v) => v.toStringAsFixed(1),
                          parseValue: (text) => double.tryParse(text),
                          controller: _maxHoleRadiusController,
                          suffix: 'px',
                        ),
                        const SizedBox(height: 8),
                        // Desenfoque Detección (permite valores negativos para sharpening)
                        _buildSliderWithTextField(
                          label: 'Desenfoque Detección',
                          value: _blurRadius,
                          min: -5.0,
                          max: 10.0,
                          divisions: 150,
                          onChanged: (value) {
                            _updateParameter(() => _blurRadius, (v) => _blurRadius = v, value, isBlur: true);
                          },
                          formatValue: (v) => v.toStringAsFixed(1),
                          parseValue: (text) => double.tryParse(text),
                          controller: _blurRadiusController,
                        ),
                        const SizedBox(height: 8),
                        // Factor de estimación de disparos
                        _buildSliderWithTextField(
                          label: 'Factor Estimación',
                          value: _shotEstimationFactor,
                          min: 0.1,
                          max: 3.0,
                          divisions: 290,
                          onChanged: (value) {
                            _updateParameter(() => _shotEstimationFactor, (v) => _shotEstimationFactor = v, value);
                          },
                          formatValue: (v) => v.toStringAsFixed(2),
                          parseValue: (text) => double.tryParse(text),
                          controller: _shotEstimationFactorController,
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              
              // Imagen y detección
              Expanded(
                child: _croppedImage == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 80, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Selecciona una imagen de la diana',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Podrás recortar la diana seleccionando las 4 esquinas',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // Imagen recortada o binaria según el toggle
                          Image.file(
                            _showBinaryImage && _binaryImage != null ? _binaryImage! : _croppedImage!,
                            fit: BoxFit.contain,
                          ),
                          
                          // Overlay con círculos de la diana
                          if (_showCircles && _dianaCenter != null && _dianaRadius != null && _imageSize != null)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: TargetZonesPainter(
                                  currentCircleIndex: _currentCircleIndex,
                                  dianaCenter: _dianaCenter!,
                                  dianaRadius: _dianaRadius!,
                                  imageSize: _imageSize!,
                                  containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                                  detectedCirclePixels: _detectedCirclePixels,
                                  detectedCenter: _detectedCenter,
                                  binaryImageFile: _binaryImage,
                                ),
                              ),
                            ),
                          
                          // Overlay con agujeros detectados
                          if (_hasDetected && _dianaCenter != null && _dianaRadius != null && _imageSize != null)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: HolesPainter(
                                  disparos: _disparosDetectados,
                                  dianaCenter: _dianaCenter!,
                                  dianaRadius: _dianaRadius!,
                                  imageSize: _imageSize!,
                                  containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                                ),
                              ),
                            ),
                          
                          // Indicador de procesamiento
                          if (_isProcessing)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(color: Colors.white),
                                    SizedBox(height: 16),
                                    Text(
                                      'Detectando agujeros...',
                                      style: TextStyle(color: Colors.white, fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ),
          
              // Botón de detección y resultados
              if (_croppedImage != null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Ocultar el botón de detectar agujeros - ahora se usa el botón de ZONA BLANCA
                      // Solo mostrar si ya se ha detectado (para redetectar)
                      if (_hasDetected)
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _detectarAgujeros,
                          icon: const Icon(Icons.search),
                          label: const Text('Redetectar Agujeros'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      if (_hasDetected) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Text(
                                'Agujeros: ${_disparosDetectados.length}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Total: ${_disparosDetectados.fold<int>(0, (sum, d) => sum + d.puntuacion.round())} pts',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Pantalla para recortar la diana seleccionando las 4 esquinas
class CropTargetScreen extends StatefulWidget {
  final File imageFile;

  const CropTargetScreen({super.key, required this.imageFile});

  @override
  State<CropTargetScreen> createState() => _CropTargetScreenState();
}

class _CropTargetScreenState extends State<CropTargetScreen> {
  final GlobalKey _imageKey = GlobalKey();
  bool _isLoading = false; 
  late Offset _tl, _tr, _bl, _br; 
  bool _isLayoutCalculated = false;
  bool _autoDetected = false; // Indica si se detectaron esquinas automáticamente
  List<Offset>? _imageCorners; // Coordenadas de imagen original (para recalcular cuando cambia el tamaño)
  // ignore: unused_field
  img.ColorRgb8? _selectedColor; // Color seleccionado por el usuario
  bool _waitingForColorSelection = false; // Indica si estamos esperando selección de color
  // Color por defecto para detección automática de esquinas (R:247 G:28 B:108)
  static final img.ColorRgb8 _defaultCornerColor = img.ColorRgb8(247, 28, 108);
  Offset? _cursorPosition; // Posición del cursor (cruz)
  img.ColorRgb8? _currentColor; // Color actual bajo el cursor
  int _colorTolerance = 50; // Tolerancia de color (0-100)
  // ignore: unused_field
  String? _debugInfo; // Información de debug para mostrar en pantalla
  bool _colorLocked = false; // Indica si el color está fijado (después de hacer click)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateInitialLayout());
  }

  void _calculateInitialLayout() async {
    if (!mounted) return;
    
      setState(() {
        _isLoading = true;
      });

    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || renderBox.size.isEmpty) {
      if (mounted) {
        setState(() {
          _isLayoutCalculated = false;
          _isLoading = false;
        });
      }
      return;
    }
    
    final size = renderBox.size;
    
    try {
      final Uint8List bytes = await widget.imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);
      
      int actualImageWidth = originalImage?.width ?? 1;
      int actualImageHeight = originalImage?.height ?? 1;

      // Calcular factor de escala
      final double ratioX = size.width / actualImageWidth;
      final double ratioY = size.height / actualImageHeight;
      final double scaleFactor = min(ratioX, ratioY);
      
      final double displayedWidth = actualImageWidth * scaleFactor;
      final double displayedHeight = actualImageHeight * scaleFactor;

      final double horizontalOffset = (size.width - displayedWidth) / 2;
      final double verticalOffset = (size.height - displayedHeight) / 2;

      // Intentar detectar automáticamente las esquinas con el color por defecto
      if (originalImage != null) {
        try {
          await _detectCornersWithColor(
            _defaultCornerColor,
            size,
            actualImageWidth,
            actualImageHeight,
            _colorTolerance,
          );
          // Si la detección fue exitosa, _detectCornersWithColor ya actualiza el estado
          return;
        } catch (e) {
          // Si falla la detección automática, usar puntos iniciales por defecto
          debugPrint('Detección automática fallida, usando puntos por defecto: $e');
        }
      }
      
      // Puntos iniciales (márgenes del 10%) si la detección automática falla
      final tl = Offset(horizontalOffset + displayedWidth * 0.1, verticalOffset + displayedHeight * 0.1);
      final tr = Offset(horizontalOffset + displayedWidth * 0.9, verticalOffset + displayedHeight * 0.1);
      final bl = Offset(horizontalOffset + displayedWidth * 0.1, verticalOffset + displayedHeight * 0.9);
      final br = Offset(horizontalOffset + displayedWidth * 0.9, verticalOffset + displayedHeight * 0.9);

      setState(() {
        _tl = tl;
        _tr = tr;
        _bl = bl;
        _br = br;
        _isLayoutCalculated = true;
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('Error en la inicialización: $e');
    setState(() {
        _isLayoutCalculated = false;
        _isLoading = false;
    });
    }
  }

  void _updatePoint(String corner, Offset newPosition) async {
    if (!_isLayoutCalculated || _imageKey.currentContext == null) return;

    final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    
    final clampedX = newPosition.dx.clamp(0.0, size.width);
    final clampedY = newPosition.dy.clamp(0.0, size.height);
    final clampedOffset = Offset(clampedX, clampedY);

    // Convertir la nueva posición de pantalla a coordenadas de imagen
    // para actualizar _imageCorners
    try {
      final Uint8List bytes = await widget.imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);
      
      if (originalImage != null && _imageCorners != null) {
        final int imageWidth = originalImage.width;
        final int imageHeight = originalImage.height;
        
        final double ratioX = size.width / imageWidth;
        final double ratioY = size.height / imageHeight;
        final double scaleFactor = min(ratioX, ratioY);
        final double displayedWidth = imageWidth * scaleFactor;
        final double displayedHeight = imageHeight * scaleFactor;
        final double horizontalOffset = (size.width - displayedWidth) / 2;
        final double verticalOffset = (size.height - displayedHeight) / 2;
        
        Offset toImageCoords(Offset screenOffset) {
          final double x = (screenOffset.dx - horizontalOffset) / scaleFactor;
          final double y = (screenOffset.dy - verticalOffset) / scaleFactor;
          return Offset(
            x.clamp(0.0, imageWidth.toDouble()),
            y.clamp(0.0, imageHeight.toDouble()),
          );
        }
        
        final imageCoord = toImageCoords(clampedOffset);
        
      setState(() {
          switch (corner) {
            case 'tl': 
              _tl = clampedOffset;
              _imageCorners![0] = imageCoord;
              break;
            case 'tr': 
              _tr = clampedOffset;
              _imageCorners![1] = imageCoord;
              break;
            case 'bl': 
              _bl = clampedOffset;
              _imageCorners![2] = imageCoord;
              break;
            case 'br': 
              _br = clampedOffset;
              _imageCorners![3] = imageCoord;
              break;
          }
        });
        } else {
        // Si no hay _imageCorners, solo actualizar coordenadas de pantalla
        setState(() {
          switch (corner) {
            case 'tl': _tl = clampedOffset; break;
            case 'tr': _tr = clampedOffset; break;
            case 'bl': _bl = clampedOffset; break;
            case 'br': _br = clampedOffset; break;
          }
        });
      }
    } catch (e) {
      // Si hay error, solo actualizar coordenadas de pantalla
      setState(() {
        switch (corner) {
          case 'tl': _tl = clampedOffset; break;
          case 'tr': _tr = clampedOffset; break;
          case 'bl': _bl = clampedOffset; break;
          case 'br': _br = clampedOffset; break;
        }
      });
    }
  }

  /// Actualiza el color actual bajo el cursor mientras se mueve
  void _updateColorAtPosition(Offset position) {
    if (!_waitingForColorSelection) return;
    
    // Si el color está fijado, no actualizar la posición del cursor
    if (_colorLocked) return;
    
    // Actualizar posición del cursor inmediatamente
      if (mounted) {
      setState(() {
        _cursorPosition = position;
      });
    }
    
    if (_imageKey.currentContext == null) {
      if (mounted) {
        setState(() {
          _debugInfo = 'Error: No se puede acceder a la imagen';
        });
      }
      return;
    }

    // Usar un Future para no bloquear la UI
    Future.microtask(() async {
      try {
        final RenderBox? containerRenderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
        if (containerRenderBox == null) {
          if (mounted) {
            setState(() {
              _debugInfo = 'Error: Contenedor no disponible';
            });
          }
          return;
        }

        final containerSize = containerRenderBox.size;

        final Uint8List bytes = await widget.imageFile.readAsBytes();
        final img.Image? originalImage = img.decodeImage(bytes);

        if (originalImage == null) {
          if (mounted) {
            setState(() {
              _debugInfo = 'Error: No se pudo decodificar la imagen';
            });
          }
          return;
        }

        int actualImageWidth = originalImage.width;
        int actualImageHeight = originalImage.height;

        final double ratioX = containerSize.width / actualImageWidth;
        final double ratioY = containerSize.height / actualImageHeight;
        final double scaleFactor = min(ratioX, ratioY);

        final double displayedWidth = actualImageWidth * scaleFactor;
        final double displayedHeight = actualImageHeight * scaleFactor;

        final double horizontalOffset = (containerSize.width - displayedWidth) / 2;
        final double verticalOffset = (containerSize.height - displayedHeight) / 2;

        final double relativeX = position.dx.clamp(0.0, containerSize.width);
        final double relativeY = position.dy.clamp(0.0, containerSize.height);

        final double imageX = ((relativeX - horizontalOffset) / scaleFactor).clamp(0.0, actualImageWidth.toDouble());
        final double imageY = ((relativeY - verticalOffset) / scaleFactor).clamp(0.0, actualImageHeight.toDouble());

        if (imageX >= 0 && imageX < actualImageWidth && imageY >= 0 && imageY < actualImageHeight) {
          final pixel = originalImage.getPixel(imageX.toInt(), imageY.toInt());
          final color = img.ColorRgb8(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

          if (mounted) {
            setState(() {
              if (!_colorLocked) {
                _cursorPosition = position;
              }
              _currentColor = color;
              if (!_colorLocked) {
                _debugInfo = 'Pos: (${imageX.toInt()}, ${imageY.toInt()}) | R:${pixel.r} G:${pixel.g} B:${pixel.b}';
              }
            });
          }
          } else {
          if (mounted) {
            setState(() {
              _debugInfo = 'Fuera de la imagen: (${imageX.toInt()}, ${imageY.toInt()})';
            });
          }
        }
    } catch (e) {
        if (mounted) {
      setState(() {
            _debugInfo = 'Error: $e';
          });
        }
      }
    });
  }

  /// Confirma la selección del color actual y detecta las esquinas
  Future<void> _confirmColorSelection() async {
    if (_currentColor == null || _imageKey.currentContext == null) {
      if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, mueve el cursor sobre una esquina roja')),
        );
      }
      return;
    }

      setState(() {
        _isLoading = true;
      _selectedColor = _currentColor;
      _waitingForColorSelection = false;
      _colorLocked = false; // Resetear el bloqueo
    });

    try {
      final RenderBox? containerRenderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (containerRenderBox == null) {
        setState(() {
          _isLoading = false;
        });
      return;
    }
    
      final containerSize = containerRenderBox.size;
    
      final Uint8List bytes = await widget.imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);
      
      if (originalImage == null) {
        throw Exception("No se pudo decodificar la imagen.");
      }

      int actualImageWidth = originalImage.width;
      int actualImageHeight = originalImage.height;

      await _detectCornersWithColor(_currentColor!, containerSize, actualImageWidth, actualImageHeight, _colorTolerance);

    } catch (e) {
      debugPrint('Error al confirmar color: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
        setState(() {
          _isLoading = false;
        });
      }
    }


  /// Detecta las esquinas usando un color de referencia
  Future<void> _detectCornersWithColor(
    img.ColorRgb8 color,
    Size containerSize,
    int actualImageWidth,
    int actualImageHeight,
    int colorTolerance,
  ) async {
    try {
      // Obtener el RenderBox actual para asegurar que tenemos el tamaño correcto
      // Esperar varios frames para asegurar que el layout esté completamente renderizado
      await Future.delayed(const Duration(milliseconds: 200));
      await SchedulerBinding.instance.endOfFrame;
      
      final RenderBox? currentRenderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (currentRenderBox == null) {
        throw Exception('No se puede acceder al contenedor de la imagen');
      }
      
      final actualContainerSize = currentRenderBox.size;
      
      // Verificar que el tamaño del contenedor sea válido
      if (actualContainerSize.width <= 0 || actualContainerSize.height <= 0) {
        throw Exception('Tamaño del contenedor inválido: $actualContainerSize');
      }

      final cornerService = CornerDetectionService();
      final redCorners = await cornerService.detectRedCorners(
        widget.imageFile,
        referenceColor: color,
        colorTolerance: colorTolerance,
      );

      if (redCorners == null || redCorners.length != 4) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudieron detectar 4 esquinas. Se encontraron: ${redCorners?.length ?? 0}. Intenta con otro color o ajusta la tolerancia.'),
              backgroundColor: Colors.orange,
            ),
          );
    setState(() {
          _isLoading = false;
        });
      }
        return;
      }

      final double ratioX = actualContainerSize.width / actualImageWidth;
      final double ratioY = actualContainerSize.height / actualImageHeight;
      final double scaleFactor = min(ratioX, ratioY);

      final double displayedWidth = actualImageWidth * scaleFactor;
      final double displayedHeight = actualImageHeight * scaleFactor;

      final double horizontalOffset = (actualContainerSize.width - displayedWidth) / 2;
      final double verticalOffset = (actualContainerSize.height - displayedHeight) / 2;

      // Convertir coordenadas de imagen a coordenadas de pantalla
      Offset toScreenCoords(Offset imgPoint) {
        final x = horizontalOffset + (imgPoint.dx * scaleFactor);
        final y = verticalOffset + (imgPoint.dy * scaleFactor);
        return Offset(x, y);
      }

      final tl = toScreenCoords(redCorners[0]); // top-left
      final tr = toScreenCoords(redCorners[1]); // top-right
      final bl = toScreenCoords(redCorners[2]); // bottom-left
      final br = toScreenCoords(redCorners[3]); // bottom-right

      if (mounted) {
    setState(() {
          _autoDetected = true;
          // Guardar coordenadas de imagen original para recalcular cuando cambie el tamaño
          _imageCorners = List.from(redCorners);
          _tl = tl;
          _tr = tr;
          _bl = bl;
          _br = br;
          _isLayoutCalculated = true;
          _isLoading = false;
        });
        
        // Forzar un rebuild después de un pequeño delay para que el LayoutBuilder
        // se ejecute con el tamaño correcto del Container
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() {
            // Esto forzará que el LayoutBuilder se ejecute de nuevo
          });
        }

      }
    } catch (e, stackTrace) {
      debugPrint('Error al detectar esquinas: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _performCrop() async {
    if (!_isLayoutCalculated || _imageKey.currentContext == null) return;

    setState(() {
      _isLoading = true;
    });

    final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
    final containerSize = renderBox.size;

    try {
      final Uint8List bytes = await widget.imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        throw Exception("No se pudo decodificar la imagen.");
      }

      int actualImageWidth = originalImage.width;
      int actualImageHeight = originalImage.height;
      
      // Usar siempre las coordenadas de imagen guardadas en _imageCorners si están disponibles
      // Estas se actualizan automáticamente cuando el usuario mueve los handles
      List<Offset> realPoints;
      
      if (_imageCorners != null) {
        // Usar directamente las coordenadas de imagen (siempre actualizadas)
        realPoints = List.from(_imageCorners!);
      } else {
        // No hay coordenadas de imagen originales, convertir coordenadas de pantalla
      final double ratioX = containerSize.width / actualImageWidth;
      final double ratioY = containerSize.height / actualImageHeight;
      final double scaleFactor = min(ratioX, ratioY);
      final double displayedWidth = actualImageWidth * scaleFactor;
      final double displayedHeight = actualImageHeight * scaleFactor;
      final double horizontalOffset = (containerSize.width - displayedWidth) / 2;
      final double verticalOffset = (containerSize.height - displayedHeight) / 2;

        Offset toRealCoords(Offset screenOffset) {
        final double x = (screenOffset.dx - horizontalOffset) / scaleFactor;
        final double y = (screenOffset.dy - verticalOffset) / scaleFactor;
          return Offset(x.clamp(0.0, actualImageWidth.toDouble()), y.clamp(0.0, actualImageHeight.toDouble()));
        }
      
        realPoints = [
        toRealCoords(_tl),
        toRealCoords(_tr),
        toRealCoords(_bl),
        toRealCoords(_br),
      ];
      }
      
      // realPoints está en orden: [TL, TR, BL, BR]
      final tl = realPoints[0];
      final tr = realPoints[1];
      final bl = realPoints[2];
      final br = realPoints[3];
      
      // Calcular el tamaño del rectángulo de salida basado en el cuadrilátero
      // Usar la distancia promedio entre las esquinas opuestas
      final widthTop = (tr.dx - tl.dx).abs();
      final widthBottom = (br.dx - bl.dx).abs();
      final heightLeft = (bl.dy - tl.dy).abs();
      final heightRight = (br.dy - tr.dy).abs();
      
      final outputWidth = ((widthTop + widthBottom) / 2).round();
      final outputHeight = ((heightLeft + heightRight) / 2).round();
      
      if (outputWidth <= 0 || outputHeight <= 0) {
         throw Exception("El área de recorte es inválida o demasiado pequeña.");
      }

      // Crear una nueva imagen del tamaño del rectángulo de salida
      final croppedImage = img.Image(width: outputWidth, height: outputHeight);
      
      // Transformación de perspectiva: mapear cada píxel del rectángulo de salida
      // al cuadrilátero en la imagen original usando interpolación bilineal
      final invWidth = 1.0 / outputWidth;
      final invHeight = 1.0 / outputHeight;
      
      for (int y = 0; y < outputHeight; y++) {
        final v = y * invHeight;
        
        for (int x = 0; x < outputWidth; x++) {
          final u = x * invWidth;
          
          // Interpolación bilineal para encontrar la posición en el cuadrilátero original
          // Top edge: interpolación horizontal entre TL y TR
          final topX = tl.dx + (tr.dx - tl.dx) * u;
          final topY = tl.dy + (tr.dy - tl.dy) * u;
          
          // Bottom edge: interpolación horizontal entre BL y BR
          final bottomX = bl.dx + (br.dx - bl.dx) * u;
          final bottomY = bl.dy + (br.dy - bl.dy) * u;
          
          // Interpolación vertical entre top y bottom
          final srcX = topX + (bottomX - topX) * v;
          final srcY = topY + (bottomY - topY) * v;
          
          // Obtener el píxel de la imagen original
          final pixelX = srcX.round().clamp(0, actualImageWidth - 1);
          final pixelY = srcY.round().clamp(0, actualImageHeight - 1);
          
          croppedImage.setPixel(x, y, originalImage.getPixel(pixelX, pixelY));
        }
      }

      // Guardar la imagen recortada
      final Uint8List encodedBytes = img.encodeJpg(croppedImage, quality: 90);
      
      final tempDir = await getTemporaryDirectory();
      final croppedFilePath = '${tempDir.path}/cropped_diana_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      await File(croppedFilePath).writeAsBytes(encodedBytes);

      if (mounted) {
        Navigator.pop(context, File(croppedFilePath));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al recortar la imagen: ${e.toString()}')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recortar Diana'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLayoutCalculated && !_isLoading ? _performCrop : null,
            tooltip: 'Confirmar recorte',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Área de instrucciones con altura fija y scrollable
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                  if (_autoDetected)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
            Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Esquinas detectadas automáticamente',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _waitingForColorSelection = true;
                              _autoDetected = false; // Permitir nueva detección
                            });
                          },
                          icon: const Icon(Icons.colorize, size: 16),
                          label: const Text('Seleccionar otro color', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
            ),
          ],
        ),
                  if (!_autoDetected && !_waitingForColorSelection)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Selecciona el color de las esquinas para detectarlas automáticamente',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _waitingForColorSelection = true;
                            });
                          },
                          icon: const Icon(Icons.colorize, size: 18),
                          label: const Text('Seleccionar Color de Esquina', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
        foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
          ),
        ],
      ),
                  if (_waitingForColorSelection)
          Column(
                      mainAxisSize: MainAxisSize.min,
            children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade300),
                          ),
                child: Text(
                            _colorLocked 
                              ? 'Color fijado! Confirma o cambia el color'
                              : 'Mueve el ratón sobre una esquina roja y haz CLICK',
                  textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Mostrar color actual de forma compacta
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_currentColor != null)
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Color.fromRGBO(
                                    _currentColor!.r.toInt(),
                                    _currentColor!.g.toInt(),
                                    _currentColor!.b.toInt(),
                                    1.0,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey.shade400),
                                ),
                              ),
                            if (_currentColor != null) const SizedBox(width: 8),
                            if (_currentColor != null)
                              Text(
                                'R:${_currentColor!.r} G:${_currentColor!.g} B:${_currentColor!.b}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              )
                            else
                              const Text(
                                'Mueve el ratón sobre la imagen...',
                                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Slider de tolerancia compacto
                        Row(
                          children: [
                            const Text('Tolerancia:', style: TextStyle(fontSize: 11)),
                            Expanded(
                              child: Slider(
                                value: _colorTolerance.toDouble(),
                                min: 10,
                                max: 100,
                                divisions: 18,
                                label: '$_colorTolerance',
                                onChanged: (value) {
                                  setState(() {
                                    _colorTolerance = value.toInt();
                                  });
                                },
                              ),
                            ),
                            Text('$_colorTolerance', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        // Botones compactos
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (_colorLocked)
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _colorLocked = false;
                                    _debugInfo = 'Color desbloqueado';
                                  });
                                },
                                icon: const Icon(Icons.lock_open, size: 16),
                                label: const Text('Cambiar', style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                              ),
                            ElevatedButton.icon(
                              onPressed: _currentColor != null ? _confirmColorSelection : null,
                              icon: const Icon(Icons.check, size: 16),
                              label: Text(_colorLocked ? 'Confirmar' : 'Confirmar color', style: const TextStyle(fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _colorLocked ? Colors.green.shade800 : Colors.green.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  if (_autoDetected)
                    const Text(
                      'Ajusta las 4 esquinas arrastrando los puntos amarillos',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          // Área de imagen - siempre ocupa el resto del espacio
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SizedBox(
                          key: _imageKey,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                              // Imagen base
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Image.file(widget.imageFile, fit: BoxFit.contain),
                                ),
                              // Overlay transparente para capturar eventos
                              if (_waitingForColorSelection)
                                Positioned.fill(
                                  child: Listener(
                                    behavior: HitTestBehavior.translucent,
                                    onPointerMove: _colorLocked ? null : (event) {
                                      final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
                                      if (box != null) {
                                        final localPosition = box.globalToLocal(event.position);
                                        _updateColorAtPosition(localPosition);
                                      }
                                    },
                                    onPointerDown: (event) {
                                      final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
                                      if (box != null) {
                                        final localPosition = box.globalToLocal(event.position);
                                        // Fijar el color cuando se hace click
                                        setState(() {
                                          _colorLocked = true;
                                          _debugInfo = 'Color fijado! Presiona "Confirmar este color"';
                                        });
                                        _updateColorAtPosition(localPosition);
                                      }
                                    },
                                    child: MouseRegion(
                                      onHover: _colorLocked ? null : (event) {
                                        _updateColorAtPosition(event.localPosition);
                                      },
                                      child: Container(
                                        color: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ),
                              // Cursor en forma de cruz simple (+)
                              if (_waitingForColorSelection && _cursorPosition != null)
                                Positioned(
                                  left: _cursorPosition!.dx - 10,
                                  top: _cursorPosition!.dy - 10,
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      size: const Size(20, 20),
                                      painter: CrossCursorPainter(),
                                    ),
                                  ),
                                ),
                              // Indicador de prueba - círculo rojo grande para verificar que funciona
                              if (_waitingForColorSelection)
                                Positioned(
                                  left: 10,
                                  top: 10,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Text('✓', style: TextStyle(color: Colors.white, fontSize: 12)),
                                    ),
                                  ),
                                ),
                              // Cuadrilátero (solo si NO estamos en modo de selección de color)
                              if (_isLayoutCalculated && !_waitingForColorSelection)
                                Builder(
                                  builder: (context) {
                                    // Recalcular coordenadas basándose en el tamaño real del canvas
                                    // Usar Builder en lugar de LayoutBuilder para que se ejecute siempre
                                    final RenderBox? currentRenderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
                                    if (currentRenderBox != null && _imageCorners != null) {
                                      final actualContainerSize = currentRenderBox.size;
                                      
                                      // Obtener dimensiones de la imagen
                                      final Uint8List bytes = widget.imageFile.readAsBytesSync();
                                      final img.Image? originalImage = img.decodeImage(bytes);
                                      if (originalImage != null) {
                                        final int imageWidth = originalImage.width;
                                        final int imageHeight = originalImage.height;
                                        
                                        // Recalcular coordenadas con el tamaño real del container
                                        final double ratioX = actualContainerSize.width / imageWidth;
                                        final double ratioY = actualContainerSize.height / imageHeight;
                                        final double scaleFactor = min(ratioX, ratioY);
                                        final double displayedWidth = imageWidth * scaleFactor;
                                        final double displayedHeight = imageHeight * scaleFactor;
                                        final double horizontalOffset = (actualContainerSize.width - displayedWidth) / 2;
                                        final double verticalOffset = (actualContainerSize.height - displayedHeight) / 2;
                                        
                                        Offset toScreenCoords(Offset imgPoint) {
                                          return Offset(
                                            horizontalOffset + (imgPoint.dx * scaleFactor),
                                            verticalOffset + (imgPoint.dy * scaleFactor),
                                          );
                                        }
                                        
                                        final recalculatedTl = toScreenCoords(_imageCorners![0]);
                                        final recalculatedTr = toScreenCoords(_imageCorners![1]);
                                        final recalculatedBl = toScreenCoords(_imageCorners![2]);
                                        final recalculatedBr = toScreenCoords(_imageCorners![3]);
                                        
                                        // Actualizar coordenadas inmediatamente si cambiaron significativamente
                                        if ((_tl - recalculatedTl).distance > 1.0 ||
                                            (_tr - recalculatedTr).distance > 1.0 ||
                                            (_bl - recalculatedBl).distance > 1.0 ||
                                            (_br - recalculatedBr).distance > 1.0) {
                                          // Actualizar inmediatamente y forzar rebuild
                                          _tl = recalculatedTl;
                                          _tr = recalculatedTr;
                                          _bl = recalculatedBl;
                                          _br = recalculatedBr;
                                          // Forzar actualización inmediata
                                          if (mounted) {
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              if (mounted) {
                                                setState(() {});
                                              }
                                            });
                                          }
                                        }
                                        
                                        // Retornar el CustomPaint con coordenadas recalculadas
                                        // Los handles se agregan después del LayoutBuilder
                                        return CustomPaint(
                                    painter: QuadrilateralPainter(
                                            tl: recalculatedTl, 
                                            tr: recalculatedTr, 
                                            bl: recalculatedBl, 
                                            br: recalculatedBr,
                                          ),
                                        );
                                      }
                                    }
                                    // Fallback: usar coordenadas guardadas
                                    return CustomPaint(
                                      painter: QuadrilateralPainter(
                                        tl: _tl, tr: _tr, bl: _bl, br: _br,
                                      ),
                                    );
                                  },
                                ),
                              // Handles (solo si NO estamos en modo de selección de color)
                              if (_isLayoutCalculated && !_waitingForColorSelection) ...[
                                  DraggableHandle(
                                    position: _tl,
                                    onDrag: (newPos) => _updatePoint('tl', newPos),
                                  ),
                                  DraggableHandle(
                                    position: _tr,
                                    onDrag: (newPos) => _updatePoint('tr', newPos),
                                  ),
                                  DraggableHandle(
                                    position: _bl,
                                    onDrag: (newPos) => _updatePoint('bl', newPos),
                                  ),
                                  DraggableHandle(
                                    position: _br,
                                    onDrag: (newPos) => _updatePoint('br', newPos),
                                  ),
                                ],
                              ],
                          ),
                        );
                      }
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: _isLayoutCalculated && !_isLoading ? _performCrop : null,
                  icon: const Icon(Icons.check, size: 24),
                  label: const Text('Confirmar Recorte', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 5,
                  ),
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom Painter para dibujar el cursor en forma de cruz
class CrossCursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Líneas más cortas para una cruz simple
    final lineLength = 12.0;
    final halfLength = lineLength / 2;
    
    // Sombra negra para contraste
    final shadowPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Línea blanca principal
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Dibujar sombra negra primero
    // Línea horizontal
    canvas.drawLine(
      Offset(center.dx - halfLength, center.dy),
      Offset(center.dx + halfLength, center.dy),
      shadowPaint,
    );
    // Línea vertical
    canvas.drawLine(
      Offset(center.dx, center.dy - halfLength),
      Offset(center.dx, center.dy + halfLength),
      shadowPaint,
    );

    // Dibujar líneas blancas encima
    // Línea horizontal
    canvas.drawLine(
      Offset(center.dx - halfLength, center.dy),
      Offset(center.dx + halfLength, center.dy),
      paint,
    );
    // Línea vertical
    canvas.drawLine(
      Offset(center.dx, center.dy - halfLength),
      Offset(center.dx, center.dy + halfLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CrossCursorPainter oldDelegate) => false;
}

/// Custom Painter para dibujar el cuadrilátero
class QuadrilateralPainter extends CustomPainter {
  final Offset tl, tr, bl, br;

  QuadrilateralPainter({required this.tl, required this.tr, required this.bl, required this.br});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
      
    final strokePaint = Paint()
      ..color = Colors.redAccent.shade700
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
      
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant QuadrilateralPainter oldDelegate) {
    return oldDelegate.tl != tl || oldDelegate.tr != tr || oldDelegate.bl != bl || oldDelegate.br != br;
  }
}

/// Widget Draggable Handle
class DraggableHandle extends StatelessWidget {
  final Offset position;
  final ValueChanged<Offset> onDrag;
  static const double handleSize = 40.0; 
  
  const DraggableHandle({super.key, required this.position, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - handleSize / 2, 
      top: position.dy - handleSize / 2,
      child: GestureDetector(
        onPanUpdate: (details) {
          onDrag(position + details.delta);
        },
        child: Container(
          width: handleSize,
          height: handleSize,
          decoration: BoxDecoration(
            color: Colors.amber.shade700.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 8,
              )
            ]
          ),
          child: const Center(
            child: Icon(Icons.control_point, size: 24, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Custom Painter para dibujar los círculos de la diana
class TargetZonesPainter extends CustomPainter {
  final Offset dianaCenter;
  final double dianaRadius;
  final Size imageSize;
  final Size containerSize;
  final List<List<Offset>>? detectedCirclePixels; // Píxeles de las líneas circulares detectadas
  final Offset? detectedCenter; // Centro estimado de los círculos
  final int? currentCircleIndex; // Índice del círculo actual a mostrar (null = todos)
  final File? binaryImageFile; // Archivo de imagen binaria para detectar píxeles negros/blancos

  TargetZonesPainter({
    required this.dianaCenter,
    required this.dianaRadius,
    required this.imageSize,
    required this.containerSize,
    this.detectedCirclePixels,
    this.detectedCenter,
    this.currentCircleIndex,
    this.binaryImageFile,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calcular cómo Image con BoxFit.contain escala la imagen
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;
    final scale = min(scaleX, scaleY); // BoxFit.contain usa el menor
    
    // Calcular el tamaño de la imagen escalada
    final displayedWidth = imageSize.width * scale;
    final displayedHeight = imageSize.height * scale;
    
    // Calcular el offset para centrar (Image con BoxFit.contain centra automáticamente)
    final offsetX = (size.width - displayedWidth) / 2;
    final offsetY = (size.height - displayedHeight) / 2;
    
      // Escáner Radial: trazar el contorno exacto de cada círculo
      if (detectedCirclePixels != null && detectedCirclePixels!.isNotEmpty && binaryImageFile != null) {
        // Calcular el centro en coordenadas de imagen
        final centerImage = detectedCenter ?? dianaCenter;
        
        // Calcular el centro en coordenadas de pantalla
        final screenCenter = Offset(
          offsetX + (centerImage.dx * scale),
          offsetY + (centerImage.dy * scale),
        );
        
        // Cargar la imagen binaria
        img.Image? binaryImage;
        try {
          final bytes = binaryImageFile!.readAsBytesSync();
          binaryImage = img.decodeImage(bytes);
        } catch (e) {
          debugPrint('Error al cargar imagen binaria: $e');
          return;
        }
        if (binaryImage == null) return;
        
        // Pint para el contorno rojo
        final contourPaint = Paint()
          ..color = Colors.red.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        
        // Pint para la cruz azul en el centro
        final crossPaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        
        // Determinar qué círculos procesar
        final circlesToProcess = currentCircleIndex != null 
            ? [currentCircleIndex!] 
            : List.generate(detectedCirclePixels!.length, (i) => i);
        
        // Procesar cada círculo con el escáner radial
        for (final circleIdx in circlesToProcess) {
          if (circleIdx < 0 || circleIdx >= detectedCirclePixels!.length) continue;
          
          // Calcular el centro de este círculo específico a partir de sus píxeles
          final circlePixels = detectedCirclePixels![circleIdx];
          if (circlePixels.isEmpty) continue;
          
          // Calcular el centroide (centro promedio) de los píxeles del círculo
          double sumX = 0;
          double sumY = 0;
          for (final pixel in circlePixels) {
            sumX += pixel.dx;
            sumY += pixel.dy;
          }
          final circleCenter = Offset(
            sumX / circlePixels.length,
            sumY / circlePixels.length,
          );
          
          // Calcular el centro en coordenadas de pantalla para este círculo
          final circleScreenCenter = Offset(
            offsetX + (circleCenter.dx * scale),
            offsetY + (circleCenter.dy * scale),
          );
          
          // Calcular el radio promedio y desviación estándar del círculo a partir de sus píxeles
          double sumDistances = 0;
          final distances = <double>[];
          for (final pixel in circlePixels) {
            final dist = sqrt(
              pow(pixel.dx - circleCenter.dx, 2) + 
              pow(pixel.dy - circleCenter.dy, 2)
            );
            sumDistances += dist;
            distances.add(dist);
          }
          final avgRadius = sumDistances / circlePixels.length;
          
          // Calcular desviación estándar para determinar el rango válido
          double sumSquaredDiff = 0;
          for (final dist in distances) {
            sumSquaredDiff += pow(dist - avgRadius, 2);
          }
          final stdDev = sqrt(sumSquaredDiff / distances.length);
          
          // Crear un conjunto de píxeles del círculo para validación rápida
          final circlePixelSet = <String>{};
          for (final pixel in circlePixels) {
            circlePixelSet.add('${pixel.dx.round()},${pixel.dy.round()}');
          }
          
          // Escáner radial: lanzar líneas desde el centro en todas las direcciones
          final numRays = 720; // 720 rayos = 0.5 grados por rayo
          final angleStep = 2 * pi / numRays;
          final contourPoints = <Offset>[];
          
          // Radio de búsqueda más estricto: usar desviación estándar
          final searchRadiusMin = max(0.0, avgRadius - stdDev * 1.5);
          final searchRadiusMax = avgRadius + stdDev * 1.5;
          
          for (int i = 0; i < numRays; i++) {
            final angle = i * angleStep;
            final cosAngle = cos(angle);
            final sinAngle = sin(angle);
            
            // Buscar la transición más cercana al radio promedio del círculo
            int? lastColor; // 0 = negro, 1 = blanco
            Offset? bestTransition;
            double minDistanceToAvgRadius = double.infinity;
            
            // Recorrer solo en el rango válido del círculo
            for (double r = searchRadiusMin; r < searchRadiusMax; r += 0.5) {
              final x = circleCenter.dx + r * cosAngle;
              final y = circleCenter.dy + r * sinAngle;
              
              final pixelX = x.round();
              final pixelY = y.round();
              
              // Verificar que esté dentro de los límites
              if (pixelX < 0 || pixelX >= binaryImage.width || 
                  pixelY < 0 || pixelY >= binaryImage.height) {
                continue;
              }
              
              // Validar que el punto esté cerca de los píxeles detectados del círculo
              bool cercaDePixelConocido = false;
              for (final pixel in circlePixels) {
                final dist = sqrt(
                  pow(pixelX - pixel.dx, 2) + 
                  pow(pixelY - pixel.dy, 2)
                );
                if (dist <= 3.0) { // Tolerancia de 3 píxeles
                  cercaDePixelConocido = true;
                  break;
                }
              }
              
              // Si no está cerca de ningún píxel conocido, saltar
              if (!cercaDePixelConocido) {
                continue;
              }
              
              // Obtener el color del píxel
              final pixel = binaryImage.getPixel(pixelX, pixelY);
              final intensity = (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b).round();
              final esNegro = intensity < 128;
              final colorActual = esNegro ? 0 : 1;
              
              // Detectar transición de color
              if (lastColor != null && lastColor != colorActual) {
                // Encontramos una transición - verificar si está cerca del radio promedio
                final distanceToAvgRadius = (r - avgRadius).abs();
                if (distanceToAvgRadius < minDistanceToAvgRadius) {
                  bestTransition = Offset(x, y);
                  minDistanceToAvgRadius = distanceToAvgRadius;
                }
              }
              
              lastColor = colorActual;
            }
            
            // Si encontramos una transición válida, agregar el punto al contorno
            if (bestTransition != null && minDistanceToAvgRadius <= stdDev * 1.5) {
              final screenPoint = Offset(
                offsetX + (bestTransition.dx * scale),
                offsetY + (bestTransition.dy * scale),
              );
              contourPoints.add(screenPoint);
            }
          }
          
          // Dibujar el contorno conectando todos los puntos encontrados
          if (contourPoints.length > 2) {
            // Ordenar puntos por ángulo para asegurar orden correcto
            contourPoints.sort((a, b) {
              final angleA = atan2(a.dy - circleScreenCenter.dy, a.dx - circleScreenCenter.dx);
              final angleB = atan2(b.dy - circleScreenCenter.dy, b.dx - circleScreenCenter.dx);
              return angleA.compareTo(angleB);
            });
            
            // Filtrar puntos anómalos que causan picos grandes
            final filteredPoints = <Offset>[];
            if (contourPoints.length > 2) {
              // Calcular distancia promedio entre puntos consecutivos
              double sumDistances = 0;
              for (int i = 0; i < contourPoints.length; i++) {
                final next = (i + 1) % contourPoints.length;
                final dist = sqrt(
                  pow(contourPoints[i].dx - contourPoints[next].dx, 2) +
                  pow(contourPoints[i].dy - contourPoints[next].dy, 2)
                );
                sumDistances += dist;
              }
              final avgDistance = sumDistances / contourPoints.length;
              final maxDistance = avgDistance * 3.0; // Tolerancia de 3x la distancia promedio
              
              // Filtrar puntos que estén demasiado lejos de sus vecinos
              for (int i = 0; i < contourPoints.length; i++) {
                final prev = (i - 1 + contourPoints.length) % contourPoints.length;
                final next = (i + 1) % contourPoints.length;
                
                final distToPrev = sqrt(
                  pow(contourPoints[i].dx - contourPoints[prev].dx, 2) +
                  pow(contourPoints[i].dy - contourPoints[prev].dy, 2)
                );
                final distToNext = sqrt(
                  pow(contourPoints[i].dx - contourPoints[next].dx, 2) +
                  pow(contourPoints[i].dy - contourPoints[next].dy, 2)
                );
                
                // Si ambas distancias son razonables, incluir el punto
                if (distToPrev <= maxDistance && distToNext <= maxDistance) {
                  filteredPoints.add(contourPoints[i]);
                }
              }
            }
            
            // Si después del filtrado tenemos suficientes puntos, dibujar
            if (filteredPoints.length > 2) {
              // Crear el path del contorno
              final path = Path();
              path.moveTo(filteredPoints[0].dx, filteredPoints[0].dy);
              
              for (int i = 1; i < filteredPoints.length; i++) {
                path.lineTo(filteredPoints[i].dx, filteredPoints[i].dy);
              }
              
              // Cerrar el contorno
              path.close();
              
              // Dibujar el contorno
              canvas.drawPath(path, contourPaint);
            }
          }
        }
        
        // Dibujar cruz en el centro
        final crossSize = 15.0;
        canvas.drawLine(
          Offset(screenCenter.dx - crossSize, screenCenter.dy),
          Offset(screenCenter.dx + crossSize, screenCenter.dy),
          crossPaint,
        );
        canvas.drawLine(
          Offset(screenCenter.dx, screenCenter.dy - crossSize),
          Offset(screenCenter.dx, screenCenter.dy + crossSize),
          crossPaint,
        );
      }
    
    // NO dibujar cruz en el centro (solo mostrar resultado final)
    // if (detectedCirclePixels != null && detectedCirclePixels!.isNotEmpty) {
    //   final screenCenter = detectedCenter != null
    //       ? Offset(offsetX + (detectedCenter!.dx * scale), offsetY + (detectedCenter!.dy * scale))
    //       : Offset(offsetX + (dianaCenter.dx * scale), offsetY + (dianaCenter.dy * scale));
    //   
    //   // Dibujar cruz en el centro
    //   final crossPaint = Paint()
    //     ..color = Colors.blue
    //     ..style = PaintingStyle.stroke
    //     ..strokeWidth = 2.0;
    //   
    //   final crossSize = 15.0;
    //   canvas.drawLine(
    //     Offset(screenCenter.dx - crossSize, screenCenter.dy),
    //     Offset(screenCenter.dx + crossSize, screenCenter.dy),
    //     crossPaint,
    //   );
    //   canvas.drawLine(
    //     Offset(screenCenter.dx, screenCenter.dy - crossSize),
    //     Offset(screenCenter.dx, screenCenter.dy + crossSize),
    //     crossPaint,
    //   );
    // }
  }

  @override
  bool shouldRepaint(TargetZonesPainter oldDelegate) {
    return oldDelegate.dianaCenter != dianaCenter ||
           oldDelegate.dianaRadius != dianaRadius ||
           oldDelegate.imageSize != imageSize ||
           oldDelegate.containerSize != containerSize ||
           oldDelegate.detectedCirclePixels != detectedCirclePixels ||
           oldDelegate.detectedCenter != detectedCenter ||
           oldDelegate.currentCircleIndex != currentCircleIndex ||
           oldDelegate.binaryImageFile != binaryImageFile;
  }
}

/// Custom Painter para dibujar los agujeros detectados
class HolesPainter extends CustomPainter {
  final List<Disparo> disparos;
  final Offset dianaCenter;
  final double dianaRadius;
  final Size imageSize;
  final Size containerSize;

  HolesPainter({
    required this.disparos,
    required this.dianaCenter,
    required this.dianaRadius,
    required this.imageSize,
    required this.containerSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calcular cómo Image con BoxFit.contain escala la imagen
    // size es el tamaño del CustomPaint (que coincide con el contenedor)
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;
    final scale = min(scaleX, scaleY); // BoxFit.contain usa el menor
    
    // Calcular el tamaño de la imagen escalada
    final displayedWidth = imageSize.width * scale;
    final displayedHeight = imageSize.height * scale;
    
    // Calcular el offset para centrar (Image con BoxFit.contain centra automáticamente)
    final offsetX = (size.width - displayedWidth) / 2;
    final offsetY = (size.height - displayedHeight) / 2;
    
      // Dibujar cada agujero como un círculo perfecto
      for (var disparo in disparos) {
        // Obtener la información del agujero desde HoleDetectionService
        final holeInfo = hole_service.HoleDetectionService.getHoleInfo(disparo.numero);
        
        if (holeInfo != null) {
          final centerX = holeInfo['centerX'] as double;
          final centerY = holeInfo['centerY'] as double;
          final radius = holeInfo['radius'] as double;
          
          // Convertir coordenadas de imagen recortada a coordenadas de pantalla
          final screenCenterX = offsetX + (centerX * scale);
          final screenCenterY = offsetY + (centerY * scale);
          final screenRadius = radius * scale;
          
          // Dibujar un círculo perfecto en rojo, sin relleno
          final circlePaint = Paint()
            ..color = Colors.red
            ..style = PaintingStyle.stroke  // Solo contorno, sin relleno
            ..strokeWidth = max(2.0, 3.0 * scale) // Línea que se escala con la imagen
            ..strokeCap = StrokeCap.round;
          
          canvas.drawCircle(
            Offset(screenCenterX, screenCenterY),
            screenRadius,
            circlePaint,
          );
        }
      }
  }

  /// Dibuja una estrella simple
  // ignore: unused_element
  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final angle = (i * 4 * pi / 5) - (pi / 2);
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(HolesPainter oldDelegate) {
    return oldDelegate.disparos.length != disparos.length ||
           oldDelegate.dianaCenter != dianaCenter ||
           oldDelegate.dianaRadius != dianaRadius;
  }
}
