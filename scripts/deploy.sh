#!/usr/bin/env bash
#
# Dispara o deploy de uma imagem ja publicada no registry para um servico do
# Render e aguarda o resultado.
#
# O script recebe a tag exata da imagem, e nao "latest": o que vai para o ar e
# exatamente o artefato que passou pelo pipeline.
#
# Uso:
#   scripts/deploy.sh <service-id> <image-url>
#
# Variaveis de ambiente obrigatorias:
#   RENDER_API_KEY   token de API do Render
#
# Variaveis opcionais:
#   DEPLOY_TIMEOUT   segundos de espera pelo deploy (padrao 600)
#   POLL_INTERVAL    segundos entre consultas de status (padrao 15)

set -euo pipefail

readonly SERVICE_ID="${1:-}"
readonly IMAGE_URL="${2:-}"
readonly API="https://api.render.com/v1"
readonly TIMEOUT="${DEPLOY_TIMEOUT:-600}"
readonly INTERVAL="${POLL_INTERVAL:-15}"

log() {
  printf '[deploy] %s\n' "$1"
}

fail() {
  printf '[deploy] erro: %s\n' "$1" >&2
  exit 1
}

[[ -n "$SERVICE_ID" ]] || fail "informe o id do servico como primeiro argumento"
[[ -n "$IMAGE_URL" ]] || fail "informe a url da imagem como segundo argumento"
[[ -n "${RENDER_API_KEY:-}" ]] || fail "a variavel RENDER_API_KEY nao esta definida"

log "servico $SERVICE_ID"
log "imagem  $IMAGE_URL"

response=$(
  curl --silent --show-error --fail-with-body \
    --request POST "$API/services/$SERVICE_ID/deploys" \
    --header "Authorization: Bearer $RENDER_API_KEY" \
    --header 'Content-Type: application/json' \
    --data "{\"imageUrl\":\"$IMAGE_URL\",\"clearCache\":\"do_not_clear\"}"
) || fail "o Render recusou a solicitacao de deploy"

deploy_id=$(printf '%s' "$response" | node -e \
  'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{process.stdout.write(JSON.parse(d).id??"")})')

[[ -n "$deploy_id" ]] || fail "a resposta do Render nao trouxe o id do deploy: $response"

log "deploy $deploy_id solicitado, aguardando conclusao"

elapsed=0
while ((elapsed < TIMEOUT)); do
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))

  status=$(
    curl --silent --show-error --fail-with-body \
      "$API/services/$SERVICE_ID/deploys/$deploy_id" \
      --header "Authorization: Bearer $RENDER_API_KEY" |
      node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{process.stdout.write(JSON.parse(d).status??"")})'
  )

  log "status: ${status:-desconhecido} (${elapsed}s)"

  case "$status" in
    live)
      log "deploy concluido"
      exit 0
      ;;
    build_failed | update_failed | canceled | pre_deploy_failed)
      fail "o deploy terminou como $status"
      ;;
  esac
done

fail "o deploy nao concluiu dentro de ${TIMEOUT}s"
