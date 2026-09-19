package br.com.devops.observability.web;

import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import br.com.devops.observability.service.ActionHistoryService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * Alimenta o historico da interface medindo a requisicao real no servidor.
 *
 * <p>Requisicoes internas do gerador de trafego sao ignoradas individualmente (senao uma
 * rajada de 200 chamadas apagaria o historico); o gerador registra uma unica entrada
 * agregada com o resultado consolidado.</p>
 */
@Component
public class ActionAuditInterceptor implements HandlerInterceptor {

    private static final String START_TIME = "observability.startNanos";

    private final ActionHistoryService history;

    public ActionAuditInterceptor(ActionHistoryService history) {
        this.history = history;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        request.setAttribute(START_TIME, System.nanoTime());
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response,
                                Object handler, Exception ex) {
        if (CorrelationIdFilter.isGeneratedTraffic(request)) {
            return;
        }

        Object start = request.getAttribute(START_TIME);
        long durationMs = (start instanceof Long startNanos)
                ? (System.nanoTime() - startNanos) / 1_000_000
                : 0L;

        history.record(
                describe(request),
                request.getMethod(),
                request.getRequestURI(),
                response.getStatus(),
                durationMs,
                CorrelationIdFilter.currentCorrelationId(request));
    }

    private String describe(HttpServletRequest request) {
        String uri = request.getRequestURI();
        return switch (uri) {
            case "/api/demo/ok" -> "Requisicao 200 OK";
            case "/api/demo/bad-request" -> "Requisicao 400 Bad Request";
            case "/api/demo/error" -> "Requisicao 500 Internal Server Error";
            case "/api/demo/log/debug" -> "Log DEBUG gerado";
            case "/api/demo/log/info" -> "Log INFO gerado";
            case "/api/demo/log/warn" -> "Log WARN gerado";
            case "/api/demo/log/error" -> "Log ERROR gerado";
            case "/api/demo/traffic" -> "Rajada de trafego";
            default -> "Chamada " + uri;
        };
    }
}
