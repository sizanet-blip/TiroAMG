/// Contenido de ayuda de TiroAMG (guía, manual y FAQ).
/// Las capturas para la web viven en docs/manual-web-cms.html + assets/help/.

class HelpDocSection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const HelpDocSection({
    required this.title,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}

class HelpDoc {
  final String id;
  final String title;
  final String subtitle;
  final List<HelpDocSection> sections;

  const HelpDoc({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.sections,
  });
}

class HelpFaqItem {
  final String question;
  final String answer;

  const HelpFaqItem({required this.question, required this.answer});
}

abstract final class HelpContent {
  static const String supportEmail = 'info@albertomaestre.es';

  static const HelpDoc guiaRapida = HelpDoc(
    id: 'guia',
    title: 'Guía rápida de uso',
    subtitle: 'Lo esencial para empezar en pocos minutos',
    sections: [
      HelpDocSection(
        title: '1. Qué es TiroAMG',
        paragraphs: [
          'TiroAMG es una app para el tirador deportivo: preparas la sesión, ejecutas series con avisos de tiempo, anotas impactos o puntos, y consultas el historial y las estadísticas.',
          'Algunas opciones (competición, historial avanzado, backup, detección de diana) dependen de los módulos de tu licencia. Si no las ves, revisa Estado de la aplicación.',
        ],
      ),
      HelpDocSection(
        title: '2. Primeros pasos (obligatorio)',
        bullets: [
          'Abre Configuración → Mis Datos y completa tu perfil.',
          'Configuración → Gestión de Armas: crea al menos un arma.',
          'Configuración → Tiempos y series: crea una plantilla (Precisión, Duelo, Aire 10m…).',
          'Opcional: Gestiona munición para llevar stock por lote.',
          'Opcional: Ajusta Avisos de tiro (volumen, perfil, vibración).',
        ],
      ),
      HelpDocSection(
        title: '3. Tu primer entrenamiento',
        bullets: [
          'Menú → Entrenamiento.',
          'Elige arma, plantilla (disciplina) y munición si quieres.',
          'Objetivo: Entrenar (sesión normal) o Corregir miras (el análisis sugerirá clics).',
          'Decide si marcas en diana o «Puntuar por números» (teclado X / 10…0).',
          'Rellena condiciones (lugar, distancia, interior…) si te interesa el histórico.',
          'Pulsa Iniciar y sigue Atención / Fuego / Alto.',
          'Al guardar puedes seguir con referencia (impactos azules) o diana limpia.',
          'Revisa la sesión en Historial.',
        ],
      ),
      HelpDocSection(
        title: '4. Menú principal',
        bullets: [
          'Competición: modalidades y fases oficiales (módulo).',
          'Entrenamiento: series, tiempos y puntuación.',
          'Historial y Análisis: sesiones, estadísticas e informes (módulo).',
          'Copia de Seguridad: exportar / importar datos (módulo).',
          'Configuración: equipos, plantillas, catálogos, avisos, estado.',
          'Ayuda: guía, manual y FAQ.',
          'Recorte Diana: análisis fotográfico (módulo de detección).',
        ],
      ),
      HelpDocSection(
        title: '5. Consejos express',
        bullets: [
          'Competición = pitidos; Entrenamiento = pitidos + voz.',
          'En diana: impactos azules = series anteriores (referencia); rojos = serie actual.',
          'En Historial, mantén pulsado para seleccionar varios entrenamientos y analizarlos juntos.',
          'Haz copias de seguridad con frecuencia.',
          'Identifica la instalación con tu email en Estado de la aplicación.',
          'Si falta un módulo, escribe a $supportEmail con tu device / email.',
        ],
      ),
    ],
  );

  static const HelpDoc manualCompleto = HelpDoc(
    id: 'manual',
    title: 'Manual completo',
    subtitle: 'Referencia detallada para el día a día',
    sections: [
      HelpDocSection(
        title: '1. Introducción y licencia',
        paragraphs: [
          'TiroAMG combina configuración de material, control de tiempos, puntuación y análisis. La instalación se valida contra el servidor de licencias cuando hay red.',
          'Módulos típicos: Inicio (base), Competición, Análisis/Historial, Backup, Detección de diana, catálogos avanzados. Sin módulo, la opción no aparece o muestra aviso de bloqueo.',
          'En Configuración → Estado de la aplicación ves: activa/bloqueada, módulos, email, última sync, device, versión de app y de base de datos, y el botón de buscar actualizaciones.',
        ],
        bullets: [
          'Identificar (email): asocia el dispositivo a tu cuenta para soporte y módulos.',
          'Refrescar: vuelve a consultar el servidor.',
          'Buscar actualizaciones: comprueba versión remota y abre la descarga si hay una nueva.',
        ],
      ),
      HelpDocSection(
        title: '2. Menú principal',
        paragraphs: [
          'La home muestra el logo TiroAMG y accesos directos. El orden y la presencia de filas dependen de tu licencia.',
        ],
        bullets: [
          'Competición — modalidades, fases y ejecución oficial.',
          'Entrenamiento — siempre disponible con el módulo base.',
          'Historial y Análisis — listados, filtros, estadísticas e informes.',
          'Copia de Seguridad — exportar e importar la BD.',
          'Configuración — todo el material y preferencias.',
          'Ayuda — documentación y contacto.',
          'Recorte Diana — foto → impactos (si tienes detección).',
        ],
      ),
      HelpDocSection(
        title: '3. Perfil del tirador',
        paragraphs: [
          'Configuración → Mis Datos (Perfil). Guarda nombre, licencia federativa, club y contacto.',
          'Esos datos se usan en informes y ayudan a identificar la instalación junto con el email de licencia.',
        ],
      ),
      HelpDocSection(
        title: '4. Armas (equipos)',
        paragraphs: [
          'Configuración → Gestión de Armas. Cada arma tiene nombre, tipo, calibre y, si aplica, diámetro de impacto estimado para dibujar los tiros en la diana.',
        ],
        bullets: [
          'Crea un perfil por cada arma que uses a menudo.',
          'Tipo y calibre salen de los catálogos del sistema.',
          'El tamaño visual del impacto en sesión depende del calibre / diámetro configurado.',
          'Puedes editar o borrar armas desde la lista (confirmar borrado).',
        ],
      ),
      HelpDocSection(
        title: '5. Munición',
        paragraphs: [
          'Configuración → Gestión de Munición. Registra marca, lote y stock. Puedes anotar compras, usos manuales y ver en qué sesiones se empleó cada lote.',
        ],
        bullets: [
          'Asocia munición a la sesión de entrenamiento o competición cuando quieras trazabilidad.',
          '«Sin especificar» es válido si no quieres controlar stock.',
        ],
      ),
      HelpDocSection(
        title: '6. Plantillas de tiempos y series',
        paragraphs: [
          'Configuración → Tiempos y series. Una plantilla define la disciplina: tiempos de preparación, atención, fuego, alto, disparos por serie, etc.',
        ],
        bullets: [
          'Ejemplos: precisión, duelo (tiempos cortos), aire 10 m, estándar.',
          'Sin al menos una plantilla no podrás iniciar un entrenamiento.',
          'Edita o duplica plantillas según la normativa de tu club o federación.',
        ],
      ),
      HelpDocSection(
        title: '7. Catálogos (tipos, calibres, dianas)',
        paragraphs: [
          'Configuración → Catálogos. Datos maestros del sistema. Suele requerir módulo de catálogos en la licencia.',
        ],
        bullets: [
          'Tipos de arma: categorías (pistola, rifle, aire…).',
          'Calibres: incluye no estándar si los usas.',
          'Dianas: anillos, zona negra, mosca (X). La diana elegida afecta al dibujo y a la puntuación en diana.',
        ],
      ),
      HelpDocSection(
        title: '8. Avisos de tiro',
        paragraphs: [
          'Configuración → Avisos de tiro. Controla cómo te avisa la app durante la serie.',
        ],
        bullets: [
          'Perfil Competición: solo pitidos (adecuado a entorno de match).',
          'Perfil Entrenamiento: pitidos + voz (Atención, Fuego, Alto…).',
          'Perfil automático: sugiere el perfil al iniciar; si lo cambias a mano, se respeta hasta que reactives la opción.',
          'Volumen, vibración y silenciar avisos.',
          '«Probar pitido» para comprobar el dispositivo.',
        ],
      ),
      HelpDocSection(
        title: '9. Entrenamiento — configuración',
        paragraphs: [
          'Menú → Entrenamiento. Pantalla «Configurar sesión».',
        ],
        bullets: [
          'Arma y reglas/disciplina (plantilla) son esenciales.',
          'Objetivo de la sesión: Entrenar (uso normal) o Corregir miras (el análisis se centra en sugerir clics; no muestra el diagnóstico técnico habitual).',
          'Munición opcional.',
          'Puntuar tocando diana vs puntuar por números (switch).',
          'Condiciones: lugar, distancia, interior/exterior, posición, iluminación, y si quieres temperatura, humedad, viento, etc.',
          'Al iniciar se abre la sesión de tiro con los avisos de la plantilla.',
        ],
      ),
      HelpDocSection(
        title: '10. Entrenamiento — durante la sesión',
        paragraphs: [
          'La sesión guía las fases (preparación, atención, fuego, alto) con sonido y, en perfil entrenamiento, voz.',
        ],
        bullets: [
          'Serie: respeta el límite de disparos; al completar avisa (snackbar / voz).',
          'Libre: sin tope de serie.',
          'En diana: marca solo en Fuego (o pausa, según reglas de la pantalla).',
          'Por números: panel X y 10…0; mismo criterio de fase y límite.',
          'Lupa / inspección: zoom y pan para revisar; no marca tiros.',
          'Al guardar: «Seguir con referencia» deja en azul los impactos anteriores (no puntúan); «Diana limpia» borra la referencia; o vuelve al menú.',
          'La referencia sirve para contrastar con el papel (telescopio): azul = ya marcados; rojo = serie actual. Solo aplica si puntuaste tocando la diana.',
          'Si acumulas varias series con referencia, la última queda más marcada y las anteriores más suaves.',
          'En landscape la diana queda a un lado y los controles al otro.',
        ],
      ),
      HelpDocSection(
        title: '11. Competición',
        paragraphs: [
          'Menú → Competición (módulo). Gestionas modalidades con fases (número de series, orden).',
        ],
        bullets: [
          'Crea o edita modalidades y sus fases.',
          'Setup: arma, munición, modo de puntuación (diana o números).',
          'Runner: ejecuta fase a fase; al completar avanza según la definición.',
          'Entre series puedes mantener impactos de referencia (azules) si sigues en el mismo papel; hay interruptor y botón para limpiar.',
          'Al cambiar de fase, si hay referencia, la app pregunta: mismo papel (mantener) o papel nuevo (limpiar).',
          'Los resultados quedan en Historial → pestaña Competiciones.',
          'En el detalle del torneo puedes introducir el acta oficial del árbitro (total, desglose tipo 3-X, 2-10, 6-8, series o tiros) y comparar con lo marcado en la app.',
        ],
      ),
      HelpDocSection(
        title: '12. Historial',
        paragraphs: [
          'Menú → Historial y Análisis. Pestañas Entrenamientos / Competiciones, filtros por fecha (hoy, mes, año, rango…).',
        ],
        bullets: [
          'Cada fila resume fecha, disciplina/arma y puntuación o dato clave.',
          'Al entrar ves el detalle: puntos, impactos, entorno, notas.',
          'Entrenamientos: mantén pulsado para seleccionar varios y analizarlos juntos (botón Analizar).',
          'Icono de estadísticas en la barra: abre el análisis del modo actual (entreno o compe).',
        ],
      ),
      HelpDocSection(
        title: '13. Estadísticas e informes',
        paragraphs: [
          'Desde Historial → icono de gráficas, o tras seleccionar entrenamientos. Filtra por periodo y compara medias, evolución y tendencias.',
          'Si la sesión era «Corregir miras», el análisis prioriza la sugerencia de clics.',
          'Según módulos, puedes generar informes PDF o exportar a Excel para archivo o club.',
        ],
      ),
      HelpDocSection(
        title: '14. Copia de seguridad',
        paragraphs: [
          'Menú → Copia de Seguridad. Exporta la base de datos a un archivo (guárdalo en Drive, correo, etc.). Importar restaura esa copia y sustituye los datos locales.',
        ],
        bullets: [
          'Exporta antes de un cambio grande o de importar otra copia.',
          'En builds de desarrollo puede haber zona de pruebas (datos de prueba); no la uses en producción real.',
        ],
      ),
      HelpDocSection(
        title: '15. Recorte / detección de diana',
        paragraphs: [
          'Si tu licencia incluye detección: tomas o eliges una foto de diana, recortas/ajustas y la app intenta localizar impactos.',
          'Es un flujo avanzado: buena iluminación, diana completa en el encuadre y parámetros de umbral ayudan. Si falla, revisa FAQ o contacta soporte.',
        ],
      ),
      HelpDocSection(
        title: '16. Actualizaciones y soporte',
        paragraphs: [
          'Estado de la aplicación → Buscar actualizaciones. Si hay versión nueva, puedes abrir el enlace de descarga del servidor.',
          'Soporte: $supportEmail. Indica versión de app, módulos, email de instalación y, si puedes, capturas.',
        ],
      ),
    ],
  );

  static const List<HelpFaqItem> faq = [
    HelpFaqItem(
      question: '¿Por qué no puedo iniciar un entrenamiento?',
      answer:
          'Necesitas al menos un arma y una plantilla de tiempos en Configuración. Si faltan, la pantalla de entrenamiento te lo indica.',
    ),
    HelpFaqItem(
      question: '¿Qué diferencia hay entre puntuar en diana y por números?',
      answer:
          'En diana marcas el impacto tocando la zona. Con «Puntuar por números» usas X y 10…0. Ambos respetan la fase Fuego y el límite de serie. La referencia de impactos anteriores solo tiene sentido al marcar en diana.',
    ),
    HelpFaqItem(
      question: '¿Qué es Entrenar vs Corregir miras?',
      answer:
          'Entrenar es una sesión normal. Corregir miras marca la sesión para que el análisis sugiera clics de mira y no muestre el diagnóstico técnico habitual.',
    ),
    HelpFaqItem(
      question: '¿Qué son los impactos azules (referencia)?',
      answer:
          'Al guardar un entrenamiento (o entre series de competición) puedes mantener los impactos previos en azul. No puntúan: sirven para ver en la app lo que ya hay en el papel (telescopio). Rojo = serie actual. La última serie de referencia se ve más marcada; las anteriores, más suaves.',
    ),
    HelpFaqItem(
      question: 'En competición, ¿se mantienen los impactos al cambiar de fase?',
      answer:
          'Si hay referencia, al pasar de fase la app pregunta: mismo papel (mantener) o papel nuevo (limpiar). Entre series de la misma fase puedes usar el interruptor «Mantener impactos de referencia».',
    ),
    HelpFaqItem(
      question: 'No oigo los avisos o la voz',
      answer:
          'Revisa Avisos de tiro: volumen, silenciar y perfil. Competición = pitidos; Entrenamiento = pitidos + voz. Comprueba también el silencio del móvil.',
    ),
    HelpFaqItem(
      question: '¿Qué es el perfil automático de avisos?',
      answer:
          'Al iniciar una serie puede sugerir Competición o Entrenamiento. Si lo cambias a mano, se mantiene hasta que reactives «Perfil automático».',
    ),
    HelpFaqItem(
      question: 'No veo Competición, Historial o Backup',
      answer:
          'Dependen de los módulos de tu licencia. Mira Estado de la aplicación → Módulos. Si falta alguno, escribe a $supportEmail.',
    ),
    HelpFaqItem(
      question: '¿Cómo restauro una copia de seguridad?',
      answer:
          'Copia de Seguridad → Importar → elige el archivo exportado. Sustituye los datos actuales. Exporta antes si quieres conservar lo de ahora.',
    ),
    HelpFaqItem(
      question: 'Los impactos en la diana se ven demasiado grandes o pequeños',
      answer:
          'Revisa calibre y diámetro de impacto del arma en Gestión de Armas. El tamaño es el mismo en tirada, historial y análisis.',
    ),
    HelpFaqItem(
      question: '¿Puedo editar una sesión después de guardarla?',
      answer:
          'Desde Historial abres el detalle. Lo que se pueda editar depende del tipo de sesión y de la pantalla de detalle.',
    ),
    HelpFaqItem(
      question: '¿Cómo analizo varios entrenamientos a la vez?',
      answer:
          'En Historial → Entrenamientos, mantén pulsado una sesión para entrar en modo selección, marca las que quieras y pulsa Analizar. Las estadísticas usarán solo esa selección.',
    ),
    HelpFaqItem(
      question: '¿Qué es el acta oficial en competición?',
      answer:
          'En el detalle del torneo puedes introducir lo que dio el árbitro: total, desglose (p. ej. 3-X, 2-10, 6-8), totales por serie o tiro a tiro. La app compara con tu marcado y muestra diferencias.',
    ),
    HelpFaqItem(
      question: 'La lupa / inspección no me deja marcar tiros',
      answer:
          'Es normal: solo sirve para ampliar y mover la vista. Desactívala para volver a puntuar.',
    ),
    HelpFaqItem(
      question: '¿Cómo identifico mi instalación?',
      answer:
          'Al abrir la app debes aceptar la política de privacidad y las condiciones de uso (obligatorio). El email es opcional; puedes añadirlo luego en Configuración → Estado de la aplicación → Identificar (email).',
    ),
    HelpFaqItem(
      question: '¿El desarrollador responde si la app falla?',
      answer:
          'TiroAMG se ofrece “tal cual”, sin garantía de ausencia de errores. Úsala bajo tu responsabilidad. Revisa Condiciones de uso en Ayuda. La detección automática puede fallar: verifica siempre los resultados.',
    ),
    HelpFaqItem(
      question: '¿Qué es una plantilla de tiempos?',
      answer:
          'Define la disciplina: cuánto dura Atención/Fuego/Alto y cuántos disparos hay por serie. Sin plantilla no hay entrenamiento.',
    ),
    HelpFaqItem(
      question: '¿Serie o libre?',
      answer:
          'Serie limita disparos según la plantilla. Libre no impone ese tope (sigue habiendo avisos de tiempo según plantilla).',
    ),
    HelpFaqItem(
      question: 'La detección de diana no encuentra impactos',
      answer:
          'Mejora luz y contraste, encuadra la diana completa, revisa umbrales/recorte. Si sigue fallando, contacta soporte con una foto de ejemplo.',
    ),
    HelpFaqItem(
      question: '¿Dónde pido ayuda personalizada?',
      answer:
          'Escribe a $supportEmail con versión de app, módulos, email de instalación y capturas si puedes.',
    ),
  ];
}
