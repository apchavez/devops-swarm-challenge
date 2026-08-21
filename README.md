# devops-swarm-challenge

Reto **privado** de preparación para el puesto de **Desarrollador DevOps** (Cinte Perú / Interbank, inicio 01-sep-2026). No forma parte del portafolio público — ver `[[project-challenge-repos]]`.

El código funcional es intencionalmente trivial (un "hola mundo" en FastAPI, `/health` y `/hello`). El objetivo de este repo **no es la aplicación**, es reproducir a escala reducida el flujo de trabajo real que me describieron en el proceso (ver `reto.png`), para entender cada pieza antes de encontrarla en un entorno real de Interbank.

## El flujo objetivo (reto.png)

```
Cloud:
  Developers --commit--> GitHub repo --> GitHub Actions:
    Build Code -> Unit Test (JUnit) -> Code analysis -> GitHub Advanced Security
    -> Fluid Attacks -> Quality Gate Sonar -> JFrog Artifactory
  GitHub Secrets alimenta a GitHub Actions.
  Developer approves --> dispara el flujo hacia Onpremise.

Onpremise:
  self-hosted runner -> DMGR1 / DMGR2 (Docker Swarm managers)
    -> cada uno despliega en DEV -> SIT -> QA
```

## Mapeo diagrama -> este repo

| Paso del diagrama | Dónde vive aquí |
|---|---|
| GitHub repo + commits | este repo (privado) |
| Build Code | `.github/workflows/ci.yml` job `build-test` |
| Unit Test (JUnit) | `pytest` (equivalente Python de JUnit) en `tests/` |
| Code analysis | `ruff` (lint + format) en `ci.yml` |
| GitHub Advanced Security | `.github/workflows/codeql.yml` (CodeQL). **Limitación real encontrada:** GHAS (code scanning + secret scanning) es gratis en repos públicos pero requiere plan pago en repos **privados** de cuentas personales — confirmado con `gh api .../code-scanning/alerts` (403) y un intento de habilitar secret scanning por API (422 "Secret scanning is not available for this repository"). El workflow corre CodeQL igual (`continue-on-error: true` en el upload de SARIF) para demostrar el paso; en Interbank con licencia GHAS esto subiría los hallazgos al tab Security normalmente. |
| **Fluid Attacks** | Sustituido por **Semgrep** (SAST) como equivalente open-source — Fluid Attacks es un producto comercial de pentesting/SAST-as-a-service; Semgrep cubre la misma categoría de control (análisis estático de seguridad en el pipeline) sin requerir licencia. Documentado aquí para no fingir una herramienta que no usé. |
| Quality Gate Sonar | job `quality-gate-sonar` en `ci.yml`, SonarCloud (mismo motor que SonarQube, hosteado) |
| JFrog Artifactory | job `publish-artifactory` en `ci.yml`, usa `jfrog/setup-jfrog-cli` contra una cuenta free-tier real de JFrog Cloud |
| GitHub Secret | GitHub Actions Secrets/Variables del repo (`SONAR_TOKEN`, `JF_ACCESS_TOKEN`, etc.) |
| Approve (developer) | GitHub Environments (`dev`, `sit`, `qa`) creados como destino de deploy. **Limitación real encontrada:** GitHub Free en repos privados no permite la protection rule "required reviewers" (HTTP 422, "Please ensure the billing plan supports the required reviewers protection rule" — es feature de plan pago/Team-Enterprise para repos privados, gratis solo en repos públicos). El gate de aprobación queda entonces implementado con `workflow_dispatch` manual (alguien dispara el deploy a mano) en vez de un botón "Review deployments" automático. En Interbank, con plan de organización, sí se configuraría el required-reviewer real. |
| Self-hosted runner | runner registrado en esta misma máquina con la etiqueta `onprem` (ver sección abajo) |
| DMGR1 / DMGR2 | **Docker Swarm** local (`docker swarm init`) — en esta simulación un solo nodo hace de manager, pero el patrón de `docker stack deploy` es el mismo que en un swarm multi-nodo real. En Interbank esto sería infraestructura real con nodos separados. |
| DEV / SIT / QA | `stack/dev.yml`, `stack/sit.yml`, `stack/qa.yml` — overrides sobre `stack/base.yml`, cada uno con su puerto y réplicas |

## Estructura

```
app/            FastAPI hola-mundo
tests/          pytest
stack/          docker-compose/stack files para Swarm (base + dev/sit/qa) + script de deploy
.github/workflows/
  ci.yml        Build -> Test -> Lint -> Semgrep -> Sonar -> push a Artifactory
  codeql.yml    GitHub Advanced Security
  deploy.yml    Self-hosted runner: DEV -> SIT -> QA con aprobación manual por ambiente
Dockerfile
docker/dev.sh   Corre build/test dentro de un contenedor, sin instalar Python localmente
```

## Cómo correrlo localmente

```bash
# Tests (dentro de Docker, no requiere Python instalado)
./docker/dev.sh test

# Build de la imagen
docker build -t devops-swarm-challenge:local .

# Swarm local (simula DMGR1/DMGR2)
docker swarm init
IMAGE=devops-swarm-challenge:local ./stack/deploy.sh dev
curl http://localhost:8081/hello
```

## Pendiente: activar JFrog Artifactory

Ver [`docs/jfrog-setup.md`](docs/jfrog-setup.md) — requiere crear una cuenta free-tier real de JFrog Cloud (verificación de correo, no automatizable) y configurar `JF_URL`/`JF_DOCKER_REPO`/`JF_ACCESS_TOKEN` como variables/secrets del repo. Hasta entonces, `ci.yml` omite el job `publish-artifactory` y `deploy.yml` construye la imagen localmente en el runner self-hosted.

## Qué NO es este repo

- No es una demo de arquitectura de aplicación — el "hola mundo" es deliberado, el foco es el pipeline.
- No reemplaza Fluid Attacks real ni JFrog Artifactory self-hosted — usa un equivalente OSS (Semgrep) y una cuenta free-tier real de JFrog respectivamente, documentado explícitamente arriba para no sobrerrepresentar experiencia con la herramienta comercial exacta.
- El Swarm es de un solo nodo simulando DMGR1/DMGR2 en esta misma máquina; en un entorno real habría nodos físicos/VMs separados.
