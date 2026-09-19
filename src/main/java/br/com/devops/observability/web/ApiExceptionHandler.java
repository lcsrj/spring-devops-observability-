package br.com.devops.observability.web;

import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

import br.com.devops.observability.model.ErrorResponse;
import jakarta.servlet.http.HttpServletRequest;

/**
 * Traduz as excecoes da aplicacao em respostas HTTP reais.
 *
 * <p>Como o status e produzido pelo proprio fluxo do Spring MVC, ele e contabilizado nas
 * metricas {@code http_server_requests_seconds_count{status="400"|"500"}} e registrado no
 * Graylog com nivel WARN/ERROR.</p>
 *
 * <p>A classe estende {@link ResponseEntityExceptionHandler} de proposito: assim as
 * excecoes proprias do Spring MVC (recurso inexistente, metodo nao suportado, media type
 * invalido) continuam devolvendo o status correto - um handler generico de
 * {@code Exception} transformaria 404 em 500.</p>
 */
@RestControllerAdvice
public class ApiExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger LOG = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(DemoBadRequestException.class)
    public ResponseEntity<ErrorResponse> handleBadRequest(DemoBadRequestException ex,
                                                          HttpServletRequest request) {
        LOG.warn("Requisicao invalida em {}: {}", request.getRequestURI(), ex.getMessage());
        return build(HttpStatus.BAD_REQUEST, "Bad Request", ex.getMessage(), request);
    }

    @ExceptionHandler(DemoServerException.class)
    public ResponseEntity<ErrorResponse> handleServerError(DemoServerException ex,
                                                           HttpServletRequest request) {
        LOG.error("Falha interna em {}: {}", request.getRequestURI(), ex.getMessage(), ex);
        return build(HttpStatus.INTERNAL_SERVER_ERROR, "Internal Server Error", ex.getMessage(), request);
    }

    /**
     * Rede de seguranca para falhas nao previstas da propria aplicacao. Excecoes do
     * framework nao caem aqui: elas tem handlers exatos herdados da superclasse.
     */
    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<ErrorResponse> handleUnexpected(RuntimeException ex,
                                                          HttpServletRequest request) {
        LOG.error("Erro nao tratado em {}: {}", request.getRequestURI(), ex.getMessage(), ex);
        return build(HttpStatus.INTERNAL_SERVER_ERROR, "Internal Server Error",
                "Erro inesperado ao processar a requisicao", request);
    }

    /** Registra em log tambem as excecoes tratadas pela superclasse (404, 405, 415, ...). */
    @Override
    protected ResponseEntity<Object> handleExceptionInternal(Exception ex, Object body,
                                                             HttpHeaders headers,
                                                             HttpStatusCode statusCode,
                                                             WebRequest request) {
        if (statusCode.is5xxServerError()) {
            LOG.error("Falha do framework ({}) em {}: {}", statusCode, request.getDescription(false),
                    ex.getMessage(), ex);
        } else {
            LOG.warn("Requisicao rejeitada ({}) em {}: {}", statusCode, request.getDescription(false),
                    ex.getMessage());
        }
        return super.handleExceptionInternal(ex, body, headers, statusCode, request);
    }

    private ResponseEntity<ErrorResponse> build(HttpStatus status, String error, String message,
                                                HttpServletRequest request) {
        ErrorResponse body = new ErrorResponse(
                status.value(),
                error,
                message,
                request.getRequestURI(),
                CorrelationIdFilter.currentCorrelationId(request),
                OffsetDateTime.now().truncatedTo(ChronoUnit.MILLIS).toString());
        return ResponseEntity.status(status).body(body);
    }
}
