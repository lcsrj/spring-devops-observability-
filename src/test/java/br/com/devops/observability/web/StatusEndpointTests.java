package br.com.devops.observability.web;

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

/** Cobre a pagina inicial, o endpoint de status e a exposicao das metricas. */
@SpringBootTest
@AutoConfigureMockMvc
class StatusEndpointTests {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("GET / entrega a interface HTML do painel")
    void indexServesHtmlDashboard() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Gerar trafego")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Gerar logs")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Historico recente")));
    }

    @Test
    @DisplayName("GET /api/status devolve o estado real da aplicacao")
    void statusReturnsRuntimeState() throws Exception {
        mockMvc.perform(get("/api/status"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.application").value("DevOps Observability Control Center"))
                .andExpect(jsonPath("$.version").exists())
                .andExpect(jsonPath("$.environment").exists())
                .andExpect(jsonPath("$.uptimeSeconds").value(greaterThanOrEqualTo(0)))
                .andExpect(jsonPath("$.heapUsedBytes").value(greaterThanOrEqualTo(1)))
                .andExpect(jsonPath("$.liveThreads").value(greaterThanOrEqualTo(1)));
    }

    @Test
    @DisplayName("toda resposta carrega um correlation id no header")
    void correlationIdIsAlwaysPresent() throws Exception {
        mockMvc.perform(get("/api/status"))
                .andExpect(status().isOk())
                .andExpect(header().exists(CorrelationIdFilter.CORRELATION_HEADER));
    }

    @Test
    @DisplayName("um correlation id enviado pelo cliente e propagado de volta")
    void correlationIdIsPropagated() throws Exception {
        mockMvc.perform(get("/api/status").header(CorrelationIdFilter.CORRELATION_HEADER, "teste-123"))
                .andExpect(status().isOk())
                .andExpect(header().string(CorrelationIdFilter.CORRELATION_HEADER, "teste-123"));
    }

    @Test
    @DisplayName("GET /actuator/health responde UP")
    void actuatorHealthIsUp() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    @DisplayName("o health nao depende de espaco em disco do host")
    void healthDoesNotDependOnHostDiskSpace() throws Exception {
        // O indicador diskSpace esta desabilitado de proposito: a aplicacao nao usa
        // disco, e um volume cheio no host faria /actuator/health responder 503 com a
        // aplicacao perfeitamente saudavel. Este teste trava essa decisao.
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.components.diskSpace").doesNotExist())
                .andExpect(jsonPath("$.components.ping.status").value("UP"))
                .andExpect(jsonPath("$.components.readinessState.status").value("UP"));
    }

    @Test
    @DisplayName("GET /actuator/info expõe nome, versao e ambiente")
    void actuatorInfoExposesMetadata() throws Exception {
        mockMvc.perform(get("/actuator/info"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.app.name").exists())
                .andExpect(jsonPath("$.app.version").exists());
    }

    @Test
    @DisplayName("GET /actuator/prometheus expõe metricas de JVM, CPU e HTTP com as tags comuns")
    void prometheusEndpointExposesRealMetrics() throws Exception {
        // Gera pelo menos uma requisicao HTTP antes de coletar, garantindo a serie http_server_requests.
        mockMvc.perform(get("/api/demo/ok")).andExpect(status().isOk());

        mockMvc.perform(get("/actuator/prometheus"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("jvm_memory_used_bytes")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("jvm_memory_max_bytes")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("process_cpu_usage")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("jvm_threads_live_threads")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("process_uptime_seconds")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("http_server_requests_seconds_count")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("application=\"spring-devops-observability\"")));
    }

    @Test
    @DisplayName("endpoints administrativos nao solicitados ficam fora da superficie exposta")
    void unnecessaryActuatorEndpointsAreNotExposed() throws Exception {
        mockMvc.perform(get("/actuator/env")).andExpect(status().isNotFound());
        mockMvc.perform(get("/actuator/beans")).andExpect(status().isNotFound());
        mockMvc.perform(get("/actuator/heapdump")).andExpect(status().isNotFound());
    }
}
