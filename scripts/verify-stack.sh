#!/usr/bin/env bash
# =============================================================================
#  verify-stack.sh - auditoria automatizada requisito por requisito
#
#  Valida o maximo possivel sem intervencao humana:
#    1. arquivos obrigatorios do repositorio;
#    2. Dockerfile multistage de verdade (build separado de runtime enxuto);
#    3. containers running/healthy;
#    4. endpoints da aplicacao;
#    5. target da aplicacao UP no Prometheus + metricas essenciais com valor;
#    6. data source e dashboard provisionados no Grafana;
#    7. Input GELF criado e logs dos 4 niveis pesquisaveis no Graylog;
#    8. suite de testes (mvn test).
#
#  Uso:   ./scripts/verify-stack.sh [--skip-tests] [--skip-image]
#  Exit:  0 = todas as verificacoes passaram | 1 = alguma falhou
# =============================================================================
set -uo pipefail

SKIP_TESTS=0
SKIP_IMAGE=0
for arg in "$@"; do
    case "${arg}" in
        --skip-tests) SKIP_TESTS=1 ;;
        --skip-image) SKIP_IMAGE=1 ;;
        *) echo "argumento desconhecido: ${arg}" >&2; exit 2 ;;
    esac
done

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

cd "${PROJECT_ROOT}"

APP_IMAGE="${APP_IMAGE:-spring-devops-observability:1.0.0}"

echo "${C_BOLD}AUDITORIA DA STACK - DevOps Observability Control Center${C_RESET}"
echo "  projeto: ${PROJECT_ROOT}"

# =============================================================================
section "1. Arquivos obrigatorios do repositorio"
# =============================================================================
file_exists() {
    [ -f "$1" ] && { echo "presente"; return 0; }
    echo "arquivo ausente: $1"; return 1
}

dir_exists() {
    [ -d "$1" ] && { echo "presente"; return 0; }
    echo "diretorio ausente: $1"; return 1
}

check "Dockerfile"                              file_exists "Dockerfile"
check "docker-compose.yml"                      file_exists "docker-compose.yml"
check "pom.xml"                                 file_exists "pom.xml"
check ".dockerignore"                           file_exists ".dockerignore"
check ".gitignore"                              file_exists ".gitignore"
check ".env.example"                            file_exists ".env.example"
check "README.md"                               file_exists "README.md"
check "EVIDENCIAS.md"                           file_exists "EVIDENCIAS.md"
check "prometheus/prometheus.yml"               file_exists "prometheus/prometheus.yml"
check "grafana: datasource provisionado"        file_exists "grafana/provisioning/datasources/prometheus.yml"
check "grafana: provider de dashboards"         file_exists "grafana/provisioning/dashboards/dashboards.yml"
check "grafana: JSON do dashboard"              file_exists "grafana/dashboards/spring-boot-observability.json"
check "graylog: script de init do Input GELF"   file_exists "graylog/init/create-gelf-input.sh"
check "workflow de CI/CD"                       file_exists ".github/workflows/ci-cd.yml"
check "application.yml"                         file_exists "src/main/resources/application.yml"
check "logback-spring.xml"                      file_exists "src/main/resources/logback-spring.xml"
check "template da interface"                   file_exists "src/main/resources/templates/index.html"
check "CSS proprio"                             file_exists "src/main/resources/static/css/app.css"
check "JS proprio"                              file_exists "src/main/resources/static/js/app.js"
check "diretorio de testes"                     dir_exists  "src/test/java"
check "diretorio de evidencias"                 dir_exists  "docs/evidencias"

# =============================================================================
section "2. Dockerfile MULTISTAGE (requisito eliminatorio)"
# =============================================================================
multistage_stage_count() {
    local n
    n="$(grep -cE '^[[:space:]]*FROM[[:space:]]' Dockerfile)"
    [ "${n}" -ge 2 ] && { echo "${n} estagios FROM declarados"; return 0; }
    echo "apenas ${n} estagio FROM - multistage ausente"; return 1
}

build_stage_has_maven() {
    grep -qE '^[[:space:]]*FROM[[:space:]]+maven:.*AS[[:space:]]+build' Dockerfile \
        && { echo "estagio de build usa imagem JDK+Maven"; return 0; }
    echo "nao encontrei um estagio de build baseado em imagem Maven"; return 1
}

build_stage_runs_tests() {
    grep -qE '^[[:space:]]*RUN[[:space:]]+mvn.*package' Dockerfile \
        && { echo "mvn package (executa os testes) presente no estagio de build"; return 0; }
    echo "o estagio de build nao executa mvn package"; return 1
}

runtime_stage_is_jre() {
    grep -qE '^[[:space:]]*FROM[[:space:]]+eclipse-temurin:.*-jre-.*AS[[:space:]]+runtime' Dockerfile \
        && { echo "estagio de runtime usa imagem apenas-JRE"; return 0; }
    echo "o estagio de runtime nao usa uma imagem apenas-JRE"; return 1
}

runtime_copies_only_jar() {
    grep -qE '^[[:space:]]*COPY[[:space:]]+--from=build[[:space:]].*\.jar' Dockerfile \
        && { echo "runtime recebe apenas o .jar do estagio de build"; return 0; }
    echo "nao encontrei COPY --from=build do .jar"; return 1
}

runtime_runs_as_non_root() {
    grep -qE '^[[:space:]]*USER[[:space:]]+' Dockerfile \
        && { echo "processo roda com usuario sem privilegios"; return 0; }
    echo "o Dockerfile nao define USER (rodaria como root)"; return 1
}

check "o Dockerfile declara 2 ou mais estagios"  multistage_stage_count
check "estagio 1 usa JDK + Maven"                build_stage_has_maven
check "estagio 1 compila e roda os testes"       build_stage_runs_tests
check "estagio 2 usa imagem apenas com JRE"      runtime_stage_is_jre
check "estagio 2 copia somente o .jar"           runtime_copies_only_jar
check "estagio 2 nao roda como root"             runtime_runs_as_non_root

if [ "${SKIP_IMAGE}" -eq 0 ]; then
    section "2b. Inspecao da IMAGEM construida (${APP_IMAGE})"

    image_exists() {
        docker image inspect "${APP_IMAGE}" >/dev/null 2>&1 \
            && { echo "imagem encontrada localmente"; return 0; }
        echo "imagem ${APP_IMAGE} nao encontrada - rode 'docker compose build'"; return 1
    }

    image_lacks_build_tools() {
        local found
        found="$(docker run --rm --entrypoint sh "${APP_IMAGE}" -c \
            'for t in mvn javac jar; do command -v $t >/dev/null 2>&1 && echo -n "$t "; done' 2>/dev/null)"
        if [ -z "${found}" ]; then
            echo "sem mvn/javac/jar na imagem final"
            return 0
        fi
        echo "ferramentas de build presentes no runtime: ${found}"
        return 1
    }

    image_lacks_sources() {
        local n
        n="$(docker run --rm --entrypoint sh "${APP_IMAGE}" -c \
            'find / -name "*.java" -o -name "pom.xml" 2>/dev/null | grep -v "^/proc" | wc -l' 2>/dev/null | tr -d ' \r')"
        if [ "${n}" = "0" ]; then
            echo "nenhum .java nem pom.xml na imagem final"
            return 0
        fi
        echo "a imagem final ainda contem ${n} arquivo(s) de codigo-fonte"
        return 1
    }

    image_has_jar() {
        docker run --rm --entrypoint sh "${APP_IMAGE}" -c 'test -f /app/app.jar' >/dev/null 2>&1 \
            && { echo "/app/app.jar presente"; return 0; }
        echo "/app/app.jar ausente na imagem"; return 1
    }

    check "a imagem da aplicacao existe"             image_exists
    if docker image inspect "${APP_IMAGE}" >/dev/null 2>&1; then
        check "a imagem final contem o .jar"             image_has_jar
        check "a imagem final NAO tem mvn/javac/jar"      image_lacks_build_tools
        check "a imagem final NAO tem codigo-fonte"       image_lacks_sources
    fi
fi

# =============================================================================
section "3. Containers da stack"
# =============================================================================
service_healthy() {
    local state
    state="$(container_health "$1")"
    [ "${state}" = "healthy" ] && { echo "healthy"; return 0; }
    echo "estado atual: ${state:-container nao encontrado}"; return 1
}

init_completed_ok() {
    local code
    code="$(container_exit_code graylog-init)"
    [ "${code}" = "0" ] && { echo "concluido com exit 0 (idempotente)"; return 0; }
    echo "exit code do graylog-init: ${code:-ainda em execucao}"; return 1
}

check "container app healthy"                    service_healthy app
check "container prometheus healthy"             service_healthy prometheus
check "container grafana healthy"                service_healthy grafana
check "container mongodb healthy"                service_healthy mongodb
check "container opensearch healthy"             service_healthy opensearch
check "container graylog healthy"                service_healthy graylog
check "graylog-init concluiu com sucesso"        init_completed_ok

# =============================================================================
section "4. Endpoints da aplicacao"
# =============================================================================
check "GET / (interface web)"                    expect_http "${APP_URL}/" 200
check "GET /api/status"                          expect_http "${APP_URL}/api/status" 200
check "GET /api/history"                         expect_http "${APP_URL}/api/history" 200
check "GET /api/demo/ok -> 200"                  expect_http "${APP_URL}/api/demo/ok" 200
check "GET /api/demo/bad-request -> 400"         expect_http "${APP_URL}/api/demo/bad-request" 400
check "GET /api/demo/error -> 500"               expect_http "${APP_URL}/api/demo/error" 500
check "/actuator/health -> UP"                   body_contains "${APP_URL}/actuator/health" '"status":"UP"'
check "/actuator/info"                           expect_http "${APP_URL}/actuator/info" 200
check "/actuator/prometheus"                     expect_http "${APP_URL}/actuator/prometheus" 200

post_ok() {
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
        -H 'Content-Type: application/json' ${2:+-d "$2"} "${APP_URL}$1")"
    [ "${code}" = "200" ] && { echo "HTTP 200"; return 0; }
    echo "HTTP ${code} em POST $1"; return 1
}

check "POST /api/demo/log/debug"                 post_ok "/api/demo/log/debug"
check "POST /api/demo/log/info"                  post_ok "/api/demo/log/info"
check "POST /api/demo/log/warn"                  post_ok "/api/demo/log/warn"
check "POST /api/demo/log/error"                 post_ok "/api/demo/log/error"
check "POST /api/demo/traffic (rajada real)"     post_ok "/api/demo/traffic" '{"requests":20}'

# =============================================================================
section "5. Prometheus: target UP e metricas essenciais"
# =============================================================================
target_up() {
    local health
    health="$(curl -s --max-time 15 "${PROMETHEUS_URL}/api/v1/targets?state=active" \
        | tr '{' '\n' | grep -A20 'spring-boot-app' | sed -n 's/.*"health":"\([^"]*\)".*/\1/p' | head -1)"
    if [ -z "${health}" ]; then
        health="$(prom_query 'up{job="spring-boot-app"}')"
        [ "${health}" = "1" ] && { echo "up=1"; return 0; }
        echo "target da aplicacao nao encontrado no Prometheus"; return 1
    fi
    [ "${health}" = "up" ] && { echo "health=UP"; return 0; }
    echo "health=${health}"; return 1
}

# metric_has_value vem de lib.sh: ja faz retry pelo intervalo de scrape.

check "target spring-boot-app esta UP"           target_up
check "memoria Heap da JVM (usada)"              metric_has_value 'sum(jvm_memory_used_bytes{job="spring-boot-app",area="heap"})'
check "memoria Heap da JVM (maxima)"             metric_has_value 'sum(jvm_memory_max_bytes{job="spring-boot-app",area="heap"})'
check "memoria Heap da JVM (comprometida)"       metric_has_value 'sum(jvm_memory_committed_bytes{job="spring-boot-app",area="heap"})'
check "uso de CPU do processo"                   metric_has_value 'process_cpu_usage{job="spring-boot-app"}'
check "threads vivas da JVM"                     metric_has_value 'jvm_threads_live_threads{job="spring-boot-app"}'
check "uptime do processo"                       metric_has_value 'process_uptime_seconds{job="spring-boot-app"}'
check "total de requisicoes HTTP"                metric_has_value 'sum(http_server_requests_seconds_count{job="spring-boot-app"})'
check "RPS (taxa de requisicoes)"                metric_has_value 'sum(rate(http_server_requests_seconds_count{job="spring-boot-app"}[5m]))'
check "requisicoes 2xx"                          metric_has_value 'sum(http_server_requests_seconds_count{job="spring-boot-app",status=~"2.."})'
check "requisicoes 4xx"                          metric_has_value 'sum(http_server_requests_seconds_count{job="spring-boot-app",status=~"4.."})'
check "requisicoes 5xx"                          metric_has_value 'sum(http_server_requests_seconds_count{job="spring-boot-app",status=~"5.."})'
check "tempo de resposta (buckets p/ percentis)" metric_has_value 'histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{job="spring-boot-app"}[5m])))'
check "tag comum application presente"           metric_has_value 'count(up{job="spring-boot-app"}) + count(process_uptime_seconds{application="spring-devops-observability"})'
check "contador proprio de eventos de log"       metric_has_value 'sum(app_demo_log_events_total{job="spring-boot-app"})'

# =============================================================================
section "6. Grafana: data source e dashboard provisionados"
# =============================================================================
GF_AUTH="${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}"

grafana_datasource() {
    local body
    body="$(curl -s --max-time 15 -u "${GF_AUTH}" "${GRAFANA_URL}/api/datasources/uid/prometheus")"
    echo "${body}" | grep -q '"type":"prometheus"' \
        && { echo "data source Prometheus provisionado"; return 0; }
    echo "data source nao encontrado: ${body}"; return 1
}

grafana_datasource_reaches_prometheus() {
    local body
    body="$(curl -s --max-time 20 -u "${GF_AUTH}" \
        "${GRAFANA_URL}/api/datasources/uid/prometheus/health")"
    echo "${body}" | grep -qi '"status":"OK"' \
        && { echo "Grafana consegue consultar o Prometheus"; return 0; }
    echo "health do data source: ${body}"; return 1
}

grafana_dashboard() {
    local body
    body="$(curl -s --max-time 15 -u "${GF_AUTH}" "${GRAFANA_URL}/api/dashboards/uid/spring-observability")"
    echo "${body}" | grep -q 'Application Observability' \
        && { echo "dashboard carregado automaticamente"; return 0; }
    echo "dashboard nao encontrado: ${body}"; return 1
}

grafana_dashboard_panel_count() {
    local n
    n="$(curl -s --max-time 15 -u "${GF_AUTH}" "${GRAFANA_URL}/api/dashboards/uid/spring-observability" \
        | grep -o '"gridPos"' | wc -l | tr -d ' \r')"
    [ "${n}" -ge 10 ] && { echo "${n} paineis no dashboard"; return 0; }
    echo "apenas ${n} paineis encontrados"; return 1
}

grafana_query_returns_data() {
    local body
    body="$(curl -s --max-time 25 -u "${GF_AUTH}" \
        -H 'Content-Type: application/json' \
        -X POST "${GRAFANA_URL}/api/ds/query" \
        -d '{"queries":[{"refId":"A","datasource":{"type":"prometheus","uid":"prometheus"},
             "expr":"sum(jvm_memory_used_bytes{job=\"spring-boot-app\",area=\"heap\"})",
             "instant":true,"format":"time_series"}],"from":"now-5m","to":"now"}')"
    echo "${body}" | grep -q '"frames"' && ! echo "${body}" | grep -q '"error"' \
        && { echo "consulta do dashboard devolve dados reais"; return 0; }
    echo "consulta sem dados: $(echo "${body}" | head -c 240)"; return 1
}

check "data source Prometheus provisionado"      grafana_datasource
check "o data source alcanca o Prometheus"       grafana_datasource_reaches_prometheus
check "dashboard provisionado automaticamente"   grafana_dashboard
check "o dashboard tem paineis suficientes"      grafana_dashboard_panel_count
check "os paineis retornam metricas reais"       grafana_query_returns_data

# =============================================================================
section "7. Graylog: Input GELF e logs pesquisaveis"
# =============================================================================
graylog_input_exists() {
    local body
    body="$(graylog_api /api/system/inputs)"
    echo "${body}" | grep -q 'GELFUDPInput' \
        && { echo "Input GELF UDP cadastrado"; return 0; }
    echo "nenhum Input GELF encontrado"; return 1
}

graylog_input_running() {
    local body
    body="$(graylog_api /api/system/inputstates)"
    echo "${body}" | grep -q '"state":"RUNNING"' \
        && { echo "Input em estado RUNNING"; return 0; }
    echo "Input nao esta RUNNING"; return 1
}

# graylog_has_messages <query_lucene> [tentativas]
# Faz retry: os logs viajam por UDP e passam pelo journal do Graylog antes de
# serem indexados no OpenSearch, o que leva alguns segundos.
graylog_has_messages() {
    local query="$1" attempts="${2:-8}" total="" i=0
    while [ "${i}" -lt "${attempts}" ]; do
        total="$(graylog_search_total "${query}")"
        if [ -n "${total}" ] && [ "${total}" -gt 0 ] 2>/dev/null; then
            echo "${total} mensagem(ns) indexada(s)"
            return 0
        fi
        i=$((i + 1))
        [ "${i}" -lt "${attempts}" ] && sleep 3
    done
    echo "nenhuma mensagem apos $((attempts * 3))s para a busca: ${query}"
    return 1
}

# Os logs viajam por UDP e passam pelo journal do Graylog: pequena espera ativa
# para a indexacao terminar antes de consultar.
printf '  aguardando indexacao dos logs no Graylog '
waited=0
while [ "${waited}" -lt 60 ]; do
    total="$(graylog_search_total 'application:spring-devops-observability')"
    if [ -n "${total}" ] && [ "${total}" -gt 0 ] 2>/dev/null; then
        echo "${C_GREEN}OK${C_RESET} - ${total} mensagens"
        break
    fi
    printf '.'
    waited=$((waited + 3))
    sleep 3
done
[ "${waited}" -ge 60 ] && echo " ${C_YELLOW}sem mensagens ainda${C_RESET}"

check "Input GELF UDP existe"                    graylog_input_exists
check "Input GELF UDP esta RUNNING"              graylog_input_running
check "logs da aplicacao indexados"              graylog_has_messages 'application:spring-devops-observability'
check "campo environment presente nos logs"      graylog_has_messages 'application:spring-devops-observability AND environment:docker'
check "campo version presente nos logs"          graylog_has_messages 'application:spring-devops-observability AND version:1.0.0'
check "correlation_id presente nos logs"         graylog_has_messages 'application:spring-devops-observability AND _exists_:correlation_id'
check "logs de nivel DEBUG pesquisaveis"         graylog_has_messages 'application:spring-devops-observability AND level_name:DEBUG'
check "logs de nivel INFO pesquisaveis"          graylog_has_messages 'application:spring-devops-observability AND level_name:INFO'
check "logs de nivel WARN pesquisaveis"          graylog_has_messages 'application:spring-devops-observability AND level_name:WARN'
check "logs de nivel ERROR pesquisaveis"         graylog_has_messages 'application:spring-devops-observability AND level_name:ERROR'

# =============================================================================
section "8. Suite de testes automatizados"
# =============================================================================
if [ "${SKIP_TESTS}" -eq 1 ]; then
    warn "testes ignorados (--skip-tests)"
else
    run_maven_tests() {
        local out
        # Maven roda na MESMA imagem do estagio de build, dispensando instalacao local.
        local mount
        mount="$(host_path_for_docker "${PROJECT_ROOT}")"
        out="$(docker_run --rm \
            -v "${mount}:/workspace" \
            -v devops-obs-m2:/root/.m2 \
            -w /workspace \
            maven:3.9.9-eclipse-temurin-21 \
            mvn -B -ntp test 2>&1)"
        local line
        line="$(echo "${out}" | grep -E '^\[INFO\] Tests run:.*Failures' | tail -1)"
        if echo "${out}" | grep -q 'BUILD SUCCESS'; then
            echo "${line:-BUILD SUCCESS}"
            return 0
        fi
        echo "$(echo "${out}" | grep -E '^\[ERROR\]' | head -5)"
        return 1
    }

    check "mvn test (suite completa)"            run_maven_tests
fi

summary
exit $?
