public with sharing class FSC_LoanDraftPersistenceService {
	public static final String STATUS_BORRADOR = 'Borrador';
	public static final String STATUS_EN_PROCESO = 'En proceso';
	public static final String STATUS_CERRADA_PERDIDA = 'Cerrada Perdida';
	public static final String SUBESTADO_COMPLETANDO_INFORMACION = 'Completando información';
	public static final String SUBESTADO_RECHAZADA_CLIENTE = 'Rechazada por cliente';
	private static Boolean isReconcilingSubmittedChildren = false;
	private static final Set<String> INITIAL_SUBMISSION_SUBESTADOS = new Set<String>{
		'En Motor Buró',
		'En validación PEP/Listas',
		'Recepción de documentos – Análisis'
	};
	private static final String TIPO_FACILIDAD_BPR = 'CONTROL DE PRESTAMOS - BPR';
	private static final String FACILIDAD_CONSUMO_DEFAULT = 'CONSUMO - 401';
	private static final String FACILIDAD_HIPOTECARIO_DOP = 'HIPOTECARIOS PARA LA VIVIENDA - 402';
	private static final String FACILIDAD_HIPOTECARIO_USD = 'HIPOTECARIO PARA LA VIVIENDA DOLARES - 453';

	public class OpenApplicationSummaryDTO {
		@AuraEnabled
		public Id id { get; set; }
		@AuraEnabled
		public String name { get; set; }
		@AuraEnabled
		public String numeroSolicitud { get; set; }
		@AuraEnabled
		public String status { get; set; }
		@AuraEnabled
		public String subestado { get; set; }
		@AuraEnabled
		public Boolean isDraft { get; set; }
		@AuraEnabled
		public String moneda { get; set; }
		@AuraEnabled
		public String monedaSimbolo { get; set; }
		@AuraEnabled
		public Decimal monto { get; set; }
		@AuraEnabled
		public String plazoMeses { get; set; }
		@AuraEnabled
		public Datetime createdDate { get; set; }
		@AuraEnabled
		public Datetime lastModifiedDate { get; set; }
		@AuraEnabled
		public String garantiaResumen { get; set; }
		@AuraEnabled
		public Integer totalGarantias { get; set; }
		@AuraEnabled
		public Integer totalSeguros { get; set; }
	}

	@AuraEnabled
	public static List<OpenApplicationSummaryDTO> getOpenApplicationsForAccount(Id accountId, String loanType) {
		List<OpenApplicationSummaryDTO> summaries = new List<OpenApplicationSummaryDTO>();
		if (accountId == null) {
			return summaries;
		}

		String rtDeveloperName = resolveRecordTypeDeveloperName(loanType);
		if (String.isBlank(rtDeveloperName)) {
			return summaries;
		}

		List<ResidentialLoanApplication> openApps = [
			SELECT
				Id,
				Name,
				FSC_NumeroSolicitud__c,
				Status,
				FSC_Subestado__c,
				FSC_Moneda__c,
				FSC_Monto__c,
				FSC_Plazo_meses__c,
				CreatedDate,
				LastModifiedDate,
				(
					SELECT
						Id,
						FSC_Clase_de_Garantia__c,
						FSC_Tipo_de_Garantia__c,
						FSC_Ubicacion__c,
						FSC_Valor_Inmueble__c,
						FSC_Marca_Vehiculo__c,
						FSC_Modelo_Vehiculo__c,
						FSC_Ano_Vehiculo__c,
						FSC_Descripcion_de_la_Garantia__c
					FROM FSC_Garantias__r
					ORDER BY CreatedDate ASC
					LIMIT 10
				),
				(SELECT Id FROM FSC_Seguros__r LIMIT 10)
			FROM ResidentialLoanApplication
			WHERE
				AccountId = :accountId
				AND RecordType.DeveloperName = :rtDeveloperName
				AND Status IN (:STATUS_BORRADOR, :STATUS_EN_PROCESO)
			WITH USER_MODE
			ORDER BY LastModifiedDate DESC, CreatedDate DESC
			LIMIT 20
		];

		for (ResidentialLoanApplication app : openApps) {
			OpenApplicationSummaryDTO dto = new OpenApplicationSummaryDTO();
			dto.id = app.Id;
			dto.name = app.Name;
			dto.numeroSolicitud = String.isNotBlank(app.FSC_NumeroSolicitud__c) ? app.FSC_NumeroSolicitud__c : app.Name;
			dto.status = app.Status;
			dto.subestado = app.FSC_Subestado__c;
			dto.isDraft = app.Status == STATUS_BORRADOR;
			dto.moneda = app.FSC_Moneda__c;
			dto.monedaSimbolo = app.FSC_Moneda__c == '2' ? 'US$' : 'RD$';
			dto.monto = app.FSC_Monto__c;
			dto.plazoMeses = app.FSC_Plazo_meses__c;
			dto.createdDate = app.CreatedDate;
			dto.lastModifiedDate = app.LastModifiedDate;
			List<FSC_Garantia__c> garantias = app.FSC_Garantias__r == null ? new List<FSC_Garantia__c>() : app.FSC_Garantias__r;
			List<FSC_Seguro__c> seguros = app.FSC_Seguros__r == null ? new List<FSC_Seguro__c>() : app.FSC_Seguros__r;
			dto.totalGarantias = garantias.size();
			dto.totalSeguros = seguros.size();
			dto.garantiaResumen = buildGuaranteeSummary(garantias);
			summaries.add(dto);
		}
		return summaries;
	}

	@AuraEnabled
	public static void discardDraftApplication(Id rlaId) {
		if (rlaId == null) {
			throw handledError('Debe indicar el borrador a descartar.');
		}
		List<ResidentialLoanApplication> rows = [
			SELECT Id, Status, FSC_Subestado__c
			FROM ResidentialLoanApplication
			WHERE Id = :rlaId
			WITH USER_MODE
			LIMIT 1
		];
		if (rows.isEmpty()) {
			throw handledError('No se encontró la solicitud borrador.');
		}
		if (rows[0].Status != STATUS_BORRADOR) {
			throw handledError('Solo se pueden descartar solicitudes que aún se encuentren en estado Borrador.');
		}
		ResidentialLoanApplication toClose = new ResidentialLoanApplication(
			Id = rows[0].Id,
			Status = STATUS_CERRADA_PERDIDA,
			FSC_Subestado__c = SUBESTADO_RECHAZADA_CLIENTE
		);
		update as user toClose;
	}

	@AuraEnabled
	public static Map<String, Object> saveStep1Draft(Id accountId, Id rlaId, String loanType, String applicantsJson) {
		Savepoint sp = Database.setSavepoint();
		try {
			Id resolvedAccountId = resolveAccountId(accountId, rlaId);
			if (resolvedAccountId == null) {
				throw handledError('No se pudo identificar el cliente de la solicitud.');
			}

			String rtDevName = resolveRecordTypeDeveloperName(loanType);
			if (String.isBlank(rtDevName)) {
				throw handledError('Tipo de solicitud no válido para guardar borrador.');
			}

			ResidentialLoanApplication draft = ensureEditableDraft(resolvedAccountId, rlaId, rtDevName);
			List<Object> rawApplicants = parseJsonList(applicantsJson);
			List<Map<String, Object>> syncedApplicants = syncDraftApplicants(draft.Id, resolvedAccountId, rawApplicants);

			return new Map<String, Object>{
				'rlaId' => draft.Id,
				'numeroSolicitud' => draft.FSC_NumeroSolicitud__c,
				'applicants' => syncedApplicants
			};
		} catch (AuraHandledException ex) {
			Database.rollback(sp);
			throw ex;
		} catch (Exception ex) {
			Database.rollback(sp);
			throw handledError('No se pudo guardar el avance de solicitantes: ' + ex.getMessage());
		}
	}

	@AuraEnabled
	public static Map<String, Object> saveFacilityDraft(
		Id rlaId,
		Id accountId,
		String loanType,
		String stepGeneralJson,
		String facilityJson
	) {
		Savepoint sp = Database.setSavepoint();
		try {
			Id resolvedAccountId = resolveAccountId(accountId, rlaId);
			if (resolvedAccountId == null) {
				throw handledError('No se pudo identificar el cliente de la solicitud.');
			}

			String rtDevName = resolveRecordTypeDeveloperName(loanType);
			if (String.isBlank(rtDevName)) {
				throw handledError('Tipo de solicitud no válido para guardar borrador.');
			}

			ResidentialLoanApplication draft = ensureEditableDraft(resolvedAccountId, rlaId, rtDevName);
			if (draft.Status != STATUS_BORRADOR) {
				return new Map<String, Object>{
					'rlaId' => draft.Id,
					'skippedNonDraft' => true,
					'guaranteeIdsByKey' => new Map<String, Id>(),
					'insuranceIdsByKey' => new Map<String, Id>()
				};
			}

			Map<String, Object> generalMap = parseJsonMap(stepGeneralJson);
			Map<String, Object> facilityMap = parseJsonMap(facilityJson);
			applyDraftFacilityHeaderFields(draft, rtDevName, generalMap, facilityMap);
			update as user draft;

			Map<String, Id> guaranteeIdsByKey = syncDraftGuarantees(draft.Id, extractChildList(facilityMap, 'FSC_Garantias__r'));
			Map<String, Id> insuranceIdsByKey = syncDraftInsurances(draft.Id, extractChildList(facilityMap, 'FSC_Seguros__r'));

			return new Map<String, Object>{
				'rlaId' => draft.Id,
				'skippedNonDraft' => false,
				'guaranteeIdsByKey' => guaranteeIdsByKey,
				'insuranceIdsByKey' => insuranceIdsByKey
			};
		} catch (AuraHandledException ex) {
			Database.rollback(sp);
			throw ex;
		} catch (Exception ex) {
			Database.rollback(sp);
			throw handledError('No se pudo guardar el avance de la solicitud: ' + ex.getMessage());
		}
	}

	@AuraEnabled
	public static Map<String, Object> getDraftSnapshot(Id rlaId, Id accountId, String loanType) {
		Map<String, Object> empty = new Map<String, Object>{ 'found' => false };
		ResidentialLoanApplication rla = findSnapshotApplication(rlaId, accountId, loanType);
		if (rla == null) {
			return empty;
		}

		List<Map<String, Object>> applicants = queryFullApplicantMaps(rla.Id);
		List<Map<String, Object>> guarantees = queryFullGuaranteeMaps(rla.Id);
		List<Map<String, Object>> insurances = queryFullInsuranceMaps(rla.Id);
		Map<String, Object> facility = buildFacilityFromApplication(rla, guarantees, insurances);
		Map<String, Object> generalStep = buildGeneralStepFromApplication(rla, facility);

		return new Map<String, Object>{
			'found' => true,
			'rlaId' => rla.Id,
			'accountId' => rla.AccountId,
			'name' => rla.Name,
			'nombreCliente' => rla.FSC_Nombre_Cliente__c,
			'numeroSolicitud' => rla.FSC_NumeroSolicitud__c,
			'status' => rla.Status,
			'subestado' => rla.FSC_Subestado__c,
			'recordTypeDeveloperName' => rla.RecordType.DeveloperName,
			'applicants' => applicants,
			'facility' => facility,
			'datosGeneralesSolicitud' => generalStep
		};
	}

	/**
	 * Reconcilia registros hijos pre-guardados en Borrador cuando el Integration Procedure de OmniStudio
	 * (DMPGarantias / DMPSeguros / DMPCrearLoanApplicant) ejecuta la transición final de Borrador -> En proceso,
	 * evitando que DataRaptors sin IsUpsertKey dejen inmuebles, seguros o referencias duplicadas.
	 */
	public static void reconcileSubmittedDraftChildren(
		List<ResidentialLoanApplication> newRLA,
		Map<Id, ResidentialLoanApplication> oldRLA
	) {
		if (newRLA == null || newRLA.isEmpty() || oldRLA == null || oldRLA.isEmpty()) {
			return;
		}
		Set<Id> promotedIds = new Set<Id>();
		for (ResidentialLoanApplication rla : newRLA) {
			ResidentialLoanApplication previous = rla == null ? null : oldRLA.get(rla.Id);
			if (
				previous != null &&
				previous.Status == STATUS_BORRADOR &&
				rla.Status == STATUS_EN_PROCESO &&
				rla.RecordTypeId != null
			) {
				promotedIds.add(rla.Id);
			}
		}
		if (promotedIds.isEmpty()) {
			return;
		}
		deduplicateSubmittedApplicantChildren(promotedIds);
	}

	public static void deduplicateInsertedGuaranteesOnSubmittedRla(List<FSC_Garantia__c> existingAndNewForRla) {
		if (existingAndNewForRla == null || existingAndNewForRla.size() <= 1) {
			return;
		}
		Map<String, List<FSC_Garantia__c>> bySignature = new Map<String, List<FSC_Garantia__c>>();
		for (FSC_Garantia__c row : existingAndNewForRla) {
			String sig = guaranteeSignature(row);
			if (!bySignature.containsKey(sig)) {
				bySignature.put(sig, new List<FSC_Garantia__c>());
			}
			bySignature.get(sig).add(row);
		}
		List<FSC_Garantia__c> duplicatesToDelete = new List<FSC_Garantia__c>();
		for (List<FSC_Garantia__c> groupRows : bySignature.values()) {
			if (groupRows.size() > 1) {
				// Conservamos el registro más reciente (recién insertado con los últimos valores del DataRaptor)
				// y retiramos la copia anterior en borrador solo cuando coinciden exactamente en firma de negocio.
				for (Integer idx = 0; idx < groupRows.size() - 1; idx++) {
					duplicatesToDelete.add(new FSC_Garantia__c(Id = groupRows[idx].Id));
				}
			}
		}
		if (!duplicatesToDelete.isEmpty()) {
			delete as system duplicatesToDelete;
		}
	}

	public static void deduplicateSubmittedChildrenForApplications(Set<Id> applicationIds) {
		if (applicationIds == null || applicationIds.isEmpty()) {
			return;
		}
		Map<Id, List<FSC_Garantia__c>> guaranteesByRla = new Map<Id, List<FSC_Garantia__c>>();
		for (FSC_Garantia__c g : [
			SELECT
				Id,
				CreatedDate,
				FSC_Residential_Loan_Application__c,
				FSC_Clase_de_Garantia__c,
				FSC_Tipo_de_Garantia__c,
				FSC_Proposito_Garantia_Hipotecario__c,
				FSC_Ubicacion__c,
				FSC_Valor_Inmueble__c,
				FSC_Precio_de_Venta__c,
				FSC_Numero_Chasis_Vehiculo__c,
				FSC_Marca_Vehiculo__c,
				FSC_Modelo_Vehiculo__c,
				FSC_Ano_Vehiculo__c,
				FSC_Descripcion_de_la_Garantia__c
			FROM FSC_Garantia__c
			WHERE FSC_Residential_Loan_Application__c IN :applicationIds
			WITH SYSTEM_MODE
			ORDER BY CreatedDate ASC, Id ASC
		]) {
			if (!guaranteesByRla.containsKey(g.FSC_Residential_Loan_Application__c)) {
				guaranteesByRla.put(g.FSC_Residential_Loan_Application__c, new List<FSC_Garantia__c>());
			}
			guaranteesByRla.get(g.FSC_Residential_Loan_Application__c).add(g);
		}
		for (List<FSC_Garantia__c> listForRla : guaranteesByRla.values()) {
			deduplicateInsertedGuaranteesOnSubmittedRla(listForRla);
		}

		Map<Id, List<FSC_Seguro__c>> insurancesByRla = new Map<Id, List<FSC_Seguro__c>>();
		for (FSC_Seguro__c s : [
			SELECT
				Id,
				CreatedDate,
				FSC_Residential_Loan_Application__c,
				FSC_Tipo_de_Seguro__c,
				FSC_Monto_de_la_Prima__c,
				FSC_Seguro_Desempleo__c,
				FSC_Monto_Prima_Desempleo__c
			FROM FSC_Seguro__c
			WHERE FSC_Residential_Loan_Application__c IN :applicationIds
			WITH SYSTEM_MODE
			ORDER BY CreatedDate ASC, Id ASC
		]) {
			if (!insurancesByRla.containsKey(s.FSC_Residential_Loan_Application__c)) {
				insurancesByRla.put(s.FSC_Residential_Loan_Application__c, new List<FSC_Seguro__c>());
			}
			insurancesByRla.get(s.FSC_Residential_Loan_Application__c).add(s);
		}
		List<FSC_Seguro__c> duplicateInsurances = new List<FSC_Seguro__c>();
		for (List<FSC_Seguro__c> listForRla : insurancesByRla.values()) {
			Map<String, List<FSC_Seguro__c>> byType = new Map<String, List<FSC_Seguro__c>>();
			for (FSC_Seguro__c s : listForRla) {
				String key = normalizeUpper(s.FSC_Tipo_de_Seguro__c);
				if (!byType.containsKey(key)) {
					byType.put(key, new List<FSC_Seguro__c>());
				}
				byType.get(key).add(s);
			}
			for (List<FSC_Seguro__c> sameType : byType.values()) {
				if (sameType.size() > 1) {
					for (Integer idx = 0; idx < sameType.size() - 1; idx++) {
						duplicateInsurances.add(new FSC_Seguro__c(Id = sameType[idx].Id));
					}
				}
			}
		}
		if (!duplicateInsurances.isEmpty()) {
			delete as system duplicateInsurances;
		}
		deduplicateSubmittedApplicantChildren(applicationIds);
	}

	public static void reconcileInsertedGuaranteesOnSubmittedApplications(List<FSC_Garantia__c> insertedGuarantees) {
		if (isReconcilingSubmittedChildren || insertedGuarantees == null || insertedGuarantees.isEmpty()) {
			return;
		}
		Set<Id> candidateRlaIds = new Set<Id>();
		for (FSC_Garantia__c g : insertedGuarantees) {
			if (g != null && g.FSC_Residential_Loan_Application__c != null) {
				candidateRlaIds.add(g.FSC_Residential_Loan_Application__c);
			}
		}
		reconcileInsertedChildrenForInitialSubmission(candidateRlaIds);
	}

	public static void reconcileInsertedInsurancesOnSubmittedApplications(List<FSC_Seguro__c> insertedInsurances) {
		if (isReconcilingSubmittedChildren || insertedInsurances == null || insertedInsurances.isEmpty()) {
			return;
		}
		Set<Id> candidateRlaIds = new Set<Id>();
		for (FSC_Seguro__c s : insertedInsurances) {
			if (s != null && s.FSC_Residential_Loan_Application__c != null) {
				candidateRlaIds.add(s.FSC_Residential_Loan_Application__c);
			}
		}
		reconcileInsertedChildrenForInitialSubmission(candidateRlaIds);
	}

	private static void reconcileInsertedChildrenForInitialSubmission(Set<Id> candidateRlaIds) {
		if (candidateRlaIds == null || candidateRlaIds.isEmpty()) {
			return;
		}
		Set<Id> activeInitialIds = new Set<Id>();
		for (ResidentialLoanApplication rla : [
			SELECT Id, Status, FSC_Subestado__c
			FROM ResidentialLoanApplication
			WHERE Id IN :candidateRlaIds AND Status = :STATUS_EN_PROCESO AND FSC_Subestado__c IN :INITIAL_SUBMISSION_SUBESTADOS
			WITH SYSTEM_MODE
		]) {
			activeInitialIds.add(rla.Id);
		}
		if (activeInitialIds.isEmpty()) {
			return;
		}
		isReconcilingSubmittedChildren = true;
		try {
			deduplicateSubmittedChildrenForApplications(activeInitialIds);
		} finally {
			isReconcilingSubmittedChildren = false;
		}
	}

	private static void deduplicateSubmittedApplicantChildren(Set<Id> applicationIds) {
		List<LoanApplicant> applicants = [
			SELECT
				Id,
				LoanApplicationId,
				(
					SELECT Id, FSC_FirstName__c, FSC_LastName__c, FSC_Telefono__c, FSC_Parentesco__c, FSC_Identificacion__c
					FROM Referencias__r
					ORDER BY CreatedDate ASC, Id ASC
				),
				(
					SELECT Id, FSC_EntidadFinanciera__c, FSC_TipoFacilidad__c, FSC_Facilidad__c, FSC_Moneda__c, FSC_Balance__c
					FROM FSC_Facilidades_en_Otras_Instituciones__r
					ORDER BY CreatedDate ASC, Id ASC
				)
			FROM LoanApplicant
			WHERE LoanApplicationId IN :applicationIds
			WITH SYSTEM_MODE
		];
		List<FSC_Referencias__c> dupRefs = new List<FSC_Referencias__c>();
		List<FSC_Facilidad_Otra_Institucion__c> dupExt = new List<FSC_Facilidad_Otra_Institucion__c>();
		for (LoanApplicant la : applicants) {
			Map<String, List<FSC_Referencias__c>> refsByKey = new Map<String, List<FSC_Referencias__c>>();
			for (FSC_Referencias__c ref : la.Referencias__r) {
				String key =
					normalizeUpper(ref.FSC_FirstName__c) +
					'|' +
					normalizeUpper(ref.FSC_LastName__c) +
					'|' +
					normalizeDigits(ref.FSC_Telefono__c) +
					'|' +
					normalizeUpper(ref.FSC_Parentesco__c);
				if (!refsByKey.containsKey(key)) {
					refsByKey.put(key, new List<FSC_Referencias__c>());
				}
				refsByKey.get(key).add(ref);
			}
			for (List<FSC_Referencias__c> groupRefs : refsByKey.values()) {
				if (groupRefs.size() > 1) {
					for (Integer i = 0; i < groupRefs.size() - 1; i++) {
						dupRefs.add(new FSC_Referencias__c(Id = groupRefs[i].Id));
					}
				}
			}

			Map<String, List<FSC_Facilidad_Otra_Institucion__c>> extByKey = new Map<String, List<FSC_Facilidad_Otra_Institucion__c>>();
			for (FSC_Facilidad_Otra_Institucion__c ext : la.FSC_Facilidades_en_Otras_Instituciones__r) {
				String key =
					normalizeUpper(ext.FSC_EntidadFinanciera__c) +
					'|' +
					normalizeUpper(ext.FSC_TipoFacilidad__c) +
					'|' +
					normalizeUpper(ext.FSC_Facilidad__c) +
					'|' +
					normalizeUpper(ext.FSC_Moneda__c) +
					'|' +
					String.valueOf(ext.FSC_Balance__c);
				if (!extByKey.containsKey(key)) {
					extByKey.put(key, new List<FSC_Facilidad_Otra_Institucion__c>());
				}
				extByKey.get(key).add(ext);
			}
			for (List<FSC_Facilidad_Otra_Institucion__c> groupExt : extByKey.values()) {
				if (groupExt.size() > 1) {
					for (Integer i = 0; i < groupExt.size() - 1; i++) {
						dupExt.add(new FSC_Facilidad_Otra_Institucion__c(Id = groupExt[i].Id));
					}
				}
			}
		}
		if (!dupRefs.isEmpty()) {
			delete as system dupRefs;
		}
		if (!dupExt.isEmpty()) {
			delete as system dupExt;
		}
	}

	private static ResidentialLoanApplication ensureEditableDraft(Id accountId, Id rlaId, String rtDevName) {
		if (rlaId != null) {
			List<ResidentialLoanApplication> existing = [
				SELECT Id, AccountId, Name, FSC_NumeroSolicitud__c, Status, FSC_Subestado__c, RecordTypeId, RecordType.DeveloperName
				FROM ResidentialLoanApplication
				WHERE Id = :rlaId
				WITH USER_MODE
				LIMIT 1
			];
			if (!existing.isEmpty()) {
				return existing[0];
			}
		}

		Account acc = [
			SELECT Id, Name, FirstName, LastName, ACC_NumIdentificacion__c
			FROM Account
			WHERE Id = :accountId
			WITH SYSTEM_MODE
			LIMIT 1
		];
		Id rtId = Schema.SObjectType.ResidentialLoanApplication.getRecordTypeInfosByDeveloperName().get(rtDevName).getRecordTypeId();
		String titlePrefix = buildTitlePrefix(rtDevName);
		String clientFullName = String.isNotBlank(acc.Name)
			? acc.Name
			: joinParts(new List<String>{ acc.FirstName, acc.LastName }, ' ');
		String docSuffix = String.isNotBlank(acc.ACC_NumIdentificacion__c) ? ' - ' + acc.ACC_NumIdentificacion__c : '';
		String draftName = (titlePrefix + ' - ' + clientFullName + docSuffix).left(80);

		ResidentialLoanApplication created = new ResidentialLoanApplication(
			Name = draftName,
			AccountId = accountId,
			RecordTypeId = rtId,
			Status = STATUS_BORRADOR,
			FSC_Subestado__c = SUBESTADO_COMPLETANDO_INFORMACION,
			FSC_Nombre_Cliente__c = clientFullName,
			FSC_TipoSolicitud__c = 'BPR'
		);
		insert as user created;

		return [
			SELECT Id, AccountId, Name, FSC_NumeroSolicitud__c, Status, FSC_Subestado__c, RecordTypeId, RecordType.DeveloperName
			FROM ResidentialLoanApplication
			WHERE Id = :created.Id
			WITH USER_MODE
			LIMIT 1
		];
	}

	private static List<Map<String, Object>> syncDraftApplicants(Id rlaId, Id accountId, List<Object> rawApplicants) {
		List<LoanApplicant> existingList = [
			SELECT Id, FSC_TipoIdentificacion__c, FSC_NumIdentificacion__c, FSC_TipoSolicitante__c
			FROM LoanApplicant
			WHERE LoanApplicationId = :rlaId
			WITH USER_MODE
			ORDER BY CreatedDate ASC
		];
		Map<Id, LoanApplicant> existingById = new Map<Id, LoanApplicant>(existingList);
		Map<String, LoanApplicant> existingByDoc = new Map<String, LoanApplicant>();
		for (LoanApplicant ex : existingList) {
			String docKey = applicantDocKey(ex.FSC_TipoIdentificacion__c, ex.FSC_NumIdentificacion__c);
			if (String.isNotBlank(docKey)) {
				existingByDoc.put(docKey, ex);
			}
		}

		List<LoanApplicant> toUpsert = new List<LoanApplicant>();
		List<Map<String, Object>> normalizedInputs = new List<Map<String, Object>>();
		Set<Id> retainedIds = new Set<Id>();

		for (Object item : rawApplicants) {
			if (!(item instanceof Map<String, Object>)) {
				continue;
			}
			Map<String, Object> row = (Map<String, Object>) item;
			LoanApplicant target = new LoanApplicant(LoanApplicationId = rlaId);

			Id incomingId = parseId(row.get('Id'), LoanApplicant.SObjectType);
			if (incomingId != null && existingById.containsKey(incomingId)) {
				target.Id = incomingId;
			} else {
				String docKey = applicantDocKey(stringVal(row.get('FSC_TipoIdentificacion__c')), stringVal(row.get('FSC_NumIdentificacion__c')));
				if (String.isNotBlank(docKey) && existingByDoc.containsKey(docKey)) {
					target.Id = existingByDoc.get(docKey).Id;
				}
			}

			String fullName = stringVal(row.get('Name'));
			if (String.isBlank(fullName)) {
				fullName = joinParts(
					new List<String>{
						stringVal(row.get('FSC_Nombre__c')),
						stringVal(row.get('FSC_PrimerApellido__c')),
						stringVal(row.get('FSC_SegundoApellido__c'))
					},
					' '
				);
			}
			target.Name = String.isNotBlank(fullName) ? fullName.left(255) : 'Solicitante';
			target.FSC_TipoSolicitante__c = stringVal(row.get('FSC_TipoSolicitante__c'));
			target.FSC_TipoIdentificacion__c = stringVal(row.get('FSC_TipoIdentificacion__c'));
			target.FSC_NumIdentificacion__c = stringVal(row.get('FSC_NumIdentificacion__c'));
			target.FSC_Nombre__c = stringVal(row.get('FSC_Nombre__c'));
			target.FSC_PrimerApellido__c = stringVal(row.get('FSC_PrimerApellido__c'));
			target.FSC_SegundoApellido__c = stringVal(row.get('FSC_SegundoApellido__c'));
			target.FSC_FechaNacimiento__c = dateVal(row.get('FSC_FechaNacimiento__c'));
			target.FSC_Nacionalidad__c = stringVal(row.get('FSC_Nacionalidad__c'));
			target.FSC_EstadoCivil__c = stringVal(row.get('FSC_EstadoCivil__c'));
			target.FSC_TipoVivienda__c = stringVal(row.get('FSC_TipoVivienda__c'));
			target.FSC_TiempoVivienda__c = dateVal(row.get('FSC_TiempoVivienda__c'));
			target.FSC_Ocupacion__c = stringVal(row.get('FSC_Ocupacion__c'));
			target.FSC_EmpresaAnteriorLaboro__c = stringVal(row.get('FSC_EmpresaAnteriorLaboro__c'));
			target.FSC_LugarFondeLabora__c = stringVal(row.get('FSC_LugarFondeLabora__c'));
			target.FSC_TiempoLaborando__c = dateVal(row.get('FSC_TiempoLaborando__c'));
			target.FSC_FuenteIngreso__c = stringVal(row.get('FSC_FuenteIngreso__c'));
			target.FSC_IngresosMensuales__c = decimalVal(row.get('FSC_IngresosMensuales__c'));
			target.FSC_MonedaSalario__c = stringVal(row.get('FSC_MonedaSalario__c'));
			target.FSC_SalarioOriginal__c = decimalVal(row.get('FSC_SalarioOriginal__c'));
			target.FSC_OtrosIngresos__c = decimalVal(row.get('FSC_OtrosIngresos__c'));
			target.FSC_OtrosIngresosOriginal__c = decimalVal(row.get('FSC_OtrosIngresosOriginal__c'));
			target.FSC_DescripcionOtrosIngresos__c = stringVal(row.get('FSC_DescripcionOtrosIngresos__c'));
			target.FSC_MontoPrestacionesLaborales__c = stringVal(row.get('FSC_MontoPrestacionesLaborales__c'));
			target.FSC_NumeroDependientes__c = decimalVal(row.get('FSC_NumeroDependientes__c'));
			target.FSC_TipoNegocio__c = stringVal(row.get('FSC_TipoNegocio__c'));
			target.FSC_ClasificacionSIB__c = stringVal(row.get('FSC_ClasificacionSIB__c'));

			toUpsert.add(target);
			normalizedInputs.add(row);
		}

		if (!toUpsert.isEmpty()) {
			upsert as user toUpsert;
		}
		for (LoanApplicant saved : toUpsert) {
			retainedIds.add(saved.Id);
		}

		List<LoanApplicant> toDelete = new List<LoanApplicant>();
		for (LoanApplicant ex : existingList) {
			if (!retainedIds.contains(ex.Id)) {
				toDelete.add(ex);
			}
		}
		if (!toDelete.isEmpty()) {
			delete as user toDelete;
		}

		if (!retainedIds.isEmpty()) {
			syncApplicantSubcollections(rlaId, accountId, toUpsert, normalizedInputs);
		}
		return queryFullApplicantMaps(rlaId);
	}

	private static void syncApplicantSubcollections(
		Id rlaId,
		Id accountId,
		List<LoanApplicant> savedApplicants,
		List<Map<String, Object>> normalizedInputs
	) {
		Set<Id> applicantIds = new Set<Id>();
		for (LoanApplicant la : savedApplicants) {
			applicantIds.add(la.Id);
		}

		delete as system [SELECT Id FROM FSC_Referencias__c WHERE FSC_LoanApplicant__c IN :applicantIds];
		delete as system [SELECT Id FROM FSC_Facilidad_Otra_Institucion__c WHERE FSC_LoanApplicant__c IN :applicantIds];
		delete as system [
			SELECT Id
			FROM ContactPointPhone
			WHERE FSC_Solicitante__c IN :applicantIds AND ParentId = NULL
		];
		delete as system [
			SELECT Id
			FROM ContactPointAddress
			WHERE FSC_Solicitante__c IN :applicantIds AND ParentId = NULL
		];
		delete as system [
			SELECT Id
			FROM ContactPointEmail
			WHERE FSC_Solicitante__c IN :applicantIds AND ParentId = NULL
		];

		List<FSC_Referencias__c> refsToInsert = new List<FSC_Referencias__c>();
		List<FSC_Facilidad_Otra_Institucion__c> extToInsert = new List<FSC_Facilidad_Otra_Institucion__c>();

		for (Integer i = 0; i < savedApplicants.size(); i++) {
			Id applicantId = savedApplicants[i].Id;
			Map<String, Object> inputRow = normalizedInputs[i];

			for (Map<String, Object> refMap : extractChildList(inputRow, 'FSC_Referencias__c')) {
				String firstName = stringVal(refMap.get('FSC_FirstName__c'));
				String lastName = stringVal(refMap.get('FSC_LastName__c'));
				String refName = stringVal(refMap.get('Name'));
				if (String.isBlank(refName)) {
					refName = joinParts(new List<String>{ firstName, lastName }, ' ');
				}
				refsToInsert.add(
					new FSC_Referencias__c(
						Name = String.isNotBlank(refName) ? refName.left(80) : 'Referencia',
						FSC_LoanApplicant__c = applicantId,
						FSC_Residential_Loan_Application__c = rlaId,
						FSC_FirstName__c = firstName,
						FSC_LastName__c = lastName,
						FSC_TipoIdentificacion__c = stringVal(refMap.get('FSC_TipoIdentificacion__c')),
						FSC_Identificacion__c = stringVal(refMap.get('FSC_Identificacion__c')),
						FSC_Direccion__c = stringVal(refMap.get('FSC_Direccion__c')),
						FSC_Email__c = stringVal(refMap.get('FSC_Email__c')),
						FSC_Telefono__c = stringVal(refMap.get('FSC_Telefono__c')),
						FSC_Parentesco__c = stringVal(refMap.get('FSC_Parentesco__c')),
						FSC_LugarTrabajo__c = stringVal(refMap.get('FSC_LugarTrabajo__c'))
					)
				);
			}

			Integer extIdx = 1;
			for (Map<String, Object> extMap : extractChildList(inputRow, 'FSC_Facilidad_Otra_Institucion__c')) {
				String extName = stringVal(extMap.get('Name'));
				extToInsert.add(
					new FSC_Facilidad_Otra_Institucion__c(
						Name = String.isNotBlank(extName) ? extName.left(80) : ('Fuera de Banco Vimenca ' + extIdx),
						FSC_LoanApplicant__c = applicantId,
						FSC_TipoFacilidad__c = stringVal(extMap.get('FSC_TipoFacilidad__c')),
						FSC_Facilidad__c = stringVal(extMap.get('FSC_Facilidad__c')),
						FSC_DescripcionFacilidad__c = stringVal(extMap.get('FSC_DescripcionFacilidad__c')),
						FSC_EntidadFinanciera__c = stringVal(extMap.get('FSC_EntidadFinanciera__c')),
						FSC_Balance__c = decimalVal(extMap.get('FSC_Balance__c')),
						FSC_Moneda__c = stringVal(extMap.get('FSC_Moneda__c'))
					)
				);
				extIdx++;
			}
		}

		if (!refsToInsert.isEmpty()) {
			insert as user refsToInsert;
		}
		if (!extToInsert.isEmpty()) {
			insert as user extToInsert;
		}
	}

	private static void applyDraftFacilityHeaderFields(
		ResidentialLoanApplication draft,
		String rtDevName,
		Map<String, Object> generalMap,
		Map<String, Object> facilityMap
	) {
		if (!generalMap.isEmpty()) {
			if (generalMap.containsKey('FSC_SolicitudMedianteReferidor__c')) {
				Boolean medRef = booleanVal(generalMap.get('FSC_SolicitudMedianteReferidor__c'));
				if (medRef != null) {
					draft.FSC_SolicitudMedianteReferidor__c = medRef;
				}
			}
			if (generalMap.containsKey('FSC_Referidor__c')) {
				draft.FSC_Referidor__c = stringVal(generalMap.get('FSC_Referidor__c'));
			}
			if (generalMap.containsKey('FSC_TipoSolicitudMRI__c')) {
				draft.FSC_TipoSolicitudMRI__c = stringVal(generalMap.get('FSC_TipoSolicitudMRI__c'));
			}
			if (generalMap.containsKey('FSC_TipoProductoSolicitudMRI__c')) {
				draft.FSC_TipoProductoSolicitudMRI__c = stringVal(generalMap.get('FSC_TipoProductoSolicitudMRI__c'));
			}
			if (generalMap.containsKey('FSC_CanalSolicitudMRI__c')) {
				draft.FSC_CanalSolicitudMRI__c = stringVal(generalMap.get('FSC_CanalSolicitudMRI__c'));
			}
			if (generalMap.containsKey('FSC_EsRefinanciamiento__c')) {
				Boolean esRef = booleanVal(generalMap.get('FSC_EsRefinanciamiento__c'));
				if (esRef != null) {
					draft.FSC_EsRefinanciamiento__c = esRef;
				}
			}
			if (generalMap.containsKey('FSC_EsConsolidacionDeudas__c')) {
				Boolean esCons = booleanVal(generalMap.get('FSC_EsConsolidacionDeudas__c'));
				if (esCons != null) {
					draft.FSC_EsConsolidacionDeudas__c = esCons;
				}
			}
			if (generalMap.containsKey('FSC_TipoDeudaCancelar__c')) {
				draft.FSC_TipoDeudaCancelar__c = stringVal(generalMap.get('FSC_TipoDeudaCancelar__c'));
			}
		}

		if (facilityMap.isEmpty()) {
			return;
		}

		String tipoFacilidad = stringVal(facilityMap.get('FSC_Tipo_Facilidad__c'));
		if (String.isNotBlank(tipoFacilidad)) {
			draft.FSC_Facilidad__c = tipoFacilidad;
			if (tipoFacilidad.contains('BPR')) {
				draft.FSC_TipoSolicitud__c = 'BPR';
			}
		}

		String facilidad = stringVal(facilityMap.get('FSC_Facilidad__c'));
		String moneda = stringVal(facilityMap.get('FSC_Moneda__c'));
		if (String.isBlank(moneda) && String.isNotBlank(facilidad)) {
			moneda = facilidad == FACILIDAD_HIPOTECARIO_USD ? '2' : '1';
		}
		if (String.isNotBlank(moneda)) {
			draft.FSC_Moneda__c = moneda;
		}

		Boolean prestamoConvenio = booleanVal(facilityMap.get('FSC_Prestamo_Convenio__c'));
		if (prestamoConvenio != null) {
			draft.FSC_PrestamoConvenio__c = prestamoConvenio;
		}
		draft.FSC_Tipo_Modalidad__c = stringVal(facilityMap.get('FSC_Tipo_Modalidad__c'));
		draft.FSC_lineaFinanciera__c = stringVal(facilityMap.get('FSC_Lineas_Financieras_Empresas__c'));

		Boolean conGarantia = booleanVal(facilityMap.get('FSC_Prestamo_Con_Garantia__c'));
		if (conGarantia != null) {
			draft.FSC_PrestamoGarantia__c = conGarantia;
		}
		Boolean reqContrato = booleanVal(facilityMap.get('FSC_Requiere_Contrato_Pagare_Notarial__c'));
		if (reqContrato != null) {
			draft.FSC_RequiereContratoPagareNotarial__c = reqContrato;
		}

		draft.FSC_DescripcionPropositoFacilidad__c = stringVal(facilityMap.get('FSC_Descripcion_Proposito_Facilidad__c'));
		draft.FSC_Monto__c = decimalVal(facilityMap.get('FSC_Monto_Solicitado__c'));
		Decimal plazoNum = decimalVal(facilityMap.get('FSC_Plazo_meses__c'));
		draft.FSC_Plazo_meses__c = plazoNum == null ? null : String.valueOf(plazoNum.intValue());
		if (rtDevName != 'FSC_Solicitud_Credito_PYME') {
			draft.FSC_Cuotas__c = plazoNum;
		}
		draft.FSC_TasaInteres__c = decimalVal(facilityMap.get('FSC_Tasa_Interes__c'));

		Boolean tasaFija = booleanVal(facilityMap.get('FSC_Tasa_Fija__c'));
		if (tasaFija != null) {
			draft.FSC_Tasa_Fija__c = tasaFija;
		}
		draft.FSC_TasaFijaPorMeses__c = tasaFija == true ? decimalVal(facilityMap.get('FSC_Tiempo_Tasa_Fija__c')) : null;
		draft.FSC_FormaPago__c = stringVal(facilityMap.get('FSC_Forma_De_Pago__c'));
		draft.FSC_Monto_De_La_Cuota__c = decimalVal(facilityMap.get('FSC_Monto_De_La_Cuota__c'));
	}

	private static Map<String, Id> syncDraftGuarantees(Id rlaId, List<Map<String, Object>> incomingGuarantees) {
		List<FSC_Garantia__c> existingRows = [
			SELECT Id
			FROM FSC_Garantia__c
			WHERE FSC_Residential_Loan_Application__c = :rlaId
			WITH USER_MODE
			ORDER BY CreatedDate ASC
		];
		Set<Id> existingIds = new Map<Id, FSC_Garantia__c>(existingRows).keySet();
		List<FSC_Garantia__c> toUpsert = new List<FSC_Garantia__c>();
		List<String> rowKeys = new List<String>();
		Set<Id> retainedIds = new Set<Id>();

		Integer idx = 1;
		for (Map<String, Object> item : incomingGuarantees) {
			FSC_Garantia__c g = new FSC_Garantia__c(FSC_Residential_Loan_Application__c = rlaId);
			Id incomingId = parseId(item.get('Id'), FSC_Garantia__c.SObjectType);
			if (incomingId != null && existingIds.contains(incomingId)) {
				g.Id = incomingId;
			}
			String nameVal = stringVal(item.get('Name'));
			if (String.isBlank(nameVal)) {
				nameVal = stringVal(item.get('FSC_Tipo_de_Garantia__c'));
			}
			g.Name = String.isNotBlank(nameVal) ? nameVal.left(80) : ('Garantia ' + idx);
			g.FSC_MonedaGarantia__c = stringVal(item.get('FSC_MonedaGarantia__c'));
			g.FSC_Clase_de_Garantia__c = stringVal(item.get('FSC_Clase_de_Garantia__c'));
			g.FSC_Tipo_de_Garantia__c = stringVal(item.get('FSC_Tipo_de_Garantia__c'));
			g.FSC_Descripcion_de_la_Garantia__c = stringVal(item.get('FSC_Descripcion_de_la_Garantia__c'));
			g.FSC_Proposito_Garantia_Hipotecario__c = stringVal(item.get('FSC_Proposito_Garantia_Hipotecario__c'));
			g.FSC_Valor_Tasado__c = decimalVal(item.get('FSC_Valor_Tasado__c'));
			g.FSC_Valor_Mejoras__c = decimalVal(item.get('FSC_Valor_Mejoras__c'));
			g.FSC_SaldoPrimeraHipoteca__c = decimalVal(item.get('FSC_SaldoPrimeraHipoteca__c'));
			Boolean tasadorExt = booleanVal(item.get('FSC_EsTasadorExterno__c'));
			g.FSC_EsTasadorExterno__c = tasadorExt == true;
			g.FSC_NombreTasadorExterno__c = stringVal(item.get('FSC_NombreTasadorExterno__c'));
			g.FSC_Tasado_Por__c = stringVal(item.get('FSC_Tasado_Por__c'));
			g.FSC_Fecha_Tasacion__c = dateVal(item.get('FSC_Fecha_Tasacion__c'));
			g.FSC_Monto_Inicial_Avance_Pagado__c = decimalVal(item.get('FSC_Monto_Inicial_Avance_Pagado__c'));
			g.FSC_Valor_Inmueble__c = decimalVal(item.get('FSC_Valor_Inmueble__c'));
			g.FSC_Precio_de_Venta__c = decimalVal(item.get('FSC_Precio_de_Venta__c'));
			g.FSC_Metros_Cuadrados_de_Construccion__c = decimalVal(item.get('FSC_Metros_Cuadrados_de_Construccion__c'));
			g.FSC_Ubicacion__c = stringVal(item.get('FSC_Ubicacion__c'));
			g.FSC_Tipo_de_Inmueble__c = stringVal(item.get('FSC_Tipo_de_Inmueble__c'));
			Boolean esDealer = booleanVal(item.get('FSC_Es_Concesionario_Dealer__c'));
			g.FSC_Es_Concesionario_Dealer__c = esDealer == true;
			g.FSC_Concesionario__c = stringVal(item.get('FSC_Concesionario__c'));
			g.FSC_Marca_Vehiculo__c = stringVal(item.get('FSC_Marca_Vehiculo__c'));
			g.FSC_Modelo_Vehiculo__c = stringVal(item.get('FSC_Modelo_Vehiculo__c'));
			g.FSC_Ano_Vehiculo__c = decimalVal(item.get('FSC_Ano_Vehiculo__c'));
			g.FSC_Color_Vehiculo__c = stringVal(item.get('FSC_Color_Vehiculo__c'));
			g.FSC_Numero_Chasis_Vehiculo__c = stringVal(item.get('FSC_Numero_Chasis_Vehiculo__c'));
			g.FSC_Serial_Motor_Vehiculo__c = stringVal(item.get('FSC_Serial_Motor_Vehiculo__c'));
			g.FSC_Numero_Placa_Vehiculo__c = stringVal(item.get('FSC_Numero_Placa_Vehiculo__c'));
			g.FSC_Numero_Matricula__c = stringVal(item.get('FSC_Numero_Matricula__c'));
			g.FSC_Fecha_Expedicion_Vehiculo__c = dateVal(item.get('FSC_Fecha_Expedicion_Vehiculo__c'));
			g.FSC_Valor_Vehiculo__c = decimalVal(item.get('FSC_Valor_Vehiculo__c'));

			toUpsert.add(g);
			String key = stringVal(item.get('__key'));
			rowKeys.add(String.isNotBlank(key) ? key : ('idx-' + idx));
			idx++;
		}

		if (!toUpsert.isEmpty()) {
			upsert as user toUpsert;
		}

		Map<String, Id> idsByKey = new Map<String, Id>();
		for (Integer i = 0; i < toUpsert.size(); i++) {
			retainedIds.add(toUpsert[i].Id);
			idsByKey.put(rowKeys[i], toUpsert[i].Id);
		}

		List<FSC_Garantia__c> toDelete = new List<FSC_Garantia__c>();
		for (FSC_Garantia__c existing : existingRows) {
			if (!retainedIds.contains(existing.Id)) {
				toDelete.add(existing);
			}
		}
		if (!toDelete.isEmpty()) {
			delete as user toDelete;
		}
		return idsByKey;
	}

	private static Map<String, Id> syncDraftInsurances(Id rlaId, List<Map<String, Object>> incomingInsurances) {
		List<FSC_Seguro__c> existingRows = [
			SELECT Id, FSC_Tipo_de_Seguro__c
			FROM FSC_Seguro__c
			WHERE FSC_Residential_Loan_Application__c = :rlaId
			WITH USER_MODE
			ORDER BY CreatedDate ASC
		];
		Map<Id, FSC_Seguro__c> existingById = new Map<Id, FSC_Seguro__c>(existingRows);
		Map<String, FSC_Seguro__c> existingByType = new Map<String, FSC_Seguro__c>();
		for (FSC_Seguro__c ex : existingRows) {
			String typeKey = normalizeUpper(ex.FSC_Tipo_de_Seguro__c);
			if (String.isNotBlank(typeKey) && !existingByType.containsKey(typeKey)) {
				existingByType.put(typeKey, ex);
			}
		}

		List<FSC_Seguro__c> toUpsert = new List<FSC_Seguro__c>();
		List<String> rowKeys = new List<String>();
		Set<Id> retainedIds = new Set<Id>();

		Integer idx = 1;
		for (Map<String, Object> item : incomingInsurances) {
			FSC_Seguro__c s = new FSC_Seguro__c(FSC_Residential_Loan_Application__c = rlaId);
			Id incomingId = parseId(item.get('Id'), FSC_Seguro__c.SObjectType);
			String tipoSeguro = stringVal(item.get('FSC_Tipo_de_Seguro__c'));
			if (incomingId != null && existingById.containsKey(incomingId)) {
				s.Id = incomingId;
			} else if (String.isNotBlank(tipoSeguro) && existingByType.containsKey(normalizeUpper(tipoSeguro))) {
				s.Id = existingByType.get(normalizeUpper(tipoSeguro)).Id;
			}

			String nameVal = stringVal(item.get('Name'));
			if (String.isBlank(nameVal)) {
				nameVal = tipoSeguro;
			}
			s.Name = String.isNotBlank(nameVal) ? nameVal.left(80) : ('Seguro ' + idx);
			s.FSC_Tipo_de_Seguro__c = tipoSeguro;
			s.FSC_Monto_de_la_Prima__c = decimalVal(item.get('FSC_Monto_de_la_Prima__c'));
			Boolean desempleo = booleanVal(item.get('FSC_Seguro_Desempleo__c'));
			if (desempleo != null) {
				s.FSC_Seguro_Desempleo__c = desempleo;
			}
			s.FSC_Monto_Prima_Desempleo__c = decimalVal(item.get('FSC_Monto_Prima_Desempleo__c'));
			s.FSC_Fuente_de_Ingresos__c = stringVal(item.get('FSC_Fuente_de_Ingresos__c'));

			toUpsert.add(s);
			String key = stringVal(item.get('__key'));
			rowKeys.add(String.isNotBlank(key) ? key : ('idx-' + idx));
			idx++;
		}

		if (!toUpsert.isEmpty()) {
			upsert as user toUpsert;
		}

		Map<String, Id> idsByKey = new Map<String, Id>();
		for (Integer i = 0; i < toUpsert.size(); i++) {
			retainedIds.add(toUpsert[i].Id);
			idsByKey.put(rowKeys[i], toUpsert[i].Id);
		}

		List<FSC_Seguro__c> toDelete = new List<FSC_Seguro__c>();
		for (FSC_Seguro__c existing : existingRows) {
			if (!retainedIds.contains(existing.Id)) {
				toDelete.add(existing);
			}
		}
		if (!toDelete.isEmpty()) {
			delete as user toDelete;
		}
		return idsByKey;
	}

	private static ResidentialLoanApplication findSnapshotApplication(Id rlaId, Id accountId, String loanType) {
		String baseFields =
			'Id, Name, FSC_Nombre_Cliente__c, FSC_NumeroSolicitud__c, AccountId, Status, FSC_Subestado__c, RecordTypeId, RecordType.DeveloperName, ' +
			'FSC_TipoSolicitud__c, FSC_Facilidad__c, FSC_Moneda__c, FSC_PrestamoConvenio__c, FSC_Tipo_Modalidad__c, ' +
			'FSC_lineaFinanciera__c, FSC_PrestamoGarantia__c, FSC_RequiereContratoPagareNotarial__c, ' +
			'FSC_DescripcionPropositoFacilidad__c, FSC_Monto__c, FSC_Plazo_meses__c, FSC_Cuotas__c, ' +
			'FSC_TasaInteres__c, FSC_Tasa_Fija__c, FSC_TasaFijaPorMeses__c, FSC_FormaPago__c, FSC_Monto_De_La_Cuota__c, ' +
			'FSC_SolicitudMedianteReferidor__c, FSC_Referidor__c, FSC_TipoSolicitudMRI__c, FSC_TipoProductoSolicitudMRI__c, ' +
			'FSC_CanalSolicitudMRI__c, FSC_EsRefinanciamiento__c, FSC_EsConsolidacionDeudas__c, FSC_TipoDeudaCancelar__c';

		if (rlaId != null) {
			List<ResidentialLoanApplication> byId = Database.queryWithBinds(
				'SELECT ' + baseFields + ' FROM ResidentialLoanApplication WHERE Id = :targetId LIMIT 1',
				new Map<String, Object>{ 'targetId' => rlaId },
				AccessLevel.USER_MODE
			);
			return byId.isEmpty() ? null : byId[0];
		}

		if (accountId == null) {
			return null;
		}

		String rtDevName = resolveRecordTypeDeveloperName(loanType);
		String filter = 'AccountId = :accId AND Status = :borrador AND FSC_Subestado__c = :subestado';
		Map<String, Object> binds = new Map<String, Object>{
			'accId' => accountId,
			'borrador' => STATUS_BORRADOR,
			'subestado' => SUBESTADO_COMPLETANDO_INFORMACION
		};
		if (String.isNotBlank(rtDevName)) {
			filter += ' AND RecordType.DeveloperName = :rtDevName';
			binds.put('rtDevName', rtDevName);
		}
		List<ResidentialLoanApplication> byAcc = Database.queryWithBinds(
			'SELECT ' + baseFields + ' FROM ResidentialLoanApplication WHERE ' + filter + ' ORDER BY LastModifiedDate DESC LIMIT 1',
			binds,
			AccessLevel.USER_MODE
		);
		return byAcc.isEmpty() ? null : byAcc[0];
	}

	private static List<Map<String, Object>> queryFullApplicantMaps(Id rlaId) {
		List<LoanApplicant> rows = [
			SELECT
				Id,
				Name,
				FSC_TipoSolicitante__c,
				FSC_TipoIdentificacion__c,
				FSC_NumIdentificacion__c,
				FSC_Nombre__c,
				FSC_PrimerApellido__c,
				FSC_SegundoApellido__c,
				FSC_FechaNacimiento__c,
				FSC_Nacionalidad__c,
				FSC_EstadoCivil__c,
				FSC_TipoVivienda__c,
				FSC_TiempoVivienda__c,
				FSC_Ocupacion__c,
				FSC_EmpresaAnteriorLaboro__c,
				FSC_LugarFondeLabora__c,
				FSC_TiempoLaborando__c,
				FSC_FuenteIngreso__c,
				FSC_IngresosMensuales__c,
				FSC_MonedaSalario__c,
				FSC_SalarioOriginal__c,
				FSC_OtrosIngresos__c,
				FSC_OtrosIngresosOriginal__c,
				FSC_DescripcionOtrosIngresos__c,
				FSC_TotalIngresos__c,
				FSC_MontoPrestacionesLaborales__c,
				FSC_NumeroDependientes__c,
				FSC_TipoNegocio__c,
				FSC_ClasificacionSIB__c,
				(
					SELECT
						Id,
						Name,
						FSC_FirstName__c,
						FSC_LastName__c,
						FSC_TipoIdentificacion__c,
						FSC_Identificacion__c,
						FSC_Direccion__c,
						FSC_Email__c,
						FSC_Telefono__c,
						FSC_Parentesco__c,
						FSC_LugarTrabajo__c
					FROM Referencias__r
					ORDER BY CreatedDate ASC
				),
				(
					SELECT
						Id,
						Name,
						FSC_TipoFacilidad__c,
						FSC_Facilidad__c,
						FSC_DescripcionFacilidad__c,
						FSC_EntidadFinanciera__c,
						FSC_Balance__c,
						FSC_Moneda__c
					FROM FSC_Facilidades_en_Otras_Instituciones__r
					ORDER BY CreatedDate ASC
				)
			FROM LoanApplicant
			WHERE LoanApplicationId = :rlaId
			WITH USER_MODE
			ORDER BY CreatedDate ASC, Id ASC
		];

		List<Map<String, Object>> out = new List<Map<String, Object>>();
		for (LoanApplicant la : rows) {
			List<Map<String, Object>> refs = new List<Map<String, Object>>();
			for (FSC_Referencias__c ref : la.Referencias__r) {
				refs.add(
					new Map<String, Object>{
						'Id' => ref.Id,
						'Name' => ref.Name,
						'FSC_FirstName__c' => ref.FSC_FirstName__c,
						'FSC_LastName__c' => ref.FSC_LastName__c,
						'FSC_TipoIdentificacion__c' => ref.FSC_TipoIdentificacion__c,
						'FSC_Identificacion__c' => ref.FSC_Identificacion__c,
						'FSC_Direccion__c' => ref.FSC_Direccion__c,
						'FSC_Email__c' => ref.FSC_Email__c,
						'FSC_Telefono__c' => ref.FSC_Telefono__c,
						'FSC_Parentesco__c' => ref.FSC_Parentesco__c,
						'FSC_LugarTrabajo__c' => ref.FSC_LugarTrabajo__c
					}
				);
			}
			List<Map<String, Object>> exts = new List<Map<String, Object>>();
			for (FSC_Facilidad_Otra_Institucion__c ext : la.FSC_Facilidades_en_Otras_Instituciones__r) {
				exts.add(
					new Map<String, Object>{
						'Id' => ext.Id,
						'Name' => ext.Name,
						'FSC_TipoFacilidad__c' => ext.FSC_TipoFacilidad__c,
						'FSC_Facilidad__c' => ext.FSC_Facilidad__c,
						'FSC_DescripcionFacilidad__c' => ext.FSC_DescripcionFacilidad__c,
						'FSC_EntidadFinanciera__c' => ext.FSC_EntidadFinanciera__c,
						'FSC_Balance__c' => ext.FSC_Balance__c,
						'FSC_Moneda__c' => ext.FSC_Moneda__c
					}
				);
			}

			out.add(
				new Map<String, Object>{
					'Id' => la.Id,
					'Name' => la.Name,
					'FSC_TipoSolicitante__c' => la.FSC_TipoSolicitante__c,
					'FSC_TipoIdentificacion__c' => la.FSC_TipoIdentificacion__c,
					'FSC_NumIdentificacion__c' => la.FSC_NumIdentificacion__c,
					'FSC_Nombre__c' => la.FSC_Nombre__c,
					'FSC_PrimerApellido__c' => la.FSC_PrimerApellido__c,
					'FSC_SegundoApellido__c' => la.FSC_SegundoApellido__c,
					'FSC_FechaNacimiento__c' => la.FSC_FechaNacimiento__c,
					'FSC_Nacionalidad__c' => la.FSC_Nacionalidad__c,
					'FSC_EstadoCivil__c' => la.FSC_EstadoCivil__c,
					'FSC_TipoVivienda__c' => la.FSC_TipoVivienda__c,
					'FSC_TiempoVivienda__c' => la.FSC_TiempoVivienda__c,
					'FSC_Ocupacion__c' => la.FSC_Ocupacion__c,
					'FSC_EmpresaAnteriorLaboro__c' => la.FSC_EmpresaAnteriorLaboro__c,
					'FSC_LugarFondeLabora__c' => la.FSC_LugarFondeLabora__c,
					'FSC_TiempoLaborando__c' => la.FSC_TiempoLaborando__c,
					'FSC_FuenteIngreso__c' => la.FSC_FuenteIngreso__c,
					'FSC_IngresosMensuales__c' => la.FSC_IngresosMensuales__c,
					'FSC_MonedaSalario__c' => la.FSC_MonedaSalario__c,
					'FSC_SalarioOriginal__c' => la.FSC_SalarioOriginal__c,
					'FSC_OtrosIngresos__c' => la.FSC_OtrosIngresos__c,
					'FSC_OtrosIngresosOriginal__c' => la.FSC_OtrosIngresosOriginal__c,
					'FSC_DescripcionOtrosIngresos__c' => la.FSC_DescripcionOtrosIngresos__c,
					'FSC_TotalIngresos__c' => la.FSC_TotalIngresos__c,
					'FSC_MontoPrestacionesLaborales__c' => la.FSC_MontoPrestacionesLaborales__c,
					'FSC_NumeroDependientes__c' => la.FSC_NumeroDependientes__c,
					'FSC_TipoNegocio__c' => la.FSC_TipoNegocio__c,
					'FSC_ClasificacionSIB__c' => la.FSC_ClasificacionSIB__c,
					'FSC_Referencias__c' => refs,
					'FSC_Facilidad_Otra_Institucion__c' => exts
				}
			);
		}
		return out;
	}

	private static List<Map<String, Object>> queryFullGuaranteeMaps(Id rlaId) {
		List<FSC_Garantia__c> rows = [
			SELECT
				Id,
				Name,
				FSC_MonedaGarantia__c,
				FSC_Clase_de_Garantia__c,
				FSC_Tipo_de_Garantia__c,
				FSC_Descripcion_de_la_Garantia__c,
				FSC_Proposito_Garantia_Hipotecario__c,
				FSC_Valor_Tasado__c,
				FSC_Valor_Mejoras__c,
				FSC_SaldoPrimeraHipoteca__c,
				FSC_EsTasadorExterno__c,
				FSC_NombreTasadorExterno__c,
				FSC_Tasado_Por__c,
				FSC_Fecha_Tasacion__c,
				FSC_Monto_Inicial_Avance_Pagado__c,
				FSC_Valor_Inmueble__c,
				FSC_Precio_de_Venta__c,
				FSC_Metros_Cuadrados_de_Construccion__c,
				FSC_Ubicacion__c,
				FSC_Tipo_de_Inmueble__c,
				FSC_Es_Concesionario_Dealer__c,
				FSC_Concesionario__c,
				FSC_Marca_Vehiculo__c,
				FSC_Modelo_Vehiculo__c,
				FSC_Ano_Vehiculo__c,
				FSC_Color_Vehiculo__c,
				FSC_Numero_Chasis_Vehiculo__c,
				FSC_Serial_Motor_Vehiculo__c,
				FSC_Numero_Placa_Vehiculo__c,
				FSC_Numero_Matricula__c,
				FSC_Fecha_Expedicion_Vehiculo__c,
				FSC_Valor_Vehiculo__c
			FROM FSC_Garantia__c
			WHERE FSC_Residential_Loan_Application__c = :rlaId
			WITH USER_MODE
			ORDER BY CreatedDate ASC, Id ASC
		];
		List<Map<String, Object>> out = new List<Map<String, Object>>();
		for (FSC_Garantia__c g : rows) {
			out.add(
				new Map<String, Object>{
					'Id' => g.Id,
					'__key' => String.valueOf(g.Id),
					'Name' => g.Name,
					'FSC_MonedaGarantia__c' => g.FSC_MonedaGarantia__c,
					'FSC_Clase_de_Garantia__c' => g.FSC_Clase_de_Garantia__c,
					'FSC_Tipo_de_Garantia__c' => g.FSC_Tipo_de_Garantia__c,
					'FSC_Descripcion_de_la_Garantia__c' => g.FSC_Descripcion_de_la_Garantia__c,
					'FSC_Proposito_Garantia_Hipotecario__c' => g.FSC_Proposito_Garantia_Hipotecario__c,
					'FSC_Valor_Tasado__c' => g.FSC_Valor_Tasado__c,
					'FSC_Valor_Mejoras__c' => g.FSC_Valor_Mejoras__c,
					'FSC_SaldoPrimeraHipoteca__c' => g.FSC_SaldoPrimeraHipoteca__c,
					'FSC_EsTasadorExterno__c' => g.FSC_EsTasadorExterno__c,
					'FSC_NombreTasadorExterno__c' => g.FSC_NombreTasadorExterno__c,
					'FSC_Tasado_Por__c' => g.FSC_Tasado_Por__c,
					'FSC_Fecha_Tasacion__c' => g.FSC_Fecha_Tasacion__c,
					'FSC_Monto_Inicial_Avance_Pagado__c' => g.FSC_Monto_Inicial_Avance_Pagado__c,
					'FSC_Valor_Inmueble__c' => g.FSC_Valor_Inmueble__c,
					'FSC_Precio_de_Venta__c' => g.FSC_Precio_de_Venta__c,
					'FSC_Metros_Cuadrados_de_Construccion__c' => g.FSC_Metros_Cuadrados_de_Construccion__c,
					'FSC_Ubicacion__c' => g.FSC_Ubicacion__c,
					'FSC_Tipo_de_Inmueble__c' => g.FSC_Tipo_de_Inmueble__c,
					'FSC_Es_Concesionario_Dealer__c' => g.FSC_Es_Concesionario_Dealer__c,
					'FSC_Concesionario__c' => g.FSC_Concesionario__c,
					'FSC_Marca_Vehiculo__c' => g.FSC_Marca_Vehiculo__c,
					'FSC_Modelo_Vehiculo__c' => g.FSC_Modelo_Vehiculo__c,
					'FSC_Ano_Vehiculo__c' => g.FSC_Ano_Vehiculo__c,
					'FSC_Color_Vehiculo__c' => g.FSC_Color_Vehiculo__c,
					'FSC_Numero_Chasis_Vehiculo__c' => g.FSC_Numero_Chasis_Vehiculo__c,
					'FSC_Serial_Motor_Vehiculo__c' => g.FSC_Serial_Motor_Vehiculo__c,
					'FSC_Numero_Placa_Vehiculo__c' => g.FSC_Numero_Placa_Vehiculo__c,
					'FSC_Numero_Matricula__c' => g.FSC_Numero_Matricula__c,
					'FSC_Fecha_Expedicion_Vehiculo__c' => g.FSC_Fecha_Expedicion_Vehiculo__c,
					'FSC_Valor_Vehiculo__c' => g.FSC_Valor_Vehiculo__c
				}
			);
		}
		return out;
	}

	private static List<Map<String, Object>> queryFullInsuranceMaps(Id rlaId) {
		List<FSC_Seguro__c> rows = [
			SELECT
				Id,
				Name,
				FSC_Tipo_de_Seguro__c,
				FSC_Monto_de_la_Prima__c,
				FSC_Seguro_Desempleo__c,
				FSC_Monto_Prima_Desempleo__c,
				FSC_Fuente_de_Ingresos__c
			FROM FSC_Seguro__c
			WHERE FSC_Residential_Loan_Application__c = :rlaId
			WITH USER_MODE
			ORDER BY CreatedDate ASC, Id ASC
		];
		List<Map<String, Object>> out = new List<Map<String, Object>>();
		for (FSC_Seguro__c s : rows) {
			out.add(
				new Map<String, Object>{
					'Id' => s.Id,
					'__key' => String.valueOf(s.Id),
					'Name' => s.Name,
					'FSC_Tipo_de_Seguro__c' => s.FSC_Tipo_de_Seguro__c,
					'FSC_Monto_de_la_Prima__c' => s.FSC_Monto_de_la_Prima__c,
					'FSC_Seguro_Desempleo__c' => s.FSC_Seguro_Desempleo__c,
					'FSC_Monto_Prima_Desempleo__c' => s.FSC_Monto_Prima_Desempleo__c,
					'FSC_Fuente_de_Ingresos__c' => s.FSC_Fuente_de_Ingresos__c
				}
			);
		}
		return out;
	}

	private static Map<String, Object> buildFacilityFromApplication(
		ResidentialLoanApplication rla,
		List<Map<String, Object>> guarantees,
		List<Map<String, Object>> insurances
	) {
		String rtName = rla.RecordType?.DeveloperName;
		Boolean isHipotecario = rtName == 'FSC_Solicitud_Credito_Hipotecario';
		Boolean isVehiculo = rtName == 'FSC_Solicitud_Credito_Vehiculo';

		Boolean hasAnyFacilityData =
			!guarantees.isEmpty() ||
			!insurances.isEmpty() ||
			rla.FSC_Monto__c != null ||
			String.isNotBlank(rla.FSC_Plazo_meses__c) ||
			rla.FSC_TasaInteres__c != null ||
			String.isNotBlank(rla.FSC_DescripcionPropositoFacilidad__c) ||
			String.isNotBlank(rla.FSC_Facilidad__c);

		if (!hasAnyFacilityData) {
			return null;
		}

		String tipoFacilidad = TIPO_FACILIDAD_BPR;
		String facilidad = FACILIDAD_CONSUMO_DEFAULT;
		if (isHipotecario) {
			facilidad = rla.FSC_Moneda__c == '2' ? FACILIDAD_HIPOTECARIO_USD : FACILIDAD_HIPOTECARIO_DOP;
		}

		String estadoVehiculo = null;
		if (isVehiculo && !guarantees.isEmpty()) {
			String clase = normalizeUpper(stringVal(guarantees[0].get('FSC_Clase_de_Garantia__c')));
			estadoVehiculo = clase.contains('NUEVO') ? 'Nuevos' : 'Usados';
		}

		return new Map<String, Object>{
			'__key' => 'facilidad-' + rla.Id,
			'FSC_Tipo_Facilidad__c' => tipoFacilidad,
			'FSC_Tipo_de_Facilidad__c' => tipoFacilidad,
			'FSC_Facilidad__c' => facilidad,
			'FSC_EstadoDelVehiculo__c' => estadoVehiculo,
			'FSC_Prestamo_Convenio__c' => rla.FSC_PrestamoConvenio__c,
			'FSC_Tipo_Modalidad__c' => rla.FSC_Tipo_Modalidad__c,
			'FSC_Lineas_Financieras_Empresas__c' => rla.FSC_lineaFinanciera__c,
			'FSC_Prestamo_Con_Garantia__c' => (isHipotecario || isVehiculo || !guarantees.isEmpty()) ? true : rla.FSC_PrestamoGarantia__c,
			'FSC_Requiere_Contrato_Pagare_Notarial__c' => isHipotecario ? true : rla.FSC_RequiereContratoPagareNotarial__c,
			'FSC_Descripcion_Proposito_Facilidad__c' => rla.FSC_DescripcionPropositoFacilidad__c,
			'FSC_Monto_Solicitado__c' => rla.FSC_Monto__c,
			'FSC_Plazo_meses__c' => rla.FSC_Plazo_meses__c,
			'FSC_Tasa_Interes__c' => rla.FSC_TasaInteres__c,
			'FSC_Tasa_Fija__c' => rla.FSC_Tasa_Fija__c,
			'FSC_Tiempo_Tasa_Fija__c' => rla.FSC_TasaFijaPorMeses__c,
			'FSC_Forma_De_Pago__c' => rla.FSC_FormaPago__c,
			'FSC_Monto_De_La_Cuota__c' => rla.FSC_Monto_De_La_Cuota__c,
			'FSC_Moneda__c' => String.isNotBlank(rla.FSC_Moneda__c) ? rla.FSC_Moneda__c : '1',
			'FSC_Garantias__r' => guarantees,
			'FSC_Seguros__r' => insurances
		};
	}

	private static Map<String, Object> buildGeneralStepFromApplication(ResidentialLoanApplication rla, Map<String, Object> facility) {
		Map<String, Object> step = new Map<String, Object>();
		if (rla.FSC_SolicitudMedianteReferidor__c != null) {
			step.put('FSC_SolicitudMedianteReferidor__c', rla.FSC_SolicitudMedianteReferidor__c);
		}
		if (String.isNotBlank(rla.FSC_Referidor__c)) {
			step.put('FSC_Referidor__c', rla.FSC_Referidor__c);
		}
		if (String.isNotBlank(rla.FSC_TipoSolicitudMRI__c)) {
			step.put('FSC_TipoSolicitudMRI__c', rla.FSC_TipoSolicitudMRI__c);
		}
		if (String.isNotBlank(rla.FSC_TipoProductoSolicitudMRI__c)) {
			step.put('FSC_TipoProductoSolicitudMRI__c', rla.FSC_TipoProductoSolicitudMRI__c);
		}
		if (String.isNotBlank(rla.FSC_CanalSolicitudMRI__c)) {
			step.put('FSC_CanalSolicitudMRI__c', rla.FSC_CanalSolicitudMRI__c);
		}
		if (rla.FSC_EsRefinanciamiento__c != null) {
			step.put('FSC_EsRefinanciamiento__c', rla.FSC_EsRefinanciamiento__c);
		}
		if (rla.FSC_EsConsolidacionDeudas__c != null) {
			step.put('FSC_EsConsolidacionDeudas__c', rla.FSC_EsConsolidacionDeudas__c);
		}
		if (String.isNotBlank(rla.FSC_TipoDeudaCancelar__c)) {
			step.put('FSC_TipoDeudaCancelar__c', rla.FSC_TipoDeudaCancelar__c);
		}
		if (facility != null) {
			step.put('FSC_Facilidades_De_Credito__c', new List<Map<String, Object>>{ facility });
		}
		return step;
	}

	public static String resolveRecordTypeDeveloperName(String loanType) {
		String norm = normalizeUpper(loanType);
		if (norm.contains('HIPOTECARIO')) {
			return 'FSC_Solicitud_Credito_Hipotecario';
		}
		if (norm.contains('VEHICULO') || norm.contains('VEHICULAR')) {
			return 'FSC_Solicitud_Credito_Vehiculo';
		}
		if (norm.contains('PYME')) {
			return 'FSC_Solicitud_Credito_PYME';
		}
		if (norm.contains('COMERCIAL')) {
			return 'FSC_Solicitud_Credito_Comercial';
		}
		if (norm.contains('CONSUMO')) {
			return 'FSC_Solicitud_Credito_Consumo';
		}
		return '';
	}

	private static String buildTitlePrefix(String rtDevName) {
		if (rtDevName == 'FSC_Solicitud_Credito_Hipotecario') {
			return 'Crédito Hipotecario';
		}
		if (rtDevName == 'FSC_Solicitud_Credito_Vehiculo') {
			return 'Crédito Vehiculo';
		}
		if (rtDevName == 'FSC_Solicitud_Credito_PYME') {
			return 'Crédito PyMe';
		}
		return 'Crédito Consumo';
	}

	private static String buildGuaranteeSummary(List<FSC_Garantia__c> garantias) {
		if (garantias == null || garantias.isEmpty()) {
			return '';
		}
		FSC_Garantia__c first = garantias[0];
		List<String> parts = new List<String>();
		if (String.isNotBlank(first.FSC_Tipo_de_Garantia__c)) {
			parts.add(first.FSC_Tipo_de_Garantia__c);
		} else if (String.isNotBlank(first.FSC_Clase_de_Garantia__c)) {
			parts.add(first.FSC_Clase_de_Garantia__c);
		}
		if (String.isNotBlank(first.FSC_Ubicacion__c)) {
			parts.add(first.FSC_Ubicacion__c);
		} else if (String.isNotBlank(first.FSC_Marca_Vehiculo__c)) {
			parts.add(
				joinParts(
					new List<String>{
						first.FSC_Marca_Vehiculo__c,
						first.FSC_Modelo_Vehiculo__c,
						first.FSC_Ano_Vehiculo__c == null ? null : String.valueOf(first.FSC_Ano_Vehiculo__c.intValue())
					},
					' '
				)
			);
		} else if (String.isNotBlank(first.FSC_Descripcion_de_la_Garantia__c)) {
			parts.add(first.FSC_Descripcion_de_la_Garantia__c.left(60));
		}
		return joinParts(parts, ' · ');
	}

	private static String guaranteeSignature(FSC_Garantia__c g) {
		return normalizeUpper(g.FSC_Clase_de_Garantia__c) +
			'|' +
			normalizeUpper(g.FSC_Tipo_de_Garantia__c) +
			'|' +
			normalizeUpper(g.FSC_Proposito_Garantia_Hipotecario__c) +
			'|' +
			normalizeUpper(g.FSC_Ubicacion__c) +
			'|' +
			String.valueOf(g.FSC_Valor_Inmueble__c == null ? null : g.FSC_Valor_Inmueble__c.setScale(2)) +
			'|' +
			String.valueOf(g.FSC_Precio_de_Venta__c == null ? null : g.FSC_Precio_de_Venta__c.setScale(2)) +
			'|' +
			normalizeUpper(g.FSC_Numero_Chasis_Vehiculo__c) +
			'|' +
			normalizeUpper(g.FSC_Marca_Vehiculo__c) +
			'|' +
			normalizeUpper(g.FSC_Modelo_Vehiculo__c) +
			'|' +
			normalizeUpper(g.FSC_Descripcion_de_la_Garantia__c);
	}

	private static Id resolveAccountId(Id accountId, Id rlaId) {
		if (accountId != null && accountId.getSObjectType() == Account.SObjectType) {
			return accountId;
		}
		if (rlaId != null && rlaId.getSObjectType() == ResidentialLoanApplication.SObjectType) {
			List<ResidentialLoanApplication> rlas = [
				SELECT AccountId
				FROM ResidentialLoanApplication
				WHERE Id = :rlaId
				WITH SYSTEM_MODE
				LIMIT 1
			];
			return rlas.isEmpty() ? null : rlas[0].AccountId;
		}
		return null;
	}

	private static String applicantDocKey(String tipo, String numero) {
		if (String.isBlank(tipo) || String.isBlank(numero)) {
			return '';
		}
		return normalizeUpper(tipo) + ':' + numero.replaceAll('[^A-Za-z0-9]', '').toUpperCase();
	}

	private static List<Object> parseJsonList(String jsonStr) {
		if (String.isBlank(jsonStr)) {
			return new List<Object>();
		}
		Object raw = JSON.deserializeUntyped(jsonStr);
		if (raw instanceof List<Object>) {
			return (List<Object>) raw;
		}
		if (raw instanceof Map<String, Object>) {
			return new List<Object>{ raw };
		}
		return new List<Object>();
	}

	private static Map<String, Object> parseJsonMap(String jsonStr) {
		if (String.isBlank(jsonStr)) {
			return new Map<String, Object>();
		}
		Object raw = JSON.deserializeUntyped(jsonStr);
		if (raw instanceof Map<String, Object>) {
			return (Map<String, Object>) raw;
		}
		if (raw instanceof List<Object>) {
			List<Object> items = (List<Object>) raw;
			if (!items.isEmpty() && items[0] instanceof Map<String, Object>) {
				return (Map<String, Object>) items[0];
			}
		}
		return new Map<String, Object>();
	}

	private static List<Map<String, Object>> extractChildList(Map<String, Object> source, String key) {
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		if (source == null || !source.containsKey(key) || source.get(key) == null) {
			return rows;
		}
		Object raw = source.get(key);
		if (raw instanceof Map<String, Object>) {
			Map<String, Object> asMap = (Map<String, Object>) raw;
			if (asMap.containsKey('records') && asMap.get('records') instanceof List<Object>) {
				raw = asMap.get('records');
			} else {
				rows.add(asMap);
				return rows;
			}
		}
		if (raw instanceof List<Object>) {
			for (Object el : (List<Object>) raw) {
				if (el instanceof Map<String, Object>) {
					rows.add((Map<String, Object>) el);
				}
			}
		}
		return rows;
	}

	private static Id parseId(Object raw, Schema.SObjectType expectedType) {
		String val = stringVal(raw);
		if (String.isBlank(val)) {
			return null;
		}
		try {
			Id parsed = Id.valueOf(val);
			return parsed.getSObjectType() == expectedType ? parsed : null;
		} catch (Exception ex) {
			return null;
		}
	}

	private static String stringVal(Object raw) {
		if (raw == null) {
			return null;
		}
		String s = String.valueOf(raw).trim();
		return String.isBlank(s) ? null : s;
	}

	private static Decimal decimalVal(Object raw) {
		String s = stringVal(raw);
		if (s == null) {
			return null;
		}
		try {
			return Decimal.valueOf(s.replace(',', ''));
		} catch (Exception ex) {
			return null;
		}
	}

	private static Date dateVal(Object raw) {
		String s = stringVal(raw);
		if (s == null) {
			return null;
		}
		try {
			return Date.valueOf(s.contains('T') ? s.split('T')[0] : s);
		} catch (Exception ex) {
			return null;
		}
	}

	private static Boolean booleanVal(Object raw) {
		if (raw == null) {
			return null;
		}
		if (raw instanceof Boolean) {
			return (Boolean) raw;
		}
		String norm = normalizeUpper(String.valueOf(raw));
		if (norm == 'TRUE' || norm == 'SI' || norm == 'YES' || norm == '1') {
			return true;
		}
		if (norm == 'FALSE' || norm == 'NO' || norm == '0') {
			return false;
		}
		return null;
	}

	private static String normalizeUpper(String val) {
		if (String.isBlank(val)) {
			return '';
		}
		return val.trim()
			.toUpperCase()
			.replace('Á', 'A')
			.replace('É', 'E')
			.replace('Í', 'I')
			.replace('Ó', 'O')
			.replace('Ú', 'U')
			.replace('Ü', 'U');
	}

	private static String normalizeDigits(String val) {
		return String.isBlank(val) ? '' : val.replaceAll('[^0-9]', '');
	}

	private static String joinParts(List<String> parts, String sep) {
		List<String> clean = new List<String>();
		for (String p : parts) {
			if (String.isNotBlank(p)) {
				clean.add(p.trim());
			}
		}
		return String.join(clean, sep);
	}

	private static AuraHandledException handledError(String message) {
		AuraHandledException err = new AuraHandledException(message);
		err.setMessage(message);
		return err;
	}
}
