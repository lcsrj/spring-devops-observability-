#!/usr/bin/env bash
# =============================================================================
#  capture-evidence.sh - coleta evidencias reais de execucao em docs/evidencias/
#
#  Gera:
#    - capturas de tela (Chromium headless em container, sem instalar nada);
#    - saidas de comandos e respostas de API em texto.
#
#  Nada aqui e fabricado: todo arquivo vem de um comando ou de uma chamada HTTP
#  executada contra a stack em funcionamento.
#
#  Uso:   ./scripts/capture-evidence.sh
#  Exit:  0 = evidencias coletadas | 1 = a stack nao esta pronta
# =============================================================================
set -uo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

cd "${PROJECT_ROOT}"

OUT_DIR="${PROJECT_ROOT}/docs/evidencias"
CHROME_IMAGE="zenika/alpine-chrome:124"
mkdir -p "${OUT_DIR}"

echo "${C_BOLD}CAPTURA DE EVIDENCIAS${C_RESET}"
echo "  destino: docs/evidencias/"

if ! curl -sf --max-time 5 "${APP_URL}/actuator/health" >/dev/null; then
    err "a aplicacao nao esta respondendo em ${APP_URL} - suba a stack primeiro"
    exit 1
fi

# -----------------------------------------------------------------------------
# shot <arquivo> <url> [largura] [altura] [orcamento_ms] [limite_s]
#
# Captura a pagina com Chromium headless em container, usando a rede do host.
#
# Dois cuidados aprendidos na pratica:
#  - limite de tempo DENTRO do container: uma SPA que mantem conexoes abertas
#    pode impedir o Chromium de encerrar sozinho. Um `timeout` no host nao
#    resolve, porque em Git Bash/MSYS o sinal nao chega ao docker.exe.
#  - orcamento de tempo virtual configuravel: valores altos deixam paineis
#    pesados terminarem de renderizar, mas em paginas com timers recorrentes o
#    tempo virtual nunca expira. Para essas, use um valor baixo.
# -----------------------------------------------------------------------------
shot() {
    local file="$1" url="$2" width="${3:-1600}" height="${4:-1400}"
    local budget="${5:-12000}" limit="${6:-60}"
    local name="obs-shot-$$-${RANDOM}"
    printf '  %-42s ' "${file}"

    rm -f "${OUT_DIR}/${file}"

    # O limite de tempo e aplicado DENTRO do container, com o `timeout` do
    # busybox. Um `timeout` no host nao resolve: em Git Bash/MSYS o sinal nao
    # chega ao docker.exe (processo nativo do Windows) e o comando fica preso.
    local script="timeout ${limit} chromium-browser \
--headless --no-sandbox --disable-gpu --hide-scrollbars \
--window-size=${width},${height} \
--virtual-time-budget=${budget} \
--screenshot=/out/${file} '${url}' >/dev/null 2>&1; [ -s /out/${file} ]"

    if MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
        docker run --rm --name "${name}" --network host \
        -v "$(host_path_for_docker "${OUT_DIR}"):/out" \
        --entrypoint sh "${CHROME_IMAGE}" -c "${script}" >/dev/null 2>&1 \
        && [ -s "${OUT_DIR}/${file}" ]; then
        pass_inline "$(du -h "${OUT_DIR}/${file}" | cut -f1)"
    else
        # Garante que um Chromium travado nao fique para tras.
        docker rm -f "${name}" >/dev/null 2>&1 || true
        fail_inline "nao foi possivel capturar ${url}"
    fi
}

save() {
    local file="$1"; shift
    printf '  %-42s ' "${file}"
    if "$@" > "${OUT_DIR}/${file}" 2>&1 && [ -s "${OUT_DIR}/${file}" ]; then
        pass_inline "$(wc -l < "${OUT_DIR}/${file}" | tr -d ' ') linha(s)"
    else
        fail_inline "falha ao gerar"
    fi
}

# =============================================================================
section "1. Trafego e logs, para que as evidencias tenham dados reais"
# =============================================================================
bash "${PROJECT_ROOT}/scripts/generate-traffic.sh" 3 >/dev/null 2>&1 \
    && ok "trafego 2xx/4xx/5xx e logs DEBUG/INFO/WARN/ERROR gerados" \
    || warn "a geracao de trafego reportou problemas"

echo "  aguardando scrape do Prometheus e indexacao no Graylog..."
sleep 12

# =============================================================================
section "2. Capturas de tela"
# =============================================================================
shot "01-interface-aplicacao.png"        "${APP_URL}/"                       1600 1900
shot "02-prometheus-targets.png"         "${PROMETHEUS_URL}/targets"         1600 1000
shot "03-prometheus-grafico-rps.png" \
     "${PROMETHEUS_URL}/graph?g0.expr=sum%20by%20(status)%20(rate(http_server_requests_seconds_count%7Bjob%3D%22spring-boot-app%22%7D%5B1m%5D))&g0.tab=0&g0.range_input=15m" \
     1600 1100
# A captura da interface do Graylog e OPT-IN, desabilitada por padrao.
#
# Motivo: em maquinas Windows com Docker Desktop sobre WSL2, o Chromium headless
# apontado para a SPA do Graylog derruba a VM do WSL. O dump gerado pelo crash
# ocupa ~14 GB em %LOCALAPPDATA%\Temp\wsl-crashes e enche o disco, o que derruba
# o proprio Docker em seguida. Foi reproduzido aqui: o dump se chamava
# `wsl-crash-..._usr_lib_chromium_chromium-5.dmp`.
#
# Nenhuma evidencia e perdida: o funcionamento do Graylog e comprovado pela API,
# que e prova mais forte que um screenshot - `11-graylog-init-logs.txt` (Input
# GELF criado e idempotente), `16-graylog-logs-por-nivel.txt` (DEBUG/INFO/WARN/
# ERROR pesquisaveis) e `17-graylog-mensagem-exemplo.txt` (todos os campos da
# mensagem, com stack trace).
#
# Para tentar a captura mesmo assim:  CAPTURE_GRAYLOG_UI=1 ./scripts/capture-evidence.sh
if [ "${CAPTURE_GRAYLOG_UI:-0}" = "1" ]; then
    shot "04-graylog-interface.png" "${GRAYLOG_URL}/" 1400 900 3000 30
else
    printf '  %-42s ' "04-graylog-interface.png"
    warn_inline "ignorada (CAPTURE_GRAYLOG_UI=0; derruba a VM do WSL)"
fi

# -----------------------------------------------------------------------------
# O dashboard do Grafana exige sessao autenticada, e o Chromium headless nao
# permite injetar credenciais. Para capturar a evidencia, habilitamos acesso
# anonimo SOMENTE DE LEITURA de forma TEMPORARIA, via docker-compose.override.yml
# (que esta no .gitignore), e revertemos ao final. A configuracao entregue no
# repositorio permanece exigindo login.
# -----------------------------------------------------------------------------
section "3. Dashboard do Grafana (acesso anonimo temporario para a captura)"

OVERRIDE="${PROJECT_ROOT}/docker-compose.override.yml"
OVERRIDE_PREEXISTING=0
[ -f "${OVERRIDE}" ] && OVERRIDE_PREEXISTING=1

if [ "${OVERRIDE_PREEXISTING}" -eq 1 ]; then
    warn "docker-compose.override.yml ja existe - a captura do Grafana sera ignorada"
else
    cat > "${OVERRIDE}" <<'OVR'
# Arquivo TEMPORARIO criado por scripts/capture-evidence.sh apenas para permitir
# a captura de tela do dashboard. E removido automaticamente ao final e esta no
# .gitignore. Nao faz parte da configuracao entregue.
services:
  grafana:
    environment:
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer"
      GF_AUTH_DISABLE_LOGIN_FORM: "false"
OVR

    echo "  aplicando override temporario no Grafana..."
    docker compose up -d grafana >/dev/null 2>&1

    waited=0
    while [ "${waited}" -lt 60 ]; do
        if curl -sf --max-time 5 "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
            break
        fi
        waited=$((waited + 3)); sleep 3
    done
    sleep 5

    shot "05-grafana-dashboard.png" \
         "${GRAFANA_URL}/d/spring-observability/spring-boot-application-observability?orgId=1&from=now-30m&to=now&kiosk" \
         1800 2100

    echo "  removendo o override temporario e restaurando o Grafana..."
    rm -f "${OVERRIDE}"
    docker compose up -d grafana >/dev/null 2>&1
    ok "Grafana restaurado: login novamente obrigatorio"
fi

# =============================================================================
section "4. Saidas de comandos e respostas de API"
# =============================================================================

save "10-docker-compose-ps.txt" \
    docker compose ps -a --format "table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

save "11-graylog-init-logs.txt" \
    docker compose logs graylog-init --no-log-prefix

save "12-prometheus-targets.json" \
    curl -s "${PROMETHEUS_URL}/api/v1/targets?state=active"

metrics_excerpt() {
    echo "# Trecho de ${APP_URL}/actuator/prometheus"
    echo "# Coletado em $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    curl -s "${APP_URL}/actuator/prometheus" \
        | grep -E '^(jvm_memory_used_bytes|jvm_memory_max_bytes|jvm_memory_committed_bytes|process_cpu_usage|system_cpu_usage|jvm_threads_live_threads|process_uptime_seconds|app_demo_log_events_total|http_server_requests_seconds_count)' \
        | sort
}
save "13-actuator-prometheus.txt" metrics_excerpt

prom_metrics_report() {
    echo "# Consultas PromQL executadas contra ${PROMETHEUS_URL}"
    echo "# Coletado em $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    while IFS='|' read -r label query; do
        [ -z "${label}" ] && continue
        printf '%-34s %s\n' "${label}" "$(prom_query "${query}")"
        printf '%-34s %s\n\n' "  promql:" "${query}"
    done <<'QUERIES'
target UP|up{job="spring-boot-app"}
heap usada (bytes)|sum(jvm_memory_used_bytes{job="spring-boot-app",area="heap"})
heap maxima (bytes)|sum(jvm_memory_max_bytes{job="spring-boot-app",area="heap"})
heap comprometida (bytes)|sum(jvm_memory_committed_bytes{job="spring-boot-app",area="heap"})
CPU do processo|process_cpu_usage{job="spring-boot-app"}
threads vivas|jvm_threads_live_threads{job="spring-boot-app"}
uptime (s)|process_uptime_seconds{job="spring-boot-app"}
total de requisicoes|sum(http_server_requests_seconds_count{job="spring-boot-app"})
RPS (1m)|sum(rate(http_server_requests_seconds_count{job="spring-boot-app"}[1m]))
requisicoes 2xx|sum(http_server_requests_seconds_count{job="spring-boot-app",status=~"2.."})
requisicoes 4xx|sum(http_server_requests_seconds_count{job="spring-boot-app",status=~"4.."})
requisicoes 5xx|sum(http_server_requests_seconds_count{job="spring-boot-app",status=~"5.."})
latencia media (s)|sum(rate(http_server_requests_seconds_sum{job="spring-boot-app"}[5m])) / clamp_min(sum(rate(http_server_requests_seconds_count{job="spring-boot-app"}[5m])), 0.0001)
latencia p95 (s)|histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{job="spring-boot-app"}[5m])))
eventos de log gerados|sum(app_demo_log_events_total{job="spring-boot-app"})
QUERIES
}
save "14-prometheus-metricas-consultadas.txt" prom_metrics_report

grafana_report() {
    local auth="${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}"
    echo "# Provisionamento do Grafana verificado via API em ${GRAFANA_URL}"
    echo "# Coletado em $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    echo "## Data source provisionado (GET /api/datasources/uid/prometheus)"
    curl -s -u "${auth}" "${GRAFANA_URL}/api/datasources/uid/prometheus"
    echo ""; echo ""
    echo "## Saude do data source (GET /api/datasources/uid/prometheus/health)"
    curl -s -u "${auth}" "${GRAFANA_URL}/api/datasources/uid/prometheus/health"
    echo ""; echo ""
    echo "## Dashboard provisionado: titulo e paineis"
    curl -s -u "${auth}" "${GRAFANA_URL}/api/dashboards/uid/spring-observability" \
        | tr ',' '\n' | grep -E '"title"|"type":"(stat|timeseries|piechart|row)"'
    echo ""
    echo "## Consulta de painel devolvendo dados reais (POST /api/ds/query)"
    curl -s -u "${auth}" -H 'Content-Type: application/json' \
        -X POST "${GRAFANA_URL}/api/ds/query" \
        -d '{"queries":[{"refId":"A","datasource":{"type":"prometheus","uid":"prometheus"},
             "expr":"sum(jvm_memory_used_bytes{job=\"spring-boot-app\",area=\"heap\"})",
             "instant":true,"format":"time_series"}],"from":"now-5m","to":"now"}'
    echo ""
}
save "15-grafana-provisionamento.txt" grafana_report

graylog_report() {
    echo "# Graylog verificado via API em ${GRAYLOG_URL}"
    echo "# Coletado em $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    echo "## Input GELF cadastrado (GET /api/system/inputs)"
    graylog_api /api/system/inputs | tr ',' '\n' | grep -E '"title"|"type"|"port"|"bind_address"|"global"'
    echo ""
    echo "## Estado do Input (GET /api/system/inputstates)"
    graylog_api /api/system/inputstates | tr ',' '\n' | grep -E '"state"|"title"|"type"'
    echo ""
    echo "## Contagem de mensagens por busca (ultimos 15 minutos)"
    while IFS='|' read -r label query; do
        [ -z "${label}" ] && continue
        printf '%-30s total_results=%s\n' "${label}" "$(graylog_search_total "${query}")"
        printf '%-30s query: %s\n\n' "" "${query}"
    done <<'QUERIES'
todos os logs da app|application:spring-devops-observability
nivel DEBUG|application:spring-devops-observability AND level_name:DEBUG
nivel INFO|application:spring-devops-observability AND level_name:INFO
nivel WARN|application:spring-devops-observability AND level_name:WARN
nivel ERROR|application:spring-devops-observability AND level_name:ERROR
ambiente docker|application:spring-devops-observability AND environment:docker
versao 1.0.0|application:spring-devops-observability AND version:1.0.0
com correlation_id|application:spring-devops-observability AND _exists_:correlation_id
QUERIES
}
save "16-graylog-logs-por-nivel.txt" graylog_report

graylog_sample() {
    echo "# Exemplo de mensagem ERROR realmente indexada no Graylog"
    echo "# Coletado em $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    graylog_api /api/search/universal/relative \
        --get --data-urlencode 'query=application:spring-devops-observability AND level_name:ERROR' \
              --data-urlencode 'range=900' --data-urlencode 'limit=1' \
        | tr ',' '\n' \
        | grep -E '"level_name"|"level"|"logger_name"|"application"|"environment"|"version"|"correlation_id"|"thread_name"|"source"|"timestamp"|"root_cause_class_name"|"demo_level"|"total_results"' \
        | head -20
}
save "17-graylog-mensagem-exemplo.txt" graylog_sample

multistage_report() {
    local image="spring-devops-observability:1.0.0"
    echo "# Prova da separacao dos estagios do Dockerfile multistage"
    echo "# Coletado em $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    echo "## Tamanho: imagem de build vs. imagem final de runtime"
    docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' \
        | grep -E 'maven:3.9.9-eclipse-temurin-21|spring-devops-observability'
    echo ""
    echo "## Conteudo de /app na imagem final"
    docker run --rm --entrypoint sh "${image}" -c 'ls -lh /app'
    echo ""
    echo "## Ferramentas de build na imagem final (devem estar AUSENTES)"
    docker run --rm --entrypoint sh "${image}" -c \
        'for t in mvn maven javac jar jdb; do if command -v $t >/dev/null 2>&1; then echo "PRESENTE: $t"; else echo "AUSENTE : $t"; fi; done'
    echo ""
    echo "## Codigo-fonte e repositorio Maven na imagem final"
    docker run --rm --entrypoint sh "${image}" -c \
        'echo "arquivos .java : $(find / -name "*.java" -not -path "/proc/*" 2>/dev/null | wc -l)";
         echo "arquivos pom.xml: $(find / -name "pom.xml" -not -path "/proc/*" 2>/dev/null | wc -l)";
         echo "diretorio .m2   : $(test -d /root/.m2 && echo EXISTE || echo ausente)"'
    echo ""
    echo "## Runtime Java e usuario do processo"
    docker run --rm --entrypoint sh "${image}" -c 'java -version 2>&1 | head -1; echo "usuario: $(id)"'
    echo ""
    echo "## Estagios declarados no Dockerfile"
    grep -nE '^FROM' Dockerfile
}
save "18-multistage-inspecao.txt" multistage_report

run_tests() {
    echo "# Saida de 'mvn test' na mesma imagem do estagio de build"
    echo "# Coletado em $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
        -v "$(host_path_for_docker "${PROJECT_ROOT}"):/workspace" \
        -v devops-obs-m2:/root/.m2 -w /workspace \
        maven:3.9.9-eclipse-temurin-21 \
        mvn -B -ntp test 2>&1 | grep -vE '^\[INFO\] Download' | tail -60
}
save "19-mvn-test.txt" run_tests

save "20-smoke-test.txt" bash "${PROJECT_ROOT}/scripts/smoke-test.sh"

verify_run() {
    NO_COLOR=1 bash "${PROJECT_ROOT}/scripts/verify-stack.sh"
}
save "21-verify-stack.txt" verify_run

# =============================================================================
section "Resultado"
# =============================================================================
ls -lh "${OUT_DIR}" | tail -n +2 | awk '{printf "  %-46s %s\n", $9, $5}'
echo ""
ok "Evidencias em docs/evidencias/"
