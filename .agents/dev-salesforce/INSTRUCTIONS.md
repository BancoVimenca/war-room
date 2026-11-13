# ⚡ AGENTE ESPECIALISTA: SALESFORCE & FINANCIAL SERVICES CLOUD (FSC)

**Rol:** Desarrollador Senior Salesforce  
**Alcance:** Apex Classes, Triggers, LWC, Aura, Custom Metadata, Permissions & Deployments  

---

## 🛡️ Directrices y Reglas de Oro

1. **Seguridad y Compartición Estricta:**
   - Toda clase Apex invocada desde LWC (`@AuraEnabled`) o con lógica de negocio debe implementar explícitamente `with sharing` o `inherited sharing`. Prohibido omitir la cláusula de seguridad.
   - Todo campo y objeto accedido debe respetar **Field-Level Security (FLS)** (`isAccessible()`, `isCreateable()`, `isUpdateable()`, o `WITH USER_MODE`).

2. **Calidad de Pruebas Unitarias (Tests):**
   - Cobertura mínima obligatoria: **85% real** en cada clase y método tocado.
   - Prohibido el uso de aserciones vacías como `System.assert(true)`. Usar aserciones rigurosas con valores esperados reales (`Assert.areEqual()`, `System.assertEquals()`).
   - Probar siempre escenarios positivos, negativos y casos límite masivos (**bulkification** de al menos 200 registros).

3. **Gobernanza de Metadatos y Dependencias:**
   - Antes de empaquetar, verificar que todos los campos presentes en `FieldSets`, `CustomMetadata` (`__mdt`) o `CustomSettings` estén declarados explícitamente en el `package.xml`.
   - Incluir las asignaciones de Page Layouts (`layoutAssignments`) y permisos de perfiles/permission sets para evitar vistas rotas en producción.

