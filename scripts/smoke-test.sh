#!/usr/bin/env bash
# =============================================================================
#  smoke-test.sh - verificacao rapida de que toda a stack responde
#
#  Valida: aplicacao, actuator health, endpoint Prometheus da aplicacao,
#  Prometheus, Grafana e Graylog.
#
#  Uso:   ./scripts/smoke-test.sh
#  Exit:  0 = tudo respondendo | 1 = alguma verificacao falhou
# =============================================================================
set -uo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

echo "${C_BOLD}SMOKE TEST - DevOps Observability Control Center${C_RESET}"
echo "  app        ${APP_URL}"
echo "  prometheus ${PROMETHEUS_URL}"
echo "  grafana    ${GRAFANA_URL}"
echo "  graylog    ${GRAYLOG_URL}"

# -----------------------------------------------------------------------------
section "1. Aplicacao Spring Boot"
# -----------------------------------------------------------------------------
check "GET / entrega a interface web"               expect_http "${APP_URL}/" 200
check "a interface contem o painel de trafego"      body_contains "${APP_URL}/" "Gerar trafego"
check "a interface contem o painel de logs"         body_contains "${APP_URL}/" "Gerar logs"
check "CSS proprio e servido pela aplicacao"        expect_http "${APP_URL}/css/app.css" 200
check "JS proprio e servido pela aplicacao"         expect_http "${APP_URL}/js/app.js" 200
check "GET /api/status responde"                    expect_http "${APP_URL}/api/status" 200
check "GET /api/status reporta status UP"           body_contains "${APP_URL}/api/status" '"status":"UP"'
check "GET /api/history responde"                   expect_http "${APP_URL}/api/history" 200

# -----------------------------------------------------------------------------
section "2. Endpoints de demonstracao"
# -----------------------------------------------------------------------------
check "GET /api/demo/ok devolve 200"                expect_http "${APP_URL}/api/demo/ok" 200
check "GET /api/demo/bad-request devolve 400"       expect_http "${APP_URL}/api/demo/bad-request" 400
check "GET /api/demo/error devolve 500"             expect_http "${APP_URL}/api/demo/error" 500

# -----------------------------------------------------------------------------
section "3. Spring Boot Actuator"
# -----------------------------------------------------------------------------
check "/actuator/health responde"                   expect_http "${APP_URL}/actuator/health" 200
check "/actuator/health reporta UP"                 body_contains "${APP_URL}/actuator/health" '"status":"UP"'
check "/actuator/health/readiness responde"         expect_http "${APP_URL}/actuator/health/readiness" 200
check "/actuator/info responde"                     expect_http "${APP_URL}/actuator/info" 200
check "/actuator/prometheus responde"               expect_http "${APP_URL}/actuator/prometheus" 200

section "3b. Superficie administrativa minima (nao deve estar exposta)"
check "/actuator/env nao esta exposto"              expect_http "${APP_URL}/actuator/env" 404
check "/actuator/beans nao esta exposto"            expect_http "${APP_URL}/actuator/beans" 404
check "/actuator/heapdump nao esta exposto"         expect_http "${APP_URL}/actuator/heapdump" 404

# -----------------------------------------------------------------------------
section "4. Prometheus"
# -----------------------------------------------------------------------------
check "Prometheus esta acessivel"                   expect_http "${PROMETHEUS_URL}/-/healthy" 200
check "Prometheus esta pronto para consultas"       expect_http "${PROMETHEUS_URL}/-/ready" 200
check "a API de query do Prometheus responde"       expect_http "${PROMETHEUS_URL}/api/v1/query?query=up" 200

# -----------------------------------------------------------------------------
section "5. Grafana"
# -----------------------------------------------------------------------------
check "Grafana esta acessivel"                      expect_http "${GRAFANA_URL}/api/health" 200
check "o banco interno do Grafana esta ok"          body_contains "${GRAFANA_URL}/api/health" '"database"'
check "a pagina de login do Grafana carrega"        expect_http "${GRAFANA_URL}/login" 200

# -----------------------------------------------------------------------------
section "6. Graylog"
# -----------------------------------------------------------------------------
check "Graylog esta acessivel"                      expect_http "${GRAYLOG_URL}/api/system/lbstatus" 200
check "Graylog reporta estar vivo"                  body_contains "${GRAYLOG_URL}/api/system/lbstatus" "ALIVE"
check "a interface web do Graylog carrega"          expect_http "${GRAYLOG_URL}/" 200

summary
exit $?
