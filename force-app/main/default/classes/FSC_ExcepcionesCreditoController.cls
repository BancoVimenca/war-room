public with sharing class FSC_ExcepcionesCreditoController {
	@TestVisible
	private static Boolean testForceAuthorized = false;
	private static final Integer LONGITUD_COMENTARIO_APROBACION = 255;
	private static final String ESTADO_EN_PROCESO = 'En proceso';
	private static final String ESTADO_NO_APLICA = 'No aplica';
	private static final String ESTADO_PENDIENTE = 'Pendiente';
	private static final String ESTADO_APROBADA = 'Aprobada';
	private static final String ESTADO_RECHAZADA = 'Rechazada';
	private static final String ESTADO_OBSERVADA = 'Observada';
	private static final String NOTIFICATION_TYPE_DEVOLUCION = 'FSC_DevolucionNegocio';
	private static final String TIPO_NEGOCIOS = 'Excepciones de Negocios';
	private static final String SUBESTADO_RECHAZADA_ANALISTA = 'Rechazado por análisis';
	private static final String SUBESTADO_RECHAZADA_CLIENTE = 'Rechazada por cliente';
	private static final String PERMISO_ADMINISTRADOR = 'FSC_CP_Administrador';
	private static final String PERMISO_OFICIAL_NEGOCIO = 'FSC_CP_Oficial_Negocio';
	private static final Set<String> SUBESTADOS_PERMITIDOS = new Set<String>{
		'En validación PEP/Listas',
		'En Motor Buró',
		'Recepción de documentos – Análisis'
	};

	public class FSC_OpcionExcepcion {
		@AuraEnabled
		public String tipo { get; set; }
		@AuraEnabled
		public String detalle { get; set; }
	}

	private class TargetSnapshot {
		private Id targetId;
		private Id solicitudId;
		private String solicitudName;
		private Id solicitudOwnerId;
		private String estado;
		private String condicion;
		private String observaciones;
		private String pasoObservacion;
		private String motivo;
		private String tipo;
		private String detalle;
	}

	@AuraEnabled(cacheable=true)
	public static Map<String, Object> getContextoExcepcion(Id residentialLoanApplicationId) {
		ResidentialLoanApplication solicitud = requireSolicitud(residentialLoanApplicationId);
		List<FSC_Excepcion__c> excepciones = FSC_ExcepcionSelector.selectBySolicitud(residentialLoanApplicationId);
		Integer cantidad = getChildCount(solicitud);

		Set<Id> targetIds = new Set<Id>();
		for (FSC_Excepcion__c excepcion : excepciones) {
			targetIds.add(excepcion.Id);
		}
		Map<Id, List<ProcessInstanceWorkitem>> workItemsByTarget = FSC_ExcepcionApprovalService.getWorkItemsByTarget(targetIds);
		Set<Id> actionableTargetIds = FSC_ExcepcionApprovalService.getActionableTargetIds(workItemsByTarget);
		TargetSnapshot selected = selectCurrentTarget(excepciones, workItemsByTarget, actionableTargetIds);
		List<ProcessInstanceWorkitem> selectedWorkItems = selected == null || !workItemsByTarget.containsKey(selected.targetId)
			? new List<ProcessInstanceWorkitem>()
			: workItemsByTarget.get(selected.targetId);
		Boolean hasActiveApproval = !selectedWorkItems.isEmpty();
		String aprobadorActual = null;
		if (hasActiveApproval) {
			ProcessInstanceWorkitem firstWi = selectedWorkItems[0];
			Id actorId = firstWi.ActorId != null ? firstWi.ActorId : firstWi.OriginalActorId;
			String baseName = String.isNotBlank(firstWi.Actor?.Name) ? firstWi.Actor.Name : firstWi.OriginalActor?.Name;
			aprobadorActual = formatAprobador(actorId, baseName);
		}
		Boolean autorizadoSolicitud = isOficialOAdministrador();
		Boolean tienePendientes = hasPendingException(excepciones);
		Integer maximoExcepciones = FSC_ExcepcionConfig.getMaximoExcepciones();

		return new Map<String, Object>{
			'excepcionId' => selected?.targetId,
			'solicitada' => cantidad > 0,
			'cantidad' => cantidad,
			'maximo' => maximoExcepciones,
			'disponibles' => Math.max(0, maximoExcepciones - cantidad),
			'limiteAlcanzado' => cantidad >= maximoExcepciones,
			'estado' => selected?.estado ?? ESTADO_NO_APLICA,
			'condicion' => selected?.condicion,
			'observaciones' => selected?.observaciones,
			'pasoObservacion' => selected?.pasoObservacion,
			'motivo' => selected?.motivo,
			'tipo' => selected?.tipo,
			'detalle' => selected?.detalle,
			'tienePendientes' => tienePendientes,
			'hasActiveApproval' => hasActiveApproval,
			'aprobadorActual' => aprobadorActual,
			'canActOnApproval' => selected != null && actionableTargetIds.contains(selected.targetId),
			'puedeSolicitar' => autorizadoSolicitud &&
			isSolicitudElegible(solicitud) &&
			cantidad < maximoExcepciones,
			'puedeResponderCondicion' => autorizadoSolicitud &&
			selected != null &&
			selected.estado == ESTADO_PENDIENTE &&
			String.isNotBlank(selected.condicion) &&
			!hasActiveApproval,
			'puedeSubsanarObservacion' => autorizadoSolicitud &&
			selected != null &&
			selected.estado == ESTADO_OBSERVADA &&
			!hasActiveApproval
		};
	}

	@AuraEnabled(cacheable=true)
	public static Map<String, Object> getContextoPorExcepcion(Id excepcionId) {
		TargetSnapshot selected = requireTarget(excepcionId);
		ResidentialLoanApplication solicitud = requireSolicitud(selected.solicitudId);
		Set<Id> targetIds = new Set<Id>{ selected.targetId };
		Map<Id, List<ProcessInstanceWorkitem>> workItemsByTarget = FSC_ExcepcionApprovalService.getWorkItemsByTarget(targetIds);
		Set<Id> actionableTargetIds = FSC_ExcepcionApprovalService.getActionableTargetIds(workItemsByTarget);
		List<ProcessInstanceWorkitem> selectedWorkItems = workItemsByTarget.containsKey(selected.targetId)
			? workItemsByTarget.get(selected.targetId)
			: new List<ProcessInstanceWorkitem>();
		Boolean hasActiveApproval = !selectedWorkItems.isEmpty();
		String aprobadorActual = null;
		if (hasActiveApproval) {
			ProcessInstanceWorkitem firstWi = selectedWorkItems[0];
			Id actorId = firstWi.ActorId != null ? firstWi.ActorId : firstWi.OriginalActorId;
			String baseName = String.isNotBlank(firstWi.Actor?.Name) ? firstWi.Actor.Name : firstWi.OriginalActor?.Name;
			aprobadorActual = formatAprobador(actorId, baseName);
		}
		Boolean autorizadoSolicitud = isOficialOAdministrador();

		return new Map<String, Object>{
			'excepcionId' => selected.targetId,
			'solicitudId' => selected.solicitudId,
			'solicitudName' => selected.solicitudName,
			'estado' => selected.estado ?? ESTADO_NO_APLICA,
			'condicion' => selected.condicion,
			'observaciones' => selected.observaciones,
			'pasoObservacion' => selected.pasoObservacion,
			'motivo' => selected.motivo,
			'tipo' => selected.tipo,
			'detalle' => selected.detalle,
			'hasActiveApproval' => hasActiveApproval,
			'aprobadorActual' => aprobadorActual,
			'canActOnApproval' => actionableTargetIds.contains(selected.targetId),
			'puedeResponderCondicion' => autorizadoSolicitud &&
			selected.estado == ESTADO_PENDIENTE &&
			String.isNotBlank(selected.condicion) &&
			!hasActiveApproval &&
			isSolicitudElegible(solicitud),
			'puedeSubsanarObservacion' => autorizadoSolicitud &&
			selected.estado == ESTADO_OBSERVADA &&
			!hasActiveApproval &&
			isSolicitudElegible(solicitud)
		};
	}

	@AuraEnabled(cacheable=true)
	public static List<FSC_OpcionExcepcion> getOpcionesExcepcion() {
		List<FSC_OpcionExcepcion> opciones = new List<FSC_OpcionExcepcion>();
		for (FSC_ExcepcionesDeCredito__mdt configuracion : FSC_ExcepcionesDeCredito__mdt.getAll().values()) {
			if (String.isBlank(configuracion.FSC_Tipo__c) || String.isBlank(configuracion.FSC_Detalle__c)) {
				continue;
			}
			FSC_OpcionExcepcion opcion = new FSC_OpcionExcepcion();
			opcion.tipo = configuracion.FSC_Tipo__c;
			opcion.detalle = configuracion.FSC_Detalle__c;
			opciones.add(opcion);
		}
		return opciones;
	}

	@AuraEnabled
	public static Id solicitarExcepcion(Id residentialLoanApplicationId, String tipo, String detalle, String descripcion) {
		validateOficialOAdministrador();
		validateRequiredRequest(residentialLoanApplicationId, tipo, detalle, descripcion);
		ResidentialLoanApplication solicitud = requireSolicitud(residentialLoanApplicationId);
		if (!isSolicitudElegible(solicitud)) {
			throw new AuraHandledException('La excepción solo puede solicitarse en estado En proceso y en uno de los subestados habilitados.');
		}

		Integer cantidad = getChildCount(solicitud);
		if (cantidad >= FSC_ExcepcionConfig.getMaximoExcepciones()) {
			throw new AuraHandledException(FSC_ExcepcionConfig.getMensajeLimite());
		}

		FSC_ExcepcionesDeCredito__mdt configuracion = findConfiguration(tipo.trim(), detalle.trim());
		if (configuracion == null) {
			throw new AuraHandledException('El tipo y detalle seleccionados no corresponden a una excepción configurada.');
		}
		if (tipo.trim() != TIPO_NEGOCIOS && (solicitud.FSC_Monto__c == null || solicitud.FSC_Monto__c <= 0)) {
			throw new AuraHandledException('La solicitud debe tener un monto mayor que cero para determinar la ruta de aprobación.');
		}

		FSC_Excepcion__c excepcion = new FSC_Excepcion__c(
			FSC_Solicitud_Prestamo__c = residentialLoanApplicationId,
			FSC_Tipo__c = configuracion.FSC_Tipo__c,
			FSC_Detalle__c = configuracion.FSC_Detalle__c,
			FSC_Motivo__c = descripcion.trim(),
			FSC_Estado__c = ESTADO_PENDIENTE
		);
		Database.insert(excepcion, AccessLevel.USER_MODE);
		FSC_ExcepcionApprovalService.submit(excepcion.Id);
		return excepcion.Id;
	}

	@AuraEnabled
	public static void aprobarExcepcion(Id excepcionId) {
		FSC_ExcepcionApprovalService.process(excepcionId, 'Approve', 'Excepción aprobada.');
	}

	@AuraEnabled
	public static void aprobarExcepcionConCondicion(Id excepcionId, String condicion) {
		if (String.isBlank(condicion)) {
			throw new AuraHandledException('Condición requerida.');
		}
		if (condicion.length() > 32768) {
			throw new AuraHandledException('La condición excede el máximo permitido.');
		}
		FSC_ExcepcionApprovalService.assertCurrentUserCanAct(excepcionId);
		updateTargetCondition(excepcionId, condicion.trim());
		String comentario = 'Aprobada con condición: ' + condicion.trim();
		if (comentario.length() > LONGITUD_COMENTARIO_APROBACION) {
			comentario = comentario.substring(0, LONGITUD_COMENTARIO_APROBACION);
		}
		Approval.ProcessResult result = FSC_ExcepcionApprovalService.process(excepcionId, 'Approve', comentario);
		if (result.getInstanceStatus() != 'Approved') {
			throw new AuraHandledException('No se pudo finalizar la aprobación condicionada.');
		}
		updateTargetState(excepcionId, ESTADO_PENDIENTE);
	}

	@AuraEnabled
	public static void rechazarExcepcion(Id excepcionId, String motivo) {
		if (String.isBlank(motivo)) {
			throw new AuraHandledException('Motivo requerido.');
		}
		String motivoNormalizado = motivo.trim();
		if (motivoNormalizado.length() > LONGITUD_COMENTARIO_APROBACION) {
			throw new AuraHandledException('Motivo máximo 255 caracteres.');
		}
		requireTarget(excepcionId);
		FSC_ExcepcionTriggerHandler.setRejectionContext(excepcionId, SUBESTADO_RECHAZADA_ANALISTA, motivoNormalizado);
		try {
			Approval.ProcessResult result = FSC_ExcepcionApprovalService.process(excepcionId, 'Reject', motivoNormalizado);
			if (result.getInstanceStatus() != 'Rejected') {
				throw new AuraHandledException('No se pudo finalizar el rechazo de la excepción.');
			}
		} finally {
			FSC_ExcepcionTriggerHandler.clearRejectionContext(excepcionId);
		}
	}

	@AuraEnabled
	public static void responderCondicionCliente(Id excepcionId, Boolean clienteAprueba) {
		validateOficialOAdministrador();
		if (excepcionId == null || clienteAprueba == null) {
			throw new AuraHandledException('Excepción y respuesta del cliente requeridas.');
		}
		TargetSnapshot target = requireTarget(excepcionId);
		if (target.estado != ESTADO_PENDIENTE || String.isBlank(target.condicion)) {
			throw new AuraHandledException('La excepción no tiene una condición pendiente de respuesta.');
		}
		if (FSC_ExcepcionApprovalService.hasActiveWorkItem(excepcionId)) {
			throw new AuraHandledException('La aprobación condicionada aún no ha finalizado.');
		}
		if (clienteAprueba) {
			updateTargetState(excepcionId, ESTADO_APROBADA);
			return;
		}

		FSC_ExcepcionTriggerHandler.setRejectionContext(excepcionId, SUBESTADO_RECHAZADA_CLIENTE, null);
		try {
			updateTargetState(excepcionId, ESTADO_RECHAZADA);
		} finally {
			FSC_ExcepcionTriggerHandler.clearRejectionContext(excepcionId);
		}
	}

	@AuraEnabled
	public static void devolverExcepcionConObservacion(Id excepcionId, String observaciones) {
		if (String.isBlank(observaciones)) {
			throw new AuraHandledException('Las observaciones son requeridas para devolver la excepción.');
		}
		String obsNormalizadas = observaciones.trim();
		if (obsNormalizadas.length() > 32768) {
			throw new AuraHandledException('Las observaciones exceden el máximo permitido.');
		}

		TargetSnapshot target = requireTarget(excepcionId);
		ProcessInstanceWorkitem workItem = FSC_ExcepcionApprovalService.getActiveActionableWorkItem(excepcionId);
		String baseActorName = String.isNotBlank(workItem.Actor?.Name)
			? workItem.Actor.Name
			: (String.isNotBlank(workItem.OriginalActor?.Name) ? workItem.OriginalActor.Name : UserInfo.getName());
		String pasoOrigen = (baseActorName + ' - ' + UserInfo.getName()).left(255);

		String comentarioHistorial = 'Devuelta con observaciones al oficial: ' + obsNormalizadas;
		if (comentarioHistorial.length() > LONGITUD_COMENTARIO_APROBACION) {
			comentarioHistorial = comentarioHistorial.substring(0, LONGITUD_COMENTARIO_APROBACION);
		}

		FSC_ExcepcionTriggerHandler.setObservationBypass(excepcionId);
		try {
			Approval.ProcessResult result = FSC_ExcepcionApprovalService.process(excepcionId, 'Reject', comentarioHistorial);
			if (result.getInstanceStatus() != 'Rejected') {
				throw new AuraHandledException('No se pudo retirar la aprobación para registrar las observaciones.');
			}
			Database.update(
				new FSC_Excepcion__c(
					Id = excepcionId,
					FSC_Estado__c = ESTADO_OBSERVADA,
					FSC_Observaciones_Aprobador__c = obsNormalizadas,
					FSC_Paso_Observacion__c = pasoOrigen
				),
				AccessLevel.SYSTEM_MODE
			);
		} finally {
			FSC_ExcepcionTriggerHandler.clearObservationBypass(excepcionId);
		}

		notifyOwnerExceptionObserved(target, obsNormalizadas);
	}

	@AuraEnabled
	public static void subsanarYReenviarExcepcion(Id excepcionId, String nuevoTipo, String nuevoDetalle, String nuevaDescripcion) {
		validateOficialOAdministrador();
		if (excepcionId == null || String.isBlank(nuevaDescripcion)) {
			throw new AuraHandledException('El motivo subsanado de la excepción es obligatorio.');
		}
		String descripcionNormalizada = nuevaDescripcion.trim();
		if (descripcionNormalizada.length() > 32768) {
			throw new AuraHandledException('El motivo excede el máximo permitido.');
		}

		TargetSnapshot target = requireTarget(excepcionId);
		if (target.estado != ESTADO_OBSERVADA) {
			throw new AuraHandledException('Solo se puede subsanar una excepción en estado Observada.');
		}
		if (FSC_ExcepcionApprovalService.hasActiveWorkItem(excepcionId)) {
			throw new AuraHandledException('La excepción ya cuenta con una aprobación activa.');
		}

		ResidentialLoanApplication solicitud = requireSolicitud(target.solicitudId);
		if (!isSolicitudElegible(solicitud)) {
			throw new AuraHandledException('La solicitud debe estar En proceso y en uno de los subestados habilitados para reenviar la excepción.');
		}

		String tipoEfectivo = String.isNotBlank(nuevoTipo) ? nuevoTipo.trim() : target.tipo;
		String detalleEfectivo = String.isNotBlank(nuevoDetalle) ? nuevoDetalle.trim() : target.detalle;
		FSC_ExcepcionesDeCredito__mdt configuracion = findConfiguration(tipoEfectivo, detalleEfectivo);
		if (configuracion == null) {
			throw new AuraHandledException('El tipo y detalle seleccionados no corresponden a una excepción configurada.');
		}
		if (tipoEfectivo != TIPO_NEGOCIOS && (solicitud.FSC_Monto__c == null || solicitud.FSC_Monto__c <= 0)) {
			throw new AuraHandledException('La solicitud debe tener un monto mayor que cero para determinar la ruta de aprobación.');
		}

		Database.update(
			new FSC_Excepcion__c(
				Id = excepcionId,
				FSC_Tipo__c = configuracion.FSC_Tipo__c,
				FSC_Detalle__c = configuracion.FSC_Detalle__c,
				FSC_Motivo__c = descripcionNormalizada,
				FSC_Estado__c = ESTADO_PENDIENTE
			),
			AccessLevel.SYSTEM_MODE
		);

		String comentarioReenvio = 'Excepción subsanada y reenviada por ' + UserInfo.getName() + '.';
		if (comentarioReenvio.length() > LONGITUD_COMENTARIO_APROBACION) {
			comentarioReenvio = comentarioReenvio.substring(0, LONGITUD_COMENTARIO_APROBACION);
		}
		FSC_ExcepcionApprovalService.submit(excepcionId, comentarioReenvio);
	}

	private static TargetSnapshot selectCurrentTarget(
		List<FSC_Excepcion__c> excepciones,
		Map<Id, List<ProcessInstanceWorkitem>> workItemsByTarget,
		Set<Id> actionableTargetIds
	) {
		for (FSC_Excepcion__c excepcion : excepciones) {
			if (excepcion.FSC_Estado__c == ESTADO_PENDIENTE && actionableTargetIds.contains(excepcion.Id)) {
				return childSnapshot(excepcion);
			}
		}
		for (FSC_Excepcion__c excepcion : excepciones) {
			if (excepcion.FSC_Estado__c == ESTADO_OBSERVADA) {
				return childSnapshot(excepcion);
			}
		}
		for (FSC_Excepcion__c excepcion : excepciones) {
			if (excepcion.FSC_Estado__c == ESTADO_PENDIENTE && workItemsByTarget.containsKey(excepcion.Id)) {
				return childSnapshot(excepcion);
			}
		}
		for (FSC_Excepcion__c excepcion : excepciones) {
			if (excepcion.FSC_Estado__c == ESTADO_PENDIENTE && String.isNotBlank(excepcion.FSC_Condicion__c)) {
				return childSnapshot(excepcion);
			}
		}
		if (!excepciones.isEmpty()) {
			return childSnapshot(excepciones[0]);
		}
		return null;
	}

	private static TargetSnapshot requireTarget(Id targetId) {
		if (targetId == null) {
			throw new AuraHandledException('Excepción requerida.');
		}
		if (targetId.getSObjectType() != FSC_Excepcion__c.SObjectType) {
			throw new AuraHandledException('El identificador no corresponde a una excepción FSC.');
		}
		FSC_Excepcion__c excepcion = FSC_ExcepcionSelector.selectById(targetId);
		if (excepcion == null) {
			throw new AuraHandledException('No se encontró la excepción.');
		}
		return childSnapshot(excepcion);
	}

	private static TargetSnapshot childSnapshot(FSC_Excepcion__c excepcion) {
		TargetSnapshot target = new TargetSnapshot();
		target.targetId = excepcion.Id;
		target.solicitudId = excepcion.FSC_Solicitud_Prestamo__c;
		Map<String, Object> populated = excepcion.getPopulatedFieldsAsMap();
		if (populated.containsKey('FSC_Solicitud_Prestamo__r') && excepcion.FSC_Solicitud_Prestamo__r != null) {
			target.solicitudName = excepcion.FSC_Solicitud_Prestamo__r.Name;
			target.solicitudOwnerId = excepcion.FSC_Solicitud_Prestamo__r.OwnerId;
		}
		target.estado = excepcion.FSC_Estado__c;
		target.condicion = excepcion.FSC_Condicion__c;
		target.observaciones = excepcion.FSC_Observaciones_Aprobador__c;
		target.pasoObservacion = excepcion.FSC_Paso_Observacion__c;
		target.motivo = excepcion.FSC_Motivo__c;
		target.tipo = excepcion.FSC_Tipo__c;
		target.detalle = excepcion.FSC_Detalle__c;
		return target;
	}

	private static ResidentialLoanApplication requireSolicitud(Id solicitudId) {
		if (solicitudId == null) {
			throw new AuraHandledException('Solicitud requerida.');
		}
		ResidentialLoanApplication solicitud = FSC_ExcepcionSelector.selectSolicitud(solicitudId);
		if (solicitud == null) {
			throw new AuraHandledException('No se encontró la solicitud.');
		}
		return solicitud;
	}

	private static Boolean hasPendingException(List<FSC_Excepcion__c> excepciones) {
		for (FSC_Excepcion__c excepcion : excepciones) {
			if (excepcion.FSC_Estado__c == ESTADO_PENDIENTE || excepcion.FSC_Estado__c == ESTADO_OBSERVADA) {
				return true;
			}
		}
		return false;
	}

	private static void notifyOwnerExceptionObserved(TargetSnapshot target, String observaciones) {
		try {
			if (target == null || target.solicitudId == null || target.solicitudOwnerId == null) {
				return;
			}
			if (target.solicitudOwnerId.getSObjectType() != User.SObjectType || target.solicitudOwnerId == UserInfo.getUserId()) {
				return;
			}
			List<User> activeOwners = [
				SELECT Id
				FROM User
				WHERE Id = :target.solicitudOwnerId AND IsActive = TRUE
				WITH SYSTEM_MODE
				LIMIT 1
			];
			if (activeOwners.isEmpty()) {
				return;
			}
			List<CustomNotificationType> notificationTypes = [
				SELECT Id
				FROM CustomNotificationType
				WHERE DeveloperName = :NOTIFICATION_TYPE_DEVOLUCION
				WITH SYSTEM_MODE
				LIMIT 1
			];
			if (notificationTypes.isEmpty()) {
				return;
			}
			String rlaLabel = String.isNotBlank(target.solicitudName) ? target.solicitudName : 'Solicitud de crédito';
			Messaging.CustomNotification notification = new Messaging.CustomNotification();
			notification.setNotificationTypeId(notificationTypes[0].Id);
			notification.setTargetId(target.solicitudId);
			notification.setTitle(('Excepción observada - ' + rlaLabel).abbreviate(250));
			notification.setBody(('Devuelta por ' + UserInfo.getName() + '. Observación: ' + observaciones).abbreviate(750));
			notification.send(new Set<String>{ String.valueOf(target.solicitudOwnerId) });
		} catch (Exception ex) {
			System.debug(LoggingLevel.WARN, 'No se pudo enviar notificación de excepción observada: ' + ex.getMessage());
		}
	}

	private static Integer getChildCount(ResidentialLoanApplication solicitud) {
		return solicitud.FSC_Cantidad_Excepciones__c == null ? 0 : solicitud.FSC_Cantidad_Excepciones__c.intValue();
	}

	private static Boolean isSolicitudElegible(ResidentialLoanApplication solicitud) {
		return solicitud.Status == ESTADO_EN_PROCESO && SUBESTADOS_PERMITIDOS.contains(solicitud.FSC_Subestado__c);
	}

	private static FSC_ExcepcionesDeCredito__mdt findConfiguration(String tipo, String detalle) {
		for (FSC_ExcepcionesDeCredito__mdt configuracion : FSC_ExcepcionesDeCredito__mdt.getAll().values()) {
			if (configuracion.FSC_Tipo__c == tipo && configuracion.FSC_Detalle__c == detalle) {
				return configuracion;
			}
		}
		return null;
	}

	private static void updateTargetCondition(Id targetId, String condicion) {
		requireTarget(targetId);
		Database.update(new FSC_Excepcion__c(Id = targetId, FSC_Condicion__c = condicion), AccessLevel.SYSTEM_MODE);
	}

	private static void updateTargetState(Id targetId, String estado) {
		requireTarget(targetId);
		Database.update(new FSC_Excepcion__c(Id = targetId, FSC_Estado__c = estado), AccessLevel.SYSTEM_MODE);
	}

	private static void validateRequiredRequest(Id solicitudId, String tipo, String detalle, String descripcion) {
		if (solicitudId == null || String.isBlank(tipo) || String.isBlank(detalle) || String.isBlank(descripcion)) {
			throw new AuraHandledException('Tipo, detalle y descripción son obligatorios.');
		}
		if (descripcion.length() > 32768) {
			throw new AuraHandledException('La descripción excede el máximo permitido.');
		}
	}

	private static void validateOficialOAdministrador() {
		if (!isOficialOAdministrador()) {
			throw new AuraHandledException('Solo el oficial de negocio o un administrador puede realizar esta acción.');
		}
	}

	@TestVisible
	private static String formatAprobador(Id actorId, String baseName) {
		if (String.isBlank(baseName)) {
			return null;
		}
		if (actorId == null || String.valueOf(actorId).startsWith('005')) {
			return baseName;
		}

		Set<Id> userIds = new Set<Id>();
		Set<Id> groupIdsToInspect = new Set<Id>{ actorId };
		for (GroupMember gm : [
			SELECT GroupId, UserOrGroupId
			FROM GroupMember
			WHERE GroupId IN :groupIdsToInspect
			WITH SYSTEM_MODE
		]) {
			if (String.valueOf(gm.UserOrGroupId).startsWith('005')) {
				userIds.add(gm.UserOrGroupId);
			} else if (String.valueOf(gm.UserOrGroupId).startsWith('00G')) {
				groupIdsToInspect.add(gm.UserOrGroupId);
			}
		}

		if (!groupIdsToInspect.isEmpty()) {
			for (GroupMember gm : [
				SELECT UserOrGroupId
				FROM GroupMember
				WHERE GroupId IN :groupIdsToInspect
				WITH SYSTEM_MODE
			]) {
				if (String.valueOf(gm.UserOrGroupId).startsWith('005')) {
					userIds.add(gm.UserOrGroupId);
				}
			}
		}

		if (userIds.isEmpty()) {
			return baseName;
		}

		List<String> userNames = new List<String>();
		for (User u : [
			SELECT Name
			FROM User
			WHERE Id IN :userIds AND IsActive = true
			WITH SYSTEM_MODE
			ORDER BY Name
		]) {
			userNames.add(u.Name);
		}

		if (userNames.isEmpty()) {
			return baseName;
		}
		return baseName + ' (' + String.join(userNames, ', ') + ')';
	}

	private static Boolean isOficialOAdministrador() {
		return (Test.isRunningTest() && testForceAuthorized) ||
			FeatureManagement.checkPermission(PERMISO_OFICIAL_NEGOCIO) ||
			FeatureManagement.checkPermission(PERMISO_ADMINISTRADOR);
	}
}