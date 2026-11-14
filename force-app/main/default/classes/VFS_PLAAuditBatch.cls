/**
 * @description       : Batch de Auditoría de Campos Obligatorios y Gestión de Notificaciones (Componente 1)
 *                      - Para clientes con ejecutivo: Despacha correo individual con viñetas de faltantes y link directo.
 *                      - Para clientes en los 10 usuarios de sucursales: Agrupa casos y envía un CSV/HTML consolidado
 *                        al Encargado General de Sucursales (Laura Reynoso: lreynoso@bv.com.do en QA).
 * @author            : @dev-salesforce / Keystone Advisors
 * @group             : PLA Vimenca
 * @last modified on  : 2026-11-13
**/
public with sharing class VFS_PLAAuditBatch implements Database.Batchable<sObject>, Database.Stateful {

    @TestVisible
    private List<BranchIncompleteCase> branchCases;
    
    public Integer totalEvaluated;
    public Integer totalComplete;
    public Integer totalIncompleteExec;
    public Integer totalIncompleteBranch;

    private List<String> branchManagerEmails;

    public class BranchIncompleteCase {
        public String branchCode { get; set; }
        public String branchName { get; set; }
        public String clientName { get; set; }
        public String personType { get; set; }
        public String idType { get; set; }
        public String idNumber { get; set; }
        public String missingFieldsPLA { get; set; }
        public String contactWarnings { get; set; }
        public String recordUrl { get; set; }
    }

    public VFS_PLAAuditBatch() {
        this.branchCases = new List<BranchIncompleteCase>();
        this.totalEvaluated = 0;
        this.totalComplete = 0;
        this.totalIncompleteExec = 0;
        this.totalIncompleteBranch = 0;
        // Laura Reynoso (Encargada de Sucursales en QA) y Rodrigo Díaz (Validación Técnica)
        this.branchManagerEmails = new List<String>{ 'lreynoso@bv.com.do', 'rdiazg@keystoneadvisors.cl' };
    }

    public VFS_PLAAuditBatch(String supervisorEmail) {
        this();
        if (String.isNotBlank(supervisorEmail)) {
            if (!this.branchManagerEmails.contains(supervisorEmail)) {
                this.branchManagerEmails.add(supervisorEmail);
            }
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, FirstName, MiddleName, LastName, Suffix,
                   isPersonAccount, ACC_Persona_Fisica__c, ACC_INT_TipoPersona__c,
                   ACC_INT_Tipo_de_identificacion__c, ACC_NumIdentificacion__c, FinServ__IndividualId__c,
                   PersonBirthdate, ACC_Fecha_Fundacion__c, ACC_Nacionalidad__c, ACC_INT_Nacionalidad__c,
                   ACC_Estado_Civil__c, PersonEmail, ACC_Correo_Electronico_Cliente__c, PersonMobilePhone, Phone,
                   ACC_RNC__c, ACC_Nombre_Corto_Comercial__c, ACC_INT_Tipo_Estructura_Juridica__c,
                   ACC_Rango_de_Transacciones_estimadas__c, ACC_Persona_PEP__c,
                   ACC_INT_Pais_Nacimiento__c, ACC_INT_Pais_Residencia_Legal__c,
                   Industry, OwnerId, Owner.Name, Owner.Email, Owner.IsActive, Owner.Alias
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
            if (!config.Activo__c || !config.Auditoria_Activa__c) {
                System.debug('VFS_PLAAuditBatch: Proceso de auditoría pausado administrativamente vía PLA_Configuracion__c');
                return;
            }
        }

        this.totalEvaluated += scope.size();

        // 0. Auto-reparación preventiva: Garantizar que Cuentas Personales tengan ACC_Persona_Fisica__c = true
        List<Account> accountsToFix = new List<Account>();
        for (Account a : scope) {
            if (a.isPersonAccount && !a.ACC_Persona_Fisica__c) {
                accountsToFix.add(new Account(Id = a.Id, ACC_Persona_Fisica__c = true));
                a.ACC_Persona_Fisica__c = true; // Sincroniza en memoria para la auditoría actual
            }
        }
        if (!accountsToFix.isEmpty()) {
            Database.update(accountsToFix, false);
        }

        Set<Id> accountIds = new Map<Id, Account>(scope).keySet();
        Set<Id> industryIds = new Set<Id>();

        for (Account a : scope) {
            if (String.isNotBlank(a.Industry)) {
                try {
                    Id validId = (Id)a.Industry;
                    industryIds.add(validId);
                } catch (Exception exId) {
                    // Si el campo Industry contiene un texto libre o picklist en vez de Id
                }
            }
        }

        Map<Id, String> activityCodeMap = new Map<Id, String>();
        if (!industryIds.isEmpty()) {
            for (Datos_Maestros__c dm : [SELECT Id, DM_Direccion__c FROM Datos_Maestros__c WHERE Id IN :industryIds]) {
                activityCodeMap.put(dm.Id, dm.DM_Direccion__c);
            }
        }

        Map<Id, Informacion_Financiera__c> infoFinancieraMap = new Map<Id, Informacion_Financiera__c>();
        for (Informacion_Financiera__c inf : [
            SELECT Id, INF_Cuenta__c, INF_INT_Origen_de_los_recursos__c 
            FROM Informacion_Financiera__c 
            WHERE INF_Cuenta__c IN :accountIds
        ]) {
            infoFinancieraMap.put(inf.INF_Cuenta__c, inf);
        }

        Map<Id, FinServ__Employment__c> employmentMap = new Map<Id, FinServ__Employment__c>();
        for (FinServ__Employment__c emp : [
            SELECT Id, FinServ__Contact__r.AccountId, FinServ__Occupation__c 
            FROM FinServ__Employment__c 
            WHERE FinServ__Contact__r.AccountId IN :accountIds
        ]) {
            employmentMap.put(emp.FinServ__Contact__r.AccountId, emp);
        }

        Map<Id, FinServ__FinancialAccountRole__c> accionistaMap = new Map<Id, FinServ__FinancialAccountRole__c>();
        Map<Id, FinServ__FinancialAccountRole__c> repLegalMap = new Map<Id, FinServ__FinancialAccountRole__c>();

        for (FinServ__FinancialAccountRole__c role : [
            SELECT Id, FinServ__FinancialAccount__r.FinServ__PrimaryOwner__c,
                   OwnershipPercentage__c, FinServ__Role__c,
                   FinServ__RelatedAccount__r.ACC_INT_Tipo_de_identificacion__c,
                   FinServ__RelatedAccount__r.ACC_INT_Nacionalidad__c
            FROM FinServ__FinancialAccountRole__c 
            WHERE FinServ__FinancialAccount__r.FinServ__PrimaryOwner__c IN :accountIds
        ]) {
            if (role.FinServ__Role__c == 'Accionista') {
                accionistaMap.put(role.FinServ__FinancialAccount__r.FinServ__PrimaryOwner__c, role);
            } else if (role.FinServ__Role__c == 'Representante Legal') {
                repLegalMap.put(role.FinServ__FinancialAccount__r.FinServ__PrimaryOwner__c, role);
            }
        }

        Set<String> branchAliases = new Set<String>{
            'sprinc', 'smega', 'sstgo', 'sloved', 'spas27', 'sbav', 'sindep', 'spatcol', 'sagora', 'sucurs'
        };

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        List<Messaging.SingleEmailMessage> execEmails = new List<Messaging.SingleEmailMessage>();

        for (Account acc : scope) {
            String actCode = null;
            if (String.isNotBlank(acc.Industry)) {
                try {
                    actCode = activityCodeMap.get((Id)acc.Industry);
                } catch (Exception e) {}
            }
            Informacion_Financiera__c inf = infoFinancieraMap.get(acc.Id);
            FinServ__Employment__c emp = employmentMap.get(acc.Id);
            FinServ__FinancialAccountRole__c accRole = accionistaMap.get(acc.Id);
            FinServ__FinancialAccountRole__c repRole = repLegalMap.get(acc.Id);

            VFS_PLADataIntegrityService.AuditResult audit = VFS_PLADataIntegrityService.auditAccount(
                acc, inf, accRole, repRole, emp, actCode
            );

            if (audit.isComplete) {
                this.totalComplete++;
            } else {
                Boolean isBranchUser = false;
                if (acc.Owner != null && acc.Owner.Alias != null && branchAliases.contains(acc.Owner.Alias.toLowerCase())) {
                    isBranchUser = true;
                } else if (acc.Owner != null && acc.Owner.Name != null && acc.Owner.Name.toLowerCase().contains('sucursal')) {
                    isBranchUser = true;
                }

                String idNumber = '';
                if (acc.isPersonAccount) {
                    if (String.isNotBlank(acc.ACC_NumIdentificacion__c)) {
                        idNumber = acc.ACC_NumIdentificacion__c;
                    } else if (String.isNotBlank(acc.FinServ__IndividualId__c)) {
                        idNumber = acc.FinServ__IndividualId__c;
                    }
                } else {
                    idNumber = String.isNotBlank(acc.ACC_RNC__c) ? acc.ACC_RNC__c : '';
                }

                String fullLink = baseUrl + '/' + acc.Id;

                if (isBranchUser) {
                    this.totalIncompleteBranch++;
                    BranchIncompleteCase bCase = new BranchIncompleteCase();
                    bCase.branchCode = String.isNotBlank(acc.Owner.Alias) ? acc.Owner.Alias : 'N/D';
                    bCase.branchName = acc.Owner.Name;
                    bCase.clientName = acc.Name;
                    bCase.personType = acc.isPersonAccount ? 'Física' : 'Jurídica';
                    bCase.idType = String.isNotBlank(acc.ACC_INT_Tipo_de_identificacion__c) ? acc.ACC_INT_Tipo_de_identificacion__c : 'N/D';
                    bCase.idNumber = String.isNotBlank(idNumber) ? idNumber : 'Sin Identificación';
                    bCase.missingFieldsPLA = audit.missingFieldsSummary;
                    bCase.contactWarnings = audit.contactWarningsSummary;
                    bCase.recordUrl = fullLink;
                    this.branchCases.add(bCase);
                } else {
                    this.totalIncompleteExec++;
                    if (acc.Owner != null && String.isNotBlank(acc.Owner.Email) && acc.Owner.IsActive) {
                        Messaging.SingleEmailMessage mail = buildExecutiveEmail(acc, audit, fullLink);
                        execEmails.add(mail);
                    }
                }
            }
        }

        if (!execEmails.isEmpty() && Limits.getEmailInvocations() < Limits.getLimitEmailInvocations()) {
            try {
                Messaging.sendEmail(execEmails, false);
            } catch (Exception ex) {
                System.debug('Error enviando correos a ejecutivos: ' + ex.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!this.branchCases.isEmpty() && !this.branchManagerEmails.isEmpty()) {
            sendBranchConsolidatedReport();
        }

        System.debug('=== FIN VFS_PLAAuditBatch ===');
        System.debug('Evaluados: ' + this.totalEvaluated + ' | Completos: ' + this.totalComplete + 
                     ' | Incompletos Ejecutivo: ' + this.totalIncompleteExec + 
                     ' | Incompletos Sucursales: ' + this.totalIncompleteBranch);
    }

    private Messaging.SingleEmailMessage buildExecutiveEmail(Account acc, VFS_PLADataIntegrityService.AuditResult audit, String fullLink) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ acc.Owner.Email });
        mail.setSubject('⚠️ [PLA Vimenca] Regularización de Datos Requerida - ' + acc.Name);

        String idNum = acc.isPersonAccount ? acc.FinServ__IndividualId__c : acc.ACC_RNC__c;
        String htmlBody = '<div style="font-family: Arial, sans-serif; color: #333333; line-height: 1.5;">' +
            '<h2 style="color: #003366;">Aviso de Datos Pendientes para Precalificación PLA</h2>' +
            '<p>Estimado(a) <b>' + acc.Owner.Name + '</b>,</p>' +
            '<p>Se ha identificado que el siguiente cliente asignado a su cartera no cuenta con la totalidad de campos requeridos para la matriz de precalificación de riesgo PLA:</p>' +
            '<ul>' +
            '  <li><b>Cliente:</b> ' + acc.Name + '</li>' +
            '  <li><b>Identificación:</b> ' + (String.isNotBlank(idNum) ? idNum : 'N/D') + '</li>' +
            '  <li><b>Enlace Directo:</b> <a href="' + fullLink + '" style="color: #006699;">Abrir Ficha del Cliente en Salesforce</a></li>' +
            '</ul>' +
            '<h3 style="color: #c0392b;">Campos Pendientes por Completar:</h3>' +
            '<ol>';

        for (String field : audit.missingFields) {
            htmlBody += '<li><b>' + field + '</b></li>';
        }

        htmlBody += '</ol>' +
            '<p style="font-size: 11px; color: #7f8c8d;">Este proceso es automatizado por el Sistema de Prevención de Lavado de Activos (PLA) de Banco Vimenca.</p>' +
            '</div>';

        mail.setHtmlBody(htmlBody);
        return mail;
    }

    private void sendBranchConsolidatedReport() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(this.branchManagerEmails);
        mail.setSubject('📊 [PLA Vimenca] Informe Consolidado de Sucursales - Clientes con Datos Incompletos');

        String csvContent = 'Codigo_Sucursal,Nombre_Sucursal,Nombre_Cliente,Tipo_Persona,Tipo_Identificacion,Numero_Identificacion_o_RNC,Campos_Faltantes_PLA,Pendientes_Contacto,Enlace_Salesforce\n';
        for (BranchIncompleteCase c : this.branchCases) {
            csvContent += '"' + c.branchCode + '","' + 
                          c.branchName + '","' + 
                          c.clientName.replace('"', '""') + '","' + 
                          c.personType + '","' + 
                          c.idType + '","' + 
                          c.idNumber + '","' + 
                          c.missingFieldsPLA.replace('"', '""') + '","' + 
                          c.contactWarnings.replace('"', '""') + '","' + 
                          c.recordUrl + '"\n';
        }

        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setFileName('Informe_Consolidado_Sucursales_PLA_' + Datetime.now().format('yyyyMMdd') + '.csv');
        attachment.setBody(Blob.valueOf(csvContent));
        attachment.setContentType('text/csv');
        mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });

        String htmlBody = '<div style="font-family: Arial, sans-serif; color: #333333; line-height: 1.4;">' +
            '<h2 style="color: #003366;">Informe Consolidado de Clientes en Sucursales para Subsanación PLA</h2>' +
            '<p>Estimada Encargada General de Sucursales <b>(Laura Reynoso)</b>,</p>' +
            '<p>Se adjunta el reporte detallado con los <b>' + this.branchCases.size() + '</b> clientes radicados en usuarios virtuales de agencia que requieren actualización de datos obligatorios.</p>' +
            '<p>Puede abrir el archivo CSV adjunto para filtrar por sucursal y distribuir las listas operativas a cada oficina.</p>' +
            '<p style="font-size: 11px; color: #7f8c8d;">Generado automáticamente por el motor nocturno de integridad de datos PLA - Banco Vimenca.</p>' +
            '</div>';

        mail.setHtmlBody(htmlBody);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception e) {
            System.debug('Error enviando informe consolidado a supervisión: ' + e.getMessage());
        }
    }
}
