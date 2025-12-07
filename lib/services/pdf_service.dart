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
  
  // COLORES
  static const PdfColor colorCrema = PdfColor.fromInt(0xFFF5F3E0);
  static const PdfColor colorNegro = PdfColor.fromInt(0xFF000000);
  static const PdfColor colorBlanco = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor colorGris = PdfColor.fromInt(0xFF9E9E9E);
  static const PdfColor colorGrisClaro = PdfColor.fromInt(0xFFEEEEEE);
  static const PdfColor colorGrisBorde = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor colorVerdeImpacto = PdfColor.fromInt(0xFF00C853);
  static const PdfColor colorAzul = PdfColor.fromInt(0xFF1976D2); 
  static const PdfColor colorAzulClaro = PdfColor.fromInt(0xFFBBDEFB); 
  static const PdfColor colorRojoMPI = PdfColor.fromInt(0xFFD50000);
  static const PdfColor colorMoradoApp = PdfColor.fromInt(0xFF1976D2);
  static const PdfColor colorNaranjaAlerta = PdfColor.fromInt(0xFFFF9800); 
  static const PdfColor colorNegroSuave = PdfColor.fromInt(0xFF1A1A1A);

  static const PdfColor colorGraveBg = PdfColor.fromInt(0xFFFFEBEE); 
  static const PdfColor colorGraveTxt = PdfColor.fromInt(0xFFB71C1C); 
  static const PdfColor colorMedioBg = PdfColor.fromInt(0xFFFFF3E0); 
  static const PdfColor colorMedioTxt = PdfColor.fromInt(0xFFE65100); 
  static const PdfColor colorLeveBg = PdfColor.fromInt(0xFFECEFF1); 
  static const PdfColor colorLeveTxt = PdfColor.fromInt(0xFF37474F); 

  // --- FUNCIÓN DE SEGURIDAD (SANITIZADOR) ---
  double _sane(double val) {
    if (val.isNaN || val.isInfinite) return 0.0;
    return val;
  }

  // =======================================================================
  // A) INFORME MODERNO
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
                     color: colorAzul,
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
                             if (constraints == null || constraints.maxWidth.isNaN || constraints.maxWidth <= 0) {
                                return pw.Container(height: 100, child: pw.Center(child: pw.Text("Error de visualización"))); 
                             }
                             return pw.CustomPaint(
                               size: PdfPoint(constraints.maxWidth, constraints.maxWidth),
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
                      pw.Text("Sin datos suficientes para diagnóstico.", style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10))
                   else
                      ...datos.diagnostico.take(5).map((d) => _buildBarraError(d)),
                   pw.SizedBox(height: 30),
                ]
              );
            }).toList(),

            pw.SizedBox(height: 10),
            
            // GRÁFICA "SEXY" - BLINDADA
            if (datosProgreso.isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10), color: colorAzul, width: double.infinity, child: pw.Text("EVOLUCIÓN", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.SizedBox(height: 20),
                pw.Container(
                  height: 150, 
                  width: double.infinity, 
                  child: _buildGraficaModerna(datosProgreso) 
                ),
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
  // B) INFORME CLÁSICO
  // =======================================================================
  Future<void> generarYMostrarPdf({required Sesion sesion, required List<Disparo> disparos, required PlantillaTiempos plantilla, required EquipoDetalle? equipo, required MunicionDetalle? municion, required int valorMinimo, required int anilloNegro, required bool esFondoNegro, required bool tieneMosca, required bool tieneGuias, required bool esEstiloDuelo, PerfilUsuario? perfil, String? lugar, String? observaciones}) async {
      await generarInformeTorneoProfesional(nombreTorneo: plantilla.nombreDisciplina, fecha: sesion.fecha, grupos: [GrupoFaseInforme(titulo: "Serie Única / Entrenamiento", disparos: disparos, valorMinimo: valorMinimo, anilloNegro: anilloNegro, esFondoNegro: esFondoNegro, tieneMosca: tieneMosca, tieneGuias: tieneGuias, esEstiloDuelo: esEstiloDuelo, esEnsayo: false)], equipo: equipo, municion: municion, perfil: perfil, lugar: lugar, observaciones: observaciones);
  }
  Future<void> generarInformeTorneoProfesional({required String nombreTorneo, required DateTime fecha, required List<GrupoFaseInforme> grupos, EquipoDetalle? equipo, MunicionDetalle? municion, PerfilUsuario? perfil, String? lugar, String? observaciones}) async {
    final doc = pw.Document(); final fontRegular = await PdfGoogleFonts.openSansRegular(); final fontBold = await PdfGoogleFonts.openSansBold(); pw.ImageProvider? logoImage; try { logoImage = await imageFromAssetBundle('assets/logo.png'); } catch (_) {}
    List<Disparo> disparosPuntuables = []; for(var g in grupos) if (!g.esEnsayo) disparosPuntuables.addAll(g.disparos); int totalPuntos = disparosPuntuables.fold(0, (sum, item) => sum + item.puntuacion.floor()); int totalMoscas = disparosPuntuables.where((d) => d.esMosca).length; String fechaStr = "${fecha.day}/${fecha.month}/${fecha.year}";
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(30), theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold), build: (pw.Context context) {
          return [pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [if (logoImage != null) pw.Container(width: 60, height: 60, child: pw.Image(logoImage)), pw.SizedBox(width: 20), pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text("ACTA DE PUNTUACIÓN", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: colorAzul)), pw.Text(nombreTorneo, style: const pw.TextStyle(fontSize: 14))]))]), pw.SizedBox(height: 15), pw.Table(border: pw.TableBorder.all(color: colorGrisBorde, width: 0.5), children: [pw.TableRow(decoration: const pw.BoxDecoration(color: colorGrisClaro), children: [_celdaFicha("TIRADOR", perfil?.nombre ?? ""), _celdaFicha("LICENCIA", perfil?.licencia ?? ""), _celdaFicha("CLUB", perfil?.club ?? "")]), pw.TableRow(children: [_celdaFicha("ARMA", equipo?.nombre ?? ""), _celdaFicha("MUNICIÓN", municion?.marca ?? ""), _celdaFicha("FECHA", "$fechaStr - ${lugar ?? ''}")])]), pw.SizedBox(height: 20), pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 10), decoration: const pw.BoxDecoration(color: colorAzul), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(" PUNTUACIÓN TOTAL", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 16)), pw.Text("$totalPuntos ($totalMoscas x)  ", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 18))])), _construirTablaFrecuencias(disparosPuntuables, mostrarCabecera: true), pw.SizedBox(height: 20), ..._generarBloquesDetallados(grupos), pw.Spacer(), pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [pw.Column(children: [pw.Container(width: 120, height: 1, color: PdfColors.black), pw.SizedBox(height: 5), pw.Text("Firma del Tirador", style: const pw.TextStyle(fontSize: 8))]), pw.Column(children: [pw.Container(width: 120, height: 1, color: PdfColors.black), pw.SizedBox(height: 5), pw.Text("Firma Árbitro", style: const pw.TextStyle(fontSize: 8))])])];
    })); await Printing.layoutPdf(onLayout: (format) => doc.save(), name: 'Acta_Puntuacion.pdf');
  }

  // --- HELPERS ---
  pw.Widget _celdaFicha(String t, String v) { return pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(t, style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)), pw.Text(v.isEmpty ? "-" : v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))])); }
  List<pw.Widget> _generarBloquesDetallados(List<GrupoFaseInforme> grupos) { List<pw.Widget> w = []; for (var g in grupos) { w.add(pw.Padding(padding: const pw.EdgeInsets.only(top: 10, bottom: 5), child: pw.Text(g.titulo, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: colorAzul)))); int bs = g.disparos.length > 20 ? 10 : 5; int ns = (g.disparos.length / bs).ceil(); Map<int, pw.TableColumnWidth> cw = { 0: const pw.FixedColumnWidth(35), bs+1: const pw.FixedColumnWidth(40) }; for(int k=1; k<=bs; k++) cw[k] = const pw.FlexColumnWidth(); for (int i = 0; i < ns; i++) { int s = i * bs; int e = min(s + bs, g.disparos.length); var ser = g.disparos.sublist(s, e); int pts = ser.fold(0, (x, y) => x + y.puntuacion.floor()); List<String> f = ["Serie ${i + 1}"]; for(var t in ser) f.add(t.puntuacion >= 10 ? (t.esMosca ? "X" : "10") : t.puntuacion.floor().toString()); while(f.length <= bs) f.add("-"); f.add("$pts"); List<String> h = ['S']; for(int k=1; k<=bs; k++) h.add('$k'); h.add('TOT'); w.add(pw.Table.fromTextArray(headers: i == 0 ? h : [], data: [f], border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), cellStyle: const pw.TextStyle(fontSize: 9), cellAlignment: pw.Alignment.center, headerDecoration: i==0 ? const pw.BoxDecoration(color: colorGrisClaro) : null, columnWidths: cw)); } } return w; }
  pw.Widget _construirTablaFrecuencias(List<Disparo> d, {bool mostrarCabecera = true}) { Map<String, int> c = {"X":0,"10":0,"9":0,"8":0,"7":0,"6":0,"5":0,"4":0,"3":0,"2":0,"1":0,"M":0}; for (var x in d) { if (x.esMosca) c["X"] = c["X"]! + 1; else if (x.puntuacion < 1) c["M"] = c["M"]! + 1; else { int v = x.puntuacion.floor(); if(v>=1 && v<=10) c["$v"] = c["$v"]! + 1; } } final h = ['Valor', 'Cantidad', 'Subtotal']; final da = <List<String>>[]; const o = ["X", "10", "9", "8", "7", "6", "5", "4", "3", "2", "1", "M"]; for(var k in o) { int cnt = c[k] ?? 0; if (cnt > 0) { String s = k == "M" ? "0" : "${(k=="X"?10:int.parse(k)) * cnt}"; da.add([k, "$cnt", s]); } } return pw.Table.fromTextArray(headers: mostrarCabecera ? h : [], data: da, border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), headerDecoration: const pw.BoxDecoration(color: colorGrisClaro), cellStyle: const pw.TextStyle(fontSize: 9), cellAlignment: pw.Alignment.center, cellAlignments: {0: pw.Alignment.centerLeft}, columnWidths: {0: const pw.FixedColumnWidth(40), 1: const pw.FixedColumnWidth(40), 2: const pw.FixedColumnWidth(40)}); }
  pw.Widget _buildCabeceraPrincipal(pw.ImageProvider? l, String t, PerfilUsuario? p, String i) { return pw.Row(children: [if(l!=null) pw.Container(width:50,height:50,child:pw.Image(l)), pw.SizedBox(width:15), pw.Expanded(child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text(t,style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold,color:colorAzul)),pw.Text("Tirador: ${p?.nombre??'Usuario'} (Lic: ${p?.licencia??'-'})",style:const pw.TextStyle(fontSize:10)),pw.Text(i,style:const pw.TextStyle(fontSize:10))]))]); }
  
  pw.Widget _buildPanelCorreccion(AnalisisAgrupacion a, EquipoDetalle? e) {
    String consejo = "Miras Correctas";
    if (!_sane(a.mpi.x).isNaN && !_sane(a.mpi.y).isNaN) {
        if ((e?.correccionClick??0)>0 && (a.mpi.x.abs()>0.05 || a.mpi.y.abs()>0.05)) { consejo = "CORREGIR MIRAS"; }
    }
    return pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
        pw.Text("CORRECCIÓN",style:pw.TextStyle(fontSize:8,fontWeight:pw.FontWeight.bold,color:PdfColors.grey)),
        pw.Text(consejo,style:pw.TextStyle(fontSize:14,fontWeight:pw.FontWeight.bold,color:PdfColors.green)),
        if (a.consejoTendencia.isNotEmpty && a.consejoTendencia != "Agrupación Circular (Equilibrada)")
          pw.Padding(padding: const pw.EdgeInsets.only(top: 8), child: pw.Text(a.consejoTendencia, style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey800, fontStyle: pw.FontStyle.italic)))
    ]);
  }
  
  pw.Widget _buildBarraError(DiagnosticoTecnico error) {
    return pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
                pw.Container(width: 14, height: 14, alignment: pw.Alignment.center, decoration: const pw.BoxDecoration(color: colorNaranjaAlerta, shape: pw.BoxShape.circle), child: pw.Text("!", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.SizedBox(width: 5),
                pw.Text(error.nombreError, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Spacer(),
                pw.Text("${_sane(error.porcentaje).round()}%", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
          if (error.detalles.isNotEmpty)
            pw.Padding(padding: const pw.EdgeInsets.only(left: 20, top: 4), child: pw.Wrap(spacing: 4, runSpacing: 4, children: error.detalles.map((detalle) {
                   PdfColor bg = detalle.puntuacion < 7 ? colorGraveBg : (detalle.puntuacion < 9 ? colorMedioBg : colorLeveBg);
                   PdfColor txt = detalle.puntuacion < 7 ? colorGraveTxt : (detalle.puntuacion < 9 ? colorMedioTxt : colorLeveTxt);
                   return pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: txt, width: 0.5)), child: pw.Text(detalle.etiqueta, style: pw.TextStyle(color: txt, fontSize: 8, fontWeight: pw.FontWeight.bold)));
                }).toList()))
    ]));
  }
  
  // --- GRÁFICA SUPER BLINDADA ---
  pw.Widget _buildGraficaModerna(List<Map<String, dynamic>> puntos) {
    if (puntos.isEmpty) return pw.Center(child: pw.Text("Sin datos de evolución", style: const pw.TextStyle(color: PdfColors.grey)));
    
    List<pw.PointChartValue> valores = [];
    for (int i = 0; i < puntos.length; i++) {
      double valY = (puntos[i]['total'] as num).toDouble();
      valores.add(pw.PointChartValue(i.toDouble(), _sane(valY)));
    }

    double minVal = 0, maxVal = 10;
    if (valores.isNotEmpty) {
       minVal = valores.map((e) => e.y).reduce(min);
       maxVal = valores.map((e) => e.y).reduce(max);
    }
    if (minVal == maxVal) { minVal -= 5; maxVal += 5; }

    List<double> ticksX = []; int paso = 1; if (valores.length > 15) paso = (valores.length / 10).ceil();
    for (int i = 0; i < valores.length; i++) { if (i % paso == 0) ticksX.add(valores[i].x); }
    
    // BLINDAJE PARA UN SOLO PUNTO (Esto causaba el error)
    if (ticksX.isEmpty && valores.isNotEmpty) ticksX.add(valores.first.x);
    if (ticksX.length == 1) { 
       // Si solo hay un tick, el eje X tiene tamaño 0. Añadimos un fake.
       ticksX.add(ticksX[0] + 1); 
    }

    return pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis(ticksX),
        yAxis: pw.FixedAxis([minVal, (minVal+maxVal)/2, maxVal], format: (v) => v.toInt().toString()),
      ),
      datasets: [pw.LineDataSet(data: valores, isCurved: true, smoothness: 0.35, color: colorAzul, lineWidth: 2, drawSurface: true, surfaceColor: colorAzulClaro, drawPoints: true, pointSize: 4, pointColor: colorAzul)],
    );
  }

  void _dianaFinalV4(PdfGraphics canvas, PdfPoint size, TipoDiana diana, AnalisisAgrupacion analisis, {required PdfFont font}) {
      if (size.x.isNaN || size.y.isNaN || size.x <= 0 || size.y <= 0) return;

      double cx = size.x / 2; double cy = size.y / 2; double radius = size.x / 2;
      canvas.setColor(diana.esFondoNegro ? PdfColors.black : colorCrema); canvas.drawEllipse(cx, cy, radius, radius); canvas.fillPath();
      int totalZonas = 11 - diana.valorMinimo; 
      if (diana.nombre.toLowerCase().contains("duelo")) totalZonas = 6; 
      if (totalZonas <= 0) totalZonas = 1; // BLINDAJE
      
      double anchoZona = radius / totalZonas;
      for(int i=0; i<totalZonas; i++) {
         double r = radius - (i * anchoZona); int numAnillo = diana.valorMinimo + i; bool esNegro = numAnillo >= diana.anilloNegroInicio;
         if (diana.esFondoNegro) { canvas.setColor(PdfColors.white); canvas.setLineWidth(0.5); canvas.drawEllipse(cx, cy, r, r); canvas.strokePath(); } else { if (esNegro) { canvas.setColor(PdfColors.black); canvas.drawEllipse(cx, cy, r, r); canvas.fillPath(); canvas.setColor(PdfColors.white); } else { canvas.setColor(PdfColors.grey); } canvas.setLineWidth(0.5); canvas.drawEllipse(cx, cy, r, r); canvas.strokePath(); }
         if (numAnillo < 10 && r > 10) { PdfColor colorNum = (esNegro || diana.esFondoNegro) ? PdfColors.white : PdfColors.black; canvas.setColor(colorNum); String txt = numAnillo.toString(); double fontSize = 8.0; double offText = 3; canvas.drawString(font, fontSize, txt, cx - offText, cy - r + (anchoZona/2) - offText); canvas.drawString(font, fontSize, txt, cx - offText, cy + r - (anchoZona/2) - offText); canvas.drawString(font, fontSize, txt, cx - r + (anchoZona/2) - offText, cy - offText); canvas.drawString(font, fontSize, txt, cx + r - (anchoZona/2) - offText, cy - offText); }
      }
      canvas.setColor(colorVerdeImpacto); double tamanoPunto = radius * 0.035;
      for (var d in analisis.disparosValidos) { 
         if (d.x.isNaN || d.y.isNaN || d.x.isInfinite || d.y.isInfinite) continue;
         double x = (d.x * radius) + cx; double y = cy - (d.y * radius); 
         canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto); canvas.fillPath(); canvas.setColor(diana.esFondoNegro ? PdfColors.white : PdfColors.black); canvas.setLineWidth(0.2); canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto); canvas.strokePath(); canvas.setColor(colorVerdeImpacto); 
      }
      canvas.setColor(PdfColors.grey);
      for (var d in analisis.disparosDescartados) { 
         if (d.x.isNaN || d.y.isNaN || d.x.isInfinite || d.y.isInfinite) continue;
         double x = (d.x * radius) + cx; double y = cy - (d.y * radius); canvas.drawEllipse(x, y, tamanoPunto, tamanoPunto); canvas.fillPath(); 
      }
      if (analisis.disparosValidos.isNotEmpty && !_sane(analisis.mpi.x).isNaN && !_sane(analisis.mpi.y).isNaN) { 
         double mpiX = (analisis.mpi.x * radius) + cx; double mpiY = cy - (analisis.mpi.y * radius); canvas.setColor(colorRojoMPI); canvas.setLineWidth(2); double l = 10; canvas.drawLine(mpiX - l, mpiY, mpiX + l, mpiY); canvas.drawLine(mpiX, mpiY - l, mpiX, mpiY + l); canvas.strokePath(); canvas.setLineWidth(1); canvas.drawEllipse(mpiX, mpiY, 4, 4); canvas.strokePath(); 
      }
  }
}