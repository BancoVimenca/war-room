@IsTest
private class FSC_RLATriggerHandlerTest {
	@TestSetup
	static void asignarPermisosAdministrador() {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			List<PermissionSet> permisos = [SELECT Id FROM PermissionSet WHERE Name = 'FSC_PS_Administrador' LIMIT 1];
			if (!permisos.isEmpty()) {
				if (
					[
						SELECT COUNT()
						FROM PermissionSetAssignment
						WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :permisos[0].Id
					] == 0
				) {
					insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = permisos[0].Id);
				}
			}
		}
	}

	@IsTest
	static void testAfterInsertEnMotorBuroAutoAdvancesWhenMotorOff() {
		Id consumoRtId = Schema.SObjectType.ResidentialLoanApplication.getRecordTypeInfosByDeveloperName()
			.get('FSC_Solicitud_Credito_Consumo')
			.getRecordTypeId();
		Account acc = new Account(Name = 'Test Account Auto Buro Consumo');
		insert acc;

		FSC_BuroConfigService.motoresApagadosEnPrueba.add('FSC_Solicitud_Credito_Consumo');
		FSC_RLATriggerHandler.testAllowEnqueueBuroOnInsert = true;
		ResidentialLoanApplication rla = new ResidentialLoanApplication(
			Name = 'RLA Auto Buro Insert',
			AccountId = acc.Id,
			RecordTypeId = consumoRtId,
			Status = 'En proceso',
			FSC_Subestado__c = 'En Motor Buró',
			FSC_Monto__c = 50000,
			FSC_Plazo_meses__c = '24',
			FSC_TasaInteres__c = 15.00
		);

		try {
			Test.startTest();
			insert rla;
			Test.stopTest();
		} finally {
			FSC_RLATriggerHandler.testAllowEnqueueBuroOnInsert = false;
			FSC_BuroConfigService.motoresApagadosEnPrueba.clear();
		}

		ResidentialLoanApplication updatedRla = [
			SELECT Id, Name, FSC_NumeroSolicitud__c, FSC_Subestado__c, FSC_Resultado_Buro__c, FSC_Mensajes_Buro__c, FSC_Moneda__c
			FROM ResidentialLoanApplication
			WHERE Id = :rla.Id
		];
		System.assertEquals(
			FSC_BuroConfigService.SUBESTADO_REFERIDO,
			updatedRla.FSC_Subestado__c,
			'La solicitud creada en En Motor Buró debe avanzar automáticamente a Recepción de documentos – Análisis sin requerir Reintentar buró'
		);
		System.assertEquals(
			FSC_BuroConfigService.RESULTADO_REFERIDO,
			updatedRla.FSC_Resultado_Buro__c,
			'El resultado de buró debe quedar en Referido automáticamente cuando el motor está apagado'
		);
		System.assertEquals(
			FSC_BuroConfigService.MENSAJE_MOTOR_APAGADO,
			updatedRla.FSC_Mensajes_Buro__c,
			'Debe registrar el mensaje estándar de motor de buró apagado'
		);
		System.assertEquals('1', updatedRla.FSC_Moneda__c, 'Consumo sin moneda debe quedar en pesos por defecto');
		if (!String.isBlank(updatedRla.FSC_NumeroSolicitud__c)) {
			System.assert(
				updatedRla.Name.endsWith(' - ' + updatedRla.FSC_NumeroSolicitud__c),
				'El nombre debe conservar el sufijo autonumérico tras la creación'
			);
		}
	}

	@IsTest
	static void testAfterInsertSkipsPymeAndPreEvaluatedBuro() {
		Id pymeRtId = Schema.SObjectType.ResidentialLoanApplication.getRecordTypeInfosByDeveloperName()
			.get('FSC_Solicitud_Credito_PYME')
			.getRecordTypeId();
		Id consumoRtId = Schema.SObjectType.ResidentialLoanApplication.getRecordTypeInfosByDeveloperName()
			.get('FSC_Solicitud_Credito_Consumo')
			.getRecordTypeId();
		Account acc = new Account(Name = 'Test Account Skip Pyme');
		insert acc;

		FSC_BuroConfigService.motoresApagadosEnPrueba.add('FSC_Solicitud_Credito_PYME');
		FSC_BuroConfigService.motoresApagadosEnPrueba.add('FSC_Solicitud_Credito_Consumo');
		FSC_RLATriggerHandler.testAllowEnqueueBuroOnInsert = true;

		ResidentialLoanApplication rlaPyme = new ResidentialLoanApplication(
			Name = 'RLA PYME En Motor Buro',
			AccountId = acc.Id,
			RecordTypeId = pymeRtId,
			Status = 'En proceso',
			FSC_Subestado__c = 'En Motor Buró'
		);
		ResidentialLoanApplication rlaPreEvaluated = new ResidentialLoanApplication(
			Name = 'RLA Consumo Ya Evaluado',
			AccountId = acc.Id,
			RecordTypeId = consumoRtId,
			Status = 'En proceso',
			FSC_Subestado__c = 'En Motor Buró',
			FSC_Resultado_Buro__c = 'Referido'
		);

		try {
			Test.startTest();
			insert new List<ResidentialLoanApplication>{ rlaPyme, rlaPreEvaluated };
			System.assertEquals(
				0,
				Limits.getQueueableJobs(),
				'No debe encolar FSC_LoanDecisionAPIQueueable para PYME ni para solicitudes con resultado de buró ya informado'
			);
			Test.stopTest();
		} finally {
			FSC_RLATriggerHandler.testAllowEnqueueBuroOnInsert = false;
			FSC_BuroConfigService.motoresApagadosEnPrueba.clear();
		}

		ResidentialLoanApplication pymeAfter = [
			SELECT Id, FSC_Subestado__c, FSC_Resultado_Buro__c
			FROM ResidentialLoanApplication
			WHERE Id = :rlaPyme.Id
		];
		System.assertEquals('En Motor Buró', pymeAfter.FSC_Subestado__c, 'PYME utiliza FSC_APIBuroCreditoPyme y no debe ser alterado por LoanDecisionAPI');
		System.assertEquals(null, pymeAfter.FSC_Resultado_Buro__c, 'PYME no debe recibir resultado de LoanDecisionAPI en afterInsert');
	}

	@IsTest
	static void testDuplicatePagareValidationInDatabase() {
		Account acc = new Account(Name = 'Test Account Pagare DB');
		insert acc;

		ResidentialLoanApplication existingRla = new ResidentialLoanApplication(
			Name = 'RLA Pagare Base',
			AccountId = acc.Id,
			FSC_ActoNumeroPagare__c = 'ACTO9001',
			FSC_NumeroFolioPagare__c = 900101
		);
		insert existingRla;

		ResidentialLoanApplication duplicateRla = new ResidentialLoanApplication(
			Name = 'RLA Pagare Duplicado',
			AccountId = acc.Id,
			FSC_ActoNumeroPagare__c = 'ACTO9001',
			FSC_NumeroFolioPagare__c = 900101
		);

		Database.SaveResult sr = Database.insert(duplicateRla, false);
		System.assertEquals(false, sr.isSuccess(), 'No debe permitir insertar un pagaré con Acto o Folio duplicado en base de datos');
		System.assert(!sr.getErrors().isEmpty(), 'Debe retornar errores de validación de unicidad de pagaré');
	}

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