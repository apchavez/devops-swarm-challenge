# Guía de demostración (para sustentar)

Orden sugerido para mostrar el pipeline completo en vivo, de principio a fin, con lo que hay que decir en cada paso.

## 0. Preparación (antes de la sustentación)

- Ten abiertas dos pestañas del navegador: el repo en GitHub (`Code`) y la pestaña `Actions`.
- Verifica que el self-hosted runner esté "Idle" en Settings → Actions → Runners (si está offline, el `deploy.yml` se queda colgado esperando).
- Ten una terminal lista en la máquina donde corre el runner, para mostrar `docker service ls` en vivo.

## 1. Mostrar el diagrama y el mapeo (2-3 min)

Abre `docs/ARQUITECTURA.md` en GitHub (renderiza el diagrama Mermaid automáticamente). Explica:

- Este es el diagrama del reto (`reto.png`) reconstruido con lo que realmente se implementó.
- El único bloque amarillo (Semgrep) es una sustitución documentada de Fluid Attacks — explica en 20 segundos por qué (ver `README.md`, tabla de mapeo).
- Todo lo demás — **incluyendo JFrog Artifactory desde el 2026-08-27** —, GitHub Advanced Security, SonarCloud, el runner self-hosted, Docker Swarm, el gate de aprobación por ambiente, es la herramienta real.

## 2. Disparar el pipeline de CI (5 min)

1. Haz un cambio trivial (ej. un comentario en `app/main.py`) en una rama y abre un **pull request** contra `main` — desde el 2026-08-24 `main` lo exige (PR + 1 aprobación); como eres el único colaborador, mergeas con el override de administrador ("Merge without waiting"), y explicas que en un equipo real ese botón no existiría. También puedes simplemente referenciar el último commit ya existente si no quieres esperar el ciclo completo.
2. En la pestaña **Actions**, abre el run de `CI` en vivo. Señala cada job mientras corre:
   - `Build Code + Unit Test + Code analysis` → build + pytest + ruff.
   - `Fluid Attacks equivalent (Semgrep SAST)` → corre dentro de un contenedor `semgrep/semgrep`, genera SARIF.
   - `Quality Gate Sonar` → cobertura + análisis en SonarCloud.
   - `Build image + push to JFrog Artifactory` → solo corre si los tres anteriores pasan y es push a `main`; el último step firma la imagen con `cosign` (keyless).
3. Cuando termine, ve a la pestaña **Security → Code scanning alerts** del repo y muestra que hay hallazgos de **dos herramientas distintas**: CodeQL y Semgrep, cada uno con su categoría.
4. Muestra **Security → Dependabot** y explica que las alertas de vulnerabilidad de dependencias (Python, Docker, GitHub Actions) llegan aquí automáticamente — puedes mencionar el caso real: Dependabot encontró `pytest` vulnerable (CVE-2025-71176) apenas se habilitó, y se corrigió el mismo día.

## 3. Mostrar el hardening de supply chain (2 min)

Abre `.github/workflows/ci.yml` en GitHub y señala una línea como:

```yaml
uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
```

Explica: no se usa el tag `@v4` (mutable, un mantenedor comprometido podría re-apuntarlo — pasó de verdad con `trivy-action` y `kics-github-action`), sino el commit SHA exacto. Menciona que esto lo encontró el propio Semgrep corriendo sobre el repo (dogfooding: la herramienta de seguridad del pipeline audita al pipeline mismo).

Complementa mostrando el step `cosign verify` en `deploy.yml`: la imagen se firma al publicarse y se verifica antes de cada `docker pull` — si alguien subiera una imagen a mano a JFrog (sin pasar por `ci.yml`), `cosign verify` la rechazaría porque no tendría la firma esperada.

## 4. Disparar el despliegue con aprobación manual (5-8 min, la parte más visual)

1. Ve a **Actions → Deploy → Run workflow**. Déjalo con el tag `latest` o especifica el SHA que acabas de construir.
2. El job `deploy-dev` corre solo, sin pausas — porque el reviewer eres tú y GitHub te lo pide antes de continuar.
3. Cuando `deploy-sit` quede en estado **"Waiting"**, muestra el botón **Review deployments**, apruébalo en vivo, y explica: esto es un `required_reviewers` real configurado en el Environment `sit`, no un `if` en el YAML.
4. Repite para `deploy-qa`.
5. Mientras corre, cambia a la terminal del runner onprem y muestra:
   ```bash
   docker service ls
   ```
   Señala las 3 stacks (`devops-swarm-challenge-dev`, `-sit`, `-qa`) con sus réplicas (1, 1, 2).

## 5. Verificar la app corriendo en cada ambiente (2 min)

```bash
curl http://localhost:8081/health   # dev
curl http://localhost:8082/health   # sit
curl http://localhost:8083/health   # qa
curl http://localhost:8083/hello    # {"message": "Hola mundo"}
curl http://localhost:8083/metrics  # métricas Prometheus reales (latencia, conteo de requests)
```

## 5.5. (Opcional) Mostrar el dashboard de Grafana

```bash
docker stack deploy -c stack/monitoring.yml monitoring
```

Abre `http://localhost:9090/targets` — muestra los 3 jobs (`devops-swarm-dev/sit/qa`) en estado `up`, scrapeando `/metrics` de verdad. Luego `http://localhost:3000` (admin/admin) — el datasource de Prometheus ya está provisionado, sin configurar nada a mano.

## 6. (Opcional, si hay tiempo) Mostrar el rollback en vivo

Esta es la parte que más impresiona porque no es un feature "de manual" — se descubrió probándolo de verdad:

1. Cuenta la historia: al implementar el smoke test, se probó a propósito desplegando una imagen rota (`broken-test`, sin servidor) a `dev`.
2. El hallazgo real: Docker Swarm **ya hace rollback solo** (`failure_action: rollback` en `stack/base.yml`) — pero el smoke test inicial (`curl` simple) daba un **falso positivo**, porque con `order: start-first` la réplica vieja sigue sirviendo tráfico mientras la nueva intenta arrancar, así que el `curl` pegaba a la instancia vieja y el job de GitHub Actions marcaba "healthy" sin que la imagen nueva jamás funcionara.
3. La corrección: el step ahora consulta `docker service inspect --format '{{.UpdateStatus.State}}'` — el estado real del rollout en Swarm — antes de confiar en el `curl`.
4. Si quieres reproducirlo en vivo: construye una imagen con `CMD ["sleep", "9999"]`, súbela a JFrog con un tag de prueba, dispara `Deploy` con ese `image_tag`, aprueba `dev`, y muestra en la terminal `docker service ps devops-swarm-challenge-dev_app` mientras el job de Actions falla con el motivo correcto (`rollout failed - Swarm already reports state: rollback_completed`).

## 7. Cierre — qué preguntas anticipar

| Pregunta probable | Respuesta corta |
|---|---|
| "¿Por qué no usaste Fluid Attacks real?" | Limitación de licenciamiento comercial de cuenta personal (mínimo de 10 "autores" facturables, sin tier gratuito), documentado en `README.md`. Semgrep cubre la misma categoría de control. |
| "¿Y JFrog? ¿Sigue siendo GHCR?" | No — desde el 2026-08-27 el pipeline usa JFrog Artifactory real (trial con correo corporativo). Se sustituyó por GHCR temporalmente mientras no había acceso, y se migró apenas fue posible; incluso encontré y corregí un problema real de hostname (subdominio vs. path) durante la migración. |
| "¿Por qué un solo nodo Swarm y no DMGR1/DMGR2 reales?" | Es una simulación en una sola máquina en el swarm que sirve `dev`/`sit`/`qa`, pero el patrón multi-nodo se verificó de verdad por separado: un swarm de prueba aislado con dos contenedores `docker:dind` unidos como managers reales, desplegando el `stack/base.yml` sin cambios y con Swarm repartiendo réplicas entre ambos nodos (ver README). No es una suposición. |
| "¿Cómo se garantiza que nadie salte el gate de aprobación?" | `required_reviewers` es una regla de GitHub a nivel de Environment, no algo que el código pueda saltarse — solo se puede desactivar desde Settings con permisos de administrador del repo. |
| "¿Qué pasa si el self-hosted runner se cae?" | `recover-swarm.ps1`, registrado como Scheduled Task, reinicializa el Swarm y vuelve a desplegar los 3 stacks al reiniciar la máquina. |
| "¿Cómo sabes que el deploy realmente funcionó y no un falso positivo?" | Justo por eso el smoke test no es un `curl` simple — verifica `UpdateStatus.State` de Swarm primero, porque un `curl` ingenuo puede pegarle a la réplica vieja durante un rollout fallido (se descubrió probándolo con una imagen rota a propósito). |
| "¿Puede alguien desplegar una imagen que no salió de este pipeline?" | No sin que falle: `deploy.yml` corre `cosign verify` contra la identidad exacta del workflow (`ci.yml@refs/heads/main`) antes de cualquier `docker pull`. |
| "¿Por qué el repo no exigía PR desde el principio?" | Se agregó el 2026-08-24, después de tener el resto del pipeline probado, para no bloquear la iteración rápida al inicio. Como único colaborador, se mantiene el override de admin para poder seguir mergeando — en un equipo real no haría falta. |
