import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';

import getContextoPorExcepcion from '@salesforce/apex/FSC_ExcepcionesCreditoController.getContextoPorExcepcion';
import aprobarExcepcion from '@salesforce/apex/FSC_ExcepcionesCreditoController.aprobarExcepcion';
import aprobarExcepcionConCondicion from '@salesforce/apex/FSC_ExcepcionesCreditoController.aprobarExcepcionConCondicion';
import devolverExcepcionConObservacion from '@salesforce/apex/FSC_ExcepcionesCreditoController.devolverExcepcionConObservacion';
import rechazarExcepcion from '@salesforce/apex/FSC_ExcepcionesCreditoController.rechazarExcepcion';
import subsanarYReenviarExcepcion from '@salesforce/apex/FSC_ExcepcionesCreditoController.subsanarYReenviarExcepcion';
import responderCondicionCliente from '@salesforce/apex/FSC_ExcepcionesCreditoController.responderCondicionCliente';

export default class Fsc_ExcepcionAcciones extends LightningElement {
	@api recordId;

	@track loading = false;
	@track showModalCondicion = false;
	@track showModalObservar = false;
	@track showModalRechazar = false;
	@track showModalSubsanar = false;

	@track condicionInput = '';
	@track observacionesInput = '';
	@track motivoRechazoInput = '';
	@track subsanacionInput = '';

	wiredContextResult;

	@wire(getContextoPorExcepcion, { excepcionId: '$recordId' })
	wiredContext(result) {
		this.wiredContextResult = result;
	}

	get ctx() {
		return (
			this.wiredContextResult?.data || {
				excepcionId: null,
				solicitudId: null,
				estado: '',
				condicion: '',
				observaciones: '',
				pasoObservacion: '',
				motivo: '',
				tipo: '',
				hasActiveApproval: false,
				aprobadorActual: '',
				canActOnApproval: false,
				puedeResponderCondicion: false,
				puedeSubsanarObservacion: false
			}
		);
	}

	get showBannerPendiente() {
		return this.ctx.estado === 'Pendiente' && !this.ctx.condicion;
	}

	get mensajePendiente() {
		const aprobador = this.ctx.aprobadorActual ? ` Asignada a: ${this.ctx.aprobadorActual}.` : '';
		return `Excepción pendiente de decisión.${aprobador}`;
	}

	get showBannerObservada() {
		return this.ctx.estado === 'Observada';
	}

	get mensajeObservada() {
		const origen = this.ctx.pasoObservacion ? ` (${this.ctx.pasoObservacion})` : '';
		return `Devuelta con observaciones${origen}: ${this.ctx.observaciones || ''}`;
	}

	get showBannerCondicion() {
		return this.ctx.estado === 'Pendiente' && !!this.ctx.condicion;
	}

	get showBannerAprobada() {
		return this.ctx.estado === 'Aprobada';
	}

	get showBannerRechazada() {
		return this.ctx.estado === 'Rechazada';
	}

	get showAccionesAprobador() {
		return this.ctx.hasActiveApproval === true && this.ctx.canActOnApproval === true && this.ctx.estado === 'Pendiente' && !this.ctx.condicion;
	}

	get showSubsanar() {
		return this.ctx.puedeSubsanarObservacion === true;
	}

	get showRespuestaCondicion() {
		return this.ctx.puedeResponderCondicion === true;
	}

	async handleAprobar() {
		this.loading = true;
		try {
			await aprobarExcepcion({ excepcionId: this.recordId });
			this.showToast('Actualizado', 'La decisión de aprobación fue registrada.', 'success');
			await this.refreshData();
		} catch (error) {
			this.showToast('Error', this.extractError(error, 'No se pudo aprobar la excepción.'), 'error');
		} finally {
			this.loading = false;
		}
	}

	openModalCondicion() {
		this.condicionInput = '';
		this.showModalCondicion = true;
	}

	closeModalCondicion() {
		this.showModalCondicion = false;
	}

	handleCondicionChange(event) {
		this.condicionInput = event.target.value;
	}

	async handleConfirmarCondicion() {
		const condicion = (this.condicionInput || '').trim();
		if (!condicion) {
			this.showToast('Error', 'Condición requerida.', 'error');
			return;
		}
		this.showModalCondicion = false;
		this.loading = true;
		try {
			await aprobarExcepcionConCondicion({ excepcionId: this.recordId, condicion });
			this.showToast('Actualizado', 'La excepción quedó pendiente de respuesta del cliente.', 'success');
			await this.refreshData();
		} catch (error) {
			this.showToast('Error', this.extractError(error, 'No se pudo aprobar con condición.'), 'error');
		} finally {
			this.loading = false;
		}
	}

	openModalObservar() {
		this.observacionesInput = '';
		this.showModalObservar = true;
	}

	closeModalObservar() {
		this.showModalObservar = false;
	}

	handleObservacionesChange(event) {
		this.observacionesInput = event.target.value;
	}

	async handleConfirmarObservar() {
		const observaciones = (this.observacionesInput || '').trim();
		if (!observaciones) {
			this.showToast('Error', 'Las observaciones son requeridas para devolver la excepción.', 'error');
			return;
		}
		this.showModalObservar = false;
		this.loading = true;
		try {
			await devolverExcepcionConObservacion({ excepcionId: this.recordId, observaciones });
			this.showToast('Actualizado', 'La excepción fue devuelta con observaciones al Oficial de Negocio.', 'success');
			await this.refreshData();
		} catch (error) {
			this.showToast('Error', this.extractError(error, 'No se pudo devolver la excepción con observaciones.'), 'error');
		} finally {
			this.loading = false;
		}
	}

	openModalRechazar() {
		this.motivoRechazoInput = '';
		this.showModalRechazar = true;
	}

	closeModalRechazar() {
		this.showModalRechazar = false;
	}

	handleMotivoRechazoChange(event) {
		this.motivoRechazoInput = event.target.value;
	}

	async handleConfirmarRechazar() {
		const motivo = (this.motivoRechazoInput || '').trim();
		if (!motivo) {
			this.showToast('Error', 'Motivo requerido.', 'error');
			return;
		}
		if (motivo.length > 255) {
			this.showToast('Error', 'Motivo máximo 255 caracteres.', 'error');
			return;
		}
		this.showModalRechazar = false;
		this.loading = true;
		try {
			await rechazarExcepcion({ excepcionId: this.recordId, motivo });
			this.showToast('Actualizado', 'La excepción fue rechazada y el crédito se cerró como perdido.', 'success');
			await this.refreshData();
		} catch (error) {
			this.showToast('Error', this.extractError(error, 'No se pudo rechazar la excepción.'), 'error');
		} finally {
			this.loading = false;
		}
	}

	openModalSubsanar() {
		this.subsanacionInput = this.ctx.motivo || '';
		this.showModalSubsanar = true;
	}

	closeModalSubsanar() {
		this.showModalSubsanar = false;
	}

	handleSubsanacionChange(event) {
		this.subsanacionInput = event.target.value;
	}

	async handleConfirmarSubsanar() {
		const nuevaDescripcion = (this.subsanacionInput || '').trim();
		if (!nuevaDescripcion) {
			this.showToast('Error', 'La descripción subsanada es obligatoria.', 'error');
			return;
		}
		this.showModalSubsanar = false;
		this.loading = true;
		try {
			await subsanarYReenviarExcepcion({ excepcionId: this.recordId, nuevaDescripcion });
			this.showToast('Excepción reenviada', 'La excepción subsanada fue enviada nuevamente a aprobación.', 'success');
			await this.refreshData();
		} catch (error) {
			this.showToast('Error', this.extractError(error, 'No se pudo subsanar y reenviar la excepción.'), 'error');
		} finally {
			this.loading = false;
		}
	}

	async handleClienteAprueba() {
		await this.procesarRespuestaCliente(true);
	}

	async handleClienteRechaza() {
		await this.procesarRespuestaCliente(false);
	}

	async procesarRespuestaCliente(clienteAprueba) {
		this.loading = true;
		try {
			await responderCondicionCliente({ excepcionId: this.recordId, clienteAprueba });
			const msg = clienteAprueba
				? 'La excepción quedó aprobada.'
				: 'La excepción quedó rechazada y la solicitud fue cerrada como perdida.';
			this.showToast('Actualizado', msg, 'success');
			await this.refreshData();
		} catch (error) {
			this.showToast('Error', this.extractError(error, 'No se pudo registrar la respuesta del cliente.'), 'error');
		} finally {
			this.loading = false;
		}
	}

	async refreshData() {
		const recordIds = [{ recordId: this.recordId }];
		if (this.ctx.solicitudId) {
			recordIds.push({ recordId: this.ctx.solicitudId });
		}
		await notifyRecordUpdateAvailable(recordIds);
		if (this.wiredContextResult) {
			await refreshApex(this.wiredContextResult);
		}
		this.dispatchEvent(new RefreshEvent());
	}

	extractError(error, fallback) {
		if (error?.body?.message) {
			return error.body.message;
		}
		if (Array.isArray(error?.body) && error.body.length > 0 && error.body[0].message) {
			return error.body[0].message;
		}
		return error?.message || fallback;
	}

	showToast(title, message, variant) {
		this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
	}
}
