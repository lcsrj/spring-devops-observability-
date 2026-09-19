package br.com.devops.observability.config;

import org.springframework.boot.web.context.WebServerInitializedEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.stereotype.Component;

/**
 * Descobre em runtime a porta HTTP real do servidor embutido.
 *
 * <p>O gerador de trafego precisa disparar requisicoes HTTP de verdade contra a propria
 * aplicacao. Resolver a porta por evento faz o componente funcionar tanto no container
 * (porta fixa 8080) quanto nos testes de integracao (porta aleatoria).</p>
 */
@Component
public class SelfEndpointResolver implements ApplicationListener<WebServerInitializedEvent> {

    private volatile int port = 8080;

    @Override
    public void onApplicationEvent(WebServerInitializedEvent event) {
        this.port = event.getWebServer().getPort();
    }

    public int getPort() {
        return port;
    }

    public String baseUrl() {
        return "http://127.0.0.1:" + port;
    }
}
