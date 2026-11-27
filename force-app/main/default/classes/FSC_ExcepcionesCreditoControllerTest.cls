@IsTest
private class FSC_ExcepcionesCreditoControllerTest {
	private static final String RLA_ELEGIBLE = 'RLA Excepción Elegible';
	private static final String RLA_NO_ELEGIBLE = 'RLA Excepción No Elegible';
	private static final String RLA_CONDICIONADA = 'RLA Excepción Condicionada';
	private static final String TIPO_NEGOCIOS = 'Excepciones de Negocios';

	@TestSetup
	static void setupTestData() {
		Account account = FSC_ExcepcionTestDataFactory.createAccount('1001', true);
		FSC_ExcepcionTestDataFactory.createSolicitud(account.Id, RLA_ELEGIBLE, 'En Motor Buró', 1000, true);
		FSC_ExcepcionTestDataFactory.createSolicitud(account.Id, RLA_NO_ELEGIBLE, 'Análisis de crédito', 1000, true);
		ResidentialLoanApplication condicionada = FSC_ExcepcionTestDataFactory.createSolicitud(
			account.Id,
			RLA_CONDICIONADA,
			'En Motor Buró',
			1000,
			true
		);
		insert FSC_ExcepcionTestDataFactory.buildExcepcion(condicionada.Id, 1, 'Pendiente', 'Presentar garantía adicional');
	}

	@IsTest
	static void shouldReturnConfiguredCatalogWhenOptionsAreRequested() {
		Integer expected = 0;
		for (FSC_ExcepcionesDeCredito__mdt config : FSC_ExcepcionesDeCredito__mdt.getAll().values()) {
			if (String.isNotBlank(config.FSC_Tipo__c) && String.isNotBlank(config.FSC_Detalle__c)) {
				expected++;
			}
		}

		Test.startTest();
		List<FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion> options = FSC_ExcepcionesCreditoController.getOpcionesExcepcion();
		Test.stopTest();

		Assert.areEqual(expected, options.size(), 'Debe devolver cada configuración válida del Custom Metadata.');
	}

	@IsTest
	static void shouldExposeConfiguredCapacityWhenRequestHasNoExceptions() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		forceAuthorization();
		FSC_ExcepcionConfig.testMaximoExcepciones = 5;

		Test.startTest();
		Map<String, Object> context = FSC_ExcepcionesCreditoController.getContextoExcepcion(solicitud.Id);
		Test.stopTest();

		Assert.areEqual(0, context.get('cantidad'), 'Una solicitud nueva debe iniciar con cero excepciones.');
		Assert.areEqual(5, context.get('maximo'), 'Debe exponer el máximo configurado al LWC.');
		Assert.areEqual(5, context.get('disponibles'), 'La capacidad inicial debe adaptarse a la configuración.');
		Assert.areEqual(true, context.get('puedeSolicitar'), 'Un oficial autorizado debe poder solicitar la primera.');
	}

	@IsTest
	static void shouldCreateChildAndSubmitChildApprovalWhenRequestIsValid() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);
		forceAuthorization();

		Test.startTest();
		Id excepcionId = FSC_ExcepcionesCreditoController.solicitarExcepcion(
			solicitud.Id,
			option.tipo,
			option.detalle,
			'  Justificación de prueba  '
		);
		Test.stopTest();

		FSC_Excepcion__c created = [
			SELECT FSC_Solicitud_Prestamo__c, FSC_Tipo__c, FSC_Detalle__c, FSC_Motivo__c, FSC_Estado__c
			FROM FSC_Excepcion__c
			WHERE Id = :excepcionId
		];
		Assert.areEqual(solicitud.Id, created.FSC_Solicitud_Prestamo__c, 'El hijo debe relacionarse con la solicitud.');
		Assert.areEqual(option.tipo, created.FSC_Tipo__c, 'Debe almacenar el tipo configurado.');
		Assert.areEqual(option.detalle, created.FSC_Detalle__c, 'Debe almacenar el detalle configurado.');
		Assert.areEqual('Justificación de prueba', created.FSC_Motivo__c, 'Debe normalizar el motivo.');
		Assert.areEqual('Pendiente', created.FSC_Estado__c, 'Debe iniciar pendiente.');
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :excepcionId],
			'La aprobación debe tener como objetivo el hijo, no ResidentialLoanApplication.'
		);
	}

	@IsTest
	static void shouldAllowThirdAndThenHideRequestActionWhenTwoChildrenExist() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		insert new List<FSC_Excepcion__c>{
			FSC_ExcepcionTestDataFactory.buildExcepcion(solicitud.Id, 1, 'Aprobada', null),
			FSC_ExcepcionTestDataFactory.buildExcepcion(solicitud.Id, 2, 'Rechazada', null)
		};
		forceAuthorization();
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);

		Test.startTest();
		Id thirdId = FSC_ExcepcionesCreditoController.solicitarExcepcion(solicitud.Id, option.tipo, option.detalle, 'Tercera excepción');
		Map<String, Object> context = FSC_ExcepcionesCreditoController.getContextoExcepcion(solicitud.Id);
		Test.stopTest();

		Assert.isNotNull(thirdId, 'La tercera excepción debe poder crearse.');
		Assert.areEqual(3, context.get('cantidad'), 'El contador debe incluir estados aprobados, rechazados y pendientes.');
		Assert.areEqual(true, context.get('limiteAlcanzado'), 'El contexto debe indicar que se alcanzó el límite.');
		Assert.areEqual(true, context.get('canActOnApproval'), 'Debe seleccionar la excepción cuyo Work Item puede atender el usuario.');
		Assert.areEqual(false, context.get('puedeSolicitar'), 'La acción de solicitud debe ocultarse después de la tercera.');
	}

	@IsTest
	static void shouldRejectRequestWhenThreeChildrenAlreadyExist() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		insert new List<FSC_Excepcion__c>{
			FSC_ExcepcionTestDataFactory.buildExcepcion(solicitud.Id, 1, 'Aprobada', null),
			FSC_ExcepcionTestDataFactory.buildExcepcion(solicitud.Id, 2, 'Rechazada', null),
			FSC_ExcepcionTestDataFactory.buildExcepcion(solicitud.Id, 3, 'Pendiente', null)
		};
		forceAuthorization();
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);

		Test.startTest();
		try {
			FSC_ExcepcionesCreditoController.solicitarExcepcion(solicitud.Id, option.tipo, option.detalle, 'Cuarta excepción');
			Assert.fail('Se esperaba el bloqueo de la cuarta excepción.');
		} catch (AuraHandledException exceptionInstance) {
			Assert.isNotNull(exceptionInstance, 'Debe devolver un error controlado al LWC.');
		}
		Test.stopTest();
		Assert.areEqual(3, [SELECT COUNT() FROM FSC_Excepcion__c WHERE FSC_Solicitud_Prestamo__c = :solicitud.Id], 'No debe crear un cuarto hijo.');
	}

	@IsTest
	static void shouldApproveConditionWhenClientAccepts() {
		FSC_Excepcion__c excepcion = getExcepcion(RLA_CONDICIONADA);
		forceAuthorization();

		Test.startTest();
		FSC_ExcepcionesCreditoController.responderCondicionCliente(excepcion.Id, true);
		Test.stopTest();

		Assert.areEqual('Aprobada', [SELECT FSC_Estado__c FROM FSC_Excepcion__c WHERE Id = :excepcion.Id].FSC_Estado__c, 'Debe aprobar el hijo.');
	}

	@IsTest
	static void shouldCloseLoanWhenClientRejectsCondition() {
		FSC_Excepcion__c excepcion = getExcepcion(RLA_CONDICIONADA);
		forceAuthorization();

		Test.startTest();
		FSC_ExcepcionesCreditoController.responderCondicionCliente(excepcion.Id, false);
		Test.stopTest();

		ResidentialLoanApplication solicitud = getSolicitud(RLA_CONDICIONADA);
		Assert.areEqual('Rechazada', [SELECT FSC_Estado__c FROM FSC_Excepcion__c WHERE Id = :excepcion.Id].FSC_Estado__c, 'Debe rechazar el hijo.');
		Assert.areEqual('Cerrada Perdida', solicitud.Status, 'Debe cerrar la solicitud.');
		Assert.areEqual('Rechazada por cliente', solicitud.FSC_Subestado__c, 'Debe distinguir el rechazo del cliente.');
	}

	@IsTest
	static void shouldApproveChildWhenAssignedApprovalIsCompleted() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);
		forceAuthorization();
		Id excepcionId = FSC_ExcepcionesCreditoController.solicitarExcepcion(
			solicitud.Id,
			option.tipo,
			option.detalle,
			'Justificación para aprobar'
		);

		Test.startTest();
		FSC_ExcepcionesCreditoController.aprobarExcepcionConCondicion(excepcionId, 'Presentar fiador solidario');
		Test.stopTest();

		FSC_Excepcion__c conditioned = [SELECT FSC_Estado__c, FSC_Condicion__c FROM FSC_Excepcion__c WHERE Id = :excepcionId];
		Assert.areEqual('Pendiente', conditioned.FSC_Estado__c, 'Debe permanecer Pendiente esperando respuesta del cliente.');
		Assert.areEqual('Presentar fiador solidario', conditioned.FSC_Condicion__c, 'Debe almacenar la condición.');
	}

	@IsTest
	static void shouldApproveChildDirectlyWhenNoConditionIsGiven() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);
		forceAuthorization();
		Id excepcionId = FSC_ExcepcionesCreditoController.solicitarExcepcion(solicitud.Id, option.tipo, option.detalle, 'Justificación para aprobar');

		Test.startTest();
		FSC_ExcepcionesCreditoController.aprobarExcepcion(excepcionId);
		Test.stopTest();

		Assert.areEqual(
			'Aprobada',
			[SELECT FSC_Estado__c FROM FSC_Excepcion__c WHERE Id = :excepcionId].FSC_Estado__c,
			'La decisión debe actualizar el hijo.'
		);
	}

	@IsTest
	static void shouldRejectChildAndCloseParentWithSingleAuthorizedUpdate() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);
		forceAuthorization();
		Id excepcionId = FSC_ExcepcionesCreditoController.solicitarExcepcion(
			solicitud.Id,
			option.tipo,
			option.detalle,
			'Justificación para rechazar'
		);

		Test.startTest();
		FSC_ExcepcionesCreditoController.rechazarExcepcion(excepcionId, 'Riesgo no aceptado');
		Test.stopTest();

		FSC_Excepcion__c excepcion = [SELECT FSC_Estado__c FROM FSC_Excepcion__c WHERE Id = :excepcionId];
		ResidentialLoanApplication updated = [
			SELECT Status, FSC_Subestado__c, FSC_Motivo_Rechazo__c
			FROM ResidentialLoanApplication
			WHERE Id = :solicitud.Id
		];
		Assert.areEqual('Rechazada', excepcion.FSC_Estado__c, 'La acción final debe rechazar la excepción hija.');
		Assert.areEqual('Cerrada Perdida', updated.Status, 'El rechazo debe cerrar la solicitud una sola vez.');
		Assert.areEqual('Rechazado por análisis', updated.FSC_Subestado__c, 'Debe conservar el origen del rechazo.');
		Assert.areEqual('Riesgo no aceptado', updated.FSC_Motivo_Rechazo__c, 'Debe conservar el motivo informado por el aprobador.');
	}

	@IsTest
	static void shouldRejectInvalidSubstatusWhenRequestIsAttempted() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_NO_ELEGIBLE);
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);
		forceAuthorization();

		Test.startTest();
		try {
			FSC_ExcepcionesCreditoController.solicitarExcepcion(solicitud.Id, option.tipo, option.detalle, 'Motivo');
			Assert.fail('Se esperaba un error por subestado no elegible.');
		} catch (AuraHandledException exceptionInstance) {
			Assert.isNotNull(exceptionInstance, 'Debe devolver un error controlado.');
		}
		Test.stopTest();
	}

	@IsTest
	static void shouldRejectUnknownConfigurationWhenRequestIsAttempted() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		forceAuthorization();

		Test.startTest();
		try {
			FSC_ExcepcionesCreditoController.solicitarExcepcion(solicitud.Id, 'Tipo inexistente', 'Detalle inexistente', 'Motivo');
			Assert.fail('Se esperaba un error por configuración inexistente.');
		} catch (AuraHandledException exceptionInstance) {
			Assert.isNotNull(exceptionInstance, 'Debe devolver un error controlado.');
		}
		Test.stopTest();
	}

	@IsTest
	static void shouldRejectNullSolicitudWhenContextIsRequested() {
		forceAuthorization();
		Test.startTest();
		try {
			FSC_ExcepcionesCreditoController.getContextoExcepcion(null);
			Assert.fail('Se esperaba un error por solicitud nula.');
		} catch (AuraHandledException exceptionInstance) {
			Assert.isNotNull(exceptionInstance, 'Debe controlar el Id nulo.');
		}
		Test.stopTest();
	}

	@IsTest
	static void shouldRejectLoanIdWhenChildExceptionIsRequired() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		forceAuthorization();

		Test.startTest();
		try {
			FSC_ExcepcionesCreditoController.responderCondicionCliente(solicitud.Id, true);
			Assert.fail('El registro padre ya no debe aceptarse como excepción.');
		} catch (AuraHandledException exceptionInstance) {
			Assert.isNotNull(exceptionInstance, 'Debe rechazar explícitamente el identificador del modelo eliminado.');
		}
		Test.stopTest();
	}

	@IsTest
	static void shouldRejectBlankConditionWhenConditionalApprovalIsAttempted() {
		forceAuthorization();
		Test.startTest();
		try {
			FSC_ExcepcionesCreditoController.aprobarExcepcionConCondicion(null, ' ');
			Assert.fail('Se esperaba un error por condición vacía.');
		} catch (AuraHandledException exceptionInstance) {
			Assert.isNotNull(exceptionInstance, 'Debe controlar la condición vacía.');
		}
		Test.stopTest();
	}

	@IsTest
	static void shouldFormatApproverProperlyForUserAndQueue() {
		User currentUser = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId()];
		String userFormatted = FSC_ExcepcionesCreditoController.formatAprobador(currentUser.Id, currentUser.Name);
		Assert.areEqual(currentUser.Name, userFormatted, 'Para un usuario directo debe devolver su nombre sin modificar.');

		Group testGroup = new Group(Name = 'Grupo Test Excepcion', Type = 'Regular');
		insert testGroup;
		insert new GroupMember(GroupId = testGroup.Id, UserOrGroupId = currentUser.Id);

		Group testQueue = new Group(Name = 'Cola Test Excepcion', Type = 'Queue');
		insert testQueue;
		insert new GroupMember(GroupId = testQueue.Id, UserOrGroupId = testGroup.Id);

		String queueFormatted = FSC_ExcepcionesCreditoController.formatAprobador(testQueue.Id, 'Cola Test Excepcion');
		Assert.isTrue(queueFormatted.contains('Cola Test Excepcion'), 'Debe incluir el nombre base de la cola.');
		Assert.isTrue(queueFormatted.contains(currentUser.Name), 'Debe incluir el nombre del usuario miembro.');

		String nullFormatted = FSC_ExcepcionesCreditoController.formatAprobador(null, null);
		Assert.isNull(nullFormatted, 'Para base nula debe retornar null.');
	}

	@IsTest
	static void shouldObserveAndResubmitWithoutClosingLoanApplication() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);
		forceAuthorization();
		Id excepcionId = FSC_ExcepcionesCreditoController.solicitarExcepcion(
			solicitud.Id,
			option.tipo,
			option.detalle,
			'Justificación inicial incompleta'
		);

		Test.startTest();
		FSC_ExcepcionesCreditoController.devolverExcepcionConObservacion(
			excepcionId,
			'  Favor indicar cantidad de moras, entidad y tipo de facilidad  '
		);

		FSC_Excepcion__c observada = [
			SELECT FSC_Estado__c, FSC_Observaciones_Aprobador__c, FSC_Paso_Observacion__c, FSC_Motivo__c
			FROM FSC_Excepcion__c
			WHERE Id = :excepcionId
		];
		ResidentialLoanApplication solicitudTrasObservar = [
			SELECT Status, FSC_Subestado__c
			FROM ResidentialLoanApplication
			WHERE Id = :solicitud.Id
		];
		Map<String, Object> ctxObservada = FSC_ExcepcionesCreditoController.getContextoExcepcion(solicitud.Id);

		Assert.areEqual('Observada', observada.FSC_Estado__c, 'La excepción debe pasar a estado Observada.');
		Assert.areEqual(
			'Favor indicar cantidad de moras, entidad y tipo de facilidad',
			observada.FSC_Observaciones_Aprobador__c,
			'Debe persistir la observación normalizada.'
		);
		Assert.isNotNull(observada.FSC_Paso_Observacion__c, 'Debe registrar el aprobador que observó.');
		Assert.areEqual('En proceso', solicitudTrasObservar.Status, 'La devolución con observación NO debe cerrar la solicitud padre.');
		Assert.areEqual('Observada', ctxObservada.get('estado'), 'El contexto debe exponer el estado Observada.');
		Assert.areEqual(true, ctxObservada.get('tienePendientes'), 'Observada debe seguir bloqueando el avance ordinario.');
		Assert.areEqual(true, ctxObservada.get('puedeSubsanarObservacion'), 'El oficial debe poder subsanar la excepción.');
		Assert.areEqual(false, ctxObservada.get('hasActiveApproval'), 'No debe tener workitem activo mientras está observada.');

		List<FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion> allOptions = FSC_ExcepcionesCreditoController.getOpcionesExcepcion();
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion updatedOption = option;
		for (FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion candidate : allOptions) {
			if (candidate.detalle != option.detalle) {
				updatedOption = candidate;
				break;
			}
		}

		FSC_ExcepcionesCreditoController.subsanarYReenviarExcepcion(
			excepcionId,
			updatedOption.tipo,
			updatedOption.detalle,
			'  Posee 5 moras a 30 días en Scotiabank ya solventadas con carta saldo  '
		);
		Test.stopTest();

		FSC_Excepcion__c reenviada = [
			SELECT FSC_Estado__c, FSC_Tipo__c, FSC_Detalle__c, FSC_Motivo__c, FSC_Observaciones_Aprobador__c
			FROM FSC_Excepcion__c
			WHERE Id = :excepcionId
		];
		Map<String, Object> ctxReenviada = FSC_ExcepcionesCreditoController.getContextoExcepcion(solicitud.Id);
		Map<String, Object> ctxDirectoExcepcion = FSC_ExcepcionesCreditoController.getContextoPorExcepcion(excepcionId);
		Assert.areEqual('Pendiente', reenviada.FSC_Estado__c, 'Tras subsanar debe regresar a estado Pendiente.');
		Assert.areEqual(updatedOption.tipo, reenviada.FSC_Tipo__c, 'Debe actualizar el tipo de la excepción subsanada.');
		Assert.areEqual(updatedOption.detalle, reenviada.FSC_Detalle__c, 'Debe actualizar el detalle de la excepción subsanada.');
		Assert.areEqual(
			'Posee 5 moras a 30 días en Scotiabank ya solventadas con carta saldo',
			reenviada.FSC_Motivo__c,
			'Debe actualizar el motivo subsanado.'
		);
		Assert.areEqual(true, ctxReenviada.get('hasActiveApproval'), 'Debe generar una nueva instancia de aprobación activa.');
		Assert.areEqual(1, (Integer) ctxReenviada.get('cantidad'), 'No debe consumir cupos adicionales de excepción.');
		Assert.areEqual(excepcionId, ctxDirectoExcepcion.get('excepcionId'), 'getContextoPorExcepcion debe devolver la excepción consultada.');
		Assert.areEqual('Pendiente', ctxDirectoExcepcion.get('estado'), 'getContextoPorExcepcion debe reflejar el estado actual.');
		Assert.areEqual(true, ctxDirectoExcepcion.get('canActOnApproval'), 'getContextoPorExcepcion debe habilitar las acciones al aprobador.');
	}

	@IsTest
	static void shouldValidateObservationAndResubmitGuardConditions() {
		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);
		forceAuthorization();
		Id excepcionId = FSC_ExcepcionesCreditoController.solicitarExcepcion(
			solicitud.Id,
			option.tipo,
			option.detalle,
			'Justificación para validar guardias'
		);

		Test.startTest();
		try {
			FSC_ExcepcionesCreditoController.devolverExcepcionConObservacion(excepcionId, '   ');
			Assert.fail('Debe rechazar observación en blanco.');
		} catch (AuraHandledException exBlank) {
			Assert.isNotNull(exBlank);
		}

		try {
			FSC_ExcepcionesCreditoController.subsanarYReenviarExcepcion(excepcionId, null, null, 'Intento sobre pendiente');
			Assert.fail('No debe permitir subsanar una excepción que no está en estado Observada.');
		} catch (AuraHandledException exInvalidState) {
			Assert.isNotNull(exInvalidState);
		}

		try {
			FSC_ExcepcionesCreditoController.subsanarYReenviarExcepcion(excepcionId, null, null, ' ');
			Assert.fail('Debe exigir descripción al subsanar.');
		} catch (AuraHandledException exEmptyDesc) {
			Assert.isNotNull(exEmptyDesc);
		}

		FSC_ExcepcionesCreditoController.devolverExcepcionConObservacion(excepcionId, 'Favor corregir detalle');
		try {
			FSC_ExcepcionesCreditoController.subsanarYReenviarExcepcion(
				excepcionId,
				option.tipo,
				'Detalle Inexistente No Configurado',
				'Motivo subsanado válido'
			);
			Assert.fail('Debe rechazar un detalle no configurado en Custom Metadata.');
		} catch (AuraHandledException exInvalidConfig) {
			Assert.isNotNull(exInvalidConfig);
		}
		Test.stopTest();
	}

	@IsTest
	static void shouldPreventSubmitterFromApprovingOwnExceptionWhenReassigned() {
		Profile vimencaProfile = [
			SELECT Id
			FROM Profile
			WHERE Name = 'Perfil Vimenca'
			LIMIT 1
		];
		PermissionSetGroup psgSolCred = [
			SELECT Id, Status
			FROM PermissionSetGroup
			WHERE DeveloperName = 'FSC_PSG_SolCred'
			LIMIT 1
		];
		if (psgSolCred.Status != 'Updated') {
			Test.calculatePermissionSetGroup(psgSolCred.Id);
		}

		String oficina = null;
		for (Schema.PicklistEntry entry : User.USE_Oficina__c.getDescribe().getPicklistValues()) {
			if (entry.isActive()) {
				oficina = entry.getValue();
				break;
			}
		}
		String uniqueToken = String.valueOf(DateTime.now().getTime());
		User regularUser = new User(
			FirstName = 'Oficial',
			LastName = 'PruebaAutoAprobacion',
			Alias = 'ofauto',
			Email = 'oficial.auto.' + uniqueToken + '@bv.com.do.test',
			Username = 'oficial.auto.' + uniqueToken + '@bv.com.do.test',
			ProfileId = vimencaProfile.Id,
			TimeZoneSidKey = 'America/Santo_Domingo',
			LocaleSidKey = 'es_DO',
			EmailEncodingKey = 'UTF-8',
			LanguageLocaleKey = 'es',
			USE_Codigo__c = 'OFAUTO',
			USE_Oficina__c = oficina,
			Canal_Atencion__c = 'TELEASISTENCIA'
		);
		User secondApproverUser = new User(
			FirstName = 'Gerente',
			LastName = 'PruebaColaExcepcion',
			Alias = 'gecola',
			Email = 'gerente.cola.' + uniqueToken + '@bv.com.do.test',
			Username = 'gerente.cola.' + uniqueToken + '@bv.com.do.test',
			ProfileId = vimencaProfile.Id,
			TimeZoneSidKey = 'America/Santo_Domingo',
			LocaleSidKey = 'es_DO',
			EmailEncodingKey = 'UTF-8',
			LanguageLocaleKey = 'es',
			USE_Codigo__c = 'GECOLA',
			USE_Oficina__c = oficina,
			Canal_Atencion__c = 'TELEASISTENCIA'
		);
		Group subGroup = new Group(Name = 'Subgrupo Excepcion ' + uniqueToken.right(5), Type = 'Regular');
		Group parentQueue = new Group(Name = 'Cola Excepcion ' + uniqueToken.right(5), Type = 'Queue');
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert new Datos_Maestros__c(Name = 'Oficina test auto', DM_Codigo_Oficina__c = oficina, DM_Tipo__c = 'Oficina');
			insert new List<User>{ regularUser, secondApproverUser };
			insert new PermissionSetAssignment(AssigneeId = regularUser.Id, PermissionSetGroupId = psgSolCred.Id);
			PermissionSet psOficial = [SELECT Id FROM PermissionSet WHERE Name = 'FSC_PS_Oficial_Negocio' LIMIT 1];
			insert new PermissionSetAssignment(AssigneeId = regularUser.Id, PermissionSetId = psOficial.Id);

			insert subGroup;
			insert parentQueue;
			insert new QueueSobject(QueueId = parentQueue.Id, SobjectType = 'Case');
			insert new GroupMember(GroupId = subGroup.Id, UserOrGroupId = secondApproverUser.Id);
			insert new GroupMember(GroupId = parentQueue.Id, UserOrGroupId = subGroup.Id);
		}

		ResidentialLoanApplication solicitud = getSolicitud(RLA_ELEGIBLE);
		update new ResidentialLoanApplication(Id = solicitud.Id, OwnerId = regularUser.Id);
		FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option = getOption(TIPO_NEGOCIOS);
		FSC_Excepcion__c exc = new FSC_Excepcion__c(
			FSC_Solicitud_Prestamo__c = solicitud.Id,
			FSC_Tipo__c = option.tipo,
			FSC_Detalle__c = option.detalle,
			FSC_Motivo__c = 'Motivo de oficial',
			FSC_Estado__c = 'Pendiente'
		);
		insert exc;

		System.runAs(regularUser) {
			FSC_ExcepcionApprovalService.submit(exc.Id);
		}

		// Probar devolución con observación enviando notificación al Owner distinto
		forceAuthorization();
		FSC_ExcepcionesCreditoController.devolverExcepcionConObservacion(exc.Id, 'Aclarar motivo');
		System.runAs(regularUser) {
			FSC_ExcepcionesCreditoController.subsanarYReenviarExcepcion(exc.Id, null, null, 'Motivo aclarado por oficial');
		}

		ProcessInstanceWorkitem wi = [
			SELECT Id, ActorId
			FROM ProcessInstanceWorkitem
			WHERE ProcessInstance.TargetObjectId = :exc.Id
			LIMIT 1
		];

		FSC_ExcepcionesCreditoController.testForceAuthorized = false;
		FSC_ExcepcionApprovalService.testForceAuthorized = false;

		Test.startTest();
		// 1. Verificar resolución de grupos anidados (Queue -> Regular Group -> secondApproverUser)
		wi.ActorId = parentQueue.Id;
		update wi;
		System.runAs(secondApproverUser) {
			Map<Id, List<ProcessInstanceWorkitem>> queueWiMap = FSC_ExcepcionApprovalService.getWorkItemsByTarget(new Set<Id>{ exc.Id });
			Assert.isTrue(
				FSC_ExcepcionApprovalService.canCurrentUserAct(queueWiMap.get(exc.Id)),
				'El miembro del grupo anidado dentro de la cola debe estar autorizado.'
			);
			Set<Id> queueActionable = FSC_ExcepcionApprovalService.getActionableTargetIds(queueWiMap);
			Assert.isTrue(queueActionable.contains(exc.Id), 'El aprobador legítimo distinto al submitter debe poder actuar.');
		}

		// 2. Verificar bloqueo de usuario no perteneciente a la cola
		System.runAs(regularUser) {
			try {
				FSC_ExcepcionApprovalService.assertCurrentUserCanAct(exc.Id);
				Assert.fail('Usuario ajeno a la cola no debe poder actuar.');
			} catch (AuraHandledException exNotAssigned) {
				Assert.isNotNull(exNotAssigned);
			}
		}

		// 3. Simular que un gerente reasigna por error el Workitem al mismo oficial solicitante
		wi.ActorId = regularUser.Id;
		update wi;

		System.runAs(regularUser) {
			Assert.isTrue(FSC_ExcepcionApprovalService.canCurrentUserAct(wi), 'canCurrentUserAct evalúa membresía directa.');
			Assert.isFalse(FSC_ExcepcionApprovalService.canCurrentUserAct((ProcessInstanceWorkitem) null), 'Workitem nulo debe ser false.');
			Assert.isTrue(FSC_ExcepcionApprovalService.hasActiveWorkItem(exc.Id), 'Debe reportar workitem activo.');
			Assert.isFalse(FSC_ExcepcionApprovalService.hasActiveWorkItem(null), 'Id nulo debe reportar false.');
			Assert.isTrue(FSC_ExcepcionApprovalService.getActionableTargetIds(null).isEmpty(), 'Mapa nulo debe retornar vacío.');
			Map<Id, List<ProcessInstanceWorkitem>> wiMap = FSC_ExcepcionApprovalService.getWorkItemsByTarget(new Set<Id>{ exc.Id });
			Set<Id> actionableIds = FSC_ExcepcionApprovalService.getActionableTargetIds(wiMap);
			Assert.isFalse(actionableIds.contains(exc.Id), 'El solicitante no debe ver su propia excepción como accionable para aprobar.');

			try {
				FSC_ExcepcionApprovalService.assertCurrentUserCanAct(null);
				Assert.fail('Debe validar Id nulo.');
			} catch (AuraHandledException exNull) {
				Assert.isNotNull(exNull);
			}

			try {
				FSC_ExcepcionApprovalService.assertCurrentUserCanAct(exc.Id);
				Assert.fail('Debe bloquear assertCurrentUserCanAct del solicitante.');
			} catch (AuraHandledException exAssert) {
				Assert.isNotNull(exAssert);
			}

			try {
				FSC_ExcepcionApprovalService.process(exc.Id, 'Approve', 'Intento autoaprobación');
				Assert.fail('Debe bloquear la autoaprobación del solicitante.');
			} catch (AuraHandledException exSelfApprove) {
				Assert.isNotNull(exSelfApprove, 'Debe lanzar excepción controlada ante autoaprobación.');
			}
		}
		Test.stopTest();
	}

	private static void forceAuthorization() {
		FSC_ExcepcionesCreditoController.testForceAuthorized = true;
		FSC_ExcepcionApprovalService.testForceAuthorized = true;
	}

	private static ResidentialLoanApplication getSolicitud(String name) {
		String pattern = name + '%';
		return [
			SELECT Id, Status, FSC_Subestado__c
			FROM ResidentialLoanApplication
			WHERE Name LIKE :pattern
			LIMIT 1
		];
	}

	private static FSC_Excepcion__c getExcepcion(String solicitudName) {
		String pattern = solicitudName + '%';
		return [
			SELECT Id, FSC_Estado__c, FSC_Condicion__c
			FROM FSC_Excepcion__c
			WHERE FSC_Solicitud_Prestamo__r.Name LIKE :pattern
			LIMIT 1
		];
	}

	private static FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion getOption(String tipo) {
		for (FSC_ExcepcionesCreditoController.FSC_OpcionExcepcion option : FSC_ExcepcionesCreditoController.getOpcionesExcepcion()) {
			if (option.tipo == tipo) {
				return option;
			}
		}
		Assert.fail('No se encontró una opción configurada para: ' + tipo);
		return null;
	}
}