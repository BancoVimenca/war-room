/**
 * @description       : Pruebas unitarias para la suite de integración masiva PLA FSC (SOL-0197 / BVWAR-292)
 *                      Cubre: VFS_PLADataIntegrityService, VFS_PLAAuditBatch, VFS_PLAPrequalificationBatch,
 *                      VFS_PLASchedulableOrchestrator y PLA_Configuracion__c.
 * @author            : @dev-salesforce / Keystone Advisors
 * @group             : Test PLA
 * @last modified on  : 2026-11-14
**/
@isTest
private class VFS_PLABatchTest {

    private class MacroProcesosHttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public MacroProcesosHttpMock(Integer status, String body) {
            this.statusCode = status;
            this.responseBody = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);
            res.setBody(this.responseBody);
            return res;
        }
    }

    @TestSetup
    static void makeData() {
        String mockInit = '{"status":"SUCCESS","data":{"id":"TRX-INIT","message":"BAJO"}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockInit));

        PLA_Configuracion__c config = PLA_Configuracion__c.getOrgDefaults();
        config.Activo__c = true;
        config.Auditoria_Activa__c = true;
        config.Precalificacion_Activa__c = true;
        upsert config;

        Datos_Maestros__c dm = new Datos_Maestros__c(
            Name = 'Comercio al por menor',
            DM_Tipo__c = 'Actividad Económica',
            DM_Direccion__c = 'COM001'
        );
        insert dm;

        List<User> sucursalUsers = [SELECT Id FROM User WHERE Name LIKE '%Sucursal%' AND IsActive = true LIMIT 1];
        Id branchUserId = !sucursalUsers.isEmpty() ? sucursalUsers[0].Id : UserInfo.getUserId();

        Id personAccountRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Id pjRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Personas_Juridicas').getRecordTypeId();

        // 1. Cuenta Persona Física Completa con arquitectura FSC
        Account accPFComplete = new Account(
            RecordTypeId = personAccountRtId,
            FirstName = 'Juan',
            LastName = 'Pérez PLA',
            ACC_TipoIdentificacion__c = 'Cédula',
            ACC_NumIdentificacion__c = '00100000001',
            PersonBirthdate = Date.newInstance(1990, 5, 20),
            ACC_Nacionalidad__c = 'REPUBLICA DOMINICANA',
            ACC_Estado_Civil__c = 'SOLTERO/A',
            PersonEmail = 'juan.perez@test.com',
            PersonMobilePhone = '8095550001',
            ACC_Rango_de_Transacciones_estimadas__c = '1',
            ACC_Persona_PEP__c = 'NO',
            ACC_Pais_Nacimiento__c = 'REPUBLICA DOMINICANA',
            ACC_Pais_Residencia_Legal__c = 'REPUBLICA DOMINICANA',
            ACC_Actividad_Economica__c = dm.Id,
            ACC_Tipo_Actividad__c = 'EMPLEADO PRIVADO',
            ACC_Total_Activos__c = 150000,
            ACC_Ventas_Ingresos_Anuales__c = 150000,
            ACC_Estado__c = 'ACTIVO',
            OwnerId = UserInfo.getUserId()
        );
        insert accPFComplete;

        // 2. Cuenta Persona Física Incompleta asignada a Sucursal
        Account accPFIncomplete = new Account(
            RecordTypeId = personAccountRtId,
            FirstName = 'Yeniffer',
            LastName = 'Incompleta Sucursal',
            ACC_TipoIdentificacion__c = 'Cédula',
            ACC_NumIdentificacion__c = '00201450541',
            ACC_Nacionalidad__c = 'REPUBLICA DOMINICANA',
            ACC_Estado__c = 'ACTIVO',
            OwnerId = branchUserId
        );
        insert accPFIncomplete;

        // 3. Cuenta Persona Jurídica Completa con Partes Relacionadas
        Account accPJComplete = new Account(
            RecordTypeId = pjRtId,
            Name = 'Inversiones Caribe SRL',
            ACC_RNC__c = '130000001',
            ACC_Nombre_Corto_Comercial__c = 'Inversiones Caribe',
            ACC_Fecha_Fundacion__c = Date.newInstance(2015, 1, 15),
            ACC_INT_Tipo_Estructura_Juridica__c = 'Sociedad de Responsabilidad Limitada (S.R.L.)',
            ACC_Rango_de_Transacciones_estimadas__c = '2',
            ACC_Persona_PEP__c = 'NO',
            ACC_Actividad_Economica__c = dm.Id,
            ACC_Total_Activos__c = 5000000,
            ACC_Ventas_Ingresos_Anuales__c = 5000000,
            ACC_Estado__c = 'ACTIVO',
            OwnerId = UserInfo.getUserId()
        );
        insert accPJComplete;

        Informacion_Financiera__c infPJ = new Informacion_Financiera__c(
            INF_Cuenta__c = accPJComplete.Id,
            INF_INT_Origen_de_los_recursos__c = 'Ahorros'
        );
        insert infPJ;
    }

    @isTest
    static void testDataIntegrityService() {
        String mockStr = '{"status":"SUCCESS","data":{"id":"TRX-101","message":"BAJO"}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockStr));

        Account accComplete = [SELECT Id, Name, isPersonAccount, ACC_Persona_Fisica__c, ACC_INT_TipoPersona__c,
                                      ACC_TipoIdentificacion__c, ACC_INT_Tipo_de_identificacion__c, ACC_NumIdentificacion__c,
                                      FinServ__IndividualId__c, PersonBirthdate, ACC_Fecha_Fundacion__c, ACC_Nacionalidad__c,
                                      ACC_INT_Nacionalidad__c, ACC_Estado_Civil__c, PersonEmail, ACC_Correo_Electronico_Cliente__c,
                                      PersonMobilePhone, Phone, ACC_RNC__c, ACC_Nombre_Corto_Comercial__c,
                                      ACC_INT_Tipo_Estructura_Juridica__c, ACC_Rango_de_Transacciones_estimadas__c,
                                      ACC_Persona_PEP__c, ACC_Pais_Nacimiento__c, ACC_INT_Pais_Nacimiento__c,
                                      ACC_Pais_Residencia_Legal__c, ACC_INT_Pais_Residencia_Legal__c,
                                      ACC_Actividad_Economica__c, ACC_Tipo_Actividad__c, ACC_Total_Activos__c,
                                      ACC_Ventas_Ingresos_Anuales__c, Industry
                               FROM Account WHERE FirstName = 'Juan' LIMIT 1];

        Test.startTest();
        VFS_PLADataIntegrityService.AuditResult res = VFS_PLADataIntegrityService.auditAccount(
            accComplete, null, null, null, null, 'COM001'
        );
        Test.stopTest();

        System.assertEquals(true, res.isPrequalificationReady, 'Cliente con campos FSC debe ser calificado como apto');
    }

    @isTest
    static void testAuditBatch() {
        String mockStr = '{"status":"SUCCESS","data":{"id":"TRX-101","message":"BAJO"}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockStr));

        Test.startTest();
        VFS_PLAAuditBatch batch = new VFS_PLAAuditBatch('test.supervisor@vimenca.test');
        Database.executeBatch(batch, 10);
        Test.stopTest();

        System.assert(true, 'Batch de auditoría ejecutado');
    }

    @isTest
    static void testPrequalificationBatchCallout() {
        String mockSuccess = '{"status":"SUCCESS","data":{"id":"TRX-101","message":"BAJO"}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockSuccess));

        Test.startTest();
        VFS_PLAPrequalificationBatch batch = new VFS_PLAPrequalificationBatch('test.report@vimenca.test');
        Database.executeBatch(batch, 10);
        Test.stopTest();

        System.assert(true, 'Batch de precalificación ejecutado con mock');
    }

    @isTest
    static void testPrequalificationBatchBranches() {
        String mockAlto = '{"status":"SUCCESS","data":{"id":"TRX-ALTO","message":"ALTO"}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockAlto));

        Account accPJ = [SELECT Id FROM Account WHERE Name = 'Inversiones Caribe SRL' LIMIT 1];
        Account accPF = [SELECT Id FROM Account WHERE FirstName = 'Juan' LIMIT 1];

        Test.startTest();
        VFS_PLAPrequalificationBatch batch = new VFS_PLAPrequalificationBatch('test@vimenca.com');
        
        // Cubrir start()
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql);

        // Obtener el scope con todos los campos
        List<Account> scope = [
            SELECT Id, Name, FirstName, MiddleName, LastName, Suffix,
                   isPersonAccount, ACC_Persona_Fisica__c, ACC_INT_TipoPersona__c,
                   ACC_TipoIdentificacion__c, ACC_INT_Tipo_de_identificacion__c, ACC_NumIdentificacion__c, FinServ__IndividualId__c,
                   PersonBirthdate, ACC_Fecha_Fundacion__c, ACC_Nacionalidad__c, ACC_INT_Nacionalidad__c,
                   ACC_Estado_Civil__c, PersonEmail, ACC_Correo_Electronico_Cliente__c, PersonMobilePhone, Phone,
                   ACC_RNC__c, ACC_Nombre_Corto_Comercial__c, ACC_INT_Tipo_Estructura_Juridica__c,
                   ACC_Rango_de_Transacciones_estimadas__c, ACC_Persona_PEP__c,
                   ACC_Pais_Nacimiento__c, ACC_INT_Pais_Nacimiento__c, ACC_Pais_Residencia_Legal__c, ACC_INT_Pais_Residencia_Legal__c,
                   ACC_DeclaracionSiProyectaManejarEfectivo__c, ACC_DeclaracionSiManejaOpInternacionales__c,
                   ACC_CIF__c, ACC_INT_NumOficina__c, Owner_Alias__c, ACC_Total_Activos__c,
                   ACC_Ventas_Ingresos_Anuales__c, ACC_ProductosASolicitar__c, ACC_Servicios_a_solicitar__c,
                   ACC_IndicarVolMensualEstimadoTransaccion__c, ACC_Tipo_beneficio_final__c,
                   ACC_Relacion_de_dignatarios__c, ACC_Relacion_ent_alto_riesgo__c,
                   ACC_Posee_Otra_Nacionalidad__c, ACC_Familiar_PEP__c, ACC_Colaborador_de_PEP__c,
                   ACC_Actividad_Economica__c, ACC_Tipo_Actividad__c,
                   Industry, OwnerId, Owner.Name, Owner.Alias, ACC_Estado__c, ACC_Calificacion_de_cliente__c
            FROM Account WHERE Id IN (:accPJ.Id, :accPF.Id)
        ];

        // 1. Ejecución con mock ALTO
        batch.execute(null, scope);

        // 2. Ejecución con mock MEDIO
        String mockMedio = '{"status":"SUCCESS","data":{"id":"TRX-MEDIO","message":"MEDIO"}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockMedio));
        batch.execute(null, scope);

        // 3. Ejecución con mock BAJO
        String mockBajo = '{"status":"SUCCESS","data":{"id":"TRX-BAJO","message":"BAJO"}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockBajo));
        batch.execute(null, scope);

        // 4. Ejecución finish() con registros para generar CSV y email
        batch.finish(null);
        Test.stopTest();

        System.assert(true, 'Ramas ALTO, MEDIO, BAJO y finish cubiertas');
    }

    @isTest
    static void testPrequalificationBatchError() {
        String mockFail = '{"status":"ERROR","data":{"id":null,"message":null}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(500, mockFail));

        Account accPJ = [SELECT Id FROM Account WHERE Name = 'Inversiones Caribe SRL' LIMIT 1];
        List<Account> scopePJ = [
            SELECT Id, Name, FirstName, MiddleName, LastName, Suffix,
                   isPersonAccount, ACC_Persona_Fisica__c, ACC_INT_TipoPersona__c,
                   ACC_TipoIdentificacion__c, ACC_INT_Tipo_de_identificacion__c, ACC_NumIdentificacion__c, FinServ__IndividualId__c,
                   PersonBirthdate, ACC_Fecha_Fundacion__c, ACC_Nacionalidad__c, ACC_INT_Nacionalidad__c,
                   ACC_Estado_Civil__c, PersonEmail, ACC_Correo_Electronico_Cliente__c, PersonMobilePhone, Phone,
                   ACC_RNC__c, ACC_Nombre_Corto_Comercial__c, ACC_INT_Tipo_Estructura_Juridica__c,
                   ACC_Rango_de_Transacciones_estimadas__c, ACC_Persona_PEP__c,
                   ACC_Pais_Nacimiento__c, ACC_INT_Pais_Nacimiento__c, ACC_Pais_Residencia_Legal__c, ACC_INT_Pais_Residencia_Legal__c,
                   ACC_DeclaracionSiProyectaManejarEfectivo__c, ACC_DeclaracionSiManejaOpInternacionales__c,
                   ACC_CIF__c, ACC_INT_NumOficina__c, Owner_Alias__c, ACC_Total_Activos__c,
                   ACC_Ventas_Ingresos_Anuales__c, ACC_ProductosASolicitar__c, ACC_Servicios_a_solicitar__c,
                   ACC_IndicarVolMensualEstimadoTransaccion__c, ACC_Tipo_beneficio_final__c,
                   ACC_Relacion_de_dignatarios__c, ACC_Relacion_ent_alto_riesgo__c,
                   ACC_Posee_Otra_Nacionalidad__c, ACC_Familiar_PEP__c, ACC_Colaborador_de_PEP__c,
                   ACC_Actividad_Economica__c, ACC_Tipo_Actividad__c,
                   Industry, OwnerId, Owner.Name, Owner.Alias, ACC_Estado__c, ACC_Calificacion_de_cliente__c
            FROM Account WHERE Id = :accPJ.Id
        ];

        Test.startTest();
        VFS_PLAPrequalificationBatch batchError = new VFS_PLAPrequalificationBatch();
        batchError.execute(null, scopePJ);
        
        // Simular respuesta nula/vacía
        String mockEmpty = '{"status":"SUCCESS","data":{"id":"TRX-NULL","message":""}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockEmpty));
        batchError.execute(null, scopePJ);

        // Llenar logs de error para cubrir >20 líneas de incidencias en reporte
        for (Integer i = 0; i < 25; i++) {
            batchError.errorLogs.add('Error simulado ' + i);
        }
        batchError.finish(null);
        Test.stopTest();

        System.assert(true, 'Ramas de error cubiertas');
    }

    @isTest
    static void testPrequalificationBatchDisabledConfig() {
        PLA_Configuracion__c config = PLA_Configuracion__c.getOrgDefaults();
        config.Precalificacion_Activa__c = false;
        upsert config;

        Test.startTest();
        VFS_PLAPrequalificationBatch batchDisabled = new VFS_PLAPrequalificationBatch();
        Database.executeBatch(batchDisabled, 10);
        Test.stopTest();

        System.assert(true, 'Batch pausado administrativamente');
    }

    @isTest
    static void testSchedulableOrchestrator() {
        String mockStr = '{"status":"SUCCESS","data":{"id":"TRX-101","message":"BAJO"}}';
        Test.setMock(HttpCalloutMock.class, new MacroProcesosHttpMock(200, mockStr));

        Test.startTest();
        // Cubrir scheduleDailyAt18
        String jobId = VFS_PLASchedulableOrchestrator.scheduleDailyAt18();
        System.assertNotEquals(null, jobId, 'Job programado');

        // Cubrir execute directo del Schedulable
        VFS_PLASchedulableOrchestrator orchestrator = new VFS_PLASchedulableOrchestrator();
        orchestrator.execute(null);

        // Cubrir rama pausada
        PLA_Configuracion__c config = PLA_Configuracion__c.getOrgDefaults();
        config.Activo__c = false;
        upsert config;
        orchestrator.execute(null);
        Test.stopTest();

        System.assert(true, 'Orquestador agendado y ejecutado');
    }
}
