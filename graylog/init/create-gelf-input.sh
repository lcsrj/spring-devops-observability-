#!/bin/sh
# =============================================================================
#  graylog-init - provisiona o Input GELF UDP do Graylog automaticamente
#
#  Objetivo: `docker compose up --build` deve entregar a stack pronta para uso.
#  O avaliador NAO precisa abrir o Graylog, navegar em menus nem criar Input
#  algum manualmente.
#
#  Comportamento:
#    1. aguarda o Graylog ficar realmente saudavel (/api/system/lbstatus);
#    2. consulta os inputs existentes;
#    3. cria o Input GELF UDP apenas se ainda nao existir  (IDEMPOTENTE);
#    4. confirma que o input esta ativo;
#    5. encerra com exit code 0 em caso de sucesso, != 0 em caso de falha.
#
#  Dependencias: apenas `sh` e `curl` (imagem curlimages/curl).
# =============================================================================
set -eu

GRAYLOG_URL="${GRAYLOG_URL:-http://graylog:9000}"
GRAYLOG_USER="${GRAYLOG_USER:-admin}"
GRAYLOG_PASSWORD="${GRAYLOG_PASSWORD:-admin}"
INPUT_TITLE="${INPUT_TITLE:-GELF UDP - Spring Boot}"
INPUT_PORT="${INPUT_PORT:-12201}"
INPUT_TYPE="org.graylog2.inputs.gelf.udp.GELFUDPInput"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-300}"

API="${GRAYLOG_URL}/api"
AUTH="${GRAYLOG_USER}:${GRAYLOG_PASSWORD}"

log() {
    echo "[graylog-init] $*"
}

fail() {
    echo "[graylog-init] ERRO: $*" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# 1) Espera ativa pelo Graylog (readiness real, sem `sleep` cego)
# -----------------------------------------------------------------------------
log "aguardando o Graylog responder em ${GRAYLOG_URL} (limite de ${MAX_WAIT_SECONDS}s)..."

waited=0
until [ "${waited}" -ge "${MAX_WAIT_SECONDS}" ]; do
    lb_status="$(curl -s -f -m 5 "${API}/system/lbstatus" 2>/dev/null || true)"
    if [ "${lb_status}" = "ALIVE" ] || [ "${lb_status}" = "alive" ]; then
        log "Graylog saudavel apos ${waited}s (lbstatus=${lb_status})"
        break
    fi
    waited=$((waited + 3))
    sleep 3
done

if [ "${waited}" -ge "${MAX_WAIT_SECONDS}" ]; then
    fail "o Graylog nao ficou saudavel dentro de ${MAX_WAIT_SECONDS}s"
fi

# -----------------------------------------------------------------------------
# 2) Espera a API autenticada aceitar requisicoes (indice/usuario prontos)
# -----------------------------------------------------------------------------
log "validando o acesso autenticado a API..."

waited=0
until [ "${waited}" -ge 90 ]; do
    if curl -s -f -m 5 -u "${AUTH}" -H 'X-Requested-By: graylog-init' \
        "${API}/system/inputs" -o /tmp/inputs.json 2>/dev/null; then
        log "API autenticada respondendo"
        break
    fi
    waited=$((waited + 3))
    sleep 3
done

if [ ! -s /tmp/inputs.json ]; then
    fail "nao foi possivel autenticar na API do Graylog com o usuario '${GRAYLOG_USER}'"
fi

# -----------------------------------------------------------------------------
# 3) Idempotencia: cria o input somente se ele ainda nao existir
# -----------------------------------------------------------------------------
if grep -q "${INPUT_TYPE}" /tmp/inputs.json; then
    log "input GELF UDP ja existe - nada a fazer (execucao idempotente)"
else
    log "criando input '${INPUT_TITLE}' (GELF UDP na porta ${INPUT_PORT})..."

    http_code="$(curl -s -o /tmp/create.json -w '%{http_code}' -m 20 \
        -X POST "${API}/system/inputs" \
        -u "${AUTH}" \
        -H 'Content-Type: application/json' \
        -H 'X-Requested-By: graylog-init' \
        -d "{
              \"title\": \"${INPUT_TITLE}\",
              \"type\": \"${INPUT_TYPE}\",
              \"global\": true,
              \"configuration\": {
                \"bind_address\": \"0.0.0.0\",
                \"port\": ${INPUT_PORT},
                \"recv_buffer_size\": 262144,
                \"number_worker_threads\": 2,
                \"decompress_size_limit\": 8388608,
                \"override_source\": null
              }
            }")"

    if [ "${http_code}" != "201" ] && [ "${http_code}" != "200" ]; then
        log "resposta da API: $(cat /tmp/create.json 2>/dev/null)"
        fail "falha ao criar o input (HTTP ${http_code})"
    fi

    log "input criado com sucesso (HTTP ${http_code})"
fi

# -----------------------------------------------------------------------------
# 4) Confirmacao final: o input precisa estar listado E em execucao
# -----------------------------------------------------------------------------
log "confirmando que o input esta ativo..."

waited=0
confirmed=0
until [ "${waited}" -ge 60 ]; do
    curl -s -f -m 5 -u "${AUTH}" -H 'X-Requested-By: graylog-init' \
        "${API}/system/inputstates" -o /tmp/states.json 2>/dev/null || true

    if grep -q '"state":"RUNNING"' /tmp/states.json 2>/dev/null && \
       grep -q "${INPUT_TYPE}" /tmp/states.json 2>/dev/null; then
        confirmed=1
        break
    fi
    waited=$((waited + 3))
    sleep 3
done

if [ "${confirmed}" -ne 1 ]; then
    log "estado retornado: $(cat /tmp/states.json 2>/dev/null)"
    fail "o input GELF nao entrou em estado RUNNING"
fi

log "OK: input GELF UDP ${INPUT_PORT} esta RUNNING e pronto para receber logs"
log "provisionamento concluido"
exit 0
