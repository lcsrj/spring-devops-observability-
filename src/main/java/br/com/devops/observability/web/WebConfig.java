package br.com.devops.observability.web;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Registra o interceptor de auditoria apenas nas rotas de acao ({@code /api/demo/**}).
 *
 * <p>Consultas de estado ({@code /api/status}, {@code /api/history}) ficam de fora de
 * proposito: o polling da interface nao deve poluir o historico nem inflar o contador de
 * acoes executadas.</p>
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final ActionAuditInterceptor auditInterceptor;

    public WebConfig(ActionAuditInterceptor auditInterceptor) {
        this.auditInterceptor = auditInterceptor;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(auditInterceptor)
                .addPathPatterns("/api/demo/**");
    }
}
