import 'help_content.dart';

/// Política de privacidad de TiroAMG (texto en la app).
/// Alineada con la política web en albertomaestre.es.
abstract final class PrivacyContent {
  static const String version = '1.3';
  static const String versionDate = '2026-10-27';
  static const String responsable = 'Alberto Maestre Gutiérrez';
  static const String emailContacto = 'info@albertomaestre.es';
  static const String web = 'https://www.albertomaestre.es/';
  static const String webPrivacidad =
      'https://www.albertomaestre.es/pagina/politica-de-privacidad';
  static const String appName = 'TiroAMG';

  /// Identificador enviado al panel al aceptar (APP_AUTH).
  static const String acceptanceVersion = '$version-$versionDate';

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
          'Versión ampliada en la web: $webPrivacidad',
        ],
      ),
      HelpDocSection(
        title: '2. Ámbito y destinatarios',
        paragraphs: [
          '$appName es una aplicación de apoyo al tiro deportivo (entrenamientos, competiciones, historial, catálogos y, si está habilitado, detección automática de impactos).',
          'El uso básico se ofrece sin cobro al usuario final. Algunas funciones avanzadas se gestionan como módulos activables por el responsable (por ejemplo, detección automática), no mediante compra dentro de la app.',
          'La aplicación está dirigida exclusivamente a personas adultas (mayores de 18 años). No está pensada para menores de edad.',
        ],
      ),
      HelpDocSection(
        title: '3. Qué se envía al servidor',
        paragraphs: [
          'Para usar $appName necesitas una cuenta AMG (usuario y contraseña). La solicitud puede quedar pendiente hasta la aprobación del administrador. El servidor puede tratar:',
        ],
        bullets: [
          'Usuario, contraseña (hash en servidor), email opcional y código de recuperación.',
          'Identificador técnico de instalación (device ID generado por la app; no es IMEI ni identificador publicitario).',
          'Plataforma (Android, Windows, etc.), versión de la app y número de build.',
          'Clave de licencia, estado y módulos habilitados (p. ej. Inicio, detección automática).',
          'Comprobaciones puntuales de capacidad/módulo y, si las solicitas, peticiones de mejora de módulos.',
        ],
      ),
      HelpDocSection(
        title: '4. Qué se queda en tu dispositivo',
        paragraphs: [
          'Estos datos se guardan en local y no se envían al servidor de licencias para el control de instalaciones:',
        ],
        bullets: [
          'Perfil deportivo (nombre, licencia federativa, club, categoría, etc.).',
          'Sesiones, disparos, puntuaciones, material, munición, fotos de diana y preferencias (p. ej. avisos de tiro).',
          'Aceptación de esta política (versión y fecha), necesaria para usar la app.',
          'Un verificador de la contraseña (hash y sal; no la contraseña en claro) para poder entrar en este dispositivo sin internet, como máximo 14 días desde la última comprobación correcta con el servidor. Cerrar sesión no lo borra. Se elimina si la cuenta queda bloqueada o rechazada, si la contraseña ya no coincide con el servidor, o al caducar ese plazo.',
          'Si activas la huella, el usuario y la contraseña se guardan en el almacén seguro del sistema, solo para desbloquear el acceso en este teléfono.',
          'Copias de seguridad que exportes o importes (tú eliges el destino del archivo).',
        ],
      ),
      HelpDocSection(
        title: '5. Finalidades',
        bullets: [
          'Registrar y validar la instalación (licencia y módulos).',
          'Estimar el número de instalaciones/usuarios activos y prevenir abusos.',
          'Prestar las funciones de la app en el dispositivo.',
          'Atender soporte y solicitudes relacionadas con $appName.',
          'Comprobar actualizaciones de la app (metadata de versión), sin enviar el historial deportivo.',
        ],
      ),
      HelpDocSection(
        title: '6. Base jurídica',
        paragraphs: [
          'El tratamiento se basa, según el caso, en:',
        ],
        bullets: [
          'Ejecución del servicio / medidas asociadas al registro de instalación y prestación de la app (art. 6.1.b RGPD).',
          'Interés legítimo (art. 6.1.f RGPD) en seguridad técnica, control de licencias/módulos y prevención de abusos.',
          'Consentimiento (art. 6.1.a RGPD) cuando marcas la aceptación de esta política para poder usar la app.',
          'Cuando aportas email, también la identificación voluntaria de la instalación para soporte o vinculación.',
        ],
      ),
      HelpDocSection(
        title: '7. Conservación',
        paragraphs: [
          'Los datos en el dispositivo permanecen mientras uses la app o hasta que los borres (desinstalación, borrado de datos o restauración). El verificador de acceso local caduca a los 14 días sin una comprobación correcta con el servidor.',
          'Los datos de instalación/licencia en servidor se conservan mientras la instalación esté activa o sea necesario para licencia, soporte y seguridad (orientativo: hasta 24 meses desde la última actividad), y después según plazos legales aplicables.',
          'Si solicitas la eliminación, se atenderá salvo obligaciones de conservación o motivos legítimos de bloqueo.',
        ],
      ),
      HelpDocSection(
        title: '8. Destinatarios y encargados',
        paragraphs: [
          'No se venden datos personales a terceros con fines comerciales.',
          'Pueden acceder a los datos de instalación/licencia proveedores de alojamiento del panel/API (habitualmente Hostinger, en la Unión Europea), actuando como encargados cuando corresponda.',
          '$appName no utiliza Firebase, analítica publicitaria ni redes de anuncios.',
          'También pueden conocerse datos las autoridades competentes cuando exista obligación legal.',
        ],
      ),
      HelpDocSection(
        title: '9. Transferencias internacionales',
        paragraphs: [
          'El tratamiento previsto del panel de licencias se realiza con infraestructura habitual en la Unión Europea. No está previsto transferir tus datos fuera del EEE de forma habitual. Si en el futuro fuera necesario, se informarían las garantías adecuadas.',
        ],
      ),
      HelpDocSection(
        title: '10. Derechos',
        paragraphs: [
          'Puedes ejercer acceso, rectificación, supresión, oposición, limitación y, cuando proceda, portabilidad, así como retirar el consentimiento sin afectar a la licitud del tratamiento previo.',
          'Para ejercerlos, escribe a $emailContacto indicando el derecho solicitado y datos que permitan identificar la instalación (email registrado y/o device ID si lo conoces).',
          'También puedes reclamar ante la Agencia Española de Protección de Datos (AEPD): www.aepd.es',
        ],
      ),
      HelpDocSection(
        title: '11. Seguridad',
        paragraphs: [
          'Se aplican medidas técnicas y organizativas razonables (comunicaciones cifradas hacia el servidor cuando se usa HTTPS, control de acceso al panel, minimización de datos, almacén seguro del sistema para la huella y el verificador local). Ningún sistema es 100 % seguro; te recomendamos proteger el dispositivo y las copias de seguridad exportadas.',
        ],
      ),
      HelpDocSection(
        title: '12. Menores',
        paragraphs: [
          '$appName está dirigida solo a adultos. No se solicita ni se autoriza el registro de menores de 18 años.',
        ],
      ),
      HelpDocSection(
        title: '13. Cambios',
        paragraphs: [
          'Esta política puede actualizarse. La versión actual en la app es $version. Si hay cambios relevantes, se procurará informarte en la propia aplicación o en $webPrivacidad.',
        ],
      ),
    ],
  );
}
