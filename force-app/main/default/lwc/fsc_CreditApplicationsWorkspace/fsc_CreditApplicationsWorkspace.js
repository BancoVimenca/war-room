import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getWorkspaceMetrics from '@salesforce/apex/FSC_CreditWorkspaceController.getWorkspaceMetrics';
import getCreditApplications from '@salesforce/apex/FSC_CreditWorkspaceController.getCreditApplications';
import processApprovalDecision from '@salesforce/apex/FSC_CreditWorkspaceController.processApprovalDecision';

const ROLE_OPTIONS = [
    { label: '🌐 Vista Global Administrador (Total Consolidado)', value: 'ADMIN_ALL' },
    { label: '👤 Oficial de Negocios (Originador)', value: 'OFICIAL' },
    { label: '🔍 Analista de Crédito & Buró (Mesa de Riesgo)', value: 'ANALISTA' },
    { label: '⚠️ Aprobador de Excepciones & VP de Negocios', value: 'EXCEPCIONES' },
    { label: '🏛️ Comité de Crédito & Supervisores', value: 'COMITE' },
    { label: '📑 Formalización & Pagarés (Custodia)', value: 'FORMALIZACION' }
];

export default class Fsc_CreditApplicationsWorkspace extends NavigationMixin(LightningElement) {
    @track activeTab = 'aprobaciones';
    @track searchKey = '';
    @track selectedRole = 'ADMIN_ALL';
    @track roleOptions = ROLE_OPTIONS;
    @track rows = [];
    @track isLoading = true;
    @track sortedBy = 'createdDate';
    @track sortDirection = 'desc';

    // Modal de dictamen de aprobación
    @track isModalOpen = false;
    @track selectedRow = {};
    @track decisionComments = '';
    @track isProcessingDecision = false;

    // Modal de generación de actas para comité
    @track isActaModalOpen = false;

    @track metrics = {
        misPendientesDirectos: 0,
        excepcionesActivas: 0,
        enRecepcion: 0,
        enAnalisis: 0,
        comiteSupervision: 0,
        formalizacionCustodia: 0,
        montoTotalCartera: 0,
        montoGanado: 0,
        montoPerdido: 0,
        isAdministrator: false,
        canGenerateActasComite: false
    };

    wiredMetricsResult;
    wiredRowsResult;

    get columns() {
        return [
            {
                label: 'Código / Correlativo',
                fieldName: 'recordUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'numeroSolicitud' },
                    target: '_blank'
                },
                sortable: true,
                initialWidth: 160
            },
            {
                label: 'Turno / Responsable Activo',
                fieldName: 'turnoActual',
                type: 'text',
                sortable: true,
                initialWidth: 200,
                cellAttributes: {
                    class: 'font-bold slds-text-color_default'
                }
            },
            {
                label: 'Subestado Actual',
                fieldName: 'subestado',
                type: 'text',
                sortable: true,
                initialWidth: 220
            },
            {
                label: 'Fecha en Subestado',
                fieldName: 'fechaSubestado',
                type: 'date',
                typeAttributes: {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit'
                },
                sortable: true,
                initialWidth: 170
            },
            {
                label: 'Fecha Creación',
                fieldName: 'createdDate',
                type: 'date',
                typeAttributes: {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit'
                },
                sortable: true,
                initialWidth: 150
            },
            {
                label: 'Cliente',
                fieldName: 'accountName',
                type: 'text',
                sortable: true,
                initialWidth: 200
            },
            {
                label: 'Producto / Tipo',
                fieldName: 'productType',
                type: 'text',
                sortable: true,
                initialWidth: 160
            },
            {
                label: 'Monto Solicitado',
                fieldName: 'monto',
                type: 'currency',
                typeAttributes: { currencyCode: 'DOP' },
                sortable: true,
                initialWidth: 140
            },
            {
                label: 'Excepción',
                fieldName: 'detalleExcepcion',
                type: 'text',
                sortable: true,
                initialWidth: 170,
                cellAttributes: {
                    class: { fieldName: 'excepcionCssClass' }
                }
            },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: this.getRowActions.bind(this)
                }
            }
        ];
    }

    getRowActions(row, doneCallback) {
        const actions = [
            { label: 'Ver Solicitud', name: 'view_record' }
        ];
        if (row.canApprove && row.workitemId) {
            actions.unshift({
                label: '⚡ Dictaminar Aprobación',
                name: 'decide_approval',
                iconName: 'utility:approval'
            });
        }
        doneCallback(actions);
    }

    @wire(getWorkspaceMetrics, { simulatedRole: '$selectedRole' })
    wiredMetrics(result) {
        this.wiredMetricsResult = result;
        if (result.data) {
            this.metrics = result.data;
        }
    }

    @wire(getCreditApplications, { tabName: '$activeTab', searchKey: '$searchKey', simulatedRole: '$selectedRole' })
    wiredApplications(result) {
        this.wiredRowsResult = result;
        this.isLoading = false;
        if (result.data) {
            this.rows = result.data.map(item => {
                return {
                    ...item,
                    excepcionCssClass: item.tieneExcepcion ? 'slds-text-color_error font-bold' : 'slds-text-color_weak'
                };
            });
        } else if (result.error) {
            this.rows = [];
        }
    }

    get isAdminUser() {
        return this.metrics.isAdministrator === true;
    }

    get showActaComiteButton() {
        return this.metrics.canGenerateActasComite === true;
    }

    get isSimulating() {
        return this.isAdminUser && this.selectedRole !== 'ADMIN_ALL';
    }

    get currentRoleLabel() {
        const found = this.roleOptions.find(opt => opt.value === this.selectedRole);
        return found ? found.label : this.selectedRole;
    }

    get formattedTotalMonto() {
        const monto = this.metrics.montoTotalCartera || 0;
        return this.formatCurrency(monto);
    }

    get formattedMontoGanado() {
        const monto = this.metrics.montoGanado || 0;
        return this.formatCurrency(monto);
    }

    get formattedMontoPerdido() {
        const monto = this.metrics.montoPerdido || 0;
        return this.formatCurrency(monto);
    }

    formatCurrency(val) {
        return new Intl.NumberFormat('es-DO', {
            style: 'currency',
            currency: 'DOP',
            maximumFractionDigits: 0
        }).format(val);
    }

    handleRoleChange(event) {
        this.selectedRole = event.detail.value;
        this.isLoading = true;

        // Auto-seleccionar pestaña recomendada según el rol simulado
        if (this.selectedRole === 'EXCEPCIONES' || this.selectedRole === 'COMITE') {
            this.activeTab = 'aprobaciones';
        } else if (this.selectedRole === 'ANALISTA') {
            this.activeTab = 'analisis';
        } else if (this.selectedRole === 'FORMALIZACION') {
            this.activeTab = 'pagares';
        } else if (this.selectedRole === 'OFICIAL') {
            this.activeTab = 'recepcion';
        }
    }

    handleTabActive(event) {
        const newTab = event.target.value;
        if (newTab && this.activeTab !== newTab) {
            this.activeTab = newTab;
            this.isLoading = true;
        }
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.isLoading = true;
    }

    async handleRefresh() {
        this.isLoading = true;
        await Promise.all([
            refreshApex(this.wiredMetricsResult),
            refreshApex(this.wiredRowsResult)
        ]);
        this.isLoading = false;
    }

    handleOpenActaModal() {
        this.isActaModalOpen = true;
    }

    handleCloseActaModal() {
        this.isActaModalOpen = false;
    }

    handleActaFlowStatusChange(event) {
        const status = event.detail.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.isActaModalOpen = false;
        }
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'view_record') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.recordId,
                    actionName: 'view'
                }
            });
        } else if (actionName === 'decide_approval') {
            this.selectedRow = row;
            this.decisionComments = '';
            this.isModalOpen = true;
        }
    }

    closeModal() {
        this.isModalOpen = false;
        this.selectedRow = {};
        this.decisionComments = '';
        this.isProcessingDecision = false;
    }

    handleCommentsChange(event) {
        this.decisionComments = event.target.value;
    }

    async handleApproveDecision() {
        await this.executeDecision('Approve');
    }

    async handleRejectDecision() {
        await this.executeDecision('Reject');
    }

    async executeDecision(action) {
        if (!this.selectedRow.workitemId) {
            this.showToast('Error', 'No se encontró el ítem de aprobación correspondiente.', 'error');
            return;
        }

        this.isProcessingDecision = true;
        try {
            const message = await processApprovalDecision({
                workitemId: this.selectedRow.workitemId,
                action: action,
                comments: this.decisionComments
            });

            this.showToast('Éxito', message, 'success');
            this.closeModal();
            await this.handleRefresh();
        } catch (error) {
            const errorMsg = error.body ? error.body.message : error.message;
            this.showToast('Error en Dictamen', errorMsg, 'error');
            this.isProcessingDecision = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        const cloneData = [...this.rows];

        cloneData.sort((a, b) => {
            let valA = a[sortedBy] ? a[sortedBy] : '';
            let valB = b[sortedBy] ? b[sortedBy] : '';
            return sortDirection === 'asc' ? (valA > valB ? 1 : -1) : (valA < valB ? 1 : -1);
        });

        this.rows = cloneData;
        this.sortDirection = sortDirection;
        this.sortedBy = sortedBy;
    }
}
