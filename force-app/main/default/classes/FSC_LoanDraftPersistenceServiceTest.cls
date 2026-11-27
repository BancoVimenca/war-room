@IsTest
private class FSC_LoanDraftPersistenceServiceTest {
	@TestSetup
	static void setupTestData() {
		Account borrower = new Account(
			FirstName = 'Carolina',
			LastName = 'Alvarado',
			RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Candidato_Persona_Fisica').getRecordTypeId(),
			ACC_TipoIdentificacion__c = 'Cédula',
			ACC_NumIdentificacion__c = '00112345678',
			ACC_Nacionalidad__c = 'REPUBLICA DOMINICANA',
			ACC_Posee_Otra_Nacionalidad__c = false
		);
		insert borrower;
	}

	private static Account getBorrower() {
		return [
			SELECT Id, Name, FirstName, LastName, ACC_NumIdentificacion__c
			FROM Account
			WHERE ACC_NumIdentificacion__c = '00112345678'
			LIMIT 1
		];
	}

	private static List<String> activePicklistVals(Schema.SObjectField field) {
		List<String> out = new List<String>();
		for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
			if (entry.isActive()) {
				out.add(entry.getValue());
			}
		}
		return out;
	}

	private static String activePicklistVal(Schema.SObjectField field) {
		List<String> vals = activePicklistVals(field);
		return vals.isEmpty() ? null : vals[0];
	}

	@IsTest
	static void shouldSaveStep1DraftAndOpenApplicationsSummary() {
		Account borrower = getBorrower();
		String estadoCivilVal = activePicklistVal(LoanApplicant.FSC_EstadoCivil__c);
		String tipoViviendaVal = activePicklistVal(LoanApplicant.FSC_TipoVivienda__c);
		String ocupacionVal = activePicklistVal(LoanApplicant.FSC_Ocupacion__c);
		String fuenteIngresoVal = activePicklistVal(LoanApplicant.FSC_FuenteIngreso__c);
		String parentescoVal = activePicklistVal(FSC_Referencias__c.FSC_Parentesco__c);
		String refTipoIdVal = activePicklistVal(FSC_Referencias__c.FSC_TipoIdentificacion__c);
		String extEntidadVal = activePicklistVal(FSC_Facilidad_Otra_Institucion__c.FSC_EntidadFinanciera__c);
		String extTipoFacVal = activePicklistVal(FSC_Facilidad_Otra_Institucion__c.FSC_TipoFacilidad__c);
		String extFacilidadVal = activePicklistVal(FSC_Facilidad_Otra_Institucion__c.FSC_Facilidad__c);
		String extMonedaVal = activePicklistVal(FSC_Facilidad_Otra_Institucion__c.FSC_Moneda__c);

		List<String> tipoSolVals = activePicklistVals(LoanApplicant.FSC_TipoSolicitante__c);
		String deudorRole = tipoSolVals[0];
		String secondRole = tipoSolVals.size() > 1 ? tipoSolVals[1] : tipoSolVals[0];

		List<Map<String, Object>> applicantsPayload = new List<Map<String, Object>>{
			new Map<String, Object>{
				'FSC_TipoSolicitante__c' => deudorRole,
				'FSC_TipoIdentificacion__c' => 'Cédula',
				'FSC_NumIdentificacion__c' => '00112345678',
				'FSC_Nombre__c' => 'Carolina',
				'FSC_PrimerApellido__c' => 'Alvarado',
				'FSC_SegundoApellido__c' => 'Pérez',
				'FSC_FechaNacimiento__c' => '1990-05-15',
				'FSC_Nacionalidad__c' => 'REPUBLICA DOMINICANA',
				'FSC_EstadoCivil__c' => estadoCivilVal,
				'FSC_TipoVivienda__c' => tipoViviendaVal,
				'FSC_TiempoVivienda__c' => '2020-01-10',
				'FSC_Ocupacion__c' => ocupacionVal,
				'FSC_LugarFondeLabora__c' => 'Empresa Dominicana SRL',
				'FSC_TiempoLaborando__c' => '2019-03-01',
				'FSC_FuenteIngreso__c' => fuenteIngresoVal,
				'FSC_IngresosMensuales__c' => 145000,
				'FSC_MonedaSalario__c' => 'DOP',
				'FSC_SalarioOriginal__c' => 145000,
				'FSC_OtrosIngresos__c' => 15000,
				'FSC_OtrosIngresosOriginal__c' => 15000,
				'FSC_DescripcionOtrosIngresos__c' => 'Alquiler',
				'FSC_MontoPrestacionesLaborales__c' => '320000',
				'FSC_NumeroDependientes__c' => 2,
				'FSC_Referencias__c' => new List<Map<String, Object>>{
					new Map<String, Object>{
						'FSC_FirstName__c' => 'Juan',
						'FSC_LastName__c' => 'Gómez',
						'FSC_TipoIdentificacion__c' => refTipoIdVal,
						'FSC_Identificacion__c' => '00199887766',
						'FSC_Telefono__c' => '8095551111',
						'FSC_Parentesco__c' => parentescoVal
					},
					new Map<String, Object>{
						'FSC_FirstName__c' => 'María',
						'FSC_LastName__c' => 'Santos',
						'FSC_Telefono__c' => '8095552222',
						'FSC_Parentesco__c' => parentescoVal
					}
				},
				'FSC_Facilidad_Otra_Institucion__c' => new List<Map<String, Object>>{
					new Map<String, Object>{
						'FSC_EntidadFinanciera__c' => extEntidadVal,
						'FSC_TipoFacilidad__c' => extTipoFacVal,
						'FSC_Facilidad__c' => extFacilidadVal,
						'FSC_DescripcionFacilidad__c' => 'Préstamo personal',
						'FSC_Balance__c' => 85000,
						'FSC_Moneda__c' => extMonedaVal
					}
				}
			},
			new Map<String, Object>{
				'FSC_TipoSolicitante__c' => secondRole,
				'FSC_TipoIdentificacion__c' => 'Cédula',
				'FSC_NumIdentificacion__c' => '00187654321',
				'FSC_Nombre__c' => 'Luis',
				'FSC_PrimerApellido__c' => 'Martínez',
				'FSC_FechaNacimiento__c' => '1988-08-20',
				'FSC_Nacionalidad__c' => 'REPUBLICA DOMINICANA',
				'FSC_Ocupacion__c' => ocupacionVal,
				'FSC_LugarFondeLabora__c' => 'Consultora Fiscal',
				'FSC_TiempoLaborando__c' => '2021-01-15',
				'FSC_FuenteIngreso__c' => fuenteIngresoVal,
				'FSC_IngresosMensuales__c' => 95000
			}
		};

		Test.startTest();
		Map<String, Object> step1Saved = FSC_LoanDraftPersistenceService.saveStep1Draft(
			borrower.Id,
			null,
			'Hipotecario',
			JSON.serialize(applicantsPayload)
		);
		Id rlaId = (Id) step1Saved.get('rlaId');
		Assert.isNotNull(rlaId, 'Debe crear la solicitud en Borrador desde el paso 1.');

		List<Map<String, Object>> updatedApplicants = (List<Map<String, Object>>) step1Saved.get('applicants');
		Assert.areEqual(2, updatedApplicants.size(), 'Deben persistirse ambos solicitantes inicialmente.');

		// Re-guardar quitando el codeudor para verificar actualización sin duplicados y limpieza de removidos
		List<Map<String, Object>> onlyDebtor = new List<Map<String, Object>>{ updatedApplicants[0] };
		Map<String, Object> secondSave = FSC_LoanDraftPersistenceService.saveStep1Draft(
			borrower.Id,
			rlaId,
			'Hipotecario',
			JSON.serialize(onlyDebtor)
		);

		List<FSC_LoanDraftPersistenceService.OpenApplicationSummaryDTO> openList = FSC_LoanDraftPersistenceService.getOpenApplicationsForAccount(
			borrower.Id,
			'Hipotecario'
		);
		Test.stopTest();

		Assert.areEqual(rlaId, (Id) secondSave.get('rlaId'), 'Debe reutilizar el mismo Id de borrador.');
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM LoanApplicant WHERE LoanApplicationId = :rlaId],
			'Debe mantener únicamente al deudor y eliminar el codeudor retirado.'
		);
		Assert.areEqual(
			2,
			[SELECT COUNT() FROM FSC_Referencias__c WHERE FSC_Residential_Loan_Application__c = :rlaId],
			'No debe duplicar las referencias en guardados sucesivos.'
		);
		Assert.areEqual(1, openList.size(), 'Debe listar la solicitud abierta para el Selector de Continuidad.');
		Assert.isTrue(openList[0].isDraft, 'Debe identificar el estado Borrador.');
		Assert.areEqual(0, FSC_LoanDraftPersistenceService.getOpenApplicationsForAccount(null, 'Hipotecario').size());
		Assert.areEqual(0, FSC_LoanDraftPersistenceService.getOpenApplicationsForAccount(borrower.Id, '').size());
	}

	@IsTest
	static void shouldSaveFacilityDraftRehydrateSnapshotAndDeduplicateOnSubmit() {
		Account borrower = getBorrower();
		String purpose = FSC_ReglaCredito__mdt.getInstance('HipCompraDOP').FSC_Proposito__c;
		String formaPagoVal = activePicklistVal(ResidentialLoanApplication.FSC_FormaPago__c);
		String seguroVidaVal = activePicklistVal(FSC_Seguro__c.FSC_Tipo_de_Seguro__c);

		Map<String, Object> stepGeneral = new Map<String, Object>{
			'FSC_SolicitudMedianteReferidor__c' => 'true',
			'FSC_Referidor__c' => 'Agente Inmobiliario Norte',
			'FSC_EsRefinanciamiento__c' => 'false',
			'FSC_EsConsolidacionDeudas__c' => 'false'
		};

		Map<String, Object> partialFacility = new Map<String, Object>{
			'FSC_Tipo_Facilidad__c' => 'CONTROL DE PRESTAMOS - BPR',
			'FSC_Facilidad__c' => 'HIPOTECARIOS PARA LA VIVIENDA - 402',
			'FSC_Prestamo_Con_Garantia__c' => true,
			'FSC_Requiere_Contrato_Pagare_Notarial__c' => true,
			'FSC_Descripcion_Proposito_Facilidad__c' => 'Compra de apartamento familiar en Piantini',
			'FSC_Moneda__c' => '1',
			'FSC_Garantias__r' => new List<Map<String, Object>>{
				new Map<String, Object>{
					'__key' => 'garantia-1',
					'FSC_MonedaGarantia__c' => 'DOP',
					'FSC_Clase_de_Garantia__c' => 'BIENES INMUEBLES',
					'FSC_Tipo_de_Garantia__c' => activePicklistVal(FSC_Garantia__c.FSC_Tipo_de_Garantia__c),
					'FSC_Proposito_Garantia_Hipotecario__c' => purpose,
					'FSC_Valor_Tasado__c' => 9500000,
					'FSC_Valor_Inmueble__c' => 9500000,
					'FSC_Precio_de_Venta__c' => 9200000,
					'FSC_Monto_Inicial_Avance_Pagado__c' => 1840000,
					'FSC_Metros_Cuadrados_de_Construccion__c' => 145,
					'FSC_EsTasadorExterno__c' => true,
					'FSC_NombreTasadorExterno__c' => 'Tasaciones Caribe SRL',
					'FSC_Fecha_Tasacion__c' => String.valueOf(Date.today().addDays(-5)),
					'FSC_Ubicacion__c' => 'Ensanche Piantini, Santo Domingo',
					'FSC_Tipo_de_Inmueble__c' => 'Vivienda'
				}
			},
			'FSC_Seguros__r' => new List<Map<String, Object>>()
		};

		Test.startTest();
		// Guardado parcial en Borrador (aún sin monto ni plazo): no debe ser bloqueado por FSC_CreditPolicyGuard
		Map<String, Object> firstFacilitySave = FSC_LoanDraftPersistenceService.saveFacilityDraft(
			null,
			borrower.Id,
			'Hipotecario',
			JSON.serialize(stepGeneral),
			JSON.serialize(partialFacility)
		);
		Id rlaId = (Id) firstFacilitySave.get('rlaId');
		Map<String, Id> guaranteeIds = (Map<String, Id>) firstFacilitySave.get('guaranteeIdsByKey');
		Id savedGuaranteeId = guaranteeIds.get('garantia-1');
		Assert.isNotNull(savedGuaranteeId, 'Debe devolver el Id real de la garantía guardada en Borrador.');

		// Completar condiciones financieras y seguros usando el Id real para verificar UPSERT cero duplicados
		partialFacility.put('FSC_Monto_Solicitado__c', 7000000);
		partialFacility.put('FSC_Plazo_meses__c', 240);
		partialFacility.put('FSC_Tasa_Interes__c', 11.5);
		partialFacility.put('FSC_Tasa_Fija__c', true);
		partialFacility.put('FSC_Tiempo_Tasa_Fija__c', 60);
		partialFacility.put('FSC_Forma_De_Pago__c', formaPagoVal);
		partialFacility.put('FSC_Monto_De_La_Cuota__c', 74637.50);

		List<Map<String, Object>> gList = (List<Map<String, Object>>) partialFacility.get('FSC_Garantias__r');
		gList[0].put('Id', savedGuaranteeId);
		partialFacility.put(
			'FSC_Seguros__r',
			new List<Map<String, Object>>{
				new Map<String, Object>{
					'__key' => 'seguro-1',
					'FSC_Tipo_de_Seguro__c' => seguroVidaVal,
					'FSC_Monto_de_la_Prima__c' => 2450.00,
					'FSC_Seguro_Desempleo__c' => false
				}
			}
		);

		Map<String, Object> secondFacilitySave = FSC_LoanDraftPersistenceService.saveFacilityDraft(
			rlaId,
			null,
			'Hipotecario',
			JSON.serialize(stepGeneral),
			JSON.serialize(partialFacility)
		);
		Assert.areEqual(false, secondFacilitySave.get('skippedNonDraft'));
		Assert.areEqual(1, [SELECT COUNT() FROM FSC_Garantia__c WHERE FSC_Residential_Loan_Application__c = :rlaId], 'UPSERT por Id no debe duplicar el inmueble.');
		Assert.areEqual(1, [SELECT COUNT() FROM FSC_Seguro__c WHERE FSC_Residential_Loan_Application__c = :rlaId], 'Debe existir el seguro guardado.');

		// Rehidratación completa del snapshot (por Id y por cuenta/tipo) y resumen con garantía
		Map<String, Object> snapshotById = FSC_LoanDraftPersistenceService.getDraftSnapshot(rlaId, borrower.Id, 'Hipotecario');
		Map<String, Object> snapshotByAccount = FSC_LoanDraftPersistenceService.getDraftSnapshot(null, borrower.Id, 'Hipotecario');
		List<FSC_LoanDraftPersistenceService.OpenApplicationSummaryDTO> summaries = FSC_LoanDraftPersistenceService.getOpenApplicationsForAccount(
			borrower.Id,
			'Hipotecario'
		);
		Assert.areEqual(true, snapshotById.get('found'));
		Assert.areEqual(rlaId, snapshotByAccount.get('rlaId'));
		Assert.isTrue(String.isNotBlank(summaries[0].garantiaResumen), 'El selector debe mostrar el resumen del inmueble capturado.');

		// Agregar solicitante con referencias duplicadas simuladas para cubrir deduplicación integral en submit
		FSC_LoanDraftPersistenceService.saveStep1Draft(
			borrower.Id,
			rlaId,
			'Hipotecario',
			JSON.serialize(
				new List<Map<String, Object>>{
					new Map<String, Object>{
						'FSC_TipoSolicitante__c' => 'Deudor',
						'FSC_TipoIdentificacion__c' => 'Cédula',
						'FSC_NumIdentificacion__c' => '00112345678',
						'FSC_Nombre__c' => 'Carolina',
						'FSC_PrimerApellido__c' => 'Alvarado',
						'FSC_Referencias__c' => new List<Map<String, Object>>{
							new Map<String, Object>{
								'FSC_FirstName__c' => 'Pedro',
								'FSC_LastName__c' => 'Ruiz',
								'FSC_Telefono__c' => '8095559999',
								'FSC_Parentesco__c' => activePicklistVal(FSC_Referencias__c.FSC_Parentesco__c)
							}
						}
					}
				}
			)
		);
		Id applicantId = [SELECT Id FROM LoanApplicant WHERE LoanApplicationId = :rlaId LIMIT 1].Id;
		insert new FSC_Referencias__c(
			Name = 'Pedro Ruiz',
			FSC_LoanApplicant__c = applicantId,
			FSC_Residential_Loan_Application__c = rlaId,
			FSC_FirstName__c = 'Pedro',
			FSC_LastName__c = 'Ruiz',
			FSC_Telefono__c = '8095559999',
			FSC_Parentesco__c = activePicklistVal(FSC_Referencias__c.FSC_Parentesco__c)
		);

		// Simular envío final del OmniScript (transición Borrador -> En proceso + post-inserción de DataRaptors sin Id)
		update new ResidentialLoanApplication(
			Id = rlaId,
			Status = 'En proceso',
			FSC_Subestado__c = 'En Motor Buró'
		);

		// Verificar que saveFacilityDraft no sobreescribe una solicitud ya enviada a En proceso
		Map<String, Object> postSubmitSave = FSC_LoanDraftPersistenceService.saveFacilityDraft(
			rlaId,
			borrower.Id,
			'Hipotecario',
			'{}',
			'{}'
		);
		Assert.areEqual(true, postSubmitSave.get('skippedNonDraft'));

		insert new FSC_Garantia__c(
			Name = 'Garantia Post Submit',
			FSC_Residential_Loan_Application__c = rlaId,
			FSC_MonedaGarantia__c = 'DOP',
			FSC_Clase_de_Garantia__c = 'BIENES INMUEBLES',
			FSC_Tipo_de_Garantia__c = activePicklistVal(FSC_Garantia__c.FSC_Tipo_de_Garantia__c),
			FSC_Proposito_Garantia_Hipotecario__c = purpose,
			FSC_Valor_Tasado__c = 9500000,
			FSC_Valor_Inmueble__c = 9500000,
			FSC_Precio_de_Venta__c = 9200000,
			FSC_Ubicacion__c = 'Ensanche Piantini, Santo Domingo',
			FSC_Tipo_de_Inmueble__c = 'Vivienda'
		);
		insert new FSC_Seguro__c(
			Name = seguroVidaVal,
			FSC_Residential_Loan_Application__c = rlaId,
			FSC_Tipo_de_Seguro__c = seguroVidaVal,
			FSC_Monto_de_la_Prima__c = 2450.00
		);
		Test.stopTest();

		Assert.areEqual(
			1,
			[SELECT COUNT() FROM FSC_Garantia__c WHERE FSC_Residential_Loan_Application__c = :rlaId],
			'Tras el envío final del OmniScript debe quedar exactamente 1 garantía sin duplicados.'
		);
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM FSC_Seguro__c WHERE FSC_Residential_Loan_Application__c = :rlaId],
			'Tras el envío final del OmniScript debe quedar exactamente 1 seguro por tipo sin duplicados.'
		);
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM FSC_Referencias__c WHERE FSC_LoanApplicant__c = :applicantId],
			'Las referencias idénticas deben deduplicarse al promover a En proceso.'
		);
	}

	@IsTest
	static void shouldDiscardDraftCoverVehiclePymeAndValidationErrors() {
		Account borrower = getBorrower();
		Map<String, Object> created = FSC_LoanDraftPersistenceService.saveStep1Draft(borrower.Id, null, 'Vehiculo', '[]');
		Id rlaId = (Id) created.get('rlaId');

		// Cubrir resoluciones de tipos de crédito y snapshot sin coincidencias
		Map<String, Object> snapVeh = FSC_LoanDraftPersistenceService.getDraftSnapshot(rlaId, borrower.Id, 'Vehiculo');
		Assert.areEqual(true, snapVeh.get('found'));
		Assert.areEqual('FSC_Solicitud_Credito_PYME', FSC_LoanDraftPersistenceService.resolveRecordTypeDeveloperName('PYME'));
		Assert.areEqual('FSC_Solicitud_Credito_Comercial', FSC_LoanDraftPersistenceService.resolveRecordTypeDeveloperName('Comercial'));
		Assert.areEqual('FSC_Solicitud_Credito_Consumo', FSC_LoanDraftPersistenceService.resolveRecordTypeDeveloperName('Consumo'));
		Assert.areEqual(false, FSC_LoanDraftPersistenceService.getDraftSnapshot(null, null, 'Consumo').get('found'));

		// Guardar y eliminar garantía/seguro en borrador vehicular
		Map<String, Object> vehSave = FSC_LoanDraftPersistenceService.saveFacilityDraft(
			rlaId,
			borrower.Id,
			'Vehiculo',
			'{}',
			JSON.serialize(
				new Map<String, Object>{
					'FSC_Tipo_Facilidad__c' => 'CONTROL DE PRESTAMOS - BPR',
					'FSC_Garantias__r' => new List<Map<String, Object>>{
						new Map<String, Object>{
							'__key' => 'veh-1',
							'FSC_Clase_de_Garantia__c' => activePicklistVal(FSC_Garantia__c.FSC_Clase_de_Garantia__c),
							'FSC_Marca_Vehiculo__c' => activePicklistVal(FSC_Garantia__c.FSC_Marca_Vehiculo__c),
							'FSC_Ano_Vehiculo__c' => 2024,
							'FSC_Valor_Vehiculo__c' => 1500000
						}
					},
					'FSC_Seguros__r' => new List<Map<String, Object>>{
						new Map<String, Object>{
							'__key' => 'seg-v1',
							'FSC_Tipo_de_Seguro__c' => activePicklistVal(FSC_Seguro__c.FSC_Tipo_de_Seguro__c),
							'FSC_Monto_de_la_Prima__c' => 1200
						}
					}
				}
			)
		);
		Assert.areEqual(1, ((Map<String, Id>) vehSave.get('guaranteeIdsByKey')).size());
		Map<String, Object> snapWithVeh = FSC_LoanDraftPersistenceService.getDraftSnapshot(rlaId, borrower.Id, 'Vehiculo');
		Assert.isNotNull(snapWithVeh.get('facility'));

		// Limpiar garantías y seguros enviando listas vacías
		FSC_LoanDraftPersistenceService.saveFacilityDraft(
			rlaId,
			borrower.Id,
			'Vehiculo',
			'{}',
			JSON.serialize(
				new Map<String, Object>{
					'FSC_Tipo_Facilidad__c' => 'CONTROL DE PRESTAMOS - BPR',
					'FSC_Garantias__r' => new List<Object>(),
					'FSC_Seguros__r' => new List<Object>()
				}
			)
		);
		Assert.areEqual(0, [SELECT COUNT() FROM FSC_Garantia__c WHERE FSC_Residential_Loan_Application__c = :rlaId]);
		Assert.areEqual(0, [SELECT COUNT() FROM FSC_Seguro__c WHERE FSC_Residential_Loan_Application__c = :rlaId]);

		Test.startTest();
		FSC_LoanDraftPersistenceService.discardDraftApplication(rlaId);
		ResidentialLoanApplication closed = [
			SELECT Status, FSC_Subestado__c
			FROM ResidentialLoanApplication
			WHERE Id = :rlaId
		];
		Assert.areEqual('Cerrada Perdida', closed.Status);
		Assert.areEqual('Rechazada por cliente', closed.FSC_Subestado__c);

		Boolean rejectedSecondDiscard = false;
		try {
			FSC_LoanDraftPersistenceService.discardDraftApplication(rlaId);
		} catch (AuraHandledException expected) {
			rejectedSecondDiscard = true;
		}
		Boolean rejectedNullDiscard = false;
		try {
			FSC_LoanDraftPersistenceService.discardDraftApplication(null);
		} catch (AuraHandledException expected) {
			rejectedNullDiscard = true;
		}
		Boolean rejectedInvalidType = false;
		try {
			FSC_LoanDraftPersistenceService.saveStep1Draft(borrower.Id, null, 'Inexistente', '[]');
		} catch (AuraHandledException expected) {
			rejectedInvalidType = true;
		}
		Test.stopTest();

		Assert.isTrue(rejectedSecondDiscard, 'No debe permitir descartar solicitudes que ya no están en estado Borrador.');
		Assert.isTrue(rejectedNullDiscard, 'Debe validar rlaId nulo.');
		Assert.isTrue(rejectedInvalidType, 'Debe validar tipo de crédito desconocido.');
	}
}
