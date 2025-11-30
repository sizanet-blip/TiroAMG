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
import 'perfil_service.dart';

class PdfService {
  
  // --- COLORES SEGUROS ---
  static const PdfColor colorCrema = PdfColor.fromInt(0xFFF5F3E0);
  static const PdfColor colorNegro = PdfColor.fromInt(0xFF000000);
  static const PdfColor colorBlanco = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor colorGris = PdfColor.fromInt(0xFF9E9E9E);
  static const PdfColor colorGrisClaro = PdfColor.fromInt(0xFFEEEEEE);
  static const PdfColor colorGrisBorde = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor colorVerdeImpacto = PdfColor.fromInt(0xFF00C853);
  static const PdfColor colorAzul = PdfColor.fromInt(0xFF1A237E);
  static const PdfColor colorAzulGris = PdfColor.fromInt(0xFF607D8B);
  static const PdfColor colorAmberSuave = PdfColor.fromInt(0xFFFFF8E1);
  static const PdfColor colorRojoMPI = PdfColor.fromInt(0xFFD50000);
  static const PdfColor colorNegroSuave = PdfColor.fromInt(0xFF1A1A1A);

  // Wrapper individual
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
        grupos: [
          GrupoFaseInforme(
            titulo: plantilla.nombreDisciplina, 
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

  // --- INFORME MAESTRO ---
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
    try {
      logoImage = await imageFromAssetBundle('assets/logo.png');
    } catch (_) {}

    List<Disparo> disparosPuntuables = [];
    List<GrupoFaseInforme> gruposCompeticion = [];
    List<GrupoFaseInforme> gruposEnsayo = [];

    for(var g in grupos) {
      if (g.esEnsayo) {
        gruposEnsayo.add(g);
      } else {
        gruposCompeticion.add(g);
        disparosPuntuables.addAll(g.disparos);
      }
    }

    int totalPuntos = disparosPuntuables.fold(0, (sum, item) => sum + item.puntuacion.floor());
    int totalMoscas = disparosPuntuables.where((d) => d.esMosca).length;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (pw.Context context) {
          return [
            // 1. CABECERA CON LOGO (LIMPIA)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Container(width: 60, height: 60, child: pw.Image(logoImage)),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(nombreTorneo, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: colorAzul)),
                      pw.Text("Acta de Puntuación Individual", style: const pw.TextStyle(fontSize: 12)),
                    ]
                  )
                ),
              ]
            ),
            
            pw.SizedBox(height: 15),

            // 2. FICHA TÉCNICA
            pw.Table(
              border: pw.TableBorder.all(color: colorGrisBorde, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: colorGrisClaro),
                  children: [
                    _celdaFicha("TIRADOR", perfil?.nombre ?? ""),
                    _celdaFicha("LICENCIA", perfil?.licencia ?? ""),
                    _celdaFicha("CLUB / FED.", perfil?.club ?? ""),
                  ]
                ),
                pw.TableRow(
                  children: [
                    _celdaFicha("ARMA", equipo?.nombre ?? ""),
                    _celdaFicha("CALIBRE/MUN.", "${equipo?.nombreCalibre ?? ''} ${municion?.marca ?? ''}"),
                    _celdaFicha("LUGAR / FECHA", "${lugar ?? ''} - $fechaStr"),
                  ]
                ),
              ]
            ),

            pw.SizedBox(height: 20),

            // 3. DIANAS
            if (gruposCompeticion.isNotEmpty)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: gruposCompeticion.map((grupo) {
                    PdfPoint? mpiLocal;
                    var validos = grupo.disparos.where((d) => d.x.isFinite && d.y.isFinite).toList();
                    if (validos.isNotEmpty) {
                        double sx=0, sy=0;
                        for(var d in validos) { sx+=d.x; sy+=d.y; }
                        mpiLocal = PdfPoint(sx/validos.length, sy/validos.length);
                    }
                    return pw.Column(
                        children: [
                            pw.Text(grupo.titulo, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                            pw.SizedBox(height: 5),
                            pw.Container(
                                width: 100, height: 100,
                                child: pw.CustomPaint(
                                    size: const PdfPoint(100, 100),
                                    painter: (PdfGraphics canvas, PdfPoint size) {
                                        _PdfDianaPainter(
                                            disparos: validos,
                                            valorMinimo: grupo.valorMinimo,
                                            anilloNegro: grupo.anilloNegro,
                                            esFondoNegro: grupo.esFondoNegro,
                                            tieneMosca: grupo.tieneMosca,
                                            tieneGuias: grupo.tieneGuias,
                                            esEstiloDuelo: grupo.esEstiloDuelo,
                                            mpi: mpiLocal,
                                            colorCrema: colorCrema,
                                            colorNegroSuave: PdfColors.black
                                        ).paint(canvas, size);
                                    }
                                )
                            ),
                            pw.Text("${validos.length} disp.", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey))
                        ]
                    );
                }).toList()
              ),

            pw.SizedBox(height: 20),

            // 4. CUADRO DE HONOR
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              decoration: const pw.BoxDecoration(color: colorAzul),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                   pw.Text(" PUNTUACIÓN TOTAL", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                   pw.Text("$totalPuntos ($totalMoscas x)  ", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                ]
              )
            ),
            _construirTablaFrecuencias(disparosPuntuables, mostrarCabecera: true),

            pw.SizedBox(height: 20),
            
            // 5. DESGLOSE
            pw.Text("Desglose por Series", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: colorAzul)),
            pw.Divider(color: colorAzul, thickness: 1),
            pw.SizedBox(height: 10),
            
            ..._generarBloquesDetallados(gruposCompeticion),

            if (gruposEnsayo.isNotEmpty) ...[
                pw.SizedBox(height: 15),
                pw.Text("Ensayos (No puntuable)", style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
                ..._generarBloquesDetallados(gruposEnsayo),
            ],

            // 6. PIE DE PÁGINA
            pw.Spacer(), // Empuja el contenido al final de la página si hay sitio
            pw.Container(
              width: double.infinity, // Ocupa todo el ancho disponible
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: colorGrisBorde),
                borderRadius: pw.BorderRadius.circular(5)
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Observaciones e Incidencias:", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(observaciones != null && observaciones.isNotEmpty ? observaciones : "Sin incidencias.", style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(height: 100), // Espacio vertical para notas a mano
                ]
              )
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(children: [
                   pw.Container(width: 120, height: 1, color: PdfColors.black),
                   pw.SizedBox(height: 5),
                   pw.Text("Firma del Tirador", style: const pw.TextStyle(fontSize: 8))
                ]),
                pw.Column(children: [
                   pw.Container(width: 120, height: 1, color: PdfColors.black),
                   pw.SizedBox(height: 5),
                   pw.Text("Firma Árbitro / Entrenador", style: const pw.TextStyle(fontSize: 8))
                ])
              ]
            )
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Acta_${nombreTorneo.replaceAll(" ", "_")}.pdf');
  }

  // --- HELPERS ---
  pw.Widget _celdaFicha(String titulo, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(titulo, style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
          pw.Text(valor.isEmpty ? "-" : valor, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]
      )
    );
  }

  List<pw.Widget> _generarBloquesDetallados(List<GrupoFaseInforme> grupos) {
      List<pw.Widget> widgets = [];
      for (var grupo in grupos) {
          PdfColor colorTitulo = grupo.esEnsayo ? PdfColors.grey700 : colorAzul;
          widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
              child: pw.Text(grupo.titulo, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: colorTitulo))
          ));

          int blockSize = 5;
          if (grupo.disparos.length % 10 == 0 && grupo.disparos.length > 20) blockSize = 10;
          int numSeries = (grupo.disparos.length / blockSize).ceil();

          Map<int, pw.TableColumnWidth> colWidths = { 0: const pw.FixedColumnWidth(35), 13: const pw.FixedColumnWidth(35) };
          for(int k=1; k<=12; k++) colWidths[k] = const pw.FixedColumnWidth(22);

          for (int i = 0; i < numSeries; i++) {
            int start = i * blockSize;
            int end = min(start + blockSize, grupo.disparos.length);
            var serie = grupo.disparos.sublist(start, end);
            int ptsSerie = serie.fold(0, (s, t) => s + t.puntuacion.floor());
            
            Map<String, int> c = {"X":0, "10":0, "9":0, "8":0, "7":0, "6":0, "5":0, "4":0, "3":0, "2":0, "1":0, "M":0};
            for(var t in serie) {
                if (t.esMosca) c["X"] = c["X"]! + 1;
                else if (t.puntuacion < 1) c["M"] = c["M"]! + 1;
                else { int v = t.puntuacion.floor(); if(v>=1 && v<=10) c["$v"] = c["$v"]! + 1; }
            }

            List<String> fila = [
              "${i + 1}",
              c["X"]==0?"": "${c["X"]}", c["10"]==0?"": "${c["10"]}", c["9"]==0?"": "${c["9"]}",
              c["8"]==0?"": "${c["8"]}", c["7"]==0?"": "${c["7"]}", c["6"]==0?"": "${c["6"]}",
              c["5"]==0?"": "${c["5"]}", c["4"]==0?"": "${c["4"]}", c["3"]==0?"": "${c["3"]}",
              c["2"]==0?"": "${c["2"]}", c["1"]==0?"": "${c["1"]}", c["M"]==0?"": "${c["M"]}",
              "$ptsSerie"
            ];
            List<String> headers = ['S', 'X', '10', '9', '8', '7', '6', '5', '4', '3', '2', '1', 'M', 'TOT'];
            widgets.add(pw.Table.fromTextArray(headers: i == 0 ? headers : [], data: [fila], border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), cellStyle: const pw.TextStyle(fontSize: 8), cellAlignment: pw.Alignment.center, headerDecoration: i==0 ? const pw.BoxDecoration(color: colorGrisClaro) : null, columnWidths: colWidths));
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
        String subtotalStr = k == "M" ? "" : "${(k=="X"?10:int.parse(k)) * count}";
        data.add([k, "$count", subtotalStr]);
    }
    return pw.Table.fromTextArray(headers: mostrarCabecera ? headers : [], data: data, border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), headerDecoration: const pw.BoxDecoration(color: colorGrisClaro), cellStyle: const pw.TextStyle(fontSize: 9), cellAlignment: pw.Alignment.center, cellAlignments: {0: pw.Alignment.centerLeft}, columnWidths: {0: const pw.FixedColumnWidth(40), 1: const pw.FixedColumnWidth(40), 2: const pw.FixedColumnWidth(40)});
  }
}

// --- PINTOR ---
class _PdfDianaPainter {
  final List<Disparo> disparos; final int valorMinimo; int anilloNegro; bool esFondoNegro; bool tieneMosca; bool tieneGuias; bool esEstiloDuelo;
  final PdfPoint? mpi; final PdfColor colorCrema; final PdfColor colorNegroSuave;
  _PdfDianaPainter({required this.disparos, required this.valorMinimo, required this.anilloNegro, required this.esFondoNegro, required this.tieneMosca, required this.tieneGuias, required this.esEstiloDuelo, this.mpi, required this.colorCrema, required this.colorNegroSuave});
  void paint(PdfGraphics canvas, PdfPoint size) {
    final center = PdfPoint(size.x / 2, size.y / 2); final radius = size.x / 2;
    if (radius <= 0) return;
    if (esEstiloDuelo) _pintarDuelo(canvas, center, radius); else _pintarPrecision(canvas, center, radius);
    _pintarImpactos(canvas, center, radius);
    if (mpi != null && mpi!.x.isFinite && mpi!.y.isFinite) { double mx = (mpi!.x * radius) + center.x; double my = (mpi!.y * radius) + center.y; if (mx.isFinite && my.isFinite) { canvas.setColor(PdfService.colorRojoMPI); canvas.setLineWidth(1.5); canvas.drawLine(mx - 5, my, mx + 5, my); canvas.drawLine(mx, my - 5, mx, my + 5); canvas.strokePath(); } }
  }
  void _pintarPrecision(PdfGraphics canvas, PdfPoint center, double radius) {
      canvas.setColor(colorCrema); canvas.drawEllipse(center.x, center.y, radius, radius); canvas.fillPath();
      int totalZonas = max(1, 11 - valorMinimo);
      for(int i=0; i<totalZonas; i++) {
          double r = radius - (i * (radius/totalZonas));
          if (!r.isFinite || r < 0) r = 0;
          if ((valorMinimo+i)>=anilloNegro) { canvas.setColor(PdfService.colorNegro); canvas.drawEllipse(center.x, center.y, r, r); canvas.fillPath(); canvas.setColor(PdfService.colorBlanco); } else { canvas.setColor(esFondoNegro ? PdfService.colorBlanco : PdfService.colorGris); } canvas.setLineWidth(0.5); canvas.drawEllipse(center.x, center.y, r, r); canvas.strokePath();
      }
      if (tieneMosca) { canvas.setColor(PdfService.colorBlanco); canvas.setLineWidth(0.5); canvas.drawEllipse(center.x, center.y, (radius/totalZonas)/2, (radius/totalZonas)/2); canvas.strokePath(); }
  }
  void _pintarDuelo(PdfGraphics canvas, PdfPoint center, double radius) {
      canvas.setColor(colorNegroSuave); canvas.drawEllipse(center.x, center.y, radius, radius); canvas.fillPath();
      for(int i=0; i<6; i++) { double r = radius-(i*(radius/6)); if (!r.isFinite || r < 0) r = 0; canvas.setColor(PdfService.colorBlanco); canvas.setLineWidth(0.5); canvas.drawEllipse(center.x, center.y, r, r); canvas.strokePath(); }
      if (tieneMosca) { canvas.setColor(PdfService.colorBlanco); canvas.setLineWidth(0.5); canvas.drawEllipse(center.x, center.y, radius/12, radius/12); canvas.strokePath(); }
      if (tieneGuias) { double l = radius * 0.4; canvas.setColor(PdfService.colorBlanco); canvas.setLineWidth(2); canvas.drawLine(center.x - radius, center.y, center.x - radius + l, center.y); canvas.drawLine(center.x + radius, center.y, center.x + radius - l, center.y); canvas.strokePath(); }
  }
  void _pintarImpactos(PdfGraphics canvas, PdfPoint center, double radius) {
      canvas.setColor(PdfService.colorVerdeImpacto);
      int totalZonas = esEstiloDuelo ? 6 : max(1, 11 - valorMinimo);
      double tamano = (radius * 0.04) * (10 / totalZonas); if (!tamano.isFinite) tamano = 1;
      for(var d in disparos) { if (!d.x.isFinite || !d.y.isFinite) continue; double x = (d.x*radius)+center.x; double y = (d.y*radius)+center.y; if (!x.isFinite || !y.isFinite) continue; canvas.drawEllipse(x, y, tamano, tamano); canvas.fillPath(); canvas.setColor(PdfService.colorNegro); canvas.setLineWidth(0.2); canvas.drawEllipse(x, y, tamano, tamano); canvas.strokePath(); canvas.setColor(PdfService.colorVerdeImpacto); }
  }
}