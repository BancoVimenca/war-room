@SuppressWarnings('PMD')
public with sharing class INT003_LEAD_FSC {
  public static Response response;
  public class Response extends INTResponse {
    public final List<String> fieldList = new List<String>{ 'NumDocumento', 'TipoDocumento', 'CoincidenciaLI', 'CoincidenciaLE', 'Listas', 'Relevancia' };
    public Integer cumplo360Relevancia;
    public Map<String, String> valuesClient = new Map<String, String>{
      '[function_document]' => 'LEA_NumIdentificacion__c',
      '[function_documentType]' => 'LEA_TipoIdentificacion__c',
      '[function_firstName]' => 'firstName',
      '[function_middleName]' => 'middleName',
      '[function_lastName]' => 'lastName',
      '[function_suffix]' => 'suffix',
      '[function_birthDate]' => 'LEA_PersonBirthdate__c',
      '[function_nacionality]' => 'LEA_Nacionalidad__c'
    };
  }

  public class BlacklistRequestDTO {
    public String identificationType;
    public String identificationNumber;
    public String commercialName;
    public String firstName;
    public String middleName;
    public String lastName;
    public String lastName2;
    public String birthDate;
    public String nationality;
  }

  public static INT003_LEAD_FSC.Response parse(String jsonResponse) {
    INT003_LEAD_FSC.Response r = new INT003_LEAD_FSC.Response();

    if (String.isBlank(jsonResponse)) {
      r.errorCode = '999';
      r.errorText = 'Respuesta vacía del servicio';
      return r;
    }

    try {
      Map<String, Object> rawMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);

      Object codeObj = rawMap.get('responseCode');
      String respCode = codeObj != null ? String.valueOf(codeObj).trim() : '';
      r.errorCode = (respCode == '0' || respCode == '000') ? '000' : respCode;

      Object descObj = rawMap.get('responseDesc');
      r.errorText = descObj != null ? String.valueOf(descObj) : '';

      String intCoinc = rawMap.get('internalCoincidences') != null ? String.valueOf(rawMap.get('internalCoincidences')).trim() : 'N';
      String extCoinc = rawMap.get('externalCoincidences') != null ? String.valueOf(rawMap.get('externalCoincidences')).trim() : 'N';
      String foundList = rawMap.get('FoundList') != null ? String.valueOf(rawMap.get('FoundList')).trim() : '';

      r.values.put('CoincidenciaLI', intCoinc);
      r.values.put('CoincidenciaLE', extCoinc);
      r.values.put('Listas', foundList);

      if (rawMap.get('cumplo360Relevancia') != null) {
        try {
          r.cumplo360Relevancia = Integer.valueOf(rawMap.get('cumplo360Relevancia'));
          r.values.put('Relevancia', String.valueOf(r.cumplo360Relevancia));
        } catch(Exception e) {
          System.debug('Error parseando cumplo360Relevancia: ' + e.getMessage());
        }
      }
    } catch (Exception ex) {
      // Compatibilidad si viniera XML legacy
      if (jsonResponse.contains('<ErrorCode>')) {
        r.errorCode = jsonResponse.substringAfter('<ErrorCode>').substringBefore('</ErrorCode>');
        r.errorText = jsonResponse.substringAfter('<ErrorText>').substringBefore('</ErrorText>');
        if (r.errorCode == '000') {
          for (String field : r.fieldList) {
            if (jsonResponse.contains('<' + field + '>')) {
              String textValue = jsonResponse.substringAfter('<' + field + '>').substringBefore('</' + field + '>');
              r.values.put(field, textValue.replace('Yamp;', '&'));
            }
          }
        }
      } else {
        r.errorCode = '999';
        r.errorText = 'Error parseando respuesta: ' + ex.getMessage();
      }
    }
    return r;
  }

  public static void updateAccount(INT003_LEAD_FSC.Response recordData, Id recordId) {
    Lead lea = [SELECT id, LEA_Resultado_Validacion__c, Status, LEA_SubEstado__c FROM Lead WHERE id = :recordId FOR UPDATE];
    
    String coincLE = recordData.values.containsKey('CoincidenciaLE') ? recordData.values.get('CoincidenciaLE').toString() : 'N';
    String coincLI = recordData.values.containsKey('CoincidenciaLI') ? recordData.values.get('CoincidenciaLI').toString() : 'N';

    List<Matriz_lista_control__c> matrizCase = [
      SELECT id, MAT_Resultado_validacion__c, MAT_Estado__c, MAT_Sub_estado__c
      FROM Matriz_lista_control__c
      WHERE MAT_Coincidencia_en_listas_externas__c = :coincLE AND MAT_Coincidencia_en_listas__c = :coincLI
    ];

    if (!matrizCase.isEmpty()) {
      applyListDecision(lea, matrizCase[0]);
    }

    lea.LEA_Coincidencia_Listas_Externas__c = (coincLE == 'Y');
    lea.LEA_Coincidencia_Listas_Internas__c = (coincLI == 'Y');
    lea.LEA_Listas__c = recordData.values.containsKey('Listas') ? recordData.values.get('Listas').toString() : '';
    lea.LEA_Ultima_Actualizacion_Listas_Internas__c = System.now();
    lea.LEA_Ultima_Actualizacion_Listas_Externas__c = System.now();

    if (recordData.cumplo360Relevancia != null) {
      lea.LEA_Cumplo360_Relevancia__c = recordData.cumplo360Relevancia;
    }

    update lea;
  }

  @TestVisible
  private static void applyListDecision(Lead candidate, Matriz_lista_control__c decision) {
    candidate.LEA_Resultado_Validacion__c = decision.MAT_Resultado_validacion__c;
    if (decision.MAT_Resultado_validacion__c != 'Aprobado' || candidate.Status == 'Calificado') {
      candidate.Status = decision.MAT_Resultado_validacion__c == 'Aprobado'
        ? 'Validado' : decision.MAT_Estado__c;
      candidate.LEA_SubEstado__c = decision.MAT_Sub_estado__c == null
        ? null : decision.MAT_Sub_estado__c.toUpperCase();
    }
  }

  public static String fillXML(INT003_LEAD_FSC.Response responseServer, Lead client, String frame) {
    String detailClient = frame.substringBetween('<Function>', '</Function>');
    frame = frame.replace(detailClient, fillDetailClient(responseServer.valuesClient, client, detailClient));
    return frame;
  }

  public static String fillDetailClient(Map<String, String> valuesClient, SObject client, String frame) {
    frame = INTUtilities.fillCorrectType(valuesClient, client, frame);
    return frame;
  }

  public INT003_LEAD_FSC(String idClient) {
    validatePF(idClient);
  }

  public INT003_LEAD_FSC.Response returnResponse() {
    return response;
  }

  public static void validatePF(String idClient) {
    Lead leadToValidate = [SELECT Status, LEA_TipoIdentificacion__c FROM Lead WHERE Id = :idClient LIMIT 1];
    if (!LeadCandidatePolicy.canValidateLists(leadToValidate)) {
      throw new IllegalArgumentException('Para validar contra listas, el candidato debe estar en estado Iniciado, Calificado, Validado o Aprobado');
    }

    List<String> fields = new List<String>(Lead.SObjectType.getDescribe().fields.getMap().keySet());
    String soql = '' + ' SELECT ' + String.join(fields, ',') + ' FROM Lead' + ' WHERE id=\'' + String.escapeSingleQuotes(idClient) + '\'';
    Lead client = Database.query(soql);

    HttpRequest request = new HttpRequest();
    HttpResponse res;
    Http http = new Http();
    INT003_LEAD_FSC.Response responseServer = new INT003_LEAD_FSC.Response();

    // 1. Construir Request DTO JSON hacia la API REST Blacklist
    BlacklistRequestDTO dto = new BlacklistRequestDTO();

    String tipoDoc = client.LEA_TipoIdentificacion__c;
    if (String.isBlank(tipoDoc)) {
      tipoDoc = 'cedula';
    } else {
      tipoDoc = tipoDoc.toLowerCase().replace('é', 'e');
    }
    dto.identificationType = tipoDoc;

    String docNum = client.LEA_NumIdentificacion__c != null ? client.LEA_NumIdentificacion__c : '';
    dto.identificationNumber = docNum.replaceAll('[^0-9a-zA-Z]', '');

    dto.commercialName = client.Company != null ? client.Company : '';
    dto.firstName = client.FirstName != null ? client.FirstName : '';
    dto.middleName = client.MiddleName != null ? client.MiddleName : '';
    dto.lastName = client.LastName != null ? client.LastName : '';
    dto.lastName2 = client.Suffix != null ? client.Suffix : '';

    if (client.LEA_PersonBirthdate__c != null) {
      Datetime birthDt = Datetime.newInstance(client.LEA_PersonBirthdate__c.year(), client.LEA_PersonBirthdate__c.month(), client.LEA_PersonBirthdate__c.day());
      dto.birthDate = birthDt.format('yyyyMMdd');
    } else {
      dto.birthDate = '';
    }
    dto.nationality = client.LEA_Nacionalidad__c != null ? client.LEA_Nacionalidad__c : '';

    // 2. Setup HTTP Request con autenticacion independiente
    request.setEndpoint(Label.EndpointBlacklistRest);
    request.setMethod('POST');
    request.setTimeout(120000);
    request.setHeader('Content-Type', 'application/json');
    request.setHeader('Accept', 'application/json');
    request.setHeader('X-API-Key', Label.BlacklistApiKey);
    request.setBody(JSON.serialize(dto));

    try {
      res = http.send(request);
      if (res.getStatusCode() == 200) {
        responseServer = parse(res.getBody());
        if (responseServer.errorCode == '000') {
          updateAccount(responseServer, idClient);
        }
      } else {
        responseServer.errorCode = String.valueOf(res.getStatusCode());
        responseServer.errorText = 'Error HTTP ' + res.getStatusCode() + ': ' + res.getStatus();
      }
    } catch (Exception e) {
      responseServer.errorCode = '999';
      responseServer.errorText = e.getMessage();
      throw e;
    } finally {
      INTLogger.INTLoggerResult result = INTLogger.logCallout('003', 'ValidaListasControl', request, res);
    }

    if (res != null) {
      responseServer.requestStatusCode = res.getStatusCode();
      responseServer.requestStatus = res.getStatus();
    }
    response = responseServer;
  }
}
