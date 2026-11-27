public with sharing class FSC_RLATriggerHandler {
	private static final String ACTO_NUMERO_PAGARE_FIELD = 'FSC_ActoNumeroPagare__c';
	private static final String NUMERO_FOLIO_PAGARE_FIELD = 'FSC_NumeroFolioPagare__c';
	private static final String SUBESTADO_PENDIENTE_PLANILLA_DESEMBOLSO = 'Pendiente planilla de desembolso';
	private static final String STATUS_CERRADA_GANADA = 'Cerrada Ganada';
	private static final Id PYME_RECORD_TYPE_ID = Schema.SObjectType.ResidentialLoanApplication.getRecordTypeInfosByDeveloperName()
		.get('FSC_Solicitud_Credito_PYME')
		.getRecordTypeId();
	private static final Id HIPOTECARIO_RECORD_TYPE_ID = Schema.SObjectType.ResidentialLoanApplication.getRecordTypeInfosByDeveloperName()
		.get('FSC_Solicitud_Credito_Hipotecario')
		.getRecordTypeId();
	private static final Id VEHICULO_RECORD_TYPE_ID = Schema.SObjectType.ResidentialLoanApplication.getRecordTypeInfosByDeveloperName()
		.get('FSC_Solicitud_Credito_Vehiculo')
		.getRecordTypeId();
	private static final Id CONSUMO_RECORD_TYPE_ID = Schema.SObjectType.ResidentialLoanApplication.getRecordTypeInfosByDeveloperName()
		.get('FSC_Solicitud_Credito_Consumo')
		.getRecordTypeId();
	private static final String MONEDA_PESOS = '1';
	private static Map<Id, String> pendingCreationNames = new Map<Id, String>();

	private static Boolean isSettingRequestNumber = false;
	@TestVisible
	private static Boolean testAllowEnqueueBuroOnInsert = false;

	public static void afterInsert(List<ResidentialLoanApplication> newRLA) {
		if (newRLA == null || newRLA.isEmpty()) {
			return;
		}
		List<ResidentialLoanApplication> recordsToUpdate = new List<ResidentialLoanApplication>();
		Set<Id> residentialLoanApplicationIds = new Set<Id>();
		Integer nameLength = ResidentialLoanApplication.Name.getDescribe().getLength();
		for (ResidentialLoanApplication rla : newRLA) {
			if (rla == null) {
				continue;
			}
			if (
				rla.FSC_Subestado__c == 'En Motor Buró' &&
				String.isBlank(rla.FSC_Resultado_Buro__c) &&
				rla.RecordTypeId != PYME_RECORD_TYPE_ID
			) {
				// PYME consulta Buró únicamente mediante FSC_APIBuroCreditoPyme.
				residentialLoanApplicationIds.add(rla.Id);
			}
			if (String.isBlank(rla.Name) || String.isBlank(rla.FSC_NumeroSolicitud__c)) {
				continue;
			}
			String suffix = ' - ' + rla.FSC_NumeroSolicitud__c;
			if (!rla.Name.endsWith(suffix)) {
				pendingCreationNames.put(rla.Id, rla.Name.left(nameLength - suffix.length()) + suffix);
				recordsToUpdate.add(new ResidentialLoanApplication(Id = rla.Id));
			}
		}
		if (!recordsToUpdate.isEmpty()) {
			isSettingRequestNumber = true;
			try {
				// El autonumérico existe después del insert. El update llega sin cambios de Name
				// al Flow de bloqueo; el before update completa únicamente estos nombres de creación.
				update as user recordsToUpdate;
			} finally {
				isSettingRequestNumber = false;
				for (ResidentialLoanApplication rla : recordsToUpdate) {
					pendingCreationNames.remove(rla.Id);
				}
			}
		}
		if (!residentialLoanApplicationIds.isEmpty() && (!Test.isRunningTest() || testAllowEnqueueBuroOnInsert)) {
			callToResidentialLoanApplication(residentialLoanApplicationIds);
		}
	}

	public static void beforeInsert(List<ResidentialLoanApplication> newRLA) {
		assignDefaultCurrency(newRLA);
		recalculateInstallmentAmount(newRLA, null);
		FSC_CreditPolicyGuard.validateApplications(newRLA, null);
		FSC_CapturaOperacionesService.asignarResponsables(newRLA);
		FSC_DeudaConsolidadaBVService.asignarEnSolicitudes(newRLA);
		validateUniquePagareFields(newRLA, null);
	}

	// Hipotecario, Vehículo y Consumo quedan en pesos si la creación no informa moneda; se conserva cualquier moneda recibida.
	@TestVisible
	private static void assignDefaultCurrency(List<ResidentialLoanApplication> newRLA) {
		for (ResidentialLoanApplication rla : newRLA) {
			if (
				(rla.RecordTypeId == HIPOTECARIO_RECORD_TYPE_ID ||
				 rla.RecordTypeId == VEHICULO_RECORD_TYPE_ID ||
				 rla.RecordTypeId == CONSUMO_RECORD_TYPE_ID) &&
				String.isBlank(rla.FSC_Moneda__c)
			) {
				rla.FSC_Moneda__c = MONEDA_PESOS;
			}
		}
	}

	public static void beforeUpdate(List<ResidentialLoanApplication> newRLA, Map<Id, ResidentialLoanApplication> oldRLA) {
		recalculateInstallmentAmount(newRLA, oldRLA);
		FSC_InstanciasCreditoService.completarAprobacion(newRLA, oldRLA);
		for (ResidentialLoanApplication rla : newRLA) {
			if (pendingCreationNames.containsKey(rla.Id)) {
				rla.Name = pendingCreationNames.remove(rla.Id);
			}
		}
		stampWonClosureDate(newRLA, oldRLA);
		FSC_CreditPolicyGuard.validateApplications(newRLA, oldRLA);
		FSC_FormalizacionGarantiasService.encaminar(newRLA, oldRLA);
		FSC_CapturaOperacionesService.asignarResponsables(newRLA);
		FSC_DocumentacionContratosService.encaminarEntradas(newRLA, oldRLA);
		FSC_CreditoAprobadoLockService.validarCamposCriticosSolicitud(newRLA, oldRLA);
		FSC_GarantiaFormalizacionService.validarCierre(newRLA, oldRLA);
		validateUniquePagareFields(newRLA, oldRLA);
	}

	@TestVisible
	private static void stampWonClosureDate(List<ResidentialLoanApplication> newRLA, Map<Id, ResidentialLoanApplication> oldRLA) {
		if (newRLA == null || newRLA.isEmpty() || oldRLA == null || oldRLA.isEmpty()) {
			return;
		}

		Datetime closureDate = System.now();
		for (ResidentialLoanApplication rla : newRLA) {
			ResidentialLoanApplication oldRecord = rla == null ? null : oldRLA.get(rla.Id);
			if (
				oldRecord != null &&
				oldRecord.Status != STATUS_CERRADA_GANADA &&
				rla.Status == STATUS_CERRADA_GANADA &&
				rla.FSC_FechaCierreGanada__c == null
			) {
				rla.FSC_FechaCierreGanada__c = closureDate;
			}
		}
	}

	public static void afterUpdate(List<ResidentialLoanApplication> newRLA, Map<Id, ResidentialLoanApplication> oldRLA) {
		FSC_LoanDraftPersistenceService.reconcileSubmittedDraftChildren(newRLA, oldRLA);
		FSC_CapturaOperacionesService.compartirSolicitudes(newRLA, oldRLA);
		FSC_FormalizacionGarantiasService.compartir(newRLA, oldRLA);
		FSC_FormalizacionNotificaciones.programar(newRLA, oldRLA);
		FSC_ServicioDocumentosAnalisisCredito.programarSegunCambioAnalisis(newRLA, oldRLA);

		Set<Id> contractGenerationIds = new Set<Id>();
		Set<Id> residentialLoanApplicationIds = new Set<Id>();
		Set<Id> solicitudCreditoRegenerationIds = new Set<Id>();
		Set<Id> planillaDesembolsoCompletedIds = new Set<Id>();
		Set<Id> gestionarFirmasIds = new Set<Id>();
		Set<Id> pagareComplementarioRegenerationIds = new Set<Id>();

		for (ResidentialLoanApplication rla : newRLA) {
			ResidentialLoanApplication oldRecord = oldRLA.get(rla.Id);
			if (oldRecord == null) {
				continue;
			}

			if (oldRecord.FSC_Subestado__c != rla.FSC_Subestado__c) {
				if (rla.FSC_Subestado__c == 'Generación de contrato') {
					contractGenerationIds.add(rla.Id);
				} else if (rla.FSC_Subestado__c == 'En Motor Buró' && rla.RecordTypeId != PYME_RECORD_TYPE_ID) {
					// PYME consulta Buró únicamente mediante FSC_APIBuroCreditoPyme.
					residentialLoanApplicationIds.add(rla.Id);
				} else if (rla.FSC_Subestado__c == 'Gestionar firmas') {
					gestionarFirmasIds.add(rla.Id);
				}
			}

			if (!isSettingRequestNumber && FSC_RegenerarSolicitudCreditoService.shouldRegenerateSolicitudCredito(rla, oldRecord)) {
				solicitudCreditoRegenerationIds.add(rla.Id);
			}

			// Se regenera al informar o corregir el número de préstamo.
			if (oldRecord.FSC_NumeroPrestamoAbanks__c != rla.FSC_NumeroPrestamoAbanks__c && !String.isBlank(rla.FSC_NumeroPrestamoAbanks__c)) {
				pagareComplementarioRegenerationIds.add(rla.Id);
			}

			if (
				oldRecord.FSC_Desembolso_Realizado__c != true &&
				rla.FSC_Desembolso_Realizado__c == true &&
				oldRecord.FSC_Subestado__c == SUBESTADO_PENDIENTE_PLANILLA_DESEMBOLSO
			) {
				planillaDesembolsoCompletedIds.add(rla.Id);
			}
		}

		if (!contractGenerationIds.isEmpty()) {
			generacionContrato(contractGenerationIds);
		}

		if (!residentialLoanApplicationIds.isEmpty()) {
			callToResidentialLoanApplication(residentialLoanApplicationIds);
		}

		if (!solicitudCreditoRegenerationIds.isEmpty()) {
			FSC_RegenerarSolicitudCreditoService.enqueueRegeneration(solicitudCreditoRegenerationIds);
		}

		if (!planillaDesembolsoCompletedIds.isEmpty()) {
			System.enqueueJob(new FSC_AutoApproveGestionPlanillasQueueable(planillaDesembolsoCompletedIds));
		}

		if (!gestionarFirmasIds.isEmpty()) {
			FSC_ConfiguracionFirmaDocumentosService.marcarFirmasFisicasCompletasSiNoAplican(gestionarFirmasIds);
		}

		if (!pagareComplementarioRegenerationIds.isEmpty()) {
			FSC_RegenerarPagareComplementarioQbl.enqueueIfExists(pagareComplementarioRegenerationIds);
		}
	}

	public static void generacionContrato(Set<Id> residentialLoanApplicationIds) {
		FSC_GenerarContratoPDF.enqueueGeneration(residentialLoanApplicationIds);
	}

	public static void desembolsoDeCredito(ResidentialLoanApplication rla) {
		FSC_DesembolsoDeCredito.desembolso(rla);
	}

	public static void callToResidentialLoanApplication(Set<Id> residentialLoanApplicationIds) {
		System.enqueueJob(new FSC_LoanDecisionAPIQueueable(new List<Id>(residentialLoanApplicationIds)));
	}

	private static void validateUniquePagareFields(List<ResidentialLoanApplication> newRLA, Map<Id, ResidentialLoanApplication> oldRLA) {
		if (newRLA == null || newRLA.isEmpty()) {
			return;
		}

		Set<Id> currentRecordIds = new Set<Id>();
		Set<String> actoNumeroValues = new Set<String>();
		Set<String> numeroFolioValues = new Set<String>();

		Map<String, List<ResidentialLoanApplication>> recordsByActoNumero = new Map<String, List<ResidentialLoanApplication>>();
		Map<String, List<ResidentialLoanApplication>> recordsByNumeroFolio = new Map<String, List<ResidentialLoanApplication>>();
		Map<String, List<ResidentialLoanApplication>> allRecordsByActoNumero = new Map<String, List<ResidentialLoanApplication>>();
		Map<String, List<ResidentialLoanApplication>> allRecordsByNumeroFolio = new Map<String, List<ResidentialLoanApplication>>();

		for (ResidentialLoanApplication rla : newRLA) {
			if (rla == null) {
				continue;
			}

			if (rla.Id != null) {
				currentRecordIds.add(rla.Id);
			}

			ResidentialLoanApplication oldRecord = oldRLA == null ? null : oldRLA.get(rla.Id);

			String actoNumero = normalizeUniqueValue(rla.get(ACTO_NUMERO_PAGARE_FIELD));
			if (!String.isBlank(actoNumero)) {
				addRecordByValue(allRecordsByActoNumero, actoNumero, rla);
			}
			String oldActoNumero = oldRecord == null ? null : normalizeUniqueValue(oldRecord.get(ACTO_NUMERO_PAGARE_FIELD));
			if (shouldValidateUniqueValue(actoNumero, oldActoNumero)) {
				actoNumeroValues.add(actoNumero);
				addRecordByValue(recordsByActoNumero, actoNumero, rla);
			}

			String numeroFolio = normalizeUniqueValue(rla.get(NUMERO_FOLIO_PAGARE_FIELD));
			if (!String.isBlank(numeroFolio)) {
				addRecordByValue(allRecordsByNumeroFolio, numeroFolio, rla);
			}
			String oldNumeroFolio = oldRecord == null ? null : normalizeUniqueValue(oldRecord.get(NUMERO_FOLIO_PAGARE_FIELD));
			if (shouldValidateUniqueValue(numeroFolio, oldNumeroFolio)) {
				numeroFolioValues.add(numeroFolio);
				addRecordByValue(recordsByNumeroFolio, numeroFolio, rla);
			}
		}

		if (recordsByActoNumero.isEmpty() && recordsByNumeroFolio.isEmpty()) {
			return;
		}

		Map<String, Id> existingByActoNumero = getExistingRecordsByActoNumero(actoNumeroValues, currentRecordIds);
		Map<String, Id> existingByNumeroFolio = getExistingRecordsByNumeroFolio(numeroFolioValues, currentRecordIds);

		addDuplicateErrors(recordsByActoNumero, allRecordsByActoNumero, existingByActoNumero, 'El Acto número pagaré ya existe en otra solicitud.');
		addDuplicateErrors(recordsByNumeroFolio, allRecordsByNumeroFolio, existingByNumeroFolio, 'El Número de folio ya existe en otra solicitud.');
	}

	private static void addRecordByValue(Map<String, List<ResidentialLoanApplication>> recordsByValue, String value, ResidentialLoanApplication rla) {
		if (String.isBlank(value) || rla == null) {
			return;
		}

		if (!recordsByValue.containsKey(value)) {
			recordsByValue.put(value, new List<ResidentialLoanApplication>());
		}

		recordsByValue.get(value).add(rla);
	}

	private static Boolean shouldValidateUniqueValue(String newValue, String oldValue) {
		return !String.isBlank(newValue) && newValue != oldValue;
	}

	private static String normalizeUniqueValue(Object value) {
		if (value == null) {
			return null;
		}

		String normalized = String.valueOf(value).trim();
		return String.isBlank(normalized) ? null : normalized;
	}

	private static void addDuplicateErrors(
		Map<String, List<ResidentialLoanApplication>> recordsByValue,
		Map<String, List<ResidentialLoanApplication>> allRecordsByValue,
		Map<String, Id> existingByValue,
		String errorMessage
	) {
		for (String value : recordsByValue.keySet()) {
			List<ResidentialLoanApplication> records = recordsByValue.get(value);
			List<ResidentialLoanApplication> allRecords = allRecordsByValue.get(value);
			Boolean existsInCurrentTransaction = allRecords != null && allRecords.size() > 1;
			Boolean existsInDatabase = existingByValue.containsKey(value);

			if (!existsInCurrentTransaction && !existsInDatabase) {
				continue;
			}

			for (ResidentialLoanApplication rla : records) {
				rla.addError(errorMessage);
			}
		}
	}

	private static Map<String, Id> getExistingRecordsByActoNumero(Set<String> values, Set<Id> currentRecordIds) {
		Map<String, Id> existingByValue = new Map<String, Id>();
		if (values == null || values.isEmpty()) {
			return existingByValue;
		}

		for (ResidentialLoanApplication existingRecord : [
			SELECT Id, FSC_ActoNumeroPagare__c
			FROM ResidentialLoanApplication
			WHERE FSC_ActoNumeroPagare__c IN :values AND Id NOT IN :currentRecordIds
			WITH USER_MODE
		]) {
			String value = normalizeUniqueValue(existingRecord.get(ACTO_NUMERO_PAGARE_FIELD));
			if (!String.isBlank(value) && !existingByValue.containsKey(value)) {
				existingByValue.put(value, existingRecord.Id);
			}
		}

		return existingByValue;
	}

	private static Map<String, Id> getExistingRecordsByNumeroFolio(Set<String> values, Set<Id> currentRecordIds) {
		Map<String, Id> existingByValue = new Map<String, Id>();
		if (values == null || values.isEmpty()) {
			return existingByValue;
		}

		Schema.DescribeFieldResult folioFieldDescribe = ResidentialLoanApplication.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
			.fields.getMap()
			.get(NUMERO_FOLIO_PAGARE_FIELD)
			.getDescribe();

		Schema.DisplayType folioFieldType = folioFieldDescribe.getType();

		if (
			folioFieldType == Schema.DisplayType.Currency ||
			folioFieldType == Schema.DisplayType.Double ||
			folioFieldType == Schema.DisplayType.Integer ||
			folioFieldType == Schema.DisplayType.Percent
		) {
			Set<Decimal> decimalValues = new Set<Decimal>();
			for (String value : values) {
				try {
					decimalValues.add(Decimal.valueOf(value));
				} catch (TypeException invalidNumber) {
					continue;
				}
			}

			if (decimalValues.isEmpty()) {
				return existingByValue;
			}

			for (
				ResidentialLoanApplication existingRecord : Database.query(
					'SELECT Id, ' +
						NUMERO_FOLIO_PAGARE_FIELD +
						' FROM ResidentialLoanApplication' +
						' WHERE ' +
						NUMERO_FOLIO_PAGARE_FIELD +
						' IN :decimalValues' +
						' AND Id NOT IN :currentRecordIds'
				)
			) {
				String value = normalizeUniqueValue(existingRecord.get(NUMERO_FOLIO_PAGARE_FIELD));
				if (!String.isBlank(value) && !existingByValue.containsKey(value)) {
					existingByValue.put(value, existingRecord.Id);
				}
			}

			return existingByValue;
		}

		for (
			ResidentialLoanApplication existingRecord : Database.query(
				'SELECT Id, ' +
					NUMERO_FOLIO_PAGARE_FIELD +
					' FROM ResidentialLoanApplication' +
					' WHERE ' +
					NUMERO_FOLIO_PAGARE_FIELD +
					' IN :values' +
					' AND Id NOT IN :currentRecordIds'
			)
		) {
			String value = normalizeUniqueValue(existingRecord.get(NUMERO_FOLIO_PAGARE_FIELD));
			if (!String.isBlank(value) && !existingByValue.containsKey(value)) {
				existingByValue.put(value, existingRecord.Id);
			}
		}

		return existingByValue;
	}

	@TestVisible
	private static void recalculateInstallmentAmount(
		List<ResidentialLoanApplication> newRLA,
		Map<Id, ResidentialLoanApplication> oldRLA
	) {
		if (newRLA == null || newRLA.isEmpty()) {
			return;
		}

		for (ResidentialLoanApplication rla : newRLA) {
			if (rla == null) {
				continue;
			}

			ResidentialLoanApplication oldRecord = oldRLA == null ? null : oldRLA.get(rla.Id);
			Boolean isInsert = oldRecord == null;

			Boolean parametersChanged = isInsert ||
				oldRecord.FSC_Monto__c != rla.FSC_Monto__c ||
				oldRecord.FSC_Plazo_meses__c != rla.FSC_Plazo_meses__c ||
				oldRecord.FSC_PlazoMeses__c != rla.FSC_PlazoMeses__c ||
				oldRecord.FSC_TasaInteres__c != rla.FSC_TasaInteres__c ||
				oldRecord.FSC_FormaPago__c != rla.FSC_FormaPago__c;

			if (!parametersChanged) {
				continue;
			}

			Decimal monto = rla.FSC_Monto__c;
			Decimal tasaAnual = rla.FSC_TasaInteres__c;
			Decimal plazo = resolvePlazoMeses(rla);

			if (monto == null || monto <= 0 || plazo == null || plazo <= 0 || tasaAnual == null || tasaAnual < 0) {
				continue;
			}

			String formaPago = rla.FSC_FormaPago__c == null ? '' : rla.FSC_FormaPago__c.trim();
			Decimal cuotaCalculada = null;

			if (formaPago.containsIgnoreCase('Capital al vencimiento')) {
				cuotaCalculada = calculateInteresMensual(monto, tasaAnual);
			} else {
				cuotaCalculada = calculateCuotaFrancesa(monto, tasaAnual, plazo);
			}

			if (cuotaCalculada != null) {
				rla.FSC_Monto_De_La_Cuota__c = cuotaCalculada;
			}
		}
	}

	private static Decimal resolvePlazoMeses(ResidentialLoanApplication rla) {
		if (rla == null) {
			return null;
		}
		if (!String.isBlank(rla.FSC_Plazo_meses__c)) {
			try {
				return Decimal.valueOf(rla.FSC_Plazo_meses__c.trim());
			} catch (Exception ex) {
				// Fallback to numeric field
			}
		}
		return rla.FSC_PlazoMeses__c;
	}

	@TestVisible
	private static Decimal calculateCuotaFrancesa(Decimal monto, Decimal tasaAnual, Decimal plazoMeses) {
		if (monto == null || monto <= 0 || plazoMeses == null || plazoMeses <= 0 || tasaAnual == null) {
			return null;
		}

		if (tasaAnual == 0) {
			return (monto / plazoMeses).setScale(2, System.RoundingMode.HALF_UP);
		}

		Double r = (tasaAnual.doubleValue() / 100.0) / 12.0;
		Double baseVal = 1.0 + r;
		Double n = plazoMeses.doubleValue();
		Double factor = Math.pow(baseVal, n);
		Double cuotaDouble = (monto.doubleValue() * r * factor) / (factor - 1.0);

		return Decimal.valueOf(cuotaDouble).setScale(2, System.RoundingMode.HALF_UP);
	}

	@TestVisible
	private static Decimal calculateInteresMensual(Decimal monto, Decimal tasaAnual) {
		if (monto == null || monto <= 0 || tasaAnual == null) {
			return null;
		}
		Decimal tasaMensual = (tasaAnual / 100.0) / 12.0;
		return (monto * tasaMensual).setScale(2, System.RoundingMode.HALF_UP);
	}
}