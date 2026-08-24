# DevOps na Prática — Fase 1

Repositório da primeira entrega da disciplina **DevOps na Prática** (GraduPUCRS Online).

A aplicação é uma **API REST de gerenciamento de tarefas** escrita em Node.js com TypeScript. Ela
não é o objetivo do trabalho: serve de veículo para exercitar o que a fase pede — um pipeline de
integração contínua com testes automatizados e scripts de infraestrutura como código.

## Sumário

- [Aplicação](#aplicação)
- [Como rodar localmente](#como-rodar-localmente)
- [Endpoints](#endpoints)
- [Docker](#docker)
- [Pipeline de Integração Contínua](#pipeline-de-integração-contínua)
- [Infraestrutura como Código](#infraestrutura-como-código)
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

| Método | Rota                  | Descrição                       | Respostas    |
| ------ | --------------------- | ------------------------------- | ------------ |
| `GET`  | `/health`             | Verificação de saúde do serviço | `200`        |
| `GET`  | `/tasks`              | Lista todas as tarefas          | `200`        |
| `POST` | `/tasks`              | Cria uma tarefa                 | `201`, `400` |
| `POST` | `/tasks/:id/complete` | Marca a tarefa como concluída   | `200`, `404` |

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

```bash
docker build -t tasks-api .
docker run -d -p 3000:3000 --name tasks-api tasks-api
curl http://localhost:3000/health
```

## Pipeline de Integração Contínua

Definido em [`.github/workflows/ci.yml`](.github/workflows/ci.yml) e executado no GitHub Actions.

### Gatilhos

- `push` na branch `main`
- `pull_request` com destino à `main`

Ou seja: toda proposta de mudança é validada antes do merge, e a `main` é revalidada depois dele.

### Jobs

| Job         | O que executa                                                | Falha quando                                                                            |
| ----------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| `lint`      | `npm run lint`, `npx prettier --check .`, `npx tsc --noEmit` | Há violação de regra do ESLint, arquivo fora do padrão de formatação ou erro de tipagem |
| `test`      | `npm test`                                                   | Qualquer teste unitário ou de integração falha                                          |
| `build`     | `npm run build` e `docker build`                             | O TypeScript não compila ou a imagem não é construída                                   |
| `terraform` | `fmt -check`, `init -backend=false`, `validate`              | Os arquivos `.tf` estão fora do padrão ou a configuração é inválida                     |

`lint` e `test` rodam em paralelo. `build` declara `needs: [lint, test]` e só começa quando ambos
passam — não faz sentido gastar tempo construindo um artefato a partir de código que não passou na
análise estática nem nos testes. `terraform` é independente dos demais e roda em paralelo.

O job `terraform` usa `init -backend=false` justamente para **não** precisar de credenciais da AWS:
ele baixa o provider e valida sintaxe, tipos e referências, sem tocar em nenhum recurso real.

Nenhum job publica imagem ou faz deploy — entrega contínua é escopo da Fase 2.

### Testes automatizados

| Arquivo                                                          | Nível      | Cobre                                                                                                                |
| ---------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------- |
| [`tests/task-repository.test.ts`](tests/task-repository.test.ts) | Unitário   | Geração de `id` e `createdAt`, status inicial, ordem da listagem, conclusão de tarefa, id inexistente e idempotência |
| [`tests/api.test.ts`](tests/api.test.ts)                         | Integração | Os quatro endpoints via HTTP: caminhos felizes, as cinco regras de validação (`400`) e tarefa inexistente (`404`)    |

Os testes de integração usam Supertest sobre a instância retornada por `createApp()`, sem abrir
porta. Cada caso recebe um `TaskRepository` novo, o que garante isolamento sem estado global.

## Infraestrutura como Código

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

## Estrutura do repositório

```
.
├── .github/workflows/ci.yml   # pipeline de integração contínua
├── src/
│   ├── app.ts                 # criação do app Express e rotas
│   ├── server.ts              # ponto de entrada (listen)
│   ├── task.ts                # tipos do domínio
│   └── task-repository.ts     # armazenamento em memória
├── tests/
│   ├── api.test.ts            # testes de integração
│   └── task-repository.test.ts# testes unitários
├── infra/                     # scripts Terraform
├── Dockerfile                 # imagem multi-stage
├── eslint.config.js
├── tsconfig.json
└── package.json
```

---

Felipe Rezende Araujo — GraduPUCRS Online, DevOps na Prática.
