#!/usr/bin/env bash
# =============================================================================
#  wait-stack.sh - espera a stack ficar realmente pronta
#
#  Usa readiness/health de verdade (healthchecks do Docker + endpoints HTTP).
#  Nao ha nenhum `sleep 30` cego.
#
#  Uso:   ./scripts/wait-stack.sh [timeout_em_segundos]
#  Exit:  0 = stack pronta | 1 = timeout
# =============================================================================
set -uo pipefail

TIMEOUT="${1:-420}"

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

section "Aguardando a stack ficar pronta (timeout ${TIMEOUT}s)"

start_epoch=$(date +%s)

elapsed() {
    echo $(( $(date +%s) - start_epoch ))
}

# -----------------------------------------------------------------------------
# 1) Containers com healthcheck precisam estar "healthy"
# -----------------------------------------------------------------------------
for service in mongodb opensearch graylog app prometheus grafana; do
    printf '  %-12s ' "${service}"
    while :; do
        state="$(container_health "${service}")"
        case "${state}" in
            healthy)
                pass_inline "healthy em $(elapsed)s"
                break
                ;;
            *)
                if [ "$(elapsed)" -ge "${TIMEOUT}" ]; then
                    fail_inline "timeout (estado: ${state:-desconhecido})"
                    exit 1
                fi
                sleep 3
                ;;
        esac
    done
done

# -----------------------------------------------------------------------------
# 2) O provisionador do Input GELF precisa ter terminado com sucesso
# -----------------------------------------------------------------------------
printf '  %-12s ' "graylog-init"
while :; do
    code="$(container_exit_code graylog-init)"
    if [ "${code}" = "0" ]; then
        pass_inline "provisionamento concluido (exit 0)"
        break
    fi
    if [ -n "${code}" ] && [ "${code}" != "0" ]; then
        fail_inline "o provisionamento falhou (exit ${code})"
        echo "     Veja os logs com: docker compose logs graylog-init"
        exit 1
    fi
    if [ "$(elapsed)" -ge "${TIMEOUT}" ]; then
        fail_inline "timeout aguardando o graylog-init"
        exit 1
    fi
    sleep 3
done

# -----------------------------------------------------------------------------
# 3) Endpoints HTTP respondendo do ponto de vista do host
# -----------------------------------------------------------------------------
wait_http "aplicacao"  "${APP_URL}/actuator/health"          "${TIMEOUT}" || exit 1
wait_http "prometheus" "${PROMETHEUS_URL}/-/ready"           "${TIMEOUT}" || exit 1
wait_http "grafana"    "${GRAFANA_URL}/api/health"           "${TIMEOUT}" || exit 1
wait_http "graylog"    "${GRAYLOG_URL}/api/system/lbstatus"  "${TIMEOUT}" || exit 1

echo ""
ok "Stack pronta em $(elapsed)s"
exit 0
