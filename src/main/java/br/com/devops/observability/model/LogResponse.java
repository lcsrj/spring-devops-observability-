package br.com.devops.observability.model;

/** Payload devolvido pelos endpoints de geracao de log. */
public record LogResponse(
        String level,
        String logger,
        String message,
        String correlationId,
        String timestamp,
        boolean sentToGraylog) {
}
