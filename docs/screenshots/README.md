# Imágenes para el manual de usuario

Este directorio recibe las **capturas PNG** cuando ejecutas el flujo con **`flutter drive`** y el driver `test_driver/integration_test.dart`. Ver **`docs/PASOS_CAPTURAS.md`**.

## Cómo rellenar esta carpeta

1. Desde la raíz del proyecto:

   ```bash
   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshot_flow_test.dart -d emulator-5554 --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo
   ```

2. Los archivos se crean aquí con nombres como `01_home_panel_control.png`, `02_entrenamiento.png`, … hasta `17_analisis_entrenamientos.png` (incluye subpantallas de Configuración `10_`…`16_`).

3. Abre **`docs/manual_usuario.html`** en el navegador para verlas en contexto.

También puedes generar variantes **horizontal** (`*_landscape.png`) con el test de solo landscape (ver `integration_test/README_screenshots.md`).

Si falta un archivo, el manual puede mostrar un icono roto; el texto sigue siendo válido.
