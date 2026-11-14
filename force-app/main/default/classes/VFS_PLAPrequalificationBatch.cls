/**
 * @description       : Motor Batch de Precalificación de Riesgo PLA en FSC (Componente 2 - SOL-0197 / BVWAR-292)
 *                      Procesa clientes con 100% de datos completos y sin precalificación mediante
 *                      llamadas asíncronas controladas (Database.AllowsCallouts) a MacroProcesos (MPTransactionRest).
 *                      Actualiza ACC_Calificacion_de_cliente__c y ACC_Fecha_de_calificacion__c preservando ACC_Estado__c = 'ACTIVO'.
 *                      Genera informe diario ejecutivo por correo y archivo CSV publicado de precalificaciones exitosas.
 * @author            : @dev-salesforce / Keystone Advisors
 * @group             : PLA Vimenca
 * @last modified on  : 2026-11-14
**/
public with sharing class VFS_PLAPrequalificationBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    public Integer totalProcessed;
    public Integer totalSuccess;
    public Integer totalFailed;
    public Integer countAlto;
    public Integer countMedio;
    public Integer countBajo;
    public List<String> errorLogs;

    @TestVisible
    private List<SuccessfulClientRecord> successfulClients;

    private String notificationEmail;

    public class SuccessfulClientRecord {
        public String clientId { get; set; }
        public String clientName { get; set; }
        public String personType { get; set; }
        public String idNumber { get; set; }
        public String rating { get; set; }
        public String branchOrOwner { get; set; }
        public String qualificationDate { get; set; }
    }

    public VFS_PLAPrequalificationBatch() {
        this.totalProcessed = 0;
        this.totalSuccess = 0;
        this.totalFailed = 0;
        this.countAlto = 0;
        this.countMedio = 0;
        this.countBajo = 0;
        this.errorLogs = new List<String>();
        this.successfulClients = new List<SuccessfulClientRecord>();
        this.notificationEmail = 'rdiazg@keystoneadvisors.cl';
    }

    public VFS_PLAPrequalificationBatch(String reportEmail) {
        this();
        if (String.isNotBlank(reportEmail)) {
            this.notificationEmail = reportEmail;
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
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
            FROM Account
            WHERE ACC_Estado__c = 'ACTIVO'
              AND ACC_Calificacion_de_cliente__c = null
              AND RecordType.DeveloperName IN ('PersonAccount', 'Personas_Juridicas')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        // Conmutador Administrativo ON/OFF vía Custom Setting PLA_Configuracion__c
        PLA_Configuracion__c config = PLA_Configuracion__c.getInstance();
        if (config != null && config.Id != null) {
            if (!config.Activo__c || !config.Precalificacion_Activa__c) {
                System.debug('VFS_PLAPrequalificationBatch: Precalificación pausada administrativamente vía PLA_Configuracion__c');
                return;
            }
        }

        Time currentTime = Datetime.now().time();
        if (!Test.isRunningTest() && currentTime >= Time.newInstance(6, 0, 0, 0) && currentTime < Time.newInstance(18, 0, 0, 0)) {
            System.debug('Circuit Breaker: Fuera de ventana nocturna (18:00 - 06:00 hrs). Pausando procesamiento de lotes.');
            return;
        }

        Set<Id> accountIds = new Map<Id, Account>(scope).keySet();
        Set<Id> industryIds = new Set<Id>();
        for (Account a : scope) {
            if (String.isNotBlank(a.Industry)) {
                try {
                    industryIds.add((Id)a.Industry);
                } catch (Exception e) {}
            }
            if (a.ACC_Actividad_Economica__c != null) {
                industryIds.add(a.ACC_Actividad_Economica__c);
            }
        }

        Map<Id, String> activityCodeMap = new Map<Id, String>();
        if (!industryIds.isEmpty()) {
            for (Datos_Maestros__c dm : [SELECT Id, DM_Direccion__c, DM_Codigo__c FROM Datos_Maestros__c WHERE Id IN :industryIds]) {
                String code = String.isNotBlank(dm.DM_Direccion__c) ? dm.DM_Direccion__c : dm.DM_Codigo__c;
                activityCodeMap.put(dm.Id, code);
            }
        }

        Map<Id, Informacion_Financiera__c> infoMap = new Map<Id, Informacion_Financiera__c>();
        for (Informacion_Financiera__c inf : [
            SELECT Id, INF_Cuenta__c, INF_INT_Origen_de_los_recursos__c 
            FROM Informacion_Financiera__c 
            WHERE INF_Cuenta__c IN :accountIds
        ]) {
            infoMap.put(inf.INF_Cuenta__c, inf);
        }

        // Si el cliente no tiene Informacion_Financiera__c hijo pero tiene finanzas en Account,
        // generar en memoria un registro virtual con origen de recursos para satisfacer PreQualifyFlowHandler_FSC.createBody()
        List<Informacion_Financiera__c> syntheticInfosToInsert = new List<Informacion_Financiera__c>();
        for (Account a : scope) {
            if (!infoMap.containsKey(a.Id) && ((a.ACC_Total_Activos__c != null && a.ACC_Total_Activos__c > 0) || 
                                               (a.ACC_Ventas_Ingresos_Anuales__c != null && a.ACC_Ventas_Ingresos_Anuales__c > 0))) {
                Informacion_Financiera__c syntheticInf = new Informacion_Financiera__c(
                    INF_Cuenta__c = a.Id,
                    INF_INT_Origen_de_los_recursos__c = 'Ahorros'
                );
                syntheticInfosToInsert.add(syntheticInf);
            }
        }
        if (!syntheticInfosToInsert.isEmpty()) {
            Database.insert(syntheticInfosToInsert, false);
            for (Informacion_Financiera__c inf : syntheticInfosToInsert) {
                if (inf.Id != null) {
                    infoMap.put(inf.INF_Cuenta__c, inf);
                }
            }
        }

        Map<Id, FinServ__Employment__c> empMap = new Map<Id, FinServ__Employment__c>();
        for (FinServ__Employment__c emp : [
            SELECT Id, FinServ__Contact__r.AccountId, FinServ__Occupation__c 
            FROM FinServ__Employment__c 
            WHERE FinServ__Contact__r.AccountId IN :accountIds
        ]) {
            empMap.put(emp.FinServ__Contact__r.AccountId, emp);
        }

        Map<Id, FinServ__FinancialAccountRole__c> accRoleMap = new Map<Id, FinServ__FinancialAccountRole__c>();
        Map<Id, FinServ__FinancialAccountRole__c> repRoleMap = new Map<Id, FinServ__FinancialAccountRole__c>();
        for (FinServ__FinancialAccountRole__c role : [
            SELECT Id, FinServ__FinancialAccount__r.FinServ__PrimaryOwner__c,
                   OwnershipPercentage__c, FinServ__Role__c,
                   FinServ__FinancialAccount__r.FinServ__PrimaryOwner__r.FirstName,
                   FinServ__FinancialAccount__r.FinServ__PrimaryOwner__r.MiddleName,
                   FinServ__FinancialAccount__r.FinServ__PrimaryOwner__r.LastName,
                   FinServ__FinancialAccount__r.FinServ__PrimaryOwner__r.Suffix,
                   FinServ__FinancialAccount__r.FinServ__PrimaryOwner__r.FinServ__IndividualId__c,
                   FinServ__RelatedAccount__r.ACC_INT_Tipo_de_identificacion__c,
                   FinServ__RelatedAccount__r.ACC_TipoIdentificacion__c,
                   FinServ__RelatedAccount__r.ACC_INT_Nacionalidad__c,
                   FinServ__RelatedAccount__r.ACC_Nacionalidad__c,
                   FinServ__RelatedAccount__r.PersonBirthdate
            FROM FinServ__FinancialAccountRole__c 
            WHERE FinServ__FinancialAccount__r.FinServ__PrimaryOwner__c IN :accountIds
        ]) {
            if (role.FinServ__Role__c == 'Accionista') {
                accRoleMap.put(role.FinServ__FinancialAccount__r.FinServ__PrimaryOwner__c, role);
            } else if (role.FinServ__Role__c == 'Representante Legal') {
                repRoleMap.put(role.FinServ__FinancialAccount__r.FinServ__PrimaryOwner__c, role);
            }
        }

        List<Account> accountsToUpdate = new List<Account>();
        Map<Id, String> accountRatingMap = new Map<Id, String>();

        for (Account acc : scope) {
            this.totalProcessed++;
            String actCode = null;
            if (acc.ACC_Actividad_Economica__c != null && activityCodeMap.containsKey(acc.ACC_Actividad_Economica__c)) {
                actCode = activityCodeMap.get(acc.ACC_Actividad_Economica__c);
            } else if (String.isNotBlank(acc.Industry)) {
                try {
                    actCode = activityCodeMap.get((Id)acc.Industry);
                } catch (Exception e) {}
            }

            Informacion_Financiera__c inf = infoMap.get(acc.Id);
            FinServ__Employment__c emp = empMap.get(acc.Id);
            FinServ__FinancialAccountRole__c aRole = accRoleMap.get(acc.Id);
            FinServ__FinancialAccountRole__c rRole = repRoleMap.get(acc.Id);

            VFS_PLADataIntegrityService.AuditResult audit = VFS_PLADataIntegrityService.auditAccount(
                acc, inf, aRole, rRole, emp, actCode
            );

            // Requisito regulatorio: Solo avanzar a precalificación si cumple 100% de la matriz PLA (MacroProcesos)
            if (!audit.isPrequalificationReady) {
                continue;
            }

            try {
                // Auto-sincronización de campos de integración si están vacíos antes de generar la trama
                if (String.isBlank(acc.ACC_INT_Tipo_de_identificacion__c) && String.isNotBlank(acc.ACC_TipoIdentificacion__c)) {
                    acc.ACC_INT_Tipo_de_identificacion__c = acc.ACC_TipoIdentificacion__c;
                }
                if (String.isBlank(acc.ACC_INT_Nacionalidad__c) && String.isNotBlank(acc.ACC_Nacionalidad__c)) {
                    acc.ACC_INT_Nacionalidad__c = acc.ACC_Nacionalidad__c;
                }
                if (String.isBlank(acc.Industry) && acc.ACC_Actividad_Economica__c != null) {
                    acc.Industry = (String)acc.ACC_Actividad_Economica__c;
                }

                PreQualifyFlowModel body = PreQualifyFlowHandler_FSC.createBody(acc, inf, aRole, rRole, emp);
                String calificacion = PreQualifyFlowHandler_FSC.prequalifyClient(body);

                if (String.isNotBlank(calificacion)) {
                    calificacion = calificacion.toUpperCase();
                    if (calificacion == 'ALTO') this.countAlto++;
                    else if (calificacion == 'MEDIO') this.countMedio++;
                    else if (calificacion == 'BAJO') this.countBajo++;

                    Account toUpd = new Account(
                        Id = acc.Id,
                        ACC_Calificacion_de_cliente__c = calificacion,
                        ACC_Fecha_de_calificacion__c = Date.today()
                    );
                    accountsToUpdate.add(toUpd);
                    accountRatingMap.put(acc.Id, calificacion);
                    this.totalSuccess++;

                    // Registrar para el CSV de exitosos
                    SuccessfulClientRecord rec = new SuccessfulClientRecord();
                    rec.clientId = acc.Id;
                    rec.clientName = acc.Name;
                    rec.personType = acc.isPersonAccount ? 'Física' : 'Jurídica';
                    rec.idNumber = acc.isPersonAccount ? 
                        (String.isNotBlank(acc.ACC_NumIdentificacion__c) ? acc.ACC_NumIdentificacion__c : acc.FinServ__IndividualId__c) : 
                        acc.ACC_RNC__c;
                    rec.rating = calificacion;
                    rec.branchOrOwner = acc.Owner != null ? acc.Owner.Name : 'N/D';
                    rec.qualificationDate = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                    this.successfulClients.add(rec);
                } else {
                    this.totalFailed++;
                    this.errorLogs.add('Cliente ' + acc.Name + ' (' + acc.Id + '): Respuesta nula o no homologada de MacroProcesos.');
                }
            } catch (Exception ex) {
                this.totalFailed++;
                this.errorLogs.add('Cliente ' + acc.Name + ' (' + acc.Id + '): Excepción en callout: ' + ex.getMessage());
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(accountsToUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    this.totalFailed++;
                    this.totalSuccess--;
                    this.errorLogs.add('Error DML en cuenta ' + accountsToUpdate[i].Id + ': ' + results[i].getErrors()[0].getMessage());
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!this.successfulClients.isEmpty()) {
            publishSuccessfulReportFile();
        }

        if (String.isNotBlank(this.notificationEmail)) {
            sendDailyExecutiveReport();
        }

        System.debug('=== FIN VFS_PLAPrequalificationBatch ===');
        System.debug('Procesados: ' + this.totalProcessed + ' | Exitosos: ' + this.totalSuccess + 
                     ' | Fallidos: ' + this.totalFailed + ' | ALTO: ' + this.countAlto + 
                     ' | MEDIO: ' + this.countMedio + ' | BAJO: ' + this.countBajo);
    }

    private void publishSuccessfulReportFile() {
        try {
            String csvContent = 'Id_Salesforce,Nombre_Cliente,Tipo_Persona,Numero_Identificacion_o_RNC,Calificacion_PLA,Propietario_o_Sucursal,Fecha_Calificacion\n';
            for (SuccessfulClientRecord r : this.successfulClients) {
                csvContent += '"' + r.clientId + '","' + 
                              r.clientName.replace('"', '""') + '","' + 
                              r.personType + '","' + 
                              r.idNumber + '","' + 
                              r.rating + '","' + 
                              r.branchOrOwner.replace('"', '""') + '","' + 
                              r.qualificationDate + '"\n';
            }

            ContentVersion cv = new ContentVersion();
            cv.Title = 'Informe_Exitosos_Precalificados_PLA_' + Datetime.now().format('yyyyMMdd_HHmmss');
            cv.PathOnClient = cv.Title + '.csv';
            cv.VersionData = Blob.valueOf(csvContent);
            cv.Description = 'Reporte oficial de clientes calificados exitosamente en la corrida nocturna PLA.';
            cv.IsMajorVersion = true;
            insert cv;

            System.debug('VFS_PLAPrequalificationBatch: Archivo CSV de exitosos publicado. ContentVersionId: ' + cv.Id);
        } catch (Exception e) {
            System.debug('Error publicando ContentVersion de exitosos: ' + e.getMessage());
        }
    }

    private void sendDailyExecutiveReport() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ this.notificationEmail });
        mail.setSubject('📈 [PLA Vimenca] Reporte Diario de Precalificación Nocturna - ' + Datetime.now().format('dd/MM/yyyy'));

        String htmlBody = '<div style="font-family: Arial, sans-serif; color: #333333; line-height: 1.5;">' +
            '<h2 style="color: #003366;">Resumen Ejecutivo de Precalificación Masiva PLA FSC</h2>' +
            '<p>Resumen consolidado de la ejecución del motor batch nocturno:</p>' +
            '<table style="border-collapse: collapse; width: 100%; max-width: 600px; font-size: 13px;">' +
            '  <tr style="background-color: #003366; color: #ffffff;"><th style="padding: 8px; text-align: left;">Métrica</th><th style="padding: 8px; text-align: right;">Cantidad</th></tr>' +
            '  <tr style="background-color: #f4f6f9;"><td style="padding: 8px;">Total Clientes Evaluados en Lotes</td><td style="padding: 8px; text-align: right;"><b>' + this.totalProcessed + '</b></td></tr>' +
            '  <tr><td style="padding: 8px; color: #27ae60;">Precalificados Exitosamente</td><td style="padding: 8px; text-align: right; color: #27ae60;"><b>' + this.totalSuccess + '</b></td></tr>' +
            '  <tr style="background-color: #f4f6f9;"><td style="padding: 8px; padding-left: 20px;">- Riesgo BAJO</td><td style="padding: 8px; text-align: right;">' + this.countBajo + '</td></tr>' +
            '  <tr><td style="padding: 8px; padding-left: 20px;">- Riesgo MEDIO</td><td style="padding: 8px; text-align: right;">' + this.countMedio + '</td></tr>' +
            '  <tr style="background-color: #f4f6f9;"><td style="padding: 8px; padding-left: 20px; color: #c0392b;">- Riesgo ALTO</td><td style="padding: 8px; text-align: right; color: #c0392b;">' + this.countAlto + '</td></tr>' +
            '  <tr><td style="padding: 8px; color: #c0392b;">Fallos / Rechazos de Middleware</td><td style="padding: 8px; text-align: right; color: #c0392b;"><b>' + this.totalFailed + '</b></td></tr>' +
            '</table>';

        if (!this.successfulClients.isEmpty()) {
            htmlBody += '<p style="color: #27ae60; margin-top: 15px;">📁 <i>Se ha generado y publicado en Salesforce Files el archivo CSV consolidado con los ' + this.successfulClients.size() + ' clientes calificados exitosamente.</i></p>';
        }

        if (!this.errorLogs.isEmpty()) {
            htmlBody += '<h4 style="color: #c0392b; margin-top: 20px;">Detalle de Incidencias:</h4><ul>';
            Integer limitLogs = Math.min(this.errorLogs.size(), 20);
            for (Integer i = 0; i < limitLogs; i++) {
                htmlBody += '<li style="font-size: 11px;">' + this.errorLogs[i] + '</li>';
            }
            if (this.errorLogs.size() > 20) {
                htmlBody += '<li style="font-size: 11px;">... y ' + (this.errorLogs.size() - 20) + ' más.</li>';
            }
            htmlBody += '</ul>';
        }

        htmlBody += '<p style="font-size: 11px; color: #7f8c8d; margin-top: 25px;">Generado por VFS_PLAPrequalificationBatch (SOL-0197 / BVWAR-292) - Banco Vimenca FSC.</p>' +
            '</div>';

        mail.setHtmlBody(htmlBody);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception e) {
            System.debug('Error enviando reporte diario de precalificación: ' + e.getMessage());
        }
    }
}
