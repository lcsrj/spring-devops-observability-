package br.com.devops.observability.service;

import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;

import org.slf4j.ILoggerFactory;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.stereotype.Service;

import ch.qos.logback.classic.LoggerContext;

import br.com.devops.observability.model.LogResponse;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

/**
 * Produz eventos de log reais nos quatro niveis exigidos pelo projeto.
 *
 * <p>Os eventos passam pelo Logback e, quando o perfil {@code docker} esta ativo, sao
 * enviados ao Graylog pelo appender GELF configurado em {@code logback-spring.xml}.
 * Nenhuma mensagem e fabricada no frontend.</p>
 */
@Service
public class LogDemoService {

    /** Logger dedicado, facilitando a busca por {@code source}/{@code logger_name} no Graylog. */
    private static final Logger LOG = LoggerFactory.getLogger("br.com.devops.observability.demo.LogGenerator");

    private final ActionHistoryService history;
    private final MeterRegistry meterRegistry;
    private final boolean gelfAppenderActive;

    public LogDemoService(ActionHistoryService history, MeterRegistry meterRegistry) {
        this.history = history;
        this.meterRegistry = meterRegistry;
        this.gelfAppenderActive = detectGelfAppender();
    }

    /**
     * Verifica no Logback se o appender GELF esta realmente anexado ao logger raiz.
     * A interface so informa "enviado ao Graylog" quando isso for verdade.
     */
    private static boolean detectGelfAppender() {
        ILoggerFactory factory = LoggerFactory.getILoggerFactory();
        if (factory instanceof LoggerContext context) {
            ch.qos.logback.classic.Logger root = context.getLogger(Logger.ROOT_LOGGER_NAME);
            return root.getAppender("GELF") != null;
        }
        return false;
    }

    public boolean isGelfAppenderActive() {
        return gelfAppenderActive;
    }

    public LogResponse debug(String correlationId, String note) {
        String message = message("DEBUG", note);
        withContext("DEBUG", () -> LOG.debug("{} | detalhe tecnico visivel apenas em nivel DEBUG", message));
        return response("DEBUG", message, correlationId);
    }

    public LogResponse info(String correlationId, String note) {
        String message = message("INFO", note);
        withContext("INFO", () -> LOG.info("{} | fluxo de negocio executado com sucesso", message));
        return response("INFO", message, correlationId);
    }

    public LogResponse warn(String correlationId, String note) {
        String message = message("WARN", note);
        withContext("WARN", () -> LOG.warn("{} | condicao degradada detectada, operacao seguiu com fallback", message));
        return response("WARN", message, correlationId);
    }

    public LogResponse error(String correlationId, String note) {
        String message = message("ERROR", note);
        withContext("ERROR", () -> LOG.error("{} | falha simulada no processamento da requisicao",
                message, new IllegalStateException("Falha simulada pelo painel de observabilidade")));
        return response("ERROR", message, correlationId);
    }

    private String message(String level, String note) {
        String suffix = (note == null || note.isBlank()) ? "acionado pelo painel" : note.trim();
        return "[demo-" + level.toLowerCase() + "] " + suffix;
    }

    /** Enriquece o evento com MDC, que o appender GELF publica como campos pesquisaveis. */
    private void withContext(String level, Runnable emitter) {
        MDC.put("demo_level", level);
        MDC.put("demo_action", "log-generator");
        try {
            emitter.run();
        } finally {
            MDC.remove("demo_level");
            MDC.remove("demo_action");
        }
        history.incrementLogEvents();
        Counter.builder("app.demo.log.events")
                .description("Eventos de log gerados pelo painel de demonstracao")
                .tag("level", level)
                .register(meterRegistry)
                .increment();
    }

    private LogResponse response(String level, String message, String correlationId) {
        return new LogResponse(
                level,
                LOG.getName(),
                message,
                correlationId,
                OffsetDateTime.now().truncatedTo(ChronoUnit.MILLIS).toString(),
                gelfAppenderActive);
    }
}
