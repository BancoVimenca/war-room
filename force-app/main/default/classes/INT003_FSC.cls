/**
 * @description       : an adapted version of INT003 to FinServ Cloud (REST Blacklist / Cumplo360)
 * @author            : lplatino@keystoneadvisors.cl / keystone
 * @group             : 
 * @last modified on  : 22-11-2026
 * @last modified by  : Keystone Advisors
**/
@SuppressWarnings('PMD')
public with sharing class INT003_FSC {
    public static Response response;

    public class Response extends INTResponse {
        public final List<String> fieldList = new List<String>{'NumDocumento', 'TipoDocumento', 'CoincidenciaLI', 'CoincidenciaLE', 'Listas', 'Relevancia'};
        public Integer cumplo360Relevancia;
        public Map<String, String> valuesClient = new Map<String, String>{
            '[function_document]'       => 'FinServ__IndividualId__c',
            '[function_documentType]'   => 'ACC_TipoIdentificacion__c',
            '[function_firstName]'      => 'firstName',
            '[function_middleName]'     => 'middleName',
            '[function_lastName]'       => 'lastName',
            '[function_suffix]'         => 'suffix',
            '[function_birthDate]'      => 'PersonBirthdate',
            '[function_nacionality]'    => 'FinServ__Citizenship__pc'
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

    public static INT003_FSC.Response parse(String jsonResponse) {
        INT003_FSC.Response r = new INT003_FSC.Response();

        if (String.isBlank(jsonResponse)) {
            r.errorCode = '999';
            r.errorText = 'Respuesta vacía del servicio';
            return r;
        }

        try {
            Map<String, Object> rawMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);

            // responseCode puede venir numérico 0 o String '0'
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
            // Compatibilidad legacy si viniera XML
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

    public static void updateAccount(INT003_FSC.Response recordData, Id recordId) {
        Account acc = [SELECT Id, ACC_Resultado_Validacion__c, ACC_Estado__c, ACC_SubEstado__c, ACC_Condicion__c FROM Account WHERE Id = :recordId];
        
        String coincLE = recordData.values.containsKey('CoincidenciaLE') ? recordData.values.get('CoincidenciaLE').toString() : 'N';
        String coincLI = recordData.values.containsKey('CoincidenciaLI') ? recordData.values.get('CoincidenciaLI').toString() : 'N';
        
        List<Matriz_lista_control__c> matrizCase = [
            SELECT Id, MAT_Resultado_validacion__c, MAT_Estado__c, MAT_Sub_estado__c
            FROM   Matriz_lista_control__c
            WHERE  MAT_Coincidencia_en_listas_externas__c = :coincLE
            AND    MAT_Coincidencia_en_listas__c = :coincLI
        ];

        if (!matrizCase.isEmpty()) {
            if (acc.ACC_Condicion__c == 'CLIENTE') {
                acc.ACC_Resultado_Validacion__c = matrizCase[0].MAT_Resultado_validacion__c;
            } else {
                acc.ACC_Resultado_Validacion__c = matrizCase[0].MAT_Resultado_validacion__c;
                acc.ACC_Estado__c = matrizCase[0].MAT_Estado__c;
                acc.ACC_SubEstado__c = matrizCase[0].MAT_Sub_estado__c != null ? matrizCase[0].MAT_Sub_estado__c.toUpperCase() : null;
            }
        }

        acc.ACC_Coincidencia_Listas_Externas__c = (coincLE == 'Y');
        acc.ACC_Coincidencia_Listas_Internas__c = (coincLI == 'Y');
        acc.ACC_Listas__c = recordData.values.containsKey('Listas') ? recordData.values.get('Listas').toString() : '';
        acc.ACC_Ultima_Actualizacion_Listas_Internas__c = System.now();
        acc.ACC_Ultima_Actualizacion_Listas_Externas__c = System.now();

        if (recordData.cumplo360Relevancia != null) {
            acc.ACC_Cumplo360_Relevancia__c = recordData.cumplo360Relevancia;
        }

        try {
            update acc;
        } catch(Exception e) {
            System.debug('ERROR NO CONTROLADO EN UPDATE:: ' + e.getMessage());
        }
    }

    public static String fillXML(INT003_FSC.Response responseServer, Account client, String frame){
        Map<String, String> valuesToUse = new Map<String, String>(responseServer.valuesClient);
        if (client != null) {
            if (String.isNotBlank((String)client.get('FinServ__IndividualId__c'))) {
                valuesToUse.put('[function_document]', 'FinServ__IndividualId__c');
            } else if (String.isNotBlank((String)client.get('ACC_NumIdentificacion__c'))) {
                valuesToUse.put('[function_document]', 'ACC_NumIdentificacion__c');
            } else if (String.isNotBlank((String)client.get('ACC_RNC__c'))) {
                valuesToUse.put('[function_document]', 'ACC_RNC__c');
            }
        }
        String detailClient = frame.substringBetween('<Function>', '</Function>');
        frame = frame.replace(detailClient, fillDetailClient(valuesToUse, client, detailClient));
        return frame;
    }

    public static String fillDetailClient(Map<String, String> valuesClient, SObject client, String frame){
        frame = INTUtilities.fillCorrectType(valuesClient, client, frame);
        return frame;
    }

    public INT003_FSC(String idClient){
        validatePF(idClient);
    }

    public INT003_FSC.Response returnResponse() {
        return response;
    }

    @future(callout=true)
    public static void validatePF(String idClient) {
        List<String> fields = new List<String>(Account.SObjectType.getDescribe().fields.getMap().keySet());
        String soql = ''
            + ' SELECT ' + String.join(fields, ',')
            + ' FROM Account'
            + ' WHERE id=\'' + String.escapeSingleQuotes(idClient) + '\'';
        Account client = Database.query(soql);

        HttpRequest request = new HttpRequest();
        HttpResponse res;
        Http http = new Http();
        INT003_FSC.Response responseServer = new INT003_FSC.Response();

        // 1. Construir Request DTO JSON hacia la API REST Blacklist
        BlacklistRequestDTO dto = new BlacklistRequestDTO();
        
        String tipoDoc = (String) client.get('ACC_TipoIdentificacion__c');
        if (String.isBlank(tipoDoc)) {
            tipoDoc = 'cedula';
        } else {
            tipoDoc = tipoDoc.toLowerCase().replace('é', 'e');
        }
        dto.identificationType = tipoDoc;

        String docNum = '';
        if (String.isNotBlank((String)client.get('FinServ__IndividualId__c'))) {
            docNum = (String)client.get('FinServ__IndividualId__c');
        } else if (String.isNotBlank((String)client.get('ACC_NumIdentificacion__c'))) {
            docNum = (String)client.get('ACC_NumIdentificacion__c');
        } else if (String.isNotBlank((String)client.get('ACC_RNC__c'))) {
            docNum = (String)client.get('ACC_RNC__c');
        }
        dto.identificationNumber = docNum.replaceAll('[^0-9a-zA-Z]', '');

        dto.commercialName = client.Name != null ? client.Name : '';
        dto.firstName = client.FirstName != null ? client.FirstName : '';
        dto.middleName = client.MiddleName != null ? client.MiddleName : '';
        dto.lastName = client.LastName != null ? client.LastName : '';
        dto.lastName2 = client.Suffix != null ? client.Suffix : '';

        if (client.PersonBirthdate != null) {
            Datetime birthDt = Datetime.newInstance(client.PersonBirthdate.year(), client.PersonBirthdate.month(), client.PersonBirthdate.day());
            dto.birthDate = birthDt.format('yyyyMMdd');
        } else {
            dto.birthDate = '';
        }
        dto.nationality = (String) client.get('FinServ__Citizenship__pc') != null ? (String) client.get('FinServ__Citizenship__pc') : '';

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
            System.debug('Error en callout Blacklist :: ' + e);
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
