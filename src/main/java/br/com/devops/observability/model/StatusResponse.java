package br.com.devops.observability.model;

/** Payload de {@code GET /api/status}, usado pelos cards de estado da interface. */
public record StatusResponse(
        String status,
        String application,
        String version,
        String environment,
        String hostname,
        String startedAt,
        long uptimeSeconds,
        String uptimeHuman,
        long totalRequests,
        long totalLogEvents,
        ActionRecord lastAction,
        boolean logShippingActive,
        long heapUsedBytes,
        long heapMaxBytes,
        int liveThreads) {
}
