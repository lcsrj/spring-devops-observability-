package br.com.devops.observability.web;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import br.com.devops.observability.config.SelfEndpointResolver;
import br.com.devops.observability.model.TrafficRequest;
import br.com.devops.observability.model.TrafficResult;

/**
 * Teste de integracao do gerador de trafego com servidor HTTP real.
 *
 * <p>O gerador dispara requisicoes de verdade contra a propria aplicacao, portanto precisa
 * de um servidor embutido ativo (webEnvironment = RANDOM_PORT) - diferente dos demais
 * testes, que usam MockMvc.</p>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TrafficGeneratorIntegrationTests {

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private SelfEndpointResolver selfEndpoint;

    @LocalServerPort
    private int serverPort;

    @Test
    @DisplayName("a porta real do servidor embutido e descoberta em runtime")
    void selfEndpointResolvesTheRunningPort() {
        assertThat(selfEndpoint.getPort()).isEqualTo(serverPort);
        assertThat(selfEndpoint.baseUrl()).isEqualTo("http://127.0.0.1:" + serverPort);
    }

    @Test
    @DisplayName("POST /api/demo/traffic executa requisicoes reais com 2xx, 4xx e 5xx")
    void trafficGeneratorProducesMixedStatuses() {
        ResponseEntity<TrafficResult> response = restTemplate.postForEntity(
                "/api/demo/traffic", new TrafficRequest(10), TrafficResult.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        TrafficResult result = response.getBody();
        assertThat(result).isNotNull();
        assertThat(result.requested()).isEqualTo(10);
        assertThat(result.executed()).isEqualTo(10);
        // O padrao ciclico do gerador produz 7 sucessos, 2 erros de cliente e 1 de servidor.
        assertThat(result.success2xx()).isEqualTo(7);
        assertThat(result.clientError4xx()).isEqualTo(2);
        assertThat(result.serverError5xx()).isEqualTo(1);
        assertThat(result.failures()).isZero();
        assertThat(result.durationMs()).isGreaterThanOrEqualTo(0);
    }

    @Test
    @DisplayName("sem corpo, o gerador usa a quantidade default configurada")
    void trafficGeneratorUsesConfiguredDefault() {
        ResponseEntity<TrafficResult> response = restTemplate.postForEntity(
                "/api/demo/traffic", null, TrafficResult.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().requested()).isEqualTo(25);
        assertThat(response.getBody().executed()).isEqualTo(25);
        assertThat(response.getBody().failures()).isZero();
    }

    @Test
    @DisplayName("o gerador respeita o teto de 200 requisicoes por rajada")
    void trafficGeneratorCapsRequestCount() {
        ResponseEntity<TrafficResult> response = restTemplate.postForEntity(
                "/api/demo/traffic", new TrafficRequest(5000), TrafficResult.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().requested()).isEqualTo(200);
    }

    @Test
    @DisplayName("o trafego gerado aparece nas metricas expostas ao Prometheus")
    void generatedTrafficShowsUpInPrometheusMetrics() {
        restTemplate.postForEntity("/api/demo/traffic", new TrafficRequest(20), TrafficResult.class);

        String metrics = restTemplate.getForObject("/actuator/prometheus", String.class);
        assertThat(metrics).isNotNull();
        assertThat(metrics).contains("http_server_requests_seconds_count");
        // As tres familias de status precisam existir para alimentar os paineis do Grafana.
        assertThat(metrics).contains("status=\"200\"");
        assertThat(metrics).contains("status=\"400\"");
        assertThat(metrics).contains("status=\"500\"");
        assertThat(metrics).contains("uri=\"/api/demo/ok\"");
        assertThat(metrics).contains("application=\"spring-devops-observability\"");
    }
}
