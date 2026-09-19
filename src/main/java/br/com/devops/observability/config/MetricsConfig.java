package br.com.devops.observability.config;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.boot.actuate.autoconfigure.metrics.MeterRegistryCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Tags comuns aplicadas a todas as metricas exportadas.
 *
 * <p>As tags sao registradas programaticamente (e nao apenas via propriedades) para garantir
 * que application/environment/version apareçam em 100% das series expostas em
 * {@code /actuator/prometheus}, inclusive nas metricas da JVM.</p>
 */
@Configuration
public class MetricsConfig {

    @Bean
    MeterRegistryCustomizer<MeterRegistry> commonTags(AppProperties properties) {
        return registry -> registry.config().commonTags(
                "application", "spring-devops-observability",
                "environment", properties.getEnvironment(),
                "version", properties.getVersion());
    }
}
