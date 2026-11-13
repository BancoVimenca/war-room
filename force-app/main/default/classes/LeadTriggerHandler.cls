/**
 * Name: LeadTriggerHandler
 * Description:
 *  Handler del Trigger del objeto Lead.
 *  Valida duplicidad, limpia campos de identificación,
 *  envía aprobación PLA cuando aplica y bloquea conversión si existen
 *  participantes candidatos pendientes.
 *
 * Last modified: 2026-05-15
 * Autor: Jhonny Peroza
 */
public with sharing class LeadTriggerHandler {

    public static Boolean bypassAccountUniqueValidation = false;

    @TestVisible
    private static Boolean alreadyRan = false;

    private static final String RECORD_TYPE_CANDIDATO_PERSONA_FISICA = 'Candidato Persona Física';

    private static final Set<String> ESTADOS_VALIDOS_PARTICIPANTE_CANDIDATO = new Set<String>{
        'Validado',
        'Aprobado',
        'Convertido',
        'Convertido a cliente'
    };

    public static void beforeSave(List<Lead> newList, Map<Id, Lead> oldMap) {

        System.debug('on LeadTriggerHandler.beforeSave()');
        System.debug('LeadTriggerHandler.beforeSave() newList size=' + (newList == null ? 0 : newList.size()));
        System.debug('LeadTriggerHandler.beforeSave() oldMap disponible=' + (oldMap != null));

        setDefaultPersonLeadFields(newList);
        syncCommercialNameForLegalEntity(newList);
        validateParticipantCandidatesBeforeConversion(newList, oldMap);
        cleanIdentificationFields(newList);
        validateUniqueIdentification(newList, oldMap);
        validateUniqueRNC(newList, oldMap);
    }

    public static void afterUpdate(List<Lead> newList, Map<Id, Lead> oldMap) {

        System.debug('on LeadTriggerHandler.afterUpdate()');

        if (alreadyRan) return;
        alreadyRan = true;

        if (newList == null || newList.isEmpty()) return;

        submitPLAApprovalIfNeeded(newList, oldMap);

        Set<Id> convertedLeadIds = new Set<Id>();

        for (Lead l : newList) {
            Lead oldL = (oldMap != null) ? oldMap.get(l.Id) : null;

            if (l != null && l.IsConverted == true && (oldL == null || oldL.IsConverted != true)) {
                convertedLeadIds.add(l.Id);
            }
        }

        // if (!convertedLeadIds.isEmpty()) {
        //     System.debug('Enqueue LeadConversionQueue leads=' + convertedLeadIds.size());
        //     System.enqueueJob(new LeadConversionQueue(convertedLeadIds));
        // }
    }

    private static void setDefaultPersonLeadFields(List<Lead> newList) {
        System.debug('on LeadTriggerHandler.setDefaultPersonLeadFields()');

        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> recordTypeIds = new Set<Id>();

        for (Lead l : newList) {
            if (l != null && l.RecordTypeId != null) {
                recordTypeIds.add(l.RecordTypeId);
            }
        }

        if (recordTypeIds.isEmpty()) {
            return;
        }

        Map<Id, RecordType> recordTypesById = new Map<Id, RecordType>([
            SELECT Id, Name, DeveloperName
            FROM RecordType
            WHERE Id IN :recordTypeIds
        ]);

        for (Lead l : newList) {
            if (l == null || l.RecordTypeId == null) {
                continue;
            }

            RecordType rt = recordTypesById.get(l.RecordTypeId);

            Boolean isPF = (rt != null && (
                rt.DeveloperName == 'Candidato_Persona_Natural' ||
                rt.DeveloperName == 'Candidato_Persona_Fisica' ||
                rt.Name == RECORD_TYPE_CANDIDATO_PERSONA_FISICA ||
                rt.Name == 'Candidato Persona Natural'
            ));

            if (!isPF) {
                continue;
            }

            System.debug('LeadTriggerHandler.setDefaultPersonLeadFields() aplicando defaults a Lead Id=' + l.Id);

            // Persona PEP se informa con la respuesta de la integracion PEP.
            // Sin respuesta (incluidos candidatos con pasaporte), permanece vacio.

            if (l.LEA_Posee_Resid_Otro_Pais__c == null) {
                l.LEA_Posee_Resid_Otro_Pais__c = false;
            }

            if (l.LEA_Posee_Resid_Otro_Pais__c == false) {
                l.LEA_INT_Pais_Residencia_Legal__c = 'REPUBLICA DOMINICANA';
                l.LEA_Pais_Residencia_Legal__c = 'REPUBLICA DOMINICANA';
            }
        }
    }

    private static void syncCommercialNameForLegalEntity(List<Lead> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> recordTypeIds = new Set<Id>();
        for (Lead l : newList) {
            if (l != null && l.RecordTypeId != null) {
                recordTypeIds.add(l.RecordTypeId);
            }
        }

        if (recordTypeIds.isEmpty()) {
            return;
        }

        Map<Id, RecordType> recordTypesById = new Map<Id, RecordType>([
            SELECT Id, Name, DeveloperName
            FROM RecordType
            WHERE Id IN :recordTypeIds
        ]);

        for (Lead l : newList) {
            if (l == null || l.RecordTypeId == null) {
                continue;
            }

            RecordType rt = recordTypesById.get(l.RecordTypeId);
            Boolean isPF = (rt != null && (
                rt.DeveloperName == 'Candidato_Persona_Natural' ||
                rt.DeveloperName == 'Candidato_Persona_Fisica' ||
                rt.Name == RECORD_TYPE_CANDIDATO_PERSONA_FISICA ||
                rt.Name == 'Candidato Persona Natural'
            ));

            if (!isPF && String.isNotBlank(l.LEA_Nombre_Corto_Comercial__c)) {
                String shortName = l.LEA_Nombre_Corto_Comercial__c.trim();
                l.LastName = shortName.length() > 80 ? shortName.substring(0, 80) : shortName;
            }
        }
    }

    private static void validateParticipantCandidatesBeforeConversion(List<Lead> newList, Map<Id, Lead> oldMap) {
        System.debug('on LeadTriggerHandler.validateParticipantCandidatesBeforeConversion()');

        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> leadIdsToValidate = new Set<Id>();

        for (Lead newLead : newList) {
            if (newLead == null || newLead.Id == null) {
                continue;
            }

            Lead oldLead = oldMap.get(newLead.Id);

            Boolean isRealConversion =
                oldLead != null &&
                oldLead.IsConverted == false &&
                newLead.IsConverted == true;

            System.debug(
                'LeadTriggerHandler.validateParticipantCandidatesBeforeConversion() Lead evaluado Id=' + newLead.Id +
                ', oldIsConverted=' + (oldLead == null ? null : oldLead.IsConverted) +
                ', newIsConverted=' + newLead.IsConverted +
                ', isRealConversion=' + isRealConversion
            );

            if (isRealConversion) {
                leadIdsToValidate.add(newLead.Id);
            }
        }

        System.debug('LeadTriggerHandler.validateParticipantCandidatesBeforeConversion() leadIdsToValidate=' + leadIdsToValidate);

        if (leadIdsToValidate.isEmpty()) {
            return;
        }

        List<Participante__c> invalidParticipants = [
            SELECT Id,
                   Name,
                   PAR_Candidato__c,
                   PAR_Participante_Candidato__c,
                   PAR_Participante_Candidato__r.Name,
                   PAR_Participante_Candidato__r.Status
            FROM Participante__c
            WHERE PAR_Candidato__c IN :leadIdsToValidate
            AND PAR_Participante_Candidato__c != null
            AND (
                PAR_Participante_Candidato__r.Status = null
                OR PAR_Participante_Candidato__r.Status NOT IN :ESTADOS_VALIDOS_PARTICIPANTE_CANDIDATO
            )
        ];

        System.debug('LeadTriggerHandler.validateParticipantCandidatesBeforeConversion() invalidParticipants size=' + invalidParticipants.size());

        Map<Id, List<String>> invalidParticipantNamesByLeadId = new Map<Id, List<String>>();

        for (Participante__c participant : invalidParticipants) {
            if (participant == null || participant.PAR_Candidato__c == null) {
                continue;
            }

            if (!invalidParticipantNamesByLeadId.containsKey(participant.PAR_Candidato__c)) {
                invalidParticipantNamesByLeadId.put(participant.PAR_Candidato__c, new List<String>());
            }

            String participantName = 'Participante candidato pendiente';

            if (participant.PAR_Participante_Candidato__r != null) {
                participantName =
                    String.valueOf(participant.PAR_Participante_Candidato__r.Name) +
                    ' - Estado: ' +
                    String.valueOf(participant.PAR_Participante_Candidato__r.Status);
            }

            invalidParticipantNamesByLeadId.get(participant.PAR_Candidato__c).add(participantName);

            System.debug(
                'LeadTriggerHandler.validateParticipantCandidatesBeforeConversion() participante inválido. ' +
                'leadPrincipal=' + participant.PAR_Candidato__c +
                ', participanteId=' + participant.Id +
                ', candidatoParticipante=' + participant.PAR_Participante_Candidato__c +
                ', nombreEstado=' + participantName
            );
        }

        for (Lead newLead : newList) {
            if (newLead == null || newLead.Id == null) {
                continue;
            }

            if (invalidParticipantNamesByLeadId.containsKey(newLead.Id)) {
                String participantesPendientes = String.join(
                    invalidParticipantNamesByLeadId.get(newLead.Id),
                    ', '
                );

                newLead.addError(
                    'No puede convertir este candidato porque existen participantes candidatos pendientes de validación: ' +
                    participantesPendientes +
                    '. Todos los participantes candidatos deben estar en estado Validado, Aprobado o Convertido.'
                );

                System.debug(
                    'LeadTriggerHandler.validateParticipantCandidatesBeforeConversion() addError aplicado al Lead=' +
                    newLead.Id +
                    ', participantesPendientes=' +
                    participantesPendientes
                );
            }
        }
    }

    private static void submitPLAApprovalIfNeeded(List<Lead> newList, Map<Id, Lead> oldMap) {
        System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() inicio');
        System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() newList size=' + (newList == null ? 0 : newList.size()));
        System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() oldMap disponible=' + (oldMap != null));

        if (newList == null || newList.isEmpty()) {
            System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() no hay Leads para procesar');
            return;
        }

        try {
            Set<Id> leadIdsToSubmit = new Set<Id>();

            // [BVWAR-264 / SOL-0249] Re-consultar campos de Lead requeridos para evitar SObjectException si newList viene de un SOQL parcial en tests/flows
            Set<Id> leadIdsInScope = new Set<Id>();
            for (Lead l : newList) {
                if (l != null && l.Id != null) {
                    leadIdsInScope.add(l.Id);
                }
            }

            Map<Id, Lead> freshLeads = new Map<Id, Lead>([
                SELECT Id, RecordTypeId, RecordType.DeveloperName, LEA_TipoIdentificacion__c,
                       LEA_Coincidencia_Listas_Internas__c, LEA_Coincidencia_Listas_Externas__c, LEA_Listas__c,
                       LEA_Estado_Aprobacion_Tecnologia__c, LEA_Doc_Legal_No_Aprobada__c
                FROM Lead
                WHERE Id IN :leadIdsInScope
            ]);

            Set<Id> leadIdsPFAlertPLA = new Set<Id>();
            Set<Id> leadIdsPFAlertTecnologia = new Set<Id>();

            for (Lead candidateLead : newList) {
                if (candidateLead == null || candidateLead.Id == null) {
                    continue;
                }

                Lead newLead = freshLeads.containsKey(candidateLead.Id) ? freshLeads.get(candidateLead.Id) : candidateLead;

                String rtDevName = newLead.RecordType != null ? newLead.RecordType.DeveloperName : '';
                Boolean isPersonaFisica = (rtDevName == 'Candidato_Persona_Natural' || rtDevName == 'Candidato_Persona_Fisica');

                if (isPersonaFisica) {
                    // Regla BVWAR-264: Persona Física solo va a PLA si hay alerta por listas restrictivas
                    Boolean tieneAlertaListas = (newLead.LEA_Coincidencia_Listas_Internas__c == true ||
                                                newLead.LEA_Coincidencia_Listas_Externas__c == true ||
                                                String.isNotBlank(newLead.LEA_Listas__c));
                    if (tieneAlertaListas) {
                        leadIdsPFAlertPLA.add(newLead.Id);
                    }

                    // Regla BVWAR-264: Persona Física con Cédula solo va a Tecnología si hay alerta por Padrón Electoral
                    String tipoIdent = String.isNotBlank(newLead.LEA_TipoIdentificacion__c) ? newLead.LEA_TipoIdentificacion__c.trim() : '';
                    Boolean esCedula = (tipoIdent.equalsIgnoreCase('Cedula') || tipoIdent.equalsIgnoreCase('Cédula'));
                    Boolean alertaPadronTec = (newLead.LEA_Estado_Aprobacion_Tecnologia__c == 'Pendiente');
                    if (esCedula && alertaPadronTec) {
                        leadIdsPFAlertTecnologia.add(newLead.Id);
                    }
                } else {
                    // Persona Jurídica o flujo estándar de documentación
                    Boolean tieneDocsNoAprobados =
                        newLead.LEA_Doc_Legal_No_Aprobada__c != null &&
                        newLead.LEA_Doc_Legal_No_Aprobada__c > 0;

                    if (tieneDocsNoAprobados) {
                        leadIdsToSubmit.add(newLead.Id);
                    }
                }
            }

            // Encolar aprobaciones de tecnología para Persona Física con alerta de padrón
            if (!leadIdsPFAlertTecnologia.isEmpty()) {
                System.enqueueJob(new TechnologyApprovalQueueable(leadIdsPFAlertTecnologia));
            }

            // Encolar aprobaciones PLA para Persona Física con alerta de listas
            if (!leadIdsPFAlertPLA.isEmpty()) {
                System.enqueueJob(new PLAApprovalQueueable(leadIdsPFAlertPLA));
            }

            // El archivo se carga inicialmente contra el Lead y luego se mueve al
            // registro Documentacion_Legal__c. Se contemplan ambas ubicaciones para
            // no depender del orden en que se crean los ContentDocumentLink.
            leadIdsToSubmit.retainAll(getLeadIdsWithRelatedFiles(leadIdsToSubmit));

            System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() leadIdsToSubmit=' + leadIdsToSubmit);

            if (leadIdsToSubmit.isEmpty()) {
                System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() no hay Leads para enviar a aprobación');
                return;
            }

            // La aprobacion bloquea el Lead. Se envia en una transaccion posterior
            // para permitir que todas las automatizaciones terminen el guardado.
            System.enqueueJob(new LegalApprovalQueueable(leadIdsToSubmit));

            Set<Id> leadIdsAlreadyPending = new Set<Id>();
            ProcessDefinition legalProcess = [
                SELECT Id
                FROM ProcessDefinition
                WHERE DeveloperName = 'Aprobacion_de_Candidatos_por_Legal'
                AND State = 'Active'
                LIMIT 1
            ];

            System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() query ProcessInstance Pending');

            for (ProcessInstance pi : [
                SELECT Id, TargetObjectId, Status
                FROM ProcessInstance
                WHERE TargetObjectId IN :leadIdsToSubmit
                AND ProcessDefinitionId = :legalProcess.Id
                AND Status IN ('Pending', 'Approved')
            ]) {
                leadIdsAlreadyPending.add(pi.TargetObjectId);
            }

            System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() leadIdsAlreadyPending=' + leadIdsAlreadyPending);

            // La ejecucion sincrona se conserva vacia para evitar bloquear el Lead
            // dentro de la transaccion que recalcula los documentos.
            for (Id leadId : new Set<Id>()) {
                if (leadIdsAlreadyPending.contains(leadId)) {
                    System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() Lead ya está en aprobación. leadId=' + leadId);
                    continue;
                }

                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(leadId);
                req.setSubmitterId(UserInfo.getUserId());
                req.setComments('Enviado automáticamente a revisión PLA porque posee documentos legales no aprobados.');

                System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() enviando Lead a aprobación PLA. leadId=' + leadId);

                Approval.ProcessResult result = Approval.process(req);

                System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() resultado leadId=' + leadId);
                System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() result.isSuccess=' + result.isSuccess());
                System.debug('LeadTriggerHandler.submitPLAApprovalIfNeeded() result.instanceId=' + result.getInstanceId());
            }

        } catch (Exception e) {
            System.debug('ERROR LeadTriggerHandler.submitPLAApprovalIfNeeded: ' + e.getMessage());
            System.debug(e.getStackTraceString());
            throw e;
        }
    }

    private class TechnologyApprovalQueueable implements Queueable {
        private Set<Id> leadIds;
        public TechnologyApprovalQueueable(Set<Id> candidateIds) {
            this.leadIds = candidateIds == null ? new Set<Id>() : new Set<Id>(candidateIds);
        }
        public void execute(QueueableContext context) {
            if (leadIds.isEmpty()) return;
            for (Id leadId : leadIds) {
                try {
                    Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                    req.setObjectId(leadId);
                    req.setProcessDefinitionNameOrId('PA_Aprobacion_Tecnologia_LEAD');
                    req.setSubmitterId(UserInfo.getUserId());
                    req.setComments('Enviado a revisión de Tecnología por alerta/rechazo de validación en Padrón Electoral.');
                    Approval.process(req);
                } catch (Exception ex) {
                    System.debug(LoggingLevel.WARN, 'Aprobación Tecnología ya pendiente o error: ' + ex.getMessage());
                }
            }
        }
    }

    private class PLAApprovalQueueable implements Queueable {
        private Set<Id> leadIds;
        public PLAApprovalQueueable(Set<Id> candidateIds) {
            this.leadIds = candidateIds == null ? new Set<Id>() : new Set<Id>(candidateIds);
        }
        public void execute(QueueableContext context) {
            if (leadIds.isEmpty()) return;
            for (Id leadId : leadIds) {
                try {
                    Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                    req.setObjectId(leadId);
                    req.setProcessDefinitionNameOrId('Aprobacion_de_Candidatos_por_Legal');
                    req.setSubmitterId(UserInfo.getUserId());
                    req.setComments('Enviado a revisión PLA por coincidencia de alerta en listas restrictivas.');
                    Approval.process(req);
                } catch (Exception ex) {
                    System.debug(LoggingLevel.WARN, 'Aprobación PLA ya pendiente o error: ' + ex.getMessage());
                }
            }
        }
    }

    private class LegalApprovalQueueable implements Queueable {
        private Set<Id> leadIds;

        private LegalApprovalQueueable(Set<Id> candidateIds) {
            leadIds = candidateIds == null ? new Set<Id>() : new Set<Id>(candidateIds);
        }

        public void execute(QueueableContext context) {
            if (leadIds.isEmpty()) {
                return;
            }

            ProcessDefinition legalProcess = [
                SELECT Id
                FROM ProcessDefinition
                WHERE DeveloperName = 'Aprobacion_de_Candidatos_por_Legal'
                AND State = 'Active'
                LIMIT 1
            ];

            Set<Id> pendingLeadIds = new Set<Id>();
            for (ProcessInstance instance : [
                SELECT TargetObjectId
                FROM ProcessInstance
                WHERE TargetObjectId IN :leadIds
                AND ProcessDefinitionId = :legalProcess.Id
                AND Status IN ('Pending', 'Approved')
            ]) {
                pendingLeadIds.add(instance.TargetObjectId);
            }

            for (Id leadId : leadIds) {
                if (pendingLeadIds.contains(leadId)) {
                    continue;
                }

                Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
                request.setObjectId(leadId);
                request.setProcessDefinitionNameOrId('Aprobacion_de_Candidatos_por_Legal');
                request.setSubmitterId(UserInfo.getUserId());
                request.setComments(
                    'Enviado automaticamente a revision PLA porque posee documentos legales no aprobados.'
                );

                Approval.ProcessResult result = Approval.process(request);
                if (!result.isSuccess()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'No se pudo enviar el candidato a aprobacion. leadId=' + leadId +
                        ', errors=' + result.getErrors()
                    );
                }
            }
        }
    }

    @TestVisible
    private static Set<Id> getLeadIdsWithRelatedFiles(Set<Id> leadIds) {
        Set<Id> result = new Set<Id>();

        if (leadIds == null || leadIds.isEmpty()) {
            return result;
        }

        Map<Id, Id> documentLeadById = new Map<Id, Id>();
        Set<Id> linkedEntityIds = new Set<Id>();
        linkedEntityIds.addAll(leadIds);

        for (Documentacion_Legal__c document : [
            SELECT Id, DOC_Candidato__c
            FROM Documentacion_Legal__c
            WHERE DOC_Candidato__c IN :leadIds
        ]) {
            documentLeadById.put(document.Id, document.DOC_Candidato__c);
            linkedEntityIds.add(document.Id);
        }

        for (ContentDocumentLink link : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :linkedEntityIds
        ]) {
            if (leadIds.contains(link.LinkedEntityId)) {
                result.add(link.LinkedEntityId);
            } else if (documentLeadById.containsKey(link.LinkedEntityId)) {
                result.add(documentLeadById.get(link.LinkedEntityId));
            }
        }

        System.debug(
            'LeadTriggerHandler.getLeadIdsWithRelatedFiles() leadIds=' +
            leadIds +
            ', result=' +
            result
        );
        return result;
    }

    private static void cleanIdentificationFields(List<Lead> newList) {
        System.debug('on LeadTriggerHandler.cleanIdentificationFields()');

        if (newList == null || newList.isEmpty()) {
            return;
        }

        for (Lead l : newList) {
            if (l == null) {
                continue;
            }

            if (l.LEA_NumIdentificacion__c != null) {
                String invalidCharacters = isPassport(l.LEA_TipoIdentificacion__c)
                    ? '[^a-zA-Z0-9]'
                    : '[^0-9]';

                l.LEA_NumIdentificacion__c =
                    l.LEA_NumIdentificacion__c.replaceAll(invalidCharacters, '');
            }

            if (l.LEA_RNC__c != null) {
                l.LEA_RNC__c = l.LEA_RNC__c.replaceAll('[^0-9]', '');
            }
        }
    }

    private static void validateUniqueIdentification(List<Lead> newList, Map<Id, Lead> oldMap) {
        System.debug('on LeadTriggerHandler.validateUniqueIdentification()');

        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<String> tiposIdentificacion = new Set<String>();
        Set<String> numerosIdentificacion = new Set<String>();
        Set<String> clavesEnTransaccion = new Set<String>();
        Set<String> clavesDuplicadasEnTransaccion = new Set<String>();
        Set<Id> leadIdsActuales = new Set<Id>();
        List<Lead> leadsAValidar = new List<Lead>();

        for (Lead l : newList) {
            if (l == null) {
                continue;
            }

            if (l.Id != null) {
                leadIdsActuales.add(l.Id);
            }

            Lead oldLead =
                (oldMap != null && l.Id != null)
                ? oldMap.get(l.Id)
                : null;

            Boolean isConverting =
                oldLead != null &&
                oldLead.IsConverted == false &&
                l.IsConverted == true;

            Boolean debeValidar =
                oldMap == null ||
                !oldMap.containsKey(l.Id) ||
                isConverting;

            if (!debeValidar && oldLead != null) {
                debeValidar =
                    oldLead != null &&
                    (
                        l.LEA_TipoIdentificacion__c != oldLead.LEA_TipoIdentificacion__c ||
                        l.LEA_NumIdentificacion__c != oldLead.LEA_NumIdentificacion__c
                    );
            }

            if (!debeValidar) {
                continue;
            }

            if (
                String.isBlank(l.LEA_TipoIdentificacion__c) ||
                String.isBlank(l.LEA_NumIdentificacion__c)
            ) {
                continue;
            }

            leadsAValidar.add(l);

            String clave =
                buildIdentificationKey(
                    l.LEA_TipoIdentificacion__c,
                    l.LEA_NumIdentificacion__c
                );

            if (clavesEnTransaccion.contains(clave)) {
                clavesDuplicadasEnTransaccion.add(clave);
            }

            clavesEnTransaccion.add(clave);
            tiposIdentificacion.add(l.LEA_TipoIdentificacion__c);
            numerosIdentificacion.add(l.LEA_NumIdentificacion__c);
        }

        if (leadsAValidar.isEmpty()) {
            return;
        }

        for (Lead l : leadsAValidar) {
            String clave =
                buildIdentificationKey(
                    l.LEA_TipoIdentificacion__c,
                    l.LEA_NumIdentificacion__c
                );

            if (clavesDuplicadasEnTransaccion.contains(clave)) {
                l.addError(
                    'Ya existe otro candidato en esta misma operación con el mismo tipo y número de identificación.'
                );
            }
        }

        if (tiposIdentificacion.isEmpty() || numerosIdentificacion.isEmpty()) {
            return;
        }

        System.debug('Query Lead - Validar combinación tipo/número de identificación');

        List<Lead> leadsExistentes = [
            SELECT Id,
                   LEA_TipoIdentificacion__c,
                   LEA_NumIdentificacion__c
            FROM Lead
            WHERE LEA_TipoIdentificacion__c IN :tiposIdentificacion
            AND LEA_NumIdentificacion__c IN :numerosIdentificacion
        ];

        System.debug('leadsExistentes size: ' + leadsExistentes.size());

        Set<String> clavesExistentes = new Set<String>();

        for (Lead existente : leadsExistentes) {
            if (leadIdsActuales.contains(existente.Id)) {
                continue;
            }

            clavesExistentes.add(
                buildIdentificationKey(
                    existente.LEA_TipoIdentificacion__c,
                    existente.LEA_NumIdentificacion__c
                )
            );
        }

        // Validar también contra cuentas existentes SOLO de clientes reales (Persona Física o Persona Jurídica)
        List<Account> cuentasExistentes = [
            SELECT Id,
                   Name,
                   ACC_TipoIdentificacion__c,
                   ACC_NumIdentificacion__c,
                   ACC_CIF__c
            FROM Account
            WHERE RecordType.DeveloperName IN ('PersonAccount', 'Personas_Juridicas')
            AND ACC_TipoIdentificacion__c IN :tiposIdentificacion
            AND ACC_NumIdentificacion__c IN :numerosIdentificacion
        ];

        Set<String> clavesCuentasExistentes = new Set<String>();
        Map<String, Account> mapCuentasPorClave = new Map<String, Account>();

        for (Account acc : cuentasExistentes) {
            String cKey =
                buildIdentificationKey(
                    acc.ACC_TipoIdentificacion__c,
                    acc.ACC_NumIdentificacion__c
                );

            clavesCuentasExistentes.add(cKey);

            if (!mapCuentasPorClave.containsKey(cKey)) {
                mapCuentasPorClave.put(cKey, acc);
            }
        }

        for (Lead l : leadsAValidar) {
            String clave =
                buildIdentificationKey(
                    l.LEA_TipoIdentificacion__c,
                    l.LEA_NumIdentificacion__c
                );

            if (clavesExistentes.contains(clave)) {
                l.addError(
                    'Ya existe un candidato con el mismo tipo y número de identificación.'
                );

            } else if (!bypassAccountUniqueValidation && clavesCuentasExistentes.contains(clave)) {
                Account acc = mapCuentasPorClave.get(clave);

                // Si el lead está siendo convertido hacia esta misma cuenta existente, permitirlo
                Boolean isConvertingToThisAccount = (l.IsConverted && l.ConvertedAccountId == acc.Id);

                if (!isConvertingToThisAccount) {
                    String cifInfo =
                        String.isNotBlank(acc.ACC_CIF__c)
                        ? ' (CIF: ' + acc.ACC_CIF__c + ')'
                        : '';

                    l.addError(
                        'Ya existe un cliente registrado con este tipo y número de identificación: ' +
                        acc.Name +
                        cifInfo +
                        '. No es posible crear el candidato.'
                    );
                }
            }
        }
    }

    private static void validateUniqueRNC(List<Lead> newList, Map<Id, Lead> oldMap) {
        System.debug('on LeadTriggerHandler.validateUniqueRNC()');

        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<String> rncs = new Set<String>();
        Set<String> rncsEnTransaccion = new Set<String>();
        Set<String> rncsDuplicadosEnTransaccion = new Set<String>();
        Set<Id> leadIdsActuales = new Set<Id>();
        List<Lead> leadsAValidar = new List<Lead>();

        for (Lead l : newList) {
            if (l == null) {
                continue;
            }

            if (l.Id != null) {
                leadIdsActuales.add(l.Id);
            }

            Lead oldLead =
                (oldMap != null && l.Id != null)
                ? oldMap.get(l.Id)
                : null;

            Boolean isConverting =
                oldLead != null &&
                oldLead.IsConverted == false &&
                l.IsConverted == true;

            Boolean debeValidar =
                oldMap == null ||
                !oldMap.containsKey(l.Id) ||
                isConverting;

            if (!debeValidar && oldLead != null) {
                debeValidar =
                    oldLead != null &&
                    l.LEA_RNC__c != oldLead.LEA_RNC__c;
            }

            if (!debeValidar) {
                continue;
            }

            if (String.isBlank(l.LEA_RNC__c)) {
                continue;
            }

            leadsAValidar.add(l);

            String rncNormalizado = buildRNCKey(l.LEA_RNC__c);

            if (rncsEnTransaccion.contains(rncNormalizado)) {
                rncsDuplicadosEnTransaccion.add(rncNormalizado);
            }

            rncsEnTransaccion.add(rncNormalizado);
            rncs.add(rncNormalizado);
        }

        if (leadsAValidar.isEmpty()) {
            return;
        }

        for (Lead l : leadsAValidar) {
            String rncNormalizado = buildRNCKey(l.LEA_RNC__c);

            if (rncsDuplicadosEnTransaccion.contains(rncNormalizado)) {
                l.addError(
                    'Ya existe otro candidato en esta misma operación con el mismo RNC.'
                );
            }
        }

        if (rncs.isEmpty()) {
            return;
        }

        System.debug('Query Lead - Validar duplicidad de RNC');

        List<Lead> leadsExistentes = [
            SELECT Id,
                   LEA_RNC__c
            FROM Lead
            WHERE LEA_RNC__c IN :rncs
        ];

        System.debug(
            'leadsExistentes por RNC size: ' +
            leadsExistentes.size()
        );

        Set<String> rncsExistentes = new Set<String>();

        for (Lead existente : leadsExistentes) {
            if (leadIdsActuales.contains(existente.Id)) {
                continue;
            }

            if (String.isBlank(existente.LEA_RNC__c)) {
                continue;
            }

            rncsExistentes.add(
                buildRNCKey(existente.LEA_RNC__c)
            );
        }

        // Validar también contra cuentas SOLO Persona Jurídica existentes por RNC / Identificación
        // Se buscan las combinaciones posibles (con y sin formato) consultando tanto ACC_RNC__c como ACC_NumIdentificacion__c
        Set<String> searchPatterns = new Set<String>();

        for (String r : rncs) {
            searchPatterns.add(r);

            if (r.length() == 9) {
                // Formato estándar RNC República Dominicana: X-XX-XXXXX-X
                searchPatterns.add(
                    r.substring(0, 1) +
                    '-' +
                    r.substring(1, 3) +
                    '-' +
                    r.substring(3, 8) +
                    '-' +
                    r.substring(8)
                );
            }
        }

        List<Account> cuentasExistentesRnc = [
            SELECT Id,
                   Name,
                   ACC_NumIdentificacion__c,
                   ACC_RNC__c,
                   ACC_CIF__c
            FROM Account
            WHERE RecordType.DeveloperName = 'Personas_Juridicas'
            AND (
                ACC_NumIdentificacion__c IN :searchPatterns
                OR ACC_RNC__c IN :searchPatterns
            )
        ];

        Set<String> rncsCuentasExistentes = new Set<String>();
        Map<String, Account> mapCuentasPorRnc = new Map<String, Account>();

        for (Account acc : cuentasExistentesRnc) {

            if (String.isNotBlank(acc.ACC_RNC__c)) {
                String rKey = buildRNCKey(acc.ACC_RNC__c);

                rncsCuentasExistentes.add(rKey);

                if (!mapCuentasPorRnc.containsKey(rKey)) {
                    mapCuentasPorRnc.put(rKey, acc);
                }
            }

            if (String.isNotBlank(acc.ACC_NumIdentificacion__c)) {
                String rKey =
                    buildRNCKey(acc.ACC_NumIdentificacion__c);

                rncsCuentasExistentes.add(rKey);

                if (!mapCuentasPorRnc.containsKey(rKey)) {
                    mapCuentasPorRnc.put(rKey, acc);
                }
            }
        }

        for (Lead l : leadsAValidar) {
            String rncNormalizado =
                buildRNCKey(l.LEA_RNC__c);

            if (rncsExistentes.contains(rncNormalizado)) {
                l.addError(
                    'Ya existe un candidato Persona Jurídica con el mismo RNC.'
                );

            } else if (!bypassAccountUniqueValidation && rncsCuentasExistentes.contains(rncNormalizado)) {
                Account acc =
                    mapCuentasPorRnc.get(rncNormalizado);

                Boolean isConvertingToThisAccount = (l.IsConverted && l.ConvertedAccountId == acc.Id);

                if (!isConvertingToThisAccount) {
                    String cifInfo =
                        String.isNotBlank(acc.ACC_CIF__c)
                        ? ' (CIF: ' + acc.ACC_CIF__c + ')'
                        : '';

                    l.addError(
                        'Ya existe una empresa registrada con este RNC: ' +
                        acc.Name +
                        cifInfo +
                        '. No es posible crear el candidato.'
                    );
                }
            }
        }
    }

    @TestVisible
    private static String buildIdentificationKey(
        String tipoIdentificacion,
        String numeroIdentificacion
    ) {
        System.debug(
            'on LeadTriggerHandler.buildIdentificationKey()'
        );

        return String.valueOf(tipoIdentificacion)
            .trim()
            .toUpperCase() +
            '-' +
            String.valueOf(numeroIdentificacion)
                .trim()
                .toUpperCase();
    }

    @TestVisible
    private static String buildRNCKey(String rnc) {
        System.debug(
            'on LeadTriggerHandler.buildRNCKey()'
        );

        if (rnc == null) {
            return '';
        }

        return rnc.replaceAll('[^0-9]', '').trim();
    }

    private static Boolean isPassport(String tipoIdentificacion) {
        System.debug(
            'on LeadTriggerHandler.isPassport()'
        );

        return String.valueOf(tipoIdentificacion)
            .trim()
            .toUpperCase() == 'PASAPORTE';
    }
}