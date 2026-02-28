import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../services/opencv_service.dart';

/// Pantalla para recortar dianas - En desarrollo con OpenCV
class RecorteDianaScreen extends StatefulWidget {
  const RecorteDianaScreen({super.key});

  @override
  State<RecorteDianaScreen> createState() => _RecorteDianaScreenState();
}

class _RecorteDianaScreenState extends State<RecorteDianaScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  
  // Esquinas en coordenadas de imagen (píxeles reales)
  // Siempre disponibles: detectadas automáticamente o cuadrado por defecto
  List<Offset>? _detectedCorners;
  bool _isDetecting = false;
  bool _cornersAutoDetected = false; // true si se detectaron automáticamente
  String? _detectionMessage;
  int? _draggingCornerIndex; // Índice de la esquina que se está arrastrando
  bool _foldMode = false; // Modo pliegue activo (6 puntos en vez de 4)
  
  // Tamaño real de la imagen para poder convertir coordenadas
  Size? _imageSize;

  // Imagen recortada (resultado del warpPerspective)
  File? _croppedImage;
  File? _croppedImageNormal; // Versión sin corrección de pliegue (para comparar)
  bool _showComparison = false; // Mostrar comparación lado a lado
  bool _isCropping = false;

  // Detección del centro de la diana (imagen principal / con pliegue)
  Offset? _dianaCenter;
  List<Map<String, double>>? _detectedCircles;
  List<List<Map<String, dynamic>>>? _ringContours; // Contornos reales de anillos
  bool _isDetectingCenter = false;
  String? _centerMessage;
  Size? _croppedImageSize;
  double? _spacingPx; // Espaciado ISSF en píxeles

  // Detección del centro para la versión NORMAL (comparación en modo pliegue)
  Offset? _dianaCenterNormal;
  List<Map<String, double>>? _detectedCirclesNormal;
  List<List<Map<String, dynamic>>>? _ringContoursNormal;
  String? _centerMessageNormal;
  double? _spacingPxNormal;

  // Detección de impactos
  List<Map<String, double>>? _impacts;
  bool _isDetectingImpacts = false;
  String? _impactsMessage;

  /// Selecciona una imagen desde cámara o galería
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null && mounted) {
        final file = File(pickedFile.path);
        setState(() {
          _selectedImage = file;
          _detectedCorners = null;
          _cornersAutoDetected = false;
          _detectionMessage = null;
          _draggingCornerIndex = null;
          _foldMode = false;
          _imageSize = null;
          _croppedImage = null;
          _croppedImageNormal = null;
          _showComparison = false;
          _dianaCenter = null;
          _detectedCircles = null;
          _ringContours = null;
          _centerMessage = null;
          _croppedImageSize = null;
          _spacingPx = null;
          _dianaCenterNormal = null;
          _detectedCirclesNormal = null;
          _ringContoursNormal = null;
          _centerMessageNormal = null;
          _spacingPxNormal = null;
          _impacts = null;
          _impactsMessage = null;
        });
        
        // Obtener tamaño real de la imagen
        await _loadImageSize(file);
        
        // Lanzar detección automática de esquinas
        await _detectCorners(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e')),
        );
      }
    }
  }

  /// Carga el tamaño real de la imagen
  Future<void> _loadImageSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null && mounted) {
        setState(() {
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
      }
    } catch (e) {
      debugPrint('Error al obtener tamaño de imagen: $e');
    }
  }

  /// Detecta las 4 esquinas de la diana usando OpenCV.
  /// Si no se detectan, genera un cuadrado centrado por defecto.
  Future<void> _detectCorners(File file) async {
    setState(() {
      _isDetecting = true;
      _detectionMessage = 'Detectando esquinas con OpenCV...';
    });

    try {
      final corners = await OpenCVService.detectTargetCorners(file);
      
      if (mounted) {
        setState(() {
          _isDetecting = false;
          if (corners != null && corners.length == 4) {
            _detectedCorners = corners;
            _cornersAutoDetected = true;
            _detectionMessage = 'Esquinas detectadas. Puedes ajustarlas arrastrando los puntos.';
          } else {
            // Fallback: cuadrado centrado con margen del 10%
            _detectedCorners = _generateDefaultSquare();
            _cornersAutoDetected = false;
            _detectionMessage = 'No se detectaron esquinas. Ajusta el cuadrado arrastrando los puntos.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDetecting = false;
          // En caso de error, generar cuadrado por defecto
          _detectedCorners = _generateDefaultSquare();
          _cornersAutoDetected = false;
          _detectionMessage = 'Error en detección. Ajusta el cuadrado arrastrando los puntos.';
        });
      }
    }
  }

  /// Genera un cuadrado centrado por defecto basado en el tamaño de la imagen.
  /// El cuadrado ocupa el 80% de la dimensión menor de la imagen.
  List<Offset> _generateDefaultSquare() {
    if (_imageSize == null) return [];
    final w = _imageSize!.width;
    final h = _imageSize!.height;
    final side = min(w, h) * 0.8;
    final cx = w / 2;
    final cy = h / 2;
    final half = side / 2;
    return [
      Offset(cx - half, cy - half), // TL
      Offset(cx + half, cy - half), // TR
      Offset(cx - half, cy + half), // BL
      Offset(cx + half, cy + half), // BR
    ];
  }

  /// Activa o desactiva el modo pliegue, añadiendo/quitando los 2 puntos de pliegue
  void _toggleFoldMode() {
    if (_detectedCorners == null || _imageSize == null) return;
    setState(() {
      _foldMode = !_foldMode;
      _croppedImage = null; // Forzar re-recorte
      if (_foldMode) {
        // Asegurar que solo tenemos 4 esquinas base
        if (_detectedCorners!.length > 4) {
          _detectedCorners = _detectedCorners!.sublist(0, 4);
        }
        // Añadir puntos de pliegue en el centro vertical (entre TL-TR y BL-BR)
        final tl = _detectedCorners![0];
        final tr = _detectedCorners![1];
        final bl = _detectedCorners![2];
        final br = _detectedCorners![3];
        final foldTop = Offset((tl.dx + tr.dx) / 2, (tl.dy + tr.dy) / 2);
        final foldBottom = Offset((bl.dx + br.dx) / 2, (bl.dy + br.dy) / 2);
        _detectedCorners!.add(foldTop);
        _detectedCorners!.add(foldBottom);
      } else {
        // Quitar los puntos de pliegue
        if (_detectedCorners!.length > 4) {
          _detectedCorners = _detectedCorners!.sublist(0, 4);
        }
      }
    });
  }

  /// Recorta la imagen usando las esquinas detectadas y OpenCV warpPerspective.
  /// Si _foldMode está activo, usa corrección en 2 mitades.
  Future<void> _cropImage() async {
    if (_selectedImage == null || _detectedCorners == null || _imageSize == null) return;
    if (_foldMode && _detectedCorners!.length < 6) return;

    setState(() {
      _isCropping = true;
      // Resetear detección previa para forzar recalculación
      _croppedImageSize = null;
      _dianaCenter = null;
      _detectedCircles = null;
      _ringContours = null;
      _dianaCenterNormal = null;
      _detectedCirclesNormal = null;
      _ringContoursNormal = null;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final corners = _detectedCorners!;

      // Calcular tamaño de salida basado en las 4 esquinas principales
      final tl = corners[0], tr = corners[1], bl = corners[2], br = corners[3];
      final widthTop = (tr - tl).distance;
      final widthBottom = (br - bl).distance;
      final heightLeft = (bl - tl).distance;
      final heightRight = (br - tr).distance;
      final outputWidth = ((widthTop + widthBottom) / 2).round();
      final outputHeight = ((heightLeft + heightRight) / 2).round();

      if (outputWidth <= 0 || outputHeight <= 0) {
        throw Exception('Área de recorte inválida');
      }

      File? result;
      File? resultNormal;
      if (_foldMode) {
        // Corrección en 2 mitades
        final foldTop = corners[4];
        final foldBottom = corners[5];
        result = await OpenCVService.cropWithFoldCorrection(
          bytes,
          corners.sublist(0, 4), // Solo las 4 esquinas
          foldTop,
          foldBottom,
          outputWidth,
          outputHeight,
        );
        // También generar la versión normal para comparar
        resultNormal = await OpenCVService.cropWithPerspective(
          bytes, corners.sublist(0, 4), outputWidth, outputHeight,
        );
      } else {
        // Corrección normal
        result = await OpenCVService.cropWithPerspective(
          bytes, corners, outputWidth, outputHeight,
        );
      }

      if (mounted) {
        setState(() {
          _isCropping = false;
          _croppedImage = result;
          _croppedImageNormal = resultNormal;
          _showComparison = false;
        });

        if (result == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al recortar la imagen')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  /// Detecta el centro de la diana en la imagen recortada usando HoughCircles.
  /// Si estamos en modo pliegue con imagen normal disponible, detecta en ambas.
  Future<void> _detectCenter() async {
    if (_croppedImage == null) return;

    setState(() {
      _isDetectingCenter = true;
      _centerMessage = 'Detectando centro y anillos...';
      _dianaCenter = null;
      _detectedCircles = null;
      _ringContours = null;
      _dianaCenterNormal = null;
      _detectedCirclesNormal = null;
      _ringContoursNormal = null;
      _centerMessageNormal = null;
    });

    try {
      // Cargar tamaño de la imagen recortada si no lo tenemos
      if (_croppedImageSize == null) {
        final bytes = await _croppedImage!.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          _croppedImageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
        }
      }

      // --- Detectar en imagen principal (con pliegue si activo) ---
      final bytes = await _croppedImage!.readAsBytes();
      final result = await OpenCVService.detectTargetCenter(bytes);

      // --- Detectar en imagen NORMAL si estamos en modo pliegue ---
      Map<String, dynamic>? resultNormal;
      if (_foldMode && _croppedImageNormal != null) {
        final bytesNormal = await _croppedImageNormal!.readAsBytes();
        resultNormal = await OpenCVService.detectTargetCenter(bytesNormal);
      }

      if (mounted) {
        setState(() {
          _isDetectingCenter = false;

          // Resultados de la imagen principal
          if (result != null && result['center'] != null) {
            _dianaCenter = result['center'] as Offset;
            _detectedCircles = (result['circles'] as List).cast<Map<String, double>>();
            _ringContours = (result['ringContours'] as List?)
                ?.map((contour) => (contour as List)
                    .map((p) => p as Map<String, dynamic>)
                    .toList())
                .toList();
            _spacingPx = (result['spacing'] as num?)?.toDouble();
            _centerMessage = result['message'] as String;
          } else {
            _centerMessage = result?['message'] as String? ?? 'No se detectó el centro';
          }

          // Resultados de la imagen normal (comparación)
          if (resultNormal != null && resultNormal['center'] != null) {
            _dianaCenterNormal = resultNormal['center'] as Offset;
            _detectedCirclesNormal = (resultNormal['circles'] as List).cast<Map<String, double>>();
            _ringContoursNormal = (resultNormal['ringContours'] as List?)
                ?.map((contour) => (contour as List)
                    .map((p) => p as Map<String, dynamic>)
                    .toList())
                .toList();
            _spacingPxNormal = (resultNormal['spacing'] as num?)?.toDouble();
            _centerMessageNormal = resultNormal['message'] as String;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDetectingCenter = false;
          _centerMessage = 'Error: $e';
        });
      }
    }
  }

  /// Detecta impactos (agujeros de bala) en la imagen recortada
  Future<void> _detectImpacts() async {
    if (_croppedImage == null || _dianaCenter == null ||
        _detectedCircles == null || _spacingPx == null) return;

    setState(() {
      _isDetectingImpacts = true;
      _impactsMessage = 'Detectando impactos...';
      _impacts = null;
    });

    try {
      final bytes = await _croppedImage!.readAsBytes();

      // Extraer radios de los anillos
      final ringRadii = _detectedCircles!.map((c) => c['r']!).toList();

      final result = await OpenCVService.detectImpacts(
        bytes,
        center: _dianaCenter!,
        ringRadii: ringRadii,
        spacingPx: _spacingPx!,
      );

      if (mounted) {
        setState(() {
          _isDetectingImpacts = false;
          _impacts = (result['impacts'] as List).cast<Map<String, double>>();
          _impactsMessage = result['message'] as String;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDetectingImpacts = false;
          _impactsMessage = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorte Diana (OpenCV)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          // Botón para re-detectar
          if (_selectedImage != null)
            IconButton(
              onPressed: _isDetecting ? null : () => _detectCorners(_selectedImage!),
              icon: const Icon(Icons.refresh),
              tooltip: 'Re-detectar esquinas',
            ),
        ],
      ),
      body: Column(
        children: [
          // Botones para seleccionar imagen
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isDetecting ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cámara'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isDetecting ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galería'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Mensaje de estado de detección
          if (_detectionMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _isDetecting
                    ? Colors.blue.shade50
                    : (_cornersAutoDetected ? Colors.green.shade50 : Colors.orange.shade50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isDetecting
                      ? Colors.blue.shade300
                      : (_cornersAutoDetected ? Colors.green.shade300 : Colors.orange.shade300),
                ),
              ),
              child: Row(
                children: [
                  if (_isDetecting)
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _cornersAutoDetected ? Icons.check_circle : Icons.touch_app,
                      size: 18,
                      color: _cornersAutoDetected ? Colors.green : Colors.orange,
                    ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_detectionMessage!, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Imagen original con esquinas + imagen recortada
          Expanded(
            child: _selectedImage != null
                ? _croppedImage != null
                    // Mostrar ambas imágenes: original arriba, recortada abajo
                    ? Column(
                        children: [
                          // Imagen original (pequeña)
                          Expanded(
                            flex: 2,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Image.file(
                                      _selectedImage!,
                                      fit: BoxFit.contain,
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                    ),
                                    if (_detectedCorners != null && _imageSize != null)
                                      _buildCornersOverlay(constraints),
                                  ],
                                );
                              },
                            ),
                          ),
                          // Separador
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            color: Colors.grey.shade200,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.arrow_downward, size: 16, color: Colors.indigo),
                                SizedBox(width: 4),
                                Text('Imagen recortada (perspectiva corregida)',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_downward, size: 16, color: Colors.indigo),
                              ],
                            ),
                          ),
                          // Botón de comparación (solo en modo pliegue con ambas imágenes)
                          if (_foldMode && _croppedImageNormal != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              color: Colors.grey.shade200,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.compare, size: 16, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  const Text('Comparar:', style: TextStyle(fontSize: 12)),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Pliegue', style: TextStyle(fontSize: 11)),
                                    selected: !_showComparison,
                                    selectedColor: Colors.orange.shade200,
                                    onSelected: (_) => setState(() => _showComparison = false),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text('Normal', style: TextStyle(fontSize: 11)),
                                    selected: _showComparison,
                                    selectedColor: Colors.green.shade200,
                                    onSelected: (_) => setState(() => _showComparison = true),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          // Imagen recortada con círculos detectados
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final displayImage = (_showComparison && _croppedImageNormal != null)
                                      ? _croppedImageNormal!
                                      : _croppedImage!;
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Image.file(
                                        displayImage,
                                        fit: BoxFit.contain,
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                      ),
                                      // Etiqueta de qué versión se muestra
                                      if (_foldMode && _croppedImageNormal != null)
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: _showComparison
                                                  ? Colors.green.shade700.withValues(alpha: 0.85)
                                                  : Colors.orange.shade700.withValues(alpha: 0.85),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              _showComparison ? 'SIN pliegue' : 'CON pliegue',
                                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      // Dibujar centro, anillos e impactos
                                      if (_showComparison && _dianaCenterNormal != null && _croppedImageSize != null)
                                        _buildCroppedOverlayFor(
                                          constraints,
                                          center: _dianaCenterNormal!,
                                          circles: _detectedCirclesNormal,
                                          ringContours: _ringContoursNormal,
                                          impacts: null, // Sin impactos en comparación
                                        )
                                      else if (!_showComparison && _dianaCenter != null && _croppedImageSize != null)
                                        _buildCroppedOverlay(constraints),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      )
                    // Imagen original con esquinas interactivas
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.file(
                                _selectedImage!,
                                fit: BoxFit.contain,
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                              ),
                              if (_detectedCorners != null && _imageSize != null)
                                _buildInteractiveCornersOverlay(constraints),
                            ],
                          );
                        },
                      )
                : const Center(
                    child: Text(
                      'Selecciona una imagen de diana',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
          ),

          // Botón de recortar + info de esquinas
          if (_detectedCorners != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Column(
                children: [
                  // Coordenadas
                  Text(
                    'TL: (${_detectedCorners![0].dx.toStringAsFixed(0)}, ${_detectedCorners![0].dy.toStringAsFixed(0)})  '
                    'TR: (${_detectedCorners![1].dx.toStringAsFixed(0)}, ${_detectedCorners![1].dy.toStringAsFixed(0)})  '
                    'BL: (${_detectedCorners![2].dx.toStringAsFixed(0)}, ${_detectedCorners![2].dy.toStringAsFixed(0)})  '
                    'BR: (${_detectedCorners![3].dx.toStringAsFixed(0)}, ${_detectedCorners![3].dy.toStringAsFixed(0)})'
                    '${_foldMode && _detectedCorners!.length >= 6 ? '\nPT: (${_detectedCorners![4].dx.toStringAsFixed(0)}, ${_detectedCorners![4].dy.toStringAsFixed(0)})  PB: (${_detectedCorners![5].dx.toStringAsFixed(0)}, ${_detectedCorners![5].dy.toStringAsFixed(0)})' : ''}',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 6),
                  // Toggle modo pliegue
                  Row(
                    children: [
                      Icon(
                        _foldMode ? Icons.unfold_more : Icons.crop_square,
                        size: 18,
                        color: _foldMode ? Colors.orange : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      const Text('Diana doblada', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      Switch(
                        value: _foldMode,
                        activeTrackColor: Colors.orange.shade200,
                        thumbColor: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected) ? Colors.orange : null),
                        onChanged: (_) => _toggleFoldMode(),
                      ),
                      if (_foldMode)
                        const Expanded(
                          child: Text(
                            'Arrastra PT y PB al pliegue',
                            style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
                            textAlign: TextAlign.right,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Botones de acción
                  Row(
                    children: [
                      // Botón de recortar
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isCropping ? null : _cropImage,
                          icon: _isCropping
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.crop, size: 18),
                          label: Text(
                            _croppedImage != null
                                ? 'Re-recortar'
                                : (_foldMode ? 'Corregir pliegue' : 'Recortar'),
                            style: const TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _foldMode ? Colors.orange.shade700 : Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      // Botón de detectar centro (solo si hay imagen recortada)
                      if (_croppedImage != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isDetectingCenter ? null : _detectCenter,
                            icon: _isDetectingCenter
                                ? const SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.my_location, size: 18),
                            label: Text(_dianaCenter != null ? 'Re-detectar' : 'Detectar centro',
                              style: const TextStyle(fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Botón de detectar impactos (solo si tenemos centro y spacing)
                  if (_dianaCenter != null && _spacingPx != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isDetectingImpacts ? null : _detectImpacts,
                        icon: _isDetectingImpacts
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.gps_fixed, size: 18),
                        label: Text(
                          _isDetectingImpacts ? 'Detectando...' :
                            (_impacts != null ? 'Re-detectar impactos' : 'Detectar impactos'),
                          style: const TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                  // Info del centro detectado
                  if (_centerMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _dianaCenter != null
                          ? 'Centro: (${_dianaCenter!.dx.toStringAsFixed(1)}, ${_dianaCenter!.dy.toStringAsFixed(1)})  |  $_centerMessage'
                          : _centerMessage!,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: _dianaCenter != null ? Colors.deepPurple : Colors.orange,
                      ),
                    ),
                  ],
                  // Info de impactos
                  if (_impactsMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _impactsMessage!,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: _impacts != null && _impacts!.isNotEmpty
                            ? Colors.red.shade700 : Colors.orange,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Construye el overlay combinado: anillos + impactos
  Widget _buildCroppedOverlay(BoxConstraints constraints) {
    final imgW = _croppedImageSize!.width;
    final imgH = _croppedImageSize!.height;

    final double ratioX = constraints.maxWidth / imgW;
    final double ratioY = constraints.maxHeight / imgH;
    final double displayScale = min(ratioX, ratioY);

    final double displayedW = imgW * displayScale;
    final double displayedH = imgH * displayScale;
    final double offsetX = (constraints.maxWidth - displayedW) / 2;
    final double offsetY = (constraints.maxHeight - displayedH) / 2;

    Offset toScreen(double x, double y) => Offset(
      offsetX + x * displayScale,
      offsetY + y * displayScale,
    );

    // Contornos de anillos
    final screenContours = _ringContours?.map((contour) {
      return contour.map((p) {
        final x = (p['x'] as num).toDouble();
        final y = (p['y'] as num).toDouble();
        return toScreen(x, y);
      }).toList();
    }).toList();

    // Impactos
    final screenImpacts = _impacts?.map((imp) {
      return {
        'center': toScreen(imp['x']!, imp['y']!),
        'radius': imp['r']! * displayScale,
        'groupCount': imp['groupCount'] ?? 1.0,
      };
    }).toList();

    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: CustomPaint(
        painter: _DianaOverlayPainter(
          center: toScreen(_dianaCenter!.dx, _dianaCenter!.dy),
          ringContours: screenContours ?? [],
          numRings: _detectedCircles?.length ?? 0,
          impacts: screenImpacts ?? [],
        ),
      ),
    );
  }

  /// Overlay con datos explícitos (para comparación con imagen normal)
  Widget _buildCroppedOverlayFor(
    BoxConstraints constraints, {
    required Offset center,
    List<Map<String, double>>? circles,
    List<List<Map<String, dynamic>>>? ringContours,
    List<Map<String, double>>? impacts,
  }) {
    final imgW = _croppedImageSize!.width;
    final imgH = _croppedImageSize!.height;

    final double ratioX = constraints.maxWidth / imgW;
    final double ratioY = constraints.maxHeight / imgH;
    final double displayScale = min(ratioX, ratioY);

    final double displayedW = imgW * displayScale;
    final double displayedH = imgH * displayScale;
    final double offsetX = (constraints.maxWidth - displayedW) / 2;
    final double offsetY = (constraints.maxHeight - displayedH) / 2;

    Offset toScreen(double x, double y) => Offset(
      offsetX + x * displayScale,
      offsetY + y * displayScale,
    );

    final screenContours = ringContours?.map((contour) {
      return contour.map((p) {
        final x = (p['x'] as num).toDouble();
        final y = (p['y'] as num).toDouble();
        return toScreen(x, y);
      }).toList();
    }).toList();

    final screenImpacts = impacts?.map((imp) {
      return {
        'center': toScreen(imp['x']!, imp['y']!),
        'radius': imp['r']! * displayScale,
        'groupCount': imp['groupCount'] ?? 1.0,
      };
    }).toList();

    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: CustomPaint(
        painter: _DianaOverlayPainter(
          center: toScreen(center.dx, center.dy),
          ringContours: screenContours ?? [],
          numRings: circles?.length ?? 0,
          impacts: screenImpacts ?? [],
        ),
      ),
    );
  }

  /// Construye el overlay con los contornos reales y el centro de la diana (legacy)
  Widget _buildCirclesOverlay(BoxConstraints constraints) {
    final imgW = _croppedImageSize!.width;
    final imgH = _croppedImageSize!.height;

    // Calcular cómo se ajusta la imagen recortada (BoxFit.contain)
    final double ratioX = constraints.maxWidth / imgW;
    final double ratioY = constraints.maxHeight / imgH;
    final double scale = min(ratioX, ratioY);

    final double displayedW = imgW * scale;
    final double displayedH = imgH * scale;
    final double offsetX = (constraints.maxWidth - displayedW) / 2;
    final double offsetY = (constraints.maxHeight - displayedH) / 2;

    // Convertir coordenadas de imagen a pantalla
    Offset toScreen(double x, double y) => Offset(
      offsetX + x * scale,
      offsetY + y * scale,
    );

    // Convertir contornos reales a coordenadas de pantalla
    final screenContours = _ringContours?.map((contour) {
      return contour.map((p) {
        final x = (p['x'] as num).toDouble();
        final y = (p['y'] as num).toDouble();
        return toScreen(x, y);
      }).toList();
    }).toList();

    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: CustomPaint(
        painter: _CirclesPainter(
          center: toScreen(_dianaCenter!.dx, _dianaCenter!.dy),
          ringContours: screenContours ?? [],
          numRings: _detectedCircles?.length ?? 0,
        ),
      ),
    );
  }

  /// Construye el overlay con las esquinas y el cuadrilátero dibujado
  Widget _buildCornersOverlay(BoxConstraints constraints) {
    final imgW = _imageSize!.width;
    final imgH = _imageSize!.height;

    final double ratioX = constraints.maxWidth / imgW;
    final double ratioY = constraints.maxHeight / imgH;
    final double scale = min(ratioX, ratioY);

    final double displayedW = imgW * scale;
    final double displayedH = imgH * scale;
    final double offsetX = (constraints.maxWidth - displayedW) / 2;
    final double offsetY = (constraints.maxHeight - displayedH) / 2;

    Offset toScreen(Offset imgPt) => Offset(
      offsetX + imgPt.dx * scale,
      offsetY + imgPt.dy * scale,
    );

    final screenCorners = _detectedCorners!.map(toScreen).toList();

    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: CustomPaint(
        painter: _CornersPainter(screenCorners, foldMode: _foldMode),
      ),
    );
  }

  /// Overlay interactivo: esquinas que se pueden arrastrar
  Widget _buildInteractiveCornersOverlay(BoxConstraints constraints) {
    final imgW = _imageSize!.width;
    final imgH = _imageSize!.height;

    final double ratioX = constraints.maxWidth / imgW;
    final double ratioY = constraints.maxHeight / imgH;
    final double scale = min(ratioX, ratioY);

    final double displayedW = imgW * scale;
    final double displayedH = imgH * scale;
    final double offsetX = (constraints.maxWidth - displayedW) / 2;
    final double offsetY = (constraints.maxHeight - displayedH) / 2;

    Offset toScreen(Offset imgPt) => Offset(
      offsetX + imgPt.dx * scale,
      offsetY + imgPt.dy * scale,
    );

    Offset toImage(Offset screenPt) => Offset(
      (screenPt.dx - offsetX) / scale,
      (screenPt.dy - offsetY) / scale,
    );

    final screenCorners = _detectedCorners!.map(toScreen).toList();
    const double hitRadius = 28.0; // Radio de detección táctil

    final int numPoints = _foldMode && screenCorners.length >= 6 ? 6 : 4;

    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: GestureDetector(
        onPanStart: (details) {
          final pos = details.localPosition;
          // Buscar el punto más cercano dentro del radio de hit
          double minDist = double.infinity;
          int? closestIdx;
          for (int i = 0; i < numPoints; i++) {
            final dist = (screenCorners[i] - pos).distance;
            if (dist < hitRadius && dist < minDist) {
              minDist = dist;
              closestIdx = i;
            }
          }
          setState(() {
            _draggingCornerIndex = closestIdx;
          });
        },
        onPanUpdate: (details) {
          if (_draggingCornerIndex == null) return;
          final newScreenPos = details.localPosition;
          // Convertir a coordenadas de imagen y limitar a los bordes
          final imgPt = toImage(newScreenPos);
          final clampedX = imgPt.dx.clamp(0.0, imgW);
          final clampedY = imgPt.dy.clamp(0.0, imgH);
          setState(() {
            _detectedCorners![_draggingCornerIndex!] = Offset(clampedX, clampedY);
            // Limpiar el recorte anterior cuando se mueven los puntos
            _croppedImage = null;
          });
        },
        onPanEnd: (_) {
          setState(() {
            _draggingCornerIndex = null;
          });
        },
        child: CustomPaint(
          painter: _CornersPainter(
            screenCorners,
            activeIndex: _draggingCornerIndex,
            foldMode: _foldMode,
          ),
        ),
      ),
    );
  }
}

/// Pinta anillos, centro e impactos sobre la imagen recortada
class _DianaOverlayPainter extends CustomPainter {
  final Offset center;
  final List<List<Offset>> ringContours;
  final int numRings;
  final List<Map<String, dynamic>> impacts; // {center: Offset, radius: double}

  _DianaOverlayPainter({
    required this.center,
    required this.ringContours,
    required this.numRings,
    required this.impacts,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // --- Anillos ---
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < ringContours.length; i++) {
      final points = ringContours[i];
      if (points.length < 3) continue;

      ringPaint.color = HSLColor.fromAHSL(
        0.85, (i * 37.0) % 360, 0.9, 0.5,
      ).toColor();

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int j = 1; j < points.length; j++) {
        path.lineTo(points[j].dx, points[j].dy);
      }
      path.close();
      canvas.drawPath(path, ringPaint);
    }

    // --- Centro ---
    canvas.drawCircle(center, 6, Paint()..color = Colors.red..style = PaintingStyle.fill);
    canvas.drawCircle(center, 6, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);

    final crossPaint = Paint()..color = Colors.red..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawLine(Offset(center.dx - 20, center.dy), Offset(center.dx + 20, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 20), Offset(center.dx, center.dy + 20), crossPaint);

    // Etiqueta anillos
    final ringLabel = TextPainter(
      text: TextSpan(
        text: '$numRings anillos',
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold,
          backgroundColor: Colors.red.withValues(alpha: 0.7)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ringLabel.paint(canvas, center + const Offset(10, 10));

    // --- Impactos ---
    if (impacts.isEmpty) return;

    for (int i = 0; i < impacts.length; i++) {
      final imp = impacts[i];
      final c = imp['center'] as Offset;
      final r = imp['radius'] as double;

      // Círculo exterior (marcador amarillo)
      final markerPaint = Paint()
        ..color = Colors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(c, r + 4, markerPaint);

      // Círculo interior (rojo)
      final fillPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(c, r, fillPaint);

      // Borde del impacto
      final borderPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(c, r, borderPaint);

      // Número del impacto (y grupo si aplica)
      final groupCount = (imp['groupCount'] as num?)?.toInt() ?? 1;
      final label = groupCount > 1 ? '${i + 1} (x$groupCount)' : '${i + 1}';
      final numLabel = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: groupCount > 1 ? Colors.orange : Colors.yellow,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black.withValues(alpha: 0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      numLabel.paint(canvas, c + Offset(r + 6, -6));
    }

    // Etiqueta total de impactos
    final impLabel = TextPainter(
      text: TextSpan(
        text: '${impacts.length} impactos',
        style: TextStyle(color: Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withValues(alpha: 0.7)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    impLabel.paint(canvas, center + const Offset(10, 24));
  }

  @override
  bool shouldRepaint(covariant _DianaOverlayPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.ringContours != ringContours ||
        oldDelegate.impacts != impacts;
  }
}

/// Pinta los contornos reales de los anillos y el centro de la diana
class _CirclesPainter extends CustomPainter {
  final Offset center;
  final List<List<Offset>> ringContours; // Polígonos reales de cada anillo
  final int numRings;

  _CirclesPainter({
    required this.center,
    required this.ringContours,
    required this.numRings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dibujar cada contorno de anillo como un polígono cerrado
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < ringContours.length; i++) {
      final points = ringContours[i];
      if (points.length < 3) continue;

      // Color variado para distinguir cada anillo
      ringPaint.color = HSLColor.fromAHSL(
        0.85, (i * 37.0) % 360, 0.9, 0.5,
      ).toColor();

      // Dibujar como path cerrado (sigue la forma real del anillo)
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int j = 1; j < points.length; j++) {
        path.lineTo(points[j].dx, points[j].dy);
      }
      path.close();

      canvas.drawPath(path, ringPaint);
    }

    // Dibujar el centro (cruz + punto)
    final centerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, centerPaint);

    final centerBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 6, centerBorder);

    // Cruz
    final crossPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(center.dx - 20, center.dy),
      Offset(center.dx + 20, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 20),
      Offset(center.dx, center.dy + 20),
      crossPaint,
    );

    // Etiqueta
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$numRings anillos',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.red.withValues(alpha: 0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, center + const Offset(10, 10));
  }

  @override
  bool shouldRepaint(covariant _CirclesPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.ringContours != ringContours;
  }
}

/// Pinta el cuadrilátero y los puntos de las esquinas detectadas.
/// Soporta 4 puntos (normal) o 6 puntos (modo pliegue: 4 esquinas + 2 pliegue).
/// Orden de puntos: [TL, TR, BL, BR, foldTop?, foldBottom?]
class _CornersPainter extends CustomPainter {
  final List<Offset> corners; // [TL, TR, BL, BR] o [TL, TR, BL, BR, FT, FB]
  final int? activeIndex; // Punto siendo arrastrado
  final bool foldMode; // Si estamos en modo pliegue (6 puntos)

  _CornersPainter(this.corners, {this.activeIndex, this.foldMode = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;

    final tl = corners[0];
    final tr = corners[1];
    final bl = corners[2];
    final br = corners[3];

    if (foldMode && corners.length >= 6) {
      final ft = corners[4]; // Fold Top
      final fb = corners[5]; // Fold Bottom

      // Mitad izquierda (semitransparente azul)
      final fillLeft = Paint()
        ..color = Colors.blue.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      final pathLeft = Path()
        ..moveTo(tl.dx, tl.dy)
        ..lineTo(ft.dx, ft.dy)
        ..lineTo(fb.dx, fb.dy)
        ..lineTo(bl.dx, bl.dy)
        ..close();
      canvas.drawPath(pathLeft, fillLeft);

      // Mitad derecha (semitransparente verde)
      final fillRight = Paint()
        ..color = Colors.green.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      final pathRight = Path()
        ..moveTo(ft.dx, ft.dy)
        ..lineTo(tr.dx, tr.dy)
        ..lineTo(br.dx, br.dy)
        ..lineTo(fb.dx, fb.dy)
        ..close();
      canvas.drawPath(pathRight, fillRight);

      // Bordes de ambas mitades
      final strokePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawPath(pathLeft, strokePaint);
      canvas.drawPath(pathRight, strokePaint);

      // Línea de pliegue (destacada en naranja discontinuo)
      final foldPaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawLine(ft, fb, foldPaint);
    } else {
      // Modo normal: cuadrilátero único
      final fillPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(tl.dx, tl.dy)
        ..lineTo(tr.dx, tr.dy)
        ..lineTo(br.dx, br.dy)
        ..lineTo(bl.dx, bl.dy)
        ..close();

      canvas.drawPath(path, fillPaint);

      final strokePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawPath(path, strokePaint);
    }

    // Dibujar todos los puntos arrastrables
    final int numPoints = foldMode && corners.length >= 6 ? 6 : 4;
    final labels = foldMode && corners.length >= 6
        ? ['TL', 'TR', 'BL', 'BR', 'PT', 'PB'] // P = Pliegue
        : ['TL', 'TR', 'BL', 'BR'];

    for (int i = 0; i < numPoints; i++) {
      final isActive = i == activeIndex;
      final isFoldPoint = i >= 4;
      final radius = isActive ? 14.0 : 10.0;

      // Círculo exterior (zona de toque visual)
      if (isActive) {
        canvas.drawCircle(
          corners[i], 22,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3)
            ..style = PaintingStyle.fill,
        );
      }

      // Color: naranja para puntos de pliegue, amarillo para esquinas
      final Color fillColor = isActive
          ? Colors.greenAccent
          : (isFoldPoint ? Colors.orange.shade300 : Colors.yellow);
      final Color strokeColor = isActive
          ? Colors.green.shade900
          : (isFoldPoint ? Colors.deepOrange.shade900 : Colors.red.shade900);

      // Punto principal
      canvas.drawCircle(
        corners[i], radius,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        corners[i], radius,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Etiqueta
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: strokeColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, corners[i] + Offset(radius + 4, -8));
    }
  }

  @override
  bool shouldRepaint(covariant _CornersPainter oldDelegate) {
    return true; // Repintar siempre para reflejar el arrastre en tiempo real
  }
}
