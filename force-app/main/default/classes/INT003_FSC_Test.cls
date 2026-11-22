@SuppressWarnings('PMD')
@isTest
private with sharing class INT003_FSC_Test {

    private class BlacklistHttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public BlacklistHttpMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setStatus(this.statusCode == 200 ? 'OK' : 'Error');
            res.setBody(this.responseBody);
            return res;
        }
    }

    @TestSetup
    static void setupData() {
        Matriz_lista_control__c matriz = new Matriz_lista_control__c(
            MAT_Coincidencia_en_listas_externas__c = 'N',
            MAT_Coincidencia_en_listas__c = 'N',
            MAT_Resultado_validacion__c = 'Aprobado',
            MAT_Estado__c = 'CREADO',
            MAT_Sub_estado__c = 'Aceptado'
        );
        insert matriz;
    }

    @isTest
    static void testValidatePF_Success() {
        List<Account> accList = TestDataFactory_FSC.createPersonAccounts(1);
        accList[0].FinServ__IndividualId__c = '00100058007';
        accList[0].ACC_TipoIdentificacion__c = 'Cédula';
        accList[0].ACC_Condicion__c = 'CLIENTE';
        accList[0].ACC_Estado__c = 'CREADO';
        accList[0].PersonBirthdate = Date.newInstance(1990, 5, 20);
        update accList;

        String jsonResp = '{"responseCode":"0","responseDesc":"OK","internalCoincidences":"N","externalCoincidences":"N","FoundList":"","cumplo360Relevancia":85}';
        Test.setMock(HttpCalloutMock.class, new BlacklistHttpMock(200, jsonResp));

        Test.startTest();
        INT003_FSC.validatePF(accList[0].Id);
        Test.stopTest();

        Account updated = [SELECT Id, ACC_Coincidencia_Listas_Internas__c, ACC_Coincidencia_Listas_Externas__c, ACC_Cumplo360_Relevancia__c, ACC_Resultado_Validacion__c FROM Account WHERE Id = :accList[0].Id];
        System.assertEquals(false, updated.ACC_Coincidencia_Listas_Internas__c);
        System.assertEquals(false, updated.ACC_Coincidencia_Listas_Externas__c);
        System.assertEquals(85, updated.ACC_Cumplo360_Relevancia__c);
        System.assertEquals('Aprobado', updated.ACC_Resultado_Validacion__c);
    }

    @isTest
    static void testValidatePF_ErrorHttp() {
        List<Account> accList = TestDataFactory_FSC.createPersonAccounts(1);
        accList[0].ACC_NumIdentificacion__c = '40212345678';
        accList[0].ACC_TipoIdentificacion__c = 'Pasaporte';
        update accList;

        Test.setMock(HttpCalloutMock.class, new BlacklistHttpMock(500, 'Internal Server Error'));

        Test.startTest();
        INT003_FSC.validatePF(accList[0].Id);
        Test.stopTest();
    }

    @isTest
    static void testConstructorAndReturnResponse() {
        List<Account> accList = TestDataFactory_FSC.createPersonAccounts(1);
        Test.setMock(HttpCalloutMock.class, new BlacklistHttpMock(200, '{"responseCode":"0"}'));

        Test.startTest();
        INT003_FSC instance = new INT003_FSC(accList[0].Id);
        INT003_FSC.Response resp = instance.returnResponse();
        Test.stopTest();
    }

    @isTest
    static void testParseAndLegacyXML() {
        String jsonResp = '{"responseCode":"0","responseDesc":"OK","internalCoincidences":"Y","externalCoincidences":"N","FoundList":"OFAC","cumplo360Relevancia":95}';
        INT003_FSC.Response rJson = INT003_FSC.parse(jsonResp);
        System.assertEquals('000', rJson.errorCode);
        System.assertEquals('Y', rJson.values.get('CoincidenciaLI'));
        System.assertEquals(95, rJson.cumplo360Relevancia);

        String xmlResp = '<ErrorCode>000</ErrorCode><ErrorText>OK</ErrorText><CoincidenciaLI>N</CoincidenciaLI><CoincidenciaLE>N</CoincidenciaLE><Listas></Listas>';
        INT003_FSC.Response rXml = INT003_FSC.parse(xmlResp);
        System.assertEquals('000', rXml.errorCode);
        System.assertEquals('N', rXml.values.get('CoincidenciaLI'));

        INT003_FSC.Response rEmpty = INT003_FSC.parse('');
        System.assertEquals('999', rEmpty.errorCode);

        INT003_FSC.Response rInvalid = INT003_FSC.parse('{not_a_json}');
        System.assertEquals('999', rInvalid.errorCode);
    }

    @isTest
    static void testFillXML_Helper() {
        Account acc = new Account(
            Name = 'TEST EMPRESA',
            ACC_NumIdentificacion__c = '40200000001',
            ACC_TipoIdentificacion__c = 'Cédula'
        );
        Account accRnc = new Account(
            Name = 'TEST RNC',
            ACC_RNC__c = '131000001',
            ACC_TipoIdentificacion__c = 'RNC'
        );
        String template = '<Function><Parameter01>[function_firstName]</Parameter01><Parameter02>[function_document]</Parameter02></Function>';
        INT003_FSC.Response resp = new INT003_FSC.Response();
        String filled = INT003_FSC.fillXML(resp, acc, template);
        String filledRnc = INT003_FSC.fillXML(resp, accRnc, template);
        System.assert(filled.contains('40200000001'));
        System.assert(filledRnc.contains('131000001'));
    }
}
