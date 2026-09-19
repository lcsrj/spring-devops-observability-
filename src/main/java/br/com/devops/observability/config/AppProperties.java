package br.com.devops.observability.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Metadados da aplicacao usados na interface, nas tags de metricas e nos campos GELF.
 */
@ConfigurationProperties(prefix = "app")
public class AppProperties {

    /** Nome de exibicao da aplicacao. */
    private String name = "DevOps Observability Control Center";

    /** Versao do artefato (preenchida pelo Maven em build time). */
    private String version = "dev";

    /** Ambiente logico de execucao: local, docker, ci, etc. */
    private String environment = "local";

    /** URLs externas exibidas na secao "Links rapidos" da interface. */
    private Links links = new Links();

    /** Limites do gerador de trafego. */
    private Traffic traffic = new Traffic();

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getVersion() {
        return version;
    }

    public void setVersion(String version) {
        this.version = version;
    }

    public String getEnvironment() {
        return environment;
    }

    public void setEnvironment(String environment) {
        this.environment = environment;
    }

    public Links getLinks() {
        return links;
    }

    public void setLinks(Links links) {
        this.links = links;
    }

    public Traffic getTraffic() {
        return traffic;
    }

    public void setTraffic(Traffic traffic) {
        this.traffic = traffic;
    }

    public static class Links {
        private String prometheus = "http://localhost:9090";
        private String grafana = "http://localhost:3000";
        private String graylog = "http://localhost:9000";

        public String getPrometheus() {
            return prometheus;
        }

        public void setPrometheus(String prometheus) {
            this.prometheus = prometheus;
        }

        public String getGrafana() {
            return grafana;
        }

        public void setGrafana(String grafana) {
            this.grafana = grafana;
        }

        public String getGraylog() {
            return graylog;
        }

        public void setGraylog(String graylog) {
            this.graylog = graylog;
        }
    }

    public static class Traffic {
        /** Quantidade usada quando o cliente nao informa nada. */
        private int defaultRequests = 25;

        /** Teto de seguranca para uma unica chamada ao gerador de trafego. */
        private int maxRequests = 200;

        public int getDefaultRequests() {
            return defaultRequests;
        }

        public void setDefaultRequests(int defaultRequests) {
            this.defaultRequests = defaultRequests;
        }

        public int getMaxRequests() {
            return maxRequests;
        }

        public void setMaxRequests(int maxRequests) {
            this.maxRequests = maxRequests;
        }
    }
}
