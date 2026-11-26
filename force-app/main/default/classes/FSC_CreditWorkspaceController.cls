public with sharing class FSC_CreditWorkspaceController {

	public class WorkspaceMetrics {
		@AuraEnabled public Integer misPendientesDirectos { get; set; }
		@AuraEnabled public Integer excepcionesActivas { get; set; }
		@AuraEnabled public Integer enAnalisis { get; set; }
		@AuraEnabled public Integer comiteSupervision { get; set; }
		@AuraEnabled public Integer formalizacionCustodia { get; set; }
		@AuraEnabled public Decimal montoTotalCartera { get; set; }
		@AuraEnabled public Boolean isAdministrator { get; set; }

		public WorkspaceMetrics() {
			this.misPendientesDirectos = 0;
			this.excepcionesActivas = 0;
			this.enAnalisis = 0;
			this.comiteSupervision = 0;
			this.formalizacionCustodia = 0;
			this.montoTotalCartera = 0.0;
			this.isAdministrator = false;
		}
	}

	public class CreditApplicationRow {
		@AuraEnabled public Id recordId { get; set; }
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
		@AuraEnabled public Boolean tieneExcepcion { get; set; }
		@AuraEnabled public String detalleExcepcion { get; set; }
		@AuraEnabled public String turnoActual { get; set; }
		@AuraEnabled public Boolean esAccionablePorUsuario { get; set; }
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

		// Si no es admin, ignorar el rol simulado y usar identidad real
		String effectiveRole = (isAdmin && String.isNotBlank(simulatedRole)) ? simulatedRole : 'REAL_USER';

		Set<Id> targetActorIds = resolveTargetActorIds(currentUserId, effectiveRole);

		// 1. Pendientes directos vía ProcessInstanceWorkitem
		List<ProcessInstanceWorkitem> pendingItems = [
			SELECT Id, ProcessInstance.TargetObjectId, ActorId
			FROM ProcessInstanceWorkitem
			WITH SYSTEM_MODE
			LIMIT 1000
		];

		Set<Id> directPendingTargetIds = new Set<Id>();
		Integer globalPendingCount = 0;
		for (ProcessInstanceWorkitem item : pendingItems) {
			globalPendingCount++;
			if (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(item.ActorId)) {
				directPendingTargetIds.add(item.ProcessInstance.TargetObjectId);
			}
		}

		// 2. Conteo de Excepciones de Crédito activas (FSC_Excepcion__c)
		List<FSC_Excepcion__c> excepcionesPendientes = [
			SELECT Id, FSC_Solicitud_Prestamo__c
			FROM FSC_Excepcion__c
			WHERE FSC_Estado__c = 'Pendiente'
			WITH USER_MODE
			LIMIT 500
		];
		Set<Id> solicitudesConExcepcionHija = new Set<Id>();
		for (FSC_Excepcion__c exc : excepcionesPendientes) {
			if (exc.FSC_Solicitud_Prestamo__c != null) {
				solicitudesConExcepcionHija.add(exc.FSC_Solicitud_Prestamo__c);
			}
		}

		// 3. Consultar Solicitudes activas para métricas
		List<ResidentialLoanApplication> solicitudesActivas = [
			SELECT Id, Status, FSC_Subestado__c, FSC_Monto__c, FSC_SolicitaExcepcionParaRechazoDeBuro__c,
			       FSC_DebeRevisarComite__c, FSC_DebeRevisarSupervisor__c, OwnerId
			FROM ResidentialLoanApplication
			WHERE Status = 'En proceso'
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

			// Directo
			if (effectiveRole == 'ADMIN_ALL') {
				if (directPendingTargetIds.contains(rla.Id)) {
					metrics.misPendientesDirectos++;
				}
			} else if (effectiveRole == 'OFICIAL') {
				if (rla.OwnerId == currentUserId && directPendingTargetIds.contains(rla.Id)) {
					metrics.misPendientesDirectos++;
				}
			} else {
				if (directPendingTargetIds.contains(rla.Id)) {
					metrics.misPendientesDirectos++;
				}
			}

			// Etapa Análisis
			if (rla.FSC_Subestado__c == 'Recepción de documentos – Análisis' ||
			    rla.FSC_Subestado__c == 'Análisis de crédito' ||
			    rla.FSC_Subestado__c == 'En validación PEP/Listas' ||
			    rla.FSC_Subestado__c == 'En Motor Buró') {
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

		if (effectiveRole == 'ADMIN_ALL') {
			metrics.misPendientesDirectos = globalPendingCount;
		}

		metrics.montoTotalCartera = sumaMonto;
		return metrics;
	}

	@AuraEnabled(cacheable=true)
	public static List<CreditApplicationRow> getCreditApplications(String tabName, String searchKey, String simulatedRole) {
		List<CreditApplicationRow> rows = new List<CreditApplicationRow>();
		Id currentUserId = UserInfo.getUserId();
		Boolean isAdmin = checkIsAdminUser();
		String effectiveRole = (isAdmin && String.isNotBlank(simulatedRole)) ? simulatedRole : 'REAL_USER';

		Set<Id> targetActorIds = resolveTargetActorIds(currentUserId, effectiveRole);

		// Mapear aprobaciones activas por TargetObjectId
		Map<Id, ProcessInstanceWorkitem> workitemsByTarget = new Map<Id, ProcessInstanceWorkitem>();
		for (ProcessInstanceWorkitem item : [
			SELECT Id, ProcessInstance.TargetObjectId, Actor.Name, OriginalActor.Name, ActorId
			FROM ProcessInstanceWorkitem
			WITH SYSTEM_MODE
			LIMIT 1000
		]) {
			workitemsByTarget.put(item.ProcessInstance.TargetObjectId, item);
		}

		// Mapear excepciones de crédito pendientes (FSC_Excepcion__c)
		Map<Id, List<FSC_Excepcion__c>> excepcionesBySolicitud = new Map<Id, List<FSC_Excepcion__c>>();
		for (FSC_Excepcion__c exc : [
			SELECT Id, FSC_Solicitud_Prestamo__c, FSC_Tipo__c, FSC_Detalle__c, FSC_Estado__c
			FROM FSC_Excepcion__c
			WHERE FSC_Estado__c = 'Pendiente'
			WITH USER_MODE
			LIMIT 1000
		]) {
			if (exc.FSC_Solicitud_Prestamo__c != null) {
				if (!excepcionesBySolicitud.containsKey(exc.FSC_Solicitud_Prestamo__c)) {
					excepcionesBySolicitud.put(exc.FSC_Solicitud_Prestamo__c, new List<FSC_Excepcion__c>());
				}
				excepcionesBySolicitud.get(exc.FSC_Solicitud_Prestamo__c).add(exc);
			}
		}

		String query = 'SELECT Id, Name, AccountId, Account.Name, RecordType.Name, FSC_Monto__c, ' +
		               'Status, FSC_Subestado__c, OwnerId, Owner.Name, CreatedDate, ' +
		               'FSC_SolicitaExcepcionParaRechazoDeBuro__c, FSC_DebeRevisarComite__c, FSC_DebeRevisarSupervisor__c ' +
		               'FROM ResidentialLoanApplication WHERE Status != null ';

		String filterCondition = '';
		if (tabName == 'excepciones') {
			filterCondition = 'AND (FSC_SolicitaExcepcionParaRechazoDeBuro__c = true OR Id IN :targetExceptionRlaIds) ';
		} else if (tabName == 'analisis') {
			filterCondition = 'AND FSC_Subestado__c IN (\'Recepción de documentos – Análisis\', \'Análisis de crédito\', \'En validación PEP/Listas\', \'En Motor Buró\') ';
		} else if (tabName == 'comite') {
			filterCondition = 'AND (FSC_DebeRevisarComite__c = true OR FSC_DebeRevisarSupervisor__c = true) ';
		} else if (tabName == 'formalizacion') {
			filterCondition = 'AND FSC_Subestado__c IN (\'Generación de pagarés y plantillas\', \'Gestionar firmas\', \'Archivo y custodia\') ';
		} else if (tabName == 'mis_casos') {
			if (effectiveRole == 'ADMIN_ALL') {
				// Admin en modo global ve todas las que tienen turno activo o asignadas
				filterCondition = 'AND Status = \'En proceso\' ';
			} else if (effectiveRole == 'OFICIAL') {
				filterCondition = 'AND (OwnerId = :currentUserId OR Id IN :userActionableRlaIds) ';
			} else {
				filterCondition = 'AND (OwnerId = :currentUserId OR Id IN :userActionableRlaIds) ';
			}
		}

		Set<Id> targetExceptionRlaIds = excepcionesBySolicitud.keySet();
		Set<Id> userActionableRlaIds = new Set<Id>();
		for (ProcessInstanceWorkitem piw : workitemsByTarget.values()) {
			if (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(piw.ActorId)) {
				userActionableRlaIds.add(piw.ProcessInstance.TargetObjectId);
			}
		}

		query += filterCondition;

		if (String.isNotBlank(searchKey)) {
			String key = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
			query += 'AND (Name LIKE :key OR Account.Name LIKE :key) ';
		}

		query += 'ORDER BY CreatedDate DESC LIMIT 150';

		List<ResidentialLoanApplication> records = Database.query(query, AccessLevel.USER_MODE);

		for (ResidentialLoanApplication rla : records) {
			CreditApplicationRow row = new CreditApplicationRow();
			row.recordId = rla.Id;
			row.name = rla.Name;
			row.recordUrl = '/' + rla.Id;
			row.accountId = rla.AccountId;
			row.accountName = rla.Account != null ? rla.Account.Name : '-';
			row.productType = rla.RecordType != null ? rla.RecordType.Name : 'Préstamo';
			row.monto = rla.FSC_Monto__c != null ? rla.FSC_Monto__c : 0.0;
			row.status = rla.Status;
			row.subestado = rla.FSC_Subestado__c;
			row.ownerName = rla.Owner != null ? rla.Owner.Name : '-';
			row.createdDate = rla.CreatedDate;

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

			// Turno actual y si es accionable
			if (workitemsByTarget.containsKey(rla.Id)) {
				ProcessInstanceWorkitem piw = workitemsByTarget.get(rla.Id);
				row.turnoActual = piw.Actor != null ? piw.Actor.Name : 'En aprobación';
				row.esAccionablePorUsuario = (effectiveRole == 'ADMIN_ALL' || targetActorIds.contains(piw.ActorId));
			} else {
				row.turnoActual = rla.Owner != null ? rla.Owner.Name : '-';
				row.esAccionablePorUsuario = (effectiveRole == 'ADMIN_ALL' || rla.OwnerId == currentUserId);
			}

			rows.add(row);
		}

		return rows;
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
			// Solo el usuario como originador
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
		Set<Id> groupIds = new Set<Id>();
		for (GroupMember gm : [
			SELECT GroupId
			FROM GroupMember
			WHERE UserOrGroupId = :userId
			WITH SYSTEM_MODE
		]) {
			groupIds.add(gm.GroupId);
		}
		return groupIds;
	}
}
