public with sharing class FSC_CreditWorkspaceController {

	public class WorkspaceMetrics {
		@AuraEnabled public Integer misPendientesDirectos { get; set; }
		@AuraEnabled public Integer excepcionesActivas { get; set; }
		@AuraEnabled public Integer enAnalisis { get; set; }
		@AuraEnabled public Integer comiteSupervision { get; set; }
		@AuraEnabled public Integer formalizacionCustodia { get; set; }
		@AuraEnabled public Decimal montoTotalCartera { get; set; }

		public WorkspaceMetrics() {
			this.misPendientesDirectos = 0;
			this.excepcionesActivas = 0;
			this.enAnalisis = 0;
			this.comiteSupervision = 0;
			this.formalizacionCustodia = 0;
			this.montoTotalCartera = 0.0;
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

	@AuraEnabled(cacheable=true)
	public static WorkspaceMetrics getWorkspaceMetrics() {
		WorkspaceMetrics metrics = new WorkspaceMetrics();
		Id currentUserId = UserInfo.getUserId();
		Set<Id> userGroupIds = getUserGroupIds(currentUserId);

		// 1. Mis pendientes directos vía ProcessInstanceWorkitem
		Set<Id> allUserTargets = new Set<Id>();
		allUserTargets.add(currentUserId);
		allUserTargets.addAll(userGroupIds);

		List<ProcessInstanceWorkitem> pendingItems = [
			SELECT Id, ProcessInstance.TargetObjectId
			FROM ProcessInstanceWorkitem
			WHERE ActorId IN :allUserTargets
			WITH SYSTEM_MODE
			LIMIT 500
		];
		Set<Id> directPendingTargetIds = new Set<Id>();
		for (ProcessInstanceWorkitem item : pendingItems) {
			directPendingTargetIds.add(item.ProcessInstance.TargetObjectId);
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
			       FSC_DebeRevisarComite__c, FSC_DebeRevisarSupervisor__c
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
			if (directPendingTargetIds.contains(rla.Id) || (tieneExc && directPendingTargetIds.contains(rla.Id))) {
				metrics.misPendientesDirectos++;
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

		metrics.montoTotalCartera = sumaMonto;
		return metrics;
	}

	@AuraEnabled(cacheable=true)
	public static List<CreditApplicationRow> getCreditApplications(String tabName, String searchKey) {
		List<CreditApplicationRow> rows = new List<CreditApplicationRow>();
		Id currentUserId = UserInfo.getUserId();
		Set<Id> userGroupIds = getUserGroupIds(currentUserId);
		Set<Id> allUserTargets = new Set<Id>();
		allUserTargets.add(currentUserId);
		allUserTargets.addAll(userGroupIds);

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
			filterCondition = 'AND (OwnerId = :currentUserId OR Id IN :userActionableRlaIds) ';
		}

		Set<Id> targetExceptionRlaIds = excepcionesBySolicitud.keySet();
		Set<Id> userActionableRlaIds = new Set<Id>();
		for (ProcessInstanceWorkitem piw : workitemsByTarget.values()) {
			if (allUserTargets.contains(piw.ActorId)) {
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
				row.esAccionablePorUsuario = allUserTargets.contains(piw.ActorId);
			} else {
				row.turnoActual = rla.Owner != null ? rla.Owner.Name : '-';
				row.esAccionablePorUsuario = (rla.OwnerId == currentUserId);
			}

			rows.add(row);
		}

		return rows;
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
