# Prerequisitos técnicos

Documento de referencia para reproducir este pipeline desde cero, o para explicar en la sustentación qué se necesitó configurar y por qué.

## 1. Cuentas y accesos externos

| Necesitas | Para qué | Notas |
|---|---|---|
| Cuenta de GitHub | Alojar el repo y correr Actions | El repo debe ser **público** para que GHAS (CodeQL + secret scanning) y `required_reviewers` en Environments sean gratuitos en una cuenta personal (ver `README.md`) |
| Cuenta de SonarCloud | Quality Gate Sonar | Gratis para repos públicos; genera un `SONAR_TOKEN` |
| Docker instalado localmente | Build de la imagen, Docker Swarm, correr el self-hosted runner | Docker Desktop en Windows, o Docker Engine en Linux |

No se necesita cuenta de JFrog ni de Fluid Attacks — ver la justificación de por qué se sustituyeron en `README.md`.

## 2. Secrets y variables de GitHub (Settings → Secrets and variables → Actions)

| Nombre | Tipo | Usado en |
|---|---|---|
| `SONAR_TOKEN` | Secret | `ci.yml`, job `quality-gate-sonar` |
| `SONAR_ORGANIZATION` | Variable (`vars`) | `ci.yml`, condición del step de SonarCloud |
| `GITHUB_TOKEN` | Automático (no se crea a mano) | login a GHCR, checkout, upload-sarif |

## 3. GitHub Environments (Settings → Environments)

Crear tres: `dev`, `sit`, `qa`. En cada uno:

- Activar **Required reviewers** y agregarte a ti mismo (o a quien apruebe) como reviewer.
- (Opcional) Restringir a la rama `main` con "Deployment branches and tags".

Sin esto, `deploy.yml` se ejecuta sin pausas — el gate de aprobación del diagrama depende enteramente de esta configuración manual en GitHub, no está en el código.

## 4. Branch protection (Settings → Branches → main)

- Require status checks to pass: `Build Code + Unit Test + Code analysis`, `Quality Gate Sonar`, `Fluid Attacks equivalent (Semgrep SAST)`, `Analyze (python)`.
- Do not allow force pushes.
- Do not allow deletions.
- **No** se exige pull request antes de mergear (el flujo de este repo es push directo a `main`; el gate de aprobación real vive en los Environments, no en la rama).

Se puede aplicar por UI o vía API (ver comando exacto usado en el historial de commits del repo, mensaje "Pin GitHub Actions to commit SHA...").

## 5. Security & analysis (Settings → Code security)

- **Secret scanning**: enabled.
- **Secret scanning push protection**: enabled.
- **Dependabot alerts**: enabled.
- **Dependabot security updates**: enabled.
- `Code scanning` se activa solo (no hay toggle manual) al hacer merge de `codeql.yml`.

## 6. Self-hosted runner (onprem)

En la máquina que va a actuar como "Onpremise":

1. Settings → Actions → Runners → New self-hosted runner.
2. Registrar el runner con la etiqueta **`onprem`** (usada en `deploy.yml`: `runs-on: [self-hosted, onprem]`).
3. Instalar el runner como servicio para que sobreviva reinicios.
4. Tener Docker instalado y el usuario del runner con permisos para usarlo.
5. Ejecutar `docker swarm init` una vez en esa máquina (idempotente: si ya está activo, no hace nada).

### Auto-recuperación del Swarm

`stack/recover-swarm.ps1` reinicializa el Swarm y vuelve a desplegar los 3 stacks si la máquina se reinicia o Docker Desktop se reinicia (el estado de Swarm no siempre persiste de forma confiable en Docker Desktop para Windows). Se registra como una **Scheduled Task de Windows** con trigger "At log on":

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\ruta\al\repo\stack\recover-swarm.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "SwarmRecovery-devops-swarm-challenge" `
  -Action $action -Trigger $trigger -RunLevel Highest
```

## 7. Dependencias del proyecto (para desarrollo local, no para CI)

| Herramienta | Versión usada | Dónde se declara |
|---|---|---|
| Python | 3.12 | `ci.yml` (`actions/setup-python`), `Dockerfile` |
| fastapi | 0.115.0 | `requirements.txt` |
| uvicorn | 0.30.6 | `requirements.txt` |
| pytest | 9.0.3 (subido por CVE-2025-71176) | `requirements-dev.txt` |
| pytest-cov | 5.0.0 | `requirements-dev.txt` |
| ruff | 0.6.4 | `requirements-dev.txt` |

No hace falta instalar Python localmente para probar: `docker/dev.sh` corre todo dentro de un contenedor.

## 8. Puertos usados localmente

| Ambiente | Puerto host | Réplicas |
|---|---|---|
| dev | 8081 | 1 |
| sit | 8082 | 1 |
| qa | 8083 | 2 |

Todos mapean al puerto 8000 del contenedor (`uvicorn`).
