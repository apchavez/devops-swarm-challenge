# Configurar JFrog Artifactory (free tier)

Pasos manuales — no automatizables porque requieren verificación de correo. Una vez hecho esto, el job `publish-artifactory` de `ci.yml` queda activo automáticamente (está condicionado a que exista `vars.JF_URL`).

1. Crear cuenta en https://jfrog.com/start-free/ (plan "Free" de JFrog Cloud, no requiere tarjeta).
2. En el panel de Artifactory, crear un repositorio Docker local: **Administration → Repositories → Repositories → Add → Local → Docker**. Nómbralo, por ejemplo, `devops-swarm-docker-local`.
3. Generar un Access Token: **User menu → Edit Profile → Generate an Identity Token** (o **Access Tokens** en instancias más nuevas). Copia el token, no se vuelve a mostrar.
4. En GitHub, configurar en `apchavez/devops-swarm-challenge → Settings → Secrets and variables → Actions`:
   - **Variables** (no secretas):
     - `JF_URL` = `https://<tu-subdominio>.jfrog.io`
     - `JF_DOCKER_REPO` = `<tu-subdominio>.jfrog.io/devops-swarm-docker-local`
   - **Secrets**:
     - `JF_ACCESS_TOKEN` = el token generado en el paso 3

```bash
gh variable set JF_URL --repo apchavez/devops-swarm-challenge --body "https://<tu-subdominio>.jfrog.io"
gh variable set JF_DOCKER_REPO --repo apchavez/devops-swarm-challenge --body "<tu-subdominio>.jfrog.io/devops-swarm-docker-local"
gh secret set JF_ACCESS_TOKEN --repo apchavez/devops-swarm-challenge --body "<el-token>"
```

5. Volver a correr `ci.yml` (push cualquier commit, o `gh workflow run ci.yml`) — el job `publish-artifactory` ahora sí construirá y subirá la imagen.
6. Para que `deploy.yml` despliegue la imagen real de Artifactory en vez del build local, el self-hosted runner necesita autenticarse una vez con `docker login <tu-subdominio>.jfrog.io` (usando el mismo usuario/token) para que `docker stack deploy --with-registry-auth` pueda hacer pull.
