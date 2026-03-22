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

Para que los **PNG se guarden en `docs/screenshots/`** hace falta **`flutter drive`** con el driver (Flutter 3.x):

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshot_flow_test.dart -d <deviceId> --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo
```

Ejemplo:

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshot_flow_test.dart -d emulator-5554 --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo
```

Solo comprobar el flujo **sin** escribir PNG en disco:

```bash
flutter test integration_test/screenshot_flow_test.dart -d emulator-5554 --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo
```

Solo **vertical** (sin `_landscape`), añade: `--dart-define=E2E_PORTRAIT_ONLY=true`

**Plan `completo`:** mantén `--dart-define=E2E_PLAN=completo` para que el flujo desbloquee **todas** las pantallas del manual (competición, backup, estadísticas, catálogos, etc.). Otros valores (`basic`, `medio`, `pro`) dejan secciones bloqueadas o generan capturas `_bloqueado`. Qué incluye cada plan comercial en la app: sección *Planes de licencia* en `docs/manual_usuario.html`; tabla técnica `E2E_PLAN` en `docs/PASOS_CAPTURAS.md`.

Pasos detallados: `docs/PASOS_CAPTURAS.md`.

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
- Submenús de **Configuración** (manual detallado): `10_mis_datos_perfil`, `11_mis_armas`, `12_mis_municiones`, `13_plantillas_tiempos`, `14_catalogo_tipos_arma`, `15_catalogo_calibres`, `16_catalogo_dianas` (cada uno puede terminar en `_bloqueado` si la licencia no permite la opción)
- **Estadísticas** (Historial → icono de gráfico): `17_analisis_entrenamientos`

Las mismas capturas se generan tambien en horizontal con sufijo `_landscape`.

Si una seccion esta bloqueada por licencia, el test no falla: guarda captura del dialogo de bloqueo y continua.

## 4) Notas utiles

- **`E2E_PLAN=completo`** es el valor recomendado para documentación completa; alinea el test con el plan **Completo** (máximo nivel).
- En algunas plataformas de escritorio, `takeScreenshot` puede no estar soportado.
- En Android suele funcionar de forma estable para manuales de usuario.
- Si quieres mas pantallas (detalle de sesion, runner de competicion, etc.), se pueden anadir pasos extra al mismo test.
