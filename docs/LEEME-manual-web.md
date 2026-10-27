# Manual web (CMS)

## 1. Sube las imágenes
Copia todos los PNG de `assets/help/` a la carpeta del panel:

`/uploads/cms/`

(en el servidor: `https://panel.albertomaestre.es/uploads/cms/`)

**Misma nombre de archivo** (ej. `21_estadisticas.png`).

Lista:

- `01_home.png` ← incluye Cerrar sesión
- `02_configuracion.png` ← incluye entrada Cuenta AMG
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
- `25_tiroamg_login.png` ← acceso (logo, entrar, crear cuenta, código)
- `26_tiroamg_registro.png`
- `27_tiroamg_privacidad.png`
- `28_tiroamg_condiciones.png`
- `29_tiroamg_recuperar.png`
- `30_cuenta_amg.png` ← Configuración → Cuenta AMG
- `31_acceso_pendiente.png` ← solicitud pendiente + comprobar

## 2. Pega el HTML
Abre `docs/manual-web-cms.html`, selecciona todo, copia y pégalo en el campo **contenido** del CMS (modo código/HTML si existe).

## 3. Guarda y revisa la web del programa

## App
En la app el manual de texto está en `lib/help/help_content.dart` (guía, manual completo y FAQ, sin imágenes). Las capturas son solo para la web.

### Novedades documentadas
- Cabecera con wordmark TiroAMG en las capturas
- Cuenta AMG: login, registro, pendiente con auto-comprobación, recuperación
- Entrar con huella; «Ahora no» no vuelve a preguntar
- Identificación al abrir; sin internet vale 14 días tras un acceso con red (también después de cerrar sesión)
- Inicio: botón Cerrar sesión con confirmación
- Configuración → Cuenta AMG (usuario, huella, contraseña, cerrar sesión)
- Privacidad 1.3: verificador local de la contraseña y almacén seguro si hay huella
- Condiciones de tiro plegadas; Objetivo Entrenar / Corregir miras
- Impactos de referencia (azul); capas; pregunta al cambiar de fase
- Selección múltiple de entrenamientos; acta oficial del árbitro
