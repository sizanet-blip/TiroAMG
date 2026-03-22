# Documentación en la web (HTML)

| Archivo | Contenido |
|---------|-----------|
| [`presentacion_web.html`](presentacion_web.html) | Descripción de **funcionalidades** del producto (orientación marketing / resumen). |
| [`manual_usuario.html`](manual_usuario.html) | **Manual de usuario**: guía detallada en lenguaje sencillo, con huecos para **capturas** (`docs/screenshots/`). |

## Imágenes del manual

1. Ejecuta **`flutter drive`** con el driver (ver [`PASOS_CAPTURAS.md`](PASOS_CAPTURAS.md) y `integration_test/README_screenshots.md`). Usa **`--dart-define=E2E_PLAN=completo`** para generar todas las capturas sin bloqueos. Los PNG se guardan en [`screenshots/`](screenshots/) solos.
2. Abre `manual_usuario.html` en el navegador. La sección **Planes de licencia** explica qué incluye **Entrenamiento**, **Competición**, **Competición Plus** y **Completo**.

Lista de nombres útiles (vertical):

- `01_home_panel_control.png` … `09_configuracion.png` (panel hasta pantalla principal de configuración)
- Opciones dentro de **Configuración**: `10_mis_datos_perfil`, `11_mis_armas`, `12_mis_municiones`, `13_plantillas_tiempos`, `14_catalogo_tipos_arma`, `15_catalogo_calibres`, `16_catalogo_dianas`
- **Estadísticas** (desde historial): `17_analisis_entrenamientos.png`
- Flujos intermedios: `03_sesion_disparo_entrenamiento`, `05_detalle_tirada`, `07_competicion_setup`, `07a_competicion_runner`, `07b_competicion_serie`, `07c_competicion_resultados_finales`
- Si la licencia bloquea algo: `08_backup_bloqueado`, `09_configuracion_bloqueado`, y `*_bloqueado` en submenús de configuración cuando aplique

Opcional (tablet): mismos nombres con sufijo `_landscape`.
