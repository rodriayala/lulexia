# Propuesta web pública de Lulexia

Sitio estático en `docs/`, con logo original, diseño adaptable a móvil, correo desarrollo.rodrigo.ayala@gmail.com y LinkedIn de Rodrigo Ayala. Sin dependencias, JavaScript, fuentes externas ni analítica propia.

## Antes de publicar

La política describe el modelo local observado en el código Swift de este repositorio. No se encontró aquí código Android. **Comparar las declaraciones con el AAB Android real antes de usar estos textos para Google Play.** Revisar especialmente SDK, permisos, motor de voz, servicios de nube, copias de seguridad, publicidad y telemetría. Si difieren, actualizar la política y Seguridad de los datos. El sitio explica la disponibilidad actual sin simular una descarga en Google Play.

Confirmar que Rodrigo Ayala figure como responsable o que el nombre del desarrollador de la ficha esté también identificado en la política. Confirmar que el correo publicado recibe mensajes. El bloque de autor incluye el retrato ilustrado suministrado, editado con la herramienta integrada de imágenes para extraer el fondo y el marco. Archivo: `docs/assets/rodrigo-recorte.png`, PNG con canal alfa. Instrucción de edición: quitar el fondo tecnológico y todas las líneas y bordes; conservar rostro, sonrisa, pose, ropa, colores y estilo; entregar únicamente la silueta con transparencia real, sin halo, sombra ni texto.

## Publicación en GitHub Pages

1. Subir `docs/` al repositorio `rodriayala/lulexia` en la rama que se elija para publicar. No hace falta incluir certificados, paquetes ni archivos privados.
2. Abrir Settings → Pages → Build and deployment.
3. Elegir **Deploy from a branch**, la rama correspondiente y carpeta **/docs**; guardar.
4. Esperar el despliegue y comprobar las URL siguientes sin iniciar sesión, incluyendo desde un teléfono.

Direcciones previstas (no verificadas como publicadas):

- Web: https://rodriayala.github.io/lulexia/
- Privacidad: https://rodriayala.github.io/lulexia/privacidad.html
- Datos y eliminación: https://rodriayala.github.io/lulexia/datos.html
- Soporte: https://rodriayala.github.io/lulexia/soporte.html

El sitio se mantiene en `docs/` dentro del mismo repositorio. La publicación requiere que GitHub Pages use la rama `main` y la carpeta `/docs`.

## Preparación para Google Play

- Pegar la URL pública de privacidad en el campo correspondiente y agregar un enlace accesible a esa política dentro de la app Android.
- Completar Seguridad de los datos según la versión final y sus SDK. El procesamiento exclusivamente local no equivale a transmisión al desarrollador; revisar las definiciones oficiales y las excepciones antes de responder.
- Acceso a la app: si efectivamente no hay login ni funciones restringidas, declarar acceso sin restricciones. No inventar credenciales.
- Anuncios: responder según el AAB real. El código local revisado no integra anuncios.
- Audiencia objetivo: elegir los grupos reales. Si incluye niños, revisar Familias; la política web por sí sola no cumple todas esas obligaciones.
- Clasificación de contenido: completar el cuestionario de IARC según funciones reales.
- Gobierno, finanzas y salud: responder por funciones reales. No equiparar automáticamente apoyo de lectura con diagnóstico médico. La web no promete diagnóstico ni tratamiento.
- Lulapoints: en el código revisado son progreso local, sin pagos, canje ni valor monetario; comprobar que siga siendo así en Android.
- Si no se crean cuentas, no declarar que existe un mecanismo de eliminación de cuentas. `datos.html` explica el borrado local; **no sustituye una solicitud de eliminación de cuenta** si se agrega registro en el futuro. En ese caso se necesitan mecanismo dentro de la app y recurso web funcional.
- Publicar email de contacto en la ficha, capturas reales, descripción fiel, categoría, bundle y pruebas que requiera la cuenta. Una web completa no garantiza aprobación.

## Fuentes oficiales revisadas

- Datos de usuarios y privacidad: https://support.google.com/googleplay/android-developer/answer/10144311
- Eliminación de cuentas: https://support.google.com/googleplay/android-developer/answer/13327111
- Configuración de la app y contacto: https://support.google.com/googleplay/android-developer/answer/9859152
- Seguridad de los datos: https://support.google.com/googleplay/android-developer/answer/10787469
- Publicar desde una rama: https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site

## Vista local

Abrir `docs/index.html` en el navegador. Los enlaces y recursos son relativos y funcionan bajo el prefijo `/lulexia/` de GitHub Pages.
