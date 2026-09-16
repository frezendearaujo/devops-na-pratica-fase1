# Fluxo DevOps implementado

Diagrama de todas as etapas, do commit ao monitoramento em producao. Para gerar
a imagem do fluxograma, cole o bloco abaixo em <https://mermaid.live> e exporte
em PNG.

```mermaid
flowchart TD
    subgraph dev["Desenvolvimento"]
        A["Commit em branch curta"] --> B["Pull request para main"]
    end

    subgraph ci["Integracao continua"]
        C1["lint<br/>ESLint, Prettier,<br/>tsc, ShellCheck"]
        C2["test<br/>24 casos<br/>Vitest e Supertest"]
        C3["security<br/>npm audit"]
        C4["terraform<br/>fmt, init, validate"]
        C5["CodeQL<br/>SAST"]
    end

    subgraph art["Artefato"]
        D["build<br/>imagem multi-stage"] --> E["push ghcr.io<br/>tag sha e latest"]
        E --> F{"Trivy<br/>HIGH ou CRITICAL?"}
    end

    subgraph cd["Entrega continua"]
        G["deploy-staging<br/>API do Render<br/>com a tag exata"] --> H{"smoke test<br/>8 verificacoes"}
        H -->|aprovado| I["Aprovacao manual<br/>GitHub Environments"]
        I --> J["deploy-production<br/>mesma imagem"]
        J --> K{"smoke test<br/>em producao"}
    end

    subgraph ops["Operacao"]
        L["/metrics<br/>Prometheus"]
        M["Logs e metricas<br/>do Render"]
        N["uptime.yml<br/>sonda a cada 6h"]
        O["Dependabot<br/>semanal"]
    end

    B --> C1 & C2 & C3 & C4 & C5
    C1 & C2 & C3 --> D
    F -->|limpo| G
    F -->|vulneravel| X1["Pipeline falha<br/>imagem nao sobe"]
    H -->|reprovado| X2["Rollback<br/>scripts/rollback.sh"]
    K -->|aprovado| L & M & N
    K -->|reprovado| X2
    X2 --> G
    O --> B

    classDef falha fill:#fde2e1,stroke:#c0392b,color:#7b241c
    classDef porta fill:#fdf2d0,stroke:#b7950b,color:#7d6608
    classDef ok fill:#e8f6ef,stroke:#1e8449,color:#145a32
    class X1,X2 falha
    class F,H,K,I porta
    class E,J ok
```

## Etapas em texto

| #   | Etapa                  | Gatilho                         | Resultado                                                |
| --- | ---------------------- | ------------------------------- | -------------------------------------------------------- |
| 1   | Commit e pull request  | trabalho em branch curta        | nenhuma alteracao entra na main sem pipeline             |
| 2   | `lint`                 | push e pull request             | ESLint, Prettier, `tsc --noEmit` e ShellCheck            |
| 3   | `test`                 | push e pull request             | 24 casos de unidade e integracao                         |
| 4   | `security`             | push e pull request             | `npm audit --audit-level=high`                           |
| 5   | `terraform`            | push e pull request             | `fmt -check`, `init -backend=false`, `validate`          |
| 6   | CodeQL                 | push, pull request e semanal    | SAST com a suite security-and-quality                    |
| 7   | `build`                | depende de 2, 3 e 4             | imagem multi-stage publicada em `ghcr.io` com tag do sha |
| 8   | Trivy                  | dentro do `build`               | falha em vulnerabilidade HIGH ou CRITICAL corrigivel     |
| 9   | `deploy-staging`       | push na main                    | API do Render recebe a tag exata da imagem               |
| 10  | Smoke test em staging  | apos o deploy                   | 8 verificacoes contra a URL publica                      |
| 11  | Aprovacao manual       | ambiente `production` protegido | job pendente ate o revisor autorizar                     |
| 12  | `deploy-production`    | apos a aprovacao                | mesma imagem promovida, sem rebuild                      |
| 13  | Smoke test em producao | apos o deploy                   | confirma a versao no ar                                  |
| 14  | Monitoramento          | continuo                        | `/metrics`, painel do Render e `uptime.yml`              |
| 15  | Rollback               | sob demanda                     | `scripts/rollback.sh` aponta a tag anterior              |
