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
  
  // Esquinas detectadas en coordenadas de imagen (píxeles reales)
  List<Offset>? _detectedCorners;
  bool _isDetecting = false;
  String? _detectionMessage;
  
  // Tamaño real de la imagen para poder convertir coordenadas
  Size? _imageSize;

  // Imagen recortada (resultado del warpPerspective)
  File? _croppedImage;
  bool _isCropping = false;

  /// Selecciona una imagen desde cámara o galería
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null && mounted) {
        final file = File(pickedFile.path);
        setState(() {
          _selectedImage = file;
          _detectedCorners = null;
          _detectionMessage = null;
          _imageSize = null;
          _croppedImage = null;
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

  /// Detecta las 4 esquinas de la diana usando OpenCV
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
            _detectionMessage = 'Detectadas 4 esquinas';
          } else {
            _detectedCorners = null;
            _detectionMessage = 'No se detectaron esquinas';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDetecting = false;
          _detectionMessage = 'Error: $e';
        });
      }
    }
  }

  /// Recorta la imagen usando las esquinas detectadas y OpenCV warpPerspective
  Future<void> _cropImage() async {
    if (_selectedImage == null || _detectedCorners == null || _imageSize == null) return;

    setState(() {
      _isCropping = true;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final corners = _detectedCorners!;

      // Calcular tamaño de salida basado en las esquinas
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

      final result = await OpenCVService.cropWithPerspective(
        bytes, corners, outputWidth, outputHeight,
      );

      if (mounted) {
        setState(() {
          _isCropping = false;
          _croppedImage = result;
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
                color: _detectedCorners != null
                    ? Colors.green.shade50
                    : (_isDetecting ? Colors.blue.shade50 : Colors.orange.shade50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _detectedCorners != null
                      ? Colors.green.shade300
                      : (_isDetecting ? Colors.blue.shade300 : Colors.orange.shade300),
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
                      _detectedCorners != null ? Icons.check_circle : Icons.warning,
                      size: 18,
                      color: _detectedCorners != null ? Colors.green : Colors.orange,
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
                          // Imagen recortada (grande)
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Image.file(
                                _croppedImage!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                      )
                    // Solo imagen original con overlay de esquinas
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
                                _buildCornersOverlay(constraints),
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
                    'BR: (${_detectedCorners![3].dx.toStringAsFixed(0)}, ${_detectedCorners![3].dy.toStringAsFixed(0)})',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  // Botón de recortar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCropping ? null : _cropImage,
                      icon: _isCropping
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.crop),
                      label: Text(_isCropping ? 'Recortando...' : 
                          (_croppedImage != null ? 'Recortar de nuevo' : 'Recortar con OpenCV')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Construye el overlay con las esquinas y el cuadrilátero dibujado
  Widget _buildCornersOverlay(BoxConstraints constraints) {
    final imgW = _imageSize!.width;
    final imgH = _imageSize!.height;

    // Calcular cómo se ajusta la imagen en el espacio disponible (BoxFit.contain)
    final double ratioX = constraints.maxWidth / imgW;
    final double ratioY = constraints.maxHeight / imgH;
    final double scale = min(ratioX, ratioY);

    final double displayedW = imgW * scale;
    final double displayedH = imgH * scale;
    final double offsetX = (constraints.maxWidth - displayedW) / 2;
    final double offsetY = (constraints.maxHeight - displayedH) / 2;

    // Convertir coordenadas de imagen a coordenadas de pantalla
    Offset toScreen(Offset imgPt) => Offset(
      offsetX + imgPt.dx * scale,
      offsetY + imgPt.dy * scale,
    );

    final screenCorners = _detectedCorners!.map(toScreen).toList();

    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: CustomPaint(
        painter: _CornersPainter(screenCorners),
      ),
    );
  }
}

/// Pinta el cuadrilátero y los puntos de las esquinas detectadas
class _CornersPainter extends CustomPainter {
  final List<Offset> corners; // [TL, TR, BL, BR]

  _CornersPainter(this.corners);

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final tl = corners[0];
    final tr = corners[1];
    final bl = corners[2];
    final br = corners[3];

    // Dibujar el cuadrilátero relleno semitransparente
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

    // Dibujar el borde del cuadrilátero
    final strokePaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawPath(path, strokePaint);

    // Dibujar los 4 puntos con etiquetas
    final dotPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;

    final dotBorderPaint = Paint()
      ..color = Colors.red.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final labels = ['TL', 'TR', 'BL', 'BR'];

    for (int i = 0; i < 4; i++) {
      // Círculo
      canvas.drawCircle(corners[i], 8, dotPaint);
      canvas.drawCircle(corners[i], 8, dotBorderPaint);

      // Etiqueta
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.red.shade900,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, corners[i] + const Offset(10, -8));
    }
  }

  @override
  bool shouldRepaint(covariant _CornersPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}
