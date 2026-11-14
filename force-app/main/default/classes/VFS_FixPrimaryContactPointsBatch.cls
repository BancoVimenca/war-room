/**
 * @description Batch Apex para saneamiento masivo de vías de contacto en FSC.
 *              Garantiza que toda cuenta Persona Física y Jurídica que tenga registros de
 *              teléfono, email o dirección cuente con al menos uno marcado como IsPrimary = true.
 *              Si no tiene ninguno marcado, selecciona el primero/más reciente y lo marca como principal.
 * @author Keystone Advisors - @dev-salesforce
 * @correlative SOL-0269
 */
public without sharing class VFS_FixPrimaryContactPointsBatch implements Database.Batchable<sObject>, Database.Stateful {

    public Integer accountsEvaluated = 0;
    public Integer phonesUpdated = 0;
    public Integer emailsUpdated = 0;
    public Integer addressesUpdated = 0;
    public List<String> errorLogs = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Selecciona cuentas Persona Física y Jurídica (o todas las cuentas estándar/FSC)
        return Database.getQueryLocator([
            SELECT Id, RecordType.DeveloperName 
            FROM Account 
            WHERE RecordType.DeveloperName IN ('IndustriesIndividual', 'IndustriesBusiness', 'PersonAccount')
               OR RecordTypeId = null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Map<Id, Account>(scope).keySet();
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
            SELECT Id, ParentId, IsPrimary, CreatedDate 
            FROM ContactPointAddress 
            WHERE ParentId IN :accountIds 
            ORDER BY IsPrimary DESC, CreatedDate DESC
        ]) {
            if (!addressesByAccount.containsKey(cpa.ParentId)) {
                addressesByAccount.put(cpa.ParentId, new List<ContactPointAddress>());
            }
            addressesByAccount.get(cpa.ParentId).add(cpa);
        }

        List<sObject> recordsToUpdate = new List<sObject>();

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
                    recordsToUpdate.add(target);
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
                    recordsToUpdate.add(target);
                    emailsUpdated++;
                }
            }

            // Evaluación de Direcciones
            if (addressesByAccount.containsKey(accId)) {
                List<ContactPointAddress> addresses = addressesByAccount.get(accId);
                Boolean hasPrimaryAddress = false;
                for (ContactPointAddress a : addresses) {
                    if (a.IsPrimary == true) {
                        hasPrimaryAddress = true;
                        break;
                    }
                }
                if (!hasPrimaryAddress && !addresses.isEmpty()) {
                    ContactPointAddress target = addresses[0];
                    target.IsPrimary = true;
                    recordsToUpdate.add(target);
                    addressesUpdated++;
                }
            }
        }

        // Ejecución DML Parcial (no abortivo ante errores puntuales de validación)
        if (!recordsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(recordsToUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    String msg = 'AccountId/RecordId: ' + recordsToUpdate[i].Id + ' - Error: ' + results[i].getErrors()[0].getMessage();
                    errorLogs.add(msg);
                    System.debug(LoggingLevel.ERROR, '>>> [SOL-0269] ' + msg);
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('>>> [SOL-0269] VFS_FixPrimaryContactPointsBatch FINALIZADO');
        System.debug('>>> Cuentas evaluadas: ' + accountsEvaluated);
        System.debug('>>> Teléfonos promovidos a IsPrimary: ' + phonesUpdated);
        System.debug('>>> Emails promovidos a IsPrimary: ' + emailsUpdated);
        System.debug('>>> Direcciones promovidas a IsPrimary: ' + addressesUpdated);
        System.debug('>>> Total incidencias DML: ' + errorLogs.size());
    }
}
