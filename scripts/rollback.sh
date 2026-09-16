#!/usr/bin/env bash
#
# Reverte um servico do Render para uma imagem anterior.
#
# Como cada build publica uma tag imutavel no registry, voltar de versao e
# apontar o servico para a tag anterior. Nao ha rebuild nem checkout: o
# artefato antigo continua exatamente como foi testado.
#
# Uso:
#   scripts/rollback.sh <service-id> <sha-anterior>
#
# Variaveis de ambiente obrigatorias:
#   RENDER_API_KEY   token de API do Render
#   IMAGE_REPO       repositorio da imagem, por exemplo ghcr.io/usuario/tasks-api

set -euo pipefail

readonly SERVICE_ID="${1:-}"
readonly TARGET_SHA="${2:-}"

fail() {
  printf '[rollback] erro: %s\n' "$1" >&2
  exit 1
}

[[ -n "$SERVICE_ID" ]] || fail "informe o id do servico como primeiro argumento"
[[ -n "$TARGET_SHA" ]] || fail "informe o sha de destino como segundo argumento"
[[ -n "${IMAGE_REPO:-}" ]] || fail "a variavel IMAGE_REPO nao esta definida"

printf '[rollback] revertendo %s para %s\n' "$SERVICE_ID" "$TARGET_SHA"

exec "$(dirname "$0")/deploy.sh" "$SERVICE_ID" "$IMAGE_REPO:$TARGET_SHA"
