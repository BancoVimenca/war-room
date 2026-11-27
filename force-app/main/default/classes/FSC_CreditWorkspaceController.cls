public with sharing class FSC_CreditWorkspaceController {

	public class WorkspaceMetrics {
		@AuraEnabled public Integer misPendientesDirectos { get; set; }
		@AuraEnabled public Integer excepcionesActivas { get; set; }
		@AuraEnabled public Integer enRecepcion { get; set; }
		@AuraEnabled public Integer enAnalisis { get; set; }
		@AuraEnabled public Integer comiteSupervision { get; set; }
		@AuraEnabled public Integer formalizacionCustodia { get; set; }
		@AuraEnabled public Decimal montoTotalCartera { get; set; }
		@AuraEnabled public Decimal montoGanado { get; set; }
		@AuraEnabled public Decimal montoPerdido { get; set; }
		@AuraEnabled public Boolean isAdministrator { get; set; }
		@AuraEnabled public Boolean canGenerateActasComite { get; set; }

		public WorkspaceMetrics() {
			this.misPendientesDirectos = 0;
			this.excepcionesActivas = 0;
			this.enRecepcion = 0;
			this.enAnalisis = 0;
			this.comiteSupervision = 0;
			this.formalizacionCustodia = 0;
			this.montoTotalCartera = 0.0;
			this.montoGanado = 0.0;
			this.montoPerdido = 0.0;
			this.isAdministrator = false;
			this.canGenerateActasComite = false;
		}
	}

	public class CreditApplicationRow {
		@AuraEnabled public Id recordId { get; set; }
		@AuraEnabled public String numeroSolicitud { get; set; }
		@AuraEnabled public String name { get; set; }
		@AuraEnabled public String recordUrl { get; set; }
		@AuraEnabled public String accountId { get; set; }
		@AuraEnabled public String accountName { get; set; }
		@AuraEnabled public String productType { get; set; }
		@AuraEnabled public Decimal monto { get; set; }
		@AuraEnabled public String status { get; set; }
		@AuraEnabled public String subestado { get; set; }
		@AuraEnabled public String ownerName { get; set; }
		@AuraEnabled public Datetime createdDate { get; set; }
		@AuraEnabled public Datetime fechaSubestado { get; set; }
		@AuraEnabled public Boolean tieneExcepcion { get; set; }
		@AuraEnabled public String detalleExcepcion { get; set; }
		@AuraEnabled public String turnoActual { get; set; }
		@AuraEnabled public Boolean esAccionablePorUsuario { get; set; }
		@AuraEnabled public Id workitemId { get; set; }
		@AuraEnabled public String processName { get; set; }
		@AuraEnabled public Boolean canApprove { get; set; }
	}

	private static final Set<String> QUEUES_ANALISIS = new Set<String>{
		'FSC_ColaAnalistasDeCredito', 'FSC_Cola_Excepcion_Buro',
		'FSC_ColaAnalistasDeCredito_Consumo', 'FSC_ColaAnalistasDeCredito_Hipotecario',
		'FSC_ColaAnalistasDeCredito_PYME', 'FSC_ColaAnalistasDeCredito_Vehiculo'
	};

	private static final Set<String> QUEUES_EXCEPCIONES = new Set<String>{
		'FSC_Cola_Excepcion_Buro', 'FSC_VPNegociosBancaPersona',
		'FSC_VPNegociosBancaEmpresarial', 'FSC_VPCreditoRecuperacion'
	};

	private static final Set<String> QUEUES_COMITE = new Set<String>{
		'FSC_ColaSupervisores', 'FSC_ColaComiteI', 'FSC_ColaComiteII', 'FSC_ColaComiteIII'
	};

	private static final Set<String> QUEUES_FORMALIZACION = new Set<String>{
		'FSC_GestionDePagaresYContratos', 'FSC_GestionFormalizacion',
		'FSC_Cola_Archivo_y_custodia_de_valores', 'FSC_GestionPlanillasDeDesembolso'
	};

	@AuraEnabled(cacheable=true)
	public static WorkspaceMetrics getWorkspaceMetrics(String simulatedRole) {
		WorkspaceMetrics metrics = new WorkspaceMetrics();
		Id currentUserId = UserInfo.getUserId();
		Boolean isAdmin = checkIsAdminUser();
		metrics.isAdministrator = isAdmin;

		String effectiveRole = (isAdmin && String.isNotBlank(simulatedRole)) ? simulatedRole : 'REAL_USER';
		metrics.canGenerateActasComite = checkCanGenerateActasComite(currentUserId, isAdmin, effectiveRole);
		Set<Id> targetActorIds = resolveTargetActorIds(currentUserId, effectiveRole);

		// 1. Mapear excepciones de crédito activas (FSC_Excepcion__c) y vincular con solicitud principal
		Map<Id, Id> solicitudIdByExcepcionId = new Map<Id, Id>();
		Set<Id> solicitudesConExcepcionHija = new Set<Id>();
		for (FSC_Excepcion__c exc : [
			SELECT Id, FSC_Solicitud_Prestamo__c
			FROM FSC_Excepcion__c
			WHERE FSC_Estado__c = 'Pendiente'
			WITH USER_MODE
			LIMIT 500
		]) {
			if (exc.FSC_Solicitud_Prestamo__c != null) {
				solicitudIdByExcepcionId.put(exc.Id, exc.FSC_Solicitud_Prestamo__c);
				solicitudesConExcepcionHija.add(exc.FSC_Solicitud_Prestamo__c);
			}
		}

		// 2. Pendientes directos vía ProcessInstanceWorkitem
		Set<Id> userActionableRlaIds = new Set<Id>();
		for (ProcessInstanceWorkitem item : [
			SELECT Id, ProcessInstance.TargetObjectId, ActorId
			FROM ProcessInstanceWorkitem
			WITH SYSTEM_MODE
			LIMIT 1000
		]) {
			Id targetId = item.ProcessInstance.TargetObjectId;
			Id rlaId = solicitudIdByExcepcionId.containsKey(targetId) ? solicitudIdByExcepcionId.get(targetId) : targetId;
			if (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(item.ActorId)) {
				userActionableRlaIds.add(rlaId);
			}
		}

		// 3. Consultar Solicitudes activas para métricas
		// Se evalúan 'En proceso' más aquellas con aprobaciones pendientes directas para el usuario (incluso en Borrador)
		List<ResidentialLoanApplication> solicitudesActivas = [
			SELECT Id, Status, FSC_Subestado__c, FSC_Monto__c, FSC_SolicitaExcepcionParaRechazoDeBuro__c,
			       FSC_DebeRevisarComite__c, FSC_DebeRevisarSupervisor__c, OwnerId,
			       FSC_UsuarioAnalista__c, FSC_UsuarioSupervisor__c, FSC_UsuarioComite__c,
			       FSC_UsuarioFormalizacion__c, FSC_UsuarioPagaresYContratos__c, FSC_UsuarioGestionPlanilla__c
			FROM ResidentialLoanApplication
			WHERE Status = 'En proceso' OR Id IN :userActionableRlaIds
			WITH USER_MODE
			LIMIT 1000
		];

		Decimal sumaMonto = 0;
		for (ResidentialLoanApplication rla : solicitudesActivas) {
			if (rla.FSC_Monto__c != null) {
				sumaMonto += rla.FSC_Monto__c;
			}

			// Excepciones (Buró o Hijas)
			Boolean tieneExc = (rla.FSC_SolicitaExcepcionParaRechazoDeBuro__c == true || solicitudesConExcepcionHija.contains(rla.Id));
			if (tieneExc) {
				metrics.excepcionesActivas++;
			}

			// Directo / Mis Pendientes
			Boolean isDirectActionable = userActionableRlaIds.contains(rla.Id);
			if (!isDirectActionable) {
				String sub = rla.FSC_Subestado__c;
				if (effectiveRole == 'ADMIN_ALL') {
					isDirectActionable = true;
				} else if (rla.OwnerId == currentUserId && (sub == 'En Motor Buró' || sub == 'En validación PEP/Listas' || sub == 'Recepción de documentos – Análisis' || sub == 'Gestionar firmas')) {
					isDirectActionable = true;
				} else if (targetActorIds.contains(rla.FSC_UsuarioAnalista__c) && sub == 'Análisis de crédito') {
					isDirectActionable = true;
				} else if (targetActorIds.contains(rla.FSC_UsuarioSupervisor__c) && rla.FSC_DebeRevisarSupervisor__c == true) {
					isDirectActionable = true;
				} else if (targetActorIds.contains(rla.FSC_UsuarioComite__c) && rla.FSC_DebeRevisarComite__c == true) {
					isDirectActionable = true;
				} else if (targetActorIds.contains(rla.FSC_UsuarioPagaresYContratos__c) && (sub == 'Generación de pagarés y plantillas' || sub == 'Generación de contrato' || sub == 'Documentación para contratos')) {
					isDirectActionable = true;
				} else if (targetActorIds.contains(rla.FSC_UsuarioFormalizacion__c) && (sub == 'Gestionar firmas' || sub == 'Formalización')) {
					isDirectActionable = true;
				} else if (targetActorIds.contains(rla.FSC_UsuarioGestionPlanilla__c) && (sub == 'Recepción Docs Desembolso' || sub == 'Archivo y custodia')) {
					isDirectActionable = true;
				}
			}

			if (isDirectActionable) {
				metrics.misPendientesDirectos++;
			}

			// Etapa Recepción, Buró y PEP
			if (rla.FSC_Subestado__c == 'Recepción de documentos – Análisis' ||
			    rla.FSC_Subestado__c == 'En validación PEP/Listas' ||
			    rla.FSC_Subestado__c == 'En Motor Buró') {
				metrics.enRecepcion++;
			}

			// Etapa Análisis de Crédito (exclusiva)
			if (rla.FSC_Subestado__c == 'Análisis de crédito') {
				metrics.enAnalisis++;
			}

			// Comité / Supervisión
			if (rla.FSC_DebeRevisarComite__c == true || rla.FSC_DebeRevisarSupervisor__c == true) {
				metrics.comiteSupervision++;
			}

			// Formalización y Custodia
			if (rla.FSC_Subestado__c == 'Generación de pagarés y plantillas' ||
			    rla.FSC_Subestado__c == 'Gestionar firmas' ||
			    rla.FSC_Subestado__c == 'Archivo y custodia') {
				metrics.formalizacionCustodia++;
			}
		}

		// 3. Montos por estado (En Proceso, Ganado, Perdido)
		Decimal sumaMontoEnProceso = 0.0;
		Decimal sumaMontoGanado = 0.0;
		Decimal sumaMontoPerdido = 0.0;

		List<ResidentialLoanApplication> todasSolicitudes = [
			SELECT Id, FSC_Monto__c, Status
			FROM ResidentialLoanApplication
			WITH USER_MODE
			LIMIT 1000
		];

		for (ResidentialLoanApplication r : todasSolicitudes) {
			Decimal m = r.FSC_Monto__c != null ? r.FSC_Monto__c : 0.0;
			if (r.Status == 'En proceso') {
				sumaMontoEnProceso += m;
			} else if (r.Status == 'Cerrada Ganada') {
				sumaMontoGanado += m;
			} else if (r.Status == 'Cerrada Perdida') {
				sumaMontoPerdido += m;
			}
		}

		metrics.montoTotalCartera = sumaMontoEnProceso;
		metrics.montoGanado = sumaMontoGanado;
		metrics.montoPerdido = sumaMontoPerdido;
		return metrics;
	}

	@AuraEnabled(cacheable=true)
	public static List<CreditApplicationRow> getCreditApplications(String tabName, String searchKey, String simulatedRole) {
		List<CreditApplicationRow> rows = new List<CreditApplicationRow>();
		Id currentUserId = UserInfo.getUserId();
		Boolean isAdmin = checkIsAdminUser();
		String effectiveRole = (isAdmin && String.isNotBlank(simulatedRole)) ? simulatedRole : 'REAL_USER';

		Set<Id> targetActorIds = resolveTargetActorIds(currentUserId, effectiveRole);

		// Mapear excepciones de crédito pendientes (FSC_Excepcion__c) y relacionar con la solicitud
		Map<Id, List<FSC_Excepcion__c>> excepcionesBySolicitud = new Map<Id, List<FSC_Excepcion__c>>();
		Map<Id, Id> solicitudIdByExcepcionId = new Map<Id, Id>();
		for (FSC_Excepcion__c exc : [
			SELECT Id, FSC_Solicitud_Prestamo__c, FSC_Tipo__c, FSC_Detalle__c, FSC_Estado__c
			FROM FSC_Excepcion__c
			WHERE FSC_Estado__c = 'Pendiente'
			WITH USER_MODE
			LIMIT 1000
		]) {
			if (exc.FSC_Solicitud_Prestamo__c != null) {
				solicitudIdByExcepcionId.put(exc.Id, exc.FSC_Solicitud_Prestamo__c);
				if (!excepcionesBySolicitud.containsKey(exc.FSC_Solicitud_Prestamo__c)) {
					excepcionesBySolicitud.put(exc.FSC_Solicitud_Prestamo__c, new List<FSC_Excepcion__c>());
				}
				excepcionesBySolicitud.get(exc.FSC_Solicitud_Prestamo__c).add(exc);
			}
		}

		// Mapear aprobaciones activas por TargetObjectId (RLA o Excepción)
		// Priorizar siempre el ítem donde el actor coincida con los grupos/usuario del usuario en sesión
		Map<Id, ProcessInstanceWorkitem> workitemsByTarget = new Map<Id, ProcessInstanceWorkitem>();
		Set<Id> userActionableRlaIds = new Set<Id>();
		Set<Id> allApprovalRlaIds = new Set<Id>();

		for (ProcessInstanceWorkitem item : [
			SELECT Id, ProcessInstance.TargetObjectId, ProcessInstance.ProcessDefinition.Name, Actor.Name, OriginalActor.Name, ActorId
			FROM ProcessInstanceWorkitem
			WITH SYSTEM_MODE
			LIMIT 1000
		]) {
			Id targetId = item.ProcessInstance.TargetObjectId;
			Id rlaId = solicitudIdByExcepcionId.containsKey(targetId) ? solicitudIdByExcepcionId.get(targetId) : targetId;
			allApprovalRlaIds.add(rlaId);

			if (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(item.ActorId)) {
				userActionableRlaIds.add(rlaId);
			}

			// Prioridad de mapeo para mostrar el actor en la tabla
			if (!workitemsByTarget.containsKey(rlaId) || targetActorIds.contains(item.ActorId)) {
				workitemsByTarget.put(rlaId, item);
			}
			if (targetId != rlaId && (!workitemsByTarget.containsKey(targetId) || targetActorIds.contains(item.ActorId))) {
				workitemsByTarget.put(targetId, item);
			}
		}

		String query = 'SELECT Id, Name, FSC_NumeroSolicitud__c, AccountId, Account.Name, RecordType.Name, FSC_Monto__c, ' +
		               'Status, FSC_Subestado__c, OwnerId, Owner.Name, CreatedDate, ' +
		               'FSC_SolicitaExcepcionParaRechazoDeBuro__c, FSC_DebeRevisarComite__c, FSC_DebeRevisarSupervisor__c, ' +
		               'FSC_UsuarioAnalista__c, FSC_UsuarioAnalista__r.Name, ' +
		               'FSC_UsuarioSupervisor__c, FSC_UsuarioSupervisor__r.Name, ' +
		               'FSC_UsuarioComite__c, FSC_UsuarioComite__r.Name, ' +
		               'FSC_UsuarioPagaresYContratos__c, FSC_UsuarioPagaresYContratos__r.Name, ' +
		               'FSC_UsuarioFormalizacion__c, FSC_UsuarioFormalizacion__r.Name, ' +
		               'FSC_UsuarioGestionPlanilla__c, FSC_UsuarioGestionPlanilla__r.Name ' +
		               'FROM ResidentialLoanApplication WHERE Status != null ';

		Set<Id> targetExceptionRlaIds = excepcionesBySolicitud.keySet();

		String filterCondition = '';
		if (tabName == 'aprobaciones') {
			// Subsección dedicada a Aprobaciones Pendientes del Usuario o Globales (sin limitar por Status para admitir aprobaciones activas)
			if (effectiveRole == 'ADMIN_ALL') {
				filterCondition = 'AND Id IN :allApprovalRlaIds ';
			} else {
				filterCondition = 'AND Id IN :userActionableRlaIds ';
			}
		} else if (tabName == 'recepcion') {
			filterCondition = 'AND FSC_Subestado__c IN (\'Recepción de documentos – Análisis\', \'En validación PEP/Listas\', \'En Motor Buró\') ';
		} else if (tabName == 'analisis') {
			filterCondition = 'AND FSC_Subestado__c IN (\'Análisis de crédito\', \'Banca Seguro\') ';
		} else if (tabName == 'comite') {
			filterCondition = 'AND Status = \'En proceso\' AND (Id IN :targetExceptionRlaIds OR FSC_DebeRevisarComite__c = true OR FSC_DebeRevisarSupervisor__c = true) ';
		} else if (tabName == 'pagares') {
			filterCondition = 'AND FSC_Subestado__c IN (\'Generación de pagarés y plantillas\', \'Generación de contrato\', \'Documentación para contratos\') ';
		} else if (tabName == 'firmas') {
			filterCondition = 'AND FSC_Subestado__c IN (\'Gestionar firmas\', \'Formalización\') ';
		} else if (tabName == 'desembolso') {
			filterCondition = 'AND FSC_Subestado__c IN (\'Documentación para desembolso y firmas\', \'Pendiente planilla de desembolso\', \'Creación de crédito\', \'Desembolso\', \'Archivo y custodia\') ';
		} else if (tabName == 'finalizadas') {
			filterCondition = 'AND Status IN (\'Cerrada Ganada\', \'Cerrada Perdida\') ';
		} else if (tabName == 'mis_casos') {
			if (effectiveRole == 'ADMIN_ALL') {
				filterCondition = 'AND Status = \'En proceso\' ';
			} else {
				filterCondition = 'AND (Id IN :userActionableRlaIds OR (Status = \'En proceso\' AND (' +
					'(OwnerId = :currentUserId AND FSC_Subestado__c IN (\'En Motor Buró\', \'En validación PEP/Listas\', \'Recepción de documentos – Análisis\', \'Gestionar firmas\')) ' +
					'OR (FSC_UsuarioAnalista__c IN :targetActorIds AND FSC_Subestado__c = \'Análisis de crédito\') ' +
					'OR (FSC_UsuarioSupervisor__c IN :targetActorIds AND FSC_DebeRevisarSupervisor__c = true) ' +
					'OR (FSC_UsuarioComite__c IN :targetActorIds AND FSC_DebeRevisarComite__c = true) ' +
					'OR (FSC_UsuarioPagaresYContratos__c IN :targetActorIds AND FSC_Subestado__c IN (\'Generación de pagarés y plantillas\', \'Generación de contrato\', \'Documentación para contratos\')) ' +
					'OR (FSC_UsuarioFormalizacion__c IN :targetActorIds AND FSC_Subestado__c IN (\'Gestionar firmas\', \'Formalización\')) ' +
					'OR (FSC_UsuarioGestionPlanilla__c IN :targetActorIds AND FSC_Subestado__c IN (\'Recepción Docs Desembolso\', \'Archivo y custodia\'))' +
				'))) ';
			}
		}

		query += filterCondition;

		if (String.isNotBlank(searchKey)) {
			String key = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
			query += 'AND (Name LIKE :key OR Account.Name LIKE :key OR FSC_NumeroSolicitud__c LIKE :key) ';
		}

		query += 'ORDER BY CreatedDate DESC LIMIT 150';

		List<ResidentialLoanApplication> records = Database.query(query, AccessLevel.USER_MODE);

		// Obtener fecha en que cada solicitud entró a su subestado actual vía historial
		Set<Id> recordIds = new Set<Id>();
		for (ResidentialLoanApplication r : records) {
			recordIds.add(r.Id);
		}

		Map<Id, Datetime> fechaSubestadoMap = new Map<Id, Datetime>();
		if (!recordIds.isEmpty()) {
			for (ResidentialLoanApplicationHistory h : [
				SELECT ResidentialLoanApplicationId, CreatedDate
				FROM ResidentialLoanApplicationHistory
				WHERE ResidentialLoanApplicationId IN :recordIds
				AND Field = 'FSC_Subestado__c'
				WITH SYSTEM_MODE
				ORDER BY CreatedDate ASC
			]) {
				fechaSubestadoMap.put(h.ResidentialLoanApplicationId, h.CreatedDate);
			}
		}

		for (ResidentialLoanApplication rla : records) {
			CreditApplicationRow row = new CreditApplicationRow();
			row.recordId = rla.Id;
			row.numeroSolicitud = String.isNotBlank(rla.FSC_NumeroSolicitud__c) ? rla.FSC_NumeroSolicitud__c : '-';
			row.name = rla.Name;
			row.recordUrl = '/' + rla.Id;
			row.accountId = rla.AccountId;
			row.accountName = rla.Account != null ? rla.Account.Name : '-';
			
			// Limpiar texto 'Solicitud de ' para dejar solo el producto
			String rawType = rla.RecordType != null ? rla.RecordType.Name : 'Crédito';
			if (rawType.toLowerCase().startsWith('solicitud de ')) {
				rawType = rawType.substring(13).trim();
			}
			row.productType = rawType.capitalize();

			row.monto = rla.FSC_Monto__c != null ? rla.FSC_Monto__c : 0.0;
			row.status = rla.Status;
			row.subestado = rla.FSC_Subestado__c;
			row.ownerName = rla.Owner != null ? rla.Owner.Name : '-';
			row.createdDate = rla.CreatedDate;

			// Fecha en que entró al subestado actual (fallback a CreatedDate si no hubo cambio previo)
			if (fechaSubestadoMap.containsKey(rla.Id)) {
				row.fechaSubestado = fechaSubestadoMap.get(rla.Id);
			} else {
				row.fechaSubestado = rla.CreatedDate;
			}

			// Evaluar excepciones
			Boolean tieneBuro = (rla.FSC_SolicitaExcepcionParaRechazoDeBuro__c == true);
			Boolean tieneHija = excepcionesBySolicitud.containsKey(rla.Id);
			row.tieneExcepcion = tieneBuro || tieneHija;

			if (tieneBuro && tieneHija) {
				row.detalleExcepcion = 'Excepción Buró + Crédito';
			} else if (tieneBuro) {
				row.detalleExcepcion = 'Excepción de Buró';
			} else if (tieneHija) {
				List<FSC_Excepcion__c> excList = excepcionesBySolicitud.get(rla.Id);
				row.detalleExcepcion = excList[0].FSC_Tipo__c;
			} else {
				row.detalleExcepcion = 'Sin excepción';
			}

			// Resolución Jerárquica de Turno / Responsable por Subestado
			resolveTurnoResponsable(row, rla, workitemsByTarget, targetActorIds, effectiveRole, currentUserId);

			// Mapear campos para dictamen directo
			if (workitemsByTarget.containsKey(rla.Id)) {
				ProcessInstanceWorkitem piw = workitemsByTarget.get(rla.Id);
				row.workitemId = piw.Id;
				row.processName = piw.ProcessInstance != null && piw.ProcessInstance.ProcessDefinition != null ? piw.ProcessInstance.ProcessDefinition.Name : 'Aprobación';
				row.canApprove = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(piw.ActorId));
			} else {
				row.canApprove = false;
			}

			rows.add(row);
		}

		return rows;
	}

	@AuraEnabled
	public static String processApprovalDecision(Id workitemId, String action, String comments) {
		try {
			if (workitemId == null) {
				throw new AuraHandledException('El identificador del ítem de aprobación no es válido.');
			}
			if (String.isBlank(action) || (action != 'Approve' && action != 'Reject')) {
				throw new AuraHandledException('Acción no permitida. Debe ser Approve o Reject.');
			}

			Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
			req.setWorkitemId(workitemId);
			req.setAction(action);
			if (String.isNotBlank(comments)) {
				req.setComments(comments);
			}

			Approval.ProcessResult result = Approval.process(req);
			if (!result.isSuccess()) {
				String errMsg = 'Error al procesar la aprobación: ';
				for (Database.Error err : result.getErrors()) {
					errMsg += err.getMessage() + ' ';
				}
				throw new AuraHandledException(errMsg);
			}

			return action == 'Approve' ? 'Aprobado exitosamente' : 'Rechazado exitosamente';
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	private static void resolveTurnoResponsable(
		CreditApplicationRow row,
		ResidentialLoanApplication rla,
		Map<Id, ProcessInstanceWorkitem> workitemsByTarget,
		Set<Id> targetActorIds,
		String effectiveRole,
		Id currentUserId
	) {
		String sub = rla.FSC_Subestado__c;
		String turno = null;
		Boolean esAccionable = false;

		// 1. Si hay un ítem de aprobación formal activo en ProcessInstanceWorkitem
		if (workitemsByTarget.containsKey(rla.Id)) {
			ProcessInstanceWorkitem piw = workitemsByTarget.get(rla.Id);
			turno = piw.Actor != null ? piw.Actor.Name : 'En aprobación';
			esAccionable = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(piw.ActorId));
		}
		// 2. Jerarquía por Subestado operativo de la Solicitud
		else if (sub == 'En Motor Buró' || sub == 'En validación PEP/Listas') {
			// En validación de Buró o Listas, el turno operativo corresponde al Oficial de Negocio (Owner) para validar/reintentar o solicitar excepción
			if (rla.Owner != null) {
				turno = rla.Owner.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || rla.OwnerId == currentUserId || effectiveRole == 'OFICIAL_NEGOCIO');
			} else {
				turno = 'Oficial de Negocio';
				esAccionable = (effectiveRole == 'ADMIN_ALL' || effectiveRole == 'OFICIAL_NEGOCIO');
			}
		}
		else if (sub == 'Recepción de documentos – Análisis') {
			// El turno corresponde al Oficial de Negocio para completar y cargar los recaudos requeridos
			if (rla.Owner != null) {
				turno = rla.Owner.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || rla.OwnerId == currentUserId || effectiveRole == 'OFICIAL_NEGOCIO');
			} else {
				turno = 'Oficial de Negocio';
				esAccionable = (effectiveRole == 'ADMIN_ALL' || effectiveRole == 'OFICIAL_NEGOCIO');
			}
		}
		else if (sub == 'Análisis de crédito') {
			if (rla.FSC_UsuarioAnalista__c != null && rla.FSC_UsuarioAnalista__r != null) {
				turno = rla.FSC_UsuarioAnalista__r.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(rla.FSC_UsuarioAnalista__c));
			} else {
				turno = 'Cola Analistas de Crédito';
				esAccionable = (effectiveRole == 'ADMIN_ALL' || effectiveRole == 'ANALISTA');
			}
		}
		else if (sub == 'Generación de pagarés y plantillas') {
			if (rla.FSC_UsuarioPagaresYContratos__c != null && rla.FSC_UsuarioPagaresYContratos__r != null) {
				turno = rla.FSC_UsuarioPagaresYContratos__r.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(rla.FSC_UsuarioPagaresYContratos__c));
			} else {
				turno = 'Mesa Pagarés y Contratos';
				esAccionable = (effectiveRole == 'ADMIN_ALL' || effectiveRole == 'FORMALIZACION');
			}
		}
		else if (sub == 'Gestionar firmas') {
			if (rla.FSC_UsuarioFormalizacion__c != null && rla.FSC_UsuarioFormalizacion__r != null) {
				turno = rla.FSC_UsuarioFormalizacion__r.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(rla.FSC_UsuarioFormalizacion__c));
			} else if (rla.Owner != null) {
				// Oficial de Negocios gestiona la firma con su cliente
				turno = rla.Owner.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || rla.OwnerId == currentUserId);
			}
		}
		else if (sub == 'Recepción Docs Desembolso' || sub == 'Archivo y custodia') {
			if (rla.FSC_UsuarioGestionPlanilla__c != null && rla.FSC_UsuarioGestionPlanilla__r != null) {
				turno = rla.FSC_UsuarioGestionPlanilla__r.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(rla.FSC_UsuarioGestionPlanilla__c));
			} else {
				turno = 'Operaciones / Custodia';
				esAccionable = (effectiveRole == 'ADMIN_ALL' || effectiveRole == 'FORMALIZACION');
			}
		}

		// 3. Fallback a Supervisor / Comité si están marcados
		if (turno == null) {
			if (rla.FSC_DebeRevisarComite__c == true && rla.FSC_UsuarioComite__c != null && rla.FSC_UsuarioComite__r != null) {
				turno = rla.FSC_UsuarioComite__r.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(rla.FSC_UsuarioComite__c));
			} else if (rla.FSC_DebeRevisarSupervisor__c == true && rla.FSC_UsuarioSupervisor__c != null && rla.FSC_UsuarioSupervisor__r != null) {
				turno = rla.FSC_UsuarioSupervisor__r.Name;
				esAccionable = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(rla.FSC_UsuarioSupervisor__c));
			} else {
				turno = rla.Owner != null ? rla.Owner.Name : '-';
				esAccionable = (effectiveRole == 'ADMIN_ALL' || rla.OwnerId == currentUserId);
			}
		}

		row.turnoActual = turno;
		row.esAccionablePorUsuario = esAccionable;
	}

	private static Boolean checkIsAdminUser() {
		List<Profile> profs = [
			SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1
		];
		if (!profs.isEmpty() && profs[0].Name == 'Administrador del sistema') {
			return true;
		}
		return FeatureManagement.checkPermission('ModifyAllData');
	}

	@TestVisible
	private static Boolean checkCanGenerateActasComite(Id userId, Boolean isAdmin, String effectiveRole) {
		if (isAdmin) {
			if (effectiveRole == 'OFICIAL' || effectiveRole == 'FORMALIZACION' || effectiveRole == 'EXCEPCIONES') {
				return false;
			}
			return true;
		}

		Set<Id> assignedPermSetIds = new Set<Id>();
		for (PermissionSetAssignment psa : [
			SELECT PermissionSetId
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId
			AND IsActive = true
			WITH SYSTEM_MODE
		]) {
			assignedPermSetIds.add(psa.PermissionSetId);
		}

		if (assignedPermSetIds.isEmpty()) {
			return false;
		}

		Integer accessCount = [
			SELECT COUNT()
			FROM SetupEntityAccess
			WHERE ParentId IN :assignedPermSetIds
			AND SetupEntityId IN (
				SELECT Id FROM ApexPage WHERE Name = 'FSC_ActaComitePDF'
			)
			WITH SYSTEM_MODE
		];
		return accessCount > 0;
	}

	private static Set<Id> resolveTargetActorIds(Id userId, String effectiveRole) {
		Set<Id> actorIds = new Set<Id>();
		actorIds.add(userId);

		if (effectiveRole == 'ADMIN_ALL') {
			return actorIds;
		}

		if (effectiveRole == 'REAL_USER') {
			actorIds.addAll(getUserGroupIds(userId));
			return actorIds;
		}

		Set<String> queueDeveloperNames = new Set<String>();
		if (effectiveRole == 'ANALISTA') {
			queueDeveloperNames = QUEUES_ANALISIS;
		} else if (effectiveRole == 'EXCEPCIONES') {
			queueDeveloperNames = QUEUES_EXCEPCIONES;
		} else if (effectiveRole == 'COMITE') {
			queueDeveloperNames = QUEUES_COMITE;
		} else if (effectiveRole == 'FORMALIZACION') {
			queueDeveloperNames = QUEUES_FORMALIZACION;
		} else if (effectiveRole == 'OFICIAL') {
			return actorIds;
		}

		if (!queueDeveloperNames.isEmpty()) {
			for (Group grp : [
				SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName IN :queueDeveloperNames
				WITH SYSTEM_MODE
			]) {
				actorIds.add(grp.Id);
			}
		}

		return actorIds;
	}

	private static Set<Id> getUserGroupIds(Id userId) {
		Set<Id> currentGroupIds = new Set<Id>{ userId };
		Set<Id> allGroupIds = new Set<Id>();

		Boolean hasMore = true;
		Integer depth = 0;
		while (hasMore && depth < 5) {
			depth++;
			Set<Id> nextGroupIds = new Set<Id>();
			for (GroupMember gm : [
				SELECT GroupId
				FROM GroupMember
				WHERE UserOrGroupId IN :currentGroupIds
				WITH SYSTEM_MODE
			]) {
				if (!allGroupIds.contains(gm.GroupId)) {
					allGroupIds.add(gm.GroupId);
					nextGroupIds.add(gm.GroupId);
				}
			}
			if (nextGroupIds.isEmpty()) {
				hasMore = false;
			} else {
				currentGroupIds = nextGroupIds;
			}
		}
		return allGroupIds;
	}
}