@IsTest
private class FSC_ActaComiteDownloadActionTest {
	private static ResidentialLoanApplication createRLAApproved(Id accountId, DateTime approvedDt) {
		FSC_CreditPolicyGuard.bypassInTests = true;
		ResidentialLoanApplication rla = new ResidentialLoanApplication();
		rla.AccountId = accountId;
		rla.FSC_SolicitudAprobadaPorComite__c = true;
		rla.FSC_FechaYHoraAprobacionComite__c = approvedDt;
		rla.Name = 'Test RLA ' + String.valueOf(approvedDt);
		rla.FSC_Monto__c = 1000;
		rla.FSC_MontoAprobado__c = 900;
		rla.FSC_PlazoMeses__c = 10;
		rla.FSC_PlazoMesesAprobado__c = 9;
		rla.FSC_TasaInteres__c = 12;
		rla.FSC_TasaInteresAprobada__c = 10;
		rla.FSC_Aplica_Garantia__c = false;
		rla.FSC_DecisionComite__c = 'Aprobada con condición';

		insert rla;
		return rla;
	}

	@IsTest
	static void testGenerateUrl_actaDateRequired() {
		Test.startTest();
		List<FSC_ActaComiteDownloadAction.Request> reqs = new List<FSC_ActaComiteDownloadAction.Request>();
		reqs.add(new FSC_ActaComiteDownloadAction.Request());

		List<FSC_ActaComiteDownloadAction.Response> resList = FSC_ActaComiteDownloadAction.generateUrl(reqs);
		Test.stopTest();

		System.assertEquals(1, resList.size());
		System.assertEquals(false, resList[0].success);
		System.assert(resList[0].message != null && resList[0].message.contains('actaDate'), 'Debe avisar que actaDate es requerido');
		System.assertEquals(null, resList[0].pdfUrl);
	}

	@IsTest
	static void testGenerateUrl_noApplications() {
		Date actaDate = Date.today();

		FSC_ActaComiteDownloadAction.Request req = new FSC_ActaComiteDownloadAction.Request();
		req.actaDate = actaDate;

		Test.startTest();
		List<FSC_ActaComiteDownloadAction.Response> resList = FSC_ActaComiteDownloadAction.generateUrl(
			new List<FSC_ActaComiteDownloadAction.Request>{ req }
		);
		Test.stopTest();

		System.assertEquals(1, resList.size());
		FSC_ActaComiteDownloadAction.Response res = resList[0];

		System.assertEquals(true, res.success);
		System.assertEquals(0, res.totalApplications);
		System.assertEquals(null, res.pdfUrl);
		System.assert(res.message != null && res.message.contains('No hay solicitudes'), 'Mensaje cuando no hay RLAs');
	}

	@IsTest
	static void testGenerateUrl_excludesNonCommitteeInstancesAndIncludesLateEvening() {
		FSC_CreditPolicyGuard.bypassInTests = true;
		Account acc = new Account(Name = 'Cliente Filtro Instancias');
		insert acc;

		Date actaDate = Date.today();
		// Aprobación de instancia Analista / Subgerente NO debe disparar acta vacía
		ResidentialLoanApplication nonCommittee = new ResidentialLoanApplication(
			AccountId = acc.Id,
			Name = 'RLA Analista Gerencia',
			FSC_InstanciaAprobacion__c = 'Analista + Subgerente o Gerente',
			FSC_RevisionAnalistaCompleta__c = true,
			FSC_FechaYHoraAprobacionComite__c = DateTime.newInstance(actaDate, Time.newInstance(15, 0, 0, 0)),
			FSC_Monto__c = 250000,
			FSC_MontoAprobado__c = 250000,
			FSC_Plazo_meses__c = '36',
			FSC_PlazoMesesAprobado__c = 36,
			FSC_TasaInteres__c = 15,
			FSC_TasaInteresAprobada__c = 15
		);
		insert nonCommittee;

		FSC_ActaComiteDownloadAction.Request req = new FSC_ActaComiteDownloadAction.Request();
		req.actaDate = actaDate;

		List<FSC_ActaComiteDownloadAction.Response> emptyRes = FSC_ActaComiteDownloadAction.generateUrl(
			new List<FSC_ActaComiteDownloadAction.Request>{ req }
		);
		System.assertEquals(0, emptyRes[0].totalApplications, 'No debe contar instancias de Analista/Gerencia');
		System.assertEquals(null, emptyRes[0].pdfUrl, 'No debe generar URL vacía para instancias no comité');

		// Aprobación de Comité II a las 22:30 hora local (antes se perdía por .addHours(-4))
		ResidentialLoanApplication lateCommittee = new ResidentialLoanApplication(
			AccountId = acc.Id,
			Name = 'RLA Comité II Noche',
			FSC_InstanciaAprobacion__c = 'Comité II',
			FSC_RevisionAnalistaCompleta__c = true,
			FSC_SolicitudAprobadaPorComite__c = true,
			FSC_FechaYHoraAprobacionComite__c = DateTime.newInstance(actaDate, Time.newInstance(22, 30, 0, 0)),
			FSC_Monto__c = 10000000,
			FSC_MontoAprobado__c = 10000000,
			FSC_Plazo_meses__c = '48',
			FSC_PlazoMesesAprobado__c = 48,
			FSC_TasaInteres__c = 14,
			FSC_TasaInteresAprobada__c = 14
		);
		insert lateCommittee;

		Test.startTest();
		List<FSC_ActaComiteDownloadAction.Response> committeeRes = FSC_ActaComiteDownloadAction.generateUrl(
			new List<FSC_ActaComiteDownloadAction.Request>{ req }
		);
		Test.stopTest();

		System.assertEquals(1, committeeRes[0].totalApplications, 'Debe incluir Comité II aprobado después de las 20:00 local');
		System.assertNotEquals(null, committeeRes[0].pdfUrl, 'Debe generar URL para Comité II');
	}

	@IsTest
	static void testGenerateUrl_multipleRequests() {
		Account acc = new Account(Name = 'Cliente Multi');
		insert acc;

		Date d1 = Date.today();
		Date d2 = Date.today().addDays(-1);

		createRLAApproved(acc.Id, DateTime.newInstance(d1.year(), d1.month(), d1.day(), 11, 0, 0));

		FSC_ActaComiteDownloadAction.Request r1 = new FSC_ActaComiteDownloadAction.Request();
		r1.actaDate = d1;

		FSC_ActaComiteDownloadAction.Request r2 = new FSC_ActaComiteDownloadAction.Request();
		r2.actaDate = d2;

		Test.startTest();
		List<FSC_ActaComiteDownloadAction.Response> resList = FSC_ActaComiteDownloadAction.generateUrl(
			new List<FSC_ActaComiteDownloadAction.Request>{ r1, r2 }
		);
		Test.stopTest();

		System.assertEquals(2, resList.size());
		System.assertEquals(true, resList[0].success);
		System.assertEquals(1, resList[0].totalApplications);
		System.assertNotEquals(null, resList[0].pdfUrl);

		System.assertEquals(true, resList[1].success);
		System.assertEquals(0, resList[1].totalApplications);
		System.assertEquals(null, resList[1].pdfUrl);
	}
}
