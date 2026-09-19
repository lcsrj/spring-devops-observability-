package br.com.devops.observability.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import br.com.devops.observability.model.ActionRecord;
import br.com.devops.observability.service.ActionHistoryService;
import io.micrometer.core.instrument.MeterRegistry;

/** Cobre os endpoints de demonstracao de status HTTP, de geracao de logs e o historico. */
@SpringBootTest
@AutoConfigureMockMvc
class DemoEndpointTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ActionHistoryService history;

    @Autowired
    private MeterRegistry meterRegistry;

    @BeforeEach
    void resetHistory() {
        history.clear();
    }

    @Test
    @DisplayName("GET /api/demo/ok devolve 200 com payload de sucesso")
    void okEndpointReturns200() throws Exception {
        mockMvc.perform(get("/api/demo/ok"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value(200))
                .andExpect(jsonPath("$.outcome").value("SUCCESS"))
                .andExpect(jsonPath("$.correlationId").exists());
    }

    @Test
    @DisplayName("GET /api/demo/bad-request devolve 400 com payload de erro")
    void badRequestEndpointReturns400() throws Exception {
        mockMvc.perform(get("/api/demo/bad-request"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.error").value("Bad Request"))
                .andExpect(jsonPath("$.path").value("/api/demo/bad-request"))
                .andExpect(jsonPath("$.correlationId").exists());
    }

    @Test
    @DisplayName("GET /api/demo/error devolve 500 com payload de erro")
    void errorEndpointReturns500() throws Exception {
        mockMvc.perform(get("/api/demo/error"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.status").value(500))
                .andExpect(jsonPath("$.error").value("Internal Server Error"))
                .andExpect(jsonPath("$.path").value("/api/demo/error"));
    }

    @Test
    @DisplayName("os quatro endpoints de log respondem com o nivel correspondente")
    void logEndpointsEmitEachLevel() throws Exception {
        for (String level : List.of("debug", "info", "warn", "error")) {
            mockMvc.perform(post("/api/demo/log/" + level))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.level").value(level.toUpperCase()))
                    .andExpect(jsonPath("$.logger").exists())
                    .andExpect(jsonPath("$.message").exists())
                    .andExpect(jsonPath("$.correlationId").exists());
        }

        // Um contador por nivel deve existir no registry apos a emissao.
        for (String level : List.of("DEBUG", "INFO", "WARN", "ERROR")) {
            assertThat(meterRegistry.get("app.demo.log.events").tag("level", level).counter().count())
                    .as("contador de eventos de log para o nivel %s", level)
                    .isGreaterThanOrEqualTo(1.0);
        }
    }

    @Test
    @DisplayName("o historico registra as acoes com status e duracao medidos no servidor")
    void historyRecordsExecutedActions() throws Exception {
        mockMvc.perform(get("/api/demo/ok")).andExpect(status().isOk());
        mockMvc.perform(get("/api/demo/bad-request")).andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/demo/error")).andExpect(status().isInternalServerError());

        List<ActionRecord> recent = history.recent(10);
        assertThat(recent).hasSize(3);
        // Mais recente primeiro.
        assertThat(recent.get(0).status()).isEqualTo(500);
        assertThat(recent.get(1).status()).isEqualTo(400);
        assertThat(recent.get(2).status()).isEqualTo(200);
        assertThat(recent).allSatisfy(record -> {
            assertThat(record.correlationId()).isNotBlank();
            assertThat(record.durationMs()).isGreaterThanOrEqualTo(0);
            assertThat(record.timestamp()).isNotBlank();
        });

        mockMvc.perform(get("/api/history"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3))
                .andExpect(jsonPath("$[0].status").value(500));
    }

    @Test
    @DisplayName("consultas de estado nao poluem o historico de acoes")
    void statusPollingIsNotRecordedInHistory() throws Exception {
        mockMvc.perform(get("/api/status")).andExpect(status().isOk());
        mockMvc.perform(get("/api/history")).andExpect(status().isOk());

        assertThat(history.recent(10)).isEmpty();
    }

    @Test
    @DisplayName("o historico e limitado para nao crescer indefinidamente")
    void historyIsBounded() {
        for (int i = 0; i < ActionHistoryService.MAX_ENTRIES + 25; i++) {
            history.record("acao " + i, "GET", "/api/demo/ok", 200, 1, "cid-" + i);
        }
        assertThat(history.recent(ActionHistoryService.MAX_ENTRIES))
                .hasSize(ActionHistoryService.MAX_ENTRIES);
    }
}
