
### Registro de Despliegue - 26/11/2026 03:31 AM
- **Cliente / Proyecto:** Banco Vimenca / War Room
- **Ambiente Destino:** Producción (`vimenca-prod`)
- **Identificador:** `SOL-0369` (Bandeja Operativa Multirrol de Créditos)
- **Deploy ID:** `0AfVT000001OPKr0AO` (Quick Deploy via Validation `0AfVT000001OPJF0A4`)
- **Componentes promovidos:** `FSC_CreditWorkspaceController`, `FSC_CreditWorkspaceControllerTest`
- **Resumen de la Ejecución:** Éxito (`Status: Succeeded`).
  1. Se ajustó la resolución de turnos y métricas en `Recepción de documentos – Análisis` para atribuir el turno operativo al Oficial de Negocios (`Owner.Name`), liberando la bandeja de los analistas de crédito de solicitudes devueltas para completar recaudos en sucursal.
  2. Se corrigió el filtro de `mis_casos` para evitar que comités o analistas anteriores sigan viendo solicitudes históricas devueltas a otras fases (`SOL-CRED-00048`).
  3. Se incorporó la resolución recursiva de grupos públicos anidados en colas, permitiendo a gerentes de crédito como Altagracia Gonzalez ver y dictaminar sus excepciones asignadas (`SOL-CRED-00071`).
  4. Tests unitarios aprobados al 100% y smoke test operativo en Producción.

### Registro de Despliegue - 26/11/2026 03:42 AM
- **Cliente / Proyecto:** Banco Vimenca / War Room
- **Ambiente Destino:** Producción (`vimenca-prod`)
- **Identificador:** `SOL-0369` (Módulo de Dictamen Directo de Aprobaciones en Bandeja de Créditos)
- **Deploy ID:** `0AfVT000001OPO50AO` (Quick Deploy via Validation `0AfVT000001OPMT0A4`)
- **Componentes promovidos:** `FSC_CreditWorkspaceController`, `FSC_CreditWorkspaceControllerTest`, `fsc_CreditApplicationsWorkspace` (LWC)
- **Resumen de la Ejecución:** Éxito (`Status: Succeeded`).
  1. Se implementó la nueva pestaña prioritaria **"⚡ Mis Aprobaciones Pendientes"** en la Bandeja de Créditos, filtrando exclusivamente las solicitudes y excepciones con workitem activo asignado al usuario o sus colas.
  2. Se habilitó la acción contextual en fila **"⚡ Dictaminar Aprobación"** que abre un modal modal para registrar comentarios y ejecutar el dictamen (**Aprobar** o **Rechazar**) en 1 clic directamente sobre `Approval.process`, sin tener que navegar fuera de la bandeja ni entrar a vistas satélites.
  3. Cobertura de tests unitarios al 100% (3/3 passing) y verificación post-despliegue en producción.

### Registro de Despliegue - 26/11/2026 01:58 PM
- **Cliente / Proyecto:** Banco Vimenca / War Room
- **Ambiente Destino:** Producción (`vimenca-prod`)
- **Identificador:** `SOL-0369` (Inclusión de Solicitudes con Aprobación en Borrador para Dictamen Directo)
- **Deploy ID:** `0AfVT000001ORJR0A4` (Quick Deploy via Validation `0AfVT000001ORHp0AO`)
- **Componentes promovidos:** `FSC_CreditWorkspaceController`, `FSC_CreditWorkspaceControllerTest`
- **Resumen de la Ejecución:** Éxito (`Status: Succeeded`).
  1. Se eliminó la restricción `Status = 'En proceso'` en el filtro de la pestaña `aprobaciones` y en el conteo del KPI `misPendientesDirectos`, permitiendo que aprobadores clave (como Sayris Heredia en PLA / Cumplimiento para `SOL-CRED-00061`) visualicen y dictaminen directamente las solicitudes de crédito que tienen procesos de aprobación activos aun cuando se encuentren en estado `Borrador` (`Completando información`).
  2. Se actualizaron los tests unitarios (`FSC_CreditWorkspaceControllerTest`) validando los métodos de dictamen y filtros en todos los roles con 100% de éxito (3/3 passing).
  3. Desplegado exitosamente en `vimenca-sandbox` (MergeQA), `vimenca-calidad` (QA) y `vimenca-prod` (Producción).
