---
trigger: always_on
---

# 🌐 REGLA GLOBAL: CADENA DE CUSTODIA GIT Y GESTIÓN AUTOMÁTICA DE CREDENCIALES

> Aplica obligatoriamente a TODOS los agentes, proyectos, repositorios y despliegues en Keystone Advisors.

---

### 1. 🔑 Resolución Obligatoria de Credenciales Git vía KeyHub (Anti-Permission Denied)
- **Consulta Previa de Credenciales por Proyecto**:
  - Antes de ejecutar cualquier comando de red en Git (`git push`, `git fetch`, `git pull` o apertura de Pull Request), el agente o `@release-manager` **DEBE consultar la configuración del proyecto en KeyHub** (`projects.github_repo` y `projects.github_token`).
  - **Prohibición de Asumir SSH Genérico**: Queda estrictamente PROHIBIDO confiar a ciegas en la clave SSH global del sistema (`git@github.com:...`) para repositorios corporativos de clientes, ya que las claves locales no suelen tener permisos en organizaciones privadas externas (ej. `BancoVimenca`).
- **Inyección Automática del PAT de KeyHub**:
  - Si el proyecto tiene configurado `github_token` en la tabla `projects`, el agente debe configurar automáticamente el remote del repositorio local antes del push:
    ```bash
    git remote set-url origin https://x-access-token:<GITHUB_TOKEN>@github.com/<GITHUB_REPO>.git
    ```
  - Esto garantiza que el 100% de las operaciones de push y creación de Pull Requests se ejecuten con las credenciales corporativas autorizadas del cliente sin intervención manual.

---

### 2. 🚫 Prohibición Estricta de Despliegues "Al Vuelo" sin Commit y Push Git
- **Trazabilidad de Código Fuente:** Queda terminantemente PROHIBIDO transferir, copiar por SCP, sincronizar por rsync o promover código hacia **QA**, **STAGING** o **PRODUCCIÓN** que no esté previamente respaldado en un **Commit Git formal** y con **Push exitoso hacia el repositorio remoto oficial en GitHub / GitLab**.
- **Auditoría de Integridad:** Un archivo en el servidor que no tenga correspondencia exacta con un commit de Git es considerado código fantasma no auditado. Todo despliegue ejecutado saltándose el control de versiones viola la gobernanza institucional de Keystone.

---

### 3. 🔄 Protocolo Mandatorio del Release Manager (@release-manager)
Antes de transferir o autorizar cualquier promoción de código:
1. **Verificación de Estado Limpio (`git status`):**
   - El árbol de trabajo debe quedar limpio. No pueden quedar cambios sin stagear (`working tree clean`).
2. **Commit Atómico Formal:**
   - Todo cambio debe incluirse en un commit que referencie el correlativo institucional:
     `feat(SOL-XXXX): descripción clara del requerimiento` o `fix(SOL-XXXX): ...`
3. **Resolución de Credencial y Push a Ramas Oficiales:**
   - Resolver el PAT de KeyHub para el proyecto.
   - El commit debe ser empujado a la rama de desarrollo (`develop`) o rama de feature.
   - Abrir el Pull Request formal hacia la rama base (`develop` o `main`) vía API de GitHub usando el token corporativo.
4. **Declaración del Hash y PR en Cadena de Custodia:**
   - Toda notificación de despliegue a QA o Prod en la tarjeta de KeyHub (`card_comments`) o en `BITACORA_PRODUCCION.md` DEBE incluir obligatoriamente:
     - El **Hash SHA del Commit** (ej: `commit 35160a9`).
     - El enlace directo al **Pull Request en GitHub** (ej: `https://github.com/BancoVimenca/war-room/pull/1`).

---

### 4. 🚨 Cláusula de Bloqueo Inmediato
Si un comando `git push` falla por cualquier motivo (red, credenciales, conflicto):
- **El agente debe detenerse de inmediato.**
- Queda terminantemente PROHIBIDO continuar con el despliegue o simular éxito en KeyHub si el push a GitHub no retornó código de salida 0.
- El agente debe inspeccionar KeyHub, resolver la credencial y reintentar, o solicitar asistencia si el token ha expirado.

