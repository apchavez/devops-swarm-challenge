# Documentación funcional

## Objetivo del repo

Este repositorio **no busca demostrar una aplicación** — el código funcional es intencionalmente trivial (un "hola mundo" en FastAPI con dos endpoints: `/health` y `/hello`). El objetivo es reproducir, a escala reducida pero con herramientas reales, un flujo de CI/CD típico de un puesto de Desarrollador DevOps, de modo que cada pieza del pipeline (compilación, pruebas, análisis de seguridad, gates de calidad, aprobación manual, despliegue en Docker Swarm por ambientes) se entienda de primera mano antes de encontrarla en un entorno real.

## ¿Qué demuestra este repo?

1. **Pipeline de CI completo con quality gates reales**: cada commit a `main` dispara compilación, pruebas unitarias, análisis estático de código (lint), dos motores de seguridad estática distintos (CodeQL y Semgrep) y un quality gate de SonarCloud — y solo si todo pasa, se publica una imagen Docker versionada.

2. **Cadena de suministro de software (supply chain) cuidada**: las dependencias (Python y GitHub Actions) están vigiladas por Dependabot con alertas de vulnerabilidad automáticas, las propias GitHub Actions usadas en los workflows están pineadas a un commit SHA exacto (no a un tag mutable, para que un mantenedor externo no pueda inyectar código simplemente re-apuntando una versión), y la imagen Docker publicada se firma con **cosign** (keyless, Sigstore OIDC) y esa firma se verifica antes de cada despliegue — si alguien sube o modifica una imagen sin pasar por este pipeline, `deploy.yml` la rechaza.

3. **Separación real Cloud / Onpremise con aprobación manual entre ambas**: el build corre en runners de GitHub hosteados en la nube; el despliegue corre en un runner self-hosted registrado en la máquina local, y cada paso de promoción (DEV → SIT → QA) requiere una aprobación manual real configurada como `required_reviewers` en GitHub Environments — no un `if` en el código ni un botón simulado.

4. **Orquestación de contenedores con Docker Swarm**: la imagen se despliega como un `docker stack` distinto por ambiente, con réplicas y puertos diferenciados, simulando el patrón de dos managers Swarm (DMGR1/DMGR2) del diagrama original con un solo nodo físico.

5. **Observabilidad real, no solo un endpoint**: la app expone `/metrics`, y un stack de Prometheus + Grafana desplegado por separado los scrapea y los muestra en un dashboard — verificable con los 3 targets en estado `up` y el datasource ya conectado.

## Flujo funcional de punta a punta

```
1. Un desarrollador abre un pull request contra `main` (requerido desde
   2026-08-24: `main` exige PR + 1 aprobación para mergear; el único
   colaborador puede mergear igual vía el override de administrador, ver
   README). El push directo solo lo puede hacer un admin saltándose la regla.
2. GitHub Actions (ci.yml) corre en paralelo/secuencia (tanto en el PR como
   al mergear a main):
     - build-test:        instala dependencias, corre ruff (lint) y pytest.
     - fluid-attacks-equivalent: corre Semgrep, sube hallazgos SARIF al tab Security.
     - quality-gate-sonar: corre pytest con cobertura y la envía a SonarCloud.
   codeql.yml corre en paralelo (push, PR, y cron semanal) y sube CodeQL a Security.
3. Si build-test + quality-gate-sonar + fluid-attacks-equivalent pasan, y el
   evento fue push directo a main (no PR), publish-ghcr construye la imagen
   Docker, la sube a ghcr.io con dos tags (el SHA del commit y `latest`), y
   la firma con **cosign** en modo keyless (Sigstore OIDC) — sin llaves que
   gestionar ni secrets nuevos.
4. Dependabot corre en paralelo, de forma independiente al push: revisa
   dependencias Python, Docker y GitHub Actions cada semana y abre PRs o
   alertas de seguridad si encuentra algo vulnerable.
5. Un desarrollador dispara manualmente el workflow `deploy.yml`
   (workflow_dispatch), indicando opcionalmente qué tag de imagen desplegar.
6. deploy.yml corre en el runner self-hosted (onprem) y pasa por 3 jobs
   encadenados con `needs`: deploy-dev -> deploy-sit -> deploy-qa.
   Cada uno pertenece a un GitHub Environment (dev/sit/qa) con
   required_reviewers: el job se queda "Waiting" hasta que alguien lo aprueba
   desde la pestaña Actions -> Review deployments.
7. Cada job aprobado primero corre `cosign verify` contra la imagen
   solicitada — si no fue firmada por este mismo workflow en `main`, el job
   falla ahí, antes de tocar Swarm. Si la firma es válida, hace `docker pull`
   desde ghcr.io y ejecuta `stack/deploy.sh <ambiente>`, que llama a
   `docker stack deploy` combinando `stack/base.yml` (config común) con el
   override del ambiente (`stack/dev.yml`, `sit.yml` o `qa.yml`).
8. Inmediatamente después de cada `docker stack deploy`, el job verifica el
   rollout consultando `docker service inspect --format
   '{{.UpdateStatus.State}}'` (la fuente de verdad real de Swarm) y solo
   confirma con `curl /health` cuando ese estado es `completed` o vacío. Si
   Swarm ya detectó el fallo y reporta `rollback_completed`/`rollback_paused`
   (porque `update_config.failure_action: rollback` en `stack/base.yml` ya
   actuó), el job falla de inmediato con ese motivo. Si el rollout se queda
   atascado sin que Swarm decida nada, el job fuerza `docker service
   rollback` como red de seguridad antes de fallar. **Por qué no basta con
   un `curl` simple:** con `update_config.order: start-first`, la réplica
   vieja (sana) sigue respondiendo en el puerto público mientras la nueva
   intenta arrancar — un `curl` ingenuo puede reportar "healthy" pegándole
   a la instancia vieja aunque la imagen nueva nunca haya funcionado
   (confirmado desplegando una imagen rota a propósito el 2026-08-22, ver
   `README.md`).
9. La app queda corriendo en Docker Swarm, expuesta en un puerto distinto
   por ambiente (8081 dev, 8082 sit, 8083 qa), verificable con
   `curl http://localhost:<puerto>/health`.
```

## Roles involucrados (mapeo a reto.png)

| Rol en el diagrama | Quién lo cumple aquí |
|---|---|
| Developers (commit) | Quien hace push a `main` |
| Developer (approves) | Quien aprueba el `required_reviewers` en cada Environment (dev/sit/qa) |
| Pipeline automatizado | GitHub Actions (`ci.yml`, `codeql.yml`, `deploy.yml`) |
| Infraestructura onprem | Runner self-hosted + Docker Swarm en la misma máquina |

## Observabilidad

La app expone `/metrics` en formato Prometheus (vía `prometheus-fastapi-instrumentator`): latencia y conteo de requests por endpoint y código de estado. Además hay un stack de Prometheus + Grafana real desplegado por separado (`stack/monitoring.yml`) que scrapea esos endpoints y trae el datasource ya provisionado en Grafana — ver `README.md`, sección Observabilidad, para los comandos.

## Qué NO es este repo

- No es una demo de arquitectura de aplicación de negocio.
- No usa Fluid Attacks ni JFrog Artifactory reales — usa Semgrep y GitHub Container Registry como equivalentes open-source, documentado explícitamente en `README.md` y `docs/ARQUITECTURA.md`, por limitaciones reales de acceso (no por preferencia).
- El Swarm es de un solo nodo simulando DMGR1/DMGR2; en un entorno real habría nodos físicos/VMs separados.
