/**
 * @description       : Servicio de validación de integridad de datos obligatorios para la precalificación PLA en FSC
 *                      Verifica la completitud del 100% de campos requeridos por el servicio MacroProcesos (MPTransactionRest)
 *                      soportando tanto la arquitectura moderna FSC (Account UI fields, FinServ__Employment__c, Datos_Maestros__c SIB)
 *                      como los campos legados de integración (ACC_INT_...).
 * @author            : @dev-salesforce / Keystone Advisors
 * @group             : PLA Vimenca
 * @last modified on  : 2026-11-14
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
     * @description Evalúa la completitud de una Cuenta bajo la arquitectura FSC (Persona Física o Jurídica)
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

        // 1. Identificación Común (Resolución Inteligente FSC / Trama)
        String idType = String.isNotBlank(acc.ACC_INT_Tipo_de_identificacion__c) ? acc.ACC_INT_Tipo_de_identificacion__c : acc.ACC_TipoIdentificacion__c;
        if (String.isBlank(idType)) {
            result.addMissingField('Tipo de Identificación');
        }

        Boolean isPhysical = acc.isPersonAccount || acc.ACC_Persona_Fisica__c;

        if (isPhysical) {
            // Número de Identificación (Cédula / Pasaporte)
            String idNum = String.isNotBlank(acc.ACC_NumIdentificacion__c) ? acc.ACC_NumIdentificacion__c : acc.FinServ__IndividualId__c;
            if (String.isBlank(idNum)) {
                result.addMissingField('Número de Identificación (Cédula/Pasaporte)');
            }
            if (acc.PersonBirthdate == null) {
                result.addMissingField('Fecha de Nacimiento');
            }
            // Nacionalidad (FSC nativo / Trama)
            String nationality = String.isNotBlank(acc.ACC_INT_Nacionalidad__c) ? acc.ACC_INT_Nacionalidad__c : acc.ACC_Nacionalidad__c;
            if (String.isBlank(nationality)) {
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

        // 2. Información Financiera (Arquitectura Nativa FSC: Account Balances o Registro Custom)
        Boolean hasFinancialData = false;
        if (infoFinanciera != null && String.isNotBlank(infoFinanciera.INF_INT_Origen_de_los_recursos__c)) {
            hasFinancialData = true;
        } else if (acc.ACC_Total_Activos__c != null || acc.ACC_Ventas_Ingresos_Anuales__c != null) {
            hasFinancialData = true;
        }

        if (!hasFinancialData) {
            result.addMissingField('Información Financiera (Activos, Ingresos u Origen de Recursos)');
        }

        // 3. Actividad Económica (FSC: Lookup SIB Datos_Maestros__c o Industry)
        Boolean hasActivity = String.isNotBlank(activityCode) || acc.ACC_Actividad_Economica__c != null || String.isNotBlank(acc.Industry);
        if (!hasActivity) {
            result.addMissingField('Actividad Económica (Actividad SIB / Datos Maestros)');
        }

        // 4. Parámetros Transaccionales y Prevención
        if (String.isBlank(acc.ACC_Rango_de_Transacciones_estimadas__c)) {
            result.addMissingField('Rango de Transacciones Estimadas');
        }
        if (acc.ACC_Persona_PEP__c == null) {
            result.addMissingField('Declaración Persona PEP');
        }

        // 5. Validaciones Específicas Persona Física (FSC Employment / Residencia)
        if (isPhysical) {
            Boolean hasOccupation = (history != null && String.isNotBlank(history.FinServ__Occupation__c)) ||
                                    String.isNotBlank(acc.ACC_Tipo_Actividad__c);
            if (!hasOccupation) {
                result.addMissingField('Historial Laboral / Ocupación');
            }
            
            String birthCountry = String.isNotBlank(acc.ACC_INT_Pais_Nacimiento__c) ? acc.ACC_INT_Pais_Nacimiento__c : acc.ACC_Pais_Nacimiento__c;
            if (String.isBlank(birthCountry)) {
                result.addMissingField('País de Nacimiento');
            }
            
            String resCountry = String.isNotBlank(acc.ACC_INT_Pais_Residencia_Legal__c) ? acc.ACC_INT_Pais_Residencia_Legal__c : acc.ACC_Pais_Residencia_Legal__c;
            if (String.isBlank(resCountry)) {
                result.addMissingField('País de Residencia Legal');
            }
        } else {
            // Validaciones Específicas Persona Jurídica (Partes Relacionadas FSC)
            if (accionista == null) {
                result.addMissingField('Accionista Principal no asignado');
            } else {
                if (accionista.OwnershipPercentage__c == null || accionista.OwnershipPercentage__c <= 0) {
                    result.addMissingField('Porcentaje de Participación Accionaria');
                }
                String accIdType = accionista.FinServ__RelatedAccount__r != null ? 
                    (String.isNotBlank(accionista.FinServ__RelatedAccount__r.ACC_INT_Tipo_de_identificacion__c) ? 
                        accionista.FinServ__RelatedAccount__r.ACC_INT_Tipo_de_identificacion__c : 
                        accionista.FinServ__RelatedAccount__r.ACC_TipoIdentificacion__c) : null;
                if (String.isBlank(accIdType)) {
                    result.addMissingField('Identificación del Accionista Principal');
                }
            }

            if (repLegal == null) {
                result.addMissingField('Representante Legal no asignado');
            } else {
                String repIdType = repLegal.FinServ__RelatedAccount__r != null ? 
                    (String.isNotBlank(repLegal.FinServ__RelatedAccount__r.ACC_INT_Tipo_de_identificacion__c) ? 
                        repLegal.FinServ__RelatedAccount__r.ACC_INT_Tipo_de_identificacion__c : 
                        repLegal.FinServ__RelatedAccount__r.ACC_TipoIdentificacion__c) : null;
                if (String.isBlank(repIdType)) {
                    result.addMissingField('Identificación del Representante Legal');
                }
            }
        }

        result.finalizeSummary();
        return result;
    }
}
