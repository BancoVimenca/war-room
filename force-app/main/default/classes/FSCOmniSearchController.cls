/**
 * @description       : Controlador para búsqueda unificada guiada en Utility Bar
 *                      Filtra Cuentas estrictamente a Persona Física y Jurídica para usuarios no administradores,
 *                      excluye Oportunidades y permite búsqueda en Leads, Casos, Tareas, Documentos y Notas.
 * @author            : Keystone Advisors
 * @group             : FSC Vimenca
**/
public with sharing class FSCOmniSearchController {

    private static final Set<String> ALLOWED_ACCOUNT_RTYPES = new Set<String>{
        'IndustriesIndividual',
        'PersonAccount',
        'Candidato_Persona_Fisica',
        'IndustriesBusiness',
        'Personas_Juridicas',
        'Candidato_Persona_Juridica'
    };

    public class SearchResultItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String sObjectType;
        @AuraEnabled public String sObjectLabel;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String extraInfo;
        @AuraEnabled public String iconName;
    }

    public class SearchResults {
        @AuraEnabled public List<SearchResultItem> accounts = new List<SearchResultItem>();
        @AuraEnabled public List<SearchResultItem> leads = new List<SearchResultItem>();
        @AuraEnabled public List<SearchResultItem> cases = new List<SearchResultItem>();
        @AuraEnabled public List<SearchResultItem> tasks = new List<SearchResultItem>();
        @AuraEnabled public List<SearchResultItem> files = new List<SearchResultItem>();
        @AuraEnabled public List<SearchResultItem> notes = new List<SearchResultItem>();
        @AuraEnabled public Integer totalCount = 0;
    }

    @AuraEnabled(cacheable=true)
    public static SearchResults searchOmni(String searchTerm) {
        SearchResults results = new SearchResults();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return results;
        }

        String sanitizedTerm = searchTerm.trim().replace('\'', '\\\'');
        Boolean isAdmin = isUserAdmin();

        // 1. Cuentas (Filtradas para no-admin)
        String accountQuery = 'SELECT Id, Name, FinServ__IndividualId__c, ACC_TipoIdentificacion__c, RecordType.Name, RecordType.DeveloperName FROM Account';
        if (!isAdmin) {
            accountQuery += ' WHERE RecordType.DeveloperName IN :ALLOWED_ACCOUNT_RTYPES';
        }
        accountQuery += ' LIMIT 20';

        String soslQuery = 'FIND \'' + sanitizedTerm + '*\' IN ALL FIELDS RETURNING ' +
            'Account(Id, Name, FinServ__IndividualId__c, ACC_NumIdentificacion__c, ACC_RNC__c, ACC_TipoIdentificacion__c, RecordType.Name, RecordType.DeveloperName ' +
                (!isAdmin ? 'WHERE RecordType.DeveloperName IN :ALLOWED_ACCOUNT_RTYPES ' : '') + 'LIMIT 20), ' +
            'Lead(Id, Name, Company, LEA_NumIdentificacion__c, LEA_RNC__c, LEA_TipoIdentificacion__c, Status, RecordType.Name LIMIT 20), ' +
            'Case(Id, CaseNumber, Subject, Status, Account.Name, Contact.Name, RecordType.Name LIMIT 20), ' +
            'Task(Id, Subject, Status, ActivityDate, Who.Name, What.Name LIMIT 20), ' +
            'ContentVersion(Id, Title, FileExtension, ContentDocumentId WHERE IsLatest = true LIMIT 20)';

        List<List<SObject>> searchList = Search.query(soslQuery);

        // Procesar Cuentas
        if (!searchList.isEmpty() && searchList[0] != null) {
            for (SObject sobj : searchList[0]) {
                Account acc = (Account) sobj;
                SearchResultItem item = new SearchResultItem();
                item.id = acc.Id;
                item.name = acc.Name;
                item.sObjectType = 'Account';
                item.sObjectLabel = acc.RecordType != null ? acc.RecordType.Name : 'Cuenta';
                item.iconName = 'standard:account';
                
                String docType = String.isNotBlank(acc.ACC_TipoIdentificacion__c) ? acc.ACC_TipoIdentificacion__c : 'Documento';
                String docNum = String.isNotBlank(acc.ACC_NumIdentificacion__c) ? acc.ACC_NumIdentificacion__c :
                                (String.isNotBlank(acc.FinServ__IndividualId__c) ? acc.FinServ__IndividualId__c : 
                                (String.isNotBlank(acc.ACC_RNC__c) ? acc.ACC_RNC__c : 'Sin N° Doc'));
                item.subtitle = docType + ': ' + docNum;
                item.extraInfo = acc.RecordType != null ? acc.RecordType.Name : '';
                results.accounts.add(item);
            }
        }

        // Procesar Leads
        if (searchList.size() > 1 && searchList[1] != null) {
            for (SObject sobj : searchList[1]) {
                Lead ld = (Lead) sobj;
                SearchResultItem item = new SearchResultItem();
                item.id = ld.Id;
                item.name = ld.Name;
                item.sObjectType = 'Lead';
                item.sObjectLabel = 'Candidato';
                item.iconName = 'standard:lead';

                String doc = String.isNotBlank(ld.LEA_NumIdentificacion__c) ? ld.LEA_NumIdentificacion__c : (String.isNotBlank(ld.LEA_RNC__c) ? ld.LEA_RNC__c : ld.Company);
                item.subtitle = (String.isNotBlank(ld.LEA_TipoIdentificacion__c) ? ld.LEA_TipoIdentificacion__c + ': ' : '') + (doc != null ? doc : '');
                item.extraInfo = 'Estado: ' + ld.Status;
                results.leads.add(item);
            }
        }

        // Procesar Casos
        if (searchList.size() > 2 && searchList[2] != null) {
            for (SObject sobj : searchList[2]) {
                Case cs = (Case) sobj;
                SearchResultItem item = new SearchResultItem();
                item.id = cs.Id;
                item.name = cs.CaseNumber + (String.isNotBlank(cs.Subject) ? ' - ' + cs.Subject : '');
                item.sObjectType = 'Case';
                item.sObjectLabel = cs.RecordType != null ? cs.RecordType.Name : 'Caso';
                item.iconName = 'standard:case';

                String cliente = cs.Account != null ? cs.Account.Name : (cs.Contact != null ? cs.Contact.Name : '');
                item.subtitle = String.isNotBlank(cliente) ? 'Cliente: ' + cliente : 'Sin cliente asociado';
                item.extraInfo = 'Estado: ' + cs.Status;
                results.cases.add(item);
            }
        }

        // Procesar Tareas
        if (searchList.size() > 3 && searchList[3] != null) {
            for (SObject sobj : searchList[3]) {
                Task tsk = (Task) sobj;
                SearchResultItem item = new SearchResultItem();
                item.id = tsk.Id;
                item.name = String.isNotBlank(tsk.Subject) ? tsk.Subject : 'Tarea sin asunto';
                item.sObjectType = 'Task';
                item.sObjectLabel = 'Tarea';
                item.iconName = 'standard:task';

                String rel = tsk.What != null ? tsk.What.Name : (tsk.Who != null ? tsk.Who.Name : '');
                item.subtitle = String.isNotBlank(rel) ? 'Relacionado: ' + rel : 'Sin relación';
                item.extraInfo = (tsk.ActivityDate != null ? 'Vencimiento: ' + tsk.ActivityDate.format() + ' | ' : '') + 'Estado: ' + tsk.Status;
                results.tasks.add(item);
            }
        }

        // Procesar Archivos / Documentos
        if (searchList.size() > 4 && searchList[4] != null) {
            for (SObject sobj : searchList[4]) {
                ContentVersion cv = (ContentVersion) sobj;
                SearchResultItem item = new SearchResultItem();
                item.id = cv.ContentDocumentId;
                item.name = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
                item.sObjectType = 'ContentDocument';
                item.sObjectLabel = 'Archivo';
                item.iconName = 'standard:file';
                item.subtitle = 'Documento adjunto';
                item.extraInfo = String.isNotBlank(cv.FileExtension) ? cv.FileExtension.toUpperCase() : 'ARCHIVO';
                results.files.add(item);
            }
        }

        // 2. Búsqueda de Notas (ContentNote)
        try {
            String noteTerm = '%' + sanitizedTerm + '%';
            for (ContentNote cn : [SELECT Id, Title, TextPreview FROM ContentNote WHERE Title LIKE :noteTerm LIMIT 10]) {
                SearchResultItem item = new SearchResultItem();
                item.id = cn.Id;
                item.name = cn.Title;
                item.sObjectType = 'ContentNote';
                item.sObjectLabel = 'Nota';
                item.iconName = 'standard:note';
                item.subtitle = String.isNotBlank(cn.TextPreview) ? (cn.TextPreview.length() > 80 ? cn.TextPreview.left(80) + '...' : cn.TextPreview) : 'Nota de texto';
                item.extraInfo = 'Nota';
                results.notes.add(item);
            }
        } catch (Exception ignoreNoteException) {
            System.debug('ContentNote search skipped: ' + ignoreNoteException.getMessage());
        }

        results.totalCount = results.accounts.size() + results.leads.size() + results.cases.size() +
                             results.tasks.size() + results.files.size() + results.notes.size();

        return results;
    }

    @TestVisible
    private static Boolean isUserAdmin() {
        return FeatureManagement.checkPermission('ViewAllData') ||
               UserInfo.getProfileId() == [SELECT Id FROM Profile WHERE Name = 'System Administrator' OR Name = 'Administrador del sistema' LIMIT 1].Id;
    }
}