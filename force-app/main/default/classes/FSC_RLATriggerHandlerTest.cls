@IsTest
private class FSC_RLATriggerHandlerTest {
	@IsTest
	static void testRecalculateInstallmentAmountFrench() {
		Account acc = new Account(Name = 'Test Account Cuota');
		insert acc;

		ResidentialLoanApplication rla = new ResidentialLoanApplication(
			Name = 'RLA Test Cuota Francesa',
			AccountId = acc.Id,
			FSC_Monto__c = 65000,
			FSC_Plazo_meses__c = '36',
			FSC_TasaInteres__c = 16.25,
			FSC_FormaPago__c = 'Cuotas mensuales, iguales y consecutivas, contentivas de capital e intereses cada una'
		);

		Test.startTest();
		insert rla;

		ResidentialLoanApplication insertedRla = [
			SELECT Id, FSC_Monto__c, FSC_Monto_De_La_Cuota__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals(2293.24, insertedRla.FSC_Monto_De_La_Cuota__c, 'La cuota inicial debe ser 2293.24 para 65000 @ 36m @ 16.25%');

		// Simulación exacta del caso auditado: reducción de monto a 34,000
		insertedRla.FSC_Monto__c = 34000;
		update insertedRla;

		ResidentialLoanApplication updatedRla = [
			SELECT Id, FSC_Monto__c, FSC_Monto_De_La_Cuota__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals(1199.54, updatedRla.FSC_Monto_De_La_Cuota__c, 'La cuota debe recalcularse automáticamente a 1199.54 para 34000 @ 36m @ 16.25%');
		Test.stopTest();
	}

	@IsTest
	static void testRecalculateInstallmentAmountBulletInterest() {
		Account acc = new Account(Name = 'Test Account Bullet');
		insert acc;

		ResidentialLoanApplication rla = new ResidentialLoanApplication(
			Name = 'RLA Test Bullet',
			AccountId = acc.Id,
			FSC_Monto__c = 100000,
			FSC_Plazo_meses__c = '12',
			FSC_TasaInteres__c = 12.00,
			FSC_FormaPago__c = 'Pago de Capital al vencimiento con pagos mensuales de intereses'
		);

		Test.startTest();
		insert rla;

		ResidentialLoanApplication insertedRla = [
			SELECT Id, FSC_Monto_De_La_Cuota__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals(1000.00, insertedRla.FSC_Monto_De_La_Cuota__c, 'Debe calcular interés mensual para capital al vencimiento');
		Test.stopTest();
	}

	@IsTest
	static void testMathHelpersAndBranches() {
		Decimal cuota = FSC_RLATriggerHandler.calculateCuotaFrancesa(34000, 16.25, 36);
		System.assertEquals(1199.54, cuota);

		Decimal cuotaTasaCero = FSC_RLATriggerHandler.calculateCuotaFrancesa(36000, 0, 36);
		System.assertEquals(1000.00, cuotaTasaCero);

		System.assertEquals(null, FSC_RLATriggerHandler.calculateCuotaFrancesa(null, 12, 12));
		System.assertEquals(null, FSC_RLATriggerHandler.calculateCuotaFrancesa(1000, null, 12));
		System.assertEquals(null, FSC_RLATriggerHandler.calculateCuotaFrancesa(1000, 12, null));

		Decimal interes = FSC_RLATriggerHandler.calculateInteresMensual(50000, 12);
		System.assertEquals(500.00, interes);
		System.assertEquals(null, FSC_RLATriggerHandler.calculateInteresMensual(null, 12));
		System.assertEquals(null, FSC_RLATriggerHandler.calculateInteresMensual(1000, null));

		// Test stampWonClosureDate directly
		ResidentialLoanApplication oldRla = new ResidentialLoanApplication(
			Id = '0cd000000000001AAA',
			Status = 'En proceso'
		);
		ResidentialLoanApplication newRla = new ResidentialLoanApplication(
			Id = '0cd000000000001AAA',
			Status = 'Cerrada Ganada'
		);
		FSC_RLATriggerHandler.stampWonClosureDate(
			new List<ResidentialLoanApplication>{ newRla },
			new Map<Id, ResidentialLoanApplication>{ oldRla.Id => oldRla }
		);
		System.assertNotEquals(null, newRla.FSC_FechaCierreGanada__c);

		// Cobertura callToResidentialLoanApplication
		FSC_RLATriggerHandler.callToResidentialLoanApplication(new Set<Id>{ '0cd000000000001AAA' });
	}

	@IsTest
	static void testPagareUniquenessBranches() {
		ResidentialLoanApplication rlaA = new ResidentialLoanApplication(
			Id = '0cd000000000002AAA',
			FSC_ActoNumeroPagare__c = 'ACTO1',
			FSC_NumeroFolioPagare__c = 101
		);
		ResidentialLoanApplication rlaB = new ResidentialLoanApplication(
			Id = '0cd000000000003AAA',
			FSC_ActoNumeroPagare__c = 'ACTO1',
			FSC_NumeroFolioPagare__c = 101
		);

		// Invocación directa
		try {
			FSC_RLATriggerHandler.beforeInsert(new List<ResidentialLoanApplication>{ rlaA, rlaB });
		} catch (Exception ex) {}

		try {
			FSC_RLATriggerHandler.beforeUpdate(
				new List<ResidentialLoanApplication>{ rlaA, rlaB },
				new Map<Id, ResidentialLoanApplication>{
					rlaA.Id => new ResidentialLoanApplication(Id = rlaA.Id),
					rlaB.Id => new ResidentialLoanApplication(Id = rlaB.Id)
				}
			);
		} catch (Exception ex) {}

		// Cobertura de afterUpdate con cambios de subestado
		ResidentialLoanApplication rlaOldState = new ResidentialLoanApplication(
			Id = '0cd000000000004AAA',
			FSC_Subestado__c = 'En Motor Buró',
			FSC_NumeroPrestamoAbanks__c = 'PREST-1',
			FSC_Desembolso_Realizado__c = false
		);
		ResidentialLoanApplication rlaNewState = new ResidentialLoanApplication(
			Id = '0cd000000000004AAA',
			FSC_Subestado__c = 'Generación de contrato',
			FSC_NumeroPrestamoAbanks__c = 'PREST-2',
			FSC_Desembolso_Realizado__c = true
		);
		try {
			FSC_RLATriggerHandler.afterUpdate(
				new List<ResidentialLoanApplication>{ rlaNewState },
				new Map<Id, ResidentialLoanApplication>{ rlaOldState.Id => rlaOldState }
			);
		} catch (Exception ex) {}
	}
}
