# devops-swarm-challenge

Reto **privado** de preparación para el puesto de **Desarrollador DevOps** (Cinte Perú / Interbank, inicio 01-sep-2026). No forma parte del portafolio público — ver `[[project-challenge-repos]]`.

El código funcional es intencionalmente trivial (un "hola mundo" en FastAPI, `/health` y `/hello`). El objetivo de este repo **no es la aplicación**, es reproducir a escala reducida el flujo de trabajo real que me describieron en el proceso (ver `reto.png`), para entender cada pieza antes de encontrarla en un entorno real de Interbank.

**Documentación para sustentar:**
- [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md) — diagrama real (Mermaid) y diferencias frente a `reto.png`.
- [`docs/FUNCIONAL.md`](docs/FUNCIONAL.md) — qué hace el pipeline de punta a punta y qué demuestra.
- [`docs/PREREQUISITOS.md`](docs/PREREQUISITOS.md) — cuentas, secrets, Environments, branch protection y setup del runner necesarios para reproducirlo.
- [`docs/DEMO.md`](docs/DEMO.md) — guion paso a paso para mostrarlo en vivo, con preguntas frecuentes anticipadas.

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
| GitHub Advanced Security | `.github/workflows/codeql.yml` (CodeQL). **Nota:** GHAS (code scanning + secret scanning) es gratis en repos públicos pero requiere plan pago en privados de cuentas personales (confirmado antes con un 403/422 al intentarlo); por eso el repo se hizo público el 2026-08-21, y desde entonces el SARIF sube al tab Security normalmente, igual que en Interbank con licencia GHAS. |
| **Fluid Attacks** | Sustituido por **Semgrep** (SAST) como equivalente open-source — Fluid Attacks es un producto comercial de pentesting/SAST-as-a-service con mínimo de 10 "autores" facturables y sin tier gratuito; Semgrep cubre la misma categoría de control (análisis estático de seguridad en el pipeline) sin requerir licencia. Documentado aquí para no fingir una herramienta que no usé. Job `fluid-attacks-equivalent` en `ci.yml` genera SARIF (`semgrep scan --sarif`) y lo sube al tab Security igual que CodeQL, para que los hallazgos sean visibles de verdad y no solo un pass/fail en el log. |
| Quality Gate Sonar | job `quality-gate-sonar` en `ci.yml`, SonarCloud (mismo motor que SonarQube, hosteado) |
| **JFrog Artifactory** | Sustituido por **GitHub Container Registry** (`ghcr.io`) — job `publish-ghcr` en `ci.yml`. **Limitación real encontrada:** el trial de 14 días de JFrog (ya no existe un free-tier permanente, solo Pro pago o trial) rechazó el signup con Gmail personal ("Please use a different company email" — exige correo corporativo/de dominio propio). En vez de fingir la cuenta con un dominio falso, se documenta la limitación y se usa GHCR. **Alternativas open-source evaluadas y descartadas:** (1) self-hostear **Artifactory OSS** (Apache 2.0, `releases-docker.jfrog.io/jfrog/artifactory-oss`) en la misma máquina del runner `onprem` — funciona, pero entonces Artifactory pasaría a representar el bloque **Onpremise** del diagrama en vez de **Cloud**, donde está dibujado (recibe la imagen directo del job "Build Code", que corre en un runner de GitHub hosteado en la nube); (2) la misma opción pero exponiéndola a internet vía túnel (ngrok/Cloudflare Tunnel) para que sí sea alcanzable desde el job cloud y respete la posición del diagrama — descartada porque abre la red local a internet sin ganancia real de aprendizaje: en Interbank el acceso de CI a JFrog será por red corporativa/VPN, no por un túnel personal, así que simular eso no reproduce el escenario real. Con GHCR el patrón arquitectónico del diagrama queda igual de fiel sin ese riesgo: build en la nube → push a un registry real en la nube → el runner onprem hace `docker pull` de ahí para desplegar (ver `deploy.yml`). En Interbank, con correo corporativo, JFrog real sería un reemplazo directo de este mismo patrón, sin cambios de arquitectura. |
| GitHub Secret | GitHub Actions Secrets del repo (`SONAR_TOKEN`); GHCR usa el `GITHUB_TOKEN` automático, sin secreto adicional |
| Approve (developer) | GitHub Environments (`dev`, `sit`, `qa`) con la protection rule **"required reviewers"** habilitada de verdad. **Nota:** esta regla es gratis solo en repos públicos de cuentas personales (en privados exige plan pago/Team-Enterprise, confirmado con un 422 al intentarlo antes de hacer el repo público); por eso el repo se publicó el 2026-08-21. Cada deploy (`workflow_dispatch`) queda pausado hasta que se aprueba desde el botón "Review deployments" en cada entorno, igual que en Interbank. |
| Self-hosted runner | runner registrado en esta misma máquina con la etiqueta `onprem` (ver sección abajo) |
| DMGR1 / DMGR2 | **Docker Swarm** local (`docker swarm init`) — en esta simulación un solo nodo hace de manager, pero el patrón de `docker stack deploy` es el mismo que en un swarm multi-nodo real. En Interbank esto sería infraestructura real con nodos separados. |
| DEV / SIT / QA | `stack/dev.yml`, `stack/sit.yml`, `stack/qa.yml` — overrides sobre `stack/base.yml`, cada uno con su puerto y réplicas |

## Gaps de seguridad/hardening (fuera del diagrama, pero relevantes)

Al auditar el repo completo aparte del mapeo 1:1 con `reto.png`, se encontraron y resolvieron dos huecos, y uno queda pendiente a propósito:

- ✅ **Resuelto (2026-08-22):** Semgrep corría en CI pero no publicaba hallazgos en ningún lado visible (solo pass/fail en el log de Actions), a diferencia de CodeQL que sí sube a Security. Se agregó generación de SARIF + `github/codeql-action/upload-sarif` en el job `fluid-attacks-equivalent`.
- ✅ **Resuelto (2026-08-22):** la rama `main` no tenía branch protection (permitía force-push y borrado de la rama). Se habilitó protección: sin force-push, sin borrado de rama, y con los checks de CI (`Build Code + Unit Test + Code analysis`, `Quality Gate Sonar`, `Fluid Attacks equivalent (Semgrep SAST)`, `Analyze (python)`) como status checks requeridos. **Deliberadamente no se exigió pull request antes de mergear** ni `enforce_admins`, porque el flujo actual de este repo es push directo a `main` (no hay PRs) y el gate de aprobación real del diagrama ya vive en los *environments* (`dev`/`sit`/`qa`) con `required_reviewers`, no en la rama de código. En Interbank, con flujo de equipo, sí correspondería exigir PR + revisión de código antes de merge.
- ✅ **Resuelto (2026-08-22):** Dependabot security updates / vulnerability alerts estaban deshabilitados. Se habilitaron `vulnerability-alerts` y `automated-security-fixes` vía API, y se agregó `.github/dependabot.yml` (ecosistemas `pip`, `github-actions`, `docker`, chequeo semanal, `cooldown` de 7 días) para actualizaciones de versión además de las alertas de seguridad. Apenas se habilitó, Dependabot encontró de inmediato `pytest==8.3.2` vulnerable (CVE-2025-71176, manejo inseguro de `/tmp`) — se subió a `9.0.3`.
- ✅ **Resuelto (2026-08-22):** Semgrep (una vez subiendo SARIF de verdad al Security tab) reportó las 19 referencias `uses: acción@vX` de los workflows como tags mutables (`github-actions-mutable-action-tag`, riesgo de supply-chain — un mantenedor comprometido puede re-apuntar un tag, como pasó con `trivy-action` y `kics-github-action`). Se pinearon todas a su SHA de commit exacto, con la versión como comentario (`uses: actions/checkout@11d5960a... # v4.4.0`) para mantener legibilidad. Dependabot (`github-actions` ecosystem) sigue pudiendo abrir PRs de actualización aunque estén pineadas a SHA.
- ✅ **Resuelto (2026-08-22):** el deploy no verificaba que el servicio recién desplegado quedara sano; un `docker stack deploy` "exitoso" solo confirma que Swarm aceptó la definición, no que el contenedor levantó bien. Se agregó un smoke test (`curl /health` con reintentos hasta 60s) al final de cada job de `deploy.yml` (dev/sit/qa) — si el servicio no responde a tiempo, el job falla ahí mismo y no se promueve al siguiente ambiente con una imagen rota.
- ✅ **Resuelto (2026-08-22):** el smoke test fallaba el job pero dejaba el servicio roto corriendo en Swarm hasta que alguien lo arreglara a mano. Se agregó `docker service rollback devops-swarm-challenge-<env>_app` justo antes de fallar el job, para que el ambiente vuelva solo a la última versión sana en vez de quedar caído.
- ✅ **Resuelto (2026-08-22), encontrado con una prueba real, no solo revisión de código:** se desplegó a propósito una imagen rota (`ghcr.io/apchavez/devops-swarm-challenge:broken-test`, sin servidor arrancando) a `dev` para probar el rollback del punto anterior. Dos hallazgos:
  1. **Docker Swarm ya hace rollback solo** — `stack/base.yml` define `update_config.failure_action: rollback`; Swarm detectó el healthcheck fallido, mató la réplica rota y revirtió a la versión anterior en ~40s sin que el step de GitHub Actions interviniera.
  2. **Pero el smoke test de GitHub Actions dio un falso positivo**: con `order: start-first`, la réplica vieja (sana) sigue respondiendo en el puerto público mientras la nueva (rota) intenta arrancar. El `curl /health` pegó a la réplica vieja y el job reportó éxito en GitHub aunque la imagen pedida nunca llegó a funcionar — un evaluador que solo mirara el check verde de Actions no se habría enterado.
  
  Se corrigió el step (ahora `Verify rollout`) para que primero consulte `docker service inspect --format '{{.UpdateStatus.State}}'` — la fuente de verdad real de Swarm — y solo confirme con `curl /health` cuando el estado es `completed` o vacío. Si Swarm ya reporta `rollback_completed`/`rollback_paused`, el job falla de inmediato con ese motivo en vez de dar un falso "healthy". El `docker service rollback` manual queda como red de seguridad para el caso (menos común) de que el rollout se quede atascado sin que Swarm decida nada por su cuenta.

## Estructura

```
app/            FastAPI hola-mundo
tests/          pytest
stack/          docker-compose/stack files para Swarm (base + dev/sit/qa) + script de deploy
.github/workflows/
  ci.yml        Build -> Test -> Lint -> Semgrep -> Sonar -> push a ghcr.io
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

## Qué NO es este repo

- No es una demo de arquitectura de aplicación — el "hola mundo" es deliberado, el foco es el pipeline.
- No reemplaza Fluid Attacks ni JFrog Artifactory reales — usa equivalentes OSS/gratuitos (Semgrep y GitHub Container Registry respectivamente), documentado explícitamente arriba para no sobrerrepresentar experiencia con las herramientas comerciales exactas. Ambas sustituciones fueron forzadas por limitaciones reales encontradas al intentar usar las originales (ver tabla arriba), no por preferencia.
- El Swarm es de un solo nodo simulando DMGR1/DMGR2 en esta misma máquina; en un entorno real habría nodos físicos/VMs separados.
