package br.com.devops.observability.model;

/** Payload dos endpoints de demonstracao de status HTTP. */
public record DemoResponse(
        int status,
        String outcome,
        String message,
        String correlationId,
        String timestamp) {
}
