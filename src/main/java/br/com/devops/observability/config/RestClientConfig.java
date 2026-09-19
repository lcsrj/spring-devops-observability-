package br.com.devops.observability.config;

import java.time.Duration;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * RestClient dedicado as chamadas internas do gerador de trafego, com timeouts curtos
 * para que uma rajada de requisicoes nunca prenda a thread do endpoint.
 */
@Configuration
public class RestClientConfig {

    @Bean
    RestClient selfCallRestClient() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(2));
        factory.setReadTimeout(Duration.ofSeconds(5));

        return RestClient.builder()
                .requestFactory(factory)
                .build();
    }
}
