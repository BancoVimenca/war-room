@SuppressWarnings('PMD')
@isTest
private with sharing class INT003_LEAD_FSC_Test {
  @TestSetup
  static void setupData() {
    Datos_Maestros__c actividad = new Datos_Maestros__c(Name = 'Test Actividad', DM_Direccion__c = 'ACT001');
    insert actividad;

    Lead lea = new Lead(
      FirstName = 'Test',
      LastName = 'Lead',
      Company = 'TestCo',
      Status = 'Calificado',
      LEA_NumIdentificacion__c = '00112345678',
      LEA_TipoIdentificacion__c = 'Cédula',
      LEA_Nacionalidad__c = 'REPUBLICA DOMINICANA',
      LEA_PersonBirthdate__c = Date.today().addYears(-30),
      LEA_Tipo_Vinculacion__c = 'DEUDOR O EMISOR NO VINCULADO',
      LEA_Actividad_Economica__c = actividad.Id,
      LEA_Tipo_Sector__c = 'PRIVADO'
    );
    insert lea;

    Matriz_lista_control__c matriz = new Matriz_lista_control__c(
      MAT_Coincidencia_en_listas_externas__c = 'N',
      MAT_Coincidencia_en_listas__c = 'N',
      MAT_Resultado_validacion__c = 'Aprobado',
      MAT_Estado__c = 'Calificado',
      MAT_Sub_estado__c = 'Aceptado'
    );
    insert matriz;
  }

  private static Lead getTestLead() {
    List<String> fields = new List<String>(Lead.SObjectType.getDescribe().fields.getMap().keySet());
    String soql = 'SELECT ' + String.join(fields, ',') + ' FROM Lead WHERE LastName = \'Lead\' LIMIT 1';
    return Database.query(soql);
  }

  @isTest
  static void parseSuccessJsonTest() {
    String responseBody = '{"responseCode":"0","responseDesc":"OK","internalCoincidences":"N","externalCoincidences":"N","FoundList":"Lista1","cumplo360Relevancia":90}';

    Test.startTest();
    INT003_LEAD_FSC.Response result = INT003_LEAD_FSC.parse(responseBody);
    Test.stopTest();

    System.assertEquals('000', result.errorCode);
    System.assertEquals('OK', result.errorText);
    System.assertEquals('N', result.values.get('CoincidenciaLI'));
    System.assertEquals('N', result.values.get('CoincidenciaLE'));
    System.assertEquals('Lista1', result.values.get('Listas'));
    System.assertEquals(90, result.cumplo360Relevancia);
  }

  @isTest
  static void parseXmlAndErrorsTest() {
    String responseBody = '{"responseCode":"999","responseDesc":"ERROR"}';
    INT003_LEAD_FSC.Response result = INT003_LEAD_FSC.parse(responseBody);
    System.assertEquals('999', result.errorCode);

    String xmlResp = '<ErrorCode>000</ErrorCode><ErrorText>OK</ErrorText><CoincidenciaLI>N</CoincidenciaLI><CoincidenciaLE>N</CoincidenciaLE><Listas>L1</Listas>';
    INT003_LEAD_FSC.Response rXml = INT003_LEAD_FSC.parse(xmlResp);
    System.assertEquals('000', rXml.errorCode);

    INT003_LEAD_FSC.Response rEmpty = INT003_LEAD_FSC.parse('');
    System.assertEquals('999', rEmpty.errorCode);

    INT003_LEAD_FSC.Response rInvalid = INT003_LEAD_FSC.parse('{not_json}');
    System.assertEquals('999', rInvalid.errorCode);
  }

  @isTest
  static void updateAccountTest() {
    Lead lea = getTestLead();

    INT003_LEAD_FSC.Response responseData = new INT003_LEAD_FSC.Response();
    responseData.values.put('CoincidenciaLI', 'N');
    responseData.values.put('CoincidenciaLE', 'N');
    responseData.values.put('Listas', '');
    responseData.cumplo360Relevancia = 88;

    Test.startTest();
    INT003_LEAD_FSC.updateAccount(responseData, lea.Id);
    Test.stopTest();

    Lead updated = [SELECT Id, LEA_Resultado_Validacion__c, Status, LEA_SubEstado__c, LEA_Coincidencia_Listas_Externas__c, LEA_Coincidencia_Listas_Internas__c, LEA_Cumplo360_Relevancia__c FROM Lead WHERE Id = :lea.Id];
    System.assertEquals('Aprobado', updated.LEA_Resultado_Validacion__c);
    System.assertEquals(false, updated.LEA_Coincidencia_Listas_Externas__c);
    System.assertEquals(false, updated.LEA_Coincidencia_Listas_Internas__c);
    System.assertEquals(88, updated.LEA_Cumplo360_Relevancia__c);
  }

  @isTest
  static void validatePFCalloutTest() {
    Lead lea = getTestLead();

    Test.setMock(HttpCalloutMock.class, new INT003_LEAD_FSC_TestMock());
    Test.startTest();
    INT003_LEAD_FSC.validatePF(lea.Id);
    Test.stopTest();

    Lead updated = [SELECT Id, LEA_Resultado_Validacion__c, LEA_Cumplo360_Relevancia__c FROM Lead WHERE Id = :lea.Id];
    System.assertEquals('Aprobado', updated.LEA_Resultado_Validacion__c);
    System.assertEquals(80, updated.LEA_Cumplo360_Relevancia__c);
  }

  @isTest
  static void testConstructorAndFillXML() {
    Lead lea = getTestLead();
    Test.setMock(HttpCalloutMock.class, new INT003_LEAD_FSC_TestMock());

    Test.startTest();
    INT003_LEAD_FSC instance = new INT003_LEAD_FSC(lea.Id);
    INT003_LEAD_FSC.Response resp = instance.returnResponse();

    String xmlFilled = INT003_LEAD_FSC.fillXML(new INT003_LEAD_FSC.Response(), lea, '<Function>[function_document]</Function>');
    Test.stopTest();

    System.assert(xmlFilled.contains('00112345678'));
  }

  @isTest
  static void validatePFPoliciesTest() {
    Lead lea = getTestLead();
    lea.Status = 'Cerrado';
    update lea;

    Test.startTest();
    try {
      INT003_LEAD_FSC.validatePF(lea.Id);
      System.assert(false, 'Debe fallar si el estado no es permitido');
    } catch(IllegalArgumentException e) {
      System.assert(e.getMessage().contains('Para validar contra listas'));
    }
    Test.stopTest();
  }
}
