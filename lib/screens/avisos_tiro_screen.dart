import 'package:flutter/material.dart';

import '../services/audio_service.dart';

class AvisosTiroScreen extends StatefulWidget {
  const AvisosTiroScreen({super.key});

  @override
  State<AvisosTiroScreen> createState() => _AvisosTiroScreenState();
}

class _AvisosTiroScreenState extends State<AvisosTiroScreen> {
  AvisoTiroPerfil _perfil = AvisoTiroPerfil.competicion;
  bool _mute = false;
  bool _vibracion = true;
  bool _autoPerfil = true;
  double _volumen = 1.0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    await AudioService.instance.init();
    if (!mounted) return;
    setState(() {
      _perfil = AudioService.instance.perfil;
      _mute = AudioService.instance.mute;
      _vibracion = AudioService.instance.vibracion;
      _autoPerfil = AudioService.instance.autoPerfil;
      _volumen = AudioService.instance.volumen;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos de tiro'),
        backgroundColor: Colors.indigo,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.campaign,
                            color: Colors.indigo,
                            size: 30,
                          ),
                          title: Text('Perfil de avisos'),
                          subtitle: Text(
                            'Competición = pitidos. Entrenamiento = pitidos + voz.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<AvisoTiroPerfil>(
                          segments: const [
                            ButtonSegment(
                              value: AvisoTiroPerfil.competicion,
                              label: Text('Competición'),
                              icon: Icon(Icons.sports_score),
                            ),
                            ButtonSegment(
                              value: AvisoTiroPerfil.entrenamiento,
                              label: Text('Entrenamiento'),
                              icon: Icon(Icons.record_voice_over),
                            ),
                          ],
                          selected: {_perfil},
                          onSelectionChanged: (s) async {
                            final next = s.first;
                            await AudioService.instance.setPerfil(next);
                            if (!mounted) return;
                            setState(() => _perfil = next);
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Perfil automático'),
                          subtitle: const Text(
                            'Sugiere perfil al iniciar serie. Si cambias el perfil a mano, se respeta hasta que reactive esta opción.',
                          ),
                          value: _autoPerfil,
                          onChanged: (v) async {
                            await AudioService.instance.setAutoPerfil(v);
                            if (!mounted) return;
                            setState(() => _autoPerfil = v);
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Vibración'),
                          value: _vibracion,
                          onChanged: (v) async {
                            await AudioService.instance.setVibracion(v);
                            if (!mounted) return;
                            setState(() => _vibracion = v);
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Silenciar avisos'),
                          value: _mute,
                          onChanged: (v) async {
                            await AudioService.instance.setMute(v);
                            if (!mounted) return;
                            setState(() => _mute = v);
                          },
                        ),
                        Text(
                          'Volumen',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                        Slider(
                          value: _volumen,
                          onChanged: _mute
                              ? null
                              : (v) async {
                                  setState(() => _volumen = v);
                                  await AudioService.instance.setVolumen(v);
                                },
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await AudioService.instance.init();
                              await AudioService.instance.probarSenalFuego();
                            },
                            icon: const Icon(Icons.volume_up),
                            label: const Text('Probar pitido'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
