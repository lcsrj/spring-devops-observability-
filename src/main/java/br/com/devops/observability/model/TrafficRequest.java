package br.com.devops.observability.model;

/**
 * Corpo aceito por {@code POST /api/demo/traffic}.
 *
 * @param requests quantidade de requisicoes a disparar; {@code null} usa o default configurado
 */
public record TrafficRequest(Integer requests) {
}
