# Roadmap

| Estado | Entrega | Seguimiento |
| --- | --- | --- |
| done | Infraestructura inicial, datos seed y pipeline | [Issues](https://github.com/panxoyk/carer-record-app/issues) |
| in-progress | Acceso, recuperación y administración de usuarios | [Issues](https://github.com/panxoyk/carer-record-app/issues) |
| done | Listado clínico y timeline de pacientes de solo lectura | [Issue #1](https://github.com/panxoyk/carer-record-app/issues/1) |

Todo cambio funcional debe estar vinculado a un GitHub Issue y actualizar esta tabla cuando cambie de estado.

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
