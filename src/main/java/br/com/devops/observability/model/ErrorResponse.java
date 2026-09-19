package br.com.devops.observability.model;

/** Payload padronizado de erro (4xx/5xx). */
public record ErrorResponse(
        int status,
        String error,
        String message,
        String path,
        String correlationId,
        String timestamp) {
}
