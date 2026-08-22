# Guía de demostración (para sustentar)

Orden sugerido para mostrar el pipeline completo en vivo, de principio a fin, con lo que hay que decir en cada paso.

## 0. Preparación (antes de la sustentación)

- Ten abiertas dos pestañas del navegador: el repo en GitHub (`Code`) y la pestaña `Actions`.
- Verifica que el self-hosted runner esté "Idle" en Settings → Actions → Runners (si está offline, el `deploy.yml` se queda colgado esperando).
- Ten una terminal lista en la máquina donde corre el runner, para mostrar `docker service ls` en vivo.

## 1. Mostrar el diagrama y el mapeo (2-3 min)

Abre `docs/ARQUITECTURA.md` en GitHub (renderiza el diagrama Mermaid automáticamente). Explica:

- Este es el diagrama del reto (`reto.png`) reconstruido con lo que realmente se implementó.
- Los dos bloques amarillos (Semgrep, GHCR) son sustituciones documentadas — explica en 20 segundos por qué (ver `README.md`, tabla de mapeo).
- Todo lo demás — GitHub Advanced Security, SonarCloud, el runner self-hosted, Docker Swarm, el gate de aprobación por ambiente — es la herramienta real.

## 2. Disparar el pipeline de CI (5 min)

1. Haz un cambio trivial (ej. un comentario en `app/main.py`) y push a `main`, o simplemente referencia el último commit ya existente.
2. En la pestaña **Actions**, abre el run de `CI` en vivo. Señala cada job mientras corre:
   - `Build Code + Unit Test + Code analysis` → build + pytest + ruff.
   - `Fluid Attacks equivalent (Semgrep SAST)` → corre dentro de un contenedor `semgrep/semgrep`, genera SARIF.
   - `Quality Gate Sonar` → cobertura + análisis en SonarCloud.
   - `Build image + push to GitHub Container Registry` → solo corre si los tres anteriores pasan y es push a `main`.
3. Cuando termine, ve a la pestaña **Security → Code scanning alerts** del repo y muestra que hay hallazgos de **dos herramientas distintas**: CodeQL y Semgrep, cada uno con su categoría.
4. Muestra **Security → Dependabot** y explica que las alertas de vulnerabilidad de dependencias (Python, Docker, GitHub Actions) llegan aquí automáticamente — puedes mencionar el caso real: Dependabot encontró `pytest` vulnerable (CVE-2025-71176) apenas se habilitó, y se corrigió el mismo día.

## 3. Mostrar el hardening de supply chain (2 min)

Abre `.github/workflows/ci.yml` en GitHub y señala una línea como:

```yaml
uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
```

Explica: no se usa el tag `@v4` (mutable, un mantenedor comprometido podría re-apuntarlo — pasó de verdad con `trivy-action` y `kics-github-action`), sino el commit SHA exacto. Menciona que esto lo encontró el propio Semgrep corriendo sobre el repo (dogfooding: la herramienta de seguridad del pipeline audita al pipeline mismo).

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
```

## 6. Cierre — qué preguntas anticipar

| Pregunta probable | Respuesta corta |
|---|---|
| "¿Por qué no usaste JFrog/Fluid Attacks reales?" | Limitaciones de acceso de cuenta personal (correo corporativo exigido / mínimo de licenciamiento comercial), documentado con las respuestas HTTP exactas en `README.md`. El patrón arquitectónico (subir a un registry en la nube, SAST en el pipeline) es idéntico. |
| "¿Por qué un solo nodo Swarm y no DMGR1/DMGR2 reales?" | Es una simulación en una sola máquina; el comando `docker stack deploy` es el mismo que en un swarm multi-nodo real, documentado en `docs/ARQUITECTURA.md`. |
| "¿Cómo se garantiza que nadie salte el gate de aprobación?" | `required_reviewers` es una regla de GitHub a nivel de Environment, no algo que el código pueda saltarse — solo se puede desactivar desde Settings con permisos de administrador del repo. |
| "¿Qué pasa si el self-hosted runner se cae?" | `recover-swarm.ps1`, registrado como Scheduled Task, reinicializa el Swarm y vuelve a desplegar los 3 stacks al reiniciar la máquina. |
