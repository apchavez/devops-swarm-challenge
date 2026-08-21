# Re-establishes local Docker Swarm state after a reboot / Docker Desktop restart,
# since Swarm state does not persist reliably on this machine (see memory).
# Registered as a Scheduled Task (trigger: At log on) so it self-heals without
# manual intervention before the runner's next deploy.yml run.

$ErrorActionPreference = "Stop"
$Image = "ghcr.io/apchavez/devops-swarm-challenge:latest"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Wait-ForDocker {
    for ($i = 0; $i -lt 30; $i++) {
        docker info *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

if (-not (Wait-ForDocker)) {
    Write-Error "Docker daemon not reachable after 150s, aborting."
    exit 1
}

$swarmState = (docker info --format '{{.Swarm.LocalNodeState}}').Trim()
if ($swarmState -ne "active") {
    Write-Output "Swarm inactive (state: $swarmState) - initializing..."
    docker swarm init
} else {
    Write-Output "Swarm already active."
}

docker pull $Image
$env:IMAGE = $Image

foreach ($stackEnv in @("dev", "sit", "qa")) {
    Write-Output "Deploying $stackEnv..."
    docker stack deploy -c "$RepoRoot\stack\base.yml" -c "$RepoRoot\stack\$stackEnv.yml" --with-registry-auth "devops-swarm-challenge-$stackEnv"
}

Write-Output "Recovery complete."
