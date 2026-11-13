/**
 * @description       : Orquestador Schedulable Apex para la ejecución nocturna del motor PLA
 *                      Gobernanza de ventana operativa: Se activa a las 18:00 hrs y coordina:
 *                      1. Batch de Auditoría de Calidad y Alertas (VFS_PLAAuditBatch).
 *                      2. Batch de Precalificación Masiva Asíncrona (VFS_PLAPrequalificationBatch).
 * @author            : @dev-salesforce / Keystone Advisors
 * @group             : PLA Vimenca
 * @last modified on  : 2026-11-13
**/
public with sharing class VFS_PLASchedulableOrchestrator implements Schedulable {

    public void execute(SchedulableContext sc) {
        // Scope calibrado de 25 registros para proteger límites SOQL (máx 75 por lote) y Callouts (máx 25 por lote)
        Integer scopeSize = 25;

        // 1. Ejecutar Batch de Auditoría y Notificaciones
        VFS_PLAAuditBatch auditBatch = new VFS_PLAAuditBatch('lreynoso@bv.com.do');
        Database.executeBatch(auditBatch, scopeSize);

        // 2. Ejecutar Batch de Precalificación Masiva PLA
        VFS_PLAPrequalificationBatch prequalBatch = new VFS_PLAPrequalificationBatch('rdiazg@keystoneadvisors.cl');
        Database.executeBatch(prequalBatch, scopeSize);
    }

    /**
     * @description Programa la ejecución diaria automática a las 18:00 hrs (Lunes a Domingo)
     */
    public static String scheduleDailyAt18() {
        String cronExp = '0 0 18 * * ?'; // Diario a las 18:00 hrs
        return System.schedule('VFS_PLA_Nocturno_18hrs', cronExp, new VFS_PLASchedulableOrchestrator());
    }
}

