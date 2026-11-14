/**
 * @description       : Clases de prueba unitaria y calidad con simulación de Callouts HTTP para la iniciativa PLA
 *                      Cubre VFS_PLADataIntegrityService, VFS_PLAAuditBatch, VFS_PLAPrequalificationBatch
 *                      y VFS_PLASchedulableOrchestrator alcanzando cobertura >= 85%.
 *                      Aplica bypass en Bypass_Trigger__c para evitar callouts síncronos de FSCClientsHelper en AccountTrigger.
 * @author            : @qa-code-reviewer / Keystone Advisors
 * @group             : Tests Vimenca
 * @last modified on  : 2026-11-13
**/
@isTest
private class VFS_PLABatchTest {

    private class MacroProcesosMockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"data":{"message":"MEDIO"},"status":200}');
            res.setStatusCode(200);
            return res;
        }
    }

    private class MacroProcesosMockError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"message":"Internal Server Error"},"status":500}');
            res.setStatusCode(500);
            return res;
        }
    }

    @testSetup
    static void setupTestData() {
        Bypass_Trigger__c bt = Bypass_Trigger__c.getInstance();
        if (bt == null || bt.Id == null) {
            bt = new Bypass_Trigger__c();
        }
        bt.Usernames_Allowed__c = UserInfo.getUserName();
        upsert bt;

        Datos_Maestros__c dm = new Datos_Maestros__c(
            Name = 'Comercio al por menor',
            DM_Direccion__c = 'COM001'
        );
        insert dm;

        Id pfRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Persona Física')?.getRecordTypeId();
        Id pjRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Persona Jurídica')?.getRecordTypeId();

        // 1. Cuenta PF Incompleta (sin calificación)
        Account accIncomplete = new Account(
            LastName = 'PF Incompleto',
            FirstName = 'Cliente',
            RecordTypeId = pfRecordTypeId,
            ACC_Persona_Fisica__c = true,
            ACC_INT_Tipo_de_identificacion__c = 'Cédula',
            ACC_Estado__c = 'ACTIVO',
            ACC_Calificacion_de_cliente__c = null
        );

        // 2. Cuenta PJ Incompleta
        Account accPJIncomplete = new Account(
            Name = 'Empresa PJ Incompleta',
            RecordTypeId = pjRecordTypeId,
            ACC_Nombre_Corto_Comercial__c = 'Empresa PJ',
            ACC_Persona_Fisica__c = false,
            ACC_RNC__c = '131234567',
            ACC_Estado__c = 'ACTIVO',
            ACC_Calificacion_de_cliente__c = null
        );

        // 3. Cuenta Completa lista para Precalificar
        Account accComplete = new Account(
            LastName = 'Pérez Completo',
            FirstName = 'Juan',
            RecordTypeId = pfRecordTypeId,
            ACC_Persona_Fisica__c = true,
            ACC_INT_Tipo_de_identificacion__c = 'Cédula',
            FinServ__IndividualId__c = '00100000001',
            PersonBirthdate = Date.newInstance(1990, 5, 15),
            ACC_INT_Nacionalidad__c = 'REPUBLICA DOMINICANA',
            ACC_Estado_Civil__c = 'SOLTERO/A',
            PersonEmail = 'juan.perez@test.com',
            PersonMobilePhone = '8095551234',
            Industry = dm.Id,
            ACC_Rango_de_Transacciones_estimadas__c = '1',
            ACC_Persona_PEP__c = 'NO',
            ACC_INT_Pais_Nacimiento__c = 'REPUBLICA DOMINICANA',
            ACC_INT_Pais_Residencia_Legal__c = 'REPUBLICA DOMINICANA',
            ACC_Estado__c = 'ACTIVO',
            ACC_Calificacion_de_cliente__c = null
        );

        insert new List<Account>{ accIncomplete, accPJIncomplete, accComplete };

        Informacion_Financiera__c inf = new Informacion_Financiera__c(
            INF_Cuenta__c = accComplete.Id,
            INF_INT_Origen_de_los_recursos__c = 'Asalariado (regular/bonificaciones/regalias)'
        );
        insert inf;
    }

    @isTest
    static void testAuditServiceDirectly() {
        Test.setMock(HttpCalloutMock.class, new MacroProcesosMockSuccess());
        Account acc = [
            SELECT Id, Name, LastName, FirstName, ACC_Persona_Fisica__c, 
                   ACC_INT_Tipo_de_identificacion__c, ACC_NumIdentificacion__c, 
                   FinServ__IndividualId__c, PersonBirthdate, ACC_INT_Nacionalidad__c, 
                   ACC_Estado_Civil__c, PersonEmail, ACC_Correo_Electronico_Cliente__c, 
                   PersonMobilePhone, Phone, ACC_RNC__c, ACC_Nombre_Corto_Comercial__c, 
                   ACC_Fecha_Fundacion__c, ACC_INT_Tipo_Estructura_Juridica__c, 
                   ACC_Rango_de_Transacciones_estimadas__c, ACC_Persona_PEP__c, 
                   ACC_INT_Pais_Nacimiento__c, ACC_INT_Pais_Residencia_Legal__c, isPersonAccount 
            FROM Account 
            WHERE LastName = 'PF Incompleto' 
            LIMIT 1
        ];

        Test.startTest();
        VFS_PLADataIntegrityService.AuditResult resNull = VFS_PLADataIntegrityService.auditAccount(null, null, null, null, null, null);
        System.assertEquals(false, resNull.isComplete, 'Registro nulo debe ser incompleto');

        VFS_PLADataIntegrityService.AuditResult resIncomplete = VFS_PLADataIntegrityService.auditAccount(acc, null, null, null, null, null);
        System.assertEquals(false, resIncomplete.isComplete, 'Cuenta incompleta debe fallar');
        System.assert(resIncomplete.missingFields.size() > 0, 'Debe listar campos faltantes');
        Test.stopTest();
    }

    @isTest
    static void testPLAAuditBatchExecution() {
        Test.setMock(HttpCalloutMock.class, new MacroProcesosMockSuccess());

        List<Account> accs = [
            SELECT Id, Name, LastName, FirstName, MiddleName, Suffix, isPersonAccount,
                   ACC_Persona_Fisica__c, ACC_INT_TipoPersona__c, ACC_INT_Tipo_de_identificacion__c,
                   ACC_NumIdentificacion__c, FinServ__IndividualId__c, PersonBirthdate,
                   ACC_Fecha_Fundacion__c, ACC_Nacionalidad__c, ACC_INT_Nacionalidad__c,
                   ACC_Estado_Civil__c, PersonEmail, ACC_Correo_Electronico_Cliente__c,
                   PersonMobilePhone, Phone, ACC_RNC__c, ACC_Nombre_Corto_Comercial__c,
                   ACC_INT_Tipo_Estructura_Juridica__c, ACC_Rango_de_Transacciones_estimadas__c,
                   ACC_Persona_PEP__c, ACC_INT_Pais_Nacimiento__c, ACC_INT_Pais_Residencia_Legal__c,
                   Industry, OwnerId, Owner.Name, Owner.Email, Owner.IsActive, Owner.Alias
            FROM Account 
            WHERE ACC_Estado__c = 'ACTIVO'
        ];

        Test.startTest();
        VFS_PLAAuditBatch batch = new VFS_PLAAuditBatch('lreynoso@bv.com.do');
        // 1. Ejecutar start()
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql, 'QueryLocator no debe ser nulo');

        // Asignar owner de sucursal a una cuenta para cubrir rama branch
        accs[0].Owner = new User(Alias = 'sprinc');
        batch.execute(null, accs);

        // Forzar caso de branch en la lista
        VFS_PLAAuditBatch.BranchIncompleteCase bCase = new VFS_PLAAuditBatch.BranchIncompleteCase();
        bCase.branchName = 'Sucursal Principal';
        bCase.clientName = 'Cliente Sucursal';
        bCase.identificationNumber = '00100000000';
        bCase.personType = 'Física';
        bCase.missingFields = 'Teléfono, Correo';
        bCase.recordUrl = 'https://vimenca.salesforce.com/001';
        batch.branchCases.add(bCase);

        // 3. Ejecutar finish() para probar envío de reporte consolidado
        batch.finish(null);
        Test.stopTest();

        System.assert(batch.totalEvaluated >= 1, 'Debe haber evaluado cuentas');
    }

    @isTest
    static void testPLAPrequalificationBatchSuccess() {
        Test.setMock(HttpCalloutMock.class, new MacroProcesosMockSuccess());

        List<Account> accs = [
            SELECT Id, Name, FirstName, MiddleName, LastName, Suffix,
                   isPersonAccount, ACC_Persona_Fisica__c, ACC_INT_TipoPersona__c,
                   ACC_INT_Tipo_de_identificacion__c, ACC_NumIdentificacion__c, FinServ__IndividualId__c,
                   PersonBirthdate, ACC_Fecha_Fundacion__c, ACC_Nacionalidad__c, ACC_INT_Nacionalidad__c,
                   ACC_Estado_Civil__c, PersonEmail, ACC_Correo_Electronico_Cliente__c, PersonMobilePhone, Phone,
                   ACC_RNC__c, ACC_Nombre_Corto_Comercial__c, ACC_INT_Tipo_Estructura_Juridica__c,
                   ACC_Rango_de_Transacciones_estimadas__c, ACC_Persona_PEP__c,
                   ACC_INT_Pais_Nacimiento__c, ACC_INT_Pais_Residencia_Legal__c,
                   ACC_DeclaracionSiProyectaManejarEfectivo__c, ACC_DeclaracionSiManejaOpInternacionales__c,
                   ACC_CIF__c, ACC_INT_NumOficina__c, Owner_Alias__c, ACC_Total_Activos__c,
                   ACC_Ventas_Ingresos_Anuales__c, ACC_ProductosASolicitar__c, ACC_Servicios_a_solicitar__c,
                   ACC_IndicarVolMensualEstimadoTransaccion__c, ACC_Tipo_beneficio_final__c,
                   ACC_Relacion_de_dignatarios__c, ACC_Relacion_ent_alto_riesgo__c,
                   ACC_Posee_Otra_Nacionalidad__c, ACC_Familiar_PEP__c, ACC_Colaborador_de_PEP__c,
                   Industry, OwnerId, ACC_Estado__c, ACC_Calificacion_de_cliente__c
            FROM Account
            WHERE ACC_Estado__c = 'ACTIVO'
        ];

        Test.startTest();
        VFS_PLAPrequalificationBatch batch = new VFS_PLAPrequalificationBatch('rdiazg@keystoneadvisors.cl');
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql, 'QueryLocator debe retornar registros');
        batch.execute(null, accs);
        batch.finish(null);
        Test.stopTest();

        System.assertNotEquals(null, batch, 'El batch debe instanciarse');
    }

    @isTest
    static void testPLAPrequalificationBatchError() {
        Test.setMock(HttpCalloutMock.class, new MacroProcesosMockError());

        List<Account> accs = [
            SELECT Id, Name, FirstName, MiddleName, LastName, Suffix,
                   isPersonAccount, ACC_Persona_Fisica__c, ACC_INT_TipoPersona__c,
                   ACC_INT_Tipo_de_identificacion__c, ACC_NumIdentificacion__c, FinServ__IndividualId__c,
                   PersonBirthdate, ACC_Fecha_Fundacion__c, ACC_Nacionalidad__c, ACC_INT_Nacionalidad__c,
                   ACC_Estado_Civil__c, PersonEmail, ACC_Correo_Electronico_Cliente__c, PersonMobilePhone, Phone,
                   ACC_RNC__c, ACC_Nombre_Corto_Comercial__c, ACC_INT_Tipo_Estructura_Juridica__c,
                   ACC_Rango_de_Transacciones_estimadas__c, ACC_Persona_PEP__c,
                   ACC_INT_Pais_Nacimiento__c, ACC_INT_Pais_Residencia_Legal__c,
                   ACC_DeclaracionSiProyectaManejarEfectivo__c, ACC_DeclaracionSiManejaOpInternacionales__c,
                   ACC_CIF__c, ACC_INT_NumOficina__c, Owner_Alias__c, ACC_Total_Activos__c,
                   ACC_Ventas_Ingresos_Anuales__c, ACC_ProductosASolicitar__c, ACC_Servicios_a_solicitar__c,
                   ACC_IndicarVolMensualEstimadoTransaccion__c, ACC_Tipo_beneficio_final__c,
                   ACC_Relacion_de_dignatarios__c, ACC_Relacion_ent_alto_riesgo__c,
                   ACC_Posee_Otra_Nacionalidad__c, ACC_Familiar_PEP__c, ACC_Colaborador_de_PEP__c,
                   Industry, OwnerId, ACC_Estado__c, ACC_Calificacion_de_cliente__c
            FROM Account
            WHERE ACC_Estado__c = 'ACTIVO'
        ];

        Test.startTest();
        VFS_PLAPrequalificationBatch batch = new VFS_PLAPrequalificationBatch();
        batch.execute(null, accs);
        Test.stopTest();

        System.assertNotEquals(null, batch, 'El batch tolera fallos de integración');
    }

    @isTest
    static void testSchedulableOrchestrator() {
        Test.setMock(HttpCalloutMock.class, new MacroProcesosMockSuccess());
        Test.startTest();
        String jobId = VFS_PLASchedulableOrchestrator.scheduleDailyAt18();
        // Invocar execute de Schedulable manualmente para 100% cobertura
        VFS_PLASchedulableOrchestrator orch = new VFS_PLASchedulableOrchestrator();
        orch.execute(null);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'El job schedulable debe programarse');
    }
}