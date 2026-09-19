package br.com.devops.observability.web;

/** Sinaliza um erro de cliente proposital, mapeado para HTTP 400. */
public class DemoBadRequestException extends RuntimeException {

    public DemoBadRequestException(String message) {
        super(message);
    }
}
