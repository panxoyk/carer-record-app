# Pendientes de desarrollo

Este backlog contiene solo trabajo que afecta el desarrollo local, funcionalidades
rotas, comportamiento incorrecto o la capacidad de agregar cambios con seguridad.
El trabajo exclusivo de distribución y producción queda fuera de esta lista.

El trabajo se realiza directamente sobre `main`. Cada commit debe resolver un
cambio lógico independiente y dejar actualizados este archivo, el roadmap, las
pruebas y la documentación afectada.

## P0 - Funcionalidad rota

- [ ] Reparar `manage-practitioners` para crear usuarios. Separar el cliente que
  valida el JWT del caller del cliente Service Role que ejecuta Auth Admin, y
  cubrir `list`, `create` y `update` con pruebas de integración.
- [ ] Corregir la recuperación de contraseña local. La URL solicitada por Flutter,
  `io.carerrecord.app://login-callback/recover`, debe estar permitida exactamente
  en Supabase y probarse con la aplicación cerrada y abierta.

## P1 - Autorización y comportamiento

- [ ] Hacer que las mutaciones de practitioners pasen exclusivamente por la Edge
  Function; retirar el DML administrativo directo sobre la tabla una vez que la
  función use un cliente Service Role separado.
- [ ] Impedir que una actualización suspenda o quite privilegios al último
  administrador activo. Definir también el comportamiento al editar la cuenta
  propia.
- [ ] Invalidar providers y datos clínicos al cerrar sesión, suspender una cuenta
  o cambiar su rol. Usar disposición automática donde corresponda.
- [ ] Mantener una sola instancia de `GoRouter` y refrescar sus redirects sin
  reconstruir el router completo en cada evento de Auth.
- [ ] Eliminar o respaldar con datos reales los textos "bajo tu atención",
  "Ficha activa", "Hospitalización activa" y "HOY". Definir además cómo se
  convierte y presenta la zona horaria de eventos clínicos.
- [ ] Agregar debounce y escaping seguro a la búsqueda de pacientes, y reiniciar
  el filtro de unidad cuando ya no exista en los resultados.
- [ ] Mostrar loading, error y retry en creación y actualización de usuarios,
  recuperación de contraseña y consultas clínicas.

## P1 - Pruebas y tooling

- [ ] Implementar la cobertura descrita en `docs/testing-strategy.md`, empezando
  por autorización, repositorios, Edge Functions y regresiones conocidas.
- [ ] Hacer que las pruebas pgTAP creen sus propios fixtures dentro de la
  transacción, en lugar de depender de cantidades exactas de `seed.sql`.
- [ ] Crear `deno.json` con dependencias fijadas y agregar checks de formato,
  lint, tipos y pruebas para las Edge Functions.
- [ ] Reparar `.github/workflows/verify.yml`: instalar pnpm antes de activar su
  cache, configurar FVM desde `app/.fvmrc` y ejecutar pruebas Flutter y Deno.

## P1 - pnpm

- [ ] Mantener `packageManager` fijado y `pnpm install --frozen-lockfile` como
  instalación reproducible.
- [ ] Agregar scripts raíz para pruebas Flutter y checks de Edge Functions, de
  modo que las validaciones locales y remotas usen los mismos comandos.
- [ ] Decidir si se elimina `pnpm-workspace.yaml` mientras no existan paquetes
  Node internos; actualmente `packages: []` no aporta funcionalidad.
- [ ] Configurar Renovate para actualizaciones controladas de pnpm, Pub, GitHub
  Actions y dependencias Deno.
- [ ] Actualizar `concurrently` a su siguiente versión mayor después de reparar
  la CI y contar con las validaciones anteriores.

## P2 - Escalabilidad y mantenibilidad

- [ ] Seleccionar columnas explícitas y paginar pacientes y eventos para evitar
  el límite silencioso de 1000 filas de la API.
- [ ] Reemplazar `Patient.payload` como `Map<String, dynamic>` por un modelo
  tipado, o dejar de solicitar la columna mientras no se utilice.
- [ ] Mover acceso remoto y modelos de practitioners fuera de
  `users_screen.dart`, respetando la separación `data/domain/presentation`.
- [ ] Separar `patient_screens.dart` por pantalla cuando se vuelva a modificar
  ese dominio; no crear abstracciones adicionales sin reutilización concreta.

## Funcionalidades diferidas

- [ ] Implementar el pipeline real de ingesta FHIR; el código actual es solo un
  scaffold que valida argumentos.
- [ ] Implementar `clinical-summary` únicamente después de definir su contrato,
  autorización clínica y tratamiento de datos sensibles; hoy responde HTTP 501.

## Fuera del alcance actual

No bloquean el desarrollo local: firma e identificador Android de release,
permisos del artefacto release, App Links/Universal Links de producción,
despliegue continuo, infraestructura cloud, backups, observabilidad y requisitos
de distribución o cumplimiento para producción.
