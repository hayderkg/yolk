# Yolk

> Antes llamado Port Dog.

Una pequeña app nativa para tener tus servidores locales a mano. [English](../README.md) · [Licencia MIT](../LICENSE)

SwiftUI, `MenuBarExtra`, macOS 13 o posterior. Sin ventana principal, icono en el Dock ni dependencias externas.

**Versión 1.3 beta (como Port Dog):** identidad propia, mascota, icono de barra específico y ajustes de apariencia dentro del panel. Modos sistema/claro/oscuro, fondo translúcido/sólido, cuatro paletas y frecuencia de actualización configurable.

**Desde la versión 1.2:** búsqueda, favoritos, servicios ocultos, alcance de red e inicio opcional con macOS. Cabeceras de grupo fijas al desplazarte, detalles visuales más cuidados y corrección del tamaño del panel al plegar grupos. Conserva los iconos de apps, favicons locales, iniciales y nombres de proyecto de la versión anterior.

## Abrir

Abre **Yolk.app**. Aparece un icono de red en la barra de menús, arriba a la derecha. Puedes arrastrar la app a Aplicaciones si quieres conservarla allí. La compilación universal incluye Apple Silicon e Intel. El funcionamiento en Intel aún necesita validación en hardware real.

> La interfaz de la app está ahora en inglés. Esta guía describe la versión 1.3; los cambios de la 1.4 están resumidos justo debajo y detallados en el [README en inglés](../README.md).

**Novedades de la 1.4 beta:** nuevo nombre (Yolk) y logo, uso completo con teclado (escribir filtra, flechas para elegir, Intro abre, ⌘C copia la dirección, ⌘⌫ detiene la fila elegida con las flechas), clic en la fila para abrir y en el puerto para copiar, comando y tiempo activo en cada fila, acciones visibles solo al pasar el cursor, contenedores de Docker con su nombre e imagen (detenerlos para el contenedor, no Docker), «detener todo» por grupo, abrir el proyecto en Finder, editor o terminal, atajo global opcional y un punto en el icono de la barra de menús cuando aparece un puerto nuevo.

- Cada fila muestra **puerto, nombre, comando y tiempo activo**. El mismo proceso puede tener varios puertos.
- Los tipos **Desarrollo, Bases de datos, Apps, Sistema y Otros** se pueden plegar pulsando su cabecera. El menú junto a actualizar permite desactivar la agrupación o expandir/plegar todo; estas preferencias se conservan.
- **⌘F** abre la búsqueda por nombre, proyecto, puerto o PID. Los grupos con resultados se expanden temporalmente; al borrar la búsqueda recuperan su estado anterior. Escape borra la consulta o cierra el buscador si ya está vacío.
- La estrella guarda el servicio como **favorito** y lo coloca arriba. Los favoritos se recuerdan por proyecto o ejecutable y puerto, aunque cambie su PID. El menú de filtros permite ver solo favoritos.
- **Ocultar servicio**, en el menú contextual, lo retira de la lista sin detenerlo. Puedes mostrar los ocultos o restaurarlos desde el menú de filtros, incluso cuando ya no estén ejecutándose. Los filtros temporales se reinician al volver a abrir la app; favoritos y servicios ocultos se conservan.
- **Local** indica que escucha solo en direcciones de este Mac; **Todas** indica una dirección comodín. Esto último no garantiza que otros dispositivos puedan acceder: depende de la red y del cortafuegos.
- Los procesos de desarrollo muestran el nombre de `package.json` cuando existe en su carpeta de trabajo o hasta tres carpetas superiores. En su defecto, se usa el nombre de la carpeta. Debajo siguen apareciendo el proceso y el PID.
- La flecha abre la dirección en el navegador predeterminado cuando parece un servicio web. Usa HTTP, o HTTPS en los puertos 443, 4443 y 8443.
- El botón de parada envía **SIGTERM** al proceso completo, cerrando todos sus puertos. Si sigue activo después de dos segundos, el botón cambia para ofrecer **Forzar cierre** (SIGKILL), con confirmación.
- Clic derecho permite abrir la carpeta del proyecto, copiar la dirección y abrir manualmente como HTTP un servicio sin web conocida.
- La lista se actualiza cada tres segundos por defecto, también con el panel cerrado. **⌘R** actualiza al momento; **Quit / ⌘Q** cierra la app.

Los controles conservan el aspecto del sistema, funcionan con teclado y tienen etiquetas de accesibilidad y ayuda al pasar el cursor. La lista tiene desplazamiento cuando hay muchos puertos y un estado vacío cuando no hay ninguno.

Las cabeceras de grupo permanecen visibles al desplazarte. Los cambios al pasar el cursor, la aparición de iconos y el giro del indicador de grupo usan transiciones breves y respetan **Reducir movimiento**. El panel ajusta su altura al plegar o filtrar sin animar la ventana ni dejar espacio sobrante, manteniendo fijo su borde superior.

Para arrancar automáticamente, coloca primero la app en **Aplicaciones** y activa **Iniciar con macOS** en Ajustes (engranaje o ⌘,). Está desactivado por defecto. La app usa el registro nativo de macOS y muestra un acceso a Ajustes del Sistema si requiere autorización. Puedes desactivarlo desde el mismo menú.

Para actualizar una copia en ejecución, pulsa **Quit** y abre la nueva **Yolk.app**.

## Iconos

Las apps usan el icono de su paquete de macOS. En desarrollo se buscan favicons en carpetas habituales del proyecto (`public`, `static`, `app` y `src/app`). Si no hay uno disponible y el proceso parece un servidor web, se consulta `/favicon.ico`, los enlaces de icono de la página principal y las variantes PNG/SVG.

Las peticiones solo admiten el mismo servidor local, protocolo y puerto; no siguen enlaces a servicios externos, no envían cookies ni credenciales y mantienen la validación normal de certificados HTTPS. Cada respuesta tiene límite de tamaño y tiempo. Los resultados, incluidas las ausencias, se conservan en memoria durante al menos diez minutos para evitar consultas en cada refresco. La carga empieza cuando se muestran las filas; una carga ya iniciada puede terminar después de cerrar el panel.

Si no se obtiene una imagen utilizable, aparecen las iniciales. Los SVG se aceptan cuando macOS puede decodificarlos y son autocontenidos; se rechazan recursos externos, scripts y contenido incrustado. La identificación de proyectos y tipos usa indicios del proceso y puede ser aproximada en monorepos o servidores con varias apps en el mismo proceso.

## Qué detecta

Consulta los sockets nativos mediante `libproc`: solo TCP en estado LISTEN, en `127.0.0.0/8`, `::1`, IPv4 mapeado en IPv6 o direcciones comodín (`0.0.0.0` y `::`). Estos últimos también escuchan en localhost. Excluye UDP, conexiones ya establecidas y sockets ligados exclusivamente a una IP de la red local.

Agrupa IPv4 e IPv6 por proceso y puerto. Solo muestra lo que macOS permite consultar con tu usuario; los procesos de otros usuarios pueden no ser visibles y, si aparecen, no se pueden terminar desde la app. No solicita privilegios de administrador. Un puerto publicado por Docker puede aparecer a nombre del proceso de Docker que lo publica, no del proceso que corre dentro del contenedor.

La acción web usa indicios del nombre y del puerto; no verifica el protocolo. La búsqueda de favicons sí puede solicitar archivos del servidor local. Los servicios conocidos de base de datos no tienen acceso directo al navegador. Para otros servicios puedes usar **Abrir como HTTP** en el menú contextual. Las direcciones habituales usan `localhost`; si un servicio escucha exclusivamente en otro alias, como `127.0.0.2`, se abre esa IP.

Antes de enviar una señal se comprueban el propietario y la hora de creación del proceso para rechazar PIDs reutilizados. Como ocurre con la API POSIX de señales por PID, la comprobación y la señal no son una operación atómica. Un supervisor como launchd, Docker o un gestor de desarrollo puede volver a iniciar automáticamente un proceso que cierres.

## Compilar

Necesitas Xcode o sus Command Line Tools con Swift 5.9 o posterior.

```sh
bash scripts/build.sh
open "dist/Yolk.app"
```

El script crea el paquete `.app` y lo firma de forma ad hoc para uso local. Esta compilación no está notarizada para distribución pública. No activa App Sandbox, porque la inspección y terminación de otros procesos necesitan acceso fuera de él.

Puedes abrir `Package.swift` en Xcode para editar el proyecto. El paquete de aplicación que genera el script incluye `LSUIElement = true`; al ejecutar directamente el binario, el delegado también configura la app como accesorio.

Para elegir otras carpetas de compilación y salida:

```sh
LOCALPORTS_BUILD_DIR=/ruta/build LOCALPORTS_OUTPUT_DIR=/ruta/salida bash scripts/build.sh
```

## Pruebas

```sh
swift test
```

Las 49 pruebas cubren IPv4, IPv6, comodines, agrupación, exclusión de UDP y TCP sin escucha, enlaces web, cierre normal/forzado, identidades obsoletas, categorías, carpetas de proyecto, iniciales, favicons enlazados desde HTML, SVG autocontenidos, respuestas demasiado grandes y redirecciones fuera del origen. También comprueban la búsqueda, el orden de favoritos, la persistencia y restauración de ocultos, el alcance de red, los estados y errores del inicio automático y el ajuste de la ventana manteniendo fijo su borde superior.

Las pruebas de procesos usan sockets locales y procesos temporales propios, creados con el Python incluido en las herramientas de desarrollo de Apple; no se tocan los servidores del usuario. Las pruebas de inicio automático usan un servicio simulado y no modifican los ítems de inicio del Mac.

## Código

- `Sources/LocalPorts`: interfaz SwiftUI y actualización asíncrona.
- `Sources/LocalPortsCore`: modelo, agrupación, enlaces y control de procesos.
- `Sources/PortInspector`: adaptador pequeño en C para las estructuras y API de `libproc`.
- `Resources/Info.plist`: configuración de app exclusiva de barra de menús.

Referencias: [MenuBarExtra de Apple](https://developer.apple.com/documentation/swiftui/menubarextra) y [API libproc de Apple](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h).

## Ajustes y beta pública

El engranaje (⌘,) abre ajustes dentro del panel. Puedes combinar modo claro/oscuro/sistema, fondo sólido/translúcido y las paletas Nativa, Mustard, Bubblegum y Electric. Se respetan Reducir movimiento y Reducir transparencia. Restablecer apariencia no borra favoritos ni cambia el inicio de sesión.

La frecuencia puede ser 2, 3, 5 o 10 segundos; el cambio se aplica al siguiente ciclo. Las notificaciones se reservan para una versión posterior.

Consulta [privacidad](../PRIVACY.md), [contribuciones](../CONTRIBUTING.md) y [publicación](../RELEASING.md). Los binarios de desarrollo tienen firma local y no están notarizados. La guía distingue las comprobaciones automáticas de las pruebas manuales pendientes.
