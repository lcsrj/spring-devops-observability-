package br.com.devops.observability;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;

import br.com.devops.observability.config.AppProperties;
import br.com.devops.observability.service.TrafficGeneratorService;

/** Garante que o contexto do Spring inicializa com todos os beans do projeto. */
@SpringBootTest
class ObservabilityApplicationTests {

    @Autowired
    private ApplicationContext context;

    @Autowired
    private AppProperties appProperties;

    @Test
    @DisplayName("o contexto do Spring inicializa e registra os beans principais")
    void contextLoads() {
        assertThat(context).isNotNull();
        assertThat(context.getBean(TrafficGeneratorService.class)).isNotNull();
        assertThat(context.containsBean("commonTags")).isTrue();
    }

    @Test
    @DisplayName("as propriedades da aplicacao sao carregadas do application.yml")
    void appPropertiesAreBound() {
        assertThat(appProperties.getName()).isEqualTo("DevOps Observability Control Center");
        // A versao e filtrada pelo Maven; o placeholder @project.version@ nao deve sobrar.
        assertThat(appProperties.getVersion()).isNotBlank().doesNotContain("project.version");
        assertThat(appProperties.getTraffic().getMaxRequests()).isEqualTo(200);
    }
}
