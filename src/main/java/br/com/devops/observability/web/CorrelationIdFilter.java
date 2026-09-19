package br.com.devops.observability.web;

import java.io.IOException;
import java.util.UUID;

import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Garante um correlation id por requisicao.
 *
 * <p>O valor vai para o MDC (e portanto para os campos do GELF, ficando pesquisavel no
 * Graylog), para o atributo da requisicao (usado pelo historico) e para o header de
 * resposta, permitindo correlacionar o que a interface mostra com o que o Graylog indexou.</p>
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class CorrelationIdFilter extends OncePerRequestFilter {

    public static final String CORRELATION_HEADER = "X-Correlation-Id";
    public static final String TRAFFIC_HEADER = "X-Traffic-Generator";
    public static final String MDC_KEY = "correlation_id";
    public static final String REQUEST_ATTRIBUTE = "observability.correlationId";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String correlationId = request.getHeader(CORRELATION_HEADER);
        if (correlationId == null || correlationId.isBlank()) {
            correlationId = UUID.randomUUID().toString();
        }

        request.setAttribute(REQUEST_ATTRIBUTE, correlationId);
        response.setHeader(CORRELATION_HEADER, correlationId);
        MDC.put(MDC_KEY, correlationId);
        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_KEY);
        }
    }

    public static String currentCorrelationId(HttpServletRequest request) {
        Object value = request.getAttribute(REQUEST_ATTRIBUTE);
        return value instanceof String id ? id : "n/a";
    }

    public static boolean isGeneratedTraffic(HttpServletRequest request) {
        return "true".equalsIgnoreCase(request.getHeader(TRAFFIC_HEADER));
    }
}
