# devops-swarm-challenge

Proyecto personal de preparación para un puesto de **Desarrollador DevOps**. No forma parte del portafolio público — ver `[[project-challenge-repos]]`.

El código funcional es intencionalmente trivial (un "hola mundo" en FastAPI, `/health` y `/hello`). El objetivo de este repo **no es la aplicación**, es reproducir a escala reducida un flujo de trabajo típico de CI/CD con aprobación manual y despliegue en Docker Swarm, para entender cada pieza de primera mano.

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
| GitHub Advanced Security | `.github/workflows/codeql.yml` (CodeQL). **Nota:** GHAS (code scanning + secret scanning) es gratis en repos públicos pero requiere plan pago en privados de cuentas personales (confirmado antes con un 403/422 al intentarlo); por eso el repo se hizo público el 2026-08-21, y desde entonces el SARIF sube al tab Security normalmente, igual que en una organización con licencia GHAS. |
| **Fluid Attacks** | Sustituido por **Semgrep** (SAST) como equivalente open-source — Fluid Attacks es un producto comercial de pentesting/SAST-as-a-service con mínimo de 10 "autores" facturables y sin tier gratuito; Semgrep cubre la misma categoría de control (análisis estático de seguridad en el pipeline) sin requerir licencia. Documentado aquí para no fingir una herramienta que no usé. Job `fluid-attacks-equivalent` en `ci.yml` genera SARIF (`semgrep scan --sarif`) y lo sube al tab Security igual que CodeQL, para que los hallazgos sean visibles de verdad y no solo un pass/fail en el log. |
| Quality Gate Sonar | job `quality-gate-sonar` en `ci.yml`, SonarCloud (mismo motor que SonarQube, hosteado) |
| **JFrog Artifactory** | Sustituido por **GitHub Container Registry** (`ghcr.io`) — job `publish-ghcr` en `ci.yml`. **Limitación real encontrada:** el trial de 14 días de JFrog (ya no existe un free-tier permanente, solo Pro pago o trial) rechazó el signup con Gmail personal ("Please use a different company email" — exige correo corporativo/de dominio propio). En vez de fingir la cuenta con un dominio falso, se documenta la limitación y se usa GHCR. **Alternativas open-source evaluadas y descartadas:** (1) self-hostear **Artifactory OSS** (Apache 2.0, `releases-docker.jfrog.io/jfrog/artifactory-oss`) en la misma máquina del runner `onprem` — funciona, pero entonces Artifactory pasaría a representar el bloque **Onpremise** del diagrama en vez de **Cloud**, donde está dibujado (recibe la imagen directo del job "Build Code", que corre en un runner de GitHub hosteado en la nube); (2) la misma opción pero exponiéndola a internet vía túnel (ngrok/Cloudflare Tunnel) para que sí sea alcanzable desde el job cloud y respete la posición del diagrama — descartada porque abre la red local a internet sin ganancia real de aprendizaje: en un entorno corporativo real el acceso de CI a JFrog sería por red corporativa/VPN, no por un túnel personal, así que simular eso no reproduce el escenario real. Con GHCR el patrón arquitectónico del diagrama queda igual de fiel sin ese riesgo: build en la nube → push a un registry real en la nube → el runner onprem hace `docker pull` de ahí para desplegar (ver `deploy.yml`). Con correo corporativo, JFrog real sería un reemplazo directo de este mismo patrón, sin cambios de arquitectura. |
| GitHub Secret | GitHub Actions Secrets del repo (`SONAR_TOKEN`); GHCR usa el `GITHUB_TOKEN` automático, sin secreto adicional |
| Approve (developer) | GitHub Environments (`dev`, `sit`, `qa`) con la protection rule **"required reviewers"** habilitada de verdad. **Nota:** esta regla es gratis solo en repos públicos de cuentas personales (en privados exige plan pago/Team-Enterprise, confirmado con un 422 al intentarlo antes de hacer el repo público); por eso el repo se publicó el 2026-08-21. Cada deploy (`workflow_dispatch`) queda pausado hasta que se aprueba desde el botón "Review deployments" en cada entorno, igual que en un flujo corporativo real. |
| Self-hosted runner | runner registrado en esta misma máquina con la etiqueta `onprem` (ver sección abajo) |
| DMGR1 / DMGR2 | El swarm que sirve `dev`/`sit`/`qa` de verdad corre en un solo nodo (esta máquina). **Verificado por separado (2026-08-24)** que el patrón sí escala a multi-nodo real: se levantó un swarm aislado de prueba con dos contenedores Docker-in-Docker (`docker:dind`), cada uno con su propio `dockerd`, unidos como dos managers reales (`docker node ls` mostró `dmgr1` Leader + `dmgr2` Reachable), y se desplegó el `stack/base.yml` + `stack/qa.yml` de este mismo repo sin cambios — Swarm distribuyó las 2 réplicas una en cada nodo (`docker service ps` confirmó `app.1` en `dmgr2`, `app.2` en `dmgr1`), y la app respondió `{"status":"ok"}` real dentro del contenedor. No se tocó el swarm que sirve los ambientes reales — se armó y se destruyó aparte, precisamente para no arriesgar `dev`/`sit`/`qa` con una prueba de infraestructura. En un entorno real esto sería infraestructura física con nodos/VMs separados, sin necesidad de Docker-in-Docker. |
| DEV / SIT / QA | `stack/dev.yml`, `stack/sit.yml`, `stack/qa.yml` — overrides sobre `stack/base.yml`, cada uno con su puerto y réplicas |

## Gaps de seguridad/hardening (fuera del diagrama, pero relevantes)

Al auditar el repo completo aparte del mapeo 1:1 con `reto.png`, se encontraron y resolvieron dos huecos, y uno queda pendiente a propósito:

- ✅ **Resuelto (2026-08-22):** Semgrep corría en CI pero no publicaba hallazgos en ningún lado visible (solo pass/fail en el log de Actions), a diferencia de CodeQL que sí sube a Security. Se agregó generación de SARIF + `github/codeql-action/upload-sarif` en el job `fluid-attacks-equivalent`.
- ✅ **Resuelto (2026-08-22):** la rama `main` no tenía branch protection (permitía force-push y borrado de la rama). Se habilitó protección: sin force-push, sin borrado de rama, y con los checks de CI (`Build Code + Unit Test + Code analysis`, `Quality Gate Sonar`, `Fluid Attacks equivalent (Semgrep SAST)`, `Analyze (python)`) como status checks requeridos. En un principio se dejó sin exigir pull request (el flujo era push directo a `main`, sin PRs) — ver más abajo por qué esto cambió el 2026-08-24.
- ✅ **Resuelto (2026-08-22):** Dependabot security updates / vulnerability alerts estaban deshabilitados. Se habilitaron `vulnerability-alerts` y `automated-security-fixes` vía API, y se agregó `.github/dependabot.yml` (ecosistemas `pip`, `github-actions`, `docker`, chequeo semanal, `cooldown` de 7 días) para actualizaciones de versión además de las alertas de seguridad. Apenas se habilitó, Dependabot encontró de inmediato `pytest==8.3.2` vulnerable (CVE-2025-71176, manejo inseguro de `/tmp`) — se subió a `9.0.3`.
- ✅ **Resuelto (2026-08-22):** Semgrep (una vez subiendo SARIF de verdad al Security tab) reportó las 19 referencias `uses: acción@vX` de los workflows como tags mutables (`github-actions-mutable-action-tag`, riesgo de supply-chain — un mantenedor comprometido puede re-apuntar un tag, como pasó con `trivy-action` y `kics-github-action`). Se pinearon todas a su SHA de commit exacto, con la versión como comentario (`uses: actions/checkout@11d5960a... # v4.4.0`) para mantener legibilidad. Dependabot (`github-actions` ecosystem) sigue pudiendo abrir PRs de actualización aunque estén pineadas a SHA.
- ✅ **Resuelto (2026-08-22):** el deploy no verificaba que el servicio recién desplegado quedara sano; un `docker stack deploy` "exitoso" solo confirma que Swarm aceptó la definición, no que el contenedor levantó bien. Se agregó un smoke test (`curl /health` con reintentos hasta 60s) al final de cada job de `deploy.yml` (dev/sit/qa) — si el servicio no responde a tiempo, el job falla ahí mismo y no se promueve al siguiente ambiente con una imagen rota.
- ✅ **Resuelto (2026-08-22):** el smoke test fallaba el job pero dejaba el servicio roto corriendo en Swarm hasta que alguien lo arreglara a mano. Se agregó `docker service rollback devops-swarm-challenge-<env>_app` justo antes de fallar el job, para que el ambiente vuelva solo a la última versión sana en vez de quedar caído.
- ✅ **Resuelto (2026-08-22), encontrado con una prueba real, no solo revisión de código:** se desplegó a propósito una imagen rota (`ghcr.io/apchavez/devops-swarm-challenge:broken-test`, sin servidor arrancando) a `dev` para probar el rollback del punto anterior. Dos hallazgos:
  1. **Docker Swarm ya hace rollback solo** — `stack/base.yml` define `update_config.failure_action: rollback`; Swarm detectó el healthcheck fallido, mató la réplica rota y revirtió a la versión anterior en ~40s sin que el step de GitHub Actions interviniera.
  2. **Pero el smoke test de GitHub Actions dio un falso positivo**: con `order: start-first`, la réplica vieja (sana) sigue respondiendo en el puerto público mientras la nueva (rota) intenta arrancar. El `curl /health` pegó a la réplica vieja y el job reportó éxito en GitHub aunque la imagen pedida nunca llegó a funcionar — un evaluador que solo mirara el check verde de Actions no se habría enterado.
  
  Se corrigió el step (ahora `Verify rollout`) para que primero consulte `docker service inspect --format '{{.UpdateStatus.State}}'` — la fuente de verdad real de Swarm — y solo confirme con `curl /health` cuando el estado es `completed` o vacío. Si Swarm ya reporta `rollback_completed`/`rollback_paused`, el job falla de inmediato con ese motivo en vez de dar un falso "healthy". El `docker service rollback` manual queda como red de seguridad para el caso (menos común) de que el rollout se quede atascado sin que Swarm decida nada por su cuenta.
- ✅ **Resuelto (2026-08-22):** ningún fallo de CI/Deploy/CodeQL generaba una alerta activa — había que entrar a la pestaña Actions para enterarse. Es una preferencia de cuenta, no de repo, y GitHub no la expone por API (confirmado contra la documentación oficial de las APIs `notifications` y `users` — no existe endpoint para esto), así que no se pudo verificar ni activar por código. Se confirmó manualmente que "Send notifications for failed workflows only" ya está activo en [github.com/settings/notifications](https://github.com/settings/notifications), sección Actions (ver `docs/PREREQUISITOS.md` sección 5). No requirió workflow ni secrets nuevos.

## Flujo de PR obligatorio (2026-08-24)

`main` ahora exige pull request con al menos 1 aprobación antes de mergear (`required_pull_request_reviews`, `dismiss_stale_reviews: true`), agregado para reflejar un flujo de equipo real — antes se dejó fuera a propósito porque el flujo era push directo sin PRs. **Limitación real de cuenta personal:** al ser el único colaborador, GitHub no permite auto-aprobar la propia PR; la única forma de mergear sin un segundo humano es el override de administrador ("Merge without waiting for requirements to be met"), disponible porque `enforce_admins` sigue en `false`. Verificado en vivo: un push directo a `main` después de activar la regla mostró el mensaje real de GitHub `Bypassed rule violations: Changes must be made through a pull request`, confirmando que la regla está activa y que el bypass de admin sigue funcionando como se esperaba.

## Firma de imagen (cosign)

Después de publicar la imagen en `ci.yml` (job `publish-ghcr`), se firma con **cosign** en modo *keyless* (Sigstore, vía OIDC de GitHub Actions con `id-token: write` — sin llaves privadas que gestionar ni secrets nuevos). En `deploy.yml`, cada ambiente corre `cosign verify` contra el `certificate-identity` (`.../workflows/ci.yml@refs/heads/main`) y el `certificate-oidc-issuer` (`token.actions.githubusercontent.com`) antes de hacer `docker pull` — si la imagen no fue firmada por ese workflow exacto en esa rama exacta, el job falla ahí, antes de tocar Swarm. Cierra el círculo de supply-chain que empezó con el pin de SHAs de las Actions: ahora también se verifica que la imagen que se despliega salió realmente de este pipeline.

**Limitación real encontrada:** la action oficial `sigstore/cosign-installer` falla en `deploy.yml` porque ese job corre en el runner self-hosted, que es **Windows** — la action intenta enrutar internamente por WSL (`execvpe(/bin/bash) failed: No such file or directory`) sin importar el shell configurado en el job, y esta máquina no tiene WSL instalado (confirmado con un run real fallido el 2026-08-23). En `ci.yml` sí funciona porque ese job corre en `ubuntu-latest`. Se sustituyó por una descarga directa del binario `cosign-windows-amd64.exe` (versión fija v3.1.3, verificada contra el checksum publicado por el proyecto) en vez de depender de la action.

## Observabilidad

La app expone `/metrics` (formato Prometheus) vía `prometheus-fastapi-instrumentator` — latencia y conteo de requests por endpoint/status code. **Limitación real:** `prometheus-fastapi-instrumentator==8.1.0` (última versión) exige `starlette>=1.0.0`, incompatible con el `fastapi==0.115.0` ya pineado en este repo (que fija `starlette<0.39.0`); se usó `7.1.0`, la última versión de la librería compatible con esa versión de FastAPI.

Además hay un stack de monitoreo real desplegado por separado (`stack/monitoring.yml`, no forma parte de `ci.yml`/`deploy.yml`): **Prometheus** scrapea los `/metrics` de `dev`/`sit`/`qa` cada 15s vía `host.docker.internal`, y **Grafana** viene con ese Prometheus provisionado automáticamente como datasource (`stack/grafana-datasources.yml`, sin configurarlo a mano en la UI). No toca las redes ni los servicios de `dev`/`sit`/`qa` — es un stack aparte, se puede tirar con `docker stack rm monitoring` sin afectar nada más.

```bash
docker stack deploy -c stack/monitoring.yml monitoring
# Prometheus: http://localhost:9090  (Status -> Targets para ver los 3 scrape jobs)
# Grafana:    http://localhost:3000  (admin / admin, cambiar en el primer login)
```

## Retención de imágenes en GHCR

Cada push a `main` sube una imagen nueva a `ghcr.io` con dos tags: el SHA del commit y `latest` (ver job `publish-ghcr` en `ci.yml`). El SHA nunca se reutiliza, así que el paquete crece un tag por commit para siempre — gratis en repos públicos, pero desordenado. `.github/workflows/cleanup-ghcr.yml` corre semanalmente (y por `workflow_dispatch`) y borra versiones viejas del paquete `devops-swarm-challenge`, conservando las últimas 10 y protegiendo explícitamente la que tiene el tag `latest`.

## Estructura

```
app/            FastAPI hola-mundo, expone /health, /hello y /metrics
tests/          pytest
stack/          docker-compose/stack files para Swarm (base + dev/sit/qa) + script de deploy
docs/           documentación de sustentación (arquitectura, funcional, prerequisitos, demo)
.github/workflows/
  ci.yml            Build -> Test -> Lint -> Semgrep -> Sonar -> push a ghcr.io -> cosign sign
  codeql.yml        GitHub Advanced Security
  deploy.yml        Self-hosted runner: DEV -> SIT -> QA, cosign verify + aprobación manual por ambiente
  cleanup-ghcr.yml  Borra versiones viejas del paquete en ghcr.io (semanal)
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
- El Swarm que sirve `dev`/`sit`/`qa` es de un solo nodo simulando DMGR1/DMGR2 en esta misma máquina; en un entorno real habría nodos físicos/VMs separados. El patrón multi-nodo sí se verificó por separado con un swarm de prueba aislado (ver tabla de mapeo, fila DMGR1/DMGR2) — no es una suposición sin probar.
