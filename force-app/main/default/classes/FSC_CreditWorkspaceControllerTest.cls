@IsTest
private class FSC_CreditWorkspaceControllerTest {

	@TestSetup
	static void makeData() {
		Account acc = new Account(Name = 'Cliente Prueba Workspace');
		insert acc;

		// 1. Solicitud en Análisis
		ResidentialLoanApplication rla1 = new ResidentialLoanApplication(
			Name = 'Crédito Prueba Workspace 1',
			AccountId = acc.Id,
			Status = 'En proceso',
			FSC_Subestado__c = 'Recepción de documentos – Análisis',
			FSC_Monto__c = 500000,
			FSC_UsuarioAnalista__c = UserInfo.getUserId()
		);
		insert rla1;

		// 2. Solicitud en Buró con Excepción
		ResidentialLoanApplication rlaBuro = new ResidentialLoanApplication(
			Name = 'Crédito Prueba Excepcion Buro',
			AccountId = acc.Id,
			Status = 'En proceso',
			FSC_Subestado__c = 'En Motor Buró',
			FSC_SolicitaExcepcionParaRechazoDeBuro__c = true,
			FSC_Monto__c = 350000,
			FSC_UsuarioAnalista__c = UserInfo.getUserId()
		);
		insert rlaBuro;

		// 3. Solicitud en Pagarés
		ResidentialLoanApplication rlaPagares = new ResidentialLoanApplication(
			Name = 'Crédito Prueba Pagares',
			AccountId = acc.Id,
			Status = 'En proceso',
			FSC_Subestado__c = 'Generación de pagarés y plantillas',
			FSC_Monto__c = 200000,
			FSC_UsuarioPagaresYContratos__c = UserInfo.getUserId()
		);
		insert rlaPagares;

		// 4. Solicitud en Firmas
		ResidentialLoanApplication rlaFirmas = new ResidentialLoanApplication(
			Name = 'Crédito Prueba Firmas',
			AccountId = acc.Id,
			Status = 'En proceso',
			FSC_Subestado__c = 'Gestionar firmas',
			FSC_Monto__c = 250000,
			FSC_UsuarioFormalizacion__c = UserInfo.getUserId()
		);
		insert rlaFirmas;

		// 5. Solicitud en Desembolso / Archivo
		ResidentialLoanApplication rlaDesembolso = new ResidentialLoanApplication(
			Name = 'Crédito Prueba Desembolso',
			AccountId = acc.Id,
			Status = 'En proceso',
			FSC_Subestado__c = 'Archivo y custodia',
			FSC_Monto__c = 150000,
			FSC_UsuarioGestionPlanilla__c = UserInfo.getUserId()
		);
		insert rlaDesembolso;

		// 6. Solicitud en Comité y Supervisión
		ResidentialLoanApplication rlaComite = new ResidentialLoanApplication(
			Name = 'Crédito Prueba Comite',
			AccountId = acc.Id,
			Status = 'En proceso',
			FSC_Subestado__c = 'Análisis de crédito',
			FSC_Monto__c = 800000,
			FSC_DebeRevisarComite__c = true,
			FSC_DebeRevisarSupervisor__c = true,
			FSC_UsuarioComite__c = UserInfo.getUserId(),
			FSC_UsuarioSupervisor__c = UserInfo.getUserId()
		);
		insert rlaComite;

		// Excepción hija pendiente para cubrir mapeos de FSC_Excepcion__c
		FSC_Excepcion__c exc = new FSC_Excepcion__c(
			FSC_Solicitud_Prestamo__c = rlaComite.Id,
			FSC_Estado__c = 'Pendiente',
			FSC_Tipo__c = 'Excepciones de Negocios',
			FSC_Detalle__c = 'Excepción de prueba cobertura'
		);
		insert exc;

		// 7. Casos de fallback sin usuarios asignados y estados cerrados (Ganada / Perdida)
		insert new List<ResidentialLoanApplication>{
			new ResidentialLoanApplication(
				Name = 'Crédito Sin Analista Asignado',
				AccountId = acc.Id,
				Status = 'En proceso',
				FSC_Subestado__c = 'Análisis de crédito',
				FSC_Monto__c = 120000
			),
			new ResidentialLoanApplication(
				Name = 'Crédito Sin Pagares Asignado',
				AccountId = acc.Id,
				Status = 'En proceso',
				FSC_Subestado__c = 'Generación de pagarés y plantillas',
				FSC_Monto__c = 130000
			),
			new ResidentialLoanApplication(
				Name = 'Crédito Sin Formalizacion Asignado',
				AccountId = acc.Id,
				Status = 'En proceso',
				FSC_Subestado__c = 'Gestionar firmas',
				FSC_Monto__c = 140000
			),
			new ResidentialLoanApplication(
				Name = 'Crédito Sin Planilla Asignado',
				AccountId = acc.Id,
				Status = 'En proceso',
				FSC_Subestado__c = 'Archivo y custodia',
				FSC_Monto__c = 110000
			),
			new ResidentialLoanApplication(
				Name = 'Crédito Fallback Comite',
				AccountId = acc.Id,
				Status = 'En proceso',
				FSC_Subestado__c = 'Documentación para contratos',
				FSC_DebeRevisarComite__c = true,
				FSC_UsuarioComite__c = UserInfo.getUserId(),
				FSC_Monto__c = 90000
			),
			new ResidentialLoanApplication(
				Name = 'Crédito Fallback Supervisor',
				AccountId = acc.Id,
				Status = 'En proceso',
				FSC_Subestado__c = 'Documentación para contratos',
				FSC_DebeRevisarSupervisor__c = true,
				FSC_UsuarioSupervisor__c = UserInfo.getUserId(),
				FSC_Monto__c = 95000
			),
			new ResidentialLoanApplication(
				Name = 'CréditoCerradoGanado',
				AccountId = acc.Id,
				Status = 'Cerrada Ganada',
				FSC_Subestado__c = 'Completado',
				FSC_Monto__c = 300000
			),
			new ResidentialLoanApplication(
				Name = 'CréditoCerradoPerdido',
				AccountId = acc.Id,
				Status = 'Cerrada Perdida',
				FSC_Subestado__c = 'Rechazado por análisis',
				FSC_Monto__c = 180000
			)
		};
	}

	@IsTest
	static void testGetWorkspaceMetricsRoles() {
		Test.startTest();
		FSC_CreditWorkspaceController.WorkspaceMetrics metricsAdmin =
			FSC_CreditWorkspaceController.getWorkspaceMetrics('ADMIN_ALL');

		FSC_CreditWorkspaceController.WorkspaceMetrics metricsAnalista =
			FSC_CreditWorkspaceController.getWorkspaceMetrics('ANALISTA');

		FSC_CreditWorkspaceController.WorkspaceMetrics metricsOficial =
			FSC_CreditWorkspaceController.getWorkspaceMetrics('OFICIAL');

		FSC_CreditWorkspaceController.WorkspaceMetrics metricsComite =
			FSC_CreditWorkspaceController.getWorkspaceMetrics('COMITE');

		FSC_CreditWorkspaceController.WorkspaceMetrics metricsFormalizacion =
			FSC_CreditWorkspaceController.getWorkspaceMetrics('FORMALIZACION');

		FSC_CreditWorkspaceController.WorkspaceMetrics metricsExcepciones =
			FSC_CreditWorkspaceController.getWorkspaceMetrics('EXCEPCIONES');

		FSC_CreditWorkspaceController.WorkspaceMetrics metricsReal =
			FSC_CreditWorkspaceController.getWorkspaceMetrics('');
		Test.stopTest();

		Assert.isNotNull(metricsAdmin, 'Las métricas admin no deben ser nulas');
		Assert.isNotNull(metricsAnalista, 'Las métricas analista no deben ser nulas');
		Assert.isNotNull(metricsOficial, 'Las métricas oficial no deben ser nulas');
		Assert.isNotNull(metricsComite, 'Las métricas comite no deben ser nulas');
		Assert.isNotNull(metricsFormalizacion, 'Las métricas formalizacion no deben ser nulas');
		Assert.isNotNull(metricsExcepciones, 'Las métricas excepciones no deben ser nulas');
		Assert.isTrue(metricsAdmin.montoTotalCartera >= 2000000, 'El monto total debe sumar las solicitudes activas');
		Assert.isTrue(metricsAdmin.canGenerateActasComite, 'Admin en vista global debe poder generar actas');
		Assert.isTrue(metricsComite.canGenerateActasComite, 'Rol simulado Comité debe poder generar actas');
		Assert.isTrue(metricsAnalista.canGenerateActasComite, 'Rol simulado Analista debe poder generar actas');
		Assert.isFalse(metricsOficial.canGenerateActasComite, 'Rol simulado Oficial no debe ver el botón de actas');
		Assert.isNotNull(
			FSC_CreditWorkspaceController.checkCanGenerateActasComite(UserInfo.getUserId(), false, 'REAL_USER'),
			'La verificación de acceso real por SetupEntityAccess debe retornar un booleano válido'
		);
	}

	@IsTest
	static void testGetCreditApplicationsAllTabs() {
		Test.startTest();
		List<FSC_CreditWorkspaceController.CreditApplicationRow> allRows =
			FSC_CreditWorkspaceController.getCreditApplications('todos', '', 'ADMIN_ALL');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> excRows =
			FSC_CreditWorkspaceController.getCreditApplications('excepciones', '', 'EXCEPCIONES');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> analisisRows =
			FSC_CreditWorkspaceController.getCreditApplications('analisis', 'Workspace', 'ANALISTA');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> comiteRows =
			FSC_CreditWorkspaceController.getCreditApplications('comite', '', 'COMITE');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> formalizacionRows =
			FSC_CreditWorkspaceController.getCreditApplications('formalizacion', '', 'FORMALIZACION');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> misCasosAdmin =
			FSC_CreditWorkspaceController.getCreditApplications('mis_casos', '', 'ADMIN_ALL');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> misCasosOficial =
			FSC_CreditWorkspaceController.getCreditApplications('mis_casos', '', 'OFICIAL');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> misCasosAnalista =
			FSC_CreditWorkspaceController.getCreditApplications('mis_casos', '', 'ANALISTA');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> aprobacionesAdmin =
			FSC_CreditWorkspaceController.getCreditApplications('aprobaciones', '', 'ADMIN_ALL');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> aprobacionesUser =
			FSC_CreditWorkspaceController.getCreditApplications('aprobaciones', '', '');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> recepcionRows =
			FSC_CreditWorkspaceController.getCreditApplications('recepcion', '', 'OFICIAL');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> pagaresRows =
			FSC_CreditWorkspaceController.getCreditApplications('pagares', '', 'FORMALIZACION');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> firmasRows =
			FSC_CreditWorkspaceController.getCreditApplications('firmas', '', 'FORMALIZACION');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> desembolsoRows =
			FSC_CreditWorkspaceController.getCreditApplications('desembolso', '', 'FORMALIZACION');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> finalizadasRows =
			FSC_CreditWorkspaceController.getCreditApplications('finalizadas', '', 'ADMIN_ALL');
		Test.stopTest();

		Assert.isFalse(allRows.isEmpty(), 'Debe retornar filas en la pestaña general');
		Assert.isFalse(excRows.isEmpty(), 'Debe retornar solicitudes con excepción');
		Assert.isFalse(analisisRows.isEmpty(), 'Debe filtrar por texto y por subestado análisis');
		Assert.isFalse(comiteRows.isEmpty(), 'Debe retornar solicitudes de comité');
		Assert.isFalse(formalizacionRows.isEmpty(), 'Debe retornar solicitudes de formalizacion');
		Assert.isFalse(misCasosAdmin.isEmpty(), 'Admin en modo ALL debe ver casos activos');
		Assert.isFalse(misCasosAnalista.isEmpty(), 'Analista debe ver sus casos asignados');
		Assert.isNotNull(aprobacionesAdmin, 'Aprobaciones admin no debe ser nulo');
		Assert.isNotNull(aprobacionesUser, 'Aprobaciones user no debe ser nulo');
	}

	@IsTest
	static void testProcessApprovalDecisionValidation() {
		Test.startTest();
		try {
			FSC_CreditWorkspaceController.processApprovalDecision(null, 'Approve', 'Comentario prueba');
			Assert.fail('Debió lanzar excepción por workitemId nulo');
		} catch (AuraHandledException e) {
			Assert.isNotNull(e.getMessage());
		}

		try {
			FSC_CreditWorkspaceController.processApprovalDecision('04i000000000001AAA', 'AccionInvalida', 'Comentario prueba');
			Assert.fail('Debió lanzar excepción por acción inválida');
		} catch (AuraHandledException e) {
			Assert.isNotNull(e.getMessage());
		}
		Test.stopTest();
	}
}