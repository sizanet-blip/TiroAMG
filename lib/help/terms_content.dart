import 'help_content.dart';

/// Condiciones de uso y limitación de responsabilidad (texto en la app).
abstract final class TermsContent {
  static const String version = '1.0';
  static const String responsable = 'Alberto Maestre Gutiérrez';
  static const String emailContacto = 'info@albertomaestre.es';
  static const String web =
      'https://www.albertomaestre.es/pagina/condiciones-de-uso';
  static const String appName = 'TiroAMG';

  static const String resumenCorto =
      '$appName se ofrece “tal cual”, sin garantía de ausencia de errores. '
      'Úsala bajo tu responsabilidad. El titular no responde de fallos, '
      'pérdida de datos ni resultados incorrectos (incluida la detección automática).';

  static const HelpDoc documento = HelpDoc(
    id: 'condiciones-uso',
    title: 'Condiciones de uso',
    subtitle: 'Limitación de responsabilidad y uso bajo tu cargo',
    sections: [
      HelpDocSection(
        title: '1. Aceptación',
        paragraphs: [
          'Al usar $appName aceptas estas condiciones. Si no estás de acuerdo, no utilices la aplicación.',
          'Titular: $responsable (persona física). Contacto: $emailContacto',
          'Texto completo también en: $web',
        ],
      ),
      HelpDocSection(
        title: '2. Naturaleza del servicio',
        paragraphs: [
          '$appName es una herramienta de apoyo al tiro deportivo. El uso básico se ofrece sin cobro al usuario final.',
          'No sustituye las normas de seguridad del polígono, del arma, de la federación ni el criterio del tirador.',
        ],
      ),
      HelpDocSection(
        title: '3. Uso bajo tu responsabilidad',
        paragraphs: [
          'Utilizas la app bajo tu exclusiva responsabilidad. Debes revisar cualquier resultado (puntuaciones, detección, estadísticas, exportaciones) antes de darlo por válido.',
        ],
      ),
      HelpDocSection(
        title: '4. Software “tal cual”',
        paragraphs: [
          'El software se facilita “tal cual” y “según disponibilidad”, sin garantía de ausencia de errores, disponibilidad continua, exactitud o idoneidad para un fin concreto.',
        ],
      ),
      HelpDocSection(
        title: '5. Limitación de responsabilidad',
        paragraphs: [
          'En la máxima medida permitida por la ley, $responsable no se hace responsable de:',
        ],
        bullets: [
          'Fallos, errores, interrupciones o indisponibilidad de la app o de sus APIs.',
          'Pérdida o corrupción de datos (historial, fotos, backups, configuración).',
          'Resultados incorrectos o incompletos, incluida la detección automática de impactos.',
          'Daños derivados del uso o de la imposibilidad de uso.',
          'Fallos de terceros (red, dispositivo, sistema operativo, hosting).',
        ],
      ),
      HelpDocSection(
        title: '6. Servicio gratuito',
        paragraphs: [
          'Si, pese a lo anterior, resultara alguna responsabilidad legalmente ineludible y el servicio es gratuito para ti, esa responsabilidad quedará limitada, en la medida permitida por la ley, a cero euros (0 €).',
          'Nada aquí excluye responsabilidad cuando la ley lo prohíba (p. ej. dolo o negligencia grave en los términos que no se puedan limitar).',
        ],
      ),
      HelpDocSection(
        title: '7. Detección automática',
        paragraphs: [
          'La detección de impactos puede fallar por luz, ángulo, calidad de imagen u otros factores. Revisa siempre el resultado antes de usarlo.',
        ],
      ),
      HelpDocSection(
        title: '8. Cambios',
        paragraphs: [
          'Estas condiciones pueden actualizarse. Versión en la app: $version. El uso continuado tras cambios relevantes implica su aceptación, salvo que la ley exija otra cosa.',
        ],
      ),
    ],
  );
}
