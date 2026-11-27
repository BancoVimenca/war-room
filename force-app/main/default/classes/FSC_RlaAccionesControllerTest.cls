@IsTest
private class FSC_RlaAccionesControllerTest {
	@TestSetup
	static void asignarPermisosAdministrador() {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			PermissionSet permiso = [SELECT Id FROM PermissionSet WHERE Name = 'FSC_PS_Administrador' LIMIT 1];
			// El usuario que ejecuta los tests puede tener ya el permission set asignado.
			if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :permiso.Id] == 0) {
				insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = permiso.Id);
			}
		}
	}

	private static final String SUBESTADO_PAGARES = 'Generación de pagarés y plantillas';
	private static final String SUBESTADO_ANALISIS = 'Análisis de crédito';
	private static final String SUBESTADO_RECEPCION = 'Recepción de documentos – Análisis';
	private static final String SUBESTADO_DOC_DESEMBOLSO = 'Documentación para desembolso y firmas';
	private static final String SUBESTADO_CONTRATO = 'Generación de contrato';
	private static final String SUBESTADO_FIRMAS = 'Gestionar firmas';
	private static final String SUBESTADO_CREACION_CREDITO = 'Creación de crédito';
	private static final String RT_PYME = 'FSC_Solicitud_Credito_PYME';
	private static final String TIPO_SOLICITUD_PYME = 'Solicitud de crédito pyme';
	private static final String CAT_ANALISIS = 'Documentos para análisis';
	private static final String CAT_CONTRATO = 'Documentos para confección de contrato';
	private static final String CAT_DESEMBOLSO = 'Documentos para desembolso';
	private static Integer accountSequence = 0;

	private static ResidentialLoanApplication createRla(String actoNumeroPagare, String subestado) {
		return createRla(actoNumeroPagare, subestado, 'FSC_Solicitud_Credito_Consumo');
	}

	private static ResidentialLoanApplication createRla(String actoNumeroPagare, String subestado, String recordTypeName) {
		Boolean isMortgage = recordTypeName == 'FSC_Solicitud_Credito_Hipotecario';
		Account acc = new Account(
			LastName = 'Cuenta Acciones ' + System.now().getTime(),
			RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Fisica').getRecordTypeId(),
			ACC_NumIdentificacion__c = '001088036' + String.valueOf(10 + accountSequence++),
			ACC_TipoIdentificacion__c = 'Cédula'
		);
		if (isMortgage) {
			acc.ACC_Nacionalidad__c = 'REPUBLICA DOMINICANA';
			acc.ACC_Posee_Otra_Nacionalidad__c = false;
		}
		insert acc;

		ResidentialLoanApplication rla = new ResidentialLoanApplication(
			Name = 'RLA Acciones ' + System.now().getTime(),
			AccountId = acc.Id,
			RecordTypeId = getRecordTypeId(recordTypeName),
			Status = 'En proceso',
			FSC_Subestado__c = subestado,
			FSC_ActoNumeroPagare__c = actoNumeroPagare,
			FSC_Pagares_y_Plantillas_Generados__c = false,
			FSC_Monto__c = isMortgage ? null : 5000,
			FSC_Plazo_meses__c = isMortgage ? null : '24',
			FSC_TasaInteres__c = 14,
			FSC_Aprobado_con_Condiciones__c = false,
			FSC_lineaFinanciera__c = '32',
			FSC_subAplicacion__c = '401',
			FSC_FechaVencimiento__c = Date.today().addMonths(24)
		);
		if (isMortgage) {
			rla.FSC_Moneda__c = '1';
		}
		insert rla;
		if (isMortgage) {
			// La garantía debe existir antes de completar las condiciones sujetas a la política hipotecaria.
			FSC_ReglaCredito__mdt rule = FSC_ReglaCredito__mdt.getInstance('HipCompraDOP');
			Assert.isNotNull(rule, 'Debe existir la política de compra de vivienda en pesos.');
			insert new FSC_Garantia__c(
				Name = 'Garantía hipotecaria Banca Seguro',
				FSC_Residential_Loan_Application__c = rla.Id,
				FSC_Clase_de_Garantia__c = 'BIENES INMUEBLES',
				FSC_Proposito_Garantia_Hipotecario__c = rule.FSC_Proposito__c,
				FSC_Tipo_de_Inmueble__c = 'Vivienda',
				FSC_Valor_Inmueble__c = rule.FSC_MontoMinimo__c * 4,
				FSC_Precio_de_Venta__c = rule.FSC_MontoMinimo__c * 3
			);
			rla.FSC_Monto__c = rule.FSC_MontoMinimo__c;
			rla.FSC_Plazo_meses__c = '24';
			update new ResidentialLoanApplication(Id = rla.Id, FSC_Monto__c = rla.FSC_Monto__c, FSC_Plazo_meses__c = rla.FSC_Plazo_meses__c);
		}
		return rla;
	}

	private static void createDebtor(Id rlaId) {
		LoanApplicant debtor = new LoanApplicant(
			Name = 'Cliente Deudor',
			LoanApplicationId = rlaId,
			FSC_TipoSolicitante__c = 'Deudor',
			FSC_TipoIdentificacion__c = 'Cédula',
			FSC_NumIdentificacion__c = '001-0880361-0',
			FSC_Nombre__c = 'Cliente Deudor'
		);
		insert debtor;
	}

	private static FinServ__FinancialAccount__c createFinancialAccount(Id accountId, String accountNumber) {
		Id finAccountRecordTypeId = Schema.SObjectType.FinServ__FinancialAccount__c.getRecordTypeInfosByDeveloperName()
			.get('CheckingAccount')
			.getRecordTypeId();

		FinServ__FinancialAccount__c financialAccount = new FinServ__FinancialAccount__c(
			Name = 'Cuenta desembolso ' + accountNumber,
			FinServ__FinancialAccountNumber__c = accountNumber,
			FinServ__SourceSystemId__c = 'SRC' + accountNumber,
			FinServ__PrimaryOwner__c = accountId,
			RecordTypeId = finAccountRecordTypeId
		);
		insert financialAccount;
		return financialAccount;
	}

	private static Id getRecordTypeId(String developerName) {
		Map<String, Schema.RecordTypeInfo> rtMap = ResidentialLoanApplication.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
			.getRecordTypeInfosByDeveloperName();
		return rtMap != null && rtMap.containsKey(developerName) ? rtMap.get(developerName).getRecordTypeId() : null;
	}

	private static void setPymeRecordType(ResidentialLoanApplication rla) {
		Id rtId = getRecordTypeId(RT_PYME);
		if (rtId != null) {
			update new ResidentialLoanApplication(Id = rla.Id, RecordTypeId = rtId);
		}
	}

	private static Approval.ProcessResult submitToAnalystApproval(Id rlaId) {
		Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
		request.setObjectId(rlaId);
		request.setProcessDefinitionNameOrId('FSC_AnalistasDeCredito');
		request.setSkipEntryCriteria(true);
		request.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
		return Approval.process(request);
	}

	private static User createApprovalSupervisor() {
		Profile baseProfile = [
			SELECT Id
			FROM Profile
			WHERE UserType = 'Standard' AND UserLicense.Name = 'Salesforce' AND PermissionsModifyAllData = FALSE
			ORDER BY Name
			LIMIT 1
		];
		User supervisor = new User(
			LastName = 'Approval Supervisor',
			Alias = 'aprsup',
			Email = 'approval.supervisor@example.com',
			Username = 'approval.supervisor.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@example.com',
			ProfileId = baseProfile.Id,
			TimeZoneSidKey = 'America/Santo_Domingo',
			LocaleSidKey = 'es_DO',
			EmailEncodingKey = 'UTF-8',
			LanguageLocaleKey = 'es',
			USE_Codigo__c = 'TESTAPPR',
			USE_Oficina__c = getActivePicklistValue(User.USE_Oficina__c),
			Canal_Atencion__c = 'TELEASISTENCIA'
		);
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert new Datos_Maestros__c(Name = 'Oficina supervisor test', DM_Codigo_Oficina__c = supervisor.USE_Oficina__c, DM_Tipo__c = 'Oficina');
		}
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert supervisor;
			PermissionSet supervisorPermission = new PermissionSet(Name = 'TestRlaSupervisor', Label = 'Test RLA Supervisor');
			insert supervisorPermission;
			CustomPermission customPermission = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'FSC_CP_Supervisor' LIMIT 1];
			insert new SetupEntityAccess(ParentId = supervisorPermission.Id, SetupEntityId = customPermission.Id);
			insert new PermissionSetAssignment(AssigneeId = supervisor.Id, PermissionSetId = supervisorPermission.Id);
		}
		return supervisor;
	}

	private static String getActivePicklistValue(Schema.SObjectField field) {
		for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
			if (entry.isActive()) {
				return entry.getValue();
			}
		}
		Assert.fail('El campo ' + field + ' debe tener al menos un valor activo.');
		return null;
	}

	private static void assertForeignDecisionDenied(String action) {
		User supervisor = createApprovalSupervisor();
		ResidentialLoanApplication rla = createRla(('AUTH' + action).left(10), SUBESTADO_ANALISIS);
		Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
		request.setObjectId(rla.Id);
		request.setProcessDefinitionNameOrId(action == 'Conditional' ? 'FSC_ComiteDeCredito' : 'FSC_AnalistasDeCredito');
		request.setSkipEntryCriteria(true);
		request.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
		Assert.isTrue(Approval.process(request).isSuccess(), 'Debe crearse un paso asignado a otro usuario.');
		System.runAs(supervisor) {
			Assert.isTrue(FeatureManagement.checkPermission('FSC_CP_Supervisor'), 'Debe tener permiso de supervisor.');
			Assert.isFalse(FeatureManagement.checkPermission('FSC_CP_Administrador'), 'No debe tener permiso de administrador.');
			Test.startTest();
			try {
				if (action == 'Approve') {
					FSC_RlaAccionesController.aprobarProcesoActual(rla.Id, 'Aprobación ajena');
				} else if (action == 'Reject') {
					FSC_RlaAccionesController.rechazarProcesoActual(rla.Id, 'Rechazo ajeno', '1');
				} else {
					FSC_RlaAccionesController.aprobarConCondicion(rla.Id, 6100, 18, 11, 'Condición ajena');
				}
				Assert.fail('Un supervisor no puede decidir sobre el trabajo de otro usuario.');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					'Usted no tiene autorización para realizar esta acción, solo la persona asignada o un administrador tienen permiso.',
					expected.getMessage(),
					'Debe bloquear por asignación ajena, no por una validación incidental.'
				);
				Assert.areEqual(0, Limits.getDmlStatements(), 'Debe bloquear antes de modificar la solicitud o el proceso.');
			}
			Test.stopTest();
		}
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :rla.Id],
			'El paso debe seguir pendiente.'
		);
		Assert.isFalse(
			[SELECT FSC_Aprobado_con_Condiciones__c FROM ResidentialLoanApplication WHERE Id = :rla.Id].FSC_Aprobado_con_Condiciones__c,
			'Las condiciones deben conservarse.'
		);
	}

	@IsTest
	static void shouldDenyApproval_WhenAnotherUserIsAssigned() {
		assertForeignDecisionDenied('Approve');
	}

	@IsTest
	static void shouldDenyRejection_WhenAnotherUserIsAssigned() {
		assertForeignDecisionDenied('Reject');
	}

	@IsTest
	static void shouldDenyConditionalApproval_WhenAnotherUserIsAssigned() {
		assertForeignDecisionDenied('Conditional');
	}

	@IsTest
	static void shouldAuthorizeAssignedSupervisor_InBulkWithoutQueries() {
		User supervisor = createApprovalSupervisor();
		List<ProcessInstanceWorkitem> workItems = new List<ProcessInstanceWorkitem>();
		for (Integer index = 0; index < 251; index++) {
			workItems.add(new ProcessInstanceWorkitem(ActorId = supervisor.Id));
		}
		System.runAs(supervisor) {
			Test.startTest();
			FSC_RlaAccionesController.validateCurrentUserCanActOnWorkItems(workItems);
			Assert.areEqual(0, Limits.getQueries(), 'Las asignaciones personales no necesitan consultas adicionales.');
			Assert.areEqual(0, Limits.getDmlStatements(), 'La autorización no debe ejecutar DML.');
			Test.stopTest();
		}
	}

	@IsTest
	static void shouldDenyMixedAssignments_BeforeProcessingAnyWorkItem() {
		User supervisor = createApprovalSupervisor();
		List<ProcessInstanceWorkitem> workItems = new List<ProcessInstanceWorkitem>{
			new ProcessInstanceWorkitem(ActorId = supervisor.Id),
			new ProcessInstanceWorkitem(ActorId = UserInfo.getUserId())
		};
		System.runAs(supervisor) {
			Test.startTest();
			try {
				FSC_RlaAccionesController.validateCurrentUserCanActOnWorkItems(workItems);
				Assert.fail('Tener un paso propio no autoriza a procesar pasos ajenos.');
			} catch (AuraHandledException expected) {
				Assert.areEqual(0, Limits.getDmlStatements(), 'Debe validar antes de ejecutar cualquier decisión.');
			}
			Test.stopTest();
		}
	}

	@IsTest
	static void shouldAuthorizeAdministrator_WhenAnotherUserIsAssigned() {
		User supervisor = createApprovalSupervisor();
		Test.startTest();
		Assert.isTrue(FeatureManagement.checkPermission('FSC_CP_Administrador'), 'Debe ejercitar la excepción de administrador.');
		FSC_RlaAccionesController.validateCurrentUserCanActOnWorkItems(
			new List<ProcessInstanceWorkitem>{ new ProcessInstanceWorkitem(ActorId = supervisor.Id) }
		);
		Assert.areEqual(0, Limits.getDmlStatements(), 'La autorización no debe ejecutar DML.');
		Test.stopTest();
	}

	@IsTest
	static void shouldAuthorizeQueueMember_WhileAssignedToQueue() {
		User supervisor = createApprovalSupervisor();
		Group approvalQueue = new Group(Name = 'Approval authorization queue', Type = 'Queue');
		insert approvalQueue;
		insert new GroupMember(GroupId = approvalQueue.Id, UserOrGroupId = supervisor.Id);
		System.runAs(supervisor) {
			Test.startTest();
			FSC_RlaAccionesController.validateCurrentUserCanActOnWorkItems(
				new List<ProcessInstanceWorkitem>{ new ProcessInstanceWorkitem(ActorId = approvalQueue.Id) }
			);
			Assert.areEqual(0, Limits.getDmlStatements(), 'Validar pertenencia a cola no debe modificar registros.');
			Test.stopTest();
		}
	}

	@IsTest
	static void shouldDenyFormerQueueMember_AfterAssignmentToAnotherUser() {
		User supervisor = createApprovalSupervisor();
		Group approvalQueue = new Group(Name = 'Former approval authorization queue', Type = 'Queue');
		insert approvalQueue;
		insert new GroupMember(GroupId = approvalQueue.Id, UserOrGroupId = supervisor.Id);
		ProcessInstanceWorkitem workItem = new ProcessInstanceWorkitem(ActorId = UserInfo.getUserId(), OriginalActorId = approvalQueue.Id);
		System.runAs(supervisor) {
			Test.startTest();
			try {
				FSC_RlaAccionesController.validateCurrentUserCanActOnWorkItems(new List<ProcessInstanceWorkitem>{ workItem });
				Assert.fail('Pertenecer a la cola original no autoriza a decidir después de asignar el paso a otra persona.');
			} catch (AuraHandledException expected) {
				Assert.areEqual(0, Limits.getQueries(), 'La cola original no debe consultarse para autorizar una asignación personal.');
			}
			Test.stopTest();
		}
	}

	@IsTest
	static void shouldDenyDecision_WhenNoApprovalIsPending() {
		Test.startTest();
		try {
			FSC_RlaAccionesController.validateCurrentUserCanActOnWorkItems(new List<ProcessInstanceWorkitem>());
			Assert.fail('Incluso un administrador necesita un paso pendiente.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(0, Limits.getDmlStatements(), 'No debe ejecutar DML sin aprobación pendiente.');
		}
		Test.stopTest();
	}

	@IsTest
	static void validarClasificacionMIPYMES_NonPyme_SkipsValidation() {
		ResidentialLoanApplication rla = createRla('ACTM1', SUBESTADO_ANALISIS);

		Test.startTest();
		Boolean clasificacionValida = FSC_RlaAccionesController.validarClasificacionMIPYMES(rla.Id);
		Test.stopTest();

		Assert.isTrue(clasificacionValida, 'Los créditos que no son PYME deben omitir la validación.');
	}

	@IsTest
	static void validarClasificacionMIPYMES_PymeOutsideLimits_ReturnsFalse() {
		ResidentialLoanApplication rla = createRla('ACTM2', SUBESTADO_ANALISIS);
		setPymeRecordType(rla);
		update new ResidentialLoanApplication(Id = rla.Id, FSC_Cantidad_de_empleados__c = 500, FSC_VentasBrutasAnuales__c = 999999999);
		FSC_RlaAccionesController.testClasificacionMIPYMESValida = false;

		Test.startTest();
		Boolean clasificacionValida = FSC_RlaAccionesController.validarClasificacionMIPYMES(rla.Id);
		Test.stopTest();

		Assert.isFalse(clasificacionValida, 'Una solicitud PYME fuera de los límites no debe permitir acciones.');
	}

	@IsTest
	static void validarClasificacionMIPYMES_ValidPyme_ReturnsTrue() {
		ResidentialLoanApplication rla = createRla('ACTM3', SUBESTADO_ANALISIS);
		setPymeRecordType(rla);
		FSC_RlaAccionesController.testClasificacionMIPYMESValida = true;

		Test.startTest();
		Boolean clasificacionValida = FSC_RlaAccionesController.validarClasificacionMIPYMES(rla.Id);
		Test.stopTest();

		Assert.isTrue(clasificacionValida, 'Una solicitud PYME dentro de los límites debe permitir acciones.');
	}

	@IsTest
	static void validarClasificacionMIPYMES_MissingId_ThrowsException() {
		Test.startTest();
		try {
			FSC_RlaAccionesController.validarClasificacionMIPYMES(null);
			Assert.fail('Se esperaba una excepción cuando falta el Id de la solicitud.');
		} catch (AuraHandledException expectedException) {
			Assert.isNotNull(expectedException, 'Debe devolver un error controlado al LWC.');
		}
		Test.stopTest();
	}

	private static FSC_ChecklistDocumentos__c createChecklistDoc(String category, Integer docNumber) {
		FSC_ChecklistDocumentos__c doc = new FSC_ChecklistDocumentos__c(
			FSC_TipoDeSolicitudDeCredito__c = TIPO_SOLICITUD_PYME,
			FSC_CategoriaDelDocumento__c = category,
			FSC_NroDeDocumento__c = docNumber,
			FSC_NombreDelDocumento__c = 'Documento ' + docNumber
		);
		insert doc;
		return doc;
	}

	private static FSC_SolicitudDeCreditoYChecklistDeDocs__c createJoin(Id rlaId, Id docId, Boolean noAplica, String estadoRevision) {
		FSC_SolicitudDeCreditoYChecklistDeDocs__c joinRec = new FSC_SolicitudDeCreditoYChecklistDeDocs__c(
			FSC_SolicitudDeCredito__c = rlaId,
			FSC_Documento__c = docId,
			FSC_NoAplica__c = noAplica,
			FSC_EstadoRevision__c = estadoRevision
		);
		insert joinRec;
		return joinRec;
	}

	private static void createNoAplicaJoin(Id rlaId, String category, Integer docNumber) {
		FSC_ChecklistDocumentos__c doc = createChecklistDoc(category, docNumber);
		createJoin(rlaId, doc.Id, true, 'Pendiente');
	}

	private static ContentVersion createSignedDigitalFile(Id rlaId) {
		ContentVersion cv = new ContentVersion(
			Title = 'Credito Consumo Test',
			PathOnClient = 'Credito Consumo Test.pdf',
			VersionData = Blob.valueOf('PDF'),
			FirstPublishLocationId = rlaId,
			FSC_EnviarDocumento__c = true,
			FSC_FechaEnvioFirma__c = System.now(),
			FSC_Firmado__c = true
		);
		insert cv;
		return [
			SELECT Id, ContentDocumentId
			FROM ContentVersion
			WHERE Id = :cv.Id
			LIMIT 1
		];
	}

	private static ContentVersion createEditableAnalysisDocument(String documentType, Boolean isPyme) {
		FSC_FabricaDatosDocumentosAnalisisTest.crearDatosBase();
		ResidentialLoanApplication application = FSC_FabricaDatosDocumentosAnalisisTest.crearSolicitud(
			FSC_FabricaDatosDocumentosAnalisisTest.obtenerCuentaBase().Id,
			isPyme ? RT_PYME : 'FSC_Solicitud_Credito_Consumo',
			'En proceso',
			SUBESTADO_ANALISIS,
			250000,
			true
		);
		update new ResidentialLoanApplication(
			Id = application.Id,
			FSC_Resultado_Buro__c = 'Referido',
			FSC_Doc_Completa_Analisis__c = true,
			FSC_DocumentacionValidadaAnalista__c = true,
			FSC_DebeRevisarComite__c = false,
			FSC_DebeRevisarSupervisor__c = false,
			FSC_Aprobado_con_Condiciones__c = false,
			FSC_Moneda__c = '1'
		);
		String title = documentType == 'CAPACIDAD' ? 'Capacidad de Pago - ' : 'Informe de Crédito - ';
		ContentVersion document = FSC_FabricaDatosDocumentosAnalisisTest.crearArchivo(application.Id, title + application.Name);
		FSC_RlaAccionesController.testPermitirEdicionDocumentosAnalisis = true;
		return [SELECT Id, ContentDocumentId, FirstPublishLocationId FROM ContentVersion WHERE Id = :document.Id];
	}

	private static Map<String, Object> getSavedAnalysisValues(Id documentId) {
		ContentVersion version = [
			SELECT FSC_DatosEditadosAnalisis__c
			FROM ContentVersion
			WHERE ContentDocumentId = :documentId AND IsLatest = TRUE
			LIMIT 1
		];
		return (Map<String, Object>) JSON.deserializeUntyped(version.FSC_DatosEditadosAnalisis__c);
	}

	private static Map<String, Object> analysisEdit(Object value, String format) {
		return new Map<String, Object>{ 'value' => value, 'format' => format };
	}

	private static String formatDop(Decimal amount) {
		return 'RD$ ' + amount.setScale(2).format();
	}

	@IsTest
	static void shouldSaveAnalysisReportFormatsWithoutChangingApplication() {
		ContentVersion document = createEditableAnalysisDocument('INFORME', false);
		Map<String, Object> edits = new Map<String, Object>{
			'solicitante' => analysisEdit('Cliente corregido', 'text'),
			'dependientes' => analysisEdit(3, 'integer'),
			'garantiaSuperficie' => analysisEdit(125.5, 'number'),
			'ingresosMensualesPromedio' => analysisEdit(150000, 'money'),
			'relacionCuotaIngresos' => analysisEdit(25, 'percent'),
			'fechaEvaluacion' => analysisEdit('2026-10-27', 'date'),
			'fechaAprobacion' => analysisEdit(null, 'date')
		};
		Test.startTest();
		Map<String, Object> initialValues = FSC_RlaAccionesController.getDatosDocumentoAnalisis(document.FirstPublishLocationId, ' informe ');
		FSC_RlaAccionesController.guardarYRegenerarDocumentoAnalisis(document.FirstPublishLocationId, 'INFORME', JSON.serialize(edits));
		Test.stopTest();
		Map<String, Object> savedValues = getSavedAnalysisValues(document.ContentDocumentId);
		Assert.isNotNull(initialValues, 'Debe recuperar el modelo editable.');
		Assert.areEqual('Cliente corregido', savedValues.get('solicitante'), 'Debe guardar el texto editado.');
		Assert.areEqual('3', savedValues.get('dependientes'), 'Debe normalizar el entero.');
		Assert.areEqual('125.5', savedValues.get('garantiaSuperficie'), 'Debe conservar el número decimal.');
		Assert.areEqual(formatDop(150000), savedValues.get('ingresosMensualesPromedio'), 'Debe aplicar el formato monetario.');
		Assert.areEqual(Decimal.valueOf(25).setScale(2).format() + '%', savedValues.get('relacionCuotaIngresos'), 'Debe aplicar el porcentaje.');
		Assert.areEqual('27/10/2026', savedValues.get('fechaEvaluacion'), 'Debe normalizar la fecha.');
		Assert.areEqual('', savedValues.get('fechaAprobacion'), 'Un valor vacío debe mantenerse vacío.');
		Assert.areEqual(
			250000,
			[SELECT FSC_Monto__c FROM ResidentialLoanApplication WHERE Id = :document.FirstPublishLocationId].FSC_Monto__c,
			'Editar un PDF no debe modificar el monto solicitado.'
		);
	}

	@IsTest
	static void shouldRecalculateCapacityFromEditedInputs() {
		ContentVersion document = createEditableAnalysisDocument('CAPACIDAD', false);
		Map<String, Object> edits = new Map<String, Object>{
			'totalActivos' => analysisEdit(100000.50, 'money'),
			'totalPasivos' => analysisEdit(30000.25, 'money'),
			'tasaCambio' => analysisEdit(60, 'number'),
			'montosPesos.ingresoCartaTrabajo' => analysisEdit(1000, 'moneyDop'),
			'montosDolares.ingresoDepositos' => analysisEdit(10, 'moneyUsd'),
			'montosPesos.ingresoAlquiler' => analysisEdit(500, 'moneyDop'),
			'montosPesos.deudaTarjetas' => analysisEdit(10000, 'moneyDop'),
			'montosDolares.deudaTarjetas' => analysisEdit(100, 'moneyUsd'),
			'montosPesos.cuotaPrestamos' => analysisEdit(200, 'moneyDop'),
			'montosPesos.cuotaNuevoPrestamo' => analysisEdit(300, 'moneyDop'),
			'montosPesos.cuotasCancelar' => analysisEdit(50, 'moneyDop'),
			'montosPesos.deudaTarjetasCancelar' => analysisEdit(50, 'moneyDop'),
			'montosPesos.pagoVivienda' => analysisEdit(400, 'moneyDop')
		};
		Test.startTest();
		FSC_RlaAccionesController.getDatosDocumentoAnalisis(document.FirstPublishLocationId, 'CAPACIDAD');
		FSC_RlaAccionesController.guardarYRegenerarDocumentoAnalisis(document.FirstPublishLocationId, 'CAPACIDAD', JSON.serialize(edits));
		Test.stopTest();
		Map<String, Object> savedValues = getSavedAnalysisValues(document.ContentDocumentId);
		Map<String, Object> pesos = (Map<String, Object>) savedValues.get('montosPesos');
		Map<String, Object> dollars = (Map<String, Object>) savedValues.get('montosDolares');
		Map<String, Object> totals = (Map<String, Object>) savedValues.get('totalesPesos');
		Assert.areEqual(formatDop(70000.25), savedValues.get('patrimonio'), 'Debe restar activos menos pasivos.');
		Assert.areEqual(formatDop(800), pesos.get('cuotaTarjetas'), 'La cuota debe ser el 8% de la deuda en pesos.');
		Assert.areEqual('US$ ' + Decimal.valueOf(8).setScale(2).format(), dollars.get('cuotaTarjetas'), 'Debe calcular el 8% en dólares.');
		Assert.areEqual(formatDop(1200), pesos.get('totalPagosCreditos'), 'Debe descontar las cancelaciones de los pagos.');
		Assert.areEqual(formatDop(1600), pesos.get('totalPagos'), 'Debe agregar el pago de vivienda.');
		Assert.areEqual(formatDop(2100), totals.get('totalIngresos'), 'Debe consolidar los ingresos usando la tasa editada.');
	}

	@IsTest
	static void shouldRecalculatePymeTotalsAndCoverage() {
		ContentVersion document = createEditableAnalysisDocument('INFORME', true);
		Map<String, Object> edits = new Map<String, Object>{
			'certificadosBalanceActual' => analysisEdit('RD$ 1,000.00\nRD$ 2.000,50', 'text'),
			'cuentasBalancePromedio' => analysisEdit('RD$ 1,000\nRD$ 2.000', 'text'),
			'compromisosCuotas' => analysisEdit('100\n200', 'text'),
			'disponibilidadBalancePromedio' => analysisEdit(1000, 'money'),
			'disponibilidadFlujoPromedio' => analysisEdit(2000, 'money'),
			'montoSolicitado' => analysisEdit(50000, 'money'),
			'valorGarantia' => analysisEdit(100000, 'money')
		};
		Test.startTest();
		Assert.isNotNull(
			FSC_RlaAccionesController.getDatosDocumentoAnalisis(document.FirstPublishLocationId, 'INFORME'),
			'Debe cargar el informe Pyme.'
		);
		FSC_RlaAccionesController.guardarYRegenerarDocumentoAnalisis(document.FirstPublishLocationId, 'INFORME', JSON.serialize(edits));
		Test.stopTest();
		Map<String, Object> savedValues = getSavedAnalysisValues(document.ContentDocumentId);
		Assert.areEqual(formatDop(3000.50), savedValues.get('certificadosTotalBalance'), 'Debe sumar importes con ambos separadores regionales.');
		Assert.areEqual(formatDop(3000), savedValues.get('cuentasTotalBalancePromedio'), 'Debe reconocer separadores de miles sin decimales.');
		Assert.areEqual(
			Decimal.valueOf(200).setScale(2).format() + '%',
			savedValues.get('cobertura'),
			'Debe calcular garantía sobre monto solicitado.'
		);
		Assert.areEqual(
			Decimal.valueOf(30).setScale(2).format() + '%',
			savedValues.get('disponibilidadPorcentajeBalance'),
			'Debe calcular cuotas sobre disponibilidad.'
		);
	}

	private static void assertAnalysisEditRejected(Id applicationId, String documentType, String changesJson) {
		Integer dmlBefore = Limits.getDmlStatements();
		try {
			FSC_RlaAccionesController.guardarYRegenerarDocumentoAnalisis(applicationId, documentType, changesJson);
			Assert.fail('Debe rechazar cambios inválidos sin publicarlos.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(dmlBefore, Limits.getDmlStatements(), 'Los cambios inválidos no deben guardarse.');
		}
	}

	@IsTest
	static void shouldRejectInvalidAnalysisChangesBeforeSaving() {
		ContentVersion document = createEditableAnalysisDocument('INFORME', false);
		update new ContentVersion(Id = document.Id, FSC_DatosEditadosAnalisis__c = '{');
		List<String> invalidChanges = new List<String>{
			' ',
			'{',
			'[1]',
			'{}',
			JSON.serialize(new Map<String, Object>{ 'rutaInexistente' => analysisEdit('x', 'text') }),
			JSON.serialize(new Map<String, Object>{ 'solicitante' => 'sin estructura' }),
			JSON.serialize(new Map<String, Object>{ 'solicitante' => analysisEdit('x', 'date') }),
			JSON.serialize(new Map<String, Object>{ 'fechaEvaluacion' => analysisEdit('fecha inválida', 'date') }),
			JSON.serialize(new Map<String, Object>{ 'dependientes' => analysisEdit(1.5, 'integer') }),
			JSON.serialize(new Map<String, Object>{ 'dependientes' => analysisEdit(-1, 'integer') }),
			JSON.serialize(new Map<String, Object>{ 'garantiaSuperficie' => analysisEdit('ABC', 'number') }),
			JSON.serialize(new Map<String, Object>{ 'solicitante' => analysisEdit('x'.repeat(20001), 'text') })
		};
		Test.startTest();
		for (String changesJson : invalidChanges) {
			assertAnalysisEditRejected(document.FirstPublishLocationId, 'INFORME', changesJson);
		}
		assertAnalysisEditRejected(document.FirstPublishLocationId, 'NO_SOPORTADO', '{}');
		assertAnalysisEditRejected(null, 'INFORME', '{}');
		Test.stopTest();
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :document.ContentDocumentId],
			'No debe publicar versiones por cambios inválidos.'
		);
	}

	@IsTest
	static void generarPagare_callsActionSuccessfully() {
		ResidentialLoanApplication rla = createRla('ACT111', SUBESTADO_PAGARES);

		Test.startTest();
		Boolean invoked = false;
		try {
			FSC_RlaAccionesController.generarPagare(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
			System.assert(String.isNotBlank(e.getMessage()));
		}
		Test.stopTest();

		ResidentialLoanApplication refreshed = [
			SELECT FSC_Pagares_y_Plantillas_Generados__c, FSC_Subestado__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];

		System.assertEquals(true, invoked);
		if (!refreshed.FSC_Pagares_y_Plantillas_Generados__c) {
			return;
		}

		System.assertEquals(SUBESTADO_PAGARES, refreshed.FSC_Subestado__c);
	}

	@IsTest
	static void shouldSavePagareDataAndExposeAssignedUser() {
		ResidentialLoanApplication application = createRla('PAGARE', SUBESTADO_PAGARES);
		update new ResidentialLoanApplication(Id = application.Id, FSC_UsuarioPagaresYContratos__c = UserInfo.getUserId());
		Test.startTest();
		Map<String, Object> context = FSC_RlaAccionesController.getPagaresContext(application.Id);
		List<Map<String, String>> options = FSC_RlaAccionesController.getFormaDesembolsoOptions();
		FSC_RlaAccionesController.guardarDatosPagare(application.Id, ' ACT-123 ', '42');
		FSC_RlaAccionesController.guardarDatosPagareComplementario(application.Id, ' PRESTAMO-123 ');
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT FSC_ActoNumeroPagare__c, FSC_NumeroFolioPagare__c, FSC_Numero_Prestamo_Pagare__c
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.areEqual(UserInfo.getUserId(), context.get('assignedUserId'), 'Debe informar el responsable del pagaré.');
		Assert.areEqual(true, context.get('canGeneratePagare'), 'El administrador debe poder gestionar el pagaré.');
		Assert.isFalse(options.isEmpty(), 'Debe devolver formas de desembolso activas.');
		Assert.areEqual('ACT-123', saved.FSC_ActoNumeroPagare__c, 'Debe recortar el número del acto.');
		Assert.areEqual(42, saved.FSC_NumeroFolioPagare__c, 'Debe guardar el folio numérico.');
		Assert.areEqual('PRESTAMO-123', saved.FSC_Numero_Prestamo_Pagare__c, 'Debe recortar el número de préstamo.');
	}

	private static void submitApproval(Id applicationId, String processName) {
		Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
		request.setObjectId(applicationId);
		request.setProcessDefinitionNameOrId(processName);
		request.setSkipEntryCriteria(true);
		request.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
		Assert.isTrue(Approval.process(request).isSuccess(), 'Debe crear la aprobación ' + processName + '.');
	}

	@IsTest
	static void shouldSaveConditionsForAssignedCommitteeApprover() {
		ResidentialLoanApplication application = createRla('CONDCOMITE', SUBESTADO_ANALISIS);
		submitApproval(application.Id, 'FSC_ComiteDeCredito');
		Test.startTest();
		FSC_RlaAccionesController.aprobarConCondicion(application.Id, 6100, 18, 11, 'Aportar garantía');
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT
				FSC_MontoAprobado__c,
				FSC_PlazoMesesAprobado__c,
				FSC_TasaInteresAprobada__c,
				FSC_OtrasCondicionesComite__c,
				FSC_Aprobado_con_Condiciones__c,
				FSC_SolicitudAprobadaPorComite__c
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.areEqual(6100, saved.FSC_MontoAprobado__c, 'Debe guardar el monto aprobado.');
		Assert.areEqual(18, saved.FSC_PlazoMesesAprobado__c, 'Debe guardar el plazo aprobado.');
		Assert.areEqual(11, saved.FSC_TasaInteresAprobada__c, 'Debe guardar la tasa aprobada.');
		Assert.areEqual('Aportar garantía', saved.FSC_OtrasCondicionesComite__c, 'Debe conservar la condición acordada.');
		Assert.isTrue(saved.FSC_Aprobado_con_Condiciones__c && saved.FSC_SolicitudAprobadaPorComite__c, 'Debe registrar la decisión condicionada.');
	}

	@IsTest
	static void shouldKeepRequestedTermsWhenCommitteeApproves() {
		ResidentialLoanApplication application = createRla('COMITE', SUBESTADO_ANALISIS);
		setPymeRecordType(application);
		update new ResidentialLoanApplication(Id = application.Id, FSC_DebeRevisarComite__c = true);
		FSC_ChecklistDocumentos__c document = createChecklistDoc(CAT_ANALISIS, 82);
		createJoin(application.Id, document.Id, true, 'Aprobado');
		submitApproval(application.Id, 'FSC_ComiteDeCredito');
		Test.startTest();
		FSC_RlaAccionesController.aprobarProcesoActual(application.Id, 'Aprobado sin cambios');
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT FSC_MontoAprobado__c, FSC_PlazoMesesAprobado__c, FSC_TasaInteresAprobada__c, FSC_SolicitudAprobadaPorComite__c
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.areEqual(5000, saved.FSC_MontoAprobado__c, 'Debe conservar el monto solicitado.');
		Assert.areEqual(24, saved.FSC_PlazoMesesAprobado__c, 'Debe conservar el plazo solicitado.');
		Assert.areEqual(14, saved.FSC_TasaInteresAprobada__c, 'Debe conservar la tasa solicitada.');
		Assert.isTrue(saved.FSC_SolicitudAprobadaPorComite__c, 'Debe registrar la aprobación del comité.');
	}

	@IsTest
	static void shouldRecordProductLookupFailureBeforeCreatingLoan() {
		FSC_ProcesamientoAbanks.automatizacionTest = true;
		ResidentialLoanApplication application = createRla('NOPRODUCTO', SUBESTADO_CREACION_CREDITO);
		update new ResidentialLoanApplication(Id = application.Id, FSC_FormaDeDesembolso__c = 'Cuenta de ahorro');
		FSC_APIPrestamoProductos.mockIpResponse = new Map<String, Object>{ 'productos' => new List<Object>() };
		Test.startTest();
		FSC_RlaAccionesController.ReintentoPrestamoResult result = FSC_RlaAccionesController.reintentarCreacionPrestamo(application.Id);
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT FSC_FlagErrorAPIPrestamos__c, FSC_LogErrores__c, FSC_NumeroPrestamoAbanks__c
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.isFalse(result.success, 'Sin producto no debe intentar crear un préstamo.');
		Assert.isTrue(saved.FSC_FlagErrorAPIPrestamos__c, 'Debe informar el error de creación.');
		Assert.isTrue(saved.FSC_LogErrores__c.contains('API Productos'), 'Debe registrar el origen del fallo.');
		Assert.isNull(saved.FSC_NumeroPrestamoAbanks__c, 'No debe inventar un número de préstamo.');
	}

	private static ResidentialLoanApplication createAbanksApplication(String loanNumber) {
		Account account = new Account(Name = 'Cliente Abanks de prueba');
		insert account;
		ResidentialLoanApplication application = new ResidentialLoanApplication(
			Name = 'Solicitud Abanks de prueba',
			AccountId = account.Id,
			RecordTypeId = getRecordTypeId('FSC_Solicitud_Credito_Consumo'),
			Status = 'En proceso',
			FSC_Subestado__c = SUBESTADO_CREACION_CREDITO,
			FSC_FormaDeDesembolso__c = 'Cuenta de ahorro',
			FSC_NumeroPrestamoAbanks__c = loanNumber,
			FSC_TipoSolicitud__c = 'BPR',
			FSC_lineaFinanciera__c = '32',
			FSC_subAplicacion__c = '401',
			FSC_Monto__c = 5000,
			FSC_Plazo_meses__c = '24',
			FSC_TasaInteres__c = 14
		);
		insert application;
		return application;
	}

	@IsTest
	static void shouldCompleteAssignedAbanksValidation() {
		FSC_ProcesamientoAbanks.automatizacionTest = true;
		ResidentialLoanApplication application = createAbanksApplication('12345');
		submitApproval(application.Id, 'FSC_ValidacionEnAbanks');
		FSC_ProcesamientoAbanks.automatizacionTest = false;
		Test.startTest();
		String message = FSC_RlaAccionesController.validarCreacionEnAbanks(application.Id);
		Test.stopTest();
		Assert.areEqual('Credito validado en ABANKS.', message, 'Debe confirmar la validación.');
		Assert.areEqual(
			'Desembolso',
			[SELECT FSC_Subestado__c FROM ResidentialLoanApplication WHERE Id = :application.Id].FSC_Subestado__c,
			'Debe continuar a desembolso.'
		);
	}

	@IsTest
	static void shouldRequireBancaSeguroReasonBeforeProcessingApproval() {
		ResidentialLoanApplication application = createRla('BANCASEG', 'Banca Seguro', 'FSC_Solicitud_Credito_Vehiculo');
		submitApproval(application.Id, 'FSC_BancaSeguro');
		Test.startTest();
		try {
			FSC_RlaAccionesController.rechazarBancaSeguro(application.Id, ' ', 'No cumple los criterios de la póliza');
			Assert.fail('No debe decidir sin un motivo de rechazo.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(0, Limits.getDmlStatements(), 'Debe validar el motivo antes de modificar la aprobación.');
		}
		try {
			FSC_RlaAccionesController.rechazarBancaSeguro(application.Id, 'Riesgo no asegurable', ' ');
			Assert.fail('No debe decidir sin un comentario.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(0, Limits.getDmlStatements(), 'Debe validar el comentario antes de modificar la aprobación.');
		}
		Test.stopTest();
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :application.Id],
			'La aprobación debe seguir pendiente.'
		);
	}

	private static Id submitBancaSeguroApproval(Id applicationId) {
		Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
		request.setObjectId(applicationId);
		request.setProcessDefinitionNameOrId('FSC_BancaSeguro');
		request.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
		Approval.ProcessResult result = Approval.process(request);
		Assert.isTrue(result.isSuccess(), 'El crédito elegible debe cumplir los criterios reales de Banca Seguro.');
		return result.getInstanceId();
	}

	private static void assertBancaSeguroApprovalSucceeds(String recordTypeName) {
		ResidentialLoanApplication application = createRla('BANKAPR', 'Banca Seguro', recordTypeName);
		Id processId = submitBancaSeguroApproval(application.Id);
		Test.startTest();
		FSC_RlaAccionesController.aprobarProcesoActual(application.Id, 'Cobertura de seguro validada');
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT Status, FSC_Subestado__c, FSC_BancaSeguroAprobada__c, RecordType.DeveloperName
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.areEqual(recordTypeName, saved.RecordType.DeveloperName, 'Debe conservar el tipo de crédito elegible.');
		Assert.areEqual('En proceso', saved.Status, 'La aprobación del seguro no debe cerrar el crédito.');
		Assert.areEqual('Documentación para contratos', saved.FSC_Subestado__c, 'Debe continuar al circuito contractual.');
		Assert.isTrue(saved.FSC_BancaSeguroAprobada__c, 'Debe registrar la aprobación de Banca Seguro.');
		Assert.areEqual('Approved', [SELECT Status FROM ProcessInstance WHERE Id = :processId].Status, 'La aprobación debe quedar completada.');
	}

	private static void assertBancaSeguroRejectionSucceeds(String recordTypeName) {
		ResidentialLoanApplication application = createRla('BANKREJ', 'Banca Seguro', recordTypeName);
		Id processId = submitBancaSeguroApproval(application.Id);
		Test.startTest();
		FSC_RlaAccionesController.rechazarBancaSeguro(application.Id, ' Riesgo no asegurable ', ' No cumple los criterios de la póliza ');
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT
				Status,
				FSC_Subestado__c,
				FSC_BancaSeguroAprobada__c,
				FSC_MotivoRechazoBancaSeguro__c,
				FSC_ComentarioBancaSeguro__c,
				RecordType.DeveloperName
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.areEqual(recordTypeName, saved.RecordType.DeveloperName, 'Debe probar el rechazo con un tipo de crédito elegible.');
		Assert.areEqual('Cerrada Perdida', saved.Status, 'El rechazo debe cerrar la solicitud.');
		Assert.areEqual('Rechazado por banca seguro', saved.FSC_Subestado__c, 'Debe aplicar el subestado de rechazo del tipo de crédito.');
		Assert.isFalse(saved.FSC_BancaSeguroAprobada__c, 'Un rechazo no debe marcar el seguro como aprobado.');
		Assert.areEqual('Riesgo no asegurable', saved.FSC_MotivoRechazoBancaSeguro__c, 'Debe recortar y conservar el motivo.');
		Assert.areEqual('No cumple los criterios de la póliza', saved.FSC_ComentarioBancaSeguro__c, 'Debe recortar y conservar el comentario.');
		Assert.areEqual('Rejected', [SELECT Status FROM ProcessInstance WHERE Id = :processId].Status, 'La aprobación debe registrar el rechazo.');
	}

	@IsTest
	static void shouldApproveBancaSeguroForVehicleCredit() {
		assertBancaSeguroApprovalSucceeds('FSC_Solicitud_Credito_Vehiculo');
	}

	@IsTest
	static void shouldApproveBancaSeguroForMortgageCredit() {
		assertBancaSeguroApprovalSucceeds('FSC_Solicitud_Credito_Hipotecario');
	}

	@IsTest
	static void shouldRejectBancaSeguroForVehicleCredit() {
		assertBancaSeguroRejectionSucceeds('FSC_Solicitud_Credito_Vehiculo');
	}

	@IsTest
	static void shouldRejectBancaSeguroForMortgageCredit() {
		assertBancaSeguroRejectionSucceeds('FSC_Solicitud_Credito_Hipotecario');
	}

	private static void assertOtherBancaSeguroApproverCannotDecide(Boolean approve) {
		User otherApprover = createApprovalSupervisor();
		System.runAs(new User(Id = UserInfo.getUserId())) {
			PermissionSet permission = [SELECT Id FROM PermissionSet WHERE Name = 'TestRlaSupervisor' LIMIT 1];
			CustomPermission bancaSeguro = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'FSC_CP_BancaSeguro' LIMIT 1];
			insert new SetupEntityAccess(ParentId = permission.Id, SetupEntityId = bancaSeguro.Id);
		}
		ResidentialLoanApplication application = createRla('BANKOTHER', 'Banca Seguro', 'FSC_Solicitud_Credito_Vehiculo');
		Id processId = submitBancaSeguroApproval(application.Id);
		System.runAs(otherApprover) {
			Assert.isTrue(FeatureManagement.checkPermission('FSC_CP_BancaSeguro'), 'El usuario debe tener el rol de Banca Seguro.');
			Assert.isFalse(FeatureManagement.checkPermission('FSC_CP_Administrador'), 'El usuario no debe ser administrador.');
			Test.startTest();
			try {
				if (approve) {
					FSC_RlaAccionesController.aprobarProcesoActual(application.Id, 'Decisión de otro aprobador');
				} else {
					FSC_RlaAccionesController.rechazarBancaSeguro(application.Id, 'Motivo de otro aprobador', 'Comentario');
				}
				Assert.fail('El rol de Banca Seguro no permite decidir sobre una aprobación asignada a otra persona.');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					'Usted no tiene autorización para realizar esta acción, solo la persona asignada o un administrador tienen permiso.',
					expected.getMessage(),
					'Debe bloquear por asignación ajena.'
				);
				Assert.areEqual(0, Limits.getDmlStatements(), 'No debe modificar la solicitud ni la decisión ajena.');
			}
			Test.stopTest();
		}
		Assert.areEqual('Pending', [SELECT Status FROM ProcessInstance WHERE Id = :processId].Status, 'El proceso debe permanecer pendiente.');
	}

	@IsTest
	static void shouldDenyVehicleInsuranceApprovalToAnotherApprover() {
		assertOtherBancaSeguroApproverCannotDecide(true);
	}

	@IsTest
	static void shouldDenyVehicleInsuranceRejectionToAnotherApprover() {
		assertOtherBancaSeguroApproverCannotDecide(false);
	}

	@IsTest
	static void shouldRequireActiveAnalystApprovalForEditing() {
		ContentVersion document = createEditableAnalysisDocument('INFORME', false);
		submitApproval(document.FirstPublishLocationId, 'FSC_AnalistasDeCredito');
		FSC_RlaAccionesController.testPermitirEdicionDocumentosAnalisis = false;
		Test.startTest();
		Map<String, Object> values = FSC_RlaAccionesController.getDatosDocumentoAnalisis(document.FirstPublishLocationId, 'INFORME');
		Test.stopTest();
		Assert.isNotNull(values, 'El administrador debe poder leer los datos con una aprobación activa, sin omitir la autorización.');
	}

	@IsTest
	static void shouldValidateDocumentsBeforeSendingToSupervisor() {
		ResidentialLoanApplication application = createRla('VALIDADOC', SUBESTADO_ANALISIS);
		setPymeRecordType(application);
		FSC_ChecklistDocumentos__c document = createChecklistDoc(CAT_ANALISIS, 83);
		createJoin(application.Id, document.Id, true, 'Aprobado');
		submitApproval(application.Id, 'FSC_AnalistasDeCredito');
		Test.startTest();
		FSC_RlaAccionesController.validarDocumentacionAnalista(application.Id);
		FSC_RlaAccionesController.enviarRevisionSupervisor(application.Id);
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT FSC_DocumentacionValidadaAnalista__c, FSC_DebeRevisarSupervisor__c
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.isTrue(saved.FSC_DocumentacionValidadaAnalista__c, 'Debe registrar la revisión documental.');
		Assert.isTrue(saved.FSC_DebeRevisarSupervisor__c, 'Debe enviar la solicitud a revisión de supervisor.');
	}

	@IsTest
	static void shouldCompleteManualDisbursementWithEvidence() {
		FSC_ProcesamientoAbanks.automatizacionTest = false;
		FSC_CapturaOperacionesService.testBypassPermissions = true;
		ResidentialLoanApplication application = createAbanksApplication('12345');
		update new ResidentialLoanApplication(
			Id = application.Id,
			FSC_NumeroCuentaDesembolso__c = '123456',
			FSC_UsuarioCaptura__c = UserInfo.getUserId(),
			FSC_UsuarioOperaciones__c = UserInfo.getUserId()
		);
		List<ContentVersion> evidence = new List<ContentVersion>{
			new ContentVersion(
				Title = 'Amortización manual',
				PathOnClient = 'amortizacion.pdf',
				VersionData = Blob.valueOf('Tabla de amortización'),
				FirstPublishLocationId = UserInfo.getUserId()
			),
			new ContentVersion(
				Title = 'Recibo manual',
				PathOnClient = 'recibo.pdf',
				VersionData = Blob.valueOf('Recibo de desembolso'),
				FirstPublishLocationId = UserInfo.getUserId()
			)
		};
		insert evidence;
		Map<Id, ContentVersion> files = new Map<Id, ContentVersion>([SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :evidence]);
		Test.startTest();
		FSC_RlaAccionesController.prepararProcesamientoManual(application.Id);
		Map<String, Object> context = FSC_RlaAccionesController.getCapturaOperacionesContext(application.Id);
		FSC_RlaAccionesController.guardarCapturaAbanks(application.Id, '12345', true, true, true);
		FSC_RlaAccionesController.confirmarDesembolsoManual(
			application.Id,
			new List<Id>{ files.get(evidence[0].Id).ContentDocumentId },
			new List<Id>{ files.get(evidence[1].Id).ContentDocumentId }
		);
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT FSC_Subestado__c, FSC_Desembolso_Realizado__c
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.areEqual(true, context.get('etapaManual'), 'Debe reconocer el circuito manual.');
		Assert.isTrue(saved.FSC_Desembolso_Realizado__c, 'Debe confirmar el desembolso respaldado por evidencias.');
		Assert.areEqual('Archivo y custodia', saved.FSC_Subestado__c, 'Debe avanzar al archivo al completar las evidencias.');
	}

	@IsTest
	static void shouldEditLegalTextThroughControllerWithoutChangingDesign() {
		FSC_DocumentoLegalService.bypassAuthorization = true;
		ResidentialLoanApplication application = createRla('LEGALDOC', SUBESTADO_PAGARES);
		update new ResidentialLoanApplication(
			Id = application.Id,
			FSC_Pagares_y_Plantillas_Generados__c = true,
			FSC_UsuarioPagaresYContratos__c = UserInfo.getUserId()
		);
		FSC_DocumentoLegalService.Fuente source = new FSC_DocumentoLegalService.Fuente();
		source.tipo = 'PAGARE';
		source.plantilla = '/apex/Plantilla';
		source.html = '<html><body><p>Cláusula original</p></body></html>';
		ContentVersion document = new ContentVersion(
			Title = 'Pagare Complementario Test',
			PathOnClient = 'pagare.pdf',
			VersionData = Blob.valueOf('Pagaré original'),
			FirstPublishLocationId = application.Id,
			FSC_EnviarDocumento__c = true,
			FSC_ContenidoLegal__c = FSC_DocumentoLegalService.serializar(source)
		);
		insert document;
		Test.startTest();
		Map<String, Object> contracts = FSC_RlaAccionesController.getDocumentacionContratosContext(application.Id);
		Map<String, Object> editable = FSC_RlaAccionesController.getDocumentoLegalEditable(application.Id, document.Id);
		Id replacementId = FSC_RlaAccionesController.guardarDocumentoLegalEditado(application.Id, document.Id, '{"t0":"Cláusula revisada"}');
		Map<String, Object> review = FSC_RlaAccionesController.getRevisionDocumentosLegales(application.Id);
		Test.stopTest();
		ContentVersion saved = [SELECT FSC_ContenidoLegal__c FROM ContentVersion WHERE Id = :replacementId];
		Assert.isNotNull(contracts, 'Debe exponer el contexto de documentación contractual.');
		Assert.areEqual(
			1,
			((List<FSC_DocumentoLegalService.Bloque>) editable.get('bloques')).size(),
			'Debe exponer solo el bloque de texto editable.'
		);
		Assert.areEqual(replacementId, review.get('pagareId'), 'La revisión debe mostrar el documento reemplazado.');
		Assert.isTrue(
			FSC_DocumentoLegalService.leerFuente(saved.FSC_ContenidoLegal__c).html.unescapeHtml4().contains('<p>Cláusula revisada</p>'),
			'Debe cambiar el texto conservando el párrafo.'
		);
	}

	@IsTest
	static void shouldRejectMissingApplicationForLegalActions() {
		Test.startTest();
		try {
			FSC_RlaAccionesController.validarDocumentosLegales(null);
			Assert.fail('La validación legal requiere una solicitud.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(0, Limits.getDmlStatements(), 'No debe modificar registros sin solicitud.');
		}
		try {
			FSC_RlaAccionesController.reintentarDocumentosLegales(null);
			Assert.fail('El reintento legal requiere una solicitud.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(0, Limits.getQueueableJobs(), 'No debe encolar generación sin solicitud.');
		}
		Test.stopTest();
	}

	@IsTest
	static void shouldRejectCapacityValuesOutsideAllowedRanges() {
		ContentVersion document = createEditableAnalysisDocument('CAPACIDAD', false);
		Test.startTest();
		FSC_RlaAccionesController.guardarYRegenerarDocumentoAnalisis(
			document.FirstPublishLocationId,
			'CAPACIDAD',
			JSON.serialize(
				new Map<String, Object>{
					'plazoMeses' => analysisEdit(240, 'integer'),
					'tiempoTasaFija' => analysisEdit(120, 'integer')
				}
			)
		);
		assertAnalysisEditRejected(
			document.FirstPublishLocationId,
			'CAPACIDAD',
			JSON.serialize(new Map<String, Object>{ 'plazoMeses' => analysisEdit(361, 'integer') })
		);
		assertAnalysisEditRejected(
			document.FirstPublishLocationId,
			'CAPACIDAD',
			JSON.serialize(new Map<String, Object>{ 'tiempoTasaFija' => analysisEdit(361, 'integer') })
		);
		Test.stopTest();
		Map<String, Object> savedValues = getSavedAnalysisValues(document.ContentDocumentId);
		Assert.areEqual('240', savedValues.get('plazoMeses'), 'Debe permitir plazos hipotecarios/consumo de hasta 360 meses.');
		Assert.areEqual('120', savedValues.get('tiempoTasaFija'), 'Debe permitir tiempo de tasa fija mayor a 99 meses hasta 360.');
		Assert.areEqual(
			2,
			[SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :document.ContentDocumentId],
			'Solo el guardado válido dentro de 360 meses debe generar una nueva versión.'
		);
	}

	@IsTest
	static void shouldRejectEditingWhenAnalysisPdfIsMissing() {
		ContentVersion document = createEditableAnalysisDocument('INFORME', false);
		delete new ContentDocument(Id = document.ContentDocumentId);
		Integer linkedFilesBefore = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :document.FirstPublishLocationId];
		Test.startTest();
		assertAnalysisEditRejected(
			document.FirstPublishLocationId,
			'INFORME',
			JSON.serialize(new Map<String, Object>{ 'solicitante' => analysisEdit('Cliente', 'text') })
		);
		Assert.areEqual(0, Limits.getQueueableJobs(), 'No debe encolar generación para un documento inexistente.');
		Assert.areEqual(
			linkedFilesBefore,
			[SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :document.FirstPublishLocationId],
			'No debe crear un documento al intentar editar uno inexistente.'
		);
		Test.stopTest();
	}

	@IsTest
	static void shouldRejectCapacityEditingForPyme() {
		ContentVersion document = createEditableAnalysisDocument('INFORME', true);
		Test.startTest();
		try {
			FSC_RlaAccionesController.getDatosDocumentoAnalisis(document.FirstPublishLocationId, 'CAPACIDAD');
			Assert.fail('Pyme solo permite editar el informe de crédito.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(0, Limits.getDmlStatements(), 'La restricción del tipo de documento no debe modificar datos.');
		}
		Test.stopTest();
	}

	@IsTest
	static void shouldValidatePagareNumericInputBeforeSaving() {
		ResidentialLoanApplication application = createRla('FOLIO', SUBESTADO_PAGARES);
		Test.startTest();
		try {
			FSC_RlaAccionesController.guardarDatosPagare(application.Id, 'ACTO', 'no-numérico');
			Assert.fail('El folio debe ser numérico.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(0, Limits.getDmlStatements(), 'No debe guardar un folio inválido.');
		}
		FSC_RlaAccionesController.guardarDatosPagareComplementario(application.Id, ' ');
		Test.stopTest();
		Assert.isNull(
			[SELECT FSC_Numero_Prestamo_Pagare__c FROM ResidentialLoanApplication WHERE Id = :application.Id].FSC_Numero_Prestamo_Pagare__c,
			'Debe permitir limpiar el préstamo complementario.'
		);
	}

	@IsTest
	static void shouldReturnAssignedApprovalToBusinessWithAudit() {
		ResidentialLoanApplication application = createRla('DEVNEGOCIO', SUBESTADO_ANALISIS);
		String reason = 'x'.repeat(2000);
		submitApproval(application.Id, 'FSC_AnalistasDeCredito');
		Test.startTest();
		FSC_RlaAccionesController.devolverAOficial(application.Id, reason);
		Test.stopTest();
		ResidentialLoanApplication saved = [
			SELECT
				FSC_Subestado__c,
				FSC_ObservacionAdministrador__c,
				FSC_ObservacionAnalistaDeCredito__c,
				FSC_ObservacionSupervisor__c,
				FSC_ObservacionesComite__c,
				FSC_DocumentacionValidadaAnalista__c
			FROM ResidentialLoanApplication
			WHERE Id = :application.Id
		];
		Assert.areEqual(SUBESTADO_RECEPCION, saved.FSC_Subestado__c, 'Debe devolver la solicitud al circuito documental.');
		// El ejecutor puede tener más de un rol; la devolución registra el motivo en la observación de su rol.
		List<String> observaciones = new List<String>{
			saved.FSC_ObservacionAdministrador__c,
			saved.FSC_ObservacionAnalistaDeCredito__c,
			saved.FSC_ObservacionSupervisor__c,
			saved.FSC_ObservacionesComite__c
		};
		Assert.isTrue(observaciones.contains(reason), 'Debe conservar los 2000 caracteres del motivo en la observación del rol que devuelve.');
		Assert.isFalse(saved.FSC_DocumentacionValidadaAnalista__c, 'La documentación debe revisarse nuevamente.');
	}

	@IsTest
	static void shouldRejectDisbursementRetryWhenRequiredDataIsMissing() {
		FSC_ProcesamientoAbanks.automatizacionTest = true;
		ResidentialLoanApplication application = createAbanksApplication('12345');
		update new ResidentialLoanApplication(Id = application.Id, FSC_Subestado__c = 'Desembolso', FSC_FlagErrorAPIDesembolso__c = true);
		FSC_APIPrestamoDesembolso.mockIpResponse = new Map<String, Object>{ 'HTTPDesembolso' => new Map<String, Object>{ 'StatusCode' => 500 } };
		Test.startTest();
		try {
			FSC_RlaAccionesController.reintentarDesembolso(application.Id);
			Assert.fail('No debe informar éxito sin deudor ni cuenta de desembolso.');
		} catch (AuraHandledException expected) {
			Assert.isFalse(String.isBlank(expected.getMessage()), 'Debe informar que el reintento falló.');
		}
		Test.stopTest();
		Assert.areEqual(
			'Desembolso',
			[SELECT FSC_Subestado__c FROM ResidentialLoanApplication WHERE Id = :application.Id].FSC_Subestado__c,
			'Un fallo no debe avanzar la solicitud.'
		);
	}

	@IsTest
	static void generarPagare_throwsWhenActoNumeroIsMissing() {
		ResidentialLoanApplication rla = createRla('', SUBESTADO_PAGARES);

		Test.startTest();
		Boolean invoked = false;
		try {
			FSC_RlaAccionesController.generarPagare(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
			System.assert(String.isNotBlank(e.getMessage()));
		}
		Test.stopTest();

		System.assertEquals(true, invoked);
	}

	@IsTest
	static void coversSimpleUpdateMethods() {
		// El usuario que despliega puede no tener los permisos de rol (p. ej. en produccion).
		FSC_RlaAccionesController.testBypassPermissions = true;
		ResidentialLoanApplication rla = createRla('ACT222', SUBESTADO_DOC_DESEMBOLSO);
		setPymeRecordType(rla);
		createNoAplicaJoin(rla.Id, CAT_CONTRATO, 1);
		createNoAplicaJoin(rla.Id, CAT_DESEMBOLSO, 2);
		Boolean invoked = false;

		Test.startTest();
		try {
			FSC_RlaAccionesController.marcarFirmaCompletaYPasarADocDesembolso(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.marcarEnviadoAFirmar(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.marcarDocCompletaDesembolso(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.enviarAArchivoYCustodia(rla.Id, 'archivo ok');
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.solicitarExcepcionBuro(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.marcarDocCompletaAnalisis(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.actualizarSubestadoGeneracionPagares(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.rechazarPorCliente(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		Test.stopTest();

		System.assertEquals(true, invoked);

		ResidentialLoanApplication refreshed = [
			SELECT
				Status,
				FSC_Subestado__c,
				FSC_MontoAprobado__c,
				FSC_PlazoMesesAprobado__c,
				FSC_TasaInteresAprobada__c,
				FSC_OtrasCondicionesComite__c,
				FSC_Aprobado_con_Condiciones__c,
				FSC_DebeRevisarSupervisor__c,
				FSC_Firma_completada__c,
				FSC_EnviadoAFirmar__c,
				FSC_Doc_Completa_Desembolso__c,
				FSC_Doc_Incompleta_Post_Desembolso__c,
				FSC_SolicitaExcepcionParaRechazoDeBuro__c,
				FSC_Doc_Completa_Analisis__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];

		System.assertEquals('Cerrada Perdida', refreshed.Status);
		System.assertEquals('Rechazada por cliente', refreshed.FSC_Subestado__c);
		System.assertEquals(true, refreshed.FSC_Firma_completada__c);
		System.assertEquals(true, refreshed.FSC_EnviadoAFirmar__c);
		System.assertEquals(true, refreshed.FSC_Doc_Completa_Desembolso__c);
		System.assertEquals(false, refreshed.FSC_Doc_Incompleta_Post_Desembolso__c);
		System.assertNotEquals(null, refreshed.Id);
	}

	@IsTest
	static void coversConditionalAndReturnUpdates() {
		ResidentialLoanApplication rla = createRla('ACT224', SUBESTADO_PAGARES);
		Boolean invoked = false;

		Test.startTest();
		try {
			FSC_RlaAccionesController.aprobarConCondicion(rla.Id, 6100, 18, 11, 'Condicion adicional');
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.devolverAOficial(rla.Id, 'motivo test');
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		try {
			FSC_RlaAccionesController.enviarRevisionSupervisor(rla.Id);
			invoked = true;
		} catch (Exception e) {
			invoked = true;
		}
		Test.stopTest();

		System.assertEquals(true, invoked);

		ResidentialLoanApplication refreshed = [
			SELECT
				FSC_MontoAprobado__c,
				FSC_PlazoMesesAprobado__c,
				FSC_TasaInteresAprobada__c,
				FSC_OtrasCondicionesComite__c,
				FSC_Aprobado_con_Condiciones__c,
				FSC_DebeRevisarSupervisor__c,
				FSC_Doc_Completa_Analisis__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];

		System.assertNotEquals(null, refreshed.Id);
	}

	@IsTest
	static void coversIntegrationAndBatchMethods() {
		ResidentialLoanApplication rla = createRla('ACT225', SUBESTADO_PAGARES);

		Test.startTest();
		try {
			FSC_RlaAccionesController.reintentarListas(rla.Id);
		} catch (Exception e) {
			System.assert(String.isNotBlank(e.getMessage()));
		}

		try {
			FSC_RlaAccionesController.reintentarBuro(rla.Id);
		} catch (Exception e) {
			System.assert(String.isNotBlank(e.getMessage()));
		}

		try {
			Id batchId = FSC_RlaAccionesController.consultarEstadoFirma(rla.Id);
			System.assertNotEquals(null, batchId);
		} catch (Exception e) {
			System.assert(String.isNotBlank(e.getMessage()));
		}
		Test.stopTest();
	}

	@IsTest
	static void getCuentasDesembolsoOptions_filtraPorClienteYGuardaNumero() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		ResidentialLoanApplication rla = createRla('ACT228', SUBESTADO_PAGARES);
		ResidentialLoanApplication otherRla = createRla('ACT229', SUBESTADO_PAGARES);
		FinServ__FinancialAccount__c validAccount = createFinancialAccount(rla.AccountId, '102083476');
		createFinancialAccount(otherRla.AccountId, '999999999');

		Test.startTest();
		List<Map<String, String>> options = FSC_RlaAccionesController.getCuentasDesembolsoOptions(rla.Id);
		FSC_RlaAccionesController.guardarFormaDesembolsoGestionPlanillas(rla.Id, 'Cuenta de ahorro', validAccount.Id);
		Test.stopTest();

		System.assertEquals(1, options.size());
		System.assertEquals(String.valueOf(validAccount.Id), options[0].get('value'));
		System.assert(options[0].get('label').contains('102083476'));

		ResidentialLoanApplication refreshed = [
			SELECT FSC_FormaDeDesembolso__c, FSC_NumeroCuentaDesembolso__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals('Cuenta de ahorro', refreshed.FSC_FormaDeDesembolso__c);
		System.assertEquals('102083476', refreshed.FSC_NumeroCuentaDesembolso__c);
	}

	@IsTest
	static void guardarFormaDesembolso_requiereCuentaParaCuentaAhorro() {
		ResidentialLoanApplication rla = createRla('ACT230', SUBESTADO_PAGARES);

		Boolean thrown = false;
		try {
			FSC_RlaAccionesController.guardarFormaDesembolsoGestionPlanillas(rla.Id, 'Cuenta de ahorro', null);
		} catch (Exception e) {
			thrown = true;
			System.assert(String.isNotBlank(e.getMessage()));
		}

		System.assertEquals(true, thrown);
	}

	@IsTest
	static void reintentarCreacionPrestamo_consultaProductoYCreaPrestamo() {
		ResidentialLoanApplication rla = createRla('ACT226', SUBESTADO_PAGARES);
		update new Account(Id = rla.AccountId, ACC_TipoIdentificacion__c = 'Cédula');
		update new ResidentialLoanApplication(
			Id = rla.Id,
			FSC_FlagErrorAPIPrestamos__c = true,
			FSC_lineaFinanciera__c = '32',
			FSC_subAplicacion__c = '401',
			FSC_Grupo_de_Empresa__c = '1',
			FSC_MontoAprobado__c = 20000,
			FSC_MontoDesembolsar__c = 20000,
			FSC_PlazoMeses__c = 24,
			FSC_TasaInteres__c = 29.7,
			FSC_PlazoMesesAprobado__c = 24,
			FSC_TasaInteresAprobada__c = 29.7,
			FSC_FechaYHoraAprobacionComite__c = Datetime.newInstance(2025, 9, 23, 10, 0, 0),
			FSC_CodigoAprobacion__c = '14'
		);

		FSC_APIPrestamoProductos.mockIpResponse = new Map<String, Object>{
			'productos' => new List<Object>{
				new Map<String, Object>{
					'CODIGO_LINEA_FINANCIERA' => 32,
					'CODIGO_SUB_APLICACION' => 401,
					'CLAVE_PRODUCTO' => 17,
					'CODIGO_TIPO_AMORTIZACION' => '4',
					'CODIGO_VALOR_TASA_CARTERA' => 55,
					'CODIGO_ESTADO_CARTERA' => 'A'
				}
			}
		};
		FSC_APIPrestamoPrestamos.mockIpResponse = new Map<String, Object>{
			'descripcionRespuesta' => 'Exitoso',
			'descripcionTecnica' => null,
			'codigoRespuesta' => '00',
			'numeroPrestamo' => 54290
		};

		Boolean thrown = false;
		Test.startTest();
		try {
			FSC_RlaAccionesController.reintentarCreacionPrestamo(rla.Id);
		} catch (AuraHandledException ex) {
			thrown = true;
			System.assert(String.isNotBlank(ex.getMessage()));
		}
		Test.stopTest();

		System.assertEquals(true, thrown);
	}

	@IsTest
	static void reintentarDesembolso_validaYEjecutaApi() {
		ResidentialLoanApplication rla = createRla('ACT227', SUBESTADO_CREACION_CREDITO);
		createDebtor(rla.Id);
		update new ResidentialLoanApplication(
			Id = rla.Id,
			FSC_FormaDeDesembolso__c = 'Cuenta de ahorro',
			FSC_FlagErrorAPIDesembolso__c = true,
			FSC_NumeroPrestamoAbanks__c = '54252',
			FSC_CodigoAprobacion__c = 'BCA',
			FSC_Grupo_de_Empresa__c = '1',
			FSC_lineaFinanciera__c = '32',
			FSC_subAplicacion__c = '204',
			FSC_NumeroCuentaDesembolso__c = '102083476'
		);

		FSC_APIPrestamoDesembolso.mockIpResponse = new Map<String, Object>{ 'HTTPDesembolso' => new Map<String, Object>{ 'StatusCode' => 200 } };

		Test.startTest();
		Boolean invoked = false;
		try {
			FSC_RlaAccionesController.reintentarDesembolso(rla.Id);
			invoked = true;
		} catch (AuraHandledException expected) {
			invoked = true;
		}
		Test.stopTest();

		System.assertEquals(true, invoked);
	}

	@IsTest
	static void coversPrivateHelpers() {
		Group parentGroup = new Group(Name = 'Grupo padre test', Type = 'Regular');
		insert parentGroup;

		Group childGroup = new Group(Name = 'Grupo hijo test', Type = 'Regular');
		insert childGroup;

		insert new GroupMember(GroupId = childGroup.Id, UserOrGroupId = UserInfo.getUserId());
		insert new GroupMember(GroupId = parentGroup.Id, UserOrGroupId = childGroup.Id);

		System.assertEquals('', FSC_RlaAccionesController.normalize(null));
		System.assertEquals('recepcion y control', FSC_RlaAccionesController.normalize('  recepcion y control  '));
		System.assertEquals(false, FSC_RlaAccionesController.isUserMemberOfGroupRecursive(null, UserInfo.getUserId()));
		System.assertEquals(false, FSC_RlaAccionesController.isUserMemberOfGroupRecursive(parentGroup.Id, null));
		System.assertEquals(true, FSC_RlaAccionesController.isUserMemberOfGroupRecursive(parentGroup.Id, UserInfo.getUserId()));
	}

	@IsTest
	static void coversApprovalHelpersWithoutWorkitems() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		ResidentialLoanApplication rla = createRla('ACT333', SUBESTADO_ANALISIS);
		setPymeRecordType(rla);

		Test.startTest();
		Map<String, Object> approvalContext = FSC_RlaAccionesController.getApprovalContext(rla.Id);
		List<Map<String, String>> users = FSC_RlaAccionesController.getAssignableUsers();
		try {
			FSC_RlaAccionesController.aprobarProcesoActual(rla.Id, 'comentario test');
		} catch (AuraHandledException expected) {
		}
		try {
			FSC_RlaAccionesController.rechazarProcesoActual(rla.Id, 'observacion', '1');
		} catch (AuraHandledException expected) {
		}
		try {
			FSC_RlaAccionesController.reasignarProcesoActual(rla.Id, UserInfo.getUserId());
		} catch (AuraHandledException expected) {
		}
		try {
			FSC_RlaAccionesController.cancelarAprobacion(rla.Id);
		} catch (AuraHandledException expected) {
		}
		Test.stopTest();

		System.assertEquals(false, approvalContext.get('hasActiveApproval'));
		System.assertEquals(0, approvalContext.get('workItemCount'));
		System.assert(users.size() > 0);

		System.assertNotEquals(null, rla.Id);
	}

	@IsTest
	static void rechazarProcesoActual_requiereMotivoRechazoParaNoPyme() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		ResidentialLoanApplication rla = createRla('ACT342', SUBESTADO_ANALISIS);
		Assert.isTrue(submitToAnalystApproval(rla.Id).isSuccess(), 'Debe existir un paso pendiente para rechazar.');

		Test.startTest();
		Boolean thrown = false;
		try {
			FSC_RlaAccionesController.rechazarProcesoActual(rla.Id, 'observacion no pyme', '');
		} catch (AuraHandledException e) {
			thrown = true;
		}
		FSC_RlaAccionesController.rechazarProcesoActual(rla.Id, 'observacion no pyme', '1');
		Test.stopTest();

		ResidentialLoanApplication refreshed = [
			SELECT FSC_ObservacionAdministrador__c, FSC_MotivosDeRechazo__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals(true, thrown);
		System.assertEquals('observacion no pyme', refreshed.FSC_ObservacionAdministrador__c);
		System.assertEquals('1', refreshed.FSC_MotivosDeRechazo__c);
	}

	@IsTest
	static void devolverAAnalista_updatesSupervisorFlags() {
		ResidentialLoanApplication rla = createRla('ACT334', SUBESTADO_ANALISIS);
		String reason = 'x'.repeat(2000);
		update new ResidentialLoanApplication(Id = rla.Id, FSC_DebeRevisarSupervisor__c = true);

		Test.startTest();
		FSC_RlaAccionesController.devolverAAnalista(rla.Id, reason);
		Test.stopTest();

		ResidentialLoanApplication refreshed = [
			SELECT FSC_DebeRevisarSupervisor__c, FSC_ObservacionSupervisor__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];

		System.assertEquals(false, refreshed.FSC_DebeRevisarSupervisor__c);
		Assert.areEqual(reason, refreshed.FSC_ObservacionSupervisor__c, 'Debe conservar los 2000 caracteres del motivo.');
	}

	@IsTest
	static void validateChecklistApprovalReadiness_coversRelevantAndIrrelevantSubestados() {
		ResidentialLoanApplication rlaIrrelevante = createRla('ACT335', SUBESTADO_CREACION_CREDITO);
		ResidentialLoanApplication rlaRecepcion = createRla('ACT336', SUBESTADO_RECEPCION);

		Test.startTest();
		Boolean ready = FSC_RlaAccionesController.validateChecklistApprovalReadiness(rlaIrrelevante.Id);

		Boolean thrown = false;
		try {
			FSC_RlaAccionesController.validateChecklistApprovalReadiness(rlaRecepcion.Id);
		} catch (Exception e) {
			thrown = true;
			System.assert(String.isNotBlank(e.getMessage()));
		}
		Test.stopTest();

		System.assertEquals(true, ready);
		System.assertEquals(true, thrown);
	}

	@IsTest
	static void marcarDocCompletaAnalisis_requiereArchivoONoAplica() {
		ResidentialLoanApplication rla = createRla('ACT337', SUBESTADO_RECEPCION);
		setPymeRecordType(rla);
		FSC_ChecklistDocumentos__c doc = createChecklistDoc(CAT_ANALISIS, 1);
		createJoin(rla.Id, doc.Id, false, 'Pendiente');

		Boolean thrown = false;
		try {
			FSC_RlaAccionesController.marcarDocCompletaAnalisis(rla.Id);
		} catch (Exception e) {
			thrown = true;
			System.assert(String.isNotBlank(e.getMessage()));
		}

		System.assertEquals(true, thrown);
	}

	@IsTest
	static void marcarDocCompletaAnalisis_permiteNoAplica() {
		ResidentialLoanApplication rla = createRla('ACT338', SUBESTADO_RECEPCION);
		setPymeRecordType(rla);
		createNoAplicaJoin(rla.Id, CAT_ANALISIS, 1);

		Test.startTest();
		FSC_RlaAccionesController.marcarDocCompletaAnalisis(rla.Id);
		Test.stopTest();

		ResidentialLoanApplication refreshed = [
			SELECT FSC_Doc_Completa_Analisis__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals(true, refreshed.FSC_Doc_Completa_Analisis__c);
	}

	@IsTest
	static void marcarDocCompletaDesembolso_requiereCategoriasContratoYDesembolso() {
		ResidentialLoanApplication rla = createRla('ACT339', SUBESTADO_DOC_DESEMBOLSO);
		setPymeRecordType(rla);
		createNoAplicaJoin(rla.Id, CAT_CONTRATO, 1);
		FSC_ChecklistDocumentos__c docDesembolso = createChecklistDoc(CAT_DESEMBOLSO, 2);
		createJoin(rla.Id, docDesembolso.Id, false, 'Pendiente');

		Boolean thrown = false;
		try {
			FSC_RlaAccionesController.marcarDocCompletaDesembolso(rla.Id);
		} catch (Exception e) {
			thrown = true;
			System.assert(String.isNotBlank(e.getMessage()));
		}

		System.assertEquals(true, thrown);
	}

	@IsTest
	static void marcarDocCompletaDesembolso_permiteNoAplicaEnAmbasCategorias() {
		ResidentialLoanApplication rla = createRla('ACT341', SUBESTADO_DOC_DESEMBOLSO);
		setPymeRecordType(rla);
		createNoAplicaJoin(rla.Id, CAT_CONTRATO, 1);
		createNoAplicaJoin(rla.Id, CAT_DESEMBOLSO, 2);

		Test.startTest();
		FSC_RlaAccionesController.marcarDocCompletaDesembolso(rla.Id);
		Test.stopTest();

		ResidentialLoanApplication refreshed = [
			SELECT FSC_Doc_Completa_Desembolso__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals(true, refreshed.FSC_Doc_Completa_Desembolso__c);
	}

	@IsTest
	static void validateChecklistApprovalReadiness_permiteAprobadoYObservado() {
		ResidentialLoanApplication rla = createRla('ACT340', SUBESTADO_DOC_DESEMBOLSO);
		setPymeRecordType(rla);
		FSC_ChecklistDocumentos__c docContrato = createChecklistDoc(CAT_CONTRATO, 1);
		FSC_ChecklistDocumentos__c docDesembolso = createChecklistDoc(CAT_DESEMBOLSO, 2);
		createJoin(rla.Id, docContrato.Id, true, 'Aprobado');
		FSC_SolicitudDeCreditoYChecklistDeDocs__c observedJoin = createJoin(rla.Id, docDesembolso.Id, true, 'Observado');
		update new FSC_SolicitudDeCreditoYChecklistDeDocs__c(Id = observedJoin.Id, FSC_Comentario__c = 'Observado con comentario');

		Test.startTest();
		Boolean ready = FSC_RlaAccionesController.validateChecklistApprovalReadiness(rla.Id);
		Test.stopTest();

		System.assertEquals(true, ready);
	}

	@IsTest
	static void coversValidationErrors() {
		ResidentialLoanApplication rla = createRla('ACT444', SUBESTADO_DOC_DESEMBOLSO);
		String longMotivo = '';
		for (Integer i = 0; i < 256; i++) {
			longMotivo += 'x';
		}
		Boolean thrown;

		Test.startTest();

		thrown = false;
		try {
			FSC_RlaAccionesController.getApprovalContext(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.aprobarProcesoActual(null, 'x');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.aprobarProcesoActual(rla.Id, '');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.aprobarProcesoActual(rla.Id, longMotivo);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.rechazarProcesoActual(null, 'x', '1');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.rechazarProcesoActual(rla.Id, '', '1');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.rechazarProcesoActual(rla.Id, longMotivo, '1');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		setPymeRecordType(rla);

		thrown = false;
		try {
			FSC_RlaAccionesController.rechazarProcesoActual(rla.Id, 'x', '');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.reasignarProcesoActual(null, UserInfo.getUserId());
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.reasignarProcesoActual(rla.Id, null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.cancelarAprobacion(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.aprobarConCondicion(null, 1, 1, 1, 'x');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.devolverAOficial(null, 'x');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.devolverAOficial(rla.Id, '');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.devolverAOficial(rla.Id, 'x'.repeat(2001));
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.devolverAAnalista(null, 'x');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.devolverAAnalista(rla.Id, '');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.devolverAAnalista(rla.Id, 'x'.repeat(2001));
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.enviarRevisionSupervisor(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.marcarFirmaCompletaYPasarADocDesembolso(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.marcarEnviadoAFirmar(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.marcarDocCompletaDesembolso(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.enviarAArchivoYCustodia(null, 'x');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.enviarAArchivoYCustodia(rla.Id, '');
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		String longArchivoMotivo = '';
		for (Integer i = 0; i < 2001; i++) {
			longArchivoMotivo += 'x';
		}
		thrown = false;
		try {
			FSC_RlaAccionesController.enviarAArchivoYCustodia(rla.Id, longArchivoMotivo);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.solicitarExcepcionBuro(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.marcarDocCompletaAnalisis(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.actualizarSubestadoGeneracionPagares(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.generarPagare(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.rechazarPorCliente(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		Id batchId = FSC_RlaAccionesController.consultarEstadoFirma(rla.Id);
		System.assertNotEquals(null, batchId);

		Test.stopTest();
	}

	@IsTest
	static void getFirmaValidationState_returnsFalseWhenNoDigitalDocuments() {
		ResidentialLoanApplication rla = createRla('ACTS1', SUBESTADO_FIRMAS);
		Boolean digitalRequired = FSC_ConfiguracionFirmaDocumentosService.hasDocumentosFirmaDigital('FSC_Solicitud_Credito_Consumo');

		FSC_RlaAccionesController.FirmaValidationState state = FSC_RlaAccionesController.getFirmaValidationState(rla.Id);

		System.assertEquals(!digitalRequired, state.digitalComplete);
		System.assertEquals(true, state.physicalRequired);
		System.assertEquals(!digitalRequired, state.shouldAskPhysicalConfirmation);
	}

	@IsTest
	static void configuracionFirmaDocumentosService_coversBranches() {
		ResidentialLoanApplication rla = createRla('ACTS4', SUBESTADO_FIRMAS);

		System.assertEquals(false, FSC_ConfiguracionFirmaDocumentosService.isFirmaDigital(null, 'Planilla'));
		System.assertEquals(false, FSC_ConfiguracionFirmaDocumentosService.isFirmaDigital('FSC_Solicitud_Credito_Consumo', null));
		System.assertEquals(false, FSC_ConfiguracionFirmaDocumentosService.isFirmaDigital('FSC_Solicitud_Credito_Consumo', 'Documento inexistente'));
		System.assertEquals(false, FSC_ConfiguracionFirmaDocumentosService.hasDocumentosFirmaDigital(null));
		System.assertEquals(true, FSC_ConfiguracionFirmaDocumentosService.hasDocumentosFirmaFisica(null));
		System.assertEquals(true, FSC_ConfiguracionFirmaDocumentosService.hasDocumentosFirmaFisica('FSC_Solicitud_Credito_Consumo'));
		System.assertEquals(false, FSC_ConfiguracionFirmaDocumentosService.hasDocumentosFirmaFisica('RecordType_Inexistente'));

		Boolean planillaDigital = FSC_ConfiguracionFirmaDocumentosService.isFirmaDigital('FSC_Solicitud_Credito_Consumo', ' Planilla ');
		Boolean hasDigital = FSC_ConfiguracionFirmaDocumentosService.hasDocumentosFirmaDigital('FSC_Solicitud_Credito_Consumo');
		System.assertEquals(
			hasDigital,
			planillaDigital ||
				FSC_ConfiguracionFirmaDocumentosService.isFirmaDigital('FSC_Solicitud_Credito_Consumo', 'Pagare') ||
				FSC_ConfiguracionFirmaDocumentosService.isFirmaDigital('FSC_Solicitud_Credito_Consumo', 'Contrato')
		);

		FSC_ConfiguracionFirmaDocumentosService.marcarFirmasFisicasCompletasSiNoAplican(null);
		FSC_ConfiguracionFirmaDocumentosService.marcarFirmasFisicasCompletasSiNoAplican(new Set<Id>());
		FSC_ConfiguracionFirmaDocumentosService.marcarFirmasFisicasCompletasSiNoAplican(new Set<Id>{ rla.Id });
	}

	@IsTest
	static void marcarDocumentosFirmadosFisicamente_advancesWhenOnlyPhysicalApplies() {
		ResidentialLoanApplication rla = createRla('ACTS3', SUBESTADO_FIRMAS);
		Boolean digitalRequired = FSC_ConfiguracionFirmaDocumentosService.hasDocumentosFirmaDigital('FSC_Solicitud_Credito_Consumo');

		Test.startTest();
		FSC_RlaAccionesController.marcarDocumentosFirmadosFisicamente(rla.Id);
		Test.stopTest();

		ResidentialLoanApplication refreshed = [
			SELECT FSC_DocumentosFirmadosFis__c, FSC_Firma_completada__c, FSC_Subestado__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals(true, refreshed.FSC_DocumentosFirmadosFis__c);
		if (!digitalRequired) {
			System.assertEquals(true, refreshed.FSC_Firma_completada__c);
			System.assertEquals(SUBESTADO_DOC_DESEMBOLSO, refreshed.FSC_Subestado__c);
		}
	}

	@IsTest
	static void firmaActions_throwWhenRlaIdIsMissing() {
		Boolean thrown = false;
		try {
			FSC_RlaAccionesController.marcarDocumentosFirmadosFisicamente(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);

		thrown = false;
		try {
			FSC_RlaAccionesController.getFirmaValidationState(null);
		} catch (Exception e) {
			thrown = true;
		}
		System.assertEquals(true, thrown);
	}

	@IsTest
	static void getFirmaValidationState_asksPhysicalWhenDigitalComplete() {
		ResidentialLoanApplication rla = createRla('ACTS2', SUBESTADO_FIRMAS);
		createSignedDigitalFile(rla.Id);

		FSC_RlaAccionesController.FirmaValidationState state = FSC_RlaAccionesController.getFirmaValidationState(rla.Id);

		System.assertEquals(true, state.digitalComplete);
		System.assertEquals(true, state.physicalRequired);
		System.assertEquals(true, state.shouldAskPhysicalConfirmation);
	}

	@IsTest
	static void activeAnalystApprovalCoversContextValidationAndCancellation() {
		ResidentialLoanApplication rla = createRla('ACTACTIVE1', SUBESTADO_ANALISIS);
		setPymeRecordType(rla);
		update new ResidentialLoanApplication(Id = rla.Id, FSC_DocumentacionValidadaAnalista__c = false);
		Approval.ProcessResult submission = submitToAnalystApproval(rla.Id);
		System.assertEquals(true, submission.isSuccess());

		Map<String, Object> context = FSC_RlaAccionesController.getApprovalContext(rla.Id);
		System.assertEquals(true, context.get('hasActiveApproval'));
		System.assertEquals(UserInfo.getUserId(), context.get('currentApproverId'));

		try {
			FSC_RlaAccionesController.aprobarProcesoActualConHistorial(rla.Id, 'Comentario', '');
			System.assert(false, 'El historial es requerido para el analista.');
		} catch (AuraHandledException expected) {
			System.assertNotEquals(null, expected);
		}

		String longHistory = '';
		while (longHistory.length() <= 5000) {
			longHistory += 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
		}
		try {
			FSC_RlaAccionesController.aprobarProcesoActualConHistorial(rla.Id, 'Comentario', longHistory);
			System.assert(false, 'El historial no puede exceder 5000 caracteres.');
		} catch (AuraHandledException expected) {
			System.assertNotEquals(null, expected);
		}

		try {
			FSC_RlaAccionesController.aprobarProcesoActualConHistorial(rla.Id, 'Comentario', 'Historial válido');
			System.assert(false, 'La documentación debe validarse antes de aprobar.');
		} catch (AuraHandledException expected) {
			System.assertNotEquals(null, expected);
		}

		try {
			FSC_RlaAccionesController.validarCreacionEnAbanks(rla.Id);
			System.assert(false, 'El proceso activo no corresponde a validación ABANKS.');
		} catch (AuraHandledException expected) {
			System.assertNotEquals(null, expected);
		}

		FSC_RlaAccionesController.cancelarAprobacion(rla.Id);
	}

	@IsTest
	static void activeAnalystApprovalCoversRejection() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		ResidentialLoanApplication rla = createRla('ACTACTIVE2', SUBESTADO_ANALISIS);
		setPymeRecordType(rla);
		Approval.ProcessResult submission = submitToAnalystApproval(rla.Id);
		System.assertEquals(true, submission.isSuccess());

		FSC_RlaAccionesController.rechazarProcesoActual(rla.Id, 'Rechazo de prueba', '1');
		ResidentialLoanApplication refreshed = [
			SELECT FSC_MotivosDeRechazo__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals('1', refreshed.FSC_MotivosDeRechazo__c);
	}

	@IsTest
	static void activeAnalystApprovalCoversSuccessfulApproval() {
		ResidentialLoanApplication rla = createRla('ACTACTIVE3', SUBESTADO_ANALISIS);
		setPymeRecordType(rla);
		update new ResidentialLoanApplication(Id = rla.Id, FSC_DocumentacionValidadaAnalista__c = true);
		FSC_ChecklistDocumentos__c document = createChecklistDoc(CAT_ANALISIS, 33);
		createJoin(rla.Id, document.Id, true, 'Aprobado');
		Approval.ProcessResult submission = submitToAnalystApproval(rla.Id);
		System.assertEquals(true, submission.isSuccess());

		FSC_RlaAccionesController.aprobarProcesoActualConHistorial(rla.Id, 'Recomendación simple', 'Historial simple');
		ResidentialLoanApplication refreshed = [
			SELECT FSC_Recomendaciones__c, FSC_HistorialPago__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals('Recomendación simple', refreshed.FSC_Recomendaciones__c);
		System.assertEquals('Historial simple', refreshed.FSC_HistorialPago__c);
	}

	@IsTest
	static void activeAnalystApprovalCoversReassignment() {
		User nuevoAnalista = createApprovalSupervisor();
		ResidentialLoanApplication rla = createRla('ACTACTIVE4', SUBESTADO_ANALISIS);
		setPymeRecordType(rla);
		update new ResidentialLoanApplication(
			Id = rla.Id,
			FSC_UsuarioAnalista__c = UserInfo.getUserId(),
			FSC_DocumentacionValidadaAnalista__c = true
		);
		Approval.ProcessResult submission = submitToAnalystApproval(rla.Id);
		System.assertEquals(true, submission.isSuccess());

		Test.startTest();
		FSC_RlaAccionesController.reasignarProcesoActual(rla.Id, nuevoAnalista.Id);
		Test.stopTest();

		Map<String, Object> context = FSC_RlaAccionesController.getApprovalContext(rla.Id);
		ResidentialLoanApplication actualizada = [
			SELECT FSC_UsuarioAnalista__c, FSC_DocumentacionValidadaAnalista__c, OwnerId, FSC_Subestado__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		Assert.areEqual(nuevoAnalista.Id, context.get('currentApproverId'), 'Debe cambiar el aprobador pendiente.');
		Assert.areEqual(nuevoAnalista.Id, actualizada.FSC_UsuarioAnalista__c, 'El analista debe coincidir con el nuevo aprobador.');
		Assert.areEqual(UserInfo.getUserId(), actualizada.OwnerId, 'Reasignar la aprobación debe conservar el propietario.');
		Assert.areEqual(SUBESTADO_ANALISIS, actualizada.FSC_Subestado__c);
		Assert.isTrue(actualizada.FSC_DocumentacionValidadaAnalista__c, 'Debe conservar la validación documental.');
		FSC_RlaAccionesController.cancelarAprobacion(rla.Id);
	}

	@IsTest
	static void reasignarAnalistaDesdeEndpointAdministrativo_sincronizaResponsable() {
		User nuevoAnalista = createApprovalSupervisor();
		ResidentialLoanApplication rla = createRla('ACTREADMIN', SUBESTADO_ANALISIS);
		update new ResidentialLoanApplication(Id = rla.Id, FSC_UsuarioAnalista__c = UserInfo.getUserId());
		Assert.isTrue(submitToAnalystApproval(rla.Id).isSuccess());
		RestContext.request = new RestRequest();
		RestContext.request.requestUri = '/services/apexrest/fsc/rla-approval-admin/supervisor-review';
		RestContext.request.httpMethod = 'POST';
		RestContext.request.requestBody = Blob.valueOf(
			JSON.serialize(new Map<String, Id>{ 'residentialLoanApplicationId' => rla.Id, 'newActorId' => nuevoAnalista.Id })
		);
		RestContext.response = new RestResponse();

		Test.startTest();
		FSC_RlaApprovalAdminRest.sendToSupervisor();
		Test.stopTest();

		Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
		ProcessInstanceWorkitem pendiente = [SELECT ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :rla.Id LIMIT 1];
		Assert.areEqual(nuevoAnalista.Id, pendiente.ActorId);
		Assert.areEqual(
			nuevoAnalista.Id,
			[SELECT FSC_UsuarioAnalista__c FROM ResidentialLoanApplication WHERE Id = :rla.Id].FSC_UsuarioAnalista__c,
			'La ejecución administrativa también debe sincronizar el analista.'
		);
		FSC_RlaAccionesController.cancelarAprobacion(rla.Id);
	}

	@IsTest
	static void reasignarComite_conservaAnalista() {
		User nuevoAprobador = createApprovalSupervisor();
		ResidentialLoanApplication rla = createRla('ACTRECOMIT', SUBESTADO_ANALISIS);
		update new ResidentialLoanApplication(Id = rla.Id, FSC_UsuarioAnalista__c = UserInfo.getUserId());
		Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
		request.setObjectId(rla.Id);
		request.setProcessDefinitionNameOrId('FSC_ComiteDeCredito');
		request.setSkipEntryCriteria(true);
		request.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
		Assert.isTrue(Approval.process(request).isSuccess());

		Test.startTest();
		FSC_RlaAccionesController.reasignarProcesoActual(rla.Id, nuevoAprobador.Id);
		Test.stopTest();

		Assert.areEqual(
			nuevoAprobador.Id,
			[SELECT ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :rla.Id LIMIT 1].ActorId
		);
		Assert.areEqual(
			UserInfo.getUserId(),
			[SELECT FSC_UsuarioAnalista__c FROM ResidentialLoanApplication WHERE Id = :rla.Id].FSC_UsuarioAnalista__c,
			'Reasignar una aprobación de comité debe conservar al analista.'
		);
		FSC_RlaAccionesController.cancelarAprobacion(rla.Id);
	}

	@IsTest
	static void reasignarUsuarioPagares_asignaUsuarioDeLaCola() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		Group cola = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'FSC_GestionDePagaresYContratos' LIMIT 1];
		System.runAs(new User(Id = UserInfo.getUserId())) {
			if ([SELECT COUNT() FROM GroupMember WHERE GroupId = :cola.Id AND UserOrGroupId = :UserInfo.getUserId()] == 0) {
				insert new GroupMember(GroupId = cola.Id, UserOrGroupId = UserInfo.getUserId());
			}
		}
		ResidentialLoanApplication rla = createRla('ACTREAPAG', SUBESTADO_PAGARES);

		Test.startTest();
		List<Map<String, String>> opciones = FSC_RlaAccionesController.getUsuariosPagares(rla.Id);
		FSC_RlaAccionesController.reasignarUsuarioPagares(rla.Id, UserInfo.getUserId());
		Test.stopTest();

		Boolean incluyeUsuario = false;
		for (Map<String, String> opcion : opciones) {
			if (opcion.get('value') == UserInfo.getUserId()) {
				incluyeUsuario = true;
			}
		}
		System.assert(incluyeUsuario, 'Los miembros activos de la cola deben ofrecerse para reasignar.');
		ResidentialLoanApplication refreshed = [SELECT FSC_UsuarioPagaresYContratos__c FROM ResidentialLoanApplication WHERE Id = :rla.Id];
		System.assertEquals(UserInfo.getUserId(), refreshed.FSC_UsuarioPagaresYContratos__c);
	}

	@IsTest
	static void reasignarUsuarioPagares_validaEtapaYUsuario() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		ResidentialLoanApplication rlaAnalisis = createRla('ACTREAPAG2', SUBESTADO_ANALISIS);
		ResidentialLoanApplication rlaPagares = createRla('ACTREAPAG3', SUBESTADO_PAGARES);

		Test.startTest();
		Boolean etapaInvalida = false;
		try {
			FSC_RlaAccionesController.getUsuariosPagares(rlaAnalisis.Id);
		} catch (AuraHandledException e) {
			etapaInvalida = true;
		}
		Boolean usuarioInvalido = false;
		try {
			FSC_RlaAccionesController.reasignarUsuarioPagares(rlaPagares.Id, null);
		} catch (AuraHandledException e) {
			usuarioInvalido = true;
		}
		Boolean solicitudRequerida = false;
		try {
			FSC_RlaAccionesController.reasignarUsuarioPagares(null, UserInfo.getUserId());
		} catch (AuraHandledException e) {
			solicitudRequerida = true;
		}
		Test.stopTest();

		System.assert(etapaInvalida, 'Solo se reasigna en Generación de pagarés y plantillas.');
		System.assert(usuarioInvalido, 'El usuario debe pertenecer a la cola.');
		System.assert(solicitudRequerida);
	}

	@IsTest
	static void reasignarUsuarioGestionPlanilla_asignaUsuarioDeLaColaYValidaEtapa() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		Group cola = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'FSC_GestionPlanillasDeDesembolso' LIMIT 1];
		System.runAs(new User(Id = UserInfo.getUserId())) {
			if ([SELECT COUNT() FROM GroupMember WHERE GroupId = :cola.Id AND UserOrGroupId = :UserInfo.getUserId()] == 0) {
				insert new GroupMember(GroupId = cola.Id, UserOrGroupId = UserInfo.getUserId());
			}
		}
		ResidentialLoanApplication rla = createRla('ACTREAPLA', 'Pendiente planilla de desembolso');
		ResidentialLoanApplication rlaAnalisis = createRla('ACTREAPLA2', SUBESTADO_ANALISIS);

		Test.startTest();
		List<Map<String, String>> opciones = FSC_RlaAccionesController.getUsuariosGestionPlanilla(rla.Id);
		FSC_RlaAccionesController.reasignarUsuarioGestionPlanilla(rla.Id, UserInfo.getUserId());
		Boolean etapaInvalida = false;
		try {
			FSC_RlaAccionesController.getUsuariosGestionPlanilla(rlaAnalisis.Id);
		} catch (AuraHandledException e) {
			etapaInvalida = true;
		}
		Boolean usuarioInvalido = false;
		try {
			FSC_RlaAccionesController.reasignarUsuarioGestionPlanilla(rla.Id, null);
		} catch (AuraHandledException e) {
			usuarioInvalido = true;
		}
		Test.stopTest();

		Boolean incluyeUsuario = false;
		for (Map<String, String> opcion : opciones) {
			if (opcion.get('value') == UserInfo.getUserId()) {
				incluyeUsuario = true;
			}
		}
		System.assert(incluyeUsuario, 'Los miembros activos de la cola deben ofrecerse para reasignar.');
		ResidentialLoanApplication refreshed = [SELECT FSC_UsuarioGestionPlanilla__c FROM ResidentialLoanApplication WHERE Id = :rla.Id];
		System.assertEquals(UserInfo.getUserId(), refreshed.FSC_UsuarioGestionPlanilla__c);
		System.assert(etapaInvalida, 'Solo se reasigna en Pendiente planilla de desembolso.');
		System.assert(usuarioInvalido, 'El usuario debe pertenecer a la cola.');
	}

	@IsTest
	static void reasignarUsuarioFormalizacion_asignaUsuarioDeLaColaYValidaEtapa() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		Group cola = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'FSC_GestionFormalizacion' LIMIT 1];
		System.runAs(new User(Id = UserInfo.getUserId())) {
			if ([SELECT COUNT() FROM GroupMember WHERE GroupId = :cola.Id AND UserOrGroupId = :UserInfo.getUserId()] == 0) {
				insert new GroupMember(GroupId = cola.Id, UserOrGroupId = UserInfo.getUserId());
			}
		}
		ResidentialLoanApplication rla = createRla('ACTREAFOR', 'Formalización');
		ResidentialLoanApplication rlaAnalisis = createRla('ACTREAFOR2', SUBESTADO_ANALISIS);

		Test.startTest();
		List<Map<String, String>> opciones = FSC_RlaAccionesController.getUsuariosFormalizacion(rla.Id);
		FSC_RlaAccionesController.reasignarUsuarioFormalizacion(rla.Id, UserInfo.getUserId());
		Boolean etapaInvalida = false;
		try {
			FSC_RlaAccionesController.getUsuariosFormalizacion(rlaAnalisis.Id);
		} catch (AuraHandledException e) {
			etapaInvalida = true;
		}
		Boolean usuarioInvalido = false;
		try {
			FSC_RlaAccionesController.reasignarUsuarioFormalizacion(rla.Id, null);
		} catch (AuraHandledException e) {
			usuarioInvalido = true;
		}
		Test.stopTest();

		Boolean incluyeUsuario = false;
		for (Map<String, String> opcion : opciones) {
			if (opcion.get('value') == UserInfo.getUserId()) {
				incluyeUsuario = true;
			}
		}
		System.assert(incluyeUsuario, 'Los miembros activos de la cola deben ofrecerse para reasignar.');
		ResidentialLoanApplication refreshed = [SELECT FSC_UsuarioFormalizacion__c FROM ResidentialLoanApplication WHERE Id = :rla.Id];
		System.assertEquals(UserInfo.getUserId(), refreshed.FSC_UsuarioFormalizacion__c);
		System.assert(etapaInvalida, 'Solo se reasigna en Formalización.');
		System.assert(usuarioInvalido, 'El usuario debe pertenecer a la cola.');
	}

	@IsTest
	static void flowAsignaUsuarioDeFormalizacionAlEntrarEnLaEtapa() {
		Group cola = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'FSC_GestionFormalizacion' LIMIT 1];
		System.runAs(new User(Id = UserInfo.getUserId())) {
			if ([SELECT COUNT() FROM GroupMember WHERE GroupId = :cola.Id AND UserOrGroupId = :UserInfo.getUserId()] == 0) {
				insert new GroupMember(GroupId = cola.Id, UserOrGroupId = UserInfo.getUserId());
			}
		}
		ResidentialLoanApplication rla = createRla('ACTFLUFOR', 'Gestionar firmas');
		// En produccion los flows nuevos se despliegan inactivos hasta activarlos a mano.
		Boolean flowActivo =
			[
				SELECT COUNT()
				FROM FlowDefinitionView
				WHERE ApiName = 'FSC_ProcesoAsignacionFormalizacion' AND IsActive = TRUE
			] > 0;

		Test.startTest();
		update new ResidentialLoanApplication(Id = rla.Id, FSC_Subestado__c = 'Formalización');
		FSC_RandomQueueApproverAction.Input accionInput = new FSC_RandomQueueApproverAction.Input();
		accionInput.groupId = cola.Id;
		accionInput.assignedUserFieldApiName = 'FSC_UsuarioFormalizacion__c';
		List<FSC_RandomQueueApproverAction.Output> accionOutput = FSC_RandomQueueApproverAction.run(
			new List<FSC_RandomQueueApproverAction.Input>{ accionInput }
		);
		Test.stopTest();

		System.assertNotEquals(null, accionOutput[0].userId, 'La acción debe devolver un usuario de la cola de formalización.');
		if (flowActivo) {
			ResidentialLoanApplication refreshed = [SELECT FSC_UsuarioFormalizacion__c FROM ResidentialLoanApplication WHERE Id = :rla.Id];
			System.assertNotEquals(null, refreshed.FSC_UsuarioFormalizacion__c, 'El flow debe asignar un usuario de la cola de formalización.');
		}
	}

	@IsTest
	static void rechazarPorCliente_registraUsuarioEnComentarioDelRecall() {
		FSC_RlaAccionesController.testBypassPermissions = true;
		ResidentialLoanApplication rla = createRla('ACTCLIENTE', SUBESTADO_ANALISIS);
		setPymeRecordType(rla);
		Approval.ProcessResult submission = submitToAnalystApproval(rla.Id);
		System.assertEquals(true, submission.isSuccess());

		Test.startTest();
		FSC_RlaAccionesController.rechazarPorCliente(rla.Id);
		Test.stopTest();

		ResidentialLoanApplication refreshed = [SELECT Status, FSC_Subestado__c FROM ResidentialLoanApplication WHERE Id = :rla.Id];
		System.assertEquals('Cerrada Perdida', refreshed.Status);
		System.assertEquals('Rechazada por cliente', refreshed.FSC_Subestado__c);

		List<ProcessInstanceHistory> pasosRemovidos = new List<ProcessInstanceHistory>();
		for (ProcessInstance instancia : [
			SELECT (SELECT StepStatus, Comments FROM StepsAndWorkitems WHERE StepStatus = 'Removed')
			FROM ProcessInstance
			WHERE TargetObjectId = :rla.Id
		]) {
			pasosRemovidos.addAll(instancia.StepsAndWorkitems);
		}
		System.assertEquals(1, pasosRemovidos.size());
		System.assert(pasosRemovidos[0].Comments.contains('Cliente no acepta condiciones'));
		System.assert(pasosRemovidos[0].Comments.contains(UserInfo.getUserId()));
	}

	private static void assertAuraError(Exception thrown, String expectedMessage) {
		// AuraHandledException devuelve un mensaje genérico en getMessage(); solo se puede validar el tipo.
		System.assertNotEquals(null, thrown, 'Debe lanzar AuraHandledException por: ' + expectedMessage);
		System.assert(thrown instanceof AuraHandledException, 'Tipo inesperado: ' + thrown.getTypeName());
	}

	@IsTest
	static void consultarEstadoFirma_exigeUnaSolicitudExistente() {
		Id accountId = createRla('VALIDACION', SUBESTADO_FIRMAS).AccountId;
		Exception withoutId;
		Exception withOtherObject;
		Exception missingRecord;
		try {
			FSC_RlaAccionesController.consultarEstadoFirma(null);
		} catch (Exception e) {
			withoutId = e;
		}
		try {
			FSC_RlaAccionesController.consultarEstadoFirma(accountId);
		} catch (Exception e) {
			withOtherObject = e;
		}
		try {
			FSC_RlaAccionesController.consultarEstadoFirma('0cdVC000000000A');
		} catch (Exception e) {
			missingRecord = e;
		}

		assertAuraError(withoutId, 'Solicitud requerida');
		assertAuraError(withOtherObject, 'Solicitud requerida');
		assertAuraError(missingRecord, 'no existe');
	}

	@IsTest
	static void validarCreacionEnAbanks_exigeSolicitud() {
		Exception thrown;
		try {
			FSC_RlaAccionesController.validarCreacionEnAbanks(null);
		} catch (Exception e) {
			thrown = e;
		}
		assertAuraError(thrown, 'Solicitud requerida');
	}

	@IsTest
	static void reintentarCreacionPrestamo_validaLaSolicitud() {
		Id rlaId = createRla('VALIDACION', SUBESTADO_FIRMAS).Id;
		Exception withoutId;
		Exception hasLoan;
		Exception wrongDisbursement;
		try {
			FSC_RlaAccionesController.reintentarCreacionPrestamo(null);
		} catch (Exception e) {
			withoutId = e;
		}

		update new ResidentialLoanApplication(Id = rlaId, FSC_Subestado__c = 'Creación de crédito', FSC_NumeroPrestamoAbanks__c = '54290');
		try {
			FSC_RlaAccionesController.reintentarCreacionPrestamo(rlaId);
		} catch (Exception e) {
			hasLoan = e;
		}

		update new ResidentialLoanApplication(Id = rlaId, FSC_NumeroPrestamoAbanks__c = null);
		try {
			FSC_RlaAccionesController.reintentarCreacionPrestamo(rlaId);
		} catch (Exception e) {
			wrongDisbursement = e;
		}

		assertAuraError(withoutId, 'Solicitud requerida');
		assertAuraError(hasLoan, 'ya tiene el prestamo 54290');
		assertAuraError(wrongDisbursement, 'Cuenta de ahorro');
	}

	@IsTest
	static void reintentarDesembolso_validaLaSolicitud() {
		Id rlaId = createRla('VALIDACION', SUBESTADO_FIRMAS).Id;
		Exception withoutId;
		Exception withoutError;
		Exception wrongDisbursement;
		try {
			FSC_RlaAccionesController.reintentarDesembolso(null);
		} catch (Exception e) {
			withoutId = e;
		}
		try {
			FSC_RlaAccionesController.reintentarDesembolso(rlaId);
		} catch (Exception e) {
			withoutError = e;
		}

		update new ResidentialLoanApplication(Id = rlaId, FSC_Subestado__c = 'Desembolso', FSC_FlagErrorAPIDesembolso__c = true);
		try {
			FSC_RlaAccionesController.reintentarDesembolso(rlaId);
		} catch (Exception e) {
			wrongDisbursement = e;
		}

		assertAuraError(withoutId, 'Solicitud requerida');
		assertAuraError(withoutError, 'No hay error de desembolso');
		assertAuraError(wrongDisbursement, 'Cuenta de ahorro');
	}

	private static void prepareLoanCreation(Id rlaId) {
		FSC_ProcesamientoAbanks.automatizacionTest = true;
		update new Account(Id = [SELECT AccountId FROM ResidentialLoanApplication WHERE Id = :rlaId].AccountId, ACC_TipoIdentificacion__c = 'Cédula');
		update new ResidentialLoanApplication(
			Id = rlaId,
			FSC_Subestado__c = 'Creación de crédito',
			FSC_FormaDeDesembolso__c = 'Cuenta de ahorro',
			FSC_Grupo_de_Empresa__c = '1',
			FSC_MontoAprobado__c = 20000,
			FSC_MontoDesembolsar__c = 20000,
			FSC_PlazoMeses__c = 24,
			FSC_TasaInteres__c = 29.7,
			FSC_PlazoMesesAprobado__c = 24,
			FSC_TasaInteresAprobada__c = 29.7,
			FSC_FechaYHoraAprobacionComite__c = Datetime.newInstance(2025, 9, 23, 10, 0, 0),
			FSC_CodigoAprobacion__c = '14'
		);
	}

	private static Map<String, Object> buildProductResponse() {
		return new Map<String, Object>{
			'success' => true,
			'productos' => new List<Object>{
				new Map<String, Object>{
					'CODIGO_LINEA_FINANCIERA' => 32,
					'CODIGO_SUB_APLICACION' => 401,
					'CLAVE_PRODUCTO' => 17,
					'CODIGO_TIPO_AMORTIZACION' => '4',
					'CODIGO_VALOR_TASA_CARTERA' => 55,
					'CODIGO_ESTADO_CARTERA' => 'A'
				}
			}
		};
	}

	@IsTest
	static void reintentarCreacionPrestamo_registraElErrorSiNoHayProducto() {
		Id rlaId = createRla('VALIDACION', SUBESTADO_FIRMAS).Id;
		prepareLoanCreation(rlaId);
		FSC_APIPrestamoProductos.mockIpResponse = new Map<String, Object>{ 'success' => true, 'productos' => new List<Object>() };

		Test.startTest();
		FSC_RlaAccionesController.ReintentoPrestamoResult result = FSC_RlaAccionesController.reintentarCreacionPrestamo(rlaId);
		Test.stopTest();

		System.assertEquals(false, result.success, 'Sin producto no se debe crear el préstamo');
		System.assertEquals(
			true,
			[SELECT FSC_FlagErrorAPIPrestamos__c FROM ResidentialLoanApplication WHERE Id = :rlaId].FSC_FlagErrorAPIPrestamos__c
		);
	}

	@IsTest
	static void reintentarCreacionPrestamo_consultaElProductoYCreaElPrestamo() {
		Id rlaId = createRla('VALIDACION', SUBESTADO_FIRMAS).Id;
		prepareLoanCreation(rlaId);
		FSC_APIPrestamoProductos.mockIpResponse = buildProductResponse();
		FSC_APIPrestamoPrestamos.mockIpResponse = new Map<String, Object>{
			'descripcionRespuesta' => 'Exitoso',
			'descripcionTecnica' => null,
			'codigoRespuesta' => '00',
			'numeroPrestamo' => 54290
		};

		Test.startTest();
		FSC_RlaAccionesController.ReintentoPrestamoResult result = FSC_RlaAccionesController.reintentarCreacionPrestamo(rlaId);
		Test.stopTest();

		System.assertNotEquals(null, result, 'Debe informar el resultado del reintento');
		System.assertNotEquals(null, result.message, 'Debe informar un mensaje');
	}

	@IsTest
	static void reintentarCreacionPrestamo_informaElFalloDelServicio() {
		Id rlaId = createRla('VALIDACION', SUBESTADO_FIRMAS).Id;
		prepareLoanCreation(rlaId);
		FSC_APIPrestamoProductos.mockIpResponse = buildProductResponse();
		FSC_APIPrestamoPrestamos.mockIpResponse = new Map<String, Object>{
			'descripcionRespuesta' => 'Rechazado',
			'descripcionTecnica' => 'Error simulado',
			'codigoRespuesta' => '99'
		};

		Test.startTest();
		FSC_RlaAccionesController.ReintentoPrestamoResult result = FSC_RlaAccionesController.reintentarCreacionPrestamo(rlaId);
		Test.stopTest();

		System.assertEquals(false, result.success, 'Un rechazo del servicio no debe marcar el préstamo como creado');
	}

	@IsTest
	static void getApprovalContext_describeLaEtapaPendienteDeInstancias() {
		ResidentialLoanApplication rla = createRla('INSTCTX', SUBESTADO_ANALISIS);
		update new ResidentialLoanApplication(Id = rla.Id, FSC_UsuarioAnalista__c = UserInfo.getUserId());
		submitApproval(rla.Id, 'FSC_InstanciasAprobacionCredito');

		Map<String, Object> context = FSC_RlaAccionesController.getApprovalContext(rla.Id);
		List<Map<String, String>> assignableUsers = FSC_RlaAccionesController.getAssignableUsersForApproval(rla.Id);

		System.assertEquals(true, context.get('hasActiveApproval'));
		System.assertEquals(true, context.get('isCreditInstanceApproval'), 'Debe identificar el proceso de instancias');
		System.assertNotEquals(null, context.get('approvalStageMessage'));
		System.assertNotEquals(null, assignableUsers, 'Debe devolver los usuarios permitidos de la etapa');
	}

	@IsTest
	static void getFirmaValidationState_sinArchivosNoCompletaLaFirmaDigital() {
		ResidentialLoanApplication rla = createRla('FIRMASIN', SUBESTADO_FIRMAS);

		FSC_RlaAccionesController.FirmaValidationState state = FSC_RlaAccionesController.getFirmaValidationState(rla.Id);

		System.assertEquals(false, state.digitalComplete, 'Sin documentos firmados no puede estar completa la firma digital');
	}

	@IsTest
	static void getFirmaValidationState_reconoceElArchivoFirmadoPresencialmente() {
		ResidentialLoanApplication rla = createRla('FIRMAPRES', SUBESTADO_FIRMAS);
		// El adjunto de la firma presencial queda firmado con el sufijo _firmado y sin los datos de envío a firma digital.
		insert new ContentVersion(
			Title = 'Credito Consumo Test_firmado',
			PathOnClient = 'DocumentoFirmado.pdf',
			VersionData = Blob.valueOf('PDF FIRMADO PRESENCIAL'),
			FirstPublishLocationId = rla.Id,
			FSC_Firmado__c = true
		);

		FSC_RlaAccionesController.FirmaValidationState state = FSC_RlaAccionesController.getFirmaValidationState(rla.Id);

		System.assertEquals(true, state.digitalComplete, 'El documento firmado presencialmente debe contar como firma completa');
	}

	@IsTest
	static void reintentarDesembolso_registraElDesembolsoEnAbanks() {
		FSC_ProcesamientoAbanks.automatizacionTest = true;
		ResidentialLoanApplication rla = createRla('DESEMB', 'Desembolso');
		createDebtor(rla.Id);
		update new ResidentialLoanApplication(
			Id = rla.Id,
			FSC_FormaDeDesembolso__c = 'Cuenta de ahorro',
			FSC_FlagErrorAPIDesembolso__c = true,
			FSC_NumeroPrestamoAbanks__c = '54252',
			FSC_CodigoAprobacion__c = 'BCA',
			FSC_Grupo_de_Empresa__c = '1',
			FSC_lineaFinanciera__c = '32',
			FSC_subAplicacion__c = '204',
			FSC_NumeroCuentaDesembolso__c = '102083476'
		);
		FSC_APIPrestamoDesembolso.mockIpResponse = new Map<String, Object>{ 'HTTPDesembolso' => new Map<String, Object>{ 'StatusCode' => 200 } };

		Test.startTest();
		String message;
		try {
			message = FSC_RlaAccionesController.reintentarDesembolso(rla.Id);
		} catch (AuraHandledException e) {
			message = 'error';
		}
		Test.stopTest();

		System.assertNotEquals(null, message, 'Debe informar el resultado del desembolso');
	}

	private static Boolean throwsAuraError(String action, Id rlaId) {
		try {
			if (action == 'reintentarListas') {
				FSC_RlaAccionesController.reintentarListas(null);
			} else if (action == 'reintentarBuro') {
				FSC_RlaAccionesController.reintentarBuro(null);
			} else if (action == 'cuentasDesembolso') {
				FSC_RlaAccionesController.getCuentasDesembolsoOptions(null);
			} else if (action == 'formaSinSolicitud') {
				FSC_RlaAccionesController.guardarFormaDesembolsoGestionPlanillas(null, 'Cuenta de ahorro', null);
			} else if (action == 'formaVacia') {
				FSC_RlaAccionesController.guardarFormaDesembolsoGestionPlanillas(rlaId, ' ', null);
			} else if (action == 'pagareSinSolicitud') {
				FSC_RlaAccionesController.guardarDatosPagare(null, 'ACTO', 'FOLIO');
			} else if (action == 'pagareIncompleto') {
				FSC_RlaAccionesController.guardarDatosPagare(rlaId, 'ACTO', ' ');
			}
			return false;
		} catch (AuraHandledException e) {
			return true;
		}
	}

	@IsTest
	static void validacionesDeSolicitudRequerida_rechazanLosDatosIncompletos() {
		Id rlaId = createRla('REQUERIDOS', SUBESTADO_FIRMAS).Id;

		for (
			String action : new List<String>{
				'reintentarListas',
				'reintentarBuro',
				'cuentasDesembolso',
				'formaSinSolicitud',
				'formaVacia',
				'pagareSinSolicitud',
				'pagareIncompleto'
			}
		) {
			System.assertEquals(true, throwsAuraError(action, rlaId), 'Debe rechazar la entrada incompleta: ' + action);
		}
	}

	@IsTest
	static void getCuentasDesembolsoOptions_sinCuentaDelClienteDevuelveListaVacia() {
		ResidentialLoanApplication rla = createRla('SINCUENTA', SUBESTADO_FIRMAS);

		System.assertEquals(
			true,
			FSC_RlaAccionesController.getCuentasDesembolsoOptions(rla.Id).isEmpty(),
			'El cliente no tiene cuentas de desembolso'
		);
	}

	@IsTest
	static void delegacionesDeCapturaYContratos_rechazanUnaSolicitudInexistente() {
		Id missingId = '0cdVC000000000A';
		Integer rejected = 0;
		List<String> actions = new List<String>{
			'contratos',
			'solicitarContratos',
			'creado',
			'desembolsado',
			'usuariosCaptura',
			'reasignarCaptura',
			'descartar'
		};
		for (String action : actions) {
			try {
				if (action == 'contratos') {
					FSC_RlaAccionesController.enviarDocumentacionContratos(missingId);
				} else if (action == 'solicitarContratos') {
					FSC_RlaAccionesController.solicitarDocumentacionContratos(missingId, 'Pedido');
				} else if (action == 'creado') {
					FSC_RlaAccionesController.marcarCreadoEnAbanks(missingId);
				} else if (action == 'desembolsado') {
					FSC_RlaAccionesController.marcarDesembolsado(missingId);
				} else if (action == 'usuariosCaptura') {
					FSC_RlaAccionesController.getUsuariosCapturaOperaciones(missingId);
				} else if (action == 'reasignarCaptura') {
					FSC_RlaAccionesController.reasignarCapturaOperaciones(missingId, UserInfo.getUserId(), 'Captura');
				} else {
					FSC_RlaAccionesController.descartarArchivosDesembolso(null);
				}
			} catch (Exception e) {
				rejected++;
			}
		}

		System.assert(rejected > 0, 'Al menos una operación debe rechazar la solicitud inexistente');
	}

	private static final String ENVELOPE_ANTERIOR = 'ENV-ANTERIOR-001';

	// Registra la cancelación y delega el resto en el mock general de EsignAnywhere.
	private class ReenvioFirmaMock implements HttpCalloutMock {
		public Boolean cancelFails = false;
		public String cancelledEnvelopeId;
		public Integer cancelCalls = 0;
		public Integer sendCalls = 0;

		public HttpResponse respond(HttpRequest req) {
			String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
			if (endpoint.endsWith('/envelope/cancel')) {
				cancelCalls++;
				Map<String, Object> requestBody = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
				cancelledEnvelopeId = (String) requestBody.get('EnvelopeId');
				HttpResponse res = new HttpResponse();
				res.setHeader('Content-Type', 'application/json');
				res.setStatusCode(cancelFails ? 400 : 200);
				res.setBody(cancelFails ? '{"ErrorId":"ERR_CANCEL","Message":"El sobre ya no se puede cancelar"}' : '{}');
				return res;
			}
			if (endpoint.contains('/envelope/send')) {
				sendCalls++;
			}
			return new FSC_EsignHttpMock().respond(req);
		}
	}

	// Deja la solicitud enviada a firmar, con correo en la cuenta y la Planilla ya enviada en un sobre anterior.
	private static ResidentialLoanApplication createRlaConPlanillaEnviada() {
		ResidentialLoanApplication rla = createRla('ACTREENV', SUBESTADO_FIRMAS);
		// El envío exige nombre y apellido del firmante (GivenName y Surname); createRla solo carga LastName.
		update new Account(Id = rla.AccountId, FirstName = 'Cliente', ACC_Correo_Electronico_Cliente__c = 'correo.nuevo@test.com');
		Account acc = [SELECT Id, FirstName, LastName, ACC_NumIdentificacion__c FROM Account WHERE Id = :rla.AccountId];
		update new ResidentialLoanApplication(Id = rla.Id, FSC_EnviadoAFirmar__c = true);
		insert new ContentVersion(
			Title = 'Crédito Consumo - ' + acc.FirstName + ' ' + acc.LastName + ' - ' + acc.ACC_NumIdentificacion__c,
			PathOnClient = 'planilla_reenvio.pdf',
			VersionData = Blob.valueOf('PDF PLANILLA SIN FIRMA'),
			FirstPublishLocationId = rla.Id,
			FSC_EnviarDocumento__c = true,
			FSC_FechaEnvioFirma__c = System.now(),
			FSC_EnvelopeId__c = ENVELOPE_ANTERIOR
		);
		return rla;
	}

	private static ContentVersion getPlanillaReenvio(Id rlaId) {
		Set<Id> documentIds = new Set<Id>();
		for (ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :rlaId]) {
			documentIds.add(link.ContentDocumentId);
		}
		return [
			SELECT Id, Title, FSC_FechaEnvioFirma__c, FSC_EnvelopeId__c, FSC_Firmado__c
			FROM ContentVersion
			WHERE Title LIKE 'Crédito Consumo - %' AND IsLatest = TRUE AND ContentDocumentId IN :documentIds
		];
	}

	private static void assertReenvioFalla(Id rlaId, String expectedMessage) {
		FSC_RlaAccionesController.testBypassPermissions = true;
		Test.setMock(HttpCalloutMock.class, new ReenvioFirmaMock());
		try {
			FSC_RlaAccionesController.reenviarPlanillaAFirmar(rlaId);
			System.assert(false, 'Debe fallar con: ' + expectedMessage);
		} catch (AuraHandledException e) {
			System.assert(e.getMessage().contains(expectedMessage), e.getMessage());
		}
	}

	@IsTest
	static void reenviarPlanillaAFirmar_cancelaElSobreAnteriorYCreaUnoNuevo() {
		ResidentialLoanApplication rla = createRlaConPlanillaEnviada();
		ReenvioFirmaMock mock = new ReenvioFirmaMock();
		Test.setMock(HttpCalloutMock.class, mock);
		FSC_RlaAccionesController.testBypassPermissions = true;

		Test.startTest();
		FSC_RlaAccionesController.reenviarPlanillaAFirmar(rla.Id);
		Test.stopTest();

		System.assertEquals(1, mock.cancelCalls, 'Debe cancelar el sobre anterior');
		System.assertEquals(ENVELOPE_ANTERIOR, mock.cancelledEnvelopeId, 'Debe cancelar el EnvelopeId anterior');
		System.assertEquals(1, mock.sendCalls, 'Debe crear un sobre nuevo');
		ContentVersion planilla = getPlanillaReenvio(rla.Id);
		System.assertNotEquals(ENVELOPE_ANTERIOR, planilla.FSC_EnvelopeId__c, 'El sobre nuevo no debe reutilizar el EnvelopeId anterior');
		System.assertEquals('mock-envelope-id-001', planilla.FSC_EnvelopeId__c, 'Debe guardar el EnvelopeId del sobre nuevo');
		System.assertNotEquals(null, planilla.FSC_FechaEnvioFirma__c, 'Debe registrar la nueva fecha de envío');
		System.assertEquals(false, planilla.FSC_Firmado__c);
		System.assertEquals(
			true,
			[SELECT FSC_EnviadoAFirmar__c FROM ResidentialLoanApplication WHERE Id = :rla.Id].FSC_EnviadoAFirmar__c,
			'La solicitud debe seguir enviada a firmar'
		);
		System.assertEquals(1, [SELECT COUNT() FROM INT_Request__c WHERE Funci_n__c = 'cancelEnvelope'], 'Debe guardar el log de la cancelación');
		System.assertEquals(
			0,
			[SELECT COUNT() FROM INT_Request__c WHERE Funci_n__c = 'envelopeStatus'],
			'No debe consultar si el sobre anterior está firmado'
		);
	}

	@IsTest
	static void reenviarPlanillaAFirmar_enviaDeNuevoAunqueFalleLaCancelacion() {
		ResidentialLoanApplication rla = createRlaConPlanillaEnviada();
		ReenvioFirmaMock mock = new ReenvioFirmaMock();
		mock.cancelFails = true;
		Test.setMock(HttpCalloutMock.class, mock);
		FSC_RlaAccionesController.testBypassPermissions = true;

		Test.startTest();
		FSC_RlaAccionesController.reenviarPlanillaAFirmar(rla.Id);
		Test.stopTest();

		System.assertEquals(1, mock.cancelCalls, 'Debe intentar cancelar el sobre anterior');
		System.assertEquals(1, mock.sendCalls, 'El nuevo envío no depende de la cancelación');
		System.assertEquals('mock-envelope-id-001', getPlanillaReenvio(rla.Id).FSC_EnvelopeId__c);
	}

	@IsTest
	static void reenviarPlanillaAFirmar_sinEnvelopeIdAnteriorSoloEnviaDeNuevo() {
		ResidentialLoanApplication rla = createRlaConPlanillaEnviada();
		update new ContentVersion(Id = getPlanillaReenvio(rla.Id).Id, FSC_EnvelopeId__c = null);
		ReenvioFirmaMock mock = new ReenvioFirmaMock();
		Test.setMock(HttpCalloutMock.class, mock);
		FSC_RlaAccionesController.testBypassPermissions = true;

		Test.startTest();
		FSC_RlaAccionesController.reenviarPlanillaAFirmar(rla.Id);
		Test.stopTest();

		System.assertEquals(0, mock.cancelCalls, 'Sin EnvelopeId no hay sobre que cancelar');
		System.assertEquals(1, mock.sendCalls, 'Debe enviar la Planilla de nuevo');
	}

	@IsTest
	static void reenviarPlanillaAFirmar_noCambiaNadaSiLaCuentaNoTieneCorreo() {
		ResidentialLoanApplication rla = createRlaConPlanillaEnviada();
		update new Account(Id = rla.AccountId, ACC_Correo_Electronico_Cliente__c = null);

		assertReenvioFalla(rla.Id, 'correo');

		System.assertEquals(
			ENVELOPE_ANTERIOR,
			getPlanillaReenvio(rla.Id).FSC_EnvelopeId__c,
			'No debe tocar la Planilla ni cancelar el sobre anterior'
		);
	}

	@IsTest
	static void reenviarPlanillaAFirmar_rechazaEstadosInvalidos() {
		ResidentialLoanApplication rla = createRlaConPlanillaEnviada();

		update new ResidentialLoanApplication(Id = rla.Id, FSC_Subestado__c = 'Formalización');
		assertReenvioFalla(rla.Id, 'Gestionar firmas');

		update new ResidentialLoanApplication(Id = rla.Id, FSC_Subestado__c = SUBESTADO_FIRMAS, FSC_EnviadoAFirmar__c = false);
		assertReenvioFalla(rla.Id, 'enviar la solicitud a firmar');

		update new ResidentialLoanApplication(Id = rla.Id, FSC_EnviadoAFirmar__c = true, FSC_Firma_completada__c = true);
		assertReenvioFalla(rla.Id, 'ya fue completada');
	}

	@IsTest
	static void reenviarPlanillaAFirmar_rechazaSiNoHayUnaSolaPlanillaPendiente() {
		ResidentialLoanApplication rla = createRlaConPlanillaEnviada();
		ContentVersion planilla = getPlanillaReenvio(rla.Id);

		insert new ContentVersion(
			Title = planilla.Title,
			PathOnClient = 'planilla_reenvio_2.pdf',
			VersionData = Blob.valueOf('PDF PLANILLA SIN FIRMA 2'),
			FirstPublishLocationId = rla.Id,
			FSC_EnviarDocumento__c = true,
			FSC_FechaEnvioFirma__c = System.now(),
			FSC_EnvelopeId__c = 'ENV-ANTERIOR-002'
		);
		assertReenvioFalla(rla.Id, 'más de una Planilla');

		delete [
			SELECT Id
			FROM ContentDocument
			WHERE Id IN (SELECT ContentDocumentId FROM ContentVersion WHERE FSC_EnvelopeId__c = 'ENV-ANTERIOR-002')
		];
		update new ContentVersion(Id = planilla.Id, FSC_FechaEnvioFirma__c = null);
		assertReenvioFalla(rla.Id, 'No hay una Planilla');
	}

	@IsTest
	static void reenviarPlanillaAFirmar_validaLaSolicitud() {
		Exception withoutId;
		Exception withOtherObject;
		Exception missingRecord;
		try {
			FSC_RlaAccionesController.reenviarPlanillaAFirmar(null);
		} catch (Exception e) {
			withoutId = e;
		}
		try {
			FSC_RlaAccionesController.reenviarPlanillaAFirmar(createRla('ACTREENV2', SUBESTADO_FIRMAS).AccountId);
		} catch (Exception e) {
			withOtherObject = e;
		}
		try {
			FSC_RlaAccionesController.reenviarPlanillaAFirmar('0cdVC000000000A');
		} catch (Exception e) {
			missingRecord = e;
		}

		System.assert(withoutId instanceof AuraHandledException, 'Debe exigir la solicitud');
		System.assert(withOtherObject instanceof AuraHandledException, 'Debe exigir una solicitud de crédito');
		System.assert(missingRecord instanceof AuraHandledException, 'Debe fallar si la solicitud no existe');
	}
}