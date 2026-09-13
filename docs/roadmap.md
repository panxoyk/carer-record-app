# Roadmap

| Estado | Entrega | Seguimiento |
| --- | --- | --- |
| done | Infraestructura local inicial y datos seed | - |
| in-progress | Acceso, recuperación y administración de usuarios | [Pendientes](todo.md) |
| done | Listado clínico y timeline de pacientes de solo lectura | - |
| planned | Pipeline de ingesta FHIR | [Pendientes](todo.md) |

Todo cambio funcional debe implementarse en un commit independiente y actualizar
esta tabla cuando cambie el estado de una entrega.

## Matriz de permisos clínicos

| Rol activo | Pacientes | Eventos clínicos | Administración de usuarios |
| --- | --- | --- | --- |
| `administrator` | Sin acceso | Sin acceso | Gestionar practitioners |
| `physician` | Listar, buscar y ver timeline | Ver timeline | Sin acceso |
| `nurse` | Listar, buscar y ver timeline | Ver timeline | Sin acceso |
| `technician` | Listar, buscar y ver timeline | Ver timeline | Sin acceso |
| Cualquier rol suspendido | Sin acceso | Sin acceso | Sin acceso |

La entrega es estrictamente de solo lectura: no permite crear, editar ni
eliminar pacientes ni eventos clínicos.
