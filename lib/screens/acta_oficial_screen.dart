import 'package:flutter/material.dart';
import '../models/disparo_model.dart';
import '../models/sesion_model.dart';
import '../models/acta_oficial_model.dart';
import '../services/entrenamiento_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tiro_amg_app_bar_title.dart';
import '../widgets/app_ui.dart';

/// Permite introducir puntuación oficial del árbitro a cualquier nivel:
/// total del torneo, total por serie y/o tiro a tiro.
class ActaOficialScreen extends StatefulWidget {
  final int idModalidad;
  final DateTime fecha;
  final String nombreTorneo;

  const ActaOficialScreen({
    super.key,
    required this.idModalidad,
    required this.fecha,
    required this.nombreTorneo,
  });

  @override
  State<ActaOficialScreen> createState() => _ActaOficialScreenState();
}

class _SerieActaState {
  final SesionResumen resumen;
  final List<Disparo> disparos;
  final TextEditingController serieCtrl;
  final Map<int, TextEditingController> tiroCtrls;
  final Map<int, bool> tiroMosca;

  _SerieActaState({
    required this.resumen,
    required this.disparos,
    required this.serieCtrl,
    required this.tiroCtrls,
    required this.tiroMosca,
  });
}

class _ActaOficialScreenState extends State<ActaOficialScreen> {
  final _service = EntrenamientoService();
  final _totalCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  final _desglosePegarCtrl = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;
  List<_SerieActaState> _series = [];
  ComparacionActaOficial? _comparacion;
  /// Conteos oficiales: X, 10, 9…0
  final Map<String, int> _conteos = {
    for (final k in ActaOficialTorneo.clavesOrden) k: 0,
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    _notaCtrl.dispose();
    _desglosePegarCtrl.dispose();
    for (final s in _series) {
      s.serieCtrl.dispose();
      for (final c in s.tiroCtrls.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    final acta = await _service.obtenerActaOficialTorneo(
      widget.idModalidad,
      widget.fecha,
    );
    final fases = await _service.obtenerFasesDeTorneoRealizado(
      widget.idModalidad,
      widget.fecha,
    );
    final puntuables = fases.where((s) => !s.esEnsayo).toList();

    final series = <_SerieActaState>[];
    for (final r in puntuables) {
      final disparos = await _service.obtenerDisparosDeSesion(r.id);
      final ctrls = <int, TextEditingController>{};
      final moscas = <int, bool>{};
      for (final d in disparos) {
        if (d.id == null) continue;
        final txt = d.puntuacionOficial == null
            ? ''
            : (d.esMoscaOficial == true
                ? 'X'
                : _fmtPts(d.puntuacionOficial!));
        ctrls[d.id!] = TextEditingController(text: txt);
        moscas[d.id!] = d.esMoscaOficial == true;
      }
      series.add(
        _SerieActaState(
          resumen: r,
          disparos: disparos,
          serieCtrl: TextEditingController(
            text: r.puntuacionOficialSerie == null
                ? ''
                : _fmtPts(r.puntuacionOficialSerie!),
          ),
          tiroCtrls: ctrls,
          tiroMosca: moscas,
        ),
      );
    }

    final comp = await _service.compararActaOficial(
      idModalidad: widget.idModalidad,
      fecha: widget.fecha,
    );

    if (!mounted) return;
    setState(() {
      _totalCtrl.text =
          acta?.totalOficial == null ? '' : _fmtPts(acta!.totalOficial!);
      _notaCtrl.text = acta?.nota ?? '';
      for (final k in ActaOficialTorneo.clavesOrden) {
        _conteos[k] = acta?.conteos[k] ?? 0;
      }
      if (acta != null && acta.tieneConteos) {
        _desglosePegarCtrl.text = acta.resumenConteos;
      }
      _series = series;
      _comparacion = comp;
      _cargando = false;
    });
  }

  String _fmtPts(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  double? _parsePts(String raw) {
    final t = raw.trim().toUpperCase();
    if (t.isEmpty) return null;
    if (t == 'X') return 10;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final total = _parsePts(_totalCtrl.text);
      await _service.guardarActaOficialTorneo(
        ActaOficialTorneo(
          idModalidad: widget.idModalidad,
          fechaDia: widget.fecha.toIso8601String().substring(0, 10),
          totalOficial: total,
          moscasOficiales: _conteos['X'],
          nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
          conteos: Map<String, int>.from(_conteos),
        ),
      );

      for (final s in _series) {
        await _service.actualizarPuntuacionOficialSerie(
          idSesion: s.resumen.id,
          puntuacionOficialSerie: _parsePts(s.serieCtrl.text),
        );
        for (final d in s.disparos) {
          if (d.id == null) continue;
          final raw = s.tiroCtrls[d.id!]?.text ?? '';
          final t = raw.trim().toUpperCase();
          if (t.isEmpty) {
            await _service.actualizarPuntuacionOficialDisparo(
              idDisparo: d.id!,
              puntuacionOficial: null,
              esMoscaOficial: null,
            );
          } else if (t == 'X') {
            await _service.actualizarPuntuacionOficialDisparo(
              idDisparo: d.id!,
              puntuacionOficial: 10,
              esMoscaOficial: true,
            );
          } else {
            final pts = _parsePts(t);
            await _service.actualizarPuntuacionOficialDisparo(
              idDisparo: d.id!,
              puntuacionOficial: pts,
              esMoscaOficial: false,
            );
          }
        }
      }

      final comp = await _service.compararActaOficial(
        idModalidad: widget.idModalidad,
        fecha: widget.fecha,
      );
      if (!mounted) return;
      setState(() {
        _comparacion = comp;
        _guardando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acta oficial guardada')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    }
  }

  void _rellenarSerieDesdeTiros(_SerieActaState s) {
    double sum = 0;
    var ok = true;
    for (final d in s.disparos) {
      if (d.id == null) continue;
      final pts = _parsePts(s.tiroCtrls[d.id!]?.text ?? '');
      if (pts == null) {
        ok = false;
        break;
      }
      sum += pts;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa todos los tiros oficiales de la serie'),
        ),
      );
      return;
    }
    setState(() => s.serieCtrl.text = _fmtPts(sum));
  }

  void _rellenarTotalDesdeSeries() {
    double sum = 0;
    var ok = true;
    for (final s in _series) {
      final pts = _parsePts(s.serieCtrl.text);
      if (pts == null) {
        // Intentar desde tiros
        double sumT = 0;
        var all = true;
        for (final d in s.disparos) {
          if (d.id == null) continue;
          final p = _parsePts(s.tiroCtrls[d.id!]?.text ?? '');
          if (p == null) {
            all = false;
            break;
          }
          sumT += p;
        }
        if (!all) {
          ok = false;
          break;
        }
        sum += sumT;
      } else {
        sum += pts;
      }
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faltan oficiales en alguna serie o tiro'),
        ),
      );
      return;
    }
    setState(() => _totalCtrl.text = _fmtPts(sum));
  }

  void _copiarAppAOficial() {
    setState(() {
      for (final s in _series) {
        s.serieCtrl.text = s.resumen.totalPuntos.toString();
        for (final d in s.disparos) {
          if (d.id == null) continue;
          s.tiroCtrls[d.id!]!.text =
              d.esMosca ? 'X' : _fmtPts(d.puntuacion);
          s.tiroMosca[d.id!] = d.esMosca;
        }
      }
      _totalCtrl.text = _series
          .fold<int>(0, (a, s) => a + s.resumen.totalPuntos)
          .toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final app = _comparacion?.totalApp ?? 0;
    final ofi = _comparacion?.totalOficial;
    final delta = _comparacion?.delta;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const TiroAmgAppBarTitle(section: 'Acta oficial'),
        actions: [
          TextButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.nombreTorneo,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Introduce lo que te dio el árbitro. Lo más habitual: desglose '
            '(3-X, 2-10, 6-8…). También puedes poner solo el total, por series '
            'o tiro a tiro.',
            style: TextStyle(fontSize: 13, color: AppColors.subtitle, height: 1.35),
          ),
          const SizedBox(height: 16),

          // Resumen comparación
          AppSectionCard(
            title: 'Comparación',
            titleIcon: Icons.compare_arrows,
            titleIconColor: AppColors.accentCompetition,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _kpi('App', app.toStringAsFixed(app == app.roundToDouble() ? 0 : 1)),
                    _kpi(
                      'Oficial',
                      ofi == null
                          ? '—'
                          : ofi.toStringAsFixed(ofi == ofi.roundToDouble() ? 0 : 1),
                    ),
                    _kpi(
                      'Δ',
                      delta == null
                          ? '—'
                          : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(delta == delta.roundToDouble() ? 0 : 1)}',
                      color: delta == null
                          ? AppColors.subtitle
                          : (delta == 0
                              ? Colors.green
                              : (delta < 0
                                  ? AppColors.accentDanger
                                  : AppColors.accentAnalytics)),
                    ),
                  ],
                ),
                if (_comparacion != null && _comparacion!.fuenteOficial != 'ninguna')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _textoFuente(_comparacion!.fuenteOficial),
                      style: TextStyle(fontSize: 11, color: AppColors.subtitle),
                    ),
                  ),
                if (_comparacion?.resumenConteos != null &&
                    _comparacion!.resumenConteos!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _comparacion!.resumenConteos!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.title,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          AppSectionCard(
            title: 'Desglose oficial (recomendado)',
            titleIcon: Icons.grid_view,
            titleIconColor: AppColors.accentCompetition,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Cantidad de cada puntuación que te dio el árbitro '
                  '(ej. 3 moscas, 2 dieces, 6 ochos…).',
                  style: TextStyle(fontSize: 12.5, color: AppColors.subtitle),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _desglosePegarCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Pegar desglose',
                    hintText: '3-X, 2-10, 6-8',
                    helperText: 'Formato: cantidad-valor separados por comas',
                  ),
                  onSubmitted: (_) => _aplicarDesgloseTexto(),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _aplicarDesgloseTexto,
                    icon: const Icon(Icons.content_paste_go, size: 18),
                    label: const Text('Aplicar texto'),
                  ),
                ),
                const Divider(),
                ...ActaOficialTorneo.clavesOrden.map(_buildFilaConteo),
                const SizedBox(height: 8),
                Text(
                  'Disparos: ${_totalDisparosConteo}  ·  '
                  'Suma: ${_sumaConteos == null ? '—' : _fmtPts(_sumaConteos!)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.title,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _sumaConteos == null
                          ? null
                          : () => setState(
                                () => _totalCtrl.text = _fmtPts(_sumaConteos!),
                              ),
                      icon: const Icon(Icons.south, size: 18),
                      label: const Text('Pasar suma al total'),
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        for (final k in ActaOficialTorneo.clavesOrden) {
                          _conteos[k] = 0;
                        }
                        _desglosePegarCtrl.clear();
                      }),
                      child: const Text('Limpiar desglose'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          AppSectionCard(
            title: 'Total del torneo (árbitro)',
            titleIcon: Icons.emoji_events,
            titleIconColor: AppColors.accentCompetition,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _totalCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Total oficial',
                    hintText: 'Opcional si ya rellenaste el desglose',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _rellenarTotalDesdeSeries,
                      icon: const Icon(Icons.functions, size: 18),
                      label: const Text('Calcular desde series/tiros'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _copiarAppAOficial,
                      icon: const Icon(Icons.copy_all, size: 18),
                      label: const Text('Copiar app → oficial'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Detalle avanzado (serie / tiro)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Opcional. Úsalo solo si conoces el desglose por serie o por disparo.',
            style: TextStyle(fontSize: 12, color: AppColors.subtitle),
          ),
          const SizedBox(height: 8),
          ..._series.map(_buildSerieCard),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: const Text('Guardar acta oficial'),
          ),
        ],
      ),
    );
  }

  int get _totalDisparosConteo =>
      _conteos.values.fold<int>(0, (a, b) => a + b);

  double? get _sumaConteos {
    final tmp = ActaOficialTorneo(
      idModalidad: 0,
      fechaDia: '',
      conteos: _conteos,
    );
    return tmp.totalDesdeConteos;
  }

  void _aplicarDesgloseTexto() {
    final parsed =
        ActaOficialTorneo.parseDesgloseTexto(_desglosePegarCtrl.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo leer. Ejemplo: 3-X, 2-10, 6-8'),
        ),
      );
      return;
    }
    setState(() {
      for (final k in ActaOficialTorneo.clavesOrden) {
        _conteos[k] = parsed[k] ?? 0;
      }
      _desglosePegarCtrl.text = ActaOficialTorneo(
        idModalidad: 0,
        fechaDia: '',
        conteos: _conteos,
      ).resumenConteos;
    });
  }

  Widget _buildFilaConteo(String clave) {
    final n = _conteos[clave] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              clave,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: clave == 'X'
                    ? AppColors.accentCompetition
                    : AppColors.title,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: n <= 0
                ? null
                : () => setState(() => _conteos[clave] = n - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$n',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.title,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _conteos[clave] = n + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
          if (n > 0)
            Text(
              '= ${_fmtPts((clave == 'X' ? 10.0 : double.parse(clave)) * n)}',
              style: TextStyle(fontSize: 12, color: AppColors.subtitle),
            ),
        ],
      ),
    );
  }

  String _textoFuente(String f) {
    switch (f) {
      case 'torneo':
        return 'Oficial tomado del total del torneo';
      case 'conteos':
        return 'Oficial calculado desde el desglose (X, 10, 9…)';
      case 'series':
        return 'Oficial calculado desde series';
      case 'tiros':
        return 'Oficial calculado desde tiros (parcial o completo)';
      default:
        return '';
    }
  }

  Widget _kpi(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.subtitle)),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.title,
          ),
        ),
      ],
    );
  }

  Widget _buildSerieCard(_SerieActaState s) {
    final titulo = (s.resumen.nota ?? s.resumen.nombreTitulo)
        .replaceFirst(RegExp(r'^Torneo:\s*[^|]+\|\s*'), '')
        .trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(titulo.isEmpty ? s.resumen.nombreTitulo : titulo),
        subtitle: Text(
          'App: ${s.resumen.totalPuntos} pts'
          '${s.resumen.puntuacionOficialSerie != null ? ' · Oficial serie: ${_fmtPts(s.resumen.puntuacionOficialSerie!)}' : ''}',
          style: TextStyle(fontSize: 12, color: AppColors.subtitle),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: s.serieCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Total oficial de la serie',
              hintText: 'Opcional si rellenas tiro a tiro',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _rellenarSerieDesdeTiros(s),
              icon: const Icon(Icons.functions, size: 18),
              label: const Text('Calcular serie desde tiros'),
            ),
          ),
          const Divider(),
          Text(
            'Tiros (App → Oficial). Usa X para mosca, vacío para borrar.',
            style: TextStyle(fontSize: 12, color: AppColors.subtitle),
          ),
          const SizedBox(height: 8),
          ...s.disparos.map((d) {
            if (d.id == null) return const SizedBox.shrink();
            final appTxt = d.esMosca ? 'X' : _fmtPts(d.puntuacion);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      '#${d.numero}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.title,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      appTxt,
                      style: TextStyle(color: AppColors.subtitle),
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: s.tiroCtrls[d.id!],
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Oficial',
                        hintText: '0–10 / X',
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
