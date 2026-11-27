global with sharing class FSC_ActaComiteDownloadAction {
	public class Request {
		@InvocableVariable(required=true)
		public Date actaDate;
	}

	public class Response {
		@InvocableVariable
		public Boolean success;
		@InvocableVariable
		public String message;
		@InvocableVariable
		public String pdfUrl;
		@InvocableVariable
		public Integer totalApplications;
	}

	@InvocableMethod(
		label='Generar URL Acta Comité (PDF)'
		description='Devuelve la URL de descarga del PDF para la fecha seleccionada.'
	)
	public static List<Response> generateUrl(List<Request> requests) {
		List<Response> out = new List<Response>();
		for (Request r : requests) {
			out.add(generateOne(r));
		}
		return out;
	}

	private static Response generateOne(Request req) {
		Response res = new Response();
		try {
			if (req == null || req.actaDate == null) {
				res.success = false;
				res.message = 'actaDate es requerido.';
				return res;
			}

			Integer cnt = FSC_ActaComitePDFController.countEligibleApplications(req.actaDate);
			res.totalApplications = cnt;

			if (cnt == 0) {
				res.success = true;
				res.message = 'No hay solicitudes decididas por comité para la fecha seleccionada.';
				res.pdfUrl = null;
				return res;
			}

			PageReference pr = Page.FSC_ActaComitePDF;
			pr.getParameters().put('actaDate', String.valueOf(req.actaDate));
			pr.getParameters().put('fn', buildFileName(req.actaDate));

			String base = URL.getOrgDomainUrl().toExternalForm();
			res.pdfUrl = base + pr.getUrl();

			res.success = true;
			res.message = 'URL generada.';
			return res;
		} catch (Exception e) {
			res.success = false;
			res.message = e.getMessage();
			res.pdfUrl = null;
			return res;
		}
	}

	private static String buildFileName(Date d) {
		String iso =
			d.year() +
			'-' +
			String.valueOf(d.month()).leftPad(2, '0') +
			'-' +
			String.valueOf(d.day()).leftPad(2, '0');
		return 'Acta_Comite_Credito_' + iso + '.pdf';
	}
}
