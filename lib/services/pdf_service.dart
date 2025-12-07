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

// Clase auxiliar para el informe moderno
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
  // A) INFORME MODERNO (ESTADÍSTICAS) - Ya funciona bien
  // =======================================================================
  
  Future<void> generarInformeAnalisisCompleto({
    required PerfilUsuario? perfil,
    required String periodoTexto,
    required List<DatosInformeDiana> datosDianas,
    required List<Map<String, dynamic>> datosProgreso,
    String? observaciones,
  }) async {
    final doc = pw.Document();
    
    final fontRegular = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    final fontItalic = await PdfGoogleFonts.openSansItalic(); 
    final fontNativa = PdfFont.helvetica(doc.document);

    pw.ImageProvider? logoImage;
    try {
      logoImage = await imageFromAssetBundle('assets/logo.png');
    } catch (_) {}

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold, italic: fontItalic),
        build: (pw.Context context) {
          return [
            _buildCabeceraPrincipal(logoImage, "Informe de Análisis Técnico", perfil, periodoTexto),
            pw.SizedBox(height: 20),

            if (datosDianas.isEmpty)
              pw.Center(child: pw.Text("No hay datos de dianas.")),

            ...datosDianas.map((datos) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                   pw.Container(
                     padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                     color: colorMoradoApp,
                     width: double.infinity,
                     child: pw.Text("ANÁLISIS: ${datos.diana.nombre.toUpperCase()}", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                   ),
                   pw.SizedBox(height: 10),
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
                                 _dianaFinalV4(canvas, size, datos.diana, datos.analisis, font: fontNativa);
                               }
                             );
                           }),
                         ),
                       ),
                       pw.SizedBox(width: 15),
                       pw.Expanded(flex: 3, child: _buildPanelCorreccion(datos.analisis, datos.equipo)),
                     ]
                   ),
                   pw.SizedBox(height: 15),
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
            if (datosProgreso.isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10), color: colorMoradoApp, width: double.infinity, child: pw.Text("EVOLUCIÓN", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.SizedBox(height: 20),
                pw.Container(height: 150, width: double.infinity, child: _buildGraficaVectorial(datosProgreso)),
              ]
            ),
            pw.Spacer(),
            pw.Container(width: double.infinity, height: 100, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(border: pw.Border.all(color: colorGrisBorde)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text("Notas:", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: colorAzul)), pw.SizedBox(height: 5), pw.Text(observaciones ?? "", style: const pw.TextStyle(fontSize: 10))])),
          ];
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Analisis_Tecnico.pdf');
  }

  // =======================================================================
  // B) INFORME CLÁSICO (ACTA DE PUNTUACIÓN) - PARA EL BOTÓN RÁPIDO
  // =======================================================================
  // Este es el que debe sacar la tabla de puntos, totales y firmas.
  
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
      // 1. Agrupamos los disparos en un "Grupo" para que el informe clásico lo entienda
      // Esto simula que toda la sesión es una única fase de competición
      await generarInformeTorneoProfesional(
        nombreTorneo: plantilla.nombreDisciplina,
        fecha: sesion.fecha,
        grupos: [
          GrupoFaseInforme(
            titulo: "Serie Única / Entrenamiento", 
            disparos: disparos, 
            valorMinimo: valorMinimo, 
            anilloNegro: anilloNegro, 
            esFondoNegro: esFondoNegro, 
            tieneMosca: tieneMosca, 
            tieneGuias: tieneGuias, 
            esEstiloDuelo: esEstiloDuelo, 
            esEnsayo: false
          )
        ],
        equipo: equipo,
        municion: municion,
        perfil: perfil,
        lugar: lugar,
        observaciones: observaciones,
      );
  }

  // Lógica del Acta de Puntuación (Restaurada)
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
    String fechaStr = "${fecha.day}/${fecha.month}/${fecha.year}";
    
    final fontRegular = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    pw.ImageProvider? logoImage;
    try { logoImage = await imageFromAssetBundle('assets/logo.png'); } catch (_) {}

    // Calcular totales
    List<Disparo> disparosPuntuables = [];
    for(var g in grupos) if (!g.esEnsayo) disparosPuntuables.addAll(g.disparos);
    int totalPuntos = disparosPuntuables.fold(0, (sum, item) => sum + item.puntuacion.floor());
    int totalMoscas = disparosPuntuables.where((d) => d.esMosca).length;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (pw.Context context) {
          return [
            // 1. Cabecera Acta
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null) pw.Container(width: 60, height: 60, child: pw.Image(logoImage)),
                pw.SizedBox(width: 20),
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text("ACTA DE PUNTUACIÓN", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: colorAzul)),
                      pw.Text(nombreTorneo, style: const pw.TextStyle(fontSize: 14)),
                ])),
              ]
            ),
            pw.SizedBox(height: 15),

            // 2. Datos Tirador
            pw.Table(border: pw.TableBorder.all(color: colorGrisBorde, width: 0.5), children: [
                pw.TableRow(decoration: const pw.BoxDecoration(color: colorGrisClaro), children: [
                    _celdaFicha("TIRADOR", perfil?.nombre ?? ""),
                    _celdaFicha("LICENCIA", perfil?.licencia ?? ""),
                    _celdaFicha("CLUB", perfil?.club ?? ""),
                ]),
                pw.TableRow(children: [
                    _celdaFicha("ARMA", equipo?.nombre ?? ""),
                    _celdaFicha("MUNICIÓN", municion?.marca ?? ""),
                    _celdaFicha("FECHA", "$fechaStr - ${lugar ?? ''}"),
                ]),
            ]),
            pw.SizedBox(height: 20),

            // 3. Totales (Cuadro Grande)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: const pw.BoxDecoration(color: colorAzul),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                   pw.Text(" PUNTUACIÓN TOTAL", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 16)),
                   pw.Text("$totalPuntos ($totalMoscas x)  ", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 18)),
              ])
            ),
            
            // 4. Tabla de conteo (Cuántos 10, cuántos 9...)
            _construirTablaFrecuencias(disparosPuntuables, mostrarCabecera: true),
            pw.SizedBox(height: 20),
            
            // 5. Desglose por Series (Tablas detalladas)
            ..._generarBloquesDetallados(grupos),

            // 6. Firmas
            pw.Spacer(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
                pw.Column(children: [pw.Container(width: 120, height: 1, color: PdfColors.black), pw.SizedBox(height: 5), pw.Text("Firma del Tirador", style: const pw.TextStyle(fontSize: 8))]),
                pw.Column(children: [pw.Container(width: 120, height: 1, color: PdfColors.black), pw.SizedBox(height: 5), pw.Text("Firma Árbitro", style: const pw.TextStyle(fontSize: 8))])
            ])
          ];
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Acta_Puntuacion.pdf');
  }

  // --- HELPERS COMUNES ---
  pw.Widget _celdaFicha(String titulo, String valor) {
    return pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(titulo, style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
          pw.Text(valor.isEmpty ? "-" : valor, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    ]));
  }

  // Generador de tablas de series (1, 2, 3, 4, 5... Total)
  List<pw.Widget> _generarBloquesDetallados(List<GrupoFaseInforme> grupos) {
      List<pw.Widget> widgets = [];
      for (var grupo in grupos) {
          widgets.add(pw.Padding(padding: const pw.EdgeInsets.only(top: 10, bottom: 5), child: pw.Text(grupo.titulo, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: colorAzul))));

          int blockSize = 5; // Filas de 5 tiros por defecto
          // Si son muchos tiros (ej: 60), agrupamos de 10 en 10
          if (grupo.disparos.length > 20) blockSize = 10;
          
          int numSeries = (grupo.disparos.length / blockSize).ceil();
          
          // Anchos de columna dinámicos
          Map<int, pw.TableColumnWidth> colWidths = { 0: const pw.FixedColumnWidth(35), blockSize+1: const pw.FixedColumnWidth(40) };
          for(int k=1; k<=blockSize; k++) colWidths[k] = const pw.FlexColumnWidth();

          for (int i = 0; i < numSeries; i++) {
            int start = i * blockSize;
            int end = min(start + blockSize, grupo.disparos.length);
            var serie = grupo.disparos.sublist(start, end);
            int ptsSerie = serie.fold(0, (s, t) => s + t.puntuacion.floor());
            
            List<String> fila = ["Serie ${i + 1}"];
            for(var t in serie) fila.add(t.puntuacion >= 10 ? (t.esMosca ? "X" : "10") : t.puntuacion.floor().toString());
            // Rellenar huecos vacíos si la última serie es corta
            while(fila.length <= blockSize) fila.add("-");
            fila.add("$ptsSerie"); // Total

            List<String> headers = ['S'];
            for(int k=1; k<=blockSize; k++) headers.add('$k');
            headers.add('TOT');

            widgets.add(pw.Table.fromTextArray(
              headers: i == 0 ? headers : [], 
              data: [fila], 
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5), 
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), 
              cellStyle: const pw.TextStyle(fontSize: 9), 
              cellAlignment: pw.Alignment.center, 
              headerDecoration: i==0 ? const pw.BoxDecoration(color: colorGrisClaro) : null, 
              columnWidths: colWidths
            ));
          }
      }
      return widgets;
  }

  pw.Widget _construirTablaFrecuencias(List<Disparo> disparos, {bool mostrarCabecera = true}) {
    Map<String, int> conteo = {"X": 0, "10": 0, "9": 0, "8": 0, "7": 0, "6": 0, "5": 0, "4": 0, "3": 0, "2": 0, "1": 0, "M": 0};
    for (var d in disparos) {
        if (d.esMosca) conteo["X"] = conteo["X"]! + 1;
        else if (d.puntuacion < 1) conteo["M"] = conteo["M"]! + 1;
        else { int val = d.puntuacion.floor(); if(val>=1 && val<=10) conteo["$val"] = conteo["$val"]! + 1; }
    }
    final headers = ['Valor', 'Cantidad', 'Subtotal'];
    final data = <List<String>>[];
    const orden = ["X", "10", "9", "8", "7", "6", "5", "4", "3", "2", "1", "M"];
    for(var k in orden) {
        int count = conteo[k] ?? 0;
        if (count > 0) { // Solo mostrar filas con valores
           String subtotalStr = k == "M" ? "0" : "${(k=="X"?10:int.parse(k)) * count}";
           data.add([k, "$count", subtotalStr]);
        }
    }
    return pw.Table.fromTextArray(headers: mostrarCabecera ? headers : [], data: data, border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), headerDecoration: const pw.BoxDecoration(color: colorGrisClaro), cellStyle: const pw.TextStyle(fontSize: 9), cellAlignment: pw.Alignment.center, cellAlignments: {0: pw.Alignment.centerLeft}, columnWidths: {0: const pw.FixedColumnWidth(40), 1: const pw.FixedColumnWidth(40), 2: const pw.FixedColumnWidth(40)});
  }

  // --- HELPERS PINTADO MODERNO ---
  pw.Widget _buildCabeceraPrincipal(pw.ImageProvider? logo, String titulo, PerfilUsuario? perfil, String infoExtra) {
    return pw.Row(children: [
        if (logo != null) pw.Container(width: 50, height: 50, child: pw.Image(logo)),
        pw.SizedBox(width: 15),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(titulo, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: colorAzul)),
              pw.Text("Tirador: ${perfil?.nombre ?? 'Usuario'} (Lic: ${perfil?.licencia ?? '-'})", style: const pw.TextStyle(fontSize: 10)),
              pw.Text(infoExtra, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ]))
    ]);
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

  void _dianaFinalV4(PdfGraphics canvas, PdfPoint size, TipoDiana diana, AnalisisAgrupacion analisis, {required PdfFont font}) {
      double cx = size.x / 2; double cy = size.y / 2; double radius = size.x / 2;
      canvas.setColor(diana.esFondoNegro ? PdfColors.black : colorCrema); canvas.drawEllipse(cx, cy, radius, radius); canvas.fillPath();
      
      int totalZonas = 11 - diana.valorMinimo; if (diana.nombre.toLowerCase().contains("duelo")) totalZonas = 6; double anchoZona = radius / totalZonas;
      
      for(int i=0; i<totalZonas; i++) {
         double r = radius - (i * anchoZona);
         int numAnillo = diana.valorMinimo + i;
         bool esNegro = numAnillo >= diana.anilloNegroInicio;
         if (diana.esFondoNegro) { canvas.setColor(PdfColors.white); canvas.setLineWidth(0.5); canvas.drawEllipse(cx, cy, r, r); canvas.strokePath(); } else { if (esNegro) { canvas.setColor(PdfColors.black); canvas.drawEllipse(cx, cy, r, r); canvas.fillPath(); canvas.setColor(PdfColors.white); } else { canvas.setColor(PdfColors.grey); } canvas.setLineWidth(0.5); canvas.drawEllipse(cx, cy, r, r); canvas.strokePath(); }
         if (numAnillo < 10 && r > 10) { PdfColor colorNum = (esNegro || diana.esFondoNegro) ? PdfColors.white : PdfColors.black; canvas.setColor(colorNum); String txt = numAnillo.toString(); double fontSize = 8.0; double offText = 3; canvas.drawString(font, fontSize, txt, cx - offText, cy - r + (anchoZona/2) - offText); canvas.drawString(font, fontSize, txt, cx - offText, cy + r - (anchoZona/2) - offText); canvas.drawString(font, fontSize, txt, cx - r + (anchoZona/2) - offText, cy - offText); canvas.drawString(font, fontSize, txt, cx + r - (anchoZona/2) - offText, cy - offText); }
      }
      canvas.setColor(colorVerdeImpacto); double tamanoPunto = radius * 0.035;
      for (var d in analisis.disparosValidos) { double x = (d.x * radius) + cx; double y = (d.y * radius) + cy; canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto); canvas.fillPath(); canvas.setColor(diana.esFondoNegro ? PdfColors.white : PdfColors.black); canvas.setLineWidth(0.2); canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto); canvas.strokePath(); canvas.setColor(colorVerdeImpacto); }
      canvas.setColor(PdfColors.grey);
      for (var d in analisis.disparosDescartados) { double x = (d.x * radius) + cx; double y = (d.y * radius) + cy; canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto); canvas.fillPath(); }
      if (analisis.disparosValidos.isNotEmpty) { double mpiX = (analisis.mpi.x * radius) + cx; double mpiY = (analisis.mpi.y * radius) + cy; canvas.setColor(colorRojoMPI); canvas.setLineWidth(2); double l = 10; canvas.drawLine(mpiX - l, mpiY, mpiX + l, mpiY); canvas.drawLine(mpiX, mpiY - l, mpiX, mpiY + l); canvas.strokePath(); canvas.setLineWidth(1); canvas.drawEllipse(mpiX, mpiY, 4, 4); canvas.strokePath(); }
  }
}