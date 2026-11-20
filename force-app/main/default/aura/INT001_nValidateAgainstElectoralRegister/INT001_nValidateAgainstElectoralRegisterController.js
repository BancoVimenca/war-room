({
	onInit : function(component, event, helper) {
		var recordId = component.get("v.recordId");
        
        helper.callUpdateAccount(component, recordId);
	}
})