({
    callUpdateAccount : function(component, recordId) {
        var action = component.get("c.updateAccount");
        var self = this;
        action.setParams({ recordId : recordId });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var returnValue = response.getReturnValue();
                component.set("v.updateResponse", returnValue);
                
                self.updatePEP(component, recordId,returnValue);
                $A.get('e.force:refreshView').fire();
            }
            else {
                var returnValue = {};
                returnValue.requestStatusCode = 404;
                component.set("v.updateResponse", returnValue);
            }
            console.log('state :: ' + state);
            component.set("v.isLoading", false);
        });
        $A.enqueueAction(action);
        component.set("v.isLoading", true);
    },
    updatePEP : function(component, recordId,returnValue){
        if (returnValue.updateSuccess && !returnValue.skipPep){
            var action = component.get("c.updateAccountPEP");
            action.setParams({ recordId : recordId });
            
            action.setCallback(this, function(response) {
                var state = response.getState();
                if (state === "SUCCESS") {
                    var returnValue = response.getReturnValue();
                    if(returnValue.updateSuccess == false){
                        console.log('RV :: ' + JSON.stringify(returnValue));
                        component.set("v.updateResponse", returnValue);
                        $A.get('e.force:refreshView').fire();   
                    }                    
                }
                else {
                    var returnValue = {};
                    returnValue.requestStatusCode = 404;
                    component.set("v.updateResponse", returnValue);
                }
                console.log('state INT004 :: ' + state);
            });
            $A.enqueueAction(action);
        }
    }
})