package br.com.devops.observability.web;

/** Sinaliza uma falha de servidor proposital, mapeada para HTTP 500. */
public class DemoServerException extends RuntimeException {

    public DemoServerException(String message) {
        super(message);
    }
}
