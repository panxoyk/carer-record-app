# Guía breve del sistema visual

La [referencia de Figma](https://www.figma.com/make/vQlRr78qmYaNPnAlMwMH4O/Utilizar-Markdown-como-referencia?p=f) y sus capturas compartidas para este incremento orientan la apariencia general; no son especificaciones medibles ni pixel-perfect. El código Dart bajo `app/lib/core/design_system/` es la fuente de verdad.

## Uso

- Conserva un canvas gris claro, superficies blancas redondeadas, gutters consistentes y separadores discretos.
- Usa jerarquía tipográfica semántica del `TextTheme` (`headlineMedium`, `titleLarge`, `bodyLarge`/`bodyMedium`) en vez de estilos duplicados.
- Usa `ClinicalSpacing` y `ClinicalRadii` para espaciado y formas compartidos. No copies los valores numéricos a tablas o constantes locales.
- Reserva menta para énfasis y acciones; los colores semánticos de texto, separación y destrucción deben conservar su significado.
- Mantén alineación entre encabezados, contenido y tarjetas; respeta estados de interacción y contraste legible.
- Reutiliza `ClinicalPageTitle` y `ClinicalContentCard` cuando encajen; no son requisito para rediseñar pantallas.
- Usa `ClinicalToast.success`, `ClinicalToast.failure` y `ClinicalToast.dismissAll` para avisos compartidos; no importes toastification desde pantallas. Cada mensaje nombra la operación y su resultado, y mantiene detalles o instrucciones de acción inline; los errores recuperables y su reintento permanecen en el control de la operación, no en una acción del aviso. `success` y `failure` muestran un solo aviso sobre rutas modales, respetan safe area y texto ampliado, y admiten cierre manual. `withDetails` extiende la duración de tres a cuatro segundos para ambos tipos. Cualquier aviso nuevo reemplaza inmediatamente al anterior, incluso si reutiliza su identificador; no hay cola ni acciones en avisos. `dismissAll` y el cierre del host limpian el aviso. La presentación usa el `Overlay` Flutter compartido.
- Las páginas internas usan `clinicalAppBar` o `clinicalBackAppBar`, con el título en el encabezado junto al botón de volver cuando corresponda; evita duplicar `ClinicalPageTitle` en el cuerpo. Los formularios de autenticación mantienen intencionalmente un diseño distinto.

## Autenticación

El login presenta la marca «Carer Record» y el subtítulo «Contexto para el cuidado clínico» sobre el canvas del tema, con una tarjeta blanca para el formulario. Títulos, etiquetas y texto usan `TextTheme`; espaciado, radios, campos y colores heredan `ClinicalSpacing`, `ClinicalRadii`, `clinicalInputDecoration` y el tema compartido. Los campos de correo y contraseña tienen etiquetas persistentes con semántica explícita; la contraseña incluye un control accesible para mostrarla u ocultarla. El botón de acceso ocupa el ancho disponible y hereda el tema de `FilledButton`. La ayuda indica contactar al administrador institucional: no hay registro en esta pantalla.

El scaffold compartido es `SafeArea`, desplazable y limitado a 420 px; permite recorrer el contenido con teclado o texto ampliado. El login es la pantalla rediseñada con tarjeta; recuperar y definir contraseña comparten el scaffold, pero no esa tarjeta ni el rediseño del formulario.

No amplía el alcance funcional ni introduce features o decisiones de dominio. Ajustes visuales futuros deben mantener la referencia, los tokens y las pruebas alineados.

## Modal de notas de contexto

El editor de nota usa una hoja modal blanca, redondeada y desplazable; abre en dictado, seguido de Texto, y la grabación solo inicia a petición. La procedencia del dictado se conserva al guardar, pero no se muestra en la interfaz. El contenido y las acciones deben seguir accesibles con teclado o texto ampliado, y el error recuperable permanece inline junto al reintento.
