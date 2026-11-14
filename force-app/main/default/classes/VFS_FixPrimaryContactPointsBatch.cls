/**
 * @description Batch Apex para saneamiento masivo de vías de contacto en FSC.
 *              Garantiza que toda cuenta Persona Física y Jurídica que tenga registros de
 *              teléfono, email o dirección cuente con al menos uno marcado como IsPrimary = true.
 *              En direcciones, asigna conjuntamente IsPrimary = true e IsDefault = true para
 *              garantizar concordancia total con la vista Lightning de FSC.
 *              Organiza las listas de actualización por sObjectType homogéneo para evitar el error de chunking.
 *              Al finalizar (finish), compila y envía un reporte ejecutivo por correo con un CSV adjunto detallando
 *              cada cliente actualizado, tipo de punto de contacto y resultado de la operación.
 * @author Keystone Advisors - @dev-salesforce
 * @correlative SOL-0277
 */
public without sharing class VFS_FixPrimaryContactPointsBatch implements Database.Batchable<sObject>, Database.Stateful {

    public Integer accountsEvaluated = 0;
    public Integer phonesUpdated = 0;
    public Integer emailsUpdated = 0;
    public Integer addressesUpdated = 0;
    public List<String> errorLogs = new List<String>();

    // Acumulador de filas para el reporte CSV
    public List<String> csvRows = new List<String>();

    // Correo de notificación configurable (por defecto el usuario que ejecuta o admin)
    public String targetNotificationEmail;

    public VFS_FixPrimaryContactPointsBatch() {
        this(null);
    }

    public VFS_FixPrimaryContactPointsBatch(String notificationEmail) {
        if (String.isNotBlank(notificationEmail)) {
            this.targetNotificationEmail = notificationEmail;
        } else {
            this.targetNotificationEmail = UserInfo.getUserEmail();
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Encabezado del reporte CSV
        if (csvRows.isEmpty()) {
            csvRows.add('AccountId,AccountName,ContactPointType,RecordId,IsPrimary,IsDefault,Status,Details');
        }

        // Selecciona cuentas evaluando tanto los record types de cliente como cuentas en general
        return Database.getQueryLocator([
            SELECT Id, Name, RecordType.DeveloperName 
            FROM Account 
            WHERE RecordType.DeveloperName IN (
                'IndustriesIndividual', 'IndustriesBusiness', 'PersonAccount', 
                'Personas_Juridicas', 'Candidato_Persona_Fisica', 'Candidato_Persona_Juridica'
            )
            OR RecordTypeId = null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        Map<Id, Account> accountsMap = new Map<Id, Account>(scope);
        Set<Id> accountIds = accountsMap.keySet();
        accountsEvaluated += accountIds.size();

        // 1. Mapeo de ContactPointPhone por Cuenta
        Map<Id, List<ContactPointPhone>> phonesByAccount = new Map<Id, List<ContactPointPhone>>();
        for (ContactPointPhone cpp : [
            SELECT Id, ParentId, IsPrimary, CreatedDate 
            FROM ContactPointPhone 
            WHERE ParentId IN :accountIds 
            ORDER BY IsPrimary DESC, CreatedDate DESC
        ]) {
            if (!phonesByAccount.containsKey(cpp.ParentId)) {
                phonesByAccount.put(cpp.ParentId, new List<ContactPointPhone>());
            }
            phonesByAccount.get(cpp.ParentId).add(cpp);
        }

        // 2. Mapeo de ContactPointEmail por Cuenta
        Map<Id, List<ContactPointEmail>> emailsByAccount = new Map<Id, List<ContactPointEmail>>();
        for (ContactPointEmail cpe : [
            SELECT Id, ParentId, IsPrimary, CreatedDate 
            FROM ContactPointEmail 
            WHERE ParentId IN :accountIds 
            ORDER BY IsPrimary DESC, CreatedDate DESC
        ]) {
            if (!emailsByAccount.containsKey(cpe.ParentId)) {
                emailsByAccount.put(cpe.ParentId, new List<ContactPointEmail>());
            }
            emailsByAccount.get(cpe.ParentId).add(cpe);
        }

        // 3. Mapeo de ContactPointAddress por Cuenta
        Map<Id, List<ContactPointAddress>> addressesByAccount = new Map<Id, List<ContactPointAddress>>();
        for (ContactPointAddress cpa : [
            SELECT Id, ParentId, IsPrimary, IsDefault, CreatedDate 
            FROM ContactPointAddress 
            WHERE ParentId IN :accountIds 
            ORDER BY IsPrimary DESC, IsDefault DESC, CreatedDate DESC
        ]) {
            if (!addressesByAccount.containsKey(cpa.ParentId)) {
                addressesByAccount.put(cpa.ParentId, new List<ContactPointAddress>());
            }
            addressesByAccount.get(cpa.ParentId).add(cpa);
        }

        List<ContactPointPhone> phonesToUpdate = new List<ContactPointPhone>();
        List<ContactPointEmail> emailsToUpdate = new List<ContactPointEmail>();
        List<ContactPointAddress> addressesToUpdate = new List<ContactPointAddress>();

        for (Id accId : accountIds) {
            // Evaluación de Teléfonos
            if (phonesByAccount.containsKey(accId)) {
                List<ContactPointPhone> phones = phonesByAccount.get(accId);
                Boolean hasPrimaryPhone = false;
                for (ContactPointPhone p : phones) {
                    if (p.IsPrimary == true) {
                        hasPrimaryPhone = true;
                        break;
                    }
                }
                if (!hasPrimaryPhone && !phones.isEmpty()) {
                    ContactPointPhone target = phones[0];
                    target.IsPrimary = true;
                    phonesToUpdate.add(target);
                    phonesUpdated++;
                }
            }

            // Evaluación de Correos Electrónicos
            if (emailsByAccount.containsKey(accId)) {
                List<ContactPointEmail> emails = emailsByAccount.get(accId);
                Boolean hasPrimaryEmail = false;
                for (ContactPointEmail e : emails) {
                    if (e.IsPrimary == true) {
                        hasPrimaryEmail = true;
                        break;
                    }
                }
                if (!hasPrimaryEmail && !emails.isEmpty()) {
                    ContactPointEmail target = emails[0];
                    target.IsPrimary = true;
                    emailsToUpdate.add(target);
                    emailsUpdated++;
                }
            }

            // Evaluación de Direcciones (Garantizar IsPrimary = true e IsDefault = true)
            if (addressesByAccount.containsKey(accId)) {
                List<ContactPointAddress> addresses = addressesByAccount.get(accId);
                Boolean hasPrimaryAddress = false;
                for (ContactPointAddress a : addresses) {
                    if (a.IsPrimary == true && a.IsDefault == true) {
                        hasPrimaryAddress = true;
                        break;
                    }
                }
                if (!hasPrimaryAddress && !addresses.isEmpty()) {
                    ContactPointAddress target = addresses[0];
                    target.IsPrimary = true;
                    target.IsDefault = true;
                    addressesToUpdate.add(target);
                    addressesUpdated++;
                }
            }
        }

        // Ejecución DML por tipo homogéneo
        if (!phonesToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(phonesToUpdate, false);
            handleSaveResults(results, phonesToUpdate, 'ContactPointPhone', accountsMap);
        }
        if (!emailsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(emailsToUpdate, false);
            handleSaveResults(results, emailsToUpdate, 'ContactPointEmail', accountsMap);
        }
        if (!addressesToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(addressesToUpdate, false);
            handleSaveResults(results, addressesToUpdate, 'ContactPointAddress', accountsMap);
        }
    }

    private void handleSaveResults(Database.SaveResult[] results, List<sObject> records, String cpType, Map<Id, Account> accountsMap) {
        for (Integer i = 0; i < results.size(); i++) {
            sObject record = records[i];
            Id parentId = (Id) record.get('ParentId');
            String accName = accountsMap.containsKey(parentId) && accountsMap.get(parentId).Name != null 
                ? accountsMap.get(parentId).Name.replace(',', ' ') 
                : 'Sin Nombre';

            Boolean isPrim = (cpType == 'ContactPointPhone' || cpType == 'ContactPointEmail' || cpType == 'ContactPointAddress');
            Boolean isDef = (cpType == 'ContactPointAddress');

            if (results[i].isSuccess()) {
                // Registrar éxito en el reporte CSV (limitar filas para no saturar memoria en lotes de millones)
                if (csvRows.size() < 10000) {
                    csvRows.add(parentId + ',"' + accName + '",' + cpType + ',' + record.Id + ',' + isPrim + ',' + isDef + ',EXITO,Actualizado a Principal');
                }
            } else {
                String errMsg = results[i].getErrors()[0].getMessage().replace('"', '""');
                String msg = 'RecordId: ' + record.Id + ' - Error: ' + results[i].getErrors()[0].getMessage();
                errorLogs.add(msg);
                System.debug(LoggingLevel.ERROR, '>>> [SOL-0277] ' + msg);

                if (csvRows.size() < 10000) {
                    csvRows.add(parentId + ',"' + accName + '",' + cpType + ',' + record.Id + ',' + isPrim + ',' + isDef + ',ERROR,"' + errMsg + '"');
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('>>> [SOL-0277] VFS_FixPrimaryContactPointsBatch FINALIZADO');
        System.debug('>>> Cuentas evaluadas: ' + accountsEvaluated);
        System.debug('>>> Teléfonos promovidos a IsPrimary: ' + phonesUpdated);
        System.debug('>>> Emails promovidos a IsPrimary: ' + emailsUpdated);
        System.debug('>>> Direcciones promovidas a IsPrimary: ' + addressesUpdated);
        System.debug('>>> Total incidencias DML: ' + errorLogs.size());

        // Envío de Reporte Ejecutivo por Correo con CSV Adjunto
        sendSummaryEmail();
    }

    private void sendSummaryEmail() {
        if (String.isBlank(this.targetNotificationEmail)) {
            return;
        }

        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ this.targetNotificationEmail });
            mail.setSubject('📊 [Vimenca FSC] Reporte de Saneamiento de Vías de Contacto Principal - ' + Datetime.now().format('dd/MM/yyyy HH:mm'));

            String htmlBody = '<div style="font-family: Arial, sans-serif; color: #333333; line-height: 1.5;">' +
                '<h2 style="color: #003366; border-bottom: 2px solid #003366; padding-bottom: 8px;">Resumen Ejecutivo: Saneamiento de Vías de Contacto (FSC)</h2>' +
                '<p>Se ha completado la ejecución del proceso por lotes para la regularización de vías de contacto principales (Teléfonos, Emails y Direcciones).</p>' +
                '<table style="border-collapse: collapse; width: 100%; max-width: 650px; font-size: 13px; margin: 15px 0;">' +
                '  <tr style="background-color: #003366; color: #ffffff;">' +
                '    <th style="padding: 10px; text-align: left;">Métrica de Proceso</th>' +
                '    <th style="padding: 10px; text-align: right;">Total Registros</th>' +
                '  </tr>' +
                '  <tr style="background-color: #f4f6f9;">' +
                '    <td style="padding: 8px; border: 1px solid #cccccc;">Total Cuentas Evaluadas</td>' +
                '    <td style="padding: 8px; text-align: right; border: 1px solid #cccccc;"><b>' + this.accountsEvaluated + '</b></td>' +
                '  </tr>' +
                '  <tr>' +
                '    <td style="padding: 8px; border: 1px solid #cccccc; color: #27ae60;">📞 Teléfonos promovidos a IsPrimary</td>' +
                '    <td style="padding: 8px; text-align: right; border: 1px solid #cccccc; color: #27ae60;"><b>' + this.phonesUpdated + '</b></td>' +
                '  </tr>' +
                '  <tr style="background-color: #f4f6f9;">' +
                '    <td style="padding: 8px; border: 1px solid #cccccc; color: #2980b9;">✉️ Emails promovidos a IsPrimary</td>' +
                '    <td style="padding: 8px; text-align: right; border: 1px solid #cccccc; color: #2980b9;"><b>' + this.emailsUpdated + '</b></td>' +
                '  </tr>' +
                '  <tr>' +
                '    <td style="padding: 8px; border: 1px solid #cccccc; color: #8e44ad;">📍 Direcciones promovidas a IsDefault / IsPrimary</td>' +
                '    <td style="padding: 8px; text-align: right; border: 1px solid #cccccc; color: #8e44ad;"><b>' + this.addressesUpdated + '</b></td>' +
                '  </tr>' +
                '  <tr style="background-color: #f4f6f9;">' +
                '    <td style="padding: 8px; border: 1px solid #cccccc; color: ' + (this.errorLogs.isEmpty() ? '#27ae60' : '#c0392b') + ';">⚠️ Incidencias DML Detectadas</td>' +
                '    <td style="padding: 8px; text-align: right; border: 1px solid #cccccc; color: ' + (this.errorLogs.isEmpty() ? '#27ae60' : '#c0392b') + ';"><b>' + this.errorLogs.size() + '</b></td>' +
                '  </tr>' +
                '</table>';

            if (!this.errorLogs.isEmpty()) {
                htmlBody += '<h4 style="color: #c0392b; margin-top: 15px;">Detalle de Errores:</h4><ul>';
                Integer limitLogs = Math.min(this.errorLogs.size(), 10);
                for (Integer i = 0; i < limitLogs; i++) {
                    htmlBody += '<li style="font-size: 11px;">' + this.errorLogs[i] + '</li>';
                }
                if (this.errorLogs.size() > 10) {
                    htmlBody += '<li style="font-size: 11px;">... y ' + (this.errorLogs.size() - 10) + ' más.</li>';
                }
                htmlBody += '</ul>';
            }

            htmlBody += '<p style="font-size: 12px; color: #555555; margin-top: 20px;">' +
                '📎 <b>Archivo Adjunto:</b> Se incluye el archivo CSV con la relación detallada de clientes y registros actualizados.</p>' +
                '<p style="font-size: 11px; color: #808080; margin-top: 25px; border-top: 1px solid #e0e0e0; padding-top: 8px;">' +
                'Generado automáticamente por VFS_FixPrimaryContactPointsBatch (SOL-0277) — Banco Vimenca & Keystone Advisors.</p>' +
                '</div>';

            mail.setHtmlBody(htmlBody);

            // Generación y adjunto del archivo CSV
            if (!this.csvRows.isEmpty()) {
                String csvContent = String.join(this.csvRows, '\n');
                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                attachment.setFileName('Reporte_Saneamiento_ContactPoints_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.csv');
                attachment.setBody(Blob.valueOf(csvContent));
                attachment.setContentType('text/csv');
                mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
            }

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
            System.debug('>>> [SOL-0277] Correo de reporte enviado satisfactoriamente a: ' + this.targetNotificationEmail);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '>>> [SOL-0277] Error enviando correo de resumen: ' + e.getMessage());
        }
    }
}
