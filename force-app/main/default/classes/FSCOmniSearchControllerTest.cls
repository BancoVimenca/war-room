@IsTest
private class FSCOmniSearchControllerTest {

    @TestSetup
    static void setupData() {
        // Cuenta Candidato Persona Juridica permitida
        RecordType rtPJ = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Candidato_Persona_Juridica' LIMIT 1];
        Account acc = new Account(
            Name = 'Empresa Prueba SRL',
            RecordTypeId = rtPJ.Id,
            ACC_RNC__c = '101999888'
        );
        insert acc;

        // Lead
        Lead ld = new Lead(
            FirstName = 'Prueba',
            LastName = 'OmniSearch',
            Company = 'Empresa Lead',
            Status = 'Iniciado',
            LEA_NumIdentificacion__c = '40299988812',
            LEA_TipoIdentificacion__c = 'Cédula'
        );
        insert ld;

        // Caso
        Case cs = new Case(
            Subject = 'Consulta de Saldo Prueba',
            Status = 'Nuevo',
            AccountId = acc.Id
        );
        insert cs;

        // Tarea
        Task tsk = new Task(
            Subject = 'Llamada de Seguimiento Prueba',
            Status = 'Not Started',
            WhatId = acc.Id,
            ActivityDate = Date.today().addDays(3)
        );
        insert tsk;
    }

    @IsTest
    static void testOmniSearchReturnsResults() {
        // En tests SOSL devuelve lo que se defina con Test.setFixedSearchResults
        List<Account> accounts = [SELECT Id FROM Account WHERE Name = 'Empresa Prueba SRL'];
        List<Lead> leads = [SELECT Id FROM Lead WHERE LastName = 'OmniSearch'];
        List<Case> cases = [SELECT Id FROM Case WHERE Subject = 'Consulta de Saldo Prueba'];
        List<Task> tasks = [SELECT Id FROM Task WHERE Subject = 'Llamada de Seguimiento Prueba'];

        List<Id> fixedSearchResults = new List<Id>{
            accounts[0].Id,
            leads[0].Id,
            cases[0].Id,
            tasks[0].Id
        };
        Test.setFixedSearchResults(fixedSearchResults);

        Test.startTest();
        FSCOmniSearchController.SearchResults emptyRes = FSCOmniSearchController.searchOmni('');
        System.assertEquals(0, emptyRes.totalCount, 'Búsqueda vacía debe retornar 0');

        FSCOmniSearchController.SearchResults results = FSCOmniSearchController.searchOmni('Prueba');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.totalCount > 0, 'Debe haber resultados encontrados');
        System.assertEquals(1, results.accounts.size(), 'Debe encontrar la cuenta');
        System.assertEquals(1, results.leads.size(), 'Debe encontrar el lead');
        System.assertEquals(1, results.cases.size(), 'Debe encontrar el caso');
        System.assertEquals(1, results.tasks.size(), 'Debe encontrar la tarea');
    }

    @IsTest
    static void testIsAdminHelper() {
        Test.startTest();
        Boolean adminCheck = FSCOmniSearchController.isUserAdmin();
        Test.stopTest();
        System.assertNotEquals(null, adminCheck);
    }
}