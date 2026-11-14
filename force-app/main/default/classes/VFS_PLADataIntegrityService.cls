/**
 * @description       : Servicio de validación de integridad de datos obligatorios para la precalificación PLA
 *                      Verifica la completitud del 100% de campos requeridos por el servicio MacroProcesos (MPTransactionRest)
 *                      tanto para Personas Físicas como Personas Jurídicas.
 * @author            : @dev-salesforce / Keystone Advisors
 * @group             : PLA Vimenca
 * @last modified on  : 2026-11-13
**/
public with sharing class VFS_PLADataIntegrityService {

    public class AuditResult {
        public Boolean isComplete { get; set; }
        public Boolean isPrequalificationReady { get; set; }
        public List<String> missingFields { get; set; }
        public String missingFieldsSummary { get; set; }
        public List<String> contactWarnings { get; set; }
        public String contactWarningsSummary { get; set; }

        public AuditResult() {
            this.isComplete = true;
            this.isPrequalificationReady = true;
            this.missingFields = new List<String>();
            this.missingFieldsSummary = '';
            this.contactWarnings = new List<String>();
            this.contactWarningsSummary = 'Contacto Completo';
        }

        public void addMissingField(String fieldLabel) {
            this.isComplete = false;
            this.isPrequalificationReady = false;
            this.missingFields.add(fieldLabel);
        }

        public void addContactWarning(String warningLabel) {
            this.isComplete = false;
            this.contactWarnings.add(warningLabel);
        }

        public void finalizeSummary() {
            if (this.missingFields.isEmpty()) {
                this.isPrequalificationReady = true;
                this.missingFieldsSummary = 'Ninguno (Apto para Precalificación)';
            } else {
                this.isPrequalificationReady = false;
                this.missingFieldsSummary = String.join(this.missingFields, '; ');
            }

            if (this.contactWarnings.isEmpty()) {
                this.contactWarningsSummary = 'Contacto Completo';
            } else {
                this.contactWarningsSummary = String.join(this.contactWarnings, '; ');
            }

            this.isComplete = this.missingFields.isEmpty() && this.contactWarnings.isEmpty();
        }
    }

    /**
     * @description Evalúa la completitud de una Cuenta (Persona Física o Jurídica)
     */
    public static AuditResult auditAccount(
        Account acc, 
        Informacion_Financiera__c infoFinanciera, 
        FinServ__FinancialAccountRole__c accionista, 
        FinServ__FinancialAccountRole__c repLegal, 
        FinServ__Employment__c history,
        String activityCode
    ) {
        AuditResult result = new AuditResult();

        if (acc == null) {
            result.addMissingField('Registro de Cuenta Nulo');
            result.finalizeSummary();
            return result;
        }

        // 1. Identificación y Datos Generales Comunes
        if (String.isBlank(acc.ACC_INT_Tipo_de_identificacion__c)) {
            result.addMissingField('Tipo de Identificación');
        }

        Boolean isPhysical = acc.isPersonAccount || acc.ACC_Persona_Fisica__c;

        if (isPhysical) {
            if (String.isBlank(acc.FinServ__IndividualId__c) && String.isBlank(acc.ACC_NumIdentificacion__c)) {
                result.addMissingField('Número de Identificación (Cédula/Pasaporte)');
            }
            if (acc.PersonBirthdate == null) {
                result.addMissingField('Fecha de Nacimiento');
            }
            if (String.isBlank(acc.ACC_INT_Nacionalidad__c)) {
                result.addMissingField('Nacionalidad');
            }
            if (String.isBlank(acc.ACC_Estado_Civil__c)) {
                result.addMissingField('Estado Civil');
            }
            // Alertas Operativas de Contacto (NO bloquean la precalificación PLA en MacroProcesos)
            if (String.isBlank(acc.PersonEmail) && String.isBlank(acc.ACC_Correo_Electronico_Cliente__c)) {
                result.addContactWarning('Sin Correo Electrónico');
            }
            if (String.isBlank(acc.PersonMobilePhone) && String.isBlank(acc.Phone)) {
                result.addContactWarning('Sin Teléfono Registrado');
            }
        } else {
            // Persona Jurídica
            if (String.isBlank(acc.ACC_RNC__c)) {
                result.addMissingField('RNC');
            }
            if (String.isBlank(acc.ACC_Nombre_Corto_Comercial__c) && String.isBlank(acc.Name)) {
                result.addMissingField('Razón Social / Nombre Comercial');
            }
            if (acc.ACC_Fecha_Fundacion__c == null) {
                result.addMissingField('Fecha de Constitución');
            }
            if (String.isBlank(acc.ACC_INT_Tipo_Estructura_Juridica__c)) {
                result.addMissingField('Tipo de Estructura Jurídica');
            }
        }

        // 2. Información Financiera
        if (infoFinanciera == null) {
            result.addMissingField('Información Financiera (Registro)');
        } else {
            if (String.isBlank(infoFinanciera.INF_INT_Origen_de_los_recursos__c)) {
                result.addMissingField('Información Financiera (Origen de los Recursos)');
            }
        }

        // 3. Actividad Económica
        if (String.isBlank(activityCode)) {
            result.addMissingField('Actividad Económica (Industry / Datos Maestros)');
        }

        // 4. Parámetros Transaccionales y Prevención
        if (String.isBlank(acc.ACC_Rango_de_Transacciones_estimadas__c)) {
            result.addMissingField('Rango de Transacciones Estimadas');
        }
        if (acc.ACC_Persona_PEP__c == null) {
            result.addMissingField('Declaración Persona PEP');
        }

        // 5. Validaciones Específicas Persona Física
        if (isPhysical) {
            if (history == null || String.isBlank(history.FinServ__Occupation__c)) {
                result.addMissingField('Historial Laboral / Ocupación');
            }
            if (String.isBlank(acc.ACC_INT_Pais_Nacimiento__c)) {
                result.addMissingField('País de Nacimiento');
            }
            if (String.isBlank(acc.ACC_INT_Pais_Residencia_Legal__c)) {
                result.addMissingField('País de Residencia Legal');
            }
        } else {
            // Validaciones Específicas Persona Jurídica (Partes Relacionadas)
            if (accionista == null) {
                result.addMissingField('Accionista Principal no asignado');
            } else {
                if (accionista.OwnershipPercentage__c == null || accionista.OwnershipPercentage__c <= 0) {
                    result.addMissingField('Porcentaje de Participación Accionaria');
                }
                if (accionista.FinServ__RelatedAccount__r == null || String.isBlank(accionista.FinServ__RelatedAccount__r.ACC_INT_Tipo_de_identificacion__c)) {
                    result.addMissingField('Identificación del Accionista Principal');
                }
            }

            if (repLegal == null) {
                result.addMissingField('Representante Legal no asignado');
            } else {
                if (repLegal.FinServ__RelatedAccount__r == null || String.isBlank(repLegal.FinServ__RelatedAccount__r.ACC_INT_Tipo_de_identificacion__c)) {
                    result.addMissingField('Identificación del Representante Legal');
                }
            }
        }

        result.finalizeSummary();
        return result;
    }
}
