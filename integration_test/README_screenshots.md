# Capturas automaticas con integration_test

Este proyecto incluye un test de integracion para generar capturas de las pantallas principales:

- `integration_test/screenshot_flow_test.dart`
- Genera dos baterias: `portrait` y `landscape` (con sufijo `_landscape`)

## 1) Preparar entorno

1. Arranca un emulador Android o conecta un movil Android con depuracion USB.
2. Verifica dispositivos:

```bash
flutter devices
```

## 2) Ejecutar test y capturas

Recomendado (desbloquea modulos por licencia de desarrollo):

```bash
flutter test integration_test/screenshot_flow_test.dart -d <deviceId> --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo
```

Ejemplo:

```bash
flutter test integration_test/screenshot_flow_test.dart -d emulator-5554 --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo
```

## 3) Que captura el flujo

- `01_home_panel_control`
- `02_entrenamiento`
- `03_sesion_disparo_entrenamiento`
- `04_historial`
- `05_detalle_tirada` (o `05_detalle_competicion`)
- `06_competicion`
- `07_competicion_setup`
- `07a_competicion_runner`
- `07b_competicion_serie`
- `07c_competicion_resultados_finales`
- `08_backup` (o `08_backup_bloqueado`)
- `09_configuracion` (o `09_configuracion_bloqueado`)

Las mismas capturas se generan tambien en horizontal con sufijo `_landscape`.

Si una seccion esta bloqueada por licencia, el test no falla: guarda captura del dialogo de bloqueo y continua.

## 4) Notas utiles

- En algunas plataformas de escritorio, `takeScreenshot` puede no estar soportado.
- En Android suele funcionar de forma estable para manuales de usuario.
- Si quieres mas pantallas (detalle de sesion, runner de competicion, etc.), se pueden anadir pasos extra al mismo test.
