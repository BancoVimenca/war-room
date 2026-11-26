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
	static void testGetWorkspaceMetrics() {
		Test.startTest();
		FSC_CreditWorkspaceController.WorkspaceMetrics metrics = FSC_CreditWorkspaceController.getWorkspaceMetrics();
		Test.stopTest();

		Assert.isNotNull(metrics, 'Las métricas no deben ser nulas');
		Assert.isTrue(metrics.montoTotalCartera >= 850000, 'El monto total debe sumar las solicitudes activas');
		Assert.isTrue(metrics.excepcionesActivas >= 1, 'Debe haber al menos 1 excepción activa');
	}

	@IsTest
	static void testGetCreditApplicationsTabs() {
		Test.startTest();
		List<FSC_CreditWorkspaceController.CreditApplicationRow> allRows =
			FSC_CreditWorkspaceController.getCreditApplications('todos', '');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> excRows =
			FSC_CreditWorkspaceController.getCreditApplications('excepciones', '');

		List<FSC_CreditWorkspaceController.CreditApplicationRow> analisisRows =
			FSC_CreditWorkspaceController.getCreditApplications('analisis', 'Workspace');
		Test.stopTest();

		Assert.isFalse(allRows.isEmpty(), 'Debe retornar filas en la pestaña general');
		Assert.isFalse(excRows.isEmpty(), 'Debe retornar solicitudes con excepción');
		Assert.isFalse(analisisRows.isEmpty(), 'Debe filtrar por texto y por subestado análisis');
	}
}
