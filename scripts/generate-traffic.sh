#!/usr/bin/env bash
# =============================================================================
#  generate-traffic.sh - gera trafego HTTP real (2xx, 4xx e 5xx) e logs
#
#  Alimenta as metricas do Prometheus/Grafana e envia eventos aos quatro niveis
#  de log para o Graylog. Todas as chamadas atravessam o backend Spring.
#
#  Uso:   ./scripts/generate-traffic.sh [rodadas]        (default: 3)
#  Exit:  0 = trafego gerado | 1 = alguma chamada nao devolveu o status esperado
# =============================================================================
set -uo pipefail

ROUNDS="${1:-3}"

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

section "Gerando trafego real contra ${APP_URL} (${ROUNDS} rodada(s))"

count_2xx=0
count_4xx=0
count_5xx=0
unexpected=0
internal_requests=0

# call <metodo> <caminho> <status_esperado>
# Guarda o status em LAST_CODE em vez de imprimi-lo: usar $( ) criaria um
# subshell e os contadores acumulados seriam perdidos.
LAST_CODE=""
call() {
    local method="$1" path="$2" expected="$3" code
    if [ "${method}" = "POST" ]; then
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
                 -H 'Content-Type: application/json' "${APP_URL}${path}")"
    else
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${APP_URL}${path}")"
    fi

    LAST_CODE="${code}"

    case "${code}" in
        2*) count_2xx=$((count_2xx + 1)) ;;
        4*) count_4xx=$((count_4xx + 1)) ;;
        5*) count_5xx=$((count_5xx + 1)) ;;
    esac

    if [ "${code}" != "${expected}" ]; then
        unexpected=$((unexpected + 1))
        err "  ${method} ${path} devolveu HTTP ${code} (esperado ${expected})"
    fi
}

for round in $(seq 1 "${ROUNDS}"); do
    echo ""
    echo "  --- rodada ${round}/${ROUNDS} ---"

    # 2xx: varias chamadas de sucesso
    printf '  6x GET  /api/demo/ok            -> '
    for _ in 1 2 3 4 5 6; do call GET /api/demo/ok 200; printf '%s ' "${LAST_CODE}"; done
    echo ""

    # 4xx: erros de cliente
    printf '  2x GET  /api/demo/bad-request   -> '
    for _ in 1 2; do call GET /api/demo/bad-request 400; printf '%s ' "${LAST_CODE}"; done
    echo ""

    # 5xx: erros de servidor
    printf '  1x GET  /api/demo/error         -> '
    call GET /api/demo/error 500; printf '%s\n' "${LAST_CODE}"

    # Rajada executada pelo proprio backend (mistura 2xx/4xx/5xx internamente)
    printf '  1x POST /api/demo/traffic       -> '
    call POST /api/demo/traffic 200
    printf '%s\n' "${LAST_CODE}"
    [ "${LAST_CODE}" = "200" ] && internal_requests=$((internal_requests + 25))

    # Logs nos quatro niveis exigidos
    for level in debug info warn error; do
        call POST "/api/demo/log/${level}" 200
        printf '  1x POST /api/demo/log/%-10s -> %s\n' "${level}" "${LAST_CODE}"
    done
done

section "Resumo do trafego gerado"
printf '  respostas 2xx ....................... %s\n' "${count_2xx}"
printf '  respostas 4xx ....................... %s\n' "${count_4xx}"
printf '  respostas 5xx ....................... %s\n' "${count_5xx}"
printf '  status inesperados .................. %s\n' "${unexpected}"
printf '  requisicoes internas da rajada ...... %s\n' "${internal_requests}"
echo ""
echo "  As requisicoes internas sao disparadas pelo proprio backend em"
echo "  POST /api/demo/traffic (mistura de 2xx/4xx/5xx) e tambem aparecem"
echo "  nas metricas coletadas pelo Prometheus."

if [ "${unexpected}" -ne 0 ]; then
    echo ""
    err "Algumas chamadas nao devolveram o status esperado"
    exit 1
fi

if [ "${count_2xx}" -eq 0 ] || [ "${count_4xx}" -eq 0 ] || [ "${count_5xx}" -eq 0 ]; then
    echo ""
    err "As tres familias de status (2xx/4xx/5xx) precisam ter sido exercitadas"
    exit 1
fi

echo ""
ok "Trafego 2xx, 4xx e 5xx gerado com sucesso, e logs DEBUG/INFO/WARN/ERROR emitidos"
exit 0
