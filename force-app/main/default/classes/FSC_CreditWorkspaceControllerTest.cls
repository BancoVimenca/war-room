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

		List<FSC_CreditWorkspaceController.CreditApplicationRow> aprobacionesRows =
			FSC_CreditWorkspaceController.getCreditApplications('aprobaciones', '', 'ADMIN_ALL');
		Test.stopTest();

		Assert.isFalse(allRows.isEmpty(), 'Debe retornar filas en la pestaña general');
		Assert.isFalse(excRows.isEmpty(), 'Debe retornar solicitudes con excepción');
		Assert.isFalse(analisisRows.isEmpty(), 'Debe filtrar por texto y por subestado análisis');
		Assert.isFalse(comiteRows.isEmpty(), 'Debe retornar solicitudes de comité');
		Assert.isFalse(formalizacionRows.isEmpty(), 'Debe retornar solicitudes de formalizacion');
		Assert.isFalse(misCasosAdmin.isEmpty(), 'Admin en modo ALL debe ver casos activos');
		Assert.isNotNull(aprobacionesRows, 'La lista de aprobaciones no debe ser nula');
	}

	@IsTest
	static void testProcessApprovalDecisionExceptions() {
		Test.startTest();
		try {
			FSC_CreditWorkspaceController.processApprovalDecision(null, 'Approve', 'Comentario');
			Assert.fail('Debe fallar con workitemId nulo');
		} catch (Exception e) {
			Assert.isNotNull(e.getMessage());
		}

		try {
			FSC_CreditWorkspaceController.processApprovalDecision('04i000000000001AAA', 'Invalido', 'Comentario');
			Assert.fail('Debe fallar con acción inválida');
		} catch (Exception e) {
			Assert.isNotNull(e.getMessage());
		}
		Test.stopTest();
	}
}
