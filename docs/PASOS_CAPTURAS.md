# Pasos para generar las capturas (Android, Flutter 3.41+)

Con el **emulador ya abierto**, sigue en orden:

## 1. Abrir terminal en la carpeta del proyecto

En PowerShell o CMD:

```text
cd C:\Users\Alberto\Documents\Proyectos\flutter\TiroAMG
```

(Ajusta la ruta si tu proyecto está en otro sitio.)

## 2. Comprobar que Flutter ve el emulador

```bash
flutter devices
```

Busca una línea tipo `sdk gphone64 ... (mobile) • emulator-5554 • android-arm64`.  
El **ID** suele ser `emulator-5554` (puede cambiar si tienes varios dispositivos).

## 3. Dependencias

```bash
flutter pub get
```

## 4. Generar las fotos y guardarlas en el PC (recomendado)

### Por qué `E2E_PLAN=completo`

Para que el manual muestre **todas** las pantallas (competición, copia de seguridad, estadísticas, catálogos, submenús de configuración…) **sin** capturas de diálogos «bloqueado por licencia», usa siempre **`--dart-define=E2E_PLAN=completo`** junto con **`DEV_PLAN_SELECTOR=true`**.

Resumen de lo que simula cada valor en el test (el servidor real puede enviar *features* que amplían tu plan):

| `E2E_PLAN` | Efecto orientativo en el flujo de capturas |
|------------|---------------------------------------------|
| `completo` | **Recomendado para el manual.** Nivel máximo en la app: todo desbloqueado para las capturas. |
| `pro` | Equivale al nivel «Competición Plus»: estadísticas, backup, catálogos; puede faltar algo exclusivo del plan Completo. |
| `medio` | Nivel «Competición»: torneos, pero sin estadísticas avanzadas ni backup ni catálogos en gran parte del manual. |
| `basic` | Nivel «Entrenamiento»: solo práctica; faltan competición y muchas opciones de configuración en las fotos. |

Los nombres que ve el usuario en **Configuración** suelen ser **Entrenamiento**, **Competición**, **Competición Plus** y **Completo**; la descripción de qué incluye cada uno está en **`manual_usuario.html`** (sección *Planes de licencia*).

Las capturas se escriben en **`docs/screenshots/`** solo si usas **`flutter drive`** con el driver `test_driver/integration_test.dart`.  
`flutter test` ejecuta el flujo pero **no** guarda los PNG en esa carpeta.

Sustituye `emulator-5554` por tu ID si es distinto:

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshot_flow_test.dart -d emulator-5554 --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo
```

**Solo vertical (móvil, sin capturas `_landscape`):** añade `--dart-define=E2E_PORTRAIT_ONLY=true`:

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshot_flow_test.dart -d emulator-5554 --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo --dart-define=E2E_PORTRAIT_ONLY=true
```

- La primera vez puede tardar (compila e instala).
- Deberías ver en consola líneas **`PNG guardado: ...\docs\screenshots\01_home_panel_control.png`** (y el resto).
- Al final: **All tests passed.**

## 5. Dónde quedan los archivos

Directamente en:

```text
docs\screenshots\
```

Con nombres como `01_home_panel_control.png`, `02_entrenamiento.png`, etc. El flujo también genera las pantallas de **cada opción de Configuración** (`10_`…`16_`) y **análisis de entrenamientos** (`17_analisis_entrenamientos.png`). Las variantes `_landscape` solo se generan si **no** usas `E2E_PORTRAIT_ONLY=true`.

**`docs/manual_usuario.html`** ya apunta a esa carpeta: abre el HTML en el navegador y deberías ver las imágenes.

## 6. Solo portrait (vertical) o todo

- **Solo vertical + PNG:** usa el comando del paso 4 con `--dart-define=E2E_PORTRAIT_ONLY=true` (ver arriba).
- **Vertical + horizontal:** el comando del paso 4 **sin** `E2E_PORTRAIT_ONLY`.
- **Solo comprobar el test sin PNG:** `flutter test ... --plain-name "Captura automatica de pantallas principales (portrait)"`.

## 7. Opcional: solo comprobar que el test pasa (sin PNG en disco)

```bash
flutter test integration_test/screenshot_flow_test.dart -d emulator-5554 --dart-define=DEV_PLAN_SELECTOR=true --dart-define=E2E_PLAN=completo
```

Verás `Captura guardada:` en el log, pero **no** se crearán los `.png` en `docs/screenshots/` sin `flutter drive`.

## 8. Si algo falla

- **No encuentra el dispositivo:** emulador encendido y `flutter devices` con el ID correcto.
- **Error de licencia / muchas pantallas «bloqueado»:** usa `DEV_PLAN_SELECTOR=true` y **`E2E_PLAN=completo`** como en el paso 4.
- **No aparecen PNG:** asegúrate de usar **`flutter drive`**, no solo `flutter test`.
