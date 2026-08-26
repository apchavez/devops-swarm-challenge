# Arquitectura real vs. reto.png

Este documento muestra la arquitectura **tal como quedó implementada** en este repo, en el mismo formato del diagrama original del reto (`reto.png`), señalando explícitamente dónde se sustituyó una herramienta comercial por un equivalente open-source y por qué.

## Diagrama

```mermaid
flowchart TB
    subgraph CLOUD["☁️ Cloud (GitHub, apchavez/devops-swarm-challenge — público)"]
        DEV["👤 Developer"] -->|PR + 1 aprobación| REPO["📦 GitHub repo\nbranch protection:\nsin force-push, sin borrado,\n4 status checks + PR requeridos\nbypass admin disponible"]
        REPO --> GHA["⚙️ GitHub Actions\n(runner ubuntu-latest)"]

        subgraph CI["ci.yml"]
            BUILD["Build Code\n(build-test)"]
            UT["Unit Test\npytest"]
            CA["Code analysis\nruff lint+format"]
            SEMGREP["Fluid Attacks equivalente\nSemgrep SAST → SARIF"]
            SONAR["Quality Gate Sonar\nSonarCloud"]
            GHCR["JFrog equivalente\nGitHub Container Registry\n(ghcr.io)"]
            COSIGN["🔏 cosign sign\nkeyless (Sigstore OIDC)"]
            BUILD --> UT --> CA
            CA --> SEMGREP
            CA --> SONAR
            SEMGREP --> GHCR
            SONAR --> GHCR
            GHCR --> COSIGN
        end

        GHA --> CI
        CODEQL["🛡️ GitHub Advanced Security\ncodeql.yml (CodeQL real)"]
        REPO --> CODEQL
        CODEQL -->|SARIF| SECURITY[("🔒 Security tab\nCodeQL + Semgrep + Dependabot")]
        SEMGREP -->|SARIF| SECURITY

        SECRETS[("🔑 GitHub Secrets\nSONAR_TOKEN")] -.-> CI
        DEPENDABOT["🤖 Dependabot\npip / github-actions / docker\nsemanal, cooldown 7d"] -->|PRs de versión\n+ alerts de vulnerabilidad| SECURITY

        COSIGN --> APPROVE{{"✋ Approve\nGitHub Environments\ndev/sit/qa\nrequired_reviewers real"}}
    end

    subgraph ONPREM["🏠 Onpremise (misma máquina, runner label: onprem)"]
        RUNNER["🖥️ Self-hosted runner"]
        VERIFY["🔏 cosign verify\n(repetido en dev/sit/qa,\nantes de cada pull)"]
        SWARM["🐳 Docker Swarm\n(1 nodo simula DMGR1/DMGR2)"]
        RUNNER --> G1{{"✋ approval\nenvironment dev"}}
        G1 --> VERIFY --> SWARM
        SWARM --> S_DEV["stack DEV\npuerto 8081, 1 réplica"]
        S_DEV --> SMOKE_DEV{"🩺 smoke test\ncurl /health"}
        SMOKE_DEV -->|ok| G2{{"✋ approval\nenvironment sit"}}
        SMOKE_DEV -->|falla 60s| RB1["⏪ docker service rollback\n(dev)"]
        RB1 -.->|job falla| RUNNER
        G2 --> S_SIT["stack SIT\npuerto 8082, 1 réplica"]
        S_SIT --> SMOKE_SIT{"🩺 smoke test\ncurl /health"}
        SMOKE_SIT -->|ok| G3{{"✋ approval\nenvironment qa"}}
        SMOKE_SIT -->|falla 60s| RB2["⏪ docker service rollback\n(sit)"]
        RB2 -.->|job falla| RUNNER
        G3 --> S_QA["stack QA\npuerto 8083, 2 réplicas"]
        S_QA --> SMOKE_QA{"🩺 smoke test\ncurl /health"}
        SMOKE_QA -->|falla 60s| RB3["⏪ docker service rollback\n(qa)"]
        RB3 -.->|job falla| RUNNER
        RECOVER["recover-swarm.ps1\nScheduled Task at logon\nself-healing tras reboot"] -.-> SWARM
    end

    APPROVE -->|workflow_dispatch\ndeploy.yml| RUNNER

    style SEMGREP fill:#fff3cd,stroke:#d39e00
    style GHCR fill:#fff3cd,stroke:#d39e00
    style SECURITY fill:#d1e7dd,stroke:#0f5132
    style DEPENDABOT fill:#d1e7dd,stroke:#0f5132
    style COSIGN fill:#d1e7dd,stroke:#0f5132
    style VERIFY fill:#d1e7dd,stroke:#0f5132
```

> Los bloques en amarillo (`Semgrep`, `GHCR`) son sustituciones documentadas de herramientas comerciales (`Fluid Attacks`, `JFrog Artifactory`) que no fue posible contratar/usar en una cuenta personal — ver el detalle de cada una en `README.md`. Todo lo demás (GitHub Advanced Security, Quality Gate Sonar, el gate de aprobación por ambiente, el runner self-hosted, Docker Swarm) es la herramienta real, no un simulacro.

## Diferencias frente al diagrama original (`reto.png`)

| Elemento | reto.png | Este repo | Motivo |
|---|---|---|---|
| Fluid Attacks | Herramienta comercial | Semgrep (SAST), sube SARIF real a Security | Fluid Attacks exige contrato con mínimo de 10 "autores" facturables, sin tier gratuito |
| JFrog Artifactory | Registry comercial | GitHub Container Registry (ghcr.io) | El trial de JFrog rechaza signup con correo personal (exige dominio corporativo) |
| DMGR1 / DMGR2 | Dos managers Swarm físicos separados | Un solo nodo Swarm en la misma máquina | Simulación de un solo desarrollador; el patrón `docker stack deploy` es idéntico a un swarm multi-nodo real |
| Todo lo demás | — | Igual | GitHub Advanced Security, Quality Gate Sonar, GitHub Secrets, self-hosted runner, gate de aprobación por ambiente y flujo DEV→SIT→QA son la implementación real, no una simulación |

## Capas de seguridad agregadas (no estaban en el diagrama original)

Estas se descubrieron y cerraron durante una auditoría posterior al mapeo inicial, y refuerzan el pipeline sin cambiar su arquitectura:

- Branch protection en `main` (sin force-push, sin borrado, checks de CI requeridos).
- Dependabot: alertas de vulnerabilidad + actualizaciones automáticas de seguridad + PRs de versión (pip, github-actions, docker) con cooldown de 7 días.
- Las 19 referencias `uses: acción@vX` de los workflows pineadas a SHA de commit exacto (mitiga supply-chain attacks tipo repointing de tags, como el caso real de `trivy-action`).
- Contenedor de la app corriendo como usuario no-root.
