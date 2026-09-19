package br.com.devops.observability.model;

/** Resumo do que o gerador de trafego realmente executou. */
public record TrafficResult(
        int requested,
        int executed,
        int success2xx,
        int clientError4xx,
        int serverError5xx,
        int failures,
        long durationMs) {
}
