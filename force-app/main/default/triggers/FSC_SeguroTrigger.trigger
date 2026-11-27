trigger FSC_SeguroTrigger on FSC_Seguro__c(before insert, before update, before delete, after insert) {
	if (Trigger.isBefore) {
		if (Trigger.isDelete) {
			FSC_CreditoAprobadoLockService.validarSeguros(Trigger.old);
		} else {
			FSC_CreditoAprobadoLockService.validarSeguros(Trigger.new, Trigger.oldMap, Trigger.isInsert);
		}
	}
	if (Trigger.isAfter && Trigger.isInsert) {
		FSC_LoanDraftPersistenceService.reconcileInsertedInsurancesOnSubmittedApplications(Trigger.new);
	}
}
