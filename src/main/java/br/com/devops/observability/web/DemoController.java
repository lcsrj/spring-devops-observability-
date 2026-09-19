package br.com.devops.observability.web;

import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import br.com.devops.observability.model.DemoResponse;
import br.com.devops.observability.model.LogResponse;
import br.com.devops.observability.model.TrafficRequest;
import br.com.devops.observability.model.TrafficResult;
import br.com.devops.observability.service.LogDemoService;
import br.com.devops.observability.service.TrafficGeneratorService;
import jakarta.servlet.http.HttpServletRequest;

/**
 * Endpoints de demonstracao acionados pela interface.
 *
 * <p>Todos produzem efeitos reais: status HTTP reais (contabilizados pelo Micrometer) e
 * eventos de log reais (enviados ao Graylog pelo appender GELF).</p>
 */
@RestController
@RequestMapping(value = "/api/demo", produces = MediaType.APPLICATION_JSON_VALUE)
public class DemoController {

    private static final Logger LOG = LoggerFactory.getLogger(DemoController.class);

    private final LogDemoService logDemoService;
    private final TrafficGeneratorService trafficGenerator;

    public DemoController(LogDemoService logDemoService, TrafficGeneratorService trafficGenerator) {
        this.logDemoService = logDemoService;
        this.trafficGenerator = trafficGenerator;
    }

    @GetMapping("/ok")
    public DemoResponse ok(HttpServletRequest request) {
        String correlationId = CorrelationIdFilter.currentCorrelationId(request);
        LOG.info("Endpoint de sucesso atendido com correlation id {}", correlationId);
        return new DemoResponse(200, "SUCCESS",
                "Requisicao processada com sucesso pelo backend Spring Boot.",
                correlationId, now());
    }

    @GetMapping("/bad-request")
    public DemoResponse badRequest() {
        throw new DemoBadRequestException(
                "Parametro obrigatorio ausente ou invalido (erro de cliente simulado).");
    }

    @GetMapping("/error")
    public DemoResponse serverError() {
        throw new DemoServerException(
                "Dependencia interna indisponivel (falha de servidor simulada).");
    }

    @PostMapping("/log/debug")
    public LogResponse logDebug(HttpServletRequest request) {
        return logDemoService.debug(CorrelationIdFilter.currentCorrelationId(request),
                "requisitado via painel de observabilidade");
    }

    @PostMapping("/log/info")
    public LogResponse logInfo(HttpServletRequest request) {
        return logDemoService.info(CorrelationIdFilter.currentCorrelationId(request),
                "requisitado via painel de observabilidade");
    }

    @PostMapping("/log/warn")
    public LogResponse logWarn(HttpServletRequest request) {
        return logDemoService.warn(CorrelationIdFilter.currentCorrelationId(request),
                "requisitado via painel de observabilidade");
    }

    @PostMapping("/log/error")
    public LogResponse logError(HttpServletRequest request) {
        return logDemoService.error(CorrelationIdFilter.currentCorrelationId(request),
                "requisitado via painel de observabilidade");
    }

    /**
     * Dispara uma rajada de requisicoes HTTP reais contra a propria aplicacao.
     * O corpo e opcional; sem corpo, usa a quantidade default configurada.
     */
    @PostMapping("/traffic")
    public TrafficResult traffic(@RequestBody(required = false) TrafficRequest body,
                                 HttpServletRequest request) {
        Integer requested = (body == null) ? null : body.requests();
        return trafficGenerator.generate(requested, CorrelationIdFilter.currentCorrelationId(request));
    }

    private static String now() {
        return OffsetDateTime.now().truncatedTo(ChronoUnit.MILLIS).toString();
    }
}
