import 'dart:math';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/sesion_model.dart';
import '../models/disparo_model.dart';
import '../models/plantilla_tiempos_model.dart';
import '../models/equipo_model.dart';
import '../models/municion_model.dart';
import '../models/informe_model.dart';
import '../services/perfil_service.dart';
import '../models/tipo_diana_model.dart';
import 'estadisticas_service.dart'; 

// Clase auxiliar
class DatosInformeDiana {
  final TipoDiana diana;
  final AnalisisAgrupacion analisis;
  final List<DiagnosticoTecnico> diagnostico;
  final EquipoDetalle? equipo;

  DatosInformeDiana({
    required this.diana,
    required this.analisis,
    required this.diagnostico,
    this.equipo,
  });
}

class PdfService {
  
  // --- COLORES ---
  static const PdfColor colorCrema = PdfColor.fromInt(0xFFF5F3E0);
  static const PdfColor colorNegro = PdfColor.fromInt(0xFF000000);
  static const PdfColor colorBlanco = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor colorGris = PdfColor.fromInt(0xFF9E9E9E);
  static const PdfColor colorGrisClaro = PdfColor.fromInt(0xFFEEEEEE);
  static const PdfColor colorGrisBorde = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor colorVerdeImpacto = PdfColor.fromInt(0xFF00C853);
  static const PdfColor colorAzul = PdfColor.fromInt(0xFF1A237E);
  static const PdfColor colorRojoMPI = PdfColor.fromInt(0xFFD50000);
  static const PdfColor colorMoradoApp = PdfColor.fromInt(0xFF9C27B0);
  static const PdfColor colorNegroSuave = PdfColor.fromInt(0xFF1A1A1A);

  // =======================================================================
  // 1. INFORME NUEVO
  // =======================================================================
  
  Future<void> generarInformeAnalisisCompleto({
    required PerfilUsuario? perfil,
    required String periodoTexto,
    required List<DatosInformeDiana> datosDianas,
    required List<Map<String, dynamic>> datosProgreso,
    String? observaciones,
  }) async {
    final doc = pw.Document();
    
    // Fuentes para los Widgets (Texto normal)
    final fontRegular = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    final fontItalic = await PdfGoogleFonts.openSansItalic(); 

    // Fuente NATIVA para el Canvas (Esta es la que soluciona el error)
    // Usamos Helvetica estándar que no requiere carga asíncrona ni conversiones raras
    final fontNumeros = PdfFont.helvetica(doc.document);

    pw.ImageProvider? logoImage;
    try {
      logoImage = await imageFromAssetBundle('assets/logo.png');
    } catch (_) {}

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(
          base: fontRegular, 
          bold: fontBold, 
          italic: fontItalic 
        ),
        build: (pw.Context context) {
          return [
            // CABECERA
            _buildCabeceraPrincipal(logoImage, "Informe de Análisis y Progreso", perfil, periodoTexto),
            pw.SizedBox(height: 20),

            // BUCLE DIANAS
            ...datosDianas.map((datos) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                   pw.Container(
                     padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                     color: colorMoradoApp,
                     width: double.infinity,
                     child: pw.Text(
                       "ANÁLISIS TÉCNICO: ${datos.diana.nombre.toUpperCase()}",
                       style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
                     ),
                   ),
                   pw.SizedBox(height: 10),

                   // BLOQUE A: DIANA
                   pw.Row(
                     crossAxisAlignment: pw.CrossAxisAlignment.start,
                     children: [
                       pw.Expanded(
                         flex: 4,
                         child: pw.AspectRatio(
                           aspectRatio: 1,
                           child: pw.LayoutBuilder(builder: (ctx, constraints) {
                             return pw.CustomPaint(
                               size: PdfPoint(constraints!.maxWidth, constraints.maxWidth),
                               painter: (PdfGraphics canvas, PdfPoint size) {
                                 // PASAMOS LA FUENTE NATIVA HELVETICA
                                 _dianaFinalV3(
                                    canvas, 
                                    size, 
                                    datos.diana, 
                                    datos.analisis, 
                                    font: fontNumeros // <--- CAMBIO CORRECTO
                                 );
                               }
                             );
                           }),
                         ),
                       ),
                       pw.SizedBox(width: 15),
                       pw.Expanded(
                         flex: 3,
                         child: _buildPanelCorreccion(datos.analisis, datos.equipo)
                       ),
                     ]
                   ),

                   pw.SizedBox(height: 15),

                   // BLOQUE B: ERRORES
                   pw.Text("Diagnóstico de Errores", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: colorAzul)),
                   pw.Divider(color: colorGrisBorde),
                   if (datos.diagnostico.isEmpty)
                      pw.Text("Sin datos suficientes.", style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10))
                   else
                      ...datos.diagnostico.take(5).map((d) => _buildBarraError(d)),

                   pw.SizedBox(height: 30),
                ]
              );
            }).toList(),

            pw.SizedBox(height: 10),

            // GRAFICA
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                     padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                     color: colorMoradoApp,
                     width: double.infinity,
                     child: pw.Text("EVOLUCIÓN", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ),
                pw.SizedBox(height: 20),
                pw.Container(
                  height: 150,
                  width: double.infinity,
                  child: _buildGraficaVectorial(datosProgreso),
                ),
              ]
            ),

            // PIE
            pw.Spacer(),
            pw.Container(
              width: double.infinity,
              height: 100,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: colorGrisBorde)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text("Notas del Entrenador:", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: colorAzul)),
              ])
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Analisis.pdf');
  }

  // =======================================================================
  // 2. LA FUNCIÓN DE PINTADO (CORRECTA)
  // =======================================================================
  
  void _dianaFinalV3(PdfGraphics canvas, PdfPoint size, TipoDiana diana, AnalisisAgrupacion analisis, {required PdfFont font}) {
      double cx = size.x / 2;
      double cy = size.y / 2;
      double radius = size.x / 2;

      // FONDO
      canvas.setColor(diana.esFondoNegro ? PdfColors.black : colorCrema);
      canvas.drawEllipse(cx, cy, radius, radius);
      canvas.fillPath();
      
      int totalZonas = 11 - diana.valorMinimo; 
      if (diana.nombre.toLowerCase().contains("duelo")) totalZonas = 6;
      double anchoZona = radius / totalZonas;
      
      // ANILLOS
      for(int i=0; i<totalZonas; i++) {
         double r = radius - (i * anchoZona);
         int numAnillo = diana.valorMinimo + i;
         bool esNegro = numAnillo >= diana.anilloNegroInicio;
         
         if (diana.esFondoNegro) {
            canvas.setColor(PdfColors.white); 
            canvas.setLineWidth(0.5);
            canvas.drawEllipse(cx, cy, r, r);
            canvas.strokePath();
         } else {
            if (esNegro) {
              canvas.setColor(PdfColors.black);
              canvas.drawEllipse(cx, cy, r, r);
              canvas.fillPath();
              canvas.setColor(PdfColors.white);
            } else {
              canvas.setColor(PdfColors.grey);
            }
            canvas.setLineWidth(0.5);
            canvas.drawEllipse(cx, cy, r, r);
            canvas.strokePath();
         }

         // NÚMEROS
         if (numAnillo < 10 && r > 10) {
             PdfColor colorNum = (esNegro || diana.esFondoNegro) ? PdfColors.white : PdfColors.black;
             canvas.setColor(colorNum);
             String txt = numAnillo.toString();
             double fontSize = 8.0; 
             double offText = 3; 
             
             canvas.drawString(font, fontSize, txt, cx - offText, cy - r + (anchoZona/2) - offText);
             canvas.drawString(font, fontSize, txt, cx - offText, cy + r - (anchoZona/2) - offText);
             canvas.drawString(font, fontSize, txt, cx - r + (anchoZona/2) - offText, cy - offText);
             canvas.drawString(font, fontSize, txt, cx + r - (anchoZona/2) - offText, cy - offText);
         }
      }

      // IMPACTOS
      canvas.setColor(colorVerdeImpacto);
      double tamanoPunto = radius * 0.035;
      
      for (var d in analisis.disparosValidos) {
         double x = (d.x * radius) + cx;
         double y = (d.y * radius) + cy;
         canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto);
         canvas.fillPath();
         canvas.setColor(diana.esFondoNegro ? PdfColors.white : PdfColors.black);
         canvas.setLineWidth(0.2);
         canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto);
         canvas.strokePath();
         canvas.setColor(colorVerdeImpacto);
      }

      canvas.setColor(PdfColors.grey);
      for (var d in analisis.disparosDescartados) {
         double x = (d.x * radius) + cx;
         double y = (d.y * radius) + cy;
         canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto);
         canvas.fillPath();
      }

      // MPI
      if (analisis.disparosValidos.isNotEmpty) {
        double mpiX = (analisis.mpi.x * radius) + cx;
        double mpiY = (analisis.mpi.y * radius) + cy;
        
        canvas.setColor(colorRojoMPI);
        canvas.setLineWidth(2);
        double l = 10;
        canvas.drawLine(mpiX - l, mpiY, mpiX + l, mpiY);
        canvas.drawLine(mpiX, mpiY - l, mpiX, mpiY + l);
        canvas.strokePath();
        
        canvas.setLineWidth(1);
        canvas.drawEllipse(mpiX, mpiY, 4, 4);
        canvas.strokePath();
      }
  }

  // =======================================================================
  // 3. WIDGETS AUXILIARES
  // =======================================================================

  pw.Widget _buildCabeceraPrincipal(pw.ImageProvider? logo, String titulo, PerfilUsuario? perfil, String infoExtra) {
    return pw.Row(
      children: [
        if (logo != null) pw.Container(width: 50, height: 50, child: pw.Image(logo)),
        pw.SizedBox(width: 15),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(titulo, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: colorAzul)),
              pw.Text("Tirador: ${perfil?.nombre ?? 'Anónimo'}", style: const pw.TextStyle(fontSize: 10)),
              pw.Text(infoExtra, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ]))
      ]
    );
  }

  pw.Widget _buildPanelCorreccion(AnalisisAgrupacion analisis, EquipoDetalle? equipo) {
    String consejo = "Miras Correctas";
    if ((equipo?.correccionClick ?? 0) > 0 && (analisis.mpi.x.abs() > 0.05 || analisis.mpi.y.abs() > 0.05)) {
        consejo = "CORREGIR MIRAS";
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text("CORRECCIÓN", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey)),
        pw.Text(consejo, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
    ]);
  }

  pw.Widget _buildBarraError(DiagnosticoTecnico error) {
    return pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Row(children: [
          pw.Container(width: 100, child: pw.Text("[!] ${error.nombreError}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
          pw.Expanded(child: pw.Row(children: [
                if (error.porcentaje > 0) pw.Expanded(flex: error.porcentaje.round(), child: pw.Container(height: 12, decoration: pw.BoxDecoration(color: colorMoradoApp, borderRadius: pw.BorderRadius.circular(2)))),
                if (error.porcentaje < 100) pw.Spacer(flex: 100 - error.porcentaje.round()),
          ])),
          pw.Text("${error.porcentaje.round()}%", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    ]));
  }
  
  pw.Widget _buildGraficaVectorial(List<Map<String, dynamic>> puntos) {
    if (puntos.isEmpty) return pw.Center(child: pw.Text("Sin datos"));
    List<double> valores = puntos.map((p) => (p['total'] as num).toDouble()).toList();
    double minVal = valores.reduce(min); double maxVal = valores.reduce(max);
    if (minVal == maxVal) { minVal -= 5; maxVal += 5; }
    return pw.LayoutBuilder(builder: (ctx, constraints) {
      double w = constraints!.maxWidth; double h = constraints.maxHeight;
      return pw.CustomPaint(size: PdfPoint(w, h), painter: (canvas, size) {
           canvas.setColor(PdfColors.grey); canvas.setLineWidth(1); canvas.drawLine(0, 0, 0, h); canvas.drawLine(0, 0, w, 0);
           canvas.setColor(colorMoradoApp); canvas.setLineWidth(2);
           double pasoX = w / (valores.length - 1); if (valores.length == 1) pasoX = w;
           for (int i = 0; i < valores.length - 1; i++) {
              double y1 = ((valores[i] - minVal) / (maxVal - minVal)) * h;
              double y2 = ((valores[i+1] - minVal) / (maxVal - minVal)) * h;
              canvas.drawLine(i * pasoX, y1, (i+1) * pasoX, y2);
           }
           canvas.strokePath();
        }
      );
    });
  }

  // =======================================================================
  // 4. FUNCIONES LEGACY (TORNEO)
  // =======================================================================
  
  Future<void> generarYMostrarPdf({
    required Sesion sesion, 
    required List<Disparo> disparos, 
    required PlantillaTiempos plantilla, 
    required EquipoDetalle? equipo, 
    required MunicionDetalle? municion, 
    required int valorMinimo, 
    required int anilloNegro, 
    required bool esFondoNegro, 
    required bool tieneMosca, 
    required bool tieneGuias, 
    required bool esEstiloDuelo,
    PerfilUsuario? perfil,
    String? lugar,
    String? observaciones,
  }) async {
      await generarInformeTorneoProfesional(
        nombreTorneo: "Entrenamiento: ${plantilla.nombreDisciplina}",
        fecha: sesion.fecha,
        grupos: [GrupoFaseInforme(titulo: plantilla.nombreDisciplina, disparos: disparos, valorMinimo: valorMinimo, anilloNegro: anilloNegro, esFondoNegro: esFondoNegro, tieneMosca: tieneMosca, tieneGuias: tieneGuias, esEstiloDuelo: esEstiloDuelo, esEnsayo: false)],
        equipo: equipo, municion: municion, perfil: perfil, lugar: lugar, observaciones: observaciones,
      );
  }

  Future<void> generarInformeTorneoProfesional({
    required String nombreTorneo,
    required DateTime fecha,
    required List<GrupoFaseInforme> grupos,
    EquipoDetalle? equipo,
    MunicionDetalle? municion,
    PerfilUsuario? perfil,
    String? lugar,
    String? observaciones,
  }) async {
    final doc = pw.Document();
    final fontRegular = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (pw.Context context) {
          return [pw.Text(nombreTorneo, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))];
        },
    ));
    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Acta.pdf');
  }
}

class _PdfDianaPainter {
   final List<Disparo> disparos; final int valorMinimo; int anilloNegro; bool esFondoNegro; bool tieneMosca; bool tieneGuias; bool esEstiloDuelo;
  final PdfPoint? mpi; final PdfColor colorCrema; final PdfColor colorNegroSuave;
  _PdfDianaPainter({required this.disparos, required this.valorMinimo, required this.anilloNegro, required this.esFondoNegro, required this.tieneMosca, required this.tieneGuias, required this.esEstiloDuelo, this.mpi, required this.colorCrema, required this.colorNegroSuave});
  void paint(PdfGraphics canvas, PdfPoint size) {}
}