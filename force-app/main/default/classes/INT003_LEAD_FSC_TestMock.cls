@isTest
public class INT003_LEAD_FSC_TestMock implements HttpCalloutMock {
    protected Integer code;
    protected String status;
    protected String bodyAsString;

    public INT003_LEAD_FSC_TestMock() {
        this.code = 200;
        this.status = 'OK';
        this.bodyAsString = '{"responseCode":"0","responseDesc":"OK","internalCoincidences":"N","externalCoincidences":"N","FoundList":"","cumplo360Relevancia":80}';
    }

    public INT003_LEAD_FSC_TestMock(Integer code, String status, String body) {
        this.code = code;
        this.status = status;
        this.bodyAsString = body;
    }

    public HttpResponse respond(HttpRequest req) {
        HttpResponse resp = new HttpResponse();
        resp.setStatusCode(code);
        resp.setStatus(status);
        resp.setBody(bodyAsString);
        return resp;
    }
}
