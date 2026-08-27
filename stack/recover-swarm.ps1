# Re-establishes local Docker Swarm state after a reboot / Docker Desktop restart,
# since Swarm state does not persist reliably on this machine (see memory).
# Registered as a Scheduled Task (trigger: At log on) so it self-heals without
# manual intervention before the runner's next deploy.yml run.

$ErrorActionPreference = "Stop"
$Image = "trialsvu54e.jfrog.io/docker-trial/devops-swarm-challenge:latest"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Wait-ForDocker {
    for ($i = 0; $i -lt 60; $i++) {
        docker info *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 10
    }
    return $false
}

if (-not (Wait-ForDocker)) {
    Write-Error "Docker daemon not reachable after 600s, aborting."
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

# After a Docker Desktop stop/restart, Swarm can come back "active" with the
# right desired replica count but never reschedule replacement tasks on its
# own (observed 2026-08-21). Give reconciliation a moment, then force any
# service still short of its desired count.
Start-Sleep -Seconds 15

foreach ($stackEnv in @("dev", "sit", "qa")) {
    $serviceName = "devops-swarm-challenge-${stackEnv}_app"
    $replicas = (docker service ls --filter "name=$serviceName" --format '{{.Replicas}}').Trim()
    if ($replicas -match '^(\d+)/(\d+)$' -and [int]$Matches[1] -lt [int]$Matches[2]) {
        Write-Output "$serviceName stuck at $replicas - forcing reschedule..."
        docker service update --force $serviceName --detach=false
    }
}

Write-Output "Recovery complete."
