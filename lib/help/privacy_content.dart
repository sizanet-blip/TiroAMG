import 'help_content.dart';

/// Política de privacidad de TiroAMG (texto en la app).
/// Borrador orientativo — no sustituye asesoramiento legal.
abstract final class PrivacyContent {
  static const String version = '1.0';
  static const String responsable = 'Alberto Maestre Gutiérrez';
  static const String emailContacto = 'info@albertomaestre.es';
  static const String web = 'https://www.albertomaestre.es/';
  static const String appName = 'TiroAMG';

  static const HelpDoc documento = HelpDoc(
    id: 'privacidad',
    title: 'Política de privacidad',
    subtitle: 'Información sobre el tratamiento de datos personales (RGPD / LOPDGDD)',
    sections: [
      HelpDocSection(
        title: '1. Responsable del tratamiento',
        paragraphs: [
          'El responsable del tratamiento de los datos personales es $responsable, persona física, en relación con la aplicación $appName.',
          'Contacto para ejercer derechos o consultas sobre privacidad: $emailContacto',
          'Sitio web: $web',
        ],
      ),
      HelpDocSection(
        title: '2. Ámbito y destinatarios',
        paragraphs: [
          '$appName es una aplicación de apoyo al tiro deportivo (entrenamientos, competiciones, historial y gestión asociada).',
          'El servicio se ofrece sin contraprestación económica por parte del responsable en el sentido de cobro al usuario final por el uso básico descrito.',
          'La aplicación está dirigida exclusivamente a personas adultas (mayores de 18 años). No está pensada para menores de edad.',
        ],
      ),
      HelpDocSection(
        title: '3. Datos que se tratan',
        paragraphs: [
          'Según el uso que hagas de la app y del registro de la instalación, pueden tratarse:',
        ],
        bullets: [
          'Email de contacto asociado a la instalación.',
          'Identificador técnico del dispositivo (device ID) y datos de plataforma (Android, Windows, etc.).',
          'Versión de la aplicación y número de build.',
          'Datos de perfil que introduzcas (nombre, licencia federativa, club, categoría, etc.).',
          'Datos de uso deportivo guardados en el dispositivo (sesiones, puntuaciones, impactos, material, munición, condiciones, etc.).',
          'Copias de seguridad que generes o restaures (archivo local que tú controlas al exportar/importar).',
          'Registros técnicos necesarios para licencia, validación y soporte (p. ej. estado de módulos, fechas de sincronización).',
        ],
      ),
      HelpDocSection(
        title: '4. Finalidades',
        bullets: [
          'Identificar y registrar la instalación para licencia, módulos y soporte.',
          'Prestar las funciones de la app (entrenamiento, competición, historial, avisos, etc.).',
          'Generar informes o exportaciones que tú solicites.',
          'Mantener la seguridad, integridad y actualización del servicio.',
          'Atender solicitudes y comunicaciones relacionadas con el uso de $appName.',
        ],
      ),
      HelpDocSection(
        title: '5. Base jurídica',
        paragraphs: [
          'El tratamiento se basa, según el caso, en:',
        ],
        bullets: [
          'Ejecución de la relación de uso / medidas precontractuales o contractuales asociadas al registro y prestación del servicio (art. 6.1.b RGPD), cuando aportas email y datos necesarios para identificar la instalación.',
          'Interés legítimo (art. 6.1.f RGPD) en la seguridad técnica, prevención de abusos y mejora del servicio, ponderado frente a tus derechos.',
          'Consentimiento (art. 6.1.a RGPD) cuando marcas expresamente la aceptación de esta política al registrar la instalación.',
          'Cumplimiento de obligaciones legales cuando proceda.',
        ],
      ),
      HelpDocSection(
        title: '6. Conservación',
        paragraphs: [
          'Los datos en el dispositivo permanecen mientras uses la app o hasta que los borres (desinstalación, borrado de datos o restauración).',
          'Los datos asociados al registro en servidor se conservan mientras la instalación esté activa o sea necesario para licencia, soporte y seguridad, y después durante los plazos legales aplicables.',
          'Si solicitas la eliminación, se atenderá salvo obligaciones de conservación o motivos legítimos de bloqueo.',
        ],
      ),
      HelpDocSection(
        title: '7. Destinatarios y encargados',
        paragraphs: [
          'No se venden datos personales a terceros con fines comerciales.',
          'Pueden acceder a los datos proveedores que prestan alojamiento o infraestructura del panel/servidor de licencias, actuando como encargados del tratamiento cuando corresponda, con servidores situados en la Unión Europea.',
          'También pueden conocerse datos las autoridades competentes cuando exista obligación legal.',
        ],
      ),
      HelpDocSection(
        title: '8. Transferencias internacionales',
        paragraphs: [
          'El tratamiento previsto se realiza con infraestructura en la Unión Europea. No está previsto transferir tus datos fuera del EEE de forma habitual. Si en el futuro fuera necesario, se informarían las garantías adecuadas.',
        ],
      ),
      HelpDocSection(
        title: '9. Derechos',
        paragraphs: [
          'Puedes ejercer acceso, rectificación, supresión, oposición, limitación y, cuando proceda, portabilidad, así como retirar el consentimiento sin afectar a la licitud del tratamiento previo.',
          'Para ejercerlos, escribe a $emailContacto indicando el derecho solicitado y datos que permitan identificar la instalación (email registrado / device si lo conoces).',
          'También puedes reclamar ante la Agencia Española de Protección de Datos (AEPD): www.aepd.es',
        ],
      ),
      HelpDocSection(
        title: '10. Seguridad',
        paragraphs: [
          'Se aplican medidas técnicas y organizativas razonables (comunicaciones cifradas hacia el servidor cuando se usa HTTPS, control de acceso al panel, minimización de datos). Ningún sistema es 100 % seguro; te recomendamos proteger el dispositivo y las copias de seguridad exportadas.',
        ],
      ),
      HelpDocSection(
        title: '11. Menores',
        paragraphs: [
          '$appName está dirigida solo a adultos. No se solicita ni se autoriza el registro de menores de 18 años.',
        ],
      ),
      HelpDocSection(
        title: '12. Cambios',
        paragraphs: [
          'Esta política puede actualizarse. La versión actual en la app es $version. Si hay cambios relevantes, se procurará informarte en la propia aplicación o en $web.',
        ],
      ),
    ],
  );
}
