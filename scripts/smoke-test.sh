#!/usr/bin/env bash
#
# Verificacao pos-deploy: exercita a API publicada de ponta a ponta e falha se
# qualquer passo divergir do esperado.
#
# Uso:
#   scripts/smoke-test.sh https://tasks-api-staging.onrender.com
#
# Variaveis opcionais:
#   WAIT_RETRIES   tentativas de espera pelo health check (padrao 20)
#   WAIT_INTERVAL  segundos entre tentativas (padrao 15)

set -euo pipefail

readonly BASE_URL="${1:-}"
readonly RETRIES="${WAIT_RETRIES:-20}"
readonly INTERVAL="${WAIT_INTERVAL:-15}"

passed=0
failed=0

log() {
  printf '[smoke] %s\n' "$1"
}

check() {
  local description="$1" expected="$2" actual="$3"

  if [[ "$actual" == "$expected" ]]; then
    printf '[smoke] ok   %s\n' "$description"
    passed=$((passed + 1))
  else
    printf '[smoke] FALHA %s (esperado %s, recebido %s)\n' "$description" "$expected" "$actual" >&2
    failed=$((failed + 1))
  fi
}

status_of() {
  curl --silent --output /dev/null --write-out '%{http_code}' "$@"
}

json_field() {
  node -e \
    'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{process.stdout.write(String(JSON.parse(d)[process.argv[1]]??""))}catch{process.stdout.write("")}})' \
    "$1"
}

[[ -n "$BASE_URL" ]] || {
  printf '[smoke] erro: informe a url base como argumento\n' >&2
  exit 1
}

log "alvo $BASE_URL"

# O free tier do Render hiberna o servico apos inatividade, e a primeira
# requisicao acorda a instancia. Por isso a espera antes de avaliar qualquer
# criterio.
log "aguardando o servico responder"
for ((attempt = 1; attempt <= RETRIES; attempt++)); do
  if [[ "$(status_of --max-time 30 "$BASE_URL/health")" == "200" ]]; then
    log "servico respondeu na tentativa $attempt"
    break
  fi

  if ((attempt == RETRIES)); then
    printf '[smoke] erro: o servico nao respondeu depois de %s tentativas\n' "$RETRIES" >&2
    exit 1
  fi

  sleep "$INTERVAL"
done

check 'GET /health responde 200' 200 "$(status_of "$BASE_URL/health")"
check 'GET /tasks responde 200' 200 "$(status_of "$BASE_URL/tasks")"
check 'GET /metrics responde 200' 200 "$(status_of "$BASE_URL/metrics")"

created=$(
  curl --silent --request POST "$BASE_URL/tasks" \
    --header 'Content-Type: application/json' \
    --data '{"title":"smoke test do pipeline"}'
)
task_id=$(printf '%s' "$created" | json_field id)

check 'POST /tasks devolveu um identificador' 'presente' "$(if [[ -n "$task_id" ]]; then echo presente; else echo ausente; fi)"
check 'a tarefa nasce pendente' 'pending' "$(printf '%s' "$created" | json_field status)"

if [[ -n "$task_id" ]]; then
  completed=$(curl --silent --request POST "$BASE_URL/tasks/$task_id/complete")
  check 'POST /tasks/:id/complete conclui a tarefa' 'done' "$(printf '%s' "$completed" | json_field status)"
fi

check 'titulo vazio e rejeitado com 400' 400 \
  "$(status_of --request POST "$BASE_URL/tasks" --header 'Content-Type: application/json' --data '{}')"
check 'tarefa inexistente responde 404' 404 \
  "$(status_of --request POST "$BASE_URL/tasks/nao-existe/complete")"

printf '[smoke] %s aprovados, %s reprovados\n' "$passed" "$failed"

((failed == 0)) || exit 1
