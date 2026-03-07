import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math';

import '../models/disparo_model.dart';
import '../models/informe_model.dart';

class ExcelService {
  
  Future<void> generarYCompartirExcel({
    required String nombreTorneo,
    required DateTime fecha,
    required List<GrupoFaseInforme> grupos,
  }) async {
    var excel = Excel.createExcel();
    
    // Borramos la hoja por defecto 'Sheet1' y creamos las nuestras
    
    // --- HOJA 1: RESUMEN ---
    Sheet sheetResumen = excel['Resumen General'];
    
    // Cabecera
    sheetResumen.appendRow([TextCellValue('TORNEO'), TextCellValue(nombreTorneo)]);
    sheetResumen.appendRow([TextCellValue('FECHA'), TextCellValue("${fecha.day}/${fecha.month}/${fecha.year}")]);
    sheetResumen.appendRow([TextCellValue('')]); // Espacio

    // Totales
    List<Disparo> todos = [];
    for (var g in grupos) {
      if (!g.esEnsayo) {
        todos.addAll(g.disparos);
      }
    }
    
    int totalPuntos = todos.fold(0, (s, i) => s + i.puntuacion.floor());
    int totalMoscas = todos.where((d) => d.esMosca).length;

    sheetResumen.appendRow([TextCellValue('PUNTUACIÓN TOTAL'), IntCellValue(totalPuntos)]);
    sheetResumen.appendRow([TextCellValue('TOTAL MOSCAS (X)'), IntCellValue(totalMoscas)]);
    sheetResumen.appendRow([TextCellValue('')]);

    // Tabla Frecuencias
    sheetResumen.appendRow([TextCellValue('VALOR'), TextCellValue('CANTIDAD')]);
    Map<String, int> conteo = {"X": 0, "10": 0, "9": 0, "8": 0, "7": 0, "6": 0, "5": 0, "M": 0};
    for (var d in todos) {
       if (d.esMosca) {
         conteo["X"] = conteo["X"]! + 1;
       } else if (d.puntuacion < 1) {
         conteo["M"] = conteo["M"]! + 1;
       }
       else {
         int val = d.puntuacion.floor();
         if (val >= 5) {
           conteo["$val"] = (conteo["$val"] ?? 0) + 1;
         }
       }
    }
    // Escribir filas
    for (final k in ["X", "10", "9", "8", "7", "6", "5", "M"]) {
      sheetResumen.appendRow([TextCellValue(k), IntCellValue(conteo[k] ?? 0)]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // --- HOJA 2: DETALLE SERIES ---
    Sheet sheetDetalle = excel['Desglose Series'];
    
    List<CellValue> headers = [
      TextCellValue('FASE'), 
      TextCellValue('SERIE'), 
      TextCellValue('TOTAL'),
      TextCellValue('X'),
      TextCellValue('10'),
      TextCellValue('9'),
      TextCellValue('8'),
      TextCellValue('7'),
      TextCellValue('M')
    ];
    sheetDetalle.appendRow(headers);

    for (var grupo in grupos) {
      int blockSize = 5;
      if (grupo.disparos.length % 10 == 0 && grupo.disparos.length > 20) blockSize = 10;
      int numSeries = (grupo.disparos.length / blockSize).ceil();

      for (int i = 0; i < numSeries; i++) {
          int start = i * blockSize;
          int end = min(start + blockSize, grupo.disparos.length);
          var serie = grupo.disparos.sublist(start, end);
          
          int ptsSerie = serie.fold(0, (s, t) => s + t.puntuacion.floor());
          
          Map<String, int> c = {"X":0, "10":0, "9":0, "8":0, "7":0, "M":0};
          for(var t in serie) {
              if (t.esMosca) {
                c["X"] = c["X"]! + 1;
              } else if (t.puntuacion < 1) {
                c["M"] = c["M"]! + 1;
              }
              else {
                 int v = t.puntuacion.floor();
                 if (c.containsKey("$v")) {
                   c["$v"] = c["$v"]! + 1;
                 }
              }
          }

          sheetDetalle.appendRow([
            TextCellValue(grupo.titulo + (grupo.esEnsayo ? " (E)" : "")),
            IntCellValue(i + 1),
            IntCellValue(ptsSerie),
            IntCellValue(c["X"]!),
            IntCellValue(c["10"]!),
            IntCellValue(c["9"]!),
            IntCellValue(c["8"]!),
            IntCellValue(c["7"]!),
            IntCellValue(c["M"]!),
          ]);
      }
    }

    // --- GUARDAR Y DESCARGAR/COMPARTIR ---
    var fileBytes = excel.save();
    if (fileBytes != null) {
      String filePath;
      
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // LÓGICA ESCRITORIO: Guardar en Descargas con nombre único
        final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        // Nombre con fecha y hora para no sobrescribir
        String fechaStr = "${fecha.year}${fecha.month.toString().padLeft(2,'0')}${fecha.day.toString().padLeft(2,'0')}_${DateTime.now().hour}${DateTime.now().minute}";
        filePath = "${directory.path}/Reporte_Tiro_$fechaStr.xlsx";
      } else {
        // LÓGICA MÓVIL: Guardar en temporal para compartir
        final directory = await getTemporaryDirectory();
        filePath = "${directory.path}/Reporte_Tiro.xlsx";
      }

      // Escribir archivo físico
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);

      // Lanzar el menú de compartir (En móvil permite "Guardar en Archivos")
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: 'Reporte de Tiro generado.',
        ),
      );
    }
  }
}