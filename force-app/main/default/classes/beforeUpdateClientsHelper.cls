public with sharing class beforeUpdateClientsHelper {
    private static final Set<String> INT007_SYNC_FIELDS = new Set<String>{
        'ACC_NumIdentificacion__c', 'ACC_TipoIdentificacion__c', 'FirstName', 'MiddleName', 'LastName', 'Suffix',
        'ACC_Genero__c', 'ACC_Estado_Civil__c', 'PersonBirthdate', 'ACC_Nacionalidad__c', 'ACC_Tipo_Cliente_PF__c',
        'ACC_Tipo_Sector__c', 'ACC_Tipo_Actividad__c', 'ACC_Segmento__c', 'ACC_Total_Activos__c', 'ACC_Moneda__c',
        'ACC_Ventas_Ingresos_Anuales__c', 'ACC_NumEmpleados__c', 'ACC_N_Identificacion_Anterior__c',
        'ACC_Tipo_Identificacion_Anterior__c', 'ACC_Tipo_Persona_PF__c', 'Actividad_Economica_Name__c',
        'ACC_Otra_Nacionalidad__c', 'ACC_Pais_Nacimiento__c', 'ACC_Provincia_Nacimiento__c',
        'ACC_Ciudad_de_nacimiento__c', 'Ciudad_Nacimiento_Codigo__c', 'ACC_Tipo_Vinculacion__c',
        'ACC_Nombre_Puesto__c', 'ACC_Nombre_Ejecutivo__c', 'ACC_NumOficina__c', 'ACC_Zona__c',
        'ACC_Residencia_Rep_Dom__c', 'ACC_Posee_Resid_Otro_Pais__c', 'Tipo_de_vivienda__c',
        'ACC_Tipo_Depositante__c', 'ACC_Relacion_Exterior__c', 'ACC_Fuente_Informacion__c',
        'ACC_Fecha_Informacion__c', 'ACC_Patrimonio_Num__c', 'ACC_Patrimonio_Desc__c', 'ACC_Persona_PEP__c',
        'ACC_Primer_Nombre_PEP__c', 'ACC_Segundo_Nombre_PEP__c', 'ACC_Tipo_Relacion_PEP__c',
        'ACC_Ocupacion_PEP__c', 'ACC_Institucion_Trabajo_PEP__c', 'ACC_Direccion_Trabajo_PEP__c',
        'ACC_Tipo_Identif_PEP__c', 'ACC_N_Identificacion_PEP__c', 'ACC_Aplica_FATCA__c', 'ACC_Nombre_FATCA__c',
        'ACC_Apellido_FATCA__c', 'ACC_N_Pasaporte_FATCA__c', 'ACC_Fecha_Expiracion_FATCA__c', 'ACC_TIN_FATCA__c',
        'ACC_SSN_FATCA__c', 'ACC_Nacionalidad_FATCA__c', 'ACC_Direccion_FATCA__c', 'ACC_Ciudad_FATCA__c',
        'ACC_Estado_FATCA__c', 'ACC_Codigo_Postal_FATCA__c', 'ACC_Telefono_FATCA__c', 'ACC_Es_Mayor_de_Edad__c',
        'ACC_Cliente_Conocido__c', 'ACC_Es_Empleado_Vimenca__c'
    };

    @TestVisible
    private static Boolean hasDemographicChanges(Account newAcc, Account oldAcc) {
        if (newAcc == null || oldAcc == null) {
            return false;
        }
        for (String fieldName : INT007_SYNC_FIELDS) {
            Object newVal = newAcc.get(fieldName);
            Object oldVal = oldAcc.get(fieldName);
            if (newVal != oldVal) {
                return true;
            }
        }
        return false;
    }

    public void updateCIF(Account recordT, Account recordTCondition) {
        System.debug('------NEW: ' + recordT);
        System.debug('------NEW: ' + recordT.ACC_Condicion__c);
        System.debug('------NEW: ' + recordT.ACC_Estado__c);
        System.debug('------OLD: ' + recordTCondition.ACC_Estado__c);
        System.debug('------OLD: ' + recordTCondition.ACC_Condicion__c);
        System.debug('------OLD: ' + recordTCondition);
        Boolean personAccountAndProspect = false;
        if (recordT.ACC_Condicion__c == 'CLIENTE' && recordT.ACC_Estado__c == 'CREADO') {
            personAccountAndProspect = (recordTCondition.ACC_Condicion__c == 'PROSPECTO' && recordTCondition.ACC_Estado__c == 'CONVERTIR') ? true : false;
        }
        System.debug('Person Account Condition Result: ' + personAccountAndProspect);
        if (personAccountAndProspect) {
            if (recordTCondition.RecordTypeId == Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Fisica').getRecordTypeId()) {
                INT007_FSC.creteClient(recordTCondition.Id);
                System.debug('Prueba CIF :: ' + recordT.ACC_CIF__c);
            } else if (recordTCondition.RecordTypeId == Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Juridica').getRecordTypeId()) {
                INT008.creteClientJ(recordTCondition.Id);
            }
            personAccountAndProspect = false;
        } else if (recordTCondition.RecordTypeId == Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId()) {
            if (System.isBatch() == false && System.isFuture() == false && !Test.isRunningTest()) {
                // BVWAR / SOL-0328: Solo gatillar INT007 modificación si hubo cambios en campos demográficos relevantes
                if (hasDemographicChanges(recordT, recordTCondition)) {
                    System.debug('beforeUpdateClientsHelper: Cambios demograficos detectados en Cuenta ' + recordTCondition.Id + '. Invocando INT007_FSC.modifiClient.');
                    INT007_FSC.modifiClient(recordTCondition.Id, 'M');
                } else {
                    System.debug('beforeUpdateClientsHelper: Sin cambios demograficos en Cuenta ' + recordTCondition.Id + '. Se omite llamada redundante a INT007_FSC.');
                }
            }
        }
    }
    // public void CalculateClasification(Account recordT,String oldClientType,String oldOrganitationtType){
    public void CalculateClasification(Account recordT,Account recordOld){
        List<String> excludeFields = new list<String> {'FIDEICOMISOS','ASOCIACIONES SIN FINES DE LUCRO','INSTITUCIONES SIN FINES DE LUCRO EXTRANJERAS','SINDICATOS EMPRESARIALES','CONDOMINIOS','PARTIDOS POLITICOS','EMBAJADAS Y/O DELEGACIONES DIPLOMÁTICAS','ASOCIACIONES RELIGIOSAS DE LA IGLESIA CATÓLICA','ONG EXTRANJERA PRIVADA','ONG EXTRANJERA PÚBLICA','INSTITUCIONES DEL SECTOR PÚBLICO NO FINANCIERO','MUNICIPIOS Y DISTRITOS MUNICIPALES','INSTITUCIONES DEL SECTOR PÚBLICO FINANCIERO: BNV Y BANCO AGRICOLA'};
            System.debug('VENTAS :: '+recordT.ACC_Volumen_Ventas_Anual__c  );
            if(!excludeFields.contains(recordT.ACC_Tipo_Organizacion__c) 
               &&( recordOld.ACC_Tipo_Organizacion__c!= recordT.ACC_Tipo_Organizacion__c
                  || recordOld.ACC_Clasificacion_Empresa__c!= recordT.ACC_Clasificacion_Empresa__c
                  || recordOld.ACC_NumEmpleados__c!= recordT.ACC_NumEmpleados__c 
                  || recordOld.ACC_Volumen_Ventas_Anual__c!= recordT.ACC_Volumen_Ventas_Anual__c 
                  || recordOld.ACC_Total_Activos__c!= recordT.ACC_Total_Activos__c )
               &&!recordT.ACC_Persona_Fisica__c && recordT.ACC_NumEmpleados__c >=0 
               && recordT.ACC_Volumen_Ventas_Anual__c >=0 && recordT.ACC_Total_Activos__c >=0){
                   System.debug('ENTRA TRIGGER');  
                   double indicador =(recordT.ACC_NumEmpleados__c /decimal.valueOf(Label.Max_Empleado))*
                       ( recordT.ACC_Total_Activos__c /decimal.valueOf(Label.Max_Activos))*
                       ( recordT.ACC_Volumen_Ventas_Anual__c /decimal.valueOf(Label.Max_Ventas));
                   double frac = 1.0/3.0;
                   double indicadorRaiz = Math.pow(indicador, frac);
                   System.debug('Fire Trieger good' + indicadorRaiz );
                   if (indicadorRaiz < 0){
                       recordT.addError('Alguno de los valores introducidos es negativo.');
                   }else if (indicadorRaiz >= 0  && indicadorRaiz <= 0.06){                  
                       asingClasification(recordT,recordOld,'Micro');                
                   } else if (indicadorRaiz > 0.06 && indicadorRaiz <= 0.29)  {
                       asingClasification(recordT,recordOld,'Pequeña');
                   } else if (indicadorRaiz > 0.29 && indicadorRaiz <= 1.0){
                       asingClasification(recordT,recordOld,'Mediana');                       
                   }else if (indicadorRaiz > 1.0){
                       asingClasification(recordT,recordOld,'Corporativa');                       
                   }            
                   if (recordOld.ACC_Clasificacion_Empresa__c != null && recordT.ACC_Clasificacion_Empresa__c != recordOld.ACC_Clasificacion_Empresa__c) {
                       recordT.ACC_Tipo_Cliente_PJ__c = '';
                   }
                   // records.add(recordT);
               }else if( recordT.ACC_NumEmpleados__c ==null 
               || recordT.ACC_Volumen_Ventas_Anual__c ==null || recordT.ACC_Total_Activos__c ==null){
                   recordT.ACC_Clasificacion_Empresa__c=null;
               }        
    }
    private  void asingClasification(Account recordT,Account recordOld,String clasification){
        if(recordT.ACC_Clasificacion_Empresa__c== clasification || recordT.ACC_Clasificacion_Empresa__c==null
           ||( recordOld.ACC_NumEmpleados__c!= recordT.ACC_NumEmpleados__c || recordOld.ACC_Volumen_Ventas_Anual__c!= recordT.ACC_Volumen_Ventas_Anual__c || recordOld.ACC_Total_Activos__c!= recordT.ACC_Total_Activos__c )){
                  recordT.ACC_Clasificacion_Empresa__c=clasification;   
              }else{
                  recordT.ACC_Clasificacion_Empresa__c.addError('Para esta organización solo es permitida la clasificación "'+clasification+'".');           
              }    
    }
    
    public void Traducir_Valores_Cliente(Account Acc){
        if(Acc.ACC_Fuente_Informacion__c !='' ){            
            Acc.ACC_Fuente_de_informacion_traduccion__c = Acc.ACC_Fuente_Informacion__c== NULL ? '' : generalUtils.pickListGetLabel(Account.ACC_Fuente_Informacion__c.getDescribe(), Acc.ACC_Fuente_Informacion__c);            
        }
        if (Acc.ACC_Persona_Fisica__c){            
            if(Acc.ACC_Tipo_Persona_PF__c !=''){                
                Acc.ACC_Traduccion_tipo_persona__c = Acc.ACC_Tipo_Persona_PF__c == NULL ? '' : generalUtils.pickListGetLabel(Account.ACC_Tipo_Persona_PF__c.getDescribe(), Acc.ACC_Tipo_Persona_PF__c);                
            }  
            if(Acc.ACC_Tipo_Cliente_PF__c !=''){                
                Acc.ACC_Traduccion_tipo_cliente__c  = Acc.ACC_Tipo_Cliente_PF__c  == NULL ? '' : generalUtils.pickListGetLabel(Account.ACC_Tipo_Cliente_PF__c.getDescribe(), Acc.ACC_Tipo_Cliente_PF__c);                
            }  
        }else{            
            if(Acc.ACC_Tipo_Cliente_PJ__c !=''){                
                Acc.ACC_Traduccion_tipo_cliente__c  = Acc.ACC_Tipo_Cliente_PJ__c  == NULL ? '' : generalUtils.pickListGetLabel(Account.ACC_Tipo_Cliente_PJ__c.getDescribe(), Acc.ACC_Tipo_Cliente_PJ__c  );                
            } 
            if(Acc.ACC_Tipo_Persona_PJ__c !=''){                
                Acc.ACC_Traduccion_tipo_persona__c = Acc.ACC_Tipo_Persona_PJ__c == NULL ? '' : generalUtils.pickListGetLabel(Account.ACC_Tipo_Persona_PJ__c.getDescribe(), Acc.ACC_Tipo_Persona_PJ__c);                
            }
        }                
    }
}