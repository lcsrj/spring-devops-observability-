package br.com.devops.observability;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

import br.com.devops.observability.config.AppProperties;

/**
 * Ponto de entrada do "DevOps Observability Control Center".
 */
@SpringBootApplication
@EnableConfigurationProperties(AppProperties.class)
public class ObservabilityApplication {

    public static void main(String[] args) {
        SpringApplication.run(ObservabilityApplication.class, args);
    }
}
