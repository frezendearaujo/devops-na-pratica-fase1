# DevOps na Prática

Repositório do projeto da disciplina **DevOps na Prática** (GraduPUCRS Online), entregue em duas
fases sobre a mesma base de código.

A aplicação é uma **API REST de gerenciamento de tarefas** escrita em Node.js com TypeScript. Ela
não é o objetivo do trabalho: serve de veículo para exercitar o que as fases pedem.

| Fase | Escopo                                                                                         |
| ---- | ---------------------------------------------------------------------------------------------- |
| 1    | Integração contínua com testes automatizados e infraestrutura como código na AWS via Terraform |
| 2    | Entrega contínua, containers e orquestração, monitoramento, logging, testes e segurança        |

## Sumário

- [Aplicação](#aplicação)
- [Como rodar localmente](#como-rodar-localmente)
- [Endpoints](#endpoints)
- [Docker](#docker)
- [Orquestração local com Docker Compose](#orquestração-local-com-docker-compose)
- [Pipeline de Integração Contínua](#pipeline-de-integração-contínua)
- [Pipeline de Entrega Contínua](#pipeline-de-entrega-contínua)
- [Scripts de deploy](#scripts-de-deploy)
- [Monitoramento e logging](#monitoramento-e-logging)
- [Segurança](#segurança)
- [Infraestrutura como Código](#infraestrutura-como-código)
- [Gerenciamento de configurações](#gerenciamento-de-configurações)
- [Estrutura do repositório](#estrutura-do-repositório)

## Aplicação

| Item           | Escolha                              |
| -------------- | ------------------------------------ |
| Linguagem      | TypeScript (ESM, `module: NodeNext`) |
| Runtime        | Node.js 22 LTS                       |
| Framework HTTP | Express                              |
| Persistência   | Em memória (o container é stateless) |
| Testes         | Vitest + Supertest                   |
| Qualidade      | ESLint (flat config) + Prettier      |

### Pré-requisitos

- Node.js 22 ou superior
- npm 10 ou superior
- Docker (opcional, para rodar em container)
- Terraform 1.9+ e credenciais AWS (opcional, para a infraestrutura)

## Como rodar localmente

```bash
npm ci                # instala as dependências a partir do package-lock.json
npm run dev           # sobe em modo watch na porta 3000
npm test              # executa os testes unitários e de integração
npm run lint          # análise estática com ESLint
npm run build         # compila o TypeScript para dist/
npm start             # executa a versão compilada
```

A porta é configurável pela variável de ambiente `PORT` (padrão `3000`).

## Endpoints

| Método | Rota                  | Descrição                         | Respostas    |
| ------ | --------------------- | --------------------------------- | ------------ |
| `GET`  | `/health`             | Verificação de saúde do serviço   | `200`        |
| `GET`  | `/metrics`            | Métricas no formato do Prometheus | `200`        |
| `GET`  | `/tasks`              | Lista todas as tarefas            | `200`        |
| `POST` | `/tasks`              | Cria uma tarefa                   | `201`, `400` |
| `POST` | `/tasks/:id/complete` | Marca a tarefa como concluída     | `200`, `404` |

### Modelo

```jsonc
{
  "id": "3f2b...", // uuid gerado pela aplicação
  "title": "estudar terraform",
  "status": "pending", // "pending" | "done"
  "createdAt": "2026-08-24T20:17:50.123Z",
}
```

### Validação do título

Obrigatório, precisa ser string, não pode ser vazio nem conter apenas espaços (o valor é
normalizado com `trim`) e é limitado a 120 caracteres. Erros são devolvidos como
`{ "error": "mensagem" }`.

### Exemplos

```bash
curl http://localhost:3000/health
# {"status":"ok"}

curl -X POST http://localhost:3000/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"escrever a documentação"}'
# {"id":"...","title":"escrever a documentação","status":"pending","createdAt":"..."}

curl http://localhost:3000/tasks

curl -X POST http://localhost:3000/tasks/<id>/complete
# {"id":"...","status":"done",...}

curl -X POST http://localhost:3000/tasks -H 'Content-Type: application/json' -d '{}'
# {"error":"title is required"}
```

## Docker

A imagem usa build em múltiplos estágios: o primeiro instala todas as dependências e compila o
TypeScript; o segundo carrega apenas `dist/` e as dependências de produção, e executa como o
usuário não-root `node`.

A imagem declara um `HEALTHCHECK` que consulta o próprio `/health`, então o orquestrador só
considera a instância saudável quando o processo responde de fato.

```bash
docker build -t tasks-api .
docker run -d -p 3000:3000 --name tasks-api tasks-api
docker ps                      # a coluna STATUS mostra (healthy)
curl http://localhost:3000/health
```

## Orquestração local com Docker Compose

O [`docker-compose.yml`](docker-compose.yml) sobe dois containers: a aplicação e um Prometheus que
raspa o endpoint `/metrics` a cada 15 segundos. O Prometheus só inicia depois que o healthcheck da
aplicação passa, o que é declarado por `depends_on: condition: service_healthy`.

```bash
docker compose up -d --build
curl http://localhost:8080/health
curl http://localhost:8080/metrics
open http://localhost:9090/targets     # alvo tasks-api-local em UP
docker compose down
```

As regras de alerta ficam em [`monitoring/alerts.yml`](monitoring/alerts.yml) e cobrem
indisponibilidade, taxa de erro acima de 5% e percentil 95 do tempo de resposta acima de um
segundo.

## Pipeline de Integração Contínua

Definido em [`.github/workflows/ci.yml`](.github/workflows/ci.yml) e executado no GitHub Actions.

### Gatilhos

- `push` na branch `main`
- `pull_request` com destino à `main`

Ou seja: toda proposta de mudança é validada antes do merge, e a `main` é revalidada depois dele.

### Jobs

| Job         | O que executa                                                          | Falha quando                                                                            |
| ----------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `lint`      | ESLint, `prettier --check`, `tsc --noEmit` e `shellcheck scripts/*.sh` | Há violação de regra, arquivo fora do padrão de formatação, erro de tipagem ou de shell |
| `test`      | `npm test`                                                             | Qualquer um dos 24 casos falha                                                          |
| `security`  | `npm audit --audit-level=high`                                         | Existe vulnerabilidade alta ou crítica nas dependências                                 |
| `terraform` | `fmt -check`, `init -backend=false`, `validate`                        | Os arquivos `.tf` estão fora do padrão ou a configuração é inválida                     |
| `build`     | build multi-stage, push no `ghcr.io` e varredura com Trivy             | O build quebra ou a imagem tem vulnerabilidade HIGH/CRITICAL com correção disponível    |

`lint`, `test`, `security` e `terraform` rodam em paralelo. `build` declara
`needs: [lint, test, security]` e só começa quando os três passam: não faz sentido gastar tempo
construindo um artefato a partir de código reprovado. `terraform` é independente dos demais.

O job `terraform` usa `init -backend=false` justamente para **não** precisar de credenciais da AWS:
ele baixa o provider e valida sintaxe, tipos e referências, sem tocar em nenhum recurso real.

Em pull request o `build` apenas constrói a imagem e não publica, porque escrever no registry a
partir de código ainda não revisado abriria caminho para publicação indevida.

## Pipeline de Entrega Contínua

O pipeline segue no mesmo arquivo, com dois jobs adicionais que só rodam em push na `main`.

```
lint ─┐
test ─┼─► build ─► push ghcr.io ─► Trivy ─► deploy-staging ─► smoke ─► [aprovação] ─► deploy-production ─► smoke
sec ──┘
terraform (paralelo)
```

O diagrama completo, com os caminhos de falha e rollback, está em
[`docs/fluxo-devops.md`](docs/fluxo-devops.md).

### Artefato imutável

Cada build publica duas tags no GitHub Container Registry:

```
ghcr.io/frezendearaujo/tasks-api:<sha-do-commit>
ghcr.io/frezendearaujo/tasks-api:latest
```

A tag do `sha` é o que sustenta todo o resto. O deploy aponta para ela, nunca para `latest`, então
o que vai ao ar é exatamente o artefato que passou pelos testes e pela varredura de segurança.
Rollback deixa de ser rebuild e passa a ser apontar o serviço para a tag anterior.

### Ambientes

| Ambiente     | Serviço no Render      | Gatilho                 | Proteção                         |
| ------------ | ---------------------- | ----------------------- | -------------------------------- |
| `staging`    | `tasks-api-staging`    | push na `main`          | nenhuma                          |
| `production` | `tasks-api-production` | após o smoke em staging | required reviewer no Environment |

O ambiente `production` é protegido por _required reviewer_ do GitHub Environments. O job fica
pendente até alguém autorizar, o que é a materialização do controle de mudança que a Aula 9
descreve com RFC e CAB, só que sem formulário.

### Configuração necessária

| Tipo     | Nome                           | Conteúdo                              |
| -------- | ------------------------------ | ------------------------------------- |
| Secret   | `RENDER_API_KEY`               | token de API do Render                |
| Secret   | `RENDER_SERVICE_ID_STAGING`    | id do serviço de staging (`srv-...`)  |
| Secret   | `RENDER_SERVICE_ID_PRODUCTION` | id do serviço de produção (`srv-...`) |
| Variable | `STAGING_URL`                  | URL pública do serviço de staging     |
| Variable | `PRODUCTION_URL`               | URL pública do serviço de produção    |

## Scripts de deploy

Os scripts ficam em [`scripts/`](scripts) e são chamados pelo pipeline, mas funcionam
isoladamente na linha de comando. Todos usam `set -euo pipefail` e são verificados por ShellCheck
no job de `lint`.

| Script                                           | Responsabilidade                                                                    |
| ------------------------------------------------ | ----------------------------------------------------------------------------------- |
| [`scripts/deploy.sh`](scripts/deploy.sh)         | Dispara o deploy de uma tag específica pela API do Render e aguarda o status `live` |
| [`scripts/smoke-test.sh`](scripts/smoke-test.sh) | Exercita a API publicada com 8 verificações e falha se alguma divergir              |
| [`scripts/rollback.sh`](scripts/rollback.sh)     | Reverte o serviço para uma tag anterior, sem rebuild                                |

```bash
# deploy manual de uma tag específica
RENDER_API_KEY=rnd_xxx ./scripts/deploy.sh srv-abc123 ghcr.io/frezendearaujo/tasks-api:1aef1cd

# verificação pós-deploy
./scripts/smoke-test.sh https://tasks-api-staging.onrender.com

# rollback para o commit anterior
RENDER_API_KEY=rnd_xxx IMAGE_REPO=ghcr.io/frezendearaujo/tasks-api \
  ./scripts/rollback.sh srv-abc123 e63ff64
```

O `deploy.sh` não devolve o controle assim que o Render aceita a solicitação: ele consulta o status
do deploy em intervalos regulares e só sai com código zero quando o serviço fica `live`. Sem isso o
smoke test rodaria contra a versão antiga e passaria por acidente.

O `smoke-test.sh` começa esperando o `/health` responder, porque o free tier do Render hiberna o
serviço após inatividade e a primeira requisição acorda a instância.

## Monitoramento e logging

| Camada                | Como                                                                                |
| --------------------- | ----------------------------------------------------------------------------------- |
| Métricas da aplicação | Endpoint `/metrics` no formato do Prometheus, servido por `prom-client`             |
| Coleta local          | Prometheus no `docker-compose.yml`, raspando o alvo a cada 15 segundos              |
| Alertas               | Regras em `monitoring/alerts.yml` para disponibilidade, taxa de erro e latência     |
| Logs e recursos       | Painel do Render, com log stream e gráficos de CPU e memória por serviço            |
| Sonda externa         | Workflow [`uptime.yml`](.github/workflows/uptime.yml) a cada seis horas             |
| Carga                 | Workflow [`load-test.yml`](.github/workflows/load-test.yml) sob demanda, autocannon |

As métricas expostas cobrem o que a Aula 6 trata como central:

| Métrica                          | Tipo      | Responde                                |
| -------------------------------- | --------- | --------------------------------------- |
| `http_requests_total`            | counter   | volume e taxa de erro por rota e status |
| `http_request_duration_seconds`  | histogram | tempo de resposta, inclusive percentis  |
| `process_resident_memory_bytes`  | gauge     | consumo de memória do processo          |
| `process_cpu_user_seconds_total` | counter   | consumo de CPU                          |
| `nodejs_eventloop_lag_seconds`   | gauge     | saturação do event loop                 |

O rótulo `route` usa o padrão da rota resolvido pelo Express, e não o caminho cru da requisição.
Usar o caminho cru faria cada `id` de tarefa criar uma série nova e explodir a cardinalidade das
métricas.

```bash
curl http://localhost:3000/metrics | grep http_requests_total
# http_requests_total{method="GET",route="/health",status="200",service="tasks-api"} 1
```

## Segurança

A esteira aplica o _shift left_ da Aula 7: a verificação acontece antes do artefato existir, não
depois do incidente.

| Controle                    | Ferramenta  | Momento                      | Bloqueia o pipeline   |
| --------------------------- | ----------- | ---------------------------- | --------------------- |
| SAST do código              | CodeQL      | push, pull request e semanal | sim                   |
| Dependências vulneráveis    | `npm audit` | antes do build               | sim, em HIGH          |
| Vulnerabilidades da imagem  | Trivy       | após o build                 | sim, em HIGH/CRITICAL |
| Atualização de dependências | Dependabot  | semanal, como pull request   | não                   |
| Qualidade dos scripts       | ShellCheck  | job de `lint`                | sim                   |

Outras decisões de segurança que atravessam o projeto:

- O container roda como o usuário não-root `node`, declarado no `Dockerfile`.
- A imagem final não carrega dependências de desenvolvimento nem o código TypeScript, apenas
  `dist/` e as dependências de produção.
- Nenhum segredo vive no repositório. `RENDER_API_KEY` e os ids de serviço são secrets do GitHub,
  e o `GITHUB_TOKEN` usado para publicar no registry é emitido por execução, com escopo mínimo
  (`packages: write`).
- O Terraform da Fase 1 não expõe a porta 22.
- O Trivy usa `ignore-unfixed`, então o pipeline falha por vulnerabilidade que tem correção
  disponível e não por achado sem patch, que só geraria ruído sem ação possível.

### Testes automatizados

| Arquivo                                                          | Nível      | Cobre                                                                                                                |
| ---------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------- |
| [`tests/task-repository.test.ts`](tests/task-repository.test.ts) | Unitário   | Geração de `id` e `createdAt`, status inicial, ordem da listagem, conclusão de tarefa, id inexistente e idempotência |
| [`tests/api.test.ts`](tests/api.test.ts)                         | Integração | Os quatro endpoints via HTTP: caminhos felizes, as cinco regras de validação (`400`) e tarefa inexistente (`404`)    |

Os testes de integração usam Supertest sobre a instância retornada por `createApp()`, sem abrir
porta. Cada caso recebe um `TaskRepository` novo, o que garante isolamento sem estado global.

## Infraestrutura como Código

Há duas camadas de infraestrutura declarada, uma por fase.

| Camada                   | Arquivo       | O que declara                                        |
| ------------------------ | ------------- | ---------------------------------------------------- |
| Rede e computação na AWS | `infra/*.tf`  | VPC, subnet, gateway, security group e instância EC2 |
| Plataforma de execução   | `render.yaml` | os dois serviços web, health check path e variáveis  |

O [`render.yaml`](render.yaml) é o blueprint que a Aula 10 pede: os dois ambientes nascem do
arquivo versionado, com `autoDeploy: false` nos dois, porque quem decide o que vai ao ar é o
pipeline e não o push. Nenhum dos serviços compila código, ambos apenas executam a imagem já
publicada no registry.

Os scripts Terraform ficam em [`infra/`](infra) e provisionam o ambiente que executa a aplicação
na AWS.

### Topologia

```
Internet
   │
   ▼
Internet Gateway
   │
   ▼
VPC 10.0.0.0/16
   └── Subnet pública 10.0.1.0/24  (map_public_ip_on_launch)
         └── Security Group  (ingress 80/tcp, egress liberado)
               └── EC2 t3.micro — Amazon Linux 2023
                     └── Docker → container tasks-api  (host:80 → container:3000)
```

### Recursos

| Arquivo        | Recursos                                                                                          |
| -------------- | ------------------------------------------------------------------------------------------------- |
| `versions.tf`  | Restrições de versão do Terraform (>= 1.9) e do provider AWS (~> 5.60)                            |
| `providers.tf` | Provider AWS com `default_tags` (`Project`, `Environment`, `ManagedBy`)                           |
| `variables.tf` | `region`, `project_name`, `instance_type`, `vpc_cidr`, `subnet_cidr`                              |
| `network.tf`   | `aws_vpc`, `aws_internet_gateway`, `aws_subnet`, `aws_route_table`, `aws_route_table_association` |
| `compute.tf`   | AMI via `aws_ssm_parameter`, `aws_security_group`, `aws_instance`                                 |
| `user_data.sh` | Bootstrap: instala Docker e Git, clona este repositório, constrói a imagem e sobe o container     |
| `outputs.tf`   | `instance_public_ip`, `api_url`, `health_check_url`                                               |

### Como aplicar

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # opcional: os defaults já funcionam
terraform init
terraform plan
terraform apply
curl "$(terraform output -raw health_check_url)"
terraform destroy
```

### Decisões

- **`t3.micro` e uma única instância** — cabe no free tier e é suficiente para a demonstração.
- **Sem porta 22 aberta** — a instância é configurada inteiramente pelo `user_data`, então não há
  motivo para expor SSH ao mundo. Para depurar, o caminho é o AWS Systems Manager Session Manager.
- **AMI resolvida via SSM** — buscar o parâmetro público `/aws/service/ami-amazon-linux-latest/...`
  evita fixar um ID que envelhece e quebra ao trocar de região.
- **State local** — o `terraform.tfstate` fica na máquina de quem aplica e está no `.gitignore`,
  porque este é um projeto individual. Em equipe, o correto seria um backend remoto (S3 com trava
  no DynamoDB) para permitir trabalho concorrente e evitar divergência de estado.
- **`.terraform.lock.hcl` versionado** — garante que todos usem exatamente a mesma versão do
  provider.
- **Sem load balancer** — um ALB traria alta disponibilidade, mas sai do free tier e não acrescenta
  nada ao que esta fase precisa demonstrar.

## Gerenciamento de configurações

Os itens de configuração do projeto, no vocabulário da Aula 9, e onde cada um é controlado.

| Item de configuração         | Onde vive                     | Versionado         |
| ---------------------------- | ----------------------------- | ------------------ |
| Código da aplicação          | `src/`                        | sim                |
| Definição da imagem          | `Dockerfile`, `.dockerignore` | sim                |
| Orquestração local           | `docker-compose.yml`          | sim                |
| Pipeline                     | `.github/workflows/`          | sim                |
| Infraestrutura AWS           | `infra/*.tf`                  | sim                |
| Plataforma de execução       | `render.yaml`                 | sim                |
| Coleta e alertas de métricas | `monitoring/`                 | sim                |
| Versão do provider Terraform | `infra/.terraform.lock.hcl`   | sim                |
| Versões de dependências      | `package-lock.json`           | sim                |
| Segredos e URLs por ambiente | GitHub Secrets e Variables    | não, por definição |

A baseline de cada versão é o commit, e o artefato correspondente é a imagem com a tag daquele
`sha`. Dado um commit, é possível dizer exatamente qual imagem foi construída, quais testes
passaram e em qual ambiente ela entrou. Essa é a rastreabilidade que o gerenciamento de
configurações busca.

Nenhum segredo entra no repositório. `.gitignore` bloqueia `.env`, `*.tfvars` e `terraform.tfstate`.

## Estrutura do repositório

```
.
├── .github/
│   ├── dependabot.yml           # atualização automática de dependências
│   └── workflows/
│       ├── ci.yml               # pipeline de CI e CD
│       ├── codeql.yml           # SAST
│       ├── uptime.yml           # sonda externa de disponibilidade
│       └── load-test.yml        # teste de carga sob demanda
├── src/
│   ├── app.ts                   # criação do app Express e rotas
│   ├── server.ts                # ponto de entrada (listen)
│   ├── metrics.ts               # registry e middleware do Prometheus
│   ├── task.ts                  # tipos do domínio
│   └── task-repository.ts       # armazenamento em memória
├── tests/
│   ├── api.test.ts              # testes de integração
│   ├── metrics.test.ts          # testes do endpoint de métricas
│   └── task-repository.test.ts  # testes unitários
├── scripts/
│   ├── deploy.sh                # deploy de uma tag pela API do Render
│   ├── smoke-test.sh            # verificação pós-deploy
│   └── rollback.sh              # reversão para a tag anterior
├── monitoring/
│   ├── prometheus.yml           # configuração de scraping
│   └── alerts.yml               # regras de alerta
├── infra/                       # scripts Terraform
├── docs/fluxo-devops.md         # fluxograma do pipeline
├── docker-compose.yml           # orquestração local
├── render.yaml                  # blueprint da plataforma de execução
├── Dockerfile                   # imagem multi-stage
├── eslint.config.js
├── tsconfig.json
└── package.json
```

---

Felipe Rezende Araujo — GraduPUCRS Online, DevOps na Prática.
