package br.com.devops.observability.model;

/**
 * Registro de uma acao realmente executada contra o backend.
 *
 * @param sequence     numero sequencial da acao
 * @param timestamp    horario ISO-8601 em que a requisicao terminou
 * @param action       rotulo legivel da acao
 * @param method       metodo HTTP
 * @param endpoint     caminho chamado
 * @param status       status HTTP devolvido
 * @param durationMs   duracao medida no servidor, em milissegundos
 * @param correlationId identificador de correlacao propagado para o Graylog
 */
public record ActionRecord(
        long sequence,
        String timestamp,
        String action,
        String method,
        String endpoint,
        int status,
        long durationMs,
        String correlationId) {
}
