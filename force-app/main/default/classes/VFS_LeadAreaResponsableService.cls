/**
 * Servicio Apex para resolver el Área Responsable dinámica de un Lead
 * considerando tanto el campo LEA_Area_Responsable__c como los procesos
 * de aprobación pendientes en ProcessInstanceWorkitem.
 */
public without sharing class VFS_LeadAreaResponsableService {

    public class AreaResponsableInfo {
        @AuraEnabled public String areaResponsable;
        @AuraEnabled public Boolean isNegocios;
        @AuraEnabled public Boolean isTecnologia;
        @AuraEnabled public Boolean isPLA;
        @AuraEnabled public Boolean isLegal;
        @AuraEnabled public Boolean isReadyOrApproved;
        @AuraEnabled public String messagePrefix;
        @AuraEnabled public String bannerClass;
        @AuraEnabled public String iconName;
        @AuraEnabled public String iconVariant;
    }

    @AuraEnabled(cacheable=true)
    public static AreaResponsableInfo getAreaResponsable(Id recordId) {
        if (recordId == null) {
            return buildDefaultResponse('Negocios', false);
        }

        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Account') {
            return getAccountAreaResponsable(recordId);
        }

        List<Lead> leads = [
            SELECT Id, Status, LEA_Area_Responsable__c, IsConverted, RecordType.DeveloperName,
                   LEA_Doc_Legal_No_Aprobada__c, LEA_SubEstado__c, LEA_Resultado_Validacion__c
            FROM Lead
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (leads.isEmpty()) {
            return buildDefaultResponse('Negocios', false);
        }

        Lead candidate = leads[0];

        Boolean isPJ = candidate.RecordType != null && candidate.RecordType.DeveloperName == 'Candidato_Persona_Juridica';

        // 1. REGLA MANDATORIA DE APROBACIÓN FORMAL:
        // Se considera formalmente aprobado si el Lead alcanzó Status = 'Aprobado' o sub-estado explícito de aprobación
        // (ACEPTADO / APROBADO POR LEGAL). Se desvincula LEA_Resultado_Validacion__c = 'Aprobado' porque ese campo sólo
        // refleja que la persona no posee marcas en listas restrictivas diurnas pero aún puede estar en etapa 'Iniciado'.
        Boolean isAprobadoFormal = (candidate.Status == 'Aprobado' ||
                                   candidate.LEA_SubEstado__c == 'ACEPTADO' ||
                                   candidate.LEA_SubEstado__c == 'APROBADO POR LEGAL');

        if (isAprobadoFormal) {
            String glosaAprobado = isPJ
                ? 'Aprobado PLA-Legal / Revise completitud de datos antes de convertir'
                : 'Aprobado / Listo para Conversión';
            return buildDefaultResponse(glosaAprobado, false);
        }

        // 2. REGLA RECTORA DE PROCESO DE APROBACIÓN EN CURSO (ProcessInstanceWorkitem):
        // Si el prospecto ya ingresó y se encuentra en una cola de validación activa (FSC_Legal, FSC_PLA o Tecnología),
        // dicha asignación formal prevalece de forma estricta sobre cualquier tarea histórica previa de requerimiento de PLA,
        // garantizando que el banner esté 100% sincronizado con la bandeja que efectivamente tiene el expediente.
        List<ProcessInstanceWorkitem> pendingWorkitems = [
            SELECT Id,
                   ProcessInstance.ProcessDefinition.DeveloperName,
                   Actor.Name,
                   OriginalActor.Name
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :recordId
            AND ProcessInstance.Status = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!pendingWorkitems.isEmpty()) {
            ProcessInstanceWorkitem item = pendingWorkitems[0];
            String processDevName = item.ProcessInstance.ProcessDefinition != null
                ? item.ProcessInstance.ProcessDefinition.DeveloperName
                : '';
            String actorName = item.Actor != null ? item.Actor.Name : '';

            // Si está en PA_Aprobacion_Tecnologia_LEAD o asignado a Cola Tecnología
            if (processDevName == 'PA_Aprobacion_Tecnologia_LEAD' ||
                actorName.containsIgnoreCase('Tecnolog')) {
                return buildDefaultResponse('Bandeja Tecnologia', false);
            }

            // Si está asignado a PLA
            if (actorName.containsIgnoreCase('PLA') ||
                actorName.containsIgnoreCase('Prevenci')) {
                return buildDefaultResponse('Bandeja PLA / Cumplimiento', false);
            }

            // Si está en revisión por Legal / Formalización
            if (processDevName == 'Aprobacion_de_Candidatos_por_Legal' ||
                processDevName == 'Aprobacion_de_Participantes_por_Legal_2' ||
                processDevName == 'PA_Flujo_Aprobacion_LEAD' ||
                actorName.containsIgnoreCase('Legal')) {
                return buildDefaultResponse('Bandeja Validación Legal', false);
            }
        }

        // 3. Revisar si el prospecto tiene una solicitud/tarea abierta de recaudos o información solicitada por PLA
        // Solo aplica si NO se encuentra en un proceso formal de aprobación asignado a otra área.
        List<Task> pendingPlaTasks = [
            SELECT Id, Description, CreatedDate
            FROM Task
            WHERE (WhoId = :recordId OR WhatId = :recordId)
            AND Subject LIKE 'PLA: Requerimiento%'
            AND Status != 'Completed'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!pendingPlaTasks.isEmpty()) {
            AreaResponsableInfo info = buildDefaultResponse('Negocios', false);
            info.messagePrefix = 'El prospecto posee requerimiento de información / evidencias solicitado por PLA (consulte la sección Actividad):';
            info.bannerClass = 'slds-notify slds-notify_alert slds-alert_warning alert-container';
            info.iconName = 'utility:warning';
            info.iconVariant = 'warning';
            return info;
        }

        // 4. Revisar si tiene documentos con observaciones devueltos a Negocios o en revisión por Legal
        List<AggregateResult> docCounts = [
            SELECT DOC_Estado__c estado, COUNT(Id) total
            FROM Documentacion_Legal__c
            WHERE DOC_Candidato__c = :recordId
            AND DOC_Estado__c IN ('EN REVISION LEGAL', 'DEVUELTO')
            GROUP BY DOC_Estado__c
        ];

        Integer enRevisionLegal = 0;
        Integer devueltos = 0;
        for (AggregateResult ar : docCounts) {
            String est = (String) ar.get('estado');
            Integer tot = (Integer) ar.get('total');
            if (est == 'EN REVISION LEGAL') {
                enRevisionLegal += tot;
            } else if (est == 'DEVUELTO') {
                devueltos = tot;
            }
        }

        if (devueltos > 0) {
            AreaResponsableInfo info = buildDefaultResponse('Negocios', false);
            info.messagePrefix = 'El prospecto posee observaciones legales pendientes de subsanación (diríjase a la sección Actividad para ver el detalle) por:';
            info.bannerClass = 'slds-notify slds-notify_alert slds-alert_warning alert-container';
            info.iconName = 'utility:warning';
            info.iconVariant = 'warning';
            return info;
        }

        if (enRevisionLegal > 0) {
            AreaResponsableInfo info = buildDefaultResponse('Bandeja Validación Legal', false);
            info.messagePrefix = 'El prospecto se encuentra actualmente en revisión documental por:';
            return info;
        }

        // 5. Si fue rechazado por PLA o Legal, debe volver a Negocios para subsanación
        Boolean hasUnapprovedDocs = candidate.LEA_Doc_Legal_No_Aprobada__c != null && candidate.LEA_Doc_Legal_No_Aprobada__c > 0;
        Boolean isRechazado = (candidate.LEA_SubEstado__c == 'RECHAZADO' ||
                               candidate.LEA_Resultado_Validacion__c == 'RECHAZADO' ||
                               candidate.Status == 'Rechazado');

        if (hasUnapprovedDocs || isRechazado) {
            return buildDefaultResponse('Negocios', false);
        }

        // Si es Persona Jurídica y está en etapa Validado (ej. consulta DGII completada)
        // pero aún no ha completado el flujo de aprobación PLA / Legal, la responsabilidad
        // continúa en Negocios (completar participantes, documentos y enviar a aprobación).
        if (isPJ && candidate.Status == 'Validado') {
            return buildDefaultResponse('Negocios', false);
        }

        // Para Persona Natural/Física, si ya alcanzó 'Validado' y no tiene rechazos ni aprobaciones pendientes
        if (!isPJ && candidate.Status == 'Validado') {
            return buildDefaultResponse('Aprobado / Listo para Conversión', false);
        }

        // 6. Si no tiene aprobación pendiente, verificar el campo LEA_Area_Responsable__c (si no es el default Negocios)
        if (String.isNotBlank(candidate.LEA_Area_Responsable__c) && candidate.LEA_Area_Responsable__c != 'Negocios') {
            return buildDefaultResponse(candidate.LEA_Area_Responsable__c, false);
        }

        // 7. Fallback por defecto a Negocios
        return buildDefaultResponse('Negocios', false);
    }

    private static AreaResponsableInfo getAccountAreaResponsable(Id accountId) {
        List<Account> accounts = [
            SELECT Id, ACC_Resultado_Validacion__c, ACC_SubEstado__c, ACC_Abogado_Asignado__r.Name
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            return buildDefaultResponse('Negocios', true);
        }

        Account acc = accounts[0];

        // 1. Si la cuenta ya fue aprobada formalmente
        Boolean isAprobadoFormal = (acc.ACC_SubEstado__c == 'ACEPTADO' ||
                                    acc.ACC_SubEstado__c == 'APROBADO POR LEGAL');

        if (isAprobadoFormal) {
            return buildDefaultResponse('Aprobado PLA-Legal / Revise completitud de datos antes de convertir', true);
        }

        // 2. Proceso formal de aprobación en curso sobre Account (ProcessInstanceWorkitem):
        // Prevalece sobre tareas previas para sincronía directa con las bandejas operativas.
        List<ProcessInstanceWorkitem> pendingWorkitems = [
            SELECT Id, ProcessInstance.ProcessDefinition.DeveloperName, Actor.Name
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :accountId
            AND ProcessInstance.Status = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!pendingWorkitems.isEmpty()) {
            ProcessInstanceWorkitem item = pendingWorkitems[0];
            String actorName = item.Actor != null ? item.Actor.Name : '';
            if (actorName.containsIgnoreCase('PLA') || actorName.containsIgnoreCase('Prevenci')) {
                return buildDefaultResponse('Bandeja PLA / Cumplimiento', true);
            }
            return buildDefaultResponse('Bandeja Validación Legal', true);
        }

        // 3. Revisar si tiene tarea pendiente de evidencias PLA
        List<Task> pendingPlaTasks = [
            SELECT Id, Description, CreatedDate
            FROM Task
            WHERE (WhatId = :accountId)
            AND Subject LIKE 'PLA: Requerimiento%'
            AND Status != 'Completed'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!pendingPlaTasks.isEmpty()) {
            AreaResponsableInfo info = buildDefaultResponse('Negocios', true);
            info.messagePrefix = 'El cliente posee requerimiento de información / evidencias solicitado por PLA (consulte la sección Actividad):';
            info.bannerClass = 'slds-notify slds-notify_alert slds-alert_warning alert-container';
            info.iconName = 'utility:warning';
            info.iconVariant = 'warning';
            return info;
        }

        // 4. Revisar si tiene DocumentChecklistItems devueltos o en revisión legal
        List<AggregateResult> dciCounts = [
            SELECT Status estado, COUNT(Id) total
            FROM DocumentChecklistItem
            WHERE (AccountId = :accountId OR ParentRecordId = :accountId)
            AND Status IN ('En Revisión Legal', 'DEVUELTO', 'Devuelto')
            GROUP BY Status
        ];

        Integer enRevisionLegal = 0;
        Integer devueltos = 0;
        for (AggregateResult ar : dciCounts) {
            String est = (String) ar.get('estado');
            Integer tot = (Integer) ar.get('total');
            if (est != null && est.equalsIgnoreCase('En Revisión Legal')) {
                enRevisionLegal += tot;
            } else if (est != null && est.toUpperCase().startsWith('DEVUELTO')) {
                devueltos += tot;
            }
        }

        if (devueltos > 0 || acc.ACC_Resultado_Validacion__c == 'Rechazado' || acc.ACC_SubEstado__c == 'RECHAZADO') {
            AreaResponsableInfo info = buildDefaultResponse('Negocios', true);
            info.messagePrefix = 'El cliente posee observaciones legales pendientes de subsanación (diríjase a la sección Actividad para ver el detalle) por:';
            info.bannerClass = 'slds-notify slds-notify_alert slds-alert_warning alert-container';
            info.iconName = 'utility:warning';
            info.iconVariant = 'warning';
            return info;
        }

        if (enRevisionLegal > 0 || acc.ACC_Resultado_Validacion__c == 'En revisión' || acc.ACC_Resultado_Validacion__c == 'En Revisión Legal' || acc.ACC_SubEstado__c == 'EN REVISIÓN') {
            AreaResponsableInfo info = buildDefaultResponse('Bandeja Validación Legal', true);
            info.messagePrefix = 'El cliente se encuentra actualmente en revisión documental por:';
            return info;
        }

        return buildDefaultResponse('Negocios', true);
    }

    private static AreaResponsableInfo buildDefaultResponse(String area, Boolean isAccount) {
        AreaResponsableInfo info = new AreaResponsableInfo();
        info.areaResponsable = String.isNotBlank(area) ? area : 'Negocios';
        info.isNegocios = (info.areaResponsable == 'Negocios');
        info.isTecnologia = (info.areaResponsable == 'Bandeja Tecnologia');
        info.isPLA = (info.areaResponsable == 'Bandeja PLA / Cumplimiento');
        info.isLegal = (info.areaResponsable == 'Bandeja Validación Legal');
        info.isReadyOrApproved = (info.areaResponsable == 'Aprobado PLA-Legal / Revise completitud de datos antes de convertir' ||
                                  info.areaResponsable == 'Aprobado / Listo para Conversión');

        String entityName = isAccount ? 'El cliente' : 'El prospecto';

        if (info.isNegocios) {
            info.messagePrefix = entityName + ' se encuentra actualmente en proceso de ingreso y validación de datos por:';
            info.bannerClass = 'slds-notify slds-notify_alert slds-theme_info alert-container';
            info.iconName = 'utility:info';
            info.iconVariant = 'inverse';
        } else if (info.isReadyOrApproved) {
            info.messagePrefix = entityName + ' se encuentra:';
            info.bannerClass = 'slds-notify slds-notify_alert slds-alert_success alert-container';
            info.iconName = 'utility:success';
            info.iconVariant = 'inverse';
        } else {
            info.messagePrefix = entityName + ' se encuentra actualmente en revisión por:';
            info.bannerClass = 'slds-notify slds-notify_alert slds-alert_warning alert-container';
            info.iconName = 'utility:warning';
            info.iconVariant = 'warning';
        }

        return info;
    }
}
