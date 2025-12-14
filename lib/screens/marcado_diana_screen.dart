import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 

// 🚨 IMPORTACIÓN NECESARIA para que no haya errores
import '../services/target_analyzer_service.dart';

// ----------------------------------------------------------------------
// 1. MODELO PARA COORDENADAS NORMALIZADAS
// ----------------------------------------------------------------------

class CornerPoint {
  Offset position; 
  CornerPoint(this.position);
}

// ----------------------------------------------------------------------
// 2. CUSTOM PAINTER PARA DIBUJAR LAS CRUCES Y EL RECUADRO
// ----------------------------------------------------------------------

class CornerPainter extends CustomPainter {
  final List<CornerPoint> corners;
  final double width;
  final double height;
  final double crossSize = 15.0; 

  CornerPainter(this.corners, this.width, this.height);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final points = corners.map((p) => Offset(p.position.dx * width, p.position.dy * height)).toList();

    if (points.length == 4) {
      path.moveTo(points[0].dx, points[0].dy);
      path.lineTo(points[1].dx, points[1].dy);
      path.lineTo(points[2].dx, points[2].dy);
      path.lineTo(points[3].dx, points[3].dy);
      path.close();
      canvas.drawPath(path, linePaint);
    }
    
    final crossPaint = Paint()
      ..color = Colors.red 
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
      
    for (final point in points) {
      canvas.drawLine(
        Offset(point.dx - crossSize, point.dy),
        Offset(point.dx + crossSize, point.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(point.dx, point.dy - crossSize),
        Offset(point.dx, point.dy + crossSize),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; 
  }
}

// ----------------------------------------------------------------------
// 3. WIDGET PRINCIPAL DE LA PANTALLA
// ----------------------------------------------------------------------

class MarcadoDianaScreen extends StatefulWidget {
  const MarcadoDianaScreen({super.key});

  @override
  State<MarcadoDianaScreen> createState() => _MarcadoDianaScreenState();
}

class _MarcadoDianaScreenState extends State<MarcadoDianaScreen> {
  // 🚨 INICIALIZACIÓN DEL SERVICIO
  final TargetAnalyzerService _analyzerService = TargetAnalyzerService();
  
  File? _imageFile; 
  final ImagePicker _picker = ImagePicker();
  
  bool _needsManualSelection = false;
  bool _showResults = false;
  
  File? _rectifiedImageFile; 
  List<CornerPoint>? _detectedCorners;

  List<CornerPoint> _corners = [
    CornerPoint(const Offset(0.1, 0.1)),
    CornerPoint(const Offset(0.9, 0.1)),
    CornerPoint(const Offset(0.9, 0.9)),
    CornerPoint(const Offset(0.1, 0.9)),
  ];

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 90); 

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _needsManualSelection = false;
        _showResults = false;
        _rectifiedImageFile = null;
        _detectedCorners = null;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se seleccionó ninguna imagen.')),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Tomar Foto'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Seleccionar de Galería'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _startAnalysis(bool manualMode) {
    if (_imageFile == null) return;

    if (manualMode) {
      setState(() {
        _needsManualSelection = true;
        _showResults = false;
      });
    } else {
      // --- Lógica de Detección Automática (Simulación por ahora) ---
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detectando diana y corrigiendo perspectiva...'), duration: Duration(seconds: 2)),
      );
      
      // Aquí iría la llamada al servicio: _analyzerService.detectCornersAutomatically(...)
      
      // Simulación de la respuesta exitosa:
      setState(() {
        _rectifiedImageFile = _imageFile; 
        _detectedCorners = [
          CornerPoint(const Offset(0.05, 0.05)), 
          CornerPoint(const Offset(0.95, 0.05)), 
          CornerPoint(const Offset(0.95, 0.95)), 
          CornerPoint(const Offset(0.05, 0.95)), 
        ];
        
        _showResults = true;
        _needsManualSelection = false;
      });
    }
  }

  void _sendManualCornersForRectification() async {
    if (_imageFile == null) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Procesando corrección de perspectiva...'), duration: Duration(minutes: 1)),
    );

    // 1. Recoger las coordenadas normalizadas
    final List<Offset> normalizedPoints = _corners.map((p) => p.position).toList();
    
    // 2. Llamar al servicio de análisis REAL
    final File? rectifiedFile = await _analyzerService.rectifyImage(
      originalFile: _imageFile!,
      normalizedPoints: normalizedPoints,
      dianaSizeMm: 170.0, // Tamaño de la diana ISSF 10m Aire
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (rectifiedFile != null) {
      setState(() {
        _rectifiedImageFile = rectifiedFile;
        _detectedCorners = _corners; // Usamos los puntos manuales como los "detectados"
        _needsManualSelection = false;
        _showResults = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Imagen Rectificada con Éxito!'), duration: Duration(seconds: 2)),
      );
    } else {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al procesar la imagen con OpenCV.'), duration: Duration(seconds: 5)),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_needsManualSelection ? 'Selección Manual de Esquinas' : 'Marcado de Diana (Pruebas)'),
        backgroundColor: Colors.deepOrange,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // --- 1. Botón de Selección de Imagen ---
            ElevatedButton.icon(
              icon: const Icon(Icons.add_a_photo),
              label: Text(_imageFile == null ? 'SELECCIONAR DIANA' : 'CAMBIAR DIANA'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(15),
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _showImageSourceDialog,
            ),
            
            const SizedBox(height: 20),

            // --- Área Central de Interacción (depende del estado) ---
            if (_imageFile == null) 
              _buildPlaceholder(),
            
            if (_imageFile != null && !_needsManualSelection && !_showResults) 
              _buildAnalysisOptions(),

            if (_imageFile != null && _needsManualSelection)
              _buildCornerSelector(), 
            
            if (_showResults) 
              _buildRectifiedView(),

            const SizedBox(height: 30),
            
            // --- Área de Resultados Numéricos ---
            const Text(
              'Resultados del Análisis:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
            const Divider(),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10.0),
              child: Text('Puntuación: N/A\nImpactos Detectados: N/A'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border.all(color: Colors.grey, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt_outlined, size: 60, color: Colors.deepOrange,),
          const SizedBox(height: 10),
          Text('Selecciona una foto de la diana', style: TextStyle(color: Colors.grey[600]),),
        ],
      ),
    );
  }

  Widget _buildAnalysisOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(_imageFile!, fit: BoxFit.contain, height: 300),
        ),
        const SizedBox(height: 20),

        const Text('Modo de Análisis:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        ElevatedButton.icon(
          icon: const Icon(Icons.flash_on),
          label: const Text('2. Análisis Automático (Detección de Diana)'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(15),
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _startAnalysis(false),
        ),

        const SizedBox(height: 10),

        ElevatedButton.icon(
          icon: const Icon(Icons.touch_app),
          label: const Text('3. Seleccionar Esquinas Manualmente (Si falla el automático)'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(15),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _startAnalysis(true),
        ),
      ],
    );
  }

  Widget _buildCornerSelector() {
    const double dragHandleSize = 60; 

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('Arrastra las cruces a las 4 esquinas de la diana para rectificar la imagen.', style: TextStyle(color: Colors.red)),
        ),
        
        AspectRatio(
          aspectRatio: 1, 
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxWidth = constraints.maxWidth;
              final double maxHeight = constraints.maxHeight;

              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(_imageFile!, fit: BoxFit.cover),
                  ),
                  
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CornerPainter(_corners, maxWidth, maxHeight),
                    ),
                  ),

                  ..._corners.asMap().entries.map((entry) {
                    final index = entry.key;
                    final point = entry.value;

                    final top = point.position.dy * maxHeight - dragHandleSize / 2;
                    final left = point.position.dx * maxWidth - dragHandleSize / 2;

                    return Positioned(
                      top: top,
                      left: left,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            double newDx = (point.position.dx * maxWidth + details.delta.dx) / maxWidth;
                            double newDy = (point.position.dy * maxHeight + details.delta.dy) / maxHeight;
                            
                            newDx = newDx.clamp(0.0, 1.0);
                            newDy = newDy.clamp(0.0, 1.0);

                            _corners[index].position = Offset(newDx, newDy);
                          });
                        },
                        child: const SizedBox(
                          width: dragHandleSize,
                          height: dragHandleSize,
                        ),
                      ),
                    );
                  }).toList(),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        ElevatedButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('ENVIAR COORDENADAS PARA CORRECCIÓN'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(15),
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
          ),
          onPressed: _sendManualCornersForRectification,
        ),
      ],
    );
  }
  
  Widget _buildRectifiedView() {
    if (_rectifiedImageFile == null || _detectedCorners == null) {
      return _buildAnalysisOptions(); 
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Resultado Rectificado. Cruces indican los puntos de la diana detectados.', 
            style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold)
          ),
        ),
        
        AspectRatio(
          aspectRatio: 1, 
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxWidth = constraints.maxWidth;
              final double maxHeight = constraints.maxHeight;

              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(_rectifiedImageFile!, fit: BoxFit.cover),
                  ),
                  
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CornerPainter(_detectedCorners!, maxWidth, maxHeight), 
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_forward),
          label: const Text('CONTINUAR A MARCADO DE DISPAROS'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(15),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pasando a la detección de impactos (Lógica de CV)...')),
            );
          },
        ),
      ],
    );
  }
}