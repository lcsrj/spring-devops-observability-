#!/usr/bin/env bash
# =============================================================================
#  lib.sh - funcoes compartilhadas pelos scripts de validacao
#
#  Nao e executado diretamente: os outros scripts fazem `. lib.sh`.
#  As URLs respeitam as mesmas variaveis de porta usadas pelo docker-compose,
#  entao um .env que troque as portas continua funcionando aqui.
# =============================================================================

# Carrega o .env do projeto (se existir) para herdar as portas configuradas.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
if [ -f "${PROJECT_ROOT}/.env" ]; then
    # shellcheck disable=SC1091
    set -a; . "${PROJECT_ROOT}/.env"; set +a
fi

APP_PORT="${APP_PORT:-8080}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GRAYLOG_PORT="${GRAYLOG_PORT:-9000}"

APP_URL="${APP_URL:-http://localhost:${APP_PORT}}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:${PROMETHEUS_PORT}}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:${GRAFANA_PORT}}"
GRAYLOG_URL="${GRAYLOG_URL:-http://localhost:${GRAYLOG_PORT}}"

GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin123}"
GRAYLOG_ADMIN_USER="${GRAYLOG_ADMIN_USER:-admin}"
GRAYLOG_ADMIN_PASSWORD="${GRAYLOG_ADMIN_PASSWORD:-admin}"

COMPOSE_PROJECT="${COMPOSE_PROJECT:-spring-devops-observability}"

# ----------------------------- saida colorida --------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

CHECKS_TOTAL=0
CHECKS_FAILED=0

section() {
    echo ""
    echo "${C_BOLD}${C_BLUE}== $* ==${C_RESET}"
}

ok()   { echo "${C_GREEN}OK${C_RESET}   $*"; }
warn() { echo "${C_YELLOW}AVISO${C_RESET} $*"; }
err()  { echo "${C_RED}ERRO${C_RESET} $*" >&2; }

pass_inline() { echo "${C_GREEN}OK${C_RESET} - $*"; }
fail_inline() { echo "${C_RED}FALHOU${C_RESET} - $*"; }
warn_inline() { echo "${C_YELLOW}IGNORADA${C_RESET} - $*"; }

# check <descricao> <comando...>
# Executa o comando e contabiliza o resultado. Nao aborta: o script segue e
# devolve exit code != 0 no final se algo falhou.
check() {
    local description="$1"; shift
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    printf '  %-58s ' "${description}"
    local output
    if output="$("$@" 2>&1)"; then
        if [ -n "${output}" ]; then
            pass_inline "${output}"
        else
            echo "${C_GREEN}OK${C_RESET}"
        fi
        return 0
    fi
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fail_inline "${output:-sem detalhes}"
    return 1
}

summary() {
    local passed=$((CHECKS_TOTAL - CHECKS_FAILED))
    echo ""
    if [ "${CHECKS_FAILED}" -eq 0 ]; then
        echo "${C_BOLD}${C_GREEN}RESULTADO: ${passed}/${CHECKS_TOTAL} verificacoes passaram${C_RESET}"
        return 0
    fi
    echo "${C_BOLD}${C_RED}RESULTADO: ${CHECKS_FAILED} de ${CHECKS_TOTAL} verificacoes FALHARAM${C_RESET}"
    return 1
}

# --------------------------- helpers de HTTP/Docker --------------------------

http_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1"
}

# expect_http <url> <codigo_esperado>
expect_http() {
    local url="$1" expected="$2" actual
    actual="$(http_code "${url}")"
    if [ "${actual}" = "${expected}" ]; then
        echo "HTTP ${actual}"
        return 0
    fi
    echo "esperado HTTP ${expected}, obtido HTTP ${actual} em ${url}"
    return 1
}

# body_contains <url> <texto>
body_contains() {
    local url="$1" needle="$2"
    if curl -s --max-time 15 "${url}" | grep -q -- "${needle}"; then
        echo "'${needle}' presente"
        return 0
    fi
    echo "'${needle}' ausente na resposta de ${url}"
    return 1
}

# wait_http <rotulo> <url> <timeout>
wait_http() {
    local label="$1" url="$2" timeout="$3" waited=0
    printf '  %-12s ' "${label}"
    while [ "${waited}" -lt "${timeout}" ]; do
        if curl -s -f --max-time 5 "${url}" >/dev/null 2>&1; then
            pass_inline "respondendo (${url})"
            return 0
        fi
        waited=$((waited + 3))
        sleep 3
    done
    fail_inline "sem resposta em ${url} apos ${timeout}s"
    return 1
}

container_health() {
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        "$(compose_container_id "$1")" 2>/dev/null
}

container_state() {
    docker inspect --format '{{.State.Status}}' "$(compose_container_id "$1")" 2>/dev/null
}

container_exit_code() {
    local id
    id="$(compose_container_id "$1")"
    [ -z "${id}" ] && return 0
    local status
    status="$(docker inspect --format '{{.State.Status}}' "${id}" 2>/dev/null)"
    if [ "${status}" = "exited" ]; then
        docker inspect --format '{{.State.ExitCode}}' "${id}" 2>/dev/null
    fi
}

compose_container_id() {
    docker ps -aq --filter "label=com.docker.compose.project=${COMPOSE_PROJECT}" \
                  --filter "label=com.docker.compose.service=$1" 2>/dev/null | head -1
}

# prom_query <promql> -> imprime o primeiro valor escalar do resultado
prom_query() {
    curl -s --max-time 15 --get --data-urlencode "query=$1" \
        "${PROMETHEUS_URL}/api/v1/query" \
        | sed -n 's/.*"value":\[[^,]*,"\([^"]*\)".*/\1/p' | head -1
}

# metric_has_value <promql> [tentativas]
# Falha se a serie nao existir. Tenta novamente por alguns segundos porque o
# Prometheus faz scrape a cada 5s: uma metrica criada agora (por exemplo o
# contador de eventos de log) pode ainda nao ter sido coletada.
metric_has_value() {
    local query="$1" attempts="${2:-6}" value="" i=0
    while [ "${i}" -lt "${attempts}" ]; do
        value="$(prom_query "${query}")"
        if [ -n "${value}" ] && [ "${value}" != "NaN" ]; then
            echo "valor = ${value}"
            return 0
        fi
        i=$((i + 1))
        [ "${i}" -lt "${attempts}" ] && sleep 3
    done
    echo "sem dados apos $((attempts * 3))s para: ${query}"
    return 1
}

# ------------------------------- Graylog API ---------------------------------
# O header `Accept: application/json` e OBRIGATORIO: sem ele a negociacao de
# conteudo do Graylog roteia a busca para o endpoint de export em CSV, que exige
# o parametro `fields` e responde HTTP 400.
graylog_api() {
    local path="$1"; shift
    curl -s --max-time 25 \
        -u "${GRAYLOG_ADMIN_USER}:${GRAYLOG_ADMIN_PASSWORD}" \
        -H 'Accept: application/json' \
        -H 'X-Requested-By: observability-scripts' \
        "$@" "${GRAYLOG_URL}${path}"
}

# graylog_search_total <query_lucene> [range_segundos] -> imprime total_results
graylog_search_total() {
    graylog_api "/api/search/universal/relative" \
        --get --data-urlencode "query=$1" \
              --data-urlencode "range=${2:-900}" \
              --data-urlencode "limit=1" \
        | sed -n 's/.*"total_results":\([0-9]*\).*/\1/p' | head -1
}

# --------------------------- caminho para bind mount -------------------------
# No Git Bash/MSYS o caminho POSIX precisa virar caminho Windows, senao o Docker
# recebe algo como 'C:/Program Files/Git/workspace' no argumento -w.
host_path_for_docker() {
    local path="$1"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            if command -v cygpath >/dev/null 2>&1; then
                cygpath -m "${path}"
            else
                echo "${path}" | sed -E 's#^/([a-zA-Z])/#\1:/#'
            fi
            ;;
        *) echo "${path}" ;;
    esac
}

# docker_run <args...> - docker run sem conversao automatica de caminhos (MSYS)
docker_run() {
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run "$@"
}
