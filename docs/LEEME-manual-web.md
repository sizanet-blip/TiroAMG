# Manual web (CMS)

## 1. Sube las imágenes
Copia todos los PNG de `assets/help/` a la carpeta del panel:

`/uploads/cms/`

(en el servidor: `https://panel.albertomaestre.es/uploads/cms/`)

**Misma nombre de archivo** (ej. `21_estadisticas.png`).

Lista:

- `01_home.png`
- `02_configuracion.png`
- `03_estado_app.png`
- `04_ayuda.png`
- `08_entrenamiento.png` ← Objetivo Entrenar / Corregir miras
- `09_historial.png` ← aviso de selección múltiple
- `10_backup.png`
- `11_avisos.png`
- `12_perfil.png`
- `13_gestion_armas.png`
- `14_gestion_municion.png`
- `15_tiempos_series.png`
- `16_catalogo_tipos.png`
- `17_catalogo_calibres.png`
- `18_catalogo_dianas.png`
- `19_competicion.png`
- `20_competicion_detalle.png`
- `21_estadisticas.png`
- `22_sesion_detalle.png`
- `23_referencia_impactos.png` ← impactos azules (referencia) + rojos
- `24_acta_oficial.png` ← acta / desglose oficial

## 2. Pega el HTML
Abre `docs/manual-web-cms.html`, selecciona todo, copia y pégalo en el campo **contenido** del CMS (modo código/HTML si existe).

## 3. Guarda y revisa la web del programa

## App
En la app el manual de texto está en `lib/help/help_content.dart` (guía, manual completo y FAQ, sin imágenes). Las capturas son solo para la web.

### Novedades documentadas
- Cabecera con wordmark TiroAMG en las capturas
- Condiciones de tiro plegadas hasta que se pulsa el título (entrenamiento y competición)
- Objetivo Entrenar / Corregir miras
- Impactos de referencia (azul) en entrenamiento y competición; capas; pregunta al cambiar de fase
- Selección múltiple de entrenamientos para estadísticas
- Acta oficial del árbitro (total, desglose, series, tiros)
