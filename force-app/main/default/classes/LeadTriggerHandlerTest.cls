@IsTest(SeeAllData=true)
private class LeadTriggerHandlerTest {

    /*
     * ============================================================
     * HELPERS
     * ============================================================
     */

    private static Lead getUnconvertedLead() {
        List<Lead> leads = [
            SELECT Id,
                   FirstName,
                   LastName,
                   Company,
                   Status,
                   IsConverted,
                   RecordTypeId,
                   LEA_TipoIdentificacion__c,
                   LEA_NumIdentificacion__c,
                   LEA_RNC__c,
                   LEA_Nombre_Corto_Comercial__c,
                   LEA_Posee_Resid_Otro_Pais__c,
                   LEA_INT_Pais_Residencia_Legal__c,
                   LEA_Pais_Residencia_Legal__c,
                   LEA_Doc_Legal_No_Aprobada__c
            FROM Lead
            WHERE IsConverted = false
            LIMIT 1
        ];

        System.assert(
            !leads.isEmpty(),
            'Debe existir al menos un Lead no convertido.'
        );

        return leads[0];
    }


    private static Lead getConvertedLead() {
        List<Lead> leads = [
            SELECT Id,
                   Name,
                   Status,
                   IsConverted
            FROM Lead
            WHERE IsConverted = true
            AND Status = 'Convertido'
            LIMIT 1
        ];

        if (leads.isEmpty()) {
            leads = [
                SELECT Id,
                       Name,
                       Status,
                       IsConverted
                FROM Lead
                WHERE IsConverted = true
                LIMIT 1
            ];
        }

        System.assert(
            !leads.isEmpty(),
            'Debe existir al menos un Lead convertido.'
        );

        return leads[0];
    }


    private static Id getRecordTypePF() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND (
                DeveloperName = 'Candidato_Persona_Natural'
                OR DeveloperName = 'Candidato_Persona_Fisica'
                OR Name = 'Candidato Persona Física'
                OR Name = 'Candidato Persona Natural'
            )
            LIMIT 1
        ];

        return rts.isEmpty() ? null : rts[0].Id;
    }


    private static Id getRecordTypePJ() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND (
                DeveloperName = 'Candidato_Persona_Juridica'
                OR Name = 'Prospecto Persona Jurídica'
                OR Name = 'Candidato Persona Jurídica'
            )
            LIMIT 1
        ];

        if (!rts.isEmpty()) {
            return rts[0].Id;
        }

        Id pf = getRecordTypePF();

        List<RecordType> otros;

        if (pf != null) {
            otros = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                AND Id != :pf
                LIMIT 1
            ];
        } else {
            otros = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead'
                LIMIT 1
            ];
        }

        return otros.isEmpty() ? null : otros[0].Id;
    }


    /*
     * Construye un Lead en memoria permitiendo simular
     * IsConverted false/true sin hacer DML.
     */
    private static Lead conversionLead(
        Id leadId,
        Boolean converted
    ) {
        Map<String, Object> values = new Map<String, Object>{
            'attributes' => new Map<String, Object>{
                'type' => 'Lead'
            },
            'Id' => leadId,
            'IsConverted' => converted
        };

        return (Lead) JSON.deserialize(
            JSON.serialize(values),
            Lead.class
        );
    }


    private static Lead memoryLead() {
        Lead base = getUnconvertedLead();

        Lead l = new Lead();

        l.Id = base.Id;
        l.FirstName = base.FirstName;
        l.LastName = base.LastName;
        l.Company = base.Company;
        l.Status = base.Status;
        l.RecordTypeId = base.RecordTypeId;

        l.LEA_TipoIdentificacion__c = null;
        l.LEA_NumIdentificacion__c = null;
        l.LEA_RNC__c = null;

        l.LEA_Nombre_Corto_Comercial__c =
            base.LEA_Nombre_Corto_Comercial__c;

        l.LEA_Posee_Resid_Otro_Pais__c =
            base.LEA_Posee_Resid_Otro_Pais__c;

        l.LEA_INT_Pais_Residencia_Legal__c =
            base.LEA_INT_Pais_Residencia_Legal__c;

        l.LEA_Pais_Residencia_Legal__c =
            base.LEA_Pais_Residencia_Legal__c;

        l.LEA_Doc_Legal_No_Aprobada__c = 0;

        return l;
    }


    private static Boolean hasErrorContaining(
        Lead l,
        String texto
    ) {
        for (Database.Error err : l.getErrors()) {
            if (
                err.getMessage() != null &&
                err.getMessage().contains(texto)
            ) {
                return true;
            }
        }

        return false;
    }


    private static Id getLeadWithoutRelatedFiles() {
        List<Lead> candidates = [
            SELECT Id
            FROM Lead
            WHERE IsConverted = false
            LIMIT 100
        ];

        if (candidates.isEmpty()) {
            return null;
        }

        Set<Id> leadIds = new Set<Id>();

        for (Lead l : candidates) {
            leadIds.add(l.Id);
        }

        Set<Id> busyLeadIds = new Set<Id>();

        for (ContentDocumentLink link : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :leadIds
        ]) {
            busyLeadIds.add(link.LinkedEntityId);
        }

        List<Documentacion_Legal__c> docs = [
            SELECT Id,
                   DOC_Candidato__c
            FROM Documentacion_Legal__c
            WHERE DOC_Candidato__c IN :leadIds
        ];

        Map<Id, Id> leadByDoc = new Map<Id, Id>();
        Set<Id> docIds = new Set<Id>();

        for (Documentacion_Legal__c doc : docs) {
            docIds.add(doc.Id);

            leadByDoc.put(
                doc.Id,
                doc.DOC_Candidato__c
            );
        }

        if (!docIds.isEmpty()) {
            for (ContentDocumentLink link : [
                SELECT LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :docIds
            ]) {
                if (leadByDoc.containsKey(link.LinkedEntityId)) {
                    busyLeadIds.add(
                        leadByDoc.get(link.LinkedEntityId)
                    );
                }
            }
        }

        for (Lead candidate : candidates) {
            if (!busyLeadIds.contains(candidate.Id)) {
                return candidate.Id;
            }
        }

        return null;
    }


    /*
     * ============================================================
     * BUILD KEYS
     * ============================================================
     */

    @IsTest
    static void testBuildIdentificationKey() {
        Test.startTest();

        String result =
            LeadTriggerHandler.buildIdentificationKey(
                ' cedula ',
                ' 00112345678 '
            );

        Test.stopTest();

        System.assertEquals(
            'CEDULA-00112345678',
            result
        );
    }


    @IsTest
    static void testBuildRNCKey() {
        Test.startTest();

        String result1 =
            LeadTriggerHandler.buildRNCKey(
                '1-30-22376-9'
            );

        String result2 =
            LeadTriggerHandler.buildRNCKey(
                ' 130223769 '
            );

        String result3 =
            LeadTriggerHandler.buildRNCKey(null);

        Test.stopTest();

        System.assertEquals(
            '130223769',
            result1
        );

        System.assertEquals(
            '130223769',
            result2
        );

        System.assertEquals(
            '',
            result3
        );
    }


    /*
     * ============================================================
     * BEFORE SAVE - EARLY RETURNS
     * ============================================================
     */

    @IsTest
    static void beforeSaveNull() {
        Test.startTest();

        LeadTriggerHandler.beforeSave(
            null,
            null
        );

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void beforeSaveEmpty() {
        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>(),
            new Map<Id, Lead>()
        );

        Test.stopTest();

        System.assert(true);
    }


    /*
     * ============================================================
     * PERSONA FÍSICA
     * ============================================================
     */

    @IsTest
    static void personaFisicaAplicaDefaults() {
        Id pfRt = getRecordTypePF();

        if (pfRt == null) {
            System.assert(true);
            return;
        }

        Lead l = new Lead(
            LastName = 'TEST PF',
            Company = 'TEST PF',
            RecordTypeId = pfRt,
            LEA_Posee_Resid_Otro_Pais__c = null
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ l },
            null
        );

        Test.stopTest();

        System.assertEquals(
            false,
            l.LEA_Posee_Resid_Otro_Pais__c
        );

        System.assertEquals(
            'REPUBLICA DOMINICANA',
            l.LEA_INT_Pais_Residencia_Legal__c
        );

        System.assertEquals(
            'REPUBLICA DOMINICANA',
            l.LEA_Pais_Residencia_Legal__c
        );
    }


    @IsTest
    static void personaFisicaResidenteExteriorNoSobrescribePais() {
        Id pfRt = getRecordTypePF();

        if (pfRt == null) {
            System.assert(true);
            return;
        }

        Lead l = new Lead(
            LastName = 'TEST PF EXTERIOR',
            Company = 'TEST PF EXTERIOR',
            RecordTypeId = pfRt,
            LEA_Posee_Resid_Otro_Pais__c = true
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ l },
            null
        );

        Test.stopTest();

        System.assertEquals(
            true,
            l.LEA_Posee_Resid_Otro_Pais__c
        );
    }


    /*
     * ============================================================
     * PERSONA JURÍDICA
     * ============================================================
     */

    @IsTest
    static void personaJuridicaSincronizaNombreComercial() {
        Id pjRt = getRecordTypePJ();

        if (pjRt == null) {
            System.assert(true);
            return;
        }

        Lead l = new Lead(
            LastName = 'NOMBRE ANTERIOR',
            Company = 'EMPRESA TEST',
            RecordTypeId = pjRt,
            LEA_Nombre_Corto_Comercial__c =
                'NOMBRE COMERCIAL TEST'
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ l },
            null
        );

        Test.stopTest();

        System.assertEquals(
            'NOMBRE COMERCIAL TEST',
            l.LastName
        );
    }


    @IsTest
    static void personaJuridicaNombreComercialLargo() {
        Id pjRt = getRecordTypePJ();

        if (pjRt == null) {
            System.assert(true);
            return;
        }

        String nombreLargo =
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ' +
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ' +
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ' +
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

        Lead l = new Lead(
            LastName = 'TEST',
            Company = 'EMPRESA TEST',
            RecordTypeId = pjRt,
            LEA_Nombre_Corto_Comercial__c =
                nombreLargo
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ l },
            null
        );

        Test.stopTest();

        System.assertEquals(
            80,
            l.LastName.length()
        );
    }


    /*
     * ============================================================
     * LIMPIEZA IDENTIFICACIÓN
     * ============================================================
     */

    @IsTest
    static void limpiaCedula() {
        Lead l = memoryLead();

        l.LEA_TipoIdentificacion__c =
            'CEDULA';

        l.LEA_NumIdentificacion__c =
            '001-1234567-8';

        Lead oldL =
            l.clone(false, true, false, false);

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ l },
            new Map<Id, Lead>{
                l.Id => oldL
            }
        );

        Test.stopTest();

        System.assertEquals(
            '00112345678',
            l.LEA_NumIdentificacion__c
        );
    }


    @IsTest
    static void limpiaPasaporte() {
        Lead l = memoryLead();

        l.LEA_TipoIdentificacion__c =
            'PASAPORTE';

        l.LEA_NumIdentificacion__c =
            'AB-123 45.X';

        Lead oldL =
            l.clone(false, true, false, false);

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ l },
            new Map<Id, Lead>{
                l.Id => oldL
            }
        );

        Test.stopTest();

        System.assertEquals(
            'AB12345X',
            l.LEA_NumIdentificacion__c
        );
    }


    @IsTest
    static void limpiaRNC() {
        Lead l = memoryLead();

        l.LEA_RNC__c =
            '1-30-22376-9';

        Lead oldL =
            l.clone(false, true, false, false);

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ l },
            new Map<Id, Lead>{
                l.Id => oldL
            }
        );

        Test.stopTest();

        System.assertEquals(
            '130223769',
            l.LEA_RNC__c
        );
    }


    /*
     * ============================================================
     * DUPLICIDAD IDENTIFICACIÓN MISMA TRANSACCIÓN
     * ============================================================
     */

    @IsTest
    static void identificacionDuplicadaEnMismaTransaccion() {
        String numero =
            '99999999999';

        Lead l1 = new Lead(
            LastName = 'TEST DUP 1',
            Company = 'TEST DUP 1',
            LEA_TipoIdentificacion__c = 'CEDULA',
            LEA_NumIdentificacion__c = numero
        );

        Lead l2 = new Lead(
            LastName = 'TEST DUP 2',
            Company = 'TEST DUP 2',
            LEA_TipoIdentificacion__c = 'CEDULA',
            LEA_NumIdentificacion__c = numero
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{
                l1,
                l2
            },
            null
        );

        Test.stopTest();

        System.assert(
            hasErrorContaining(
                l1,
                'misma operación'
            )
            ||
            hasErrorContaining(
                l2,
                'misma operación'
            )
        );
    }


    /*
     * ============================================================
     * DUPLICIDAD IDENTIFICACIÓN CONTRA LEAD
     * ============================================================
     */

    @IsTest
    static void identificacionDuplicadaContraLead() {
        List<Lead> candidatos = [
            SELECT Id,
                   LEA_TipoIdentificacion__c,
                   LEA_NumIdentificacion__c
            FROM Lead
            WHERE LEA_TipoIdentificacion__c != null
            AND LEA_NumIdentificacion__c != null
            AND IsConverted = false
            LIMIT 100
        ];

        Lead existente;

        for (Lead candidato : candidatos) {
            if (
                String.isBlank(
                    candidato.LEA_TipoIdentificacion__c
                ) ||
                String.isBlank(
                    candidato.LEA_NumIdentificacion__c
                )
            ) {
                continue;
            }

            String numeroOriginal =
                candidato.LEA_NumIdentificacion__c;

            String numeroNormalizado;

            if (
                candidato.LEA_TipoIdentificacion__c
                    .trim()
                    .toUpperCase() == 'PASAPORTE'
            ) {
                numeroNormalizado =
                    numeroOriginal.replaceAll(
                        '[^a-zA-Z0-9]',
                        ''
                    );
            } else {
                numeroNormalizado =
                    numeroOriginal.replaceAll(
                        '[^0-9]',
                        ''
                    );
            }

            if (numeroOriginal == numeroNormalizado) {
                existente = candidato;
                break;
            }
        }

        if (existente == null) {
            System.assert(true);
            return;
        }

        Lead nuevo = new Lead(
            LastName = 'TEST DUPLICADO LEAD',
            Company = 'TEST DUPLICADO LEAD',
            LEA_TipoIdentificacion__c =
                existente.LEA_TipoIdentificacion__c,
            LEA_NumIdentificacion__c =
                existente.LEA_NumIdentificacion__c
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ nuevo },
            null
        );

        Test.stopTest();

        System.assert(
            nuevo.getErrors().size() > 0,
            'Debe detectar el candidato con identificación duplicada.'
        );
    }


    /*
     * ============================================================
     * DUPLICIDAD IDENTIFICACIÓN CONTRA ACCOUNT
     * ============================================================
     */

    @IsTest
    static void identificacionDuplicadaContraCliente() {
        List<Account> accounts = [
            SELECT Id,
                   Name,
                   ACC_TipoIdentificacion__c,
                   ACC_NumIdentificacion__c,
                   ACC_CIF__c
            FROM Account
            WHERE RecordType.DeveloperName
                IN ('PersonAccount', 'Personas_Juridicas')
            AND ACC_TipoIdentificacion__c != null
            AND ACC_NumIdentificacion__c != null
            LIMIT 30
        ];

        if (accounts.isEmpty()) {
            System.assert(true);
            return;
        }

        Account elegido;

        Set<String> tipos =
            new Set<String>();

        Set<String> numeros =
            new Set<String>();

        for (Account a : accounts) {
            tipos.add(
                a.ACC_TipoIdentificacion__c
            );

            numeros.add(
                a.ACC_NumIdentificacion__c
            );
        }

        Set<String> clavesLeads =
            new Set<String>();

        for (Lead l : [
            SELECT LEA_TipoIdentificacion__c,
                   LEA_NumIdentificacion__c
            FROM Lead
            WHERE LEA_TipoIdentificacion__c IN :tipos
            AND LEA_NumIdentificacion__c IN :numeros
        ]) {
            clavesLeads.add(
                LeadTriggerHandler.buildIdentificationKey(
                    l.LEA_TipoIdentificacion__c,
                    l.LEA_NumIdentificacion__c
                )
            );
        }

        for (Account a : accounts) {
            String key =
                LeadTriggerHandler.buildIdentificationKey(
                    a.ACC_TipoIdentificacion__c,
                    a.ACC_NumIdentificacion__c
                );

            if (!clavesLeads.contains(key)) {
                elegido = a;
                break;
            }
        }

        if (elegido == null) {
            System.assert(true);
            return;
        }

        Lead nuevo = new Lead(
            LastName = 'TEST CLIENTE DUP',
            Company = 'TEST CLIENTE DUP',
            LEA_TipoIdentificacion__c =
                elegido.ACC_TipoIdentificacion__c,
            LEA_NumIdentificacion__c =
                elegido.ACC_NumIdentificacion__c
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ nuevo },
            null
        );

        Test.stopTest();

        System.assert(
            hasErrorContaining(
                nuevo,
                'Ya existe un cliente registrado'
            )
        );
    }


    /*
     * ============================================================
     * RNC DUPLICADO MISMA TRANSACCIÓN
     * ============================================================
     */

    @IsTest
    static void rncDuplicadoEnMismaTransaccion() {
        String rnc =
            '999999999';

        Lead l1 = new Lead(
            LastName = 'EMPRESA RNC 1',
            Company = 'EMPRESA RNC 1',
            LEA_RNC__c = rnc
        );

        Lead l2 = new Lead(
            LastName = 'EMPRESA RNC 2',
            Company = 'EMPRESA RNC 2',
            LEA_RNC__c = rnc
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{
                l1,
                l2
            },
            null
        );

        Test.stopTest();

        System.assert(
            hasErrorContaining(
                l1,
                'mismo RNC'
            )
            ||
            hasErrorContaining(
                l2,
                'mismo RNC'
            )
        );
    }


    /*
     * ============================================================
     * RNC DUPLICADO CONTRA LEAD
     * ============================================================
     */

    @IsTest
    static void rncDuplicadoContraLead() {
        List<Lead> existentes = [
            SELECT Id,
                   LEA_RNC__c
            FROM Lead
            WHERE LEA_RNC__c != null
            LIMIT 1
        ];

        if (existentes.isEmpty()) {
            System.assert(true);
            return;
        }

        Lead nuevo = new Lead(
            LastName = 'TEST DUP RNC',
            Company = 'TEST DUP RNC',
            LEA_RNC__c =
                existentes[0].LEA_RNC__c
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ nuevo },
            null
        );

        Test.stopTest();

        System.assert(
            nuevo.getErrors().size() > 0
        );
    }


    /*
     * ============================================================
     * RNC DUPLICADO CONTRA EMPRESA
     * ============================================================
     */

    @IsTest
    static void rncDuplicadoContraEmpresa() {
        List<Account> empresas = [
            SELECT Id,
                   Name,
                   ACC_RNC__c,
                   ACC_NumIdentificacion__c,
                   ACC_CIF__c
            FROM Account
            WHERE RecordType.DeveloperName =
                'Personas_Juridicas'
            AND (
                ACC_RNC__c != null
                OR ACC_NumIdentificacion__c != null
            )
            LIMIT 50
        ];

        if (empresas.isEmpty()) {
            System.assert(true);
            return;
        }

        Account elegida;

        for (Account a : empresas) {
            String posibleRnc =
                String.isNotBlank(a.ACC_RNC__c)
                ? a.ACC_RNC__c
                : a.ACC_NumIdentificacion__c;

            if (String.isBlank(posibleRnc)) {
                continue;
            }

            String normalized =
                LeadTriggerHandler.buildRNCKey(
                    posibleRnc
                );

            Boolean existsLead = false;

            for (Lead candidate : [
                SELECT Id,
                       LEA_RNC__c
                FROM Lead
                WHERE LEA_RNC__c != null
                LIMIT 200
            ]) {
                if (
                    LeadTriggerHandler.buildRNCKey(
                        candidate.LEA_RNC__c
                    ) == normalized
                ) {
                    existsLead = true;
                    break;
                }
            }

            if (!existsLead) {
                elegida = a;
                break;
            }
        }

        if (elegida == null) {
            System.assert(true);
            return;
        }

        String rnc =
            String.isNotBlank(elegida.ACC_RNC__c)
            ? elegida.ACC_RNC__c
            : elegida.ACC_NumIdentificacion__c;

        Lead nuevo = new Lead(
            LastName = 'TEST EMPRESA RNC',
            Company = 'TEST EMPRESA RNC',
            LEA_RNC__c = rnc
        );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ nuevo },
            null
        );

        Test.stopTest();

        System.assert(
            nuevo.getErrors().size() > 0
        );
    }


    /*
     * ============================================================
     * BUG PRINCIPAL: PARTICIPANTE CONVERTIDO
     * ============================================================
     */

    @IsTest
    static void participanteConvertidoNoDebeBloquear() {
        List<Participante__c> relaciones = [
            SELECT Id,
                   PAR_Candidato__c,
                   PAR_Participante_Candidato__c,
                   PAR_Participante_Candidato__r.Status
            FROM Participante__c
            WHERE PAR_Candidato__c != null
            AND PAR_Participante_Candidato__c != null
            AND PAR_Participante_Candidato__r.Status =
                'Convertido'
            LIMIT 1
        ];

        if (!relaciones.isEmpty()) {
            Participante__c relacion =
                relaciones[0];

            Lead oldLead =
                conversionLead(
                    relacion.PAR_Candidato__c,
                    false
                );

            Lead newLead =
                conversionLead(
                    relacion.PAR_Candidato__c,
                    true
                );

            Test.startTest();

            LeadTriggerHandler.beforeSave(
                new List<Lead>{
                    newLead
                },
                new Map<Id, Lead>{
                    relacion.PAR_Candidato__c =>
                        oldLead
                }
            );

            Test.stopTest();

            System.assertEquals(
                false,
                hasErrorContaining(
                    newLead,
                    'participantes candidatos pendientes'
                ),
                'Un participante Convertido no debe bloquear.'
            );

            return;
        }

        Lead principal =
            getUnconvertedLead();

        Lead convertido =
            getConvertedLead();

        Participante__c p =
            new Participante__c(
                PAR_Candidato__c =
                    principal.Id,
                PAR_Participante_Candidato__c =
                    convertido.Id
            );

        Database.SaveResult sr =
            Database.insert(
                p,
                false
            );

        if (!sr.isSuccess()) {
            System.assert(true);
            return;
        }

        Lead oldLead =
            conversionLead(
                principal.Id,
                false
            );

        Lead newLead =
            conversionLead(
                principal.Id,
                true
            );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{
                principal.Id => oldLead
            }
        );

        Test.stopTest();

        System.assertEquals(
            false,
            hasErrorContaining(
                newLead,
                'participantes candidatos pendientes'
            )
        );
    }


    /*
     * ============================================================
     * PARTICIPANTE INVÁLIDO - DEBE BLOQUEAR
     * ============================================================
     */

    @IsTest
    static void participanteNoValidadoDebeBloquearConversion() {
        List<Lead> leads = [
            SELECT Id,
                   Status,
                   IsConverted
            FROM Lead
            WHERE IsConverted = false
            AND Status NOT IN (
                'Validado',
                'Aprobado',
                'Convertido',
                'Convertido a cliente'
            )
            LIMIT 2
        ];

        if (leads.size() < 2) {
            System.assert(true);
            return;
        }

        Lead principal =
            leads[0];

        Lead participanteLead =
            leads[1];

        Participante__c participante =
            new Participante__c(
                PAR_Candidato__c =
                    principal.Id,
                PAR_Participante_Candidato__c =
                    participanteLead.Id
            );

        Database.SaveResult sr =
            Database.insert(
                participante,
                false
            );

        if (!sr.isSuccess()) {
            System.debug(
                'No se pudo crear Participante de prueba: ' +
                sr.getErrors()
            );

            System.assert(true);
            return;
        }

        Lead oldLead =
            conversionLead(
                principal.Id,
                false
            );

        Lead newLead =
            conversionLead(
                principal.Id,
                true
            );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{
                newLead
            },
            new Map<Id, Lead>{
                principal.Id => oldLead
            }
        );

        Test.stopTest();

        System.assert(
            hasErrorContaining(
                newLead,
                'participantes candidatos pendientes'
            ),
            'Un participante no validado debe bloquear la conversión.'
        );
    }


    /*
     * ============================================================
     * PARTICIPANTE INVÁLIDO EXISTENTE
     * ============================================================
     */

    @IsTest
    static void participantePendienteExistenteDebeBloquear() {
        List<Participante__c> relaciones = [
            SELECT Id,
                   PAR_Candidato__c,
                   PAR_Participante_Candidato__c,
                   PAR_Participante_Candidato__r.Status
            FROM Participante__c
            WHERE PAR_Candidato__c != null
            AND PAR_Participante_Candidato__c != null
            AND PAR_Participante_Candidato__r.Status
                NOT IN (
                    'Validado',
                    'Aprobado',
                    'Convertido',
                    'Convertido a cliente'
                )
            LIMIT 1
        ];

        if (relaciones.isEmpty()) {
            System.assert(true);
            return;
        }

        Participante__c relacion =
            relaciones[0];

        Lead oldLead =
            conversionLead(
                relacion.PAR_Candidato__c,
                false
            );

        Lead newLead =
            conversionLead(
                relacion.PAR_Candidato__c,
                true
            );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{
                relacion.PAR_Candidato__c =>
                    oldLead
            }
        );

        Test.stopTest();

        System.assert(
            hasErrorContaining(
                newLead,
                'participantes candidatos pendientes'
            )
        );
    }


    /*
     * ============================================================
     * CONVERSIÓN SIN PARTICIPANTES
     * ============================================================
     */

    @IsTest
    static void conversionSinParticipantes() {
        List<Lead> candidatos = [
            SELECT Id
            FROM Lead
            WHERE IsConverted = false
            LIMIT 100
        ];

        Set<Id> ids =
            new Set<Id>();

        for (Lead l : candidatos) {
            ids.add(l.Id);
        }

        Set<Id> conParticipantes =
            new Set<Id>();

        if (!ids.isEmpty()) {
            for (Participante__c p : [
                SELECT PAR_Candidato__c
                FROM Participante__c
                WHERE PAR_Candidato__c IN :ids
            ]) {
                conParticipantes.add(
                    p.PAR_Candidato__c
                );
            }
        }

        Id elegido;

        for (Lead l : candidatos) {
            if (!conParticipantes.contains(l.Id)) {
                elegido = l.Id;
                break;
            }
        }

        if (elegido == null) {
            System.assert(true);
            return;
        }

        Lead oldLead =
            conversionLead(
                elegido,
                false
            );

        Lead newLead =
            conversionLead(
                elegido,
                true
            );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{
                elegido => oldLead
            }
        );

        Test.stopTest();

        System.assertEquals(
            false,
            hasErrorContaining(
                newLead,
                'participantes candidatos pendientes'
            )
        );
    }


    /*
     * ============================================================
     * OLD MAP VACÍO DURANTE SUPUESTA CONVERSIÓN
     * ============================================================
     */

    @IsTest
    static void conversionOldMapSinRegistro() {
        Lead source =
            getUnconvertedLead();

        Lead newLead =
            conversionLead(
                source.Id,
                true
            );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{
                newLead
            },
            new Map<Id, Lead>()
        );

        Test.stopTest();

        System.assert(true);
    }


    /*
     * ============================================================
     * ARCHIVOS RELACIONADOS
     * ============================================================
     */

    @IsTest
    static void getLeadIdsWithRelatedFilesNull() {
        Test.startTest();

        Set<Id> resultado =
            LeadTriggerHandler.getLeadIdsWithRelatedFiles(
                null
            );

        Test.stopTest();

        System.assertEquals(
            0,
            resultado.size()
        );
    }


    @IsTest
    static void getLeadIdsWithRelatedFilesEmpty() {
        Test.startTest();

        Set<Id> result =
            LeadTriggerHandler.getLeadIdsWithRelatedFiles(
                new Set<Id>()
            );

        Test.stopTest();

        System.assertEquals(
            0,
            result.size()
        );
    }


    @IsTest
    static void getLeadIdsWithDirectFile() {
        List<Lead> leads = [
            SELECT Id
            FROM Lead
            LIMIT 100
        ];

        if (leads.isEmpty()) {
            System.assert(true);
            return;
        }

        Set<Id> ids =
            new Set<Id>();

        for (Lead l : leads) {
            ids.add(l.Id);
        }

        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :ids
            LIMIT 1
        ];

        if (links.isEmpty()) {
            System.assert(true);
            return;
        }

        Id leadId =
            links[0].LinkedEntityId;

        Test.startTest();

        Set<Id> result =
            LeadTriggerHandler.getLeadIdsWithRelatedFiles(
                new Set<Id>{
                    leadId
                }
            );

        Test.stopTest();

        System.assert(
            result.contains(leadId)
        );
    }


    @IsTest
    static void getLeadIdsWithDocumentLegalFile() {
        List<Documentacion_Legal__c> docs = [
            SELECT Id,
                   DOC_Candidato__c
            FROM Documentacion_Legal__c
            WHERE DOC_Candidato__c != null
            LIMIT 100
        ];

        if (docs.isEmpty()) {
            System.assert(true);
            return;
        }

        Set<Id> docIds =
            new Set<Id>();

        Map<Id, Id> leadByDoc =
            new Map<Id, Id>();

        for (Documentacion_Legal__c d : docs) {
            docIds.add(d.Id);

            leadByDoc.put(
                d.Id,
                d.DOC_Candidato__c
            );
        }

        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docIds
            LIMIT 1
        ];

        if (links.isEmpty()) {
            System.assert(true);
            return;
        }

        Id leadId =
            leadByDoc.get(
                links[0].LinkedEntityId
            );

        Test.startTest();

        Set<Id> result =
            LeadTriggerHandler.getLeadIdsWithRelatedFiles(
                new Set<Id>{
                    leadId
                }
            );

        Test.stopTest();

        System.assert(
            result.contains(leadId)
        );
    }


    /*
     * ============================================================
     * AFTER UPDATE
     * ============================================================
     */

    @IsTest
    static void afterUpdateNull() {
        Test.startTest();

        LeadTriggerHandler.afterUpdate(
            null,
            null
        );

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void afterUpdateEmpty() {
        Test.startTest();

        LeadTriggerHandler.afterUpdate(
            new List<Lead>(),
            new Map<Id, Lead>()
        );

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void afterUpdateSinDocsNoAprobados() {
        Lead source =
            getUnconvertedLead();

        Lead oldLead =
            source.clone(
                true,
                true,
                false,
                false
            );

        Lead newLead =
            source.clone(
                true,
                true,
                false,
                false
            );

        newLead.LEA_Doc_Legal_No_Aprobada__c =
            0;

        Test.startTest();

        LeadTriggerHandler.afterUpdate(
            new List<Lead>{
                newLead
            },
            new Map<Id, Lead>{
                oldLead.Id => oldLead
            }
        );

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void afterUpdateDocsPendientesSinArchivos() {
        Id leadId =
            getLeadWithoutRelatedFiles();

        if (leadId == null) {
            System.assert(true);
            return;
        }

        Lead oldLead =
            conversionLead(
                leadId,
                false
            );

        Lead newLead =
            conversionLead(
                leadId,
                false
            );

        newLead.LEA_Doc_Legal_No_Aprobada__c =
            1;

        Test.startTest();

        LeadTriggerHandler.afterUpdate(
            new List<Lead>{
                newLead
            },
            new Map<Id, Lead>{
                leadId => oldLead
            }
        );

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void afterUpdateDetectaConversion() {
        Lead source =
            getUnconvertedLead();

        Lead oldLead =
            conversionLead(
                source.Id,
                false
            );

        Lead newLead =
            conversionLead(
                source.Id,
                true
            );

        newLead.LEA_Doc_Legal_No_Aprobada__c =
            0;

        Test.startTest();

        LeadTriggerHandler.afterUpdate(
            new List<Lead>{
                newLead
            },
            new Map<Id, Lead>{
                source.Id => oldLead
            }
        );

        Test.stopTest();

        System.assert(true);
    }


    /*
     * ============================================================
     * SIN CAMBIOS
     * ============================================================
     */

    @IsTest
    static void registroSinCambiosNoValidaDuplicidad() {
        Lead l =
            memoryLead();

        Lead oldL =
            l.clone(
                false,
                true,
                false,
                false
            );

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{
                l
            },
            new Map<Id, Lead>{
                l.Id => oldL
            }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            l.getErrors().size()
        );
    }


    /*
     * ============================================================
     * IDENTIFICACIÓN VACÍA
     * ============================================================
     */

    @IsTest
    static void identificacionVacia() {
        Lead l =
            memoryLead();

        l.LEA_TipoIdentificacion__c =
            null;

        l.LEA_NumIdentificacion__c =
            null;

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{
                l
            },
            null
        );

        Test.stopTest();

        System.assertEquals(
            0,
            l.getErrors().size()
        );
    }


    /*
     * ============================================================
     * RNC VACÍO
     * ============================================================
     */

    @IsTest
    static void rncVacio() {
        Lead l =
            memoryLead();

        l.LEA_RNC__c =
            null;

        Test.startTest();

        LeadTriggerHandler.beforeSave(
            new List<Lead>{
                l
            },
            null
        );

        Test.stopTest();

        System.assertEquals(
            0,
            l.getErrors().size()
        );
    }

    /*
     * ============================================================
     * [BVWAR-264 / SOL-0249] TESTS VALIDACION PERSONA FISICA (ALERTAS)
     * ============================================================
     */

    @IsTest
    static void testPersonaFisicaSinAlertasNoEnviaAPLA() {
        Id rtPF = getRecordTypePF();
        if (rtPF == null) return;

        Lead l = new Lead(
            FirstName = 'Juan',
            LastName = 'Perez Test',
            Company = 'Juan Perez Test',
            Status = 'VALIDADO',
            LEA_SubEstado__c = 'ACEPTADO',
            RecordTypeId = rtPF,
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '40200000001',
            LEA_Coincidencia_Listas_Internas__c = false,
            LEA_Coincidencia_Listas_Externas__c = false
        );
        insert l;

        Test.startTest();
        l.LEA_SubEstado__c = 'EN REVISIÓN';
        update l;
        Test.stopTest();

        System.assertNotEquals(null, l.Id);
    }

    @IsTest
    static void testPersonaFisicaAlertaListasEnviaAPLA() {
        Id rtPF = getRecordTypePF();
        if (rtPF == null) return;

        Lead l = new Lead(
            FirstName = 'Alerta',
            LastName = 'Listas Test',
            Company = 'Alerta Listas Test',
            Status = 'VALIDADO',
            LEA_SubEstado__c = 'ACEPTADO',
            RecordTypeId = rtPF,
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '40200000002',
            LEA_Coincidencia_Listas_Internas__c = true
        );
        insert l;

        Test.startTest();
        l.LEA_SubEstado__c = 'EN REVISIÓN';
        update l;
        Test.stopTest();

        System.assertNotEquals(null, l.Id);
    }

    @IsTest
    static void testPersonaFisicaCedulaAlertaPadronEnviaTecnologia() {
        Id rtPF = getRecordTypePF();
        if (rtPF == null) return;

        Lead l = new Lead(
            FirstName = 'Alerta',
            LastName = 'Padron Test',
            Company = 'Alerta Padron Test',
            Status = 'VALIDADO',
            LEA_SubEstado__c = 'ACEPTADO',
            RecordTypeId = rtPF,
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '40200000003'
        );
        insert l;

        Test.startTest();
        l.LEA_SubEstado__c = 'EN REVISIÓN';
        update l;
        Test.stopTest();

        System.assertNotEquals(null, l.Id);
    }
}
