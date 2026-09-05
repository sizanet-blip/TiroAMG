import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

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
    if (_cargando) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Avisos de tiro')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return AppPageScaffold(
      title: 'Avisos de tiro',
      body: AppSectionCard(
        title: 'Perfil de avisos',
        titleIcon: Icons.campaign_outlined,
        titleIconColor: AppColors.accentAnalytics,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Competición = pitidos. Entrenamiento = pitidos + voz.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.subtitleSoft,
              ),
            ),
            const SizedBox(height: 12),
            _buildPerfilSelector(),
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
                color: AppColors.primary,
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
    );
  }

  Widget _buildPerfilSelector() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _perfilOpcion(
                value: AvisoTiroPerfil.competicion,
                label: 'Competición',
                icon: Icons.sports_score,
                isFirst: true,
              ),
            ),
            Container(width: 1, color: AppColors.border),
            Expanded(
              child: _perfilOpcion(
                value: AvisoTiroPerfil.entrenamiento,
                label: 'Entrenamiento',
                icon: Icons.record_voice_over,
                isFirst: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _perfilOpcion({
    required AvisoTiroPerfil value,
    required String label,
    required IconData icon,
    required bool isFirst,
  }) {
    final selected = _perfil == value;
    final color = selected ? AppColors.primary : AppColors.subtitle;

    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.horizontal(
        left: isFirst ? const Radius.circular(11) : Radius.zero,
        right: isFirst ? Radius.zero : const Radius.circular(11),
      ),
      child: InkWell(
        onTap: () async {
          await AudioService.instance.setPerfil(value);
          if (!mounted) return;
          setState(() => _perfil = value);
        },
        borderRadius: BorderRadius.horizontal(
          left: isFirst ? const Radius.circular(11) : Radius.zero,
          right: isFirst ? Radius.zero : const Radius.circular(11),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
