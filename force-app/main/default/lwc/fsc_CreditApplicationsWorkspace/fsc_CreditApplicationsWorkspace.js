import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getWorkspaceMetrics from '@salesforce/apex/FSC_CreditWorkspaceController.getWorkspaceMetrics';
import getCreditApplications from '@salesforce/apex/FSC_CreditWorkspaceController.getCreditApplications';

const ROLE_OPTIONS = [
    { label: '🌐 Vista Global Administrador (Total Consolidado)', value: 'ADMIN_ALL' },
    { label: '👤 Oficial de Negocios (Originador)', value: 'OFICIAL' },
    { label: '🔍 Analista de Crédito & Buró (Mesa de Riesgo)', value: 'ANALISTA' },
    { label: '⚠️ Aprobador de Excepciones & VP de Negocios', value: 'EXCEPCIONES' },
    { label: '🏛️ Comité de Crédito & Supervisores', value: 'COMITE' },
    { label: '📑 Formalización & Pagarés (Custodia)', value: 'FORMALIZACION' }
];

const COLUMNS = [
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
        label: 'Solicitud de Crédito',
        fieldName: 'name',
        type: 'text',
        sortable: true,
        initialWidth: 260
    },
    {
        label: 'Cliente',
        fieldName: 'accountName',
        type: 'text',
        sortable: true,
        initialWidth: 220
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
        initialWidth: 150
    },
    {
        label: 'Subestado Actual',
        fieldName: 'subestado',
        type: 'text',
        sortable: true,
        initialWidth: 220
    },
    {
        label: 'Excepción',
        fieldName: 'detalleExcepcion',
        type: 'text',
        sortable: true,
        initialWidth: 180,
        cellAttributes: {
            class: { fieldName: 'excepcionCssClass' }
        }
    },
    {
        label: 'Turno / Responsable',
        fieldName: 'turnoActual',
        type: 'text',
        sortable: true,
        initialWidth: 180
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
        initialWidth: 160
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Ver Solicitud', name: 'view_record' }
            ]
        }
    }
];

export default class Fsc_CreditApplicationsWorkspace extends NavigationMixin(LightningElement) {
    @track activeTab = 'excepciones';
    @track searchKey = '';
    @track selectedRole = 'ADMIN_ALL';
    @track roleOptions = ROLE_OPTIONS;
    @track rows = [];
    @track columns = COLUMNS;
    @track isLoading = true;
    @track sortedBy = 'createdDate';
    @track sortDirection = 'desc';

    @track metrics = {
        misPendientesDirectos: 0,
        excepcionesActivas: 0,
        enAnalisis: 0,
        comiteSupervision: 0,
        formalizacionCustodia: 0,
        montoTotalCartera: 0,
        montoGanado: 0,
        montoPerdido: 0,
        isAdministrator: false
    };

    wiredMetricsResult;
    wiredRowsResult;

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
        if (this.selectedRole === 'EXCEPCIONES') {
            this.activeTab = 'excepciones';
        } else if (this.selectedRole === 'ANALISTA') {
            this.activeTab = 'analisis';
        } else if (this.selectedRole === 'COMITE') {
            this.activeTab = 'comite';
        } else if (this.selectedRole === 'FORMALIZACION') {
            this.activeTab = 'formalizacion';
        } else if (this.selectedRole === 'OFICIAL') {
            this.activeTab = 'mis_casos';
        }
    }

    handleTabActive(event) {
        const newTab = event.target.value;
        if (newTab && this.activeTab !== newTab) {
            this.activeTab = newTab;
            this.isLoading = true;
        }
    }

    handleTabSelect(event) {
        const val = event.target.value || event.detail.value;
        if (val && this.activeTab !== val) {
            this.activeTab = val;
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
        }
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
