@IsTest
private class VFS_LeadAreaResponsableServiceTest {

    @IsTest
    static void testGetAreaResponsable_NullRecordId() {
        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(null);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Negocios', info.areaResponsable);
        System.assertEquals(true, info.isNegocios);
    }

    @IsTest
    static void testGetAreaResponsable_LeadNoExistente() {
        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable('00Q000000000000AAA');
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Negocios', info.areaResponsable);
    }

    @IsTest
    static void testGetAreaResponsable_ConCampoInformado() {
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Empresa Test',
            Status = 'Iniciado',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999991',
            LEA_Area_Responsable__c = 'Bandeja PLA / Cumplimiento'
        );
        insert l;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Bandeja PLA / Cumplimiento', info.areaResponsable);
        System.assertEquals(true, info.isPLA);
    }

    @IsTest
    static void testGetAreaResponsable_ValidadoListoConversion() {
        Lead l = new Lead(
            LastName = 'Test Lead 2',
            Company = 'Empresa Test 2',
            Status = 'Validado',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999992'
        );
        insert l;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Aprobado / Listo para Conversión', info.areaResponsable);
        System.assertEquals(true, info.isReadyOrApproved);
        System.assertEquals('El prospecto se encuentra:', info.messagePrefix);
    }

    @IsTest
    static void testGetAreaResponsable_ValidadoConDocsPendientes() {
        Lead l = new Lead(
            LastName = 'Test Lead Docs Pendientes',
            Company = 'Empresa Test',
            Status = 'Validado',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999994',
            LEA_Doc_Legal_No_Aprobada__c = 2
        );
        insert l;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Negocios', info.areaResponsable, 'Si tiene documentos legales pendientes, debe volver a Negocios');
        System.assertEquals(true, info.isNegocios);
    }

    @IsTest
    static void testGetAreaResponsable_RechazadoVuelveANegocios() {
        Lead l = new Lead(
            LastName = 'Test Lead Rechazado',
            Company = 'Empresa Test',
            Status = 'Validado',
            LEA_SubEstado__c = 'RECHAZADO',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999995'
        );
        insert l;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Negocios', info.areaResponsable, 'Si fue rechazado, debe volver a Negocios');
        System.assertEquals(true, info.isNegocios);
    }

    @IsTest
    static void testGetAreaResponsable_ConProcesoTecnologiaPendiente() {
        Lead l = new Lead(
            LastName = 'Castillo',
            FirstName = 'Maria',
            Company = 'Particular',
            Status = 'Iniciado',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999993'
        );
        insert l;

        // Enviar a aprobación de tecnología
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(l.Id);
        req.setProcessDefinitionNameOrId('PA_Aprobacion_Tecnologia_LEAD');
        req.setSkipEntryCriteria(true);
        Approval.ProcessResult submitResult = Approval.process(req);
        System.assertEquals(true, submitResult.isSuccess(), 'El Lead debe entrar a aprobación de tecnología');

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Bandeja Tecnologia', info.areaResponsable, 'Debe detectar dinámicamente que está en Bandeja Tecnologia');
        System.assertEquals(true, info.isTecnologia);
    }

    @IsTest
    static void testGetAreaResponsable_ConDocsEnRevisionLegal() {
        Account acc = new Account(Name = 'Cuenta Test Legal Revision');
        insert acc;

        Lead l = new Lead(
            LastName = 'Test Doc Revision',
            Company = 'Empresa Revision',
            Status = 'Validado',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999998'
        );
        insert l;

        Documentacion_Legal__c doc = new Documentacion_Legal__c(
            DOC_Cliente__c = acc.Id,
            DOC_Candidato__c = l.Id,
            DOC_Estado__c = 'PENDIENTE',
            DOC_Sub_Estado__c = 'NO RECIBIDO'
        );
        insert doc;
        doc.DOC_Estado__c = 'EN REVISION LEGAL';
        doc.DOC_Sub_Estado__c = null;
        update doc;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Bandeja Validación Legal', info.areaResponsable);
        System.assertEquals(true, info.isLegal);
        System.assertEquals('El prospecto se encuentra actualmente en revisión documental por:', info.messagePrefix);
    }

    @IsTest
    static void testGetAreaResponsable_ConDocsDevueltos() {
        Account acc = new Account(Name = 'Cuenta Test Legal Devuelto');
        insert acc;

        Lead l = new Lead(
            LastName = 'Test Doc Devuelto',
            Company = 'Empresa Devuelto',
            Status = 'Validado',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999999'
        );
        insert l;

        Documentacion_Legal__c doc = new Documentacion_Legal__c(
            DOC_Cliente__c = acc.Id,
            DOC_Candidato__c = l.Id,
            DOC_Estado__c = 'DEVUELTO',
            DOC_Sub_Estado__c = 'ERROR EN DOCUMENTO'
        );
        insert doc;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Negocios', info.areaResponsable);
        System.assertEquals(true, info.isNegocios);
        System.assert(info.messagePrefix.contains('observaciones legales pendientes de subsanación'));
        System.assert(info.messagePrefix.contains('Actividad'));
    }

    @IsTest
    static void testGetAreaResponsable_PJ_Validado_PermaneceEnNegocios() {
        Id pjRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Juridica')?.getRecordTypeId();
        Lead l = new Lead(
            LastName = 'Empresa Test PJ',
            Company = 'Empresa Test PJ SRL',
            Status = 'Validado',
            LEA_RNC__c = '130999991',
            RecordTypeId = pjRecordTypeId
        );
        insert l;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Negocios', info.areaResponsable, 'Un prospecto PJ en estado Validado sin proceso de aprobación debe estar en Negocios');
        System.assertEquals(true, info.isNegocios);
        System.assertEquals('El prospecto se encuentra actualmente en proceso de ingreso y validación de datos por:', info.messagePrefix);
    }

    @IsTest
    static void testGetAreaResponsable_PJ_AprobadoFormal() {
        Id pjRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Juridica')?.getRecordTypeId();
        Lead l = new Lead(
            LastName = 'Empresa Aprobada PJ',
            Company = 'Empresa Aprobada PJ SRL',
            Status = 'Aprobado',
            LEA_SubEstado__c = 'ACEPTADO',
            LEA_RNC__c = '130999992',
            RecordTypeId = pjRecordTypeId
        );
        insert l;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Aprobado PLA-Legal / Revise completitud de datos antes de convertir', info.areaResponsable, 'Un prospecto formalmente aprobado debe estar listo para conversión');
        System.assertEquals(true, info.isReadyOrApproved);
        System.assertEquals('El prospecto se encuentra:', info.messagePrefix);
    }

    @IsTest
    static void testGetAreaResponsable_AccountCases() {
        Account accNeg = new Account(Name = 'Acc Negocios');
        insert accNeg;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo resNeg = 
            VFS_LeadAreaResponsableService.getAreaResponsable(accNeg.Id);
        System.assertEquals('Negocios', resNeg.areaResponsable);
        System.assertEquals(true, resNeg.isNegocios);

        Account accRev = new Account(
            Name = 'Acc En Revision',
            ACC_Resultado_Validacion__c = 'En revisión'
        );
        insert accRev;
        VFS_LeadAreaResponsableService.AreaResponsableInfo resRev = 
            VFS_LeadAreaResponsableService.getAreaResponsable(accRev.Id);
        System.assertEquals('Bandeja Validación Legal', resRev.areaResponsable);
        System.assertEquals(true, resRev.isLegal);

        Account accRech = new Account(
            Name = 'Acc Rechazado',
            ACC_Resultado_Validacion__c = 'Rechazado'
        );
        insert accRech;
        VFS_LeadAreaResponsableService.AreaResponsableInfo resRech = 
            VFS_LeadAreaResponsableService.getAreaResponsable(accRech.Id);
        System.assertEquals('Negocios', resRech.areaResponsable);

        Account accApr = new Account(
            Name = 'Acc Aprobada',
            ACC_Estado__c = 'VALIDADO',
            ACC_SubEstado__c = 'ACEPTADO'
        );
        insert accApr;
        VFS_LeadAreaResponsableService.AreaResponsableInfo resApr = 
            VFS_LeadAreaResponsableService.getAreaResponsable(accApr.Id);
        System.assertEquals('Aprobado PLA-Legal / Revise completitud de datos antes de convertir', resApr.areaResponsable);
        System.assertEquals(true, resApr.isReadyOrApproved);

        // Caso cuenta con solicitud de evidencias PLA abierta
        Task accPlaTask = new Task(
            WhatId = accNeg.Id,
            Subject = 'PLA: Requerimiento de Información y Evidencias (Cliente)',
            Status = 'Not Started'
        );
        insert accPlaTask;
        VFS_LeadAreaResponsableService.AreaResponsableInfo resAccPla = 
            VFS_LeadAreaResponsableService.getAreaResponsable(accNeg.Id);
        System.assertEquals('Negocios', resAccPla.areaResponsable);
        System.assert(resAccPla.messagePrefix.contains('solicitado por PLA'));

        Test.stopTest();
    }

    @IsTest
    static void testGetAreaResponsable_LeadConSolicitudEvidenciasPLA() {
        Lead l = new Lead(
            LastName = 'Test Lead Evidencias PLA',
            Company = 'Empresa PLA Evidencias',
            Status = 'Iniciado',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999977'
        );
        insert l;

        Task t = new Task(
            WhoId = l.Id,
            Subject = 'PLA: Requerimiento de Información y Evidencias',
            Status = 'Not Started',
            Description = 'Falta cédula legible'
        );
        insert t;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Negocios', info.areaResponsable);
        System.assertEquals(true, info.isNegocios);
        System.assert(info.messagePrefix.contains('solicitado por PLA'));
        System.assertEquals('utility:warning', info.iconName);
    }

    @IsTest
    static void testGetAreaResponsable_AprobadoPrevaleceSobreSolicitudPLA() {
        Lead l = new Lead(
            LastName = 'Lead Aprobado Con Tarea PLA',
            Company = 'Empresa Aprobada Con PLA',
            Status = 'Aprobado',
            LEA_TipoIdentificacion__c = 'Cédula',
            LEA_NumIdentificacion__c = '00199999966'
        );
        insert l;

        Task t = new Task(
            WhoId = l.Id,
            Subject = 'PLA: Requerimiento de Información y Evidencias',
            Status = 'Not Started',
            Description = 'Tarea PLA que quedó abierta'
        );
        insert t;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Aprobado / Listo para Conversión', info.areaResponsable, 'Para Persona Física aprobada debe ser Aprobado / Listo para Conversión');
        System.assertEquals(true, info.isReadyOrApproved);
        System.assertEquals('El prospecto se encuentra:', info.messagePrefix);
    }

    @IsTest
    static void testGetAreaResponsable_PFIniciadoConValidacionAprobadoQuedaEnNegocios() {
        Lead l = new Lead(
            LastName = 'Monaco Test',
            FirstName = 'Eduardo',
            Company = 'Particular',
            Status = 'Iniciado',
            LEA_Resultado_Validacion__c = 'Aprobado',
            LEA_TipoIdentificacion__c = 'Pasaporte',
            LEA_NumIdentificacion__c = 'AAF425764'
        );
        insert l;

        Test.startTest();
        VFS_LeadAreaResponsableService.AreaResponsableInfo info =
            VFS_LeadAreaResponsableService.getAreaResponsable(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals('Negocios', info.areaResponsable, 'Un Lead PF en etapa Iniciado debe permanecer en Negocios aunque LEA_Resultado_Validacion__c sea Aprobado');
        System.assertEquals(true, info.isNegocios);
    }
}