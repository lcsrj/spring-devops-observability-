package br.com.devops.observability.service;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import br.com.devops.observability.config.AppProperties;
import br.com.devops.observability.config.SelfEndpointResolver;
import br.com.devops.observability.model.TrafficResult;
import br.com.devops.observability.web.CorrelationIdFilter;

/**
 * Gerador de trafego real.
 *
 * <p>Ao contrario de um mock de frontend, este servico executa requisicoes HTTP de verdade
 * contra os proprios endpoints da aplicacao. Isso faz com que as chamadas atravessem o
 * pipeline do Spring MVC e sejam contabilizadas por {@code http_server_requests_seconds},
 * alimentando Prometheus e Grafana com dados legitimos.</p>
 *
 * <p>A distribuicao e deliberadamente mista (aprox. 70% 2xx, 20% 4xx, 10% 5xx) para que os
 * paineis de status HTTP tenham series 2xx, 4xx e 5xx simultaneamente.</p>
 */
@Service
public class TrafficGeneratorService {

    private static final Logger LOG = LoggerFactory.getLogger(TrafficGeneratorService.class);

    /** Padrao repetido ciclicamente: 7 chamadas OK, 2 de erro de cliente, 1 de erro de servidor. */
    private static final List<String> PATTERN = List.of(
            "/api/demo/ok",
            "/api/demo/ok",
            "/api/demo/bad-request",
            "/api/demo/ok",
            "/api/demo/ok",
            "/api/demo/error",
            "/api/demo/ok",
            "/api/demo/bad-request",
            "/api/demo/ok",
            "/api/demo/ok");

    private final RestClient restClient;
    private final SelfEndpointResolver selfEndpoint;
    private final AppProperties properties;

    public TrafficGeneratorService(RestClient selfCallRestClient,
                                   SelfEndpointResolver selfEndpoint,
                                   AppProperties properties) {
        this.restClient = selfCallRestClient;
        this.selfEndpoint = selfEndpoint;
        this.properties = properties;
    }

    /**
     * @param requested quantidade solicitada; {@code null} usa o default configurado
     * @return resumo real das respostas obtidas
     */
    public TrafficResult generate(Integer requested, String correlationId) {
        int total = normalize(requested);
        String baseUrl = selfEndpoint.baseUrl();

        int ok = 0;
        int clientError = 0;
        int serverError = 0;
        int failures = 0;

        long startedAt = System.nanoTime();
        LOG.info("Iniciando geracao de trafego: {} requisicoes contra {}", total, baseUrl);

        for (int i = 0; i < total; i++) {
            String path = PATTERN.get(i % PATTERN.size());
            try {
                HttpStatusCode status = restClient.get()
                        .uri(baseUrl + path)
                        .header(CorrelationIdFilter.TRAFFIC_HEADER, "true")
                        .header(CorrelationIdFilter.CORRELATION_HEADER, correlationId)
                        .retrieve()
                        // Desliga o tratamento padrao de erro: 4xx/5xx sao resultados esperados aqui.
                        .onStatus(code -> true, (request, response) -> { })
                        .toBodilessEntity()
                        .getStatusCode();

                if (status.is2xxSuccessful()) {
                    ok++;
                } else if (status.is4xxClientError()) {
                    clientError++;
                } else if (status.is5xxServerError()) {
                    serverError++;
                } else {
                    failures++;
                }
            } catch (RuntimeException ex) {
                failures++;
                LOG.warn("Requisicao de trafego para {} falhou no transporte: {}", path, ex.getMessage());
            }
        }

        long durationMs = (System.nanoTime() - startedAt) / 1_000_000;
        TrafficResult result = new TrafficResult(total, ok + clientError + serverError + failures,
                ok, clientError, serverError, failures, durationMs);

        LOG.info("Geracao de trafego concluida: 2xx={} 4xx={} 5xx={} falhas={} em {}ms",
                ok, clientError, serverError, failures, durationMs);
        return result;
    }

    private int normalize(Integer requested) {
        int value = (requested == null || requested <= 0)
                ? properties.getTraffic().getDefaultRequests()
                : requested;
        return Math.min(value, properties.getTraffic().getMaxRequests());
    }
}
