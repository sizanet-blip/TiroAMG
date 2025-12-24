import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img; 
import 'dart:math';

// =========================================================================
// WIDGET PRINCIPAL Y ENTRADA DE LA APLICACIÓN
// =========================================================================

/// Pantalla inicial para capturar o seleccionar la imagen.
class RecorteDianaScreen extends StatefulWidget {
  const RecorteDianaScreen({super.key});

  @override
  State<RecorteDianaScreen> createState() => _RecorteDianaScreenState();
}

class _RecorteDianaScreenState extends State<RecorteDianaScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  /// Función para capturar una imagen con la cámara o galería.
  Future<void> _pickImage(ImageSource source) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      
      if (pickedFile != null) {
        if (mounted) {
          // Navegar a la pantalla de recorte con la imagen seleccionada.
          final croppedPath = await Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (context) => RecorteDianaCropScreen(imageFile: File(pickedFile.path)),
            ),
          );

          if (croppedPath != null) {
             // Opcional: mostrar un mensaje con la ruta temporal del recorte
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text('Recorte guardado temporalmente en: $croppedPath'),
                 duration: const Duration(seconds: 4),
               ),
             );
          }
        }
      }
    } catch (e) {
      // Manejo de errores
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar la imagen: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura y Recorte de Diana'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'Selecciona la imagen de la diana para aplicar el recorte de 4 puntos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 24),
                label: const Text('Tomar Foto', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(250, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  elevation: 5,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: 24),
                label: const Text('Elegir de Galería', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(250, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  elevation: 5,
                ),
              ),
              if (_isLoading) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// WIDGETS AUXILIARES PARA EL RECORTE
// =========================================================================

/// Custom Painter para dibujar el cuadrilátero que define el área de recorte.
class QuadrilateralPainter extends CustomPainter {
  final Offset tl, tr, bl, br; // Top-Left, Top-Right, Bottom-Left, Bottom-Right

  QuadrilateralPainter({required this.tl, required this.tr, required this.bl, required this.br});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
      
    // Dibujo del borde (línea)
    final strokePaint = Paint()
      ..color = Colors.redAccent.shade700
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Dibujo del relleno semi-transparente
    final fillPaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.15)
      ..style = PaintingStyle.fill;
      
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant QuadrilateralPainter oldDelegate) {
    return oldDelegate.tl != tl || oldDelegate.tr != tr || oldDelegate.bl != bl || oldDelegate.br != br;
  }
}

/// Widget Draggable Handle (Punto de Arrastre).
class DraggableHandle extends StatelessWidget {
  final Offset position;
  final ValueChanged<Offset> onDrag;
  static const double handleSize = 40.0; 
  
  const DraggableHandle({super.key, required this.position, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    // El handle se posiciona en el centro restando la mitad de su tamaño.
    return Positioned(
      left: position.dx - handleSize / 2, 
      top: position.dy - handleSize / 2,
      child: GestureDetector(
        // Al arrastrar, se llama a onDrag con el nuevo Offset.
        onPanUpdate: (details) {
          onDrag(position + details.delta);
        },
        child: Container(
          width: handleSize,
          height: handleSize,
          decoration: BoxDecoration(
            color: Colors.amber.shade700.withOpacity(0.8), // Color más contrastante
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4), // Borde más grueso
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
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

// =========================================================================
// PANTALLA DE RECORTE (RECORTE DIANA)
// =========================================================================

/// Pantalla donde el usuario define el área de recorte arrastrando las 4 esquinas.
class RecorteDianaCropScreen extends StatefulWidget {
  final File imageFile;

  const RecorteDianaCropScreen({super.key, required this.imageFile});

  @override
  State<RecorteDianaCropScreen> createState() => _RecorteDianaCropScreenState();
}

// Estructura para definir los colores de referencia de las esquinas.
class CornerReference {
  final String name;
  Color color; // Ahora es mutable
  final int tolerance; 

  CornerReference(this.name, this.color, {this.tolerance = 70});
}

class _RecorteDianaCropScreenState extends State<RecorteDianaCropScreen> {
  final GlobalKey _imageKey = GlobalKey();
  bool _isLoading = false; 
  late Offset _tl, _tr, _bl, _br; 
  bool _isLayoutCalculated = false;

  // Variables para la calibración de color
  bool _isSamplingMode = false;
  Color? _sampledColor; // Color muestreado temporalmente
  String _samplingMessage = 'Ajusta los puntos o calibra el color.';

  // Definición de las referencias de color iniciales. (Usamos un color por defecto)
  final List<CornerReference> _cornerReferences = [
    CornerReference('tl', Colors.red, tolerance: 70), 
    CornerReference('tr', Colors.red, tolerance: 70), 
    CornerReference('bl', Colors.red, tolerance: 70), 
    CornerReference('br', Colors.red, tolerance: 70), 
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateInitialLayout());
  }

  /// Convierte un color de Flutter a su valor HEX.
  String _colorToName(Color c) {
    // Muestra el valor hexadecimal del color (omitiendo el alfa FF)
    return '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  /// Inicia el modo de muestreo de color.
  void _enterSamplingMode() {
    setState(() {
      _isSamplingMode = true;
      _sampledColor = null; // Reinicia el color muestreado
      _samplingMessage = 'Toca cualquier punto de color de referencia en la imagen para muestrear.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Modo de calibración activado. Toca la imagen.')),
    );
  }

  /// Cancela el modo de muestreo.
  void _cancelSamplingMode() {
    setState(() {
      _isSamplingMode = false;
      _sampledColor = null;
      _samplingMessage = 'Ajusta los puntos o calibra el color.';
    });
  }

  /// Aplica el color muestreado y desencadena la detección automática.
  void _confirmSampledColor() { // <--- Ya no es async (removido 'async')
    if (_sampledColor == null) return;
    
    // 1. Aplicar el color a todas las referencias
    for (var ref in _cornerReferences) {
      ref.color = _sampledColor!;
    }

    // 2. Salir del modo de muestreo y actualizar mensaje
    setState(() {
      _isSamplingMode = false;
      _sampledColor = null;
      _samplingMessage = '¡Color calibrado! Iniciando detección CV...';
    });

    // 3. Iniciar la detección de esquinas con el nuevo color.
    // Llama al método Future<void> sin 'await' para evitar el error 'void used as value'.
    _calculateInitialLayout(); 
  }

  /// Mapea un offset de pantalla a coordenadas de píxeles reales de la imagen.
  Offset _screenToRealCoords(Offset screenOffset, img.Image originalImage, Size containerSize) {
    int actualImageWidth = originalImage.width;
    int actualImageHeight = originalImage.height;
    
    final double ratioX = containerSize.width / actualImageWidth;
    final double ratioY = containerSize.height / actualImageHeight;
    final double scaleFactor = min(ratioX, ratioY);
    
    final double displayedWidth = actualImageWidth * scaleFactor;
    final double displayedHeight = actualImageHeight * scaleFactor;

    final double horizontalOffset = (containerSize.width - displayedWidth) / 2;
    final double verticalOffset = (containerSize.height - displayedHeight) / 2;

    final double x = (screenOffset.dx - horizontalOffset) / scaleFactor;
    final double y = (screenOffset.dy - verticalOffset) / scaleFactor;
    
    return Offset(x.clamp(0.0, actualImageWidth.toDouble()), y.clamp(0.0, actualImageHeight.toDouble()));
  }

  /// Procesa el toque del usuario para capturar el color de referencia.
  void _processSample(Offset tapOffset) async {
    // Si ya muestreamos un color, esperamos la confirmación
    if (!_isSamplingMode || _sampledColor != null) return;

    setState(() {
      _isLoading = true;
    });

    final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
    final containerSize = renderBox.size;

    try {
      final Uint8List bytes = await widget.imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) throw Exception("No se pudo decodificar la imagen.");

      // 1. Mapear el toque de pantalla a coordenadas de píxeles reales
      final realCoords = _screenToRealCoords(tapOffset, originalImage, containerSize);
      final int x = realCoords.dx.toInt();
      final int y = realCoords.dy.toInt();

      if (x < 0 || y < 0 || x >= originalImage.width || y >= originalImage.height) {
          throw Exception("El toque está fuera de los límites de la imagen.");
      }

      // 2. Muestrear el color
      final img.Pixel pixel = originalImage.getPixelSafe(x, y);
      final sampledColor = Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
      final colorName = _colorToName(sampledColor);

      // 3. Almacenar el color muestreado y actualizar mensaje para mostrar el diálogo
      setState(() {
        _sampledColor = sampledColor;
        _samplingMessage = 'Color capturado: $colorName. Confirma para continuar.';
      });
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error durante el muestreo: ${e.toString()}')),
        );
      }
      _cancelSamplingMode();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// CV Helper: Comprueba si hay un borde fuerte en las coordenadas (x, y)
  double _getLuminance(img.Pixel pixel) {
    // Cálculo simple de luminancia para detectar cambios de intensidad (bordes)
    return (0.2126 * pixel.r.toDouble() + 0.7152 * pixel.g.toDouble() + 0.0722 * pixel.b.toDouble());
  }

  bool _hasStrongEdge(img.Image originalImage, int x, int y, double threshold) {
    if (x <= 0 || y <= 0 || x >= originalImage.width - 1 || y >= originalImage.height - 1) {
      return false;
    }

    final p00 = originalImage.getPixelSafe(x - 1, y - 1);
    final p01 = originalImage.getPixelSafe(x, y - 1);
    final p02 = originalImage.getPixelSafe(x + 1, y - 1);
    final p10 = originalImage.getPixelSafe(x - 1, y);
    final p12 = originalImage.getPixelSafe(x + 1, y);
    final p20 = originalImage.getPixelSafe(x - 1, y + 1);
    final p21 = originalImage.getPixelSafe(x, y + 1);
    final p22 = originalImage.getPixelSafe(x + 1, y + 1);
    
    // Convertir a luminancia
    final l00 = _getLuminance(p00);
    final l01 = _getLuminance(p01);
    final l02 = _getLuminance(p02);
    final l10 = _getLuminance(p10);
    final l12 = _getLuminance(p12);
    final l20 = _getLuminance(p20);
    final l21 = _getLuminance(p21);
    final l22 = _getLuminance(p22);
    
    // Operador Sobel simple (aproximación del gradiente)
    final gx = (l20 + 2 * l21 + l22) - (l00 + 2 * l01 + l02);
    final gy = (l02 + 2 * l12 + l22) - (l00 + 2 * l10 + l20);
    
    final magnitude = sqrt(gx * gx + gy * gy);
    
    // Umbral empírico: un valor alto indica un cambio brusco (borde)
    return magnitude > threshold; 
  }


  /// Busca las coordenadas reales de los colores de referencia en la imagen.
  /// Devuelve un mapa de 'tl', 'tr', 'bl', 'br' con las coordenadas reales (píxeles de imagen).
  Future<Map<String, Offset>?> _findColoredCorners(img.Image originalImage) async {
    final Map<String, List<Offset>> foundPoints = {
      'tl': [], 'tr': [], 'bl': [], 'br': []
    };

    final int width = originalImage.width;
    final int height = originalImage.height;

    // Lógica de búsqueda optimizada: escanea solo el 20% del borde
    const double scanRatio = 0.2; 
    final int scanAreaX = (width * scanRatio).toInt();
    final int scanAreaY = (height * scanRatio).toInt();

    // Solo necesitamos la primera referencia ya que todas son iguales
    final ref = _cornerReferences[0];
    const double edgeThreshold = 100.0; // Umbral para la detección de bordes (ajustable)

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Optimización: Solo escanea si está cerca de un borde de la imagen
        if (x > scanAreaX && x < (width - scanAreaX) && y > scanAreaY && y < (height - scanAreaY)) {
          continue;
        }

        final img.Pixel pixel = originalImage.getPixelSafe(x, y);
        final int r = pixel.r.toInt();
        final int g = pixel.g.toInt();
        final int b = pixel.b.toInt();
        
        // 1. Detección de Color (Segmentación)
        final int rDiff = (r - ref.color.red).abs();
        final int gDiff = (g - ref.color.green).abs();
        final int bDiff = (b - ref.color.blue).abs();
        final int colorDistance = rDiff + gDiff + bDiff;
        
        bool colorMatches = colorDistance < ref.tolerance * 3;
        
        // 2. Detección de Bordes (CV Avanzado)
        bool isStrongEdge = _hasStrongEdge(originalImage, x, y, edgeThreshold);

        // 3. Combinación de CV: solo aceptar si el color coincide Y es un borde
        if (colorMatches && isStrongEdge) {
          // Asignar el punto encontrado a una de las 4 esquinas geográficas
          String cornerName;
          if (x < width / 2 && y < height / 2) {
            cornerName = 'tl';
          } else if (x >= width / 2 && y < height / 2) {
            cornerName = 'tr';
          } else if (x < width / 2 && y >= height / 2) {
            cornerName = 'bl';
          } else {
            cornerName = 'br';
          }

          foundPoints[cornerName]?.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }

    final Map<String, Offset> finalCorners = {};

    for (var entry in foundPoints.entries) {
      if (entry.value.isNotEmpty) {
        // Calcula el punto promedio de todos los puntos encontrados para esa región
        final double avgX = entry.value.map((p) => p.dx).reduce((a, b) => a + b) / entry.value.length;
        final double avgY = entry.value.map((p) => p.dy).reduce((a, b) => a + b) / entry.value.length;
        finalCorners[entry.key] = Offset(avgX, avgY);
      }
    }

    // Se requieren al menos 3 puntos para definir un área.
    return finalCorners.length >= 3 ? finalCorners : null;
  }


  /// Inicializa los puntos de arrastre. Primero intenta la detección de color, luego usa valores por defecto.
  void _calculateInitialLayout() async {
    // 1. Iniciar el estado de carga
    if (!_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || renderBox.size.isEmpty) {
      // Si falla la obtención de RenderBox, salimos del estado de carga.
      if (mounted) {
        setState(() {
          _isLayoutCalculated = false;
          _isLoading = false;
        });
      }
      return;
    }
    
    final size = renderBox.size;
    Map<String, Offset>? detectedCorners;
    
    try {
      final Uint8List bytes = await widget.imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);
      
      if (originalImage != null) {
        detectedCorners = await _findColoredCorners(originalImage);
      }

      // Necesitamos el tamaño original de la imagen para la escala precisa
      int actualImageWidth = originalImage?.width ?? 1;
      int actualImageHeight = originalImage?.height ?? 1;

      // Calcular factor de escala para mapear píxeles reales a coordenadas de pantalla
      final double ratioX = size.width / actualImageWidth;
      final double ratioY = size.height / actualImageHeight;
      final double scaleFactor = min(ratioX, ratioY);
      
      final double displayedWidth = actualImageWidth * scaleFactor;
      final double displayedHeight = actualImageHeight * scaleFactor;

      final double horizontalOffset = (size.width - displayedWidth) / 2;
      final double verticalOffset = (size.height - displayedHeight) / 2;

      // Definir puntos por defecto (si la detección falla)
      final defaultTL = Offset(size.width * 0.1, size.height * 0.1);
      final defaultTR = Offset(size.width * 0.9, size.height * 0.1);
      final defaultBL = Offset(size.width * 0.1, size.height * 0.9);
      final defaultBR = Offset(size.width * 0.9, size.height * 0.9);

      // Definir los puntos calculados/mapeados
      Offset mapToScreen(Offset realCoords) {
        return Offset(
          realCoords.dx * scaleFactor + horizontalOffset,
          realCoords.dy * scaleFactor + verticalOffset,
        );
      }


      setState(() {
        if (detectedCorners != null) {
          
          // Mapear las coordenadas reales de la imagen a las coordenadas de pantalla.
          // Aquí garantizamos la asignación explícita para evitar errores de tipo/inicialización.
          _tl = detectedCorners.containsKey('tl') ? mapToScreen(detectedCorners['tl']!) : defaultTL;
          _tr = detectedCorners.containsKey('tr') ? mapToScreen(detectedCorners['tr']!) : defaultTR;
          _bl = detectedCorners.containsKey('bl') ? mapToScreen(detectedCorners['bl']!) : defaultBL;
          _br = detectedCorners.containsKey('br') ? mapToScreen(detectedCorners['br']!) : defaultBR;
          
          // Clamping para asegurar que los puntos no se salgan demasiado del borde visible.
          _tl = Offset(_tl.dx.clamp(0.0, size.width), _tl.dy.clamp(0.0, size.height));
          _tr = Offset(_tr.dx.clamp(0.0, size.width), _tr.dy.clamp(0.0, size.height));
          _bl = Offset(_bl.dx.clamp(0.0, size.width), _bl.dy.clamp(0.0, size.height));
          _br = Offset(_br.dx.clamp(0.0, size.width), _br.dy.clamp(0.0, size.height));


          if(mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Esquinas detectadas automáticamente con Detección de Bordes.')),
            );
          }
        } else {
          // Inicialización por defecto si la detección falla
          _tl = defaultTL;
          _tr = defaultTR;
          _bl = defaultBL;
          _br = defaultBR;
        }
        _isLayoutCalculated = true;
      });

    } catch (e) {
      // Manejo de errores en la detección
      print('Error en la detección de color y borde: $e');
      setState(() {
        _tl = Offset(size.width * 0.1, size.height * 0.1);
        _tr = Offset(size.width * 0.9, size.height * 0.1);
        _bl = Offset(size.width * 0.1, size.height * 0.9);
        _br = Offset(size.width * 0.9, size.height * 0.9);
        _isLayoutCalculated = true;
        if(mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error CV. Usando valores por defecto.')),
          );
        }
      });
    } finally {
      // 2. Finalizar el estado de carga
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Actualiza la posición de un punto, asegurándose de que permanezca dentro de los límites.
  void _updatePoint(String corner, Offset newPosition) {
    if (!_isLayoutCalculated || _imageKey.currentContext == null) return;

    final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    
    // Sujeta la posición dentro de los límites del contenedor.
    final clampedX = newPosition.dx.clamp(0.0, size.width);
    final clampedY = newPosition.dy.clamp(0.0, size.height);
    final clampedOffset = Offset(clampedX, clampedY);

    setState(() {
      switch (corner) {
        case 'tl': _tl = clampedOffset; break;
        case 'tr': _tr = clampedOffset; break;
        case 'bl': _bl = clampedOffset; break;
        case 'br': _br = clampedOffset; break;
      }
    });
  }

  /// Función para realizar el recorte real y guardar la nueva imagen.
  Future<void> _performCrop() async {
    if (!_isLayoutCalculated || _imageKey.currentContext == null) return;

    setState(() {
      _isLoading = true;
    });

    final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
    final containerSize = renderBox.size;

    try {
      // 1. Leer la imagen original.
      final Uint8List bytes = await widget.imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        throw Exception("No se pudo decodificar la imagen.");
      }

      final double originalWidth = originalImage.width.toDouble();
      final double originalHeight = originalImage.height.toDouble();

      // Obtener el tamaño de la imagen dibujada en pantalla (requiere una lógica similar a la de _calculateInitialLayout)
      int actualImageWidth = originalImage.width;
      int actualImageHeight = originalImage.height;
      
      final double ratioX = containerSize.width / actualImageWidth;
      final double ratioY = containerSize.height / actualImageHeight;
      final double scaleFactor = min(ratioX, ratioY);
      
      final double displayedWidth = actualImageWidth * scaleFactor;
      final double displayedHeight = actualImageHeight * scaleFactor;

      final double horizontalOffset = (containerSize.width - displayedWidth) / 2;
      final double verticalOffset = (containerSize.height - displayedHeight) / 2;

      // Deshacer el mapeo de pantalla para obtener coordenadas de píxeles reales
      Offset toRealCoords(Offset screenOffset) {
        final double x = (screenOffset.dx - horizontalOffset) / scaleFactor;
        final double y = (screenOffset.dy - verticalOffset) / scaleFactor;
        return Offset(x, y);
      }
      
      final realPoints = [
        toRealCoords(_tl),
        toRealCoords(_tr),
        toRealCoords(_bl),
        toRealCoords(_br),
      ];
      

      // 4. Calcular el Bounding Box (la caja rectangular más pequeña que contiene los 4 puntos).
      final minX = realPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b).toInt().clamp(0, originalWidth.toInt());
      final maxX = realPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b).toInt().clamp(0, originalWidth.toInt());
      final minY = realPoints.map((p) => p.dy).reduce((a, b) => a < b ? a : b).toInt().clamp(0, originalHeight.toInt());
      final maxY = realPoints.map((p) => p.dy).reduce((a, b) => a > b ? a : b).toInt().clamp(0, originalHeight.toInt());

      final cropWidth = (maxX - minX);
      final cropHeight = (maxY - minY);

      if (cropWidth <= 0 || cropHeight <= 0) {
         throw Exception("El área de recorte es inválida o demasiado pequeña.");
      }

      // 5. Aplicar el recorte.
      img.Image croppedImage = img.copyCrop(
        originalImage, 
        x: minX, 
        y: minY, 
        width: cropWidth, 
        height: cropHeight
      );

      // 6. Codificar y guardar el nuevo archivo.
      final Uint8List? encodedBytes = img.encodeJpg(croppedImage, quality: 90);
      if (encodedBytes == null) {
         throw Exception("No se pudo codificar la imagen recortada.");
      }
      
      final tempDir = await getTemporaryDirectory();
      // Guardar como JPG real.
      final croppedFilePath = '${tempDir.path}/cropped_diana_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      await File(croppedFilePath).writeAsBytes(encodedBytes);

      if (mounted) {
        // Volver a la pantalla anterior, devolviendo la ruta del archivo recortado.
        Navigator.pop(context, croppedFilePath);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al recortar la imagen: ${e.toString()}')),
        );
      }
      if (mounted) Navigator.pop(context, null); // Vuelve sin ruta
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildColorConfirmationOverlay() {
    if (_sampledColor == null) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black38)],
        ),
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Color Capturado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _sampledColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300, width: 2),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _colorToName(_sampledColor!), 
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _sampledColor = null;
                    _samplingMessage = 'Toca de nuevo para recalibrar.';
                  }),
                  child: const Text('REINTENTAR', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: _confirmSampledColor,
                  child: const Text('ACEPTAR COLOR'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Definir Área de Diana'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isSamplingMode ? Icons.close : Icons.colorize),
            onPressed: _isLoading ? null : (_isSamplingMode ? _cancelSamplingMode : _enterSamplingMode),
            tooltip: _isSamplingMode ? 'Cancelar Calibración' : 'Calibrar Colores',
          ),
          IconButton(
            icon: const Icon(Icons.crop),
            onPressed: _isLayoutCalculated && !_isLoading && !_isSamplingMode ? _performCrop : null,
            tooltip: 'Confirmar Recorte',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Muestra el mensaje de guía en el modo de muestreo
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _samplingMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: _isSamplingMode ? Colors.indigo.shade700 : Colors.grey.shade600,
                    fontWeight: _isSamplingMode ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),

              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          // Solo permitimos tocar si estamos muestreando Y aún no hemos capturado un color
                          onTapUp: _isSamplingMode && _sampledColor == null ? (details) => _processSample(details.localPosition) : null,
                          child: Container( 
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                              maxHeight: constraints.maxHeight,
                            ),
                            child: Stack(
                              key: _imageKey, // Key para obtener el tamaño de este contenedor
                              fit: StackFit.expand,
                              children: [
                                // 1. La imagen de la diana original
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Image.file(widget.imageFile, fit: BoxFit.contain),
                                ),

                                // 2. Dibujador del cuadrilátero (visible solo si el layout está listo)
                                if (_isLayoutCalculated) 
                                  CustomPaint(
                                    painter: QuadrilateralPainter(
                                      tl: _tl, tr: _tr, bl: _bl, br: _br
                                    ),
                                  ),

                                // 3. Handles (Puntos de Arrastre) (visible solo si el layout está listo y no estamos muestreando)
                                if (_isLayoutCalculated && !_isSamplingMode) ...[
                                  // Handle Top-Left
                                  DraggableHandle(
                                    position: _tl,
                                    onDrag: (newPos) => _updatePoint('tl', newPos),
                                  ),
                                  // Handle Top-Right
                                  DraggableHandle(
                                    position: _tr,
                                    onDrag: (newPos) => _updatePoint('tr', newPos),
                                  ),
                                  // Handle Bottom-Left
                                  DraggableHandle(
                                    position: _bl,
                                    onDrag: (newPos) => _updatePoint('bl', newPos),
                                  ),
                                  // Handle Bottom-Right
                                  DraggableHandle(
                                    position: _br,
                                    onDrag: (newPos) => _updatePoint('br', newPos),
                                  ),
                                ],
                                
                                // 4. Overlay de Confirmación (Solo en modo muestreo y con color capturado)
                                if (_isSamplingMode && _sampledColor != null)
                                  _buildColorConfirmationOverlay(),
                              ],
                            ),
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
                  // Deshabilitar si el layout aún no está calculado o estamos muestreando
                  onPressed: _isLayoutCalculated && !_isLoading && !_isSamplingMode ? _performCrop : null,
                  icon: const Icon(Icons.check, size: 24),
                  label: const Text('Confirmar Recorte y Guardar Temporal', style: TextStyle(fontSize: 18)),
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
          // Indicador de carga superpuesto
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          // Indicador de layout (anteriormente en el Stack)
          if (!_isLayoutCalculated && !_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
        ],
      ),
    );
  }
}