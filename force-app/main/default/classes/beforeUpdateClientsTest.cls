@isTest
public class beforeUpdateClientsTest {
    @isTest
    static void testHelperClassificationAndTranslations() {
        beforeUpdateClientsHelper helper = new beforeUpdateClientsHelper();
        
        // 1. Classification bands
        Account cur = new Account(
            ACC_Persona_Fisica__c = false,
            ACC_Tipo_Organizacion__c = 'CONSORCIOS',
            ACC_NumEmpleados__c = 1,
            ACC_Total_Activos__c = 1000,
            ACC_Volumen_Ventas_Anual__c = 1000
        );
        Account prev = new Account(
            ACC_Persona_Fisica__c = false,
            ACC_Tipo_Organizacion__c = 'CONSORCIOS',
            ACC_NumEmpleados__c = 2,
            ACC_Total_Activos__c = 2000,
            ACC_Volumen_Ventas_Anual__c = 2000
        );

        // Micro band
        helper.CalculateClasification(cur, prev);
        System.assertEquals('Micro', cur.ACC_Clasificacion_Empresa__c);

        // Pequeña band
        cur.ACC_NumEmpleados__c = 15;
        cur.ACC_Total_Activos__c = 5000000;
        cur.ACC_Volumen_Ventas_Anual__c = 5000000;
        helper.CalculateClasification(cur, prev);
        System.assertEquals('Pequeña', cur.ACC_Clasificacion_Empresa__c);

        // Mediana band
        cur.ACC_NumEmpleados__c = 80;
        cur.ACC_Total_Activos__c = 40000000;
        cur.ACC_Volumen_Ventas_Anual__c = 40000000;
        helper.CalculateClasification(cur, prev);
        System.assertEquals('Mediana', cur.ACC_Clasificacion_Empresa__c);

        // Corporativa band
        cur.ACC_NumEmpleados__c = 300;
        cur.ACC_Total_Activos__c = 250000000;
        cur.ACC_Volumen_Ventas_Anual__c = 250000000;
        helper.CalculateClasification(cur, prev);
        System.assertEquals('Corporativa', cur.ACC_Clasificacion_Empresa__c);

        // Reset to null on missing values
        cur.ACC_NumEmpleados__c = null;
        helper.CalculateClasification(cur, prev);
        System.assertEquals(null, cur.ACC_Clasificacion_Empresa__c);

        // Excluded organization
        cur.ACC_Tipo_Organizacion__c = 'FIDEICOMISOS';
        cur.ACC_NumEmpleados__c = 10;
        helper.CalculateClasification(cur, prev);

        // 2. Translations
        Account accPF = new Account(
            ACC_Persona_Fisica__c = true,
            ACC_Fuente_Informacion__c = 'E',
            ACC_Tipo_Persona_PF__c = 'P3',
            ACC_Tipo_Cliente_PF__c = '511'
        );
        helper.Traducir_Valores_Cliente(accPF);

        Account accPJ = new Account(
            ACC_Persona_Fisica__c = false,
            ACC_Fuente_Informacion__c = 'E',
            ACC_Tipo_Persona_PJ__c = 'J1',
            ACC_Tipo_Cliente_PJ__c = '512'
        );
        helper.Traducir_Valores_Cliente(accPJ);
    }

    @isTest(SeeAllData=true)
    static void testUpdateCIF_Logic() {
        Test.setMock(HttpCalloutMock.class, new INT007TestMock('PF'));

        Account existingAcc = [SELECT Id, RecordTypeId FROM Account WHERE isPersonAccount = true LIMIT 1];

        Id personAccountRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Id naturalRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Fisica') != null
            ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Fisica').getRecordTypeId()
            : personAccountRtId;
        Id juridicRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Juridica') != null
            ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Juridica').getRecordTypeId()
            : personAccountRtId;

        Account target = new Account(
            Id = existingAcc.Id,
            ACC_Condicion__c = 'CLIENTE',
            ACC_Estado__c = 'CREADO'
        );

        Account conditionPF = new Account(
            Id = existingAcc.Id,
            RecordTypeId = naturalRtId,
            ACC_Condicion__c = 'PROSPECTO',
            ACC_Estado__c = 'CONVERTIR'
        );

        Account conditionPJ = new Account(
            Id = existingAcc.Id,
            RecordTypeId = juridicRtId,
            ACC_Condicion__c = 'PROSPECTO',
            ACC_Estado__c = 'CONVERTIR'
        );

        Account conditionPersonAccount = new Account(
            Id = existingAcc.Id,
            RecordTypeId = personAccountRtId,
            ACC_Condicion__c = 'CLIENTE',
            ACC_Estado__c = 'CREADO'
        );

        beforeUpdateClientsHelper helper = new beforeUpdateClientsHelper();

        Test.startTest();
        // Rama 1: Candidato PF a CLIENTE
        try {
            helper.updateCIF(target, conditionPF);
        } catch (Exception e) {}

        // Rama 2: Candidato PJ a CLIENTE
        try {
            helper.updateCIF(target, conditionPJ);
        } catch (Exception e) {}

        // Rama 3: PersonAccount modification
        try {
            helper.updateCIF(target, conditionPersonAccount);
        } catch (Exception e) {}
        Test.stopTest();
    }

    @isTest
    static void testHasDemographicChanges() {
        Account a1 = new Account(FirstName = 'Juan', LastName = 'Perez');
        Account a2 = new Account(FirstName = 'Juan', LastName = 'Perez');
        Account a3 = new Account(FirstName = 'Pedro', LastName = 'Perez');

        System.assertEquals(false, beforeUpdateClientsHelper.hasDemographicChanges(a1, a2));
        System.assertEquals(true, beforeUpdateClientsHelper.hasDemographicChanges(a1, a3));
        System.assertEquals(false, beforeUpdateClientsHelper.hasDemographicChanges(null, a2));
    }
}
