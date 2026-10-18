# ADR-018: Módulo compartido de IA en el dispositivo

Fecha: 2026-10-18

## Estado

Aceptada. Esta decisión organiza técnicamente capacidades locales existentes y no modifica decisiones de producto, privacidad ni permisos de ADR-016 y ADR-017.

## Contexto

ASR, síntesis y administración de modelos son capacidades técnicas reutilizables por distintos flujos. Mantenerlas dentro del dominio de notas acopla esos motores a publicación y dictado.

## Decisión

`on_device_ai` es un dominio vertical independiente con capas `data`, `domain` y `presentation`, propietario de ASR, síntesis, gestión de modelos y capacidades de uso. El dominio `context_note` conserva sus controladores de dictado, asistencia y publicación, su vault y sus casos de uso de negocio; consume los puertos y capacidades compartidas.

El contrato técnico de procedencia de transcripción se conserva para compatibilidad. `ConfirmedMilestoneWriter` y `DictationAudio` son puertos del dominio de notas. El uso de capacidades compartidas se coordina mediante leases genéricos; `LocalCapabilityRepository` es la única frontera de provisioning. El hook genérico de limpieza de sesión se inyecta desde la raíz de composición.

## Consecuencias

- Los motores y la gestión de modelos no dependen de la publicación de notas.
- Los flujos de negocio siguen siendo responsables de confirmar texto y limpiar sus artefactos locales.
- La separación no implica cambiar egress, permisos, políticas RLS ni el comportamiento de disponibilidad de modelos.
- La migración puede mover archivos sin cambiar contratos wire existentes.
