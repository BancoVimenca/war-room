@IsTest
private class FSC_CreditWorkspaceControllerTest {

	@TestSetup
	static void makeData() {
		Account acc = new Account(Name = 'Cliente Prueba Workspace');
		insert acc;

		ResidentialLoanApplication rla = new ResidentialLoanApplication(
			Name = 'Crédito Prueba Workspace 1',
			AccountId = acc.Id,
			Status = 'En proceso',
			FSC_Subestado__c = 'Recepción de documentos – Análisis',
			FSC_Monto__c = 500000
		);
		insert rla;

		ResidentialLoanApplication rlaBuro = new ResidentialLoanApplication(
			Name = 'Crédito Prueba Excepcion Buro',
			AccountId = acc.Id,
			Status = 'En proceso',
			FSC_Subestado__c = 'En Motor Buró',
			FSC_SolicitaExcepcionParaRechazoDeBuro__c = true,
			FSC_Monto__c = 350000
		);
		insert rlaBuro;
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
		Test.stopTest();

		Assert.isNotNull(metricsAdmin, 'Las métricas admin no deben ser nulas');
		Assert.isNotNull(metricsAnalista, 'Las métricas analista no deben ser nulas');
		Assert.isNotNull(metricsOficial, 'Las métricas oficial no deben ser nulas');
		Assert.isTrue(metricsAdmin.montoTotalCartera >= 850000, 'El monto total debe sumar las solicitudes activas');
	}

	@IsTest
	static void testGetCreditApplicationsSimulatedRoles() {
		Test.startTest();
		List<FSC_CreditWorkspaceController.CreditApplicationRow> allRows =
			FSC_CreditWorkspaceController.getCreditApplications('todos', '', 'ADMIN_ALL');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> excRows =
			FSC_CreditWorkspaceController.getCreditApplications('excepciones', '', 'EXCEPCIONES');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> analisisRows =
			FSC_CreditWorkspaceController.getCreditApplications('analisis', 'Workspace', 'ANALISTA');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> misCasosAdmin =
			FSC_CreditWorkspaceController.getCreditApplications('mis_casos', '', 'ADMIN_ALL');
		Test.stopTest();

		Assert.isFalse(allRows.isEmpty(), 'Debe retornar filas en la pestaña general');
		Assert.isFalse(excRows.isEmpty(), 'Debe retornar solicitudes con excepción');
		Assert.isFalse(analisisRows.isEmpty(), 'Debe filtrar por texto y por subestado análisis');
		Assert.isFalse(misCasosAdmin.isEmpty(), 'Admin en modo ALL debe ver casos activos');
	}
}
