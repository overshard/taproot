<#
.SYNOPSIS
    Idempotent host-side setup for the bythewood-webdev Docker container.

.DESCRIPTION
    Brings a Windows 11 machine from "Docker Desktop installed + SSH key set up"
    to a fully running webdev container with restic credentials in place.

    The host stays minimal: this script never clones taproot to the host
    filesystem. Instead it uses one-shot ubuntu:24.04 helper containers (the
    same base image webdev itself is built from) to do the work directly
    against the bythewood-code volume:

        - clone taproot into the volume via SSH (using the host's home_key,
          mounted read-only)
        - build the webdev image using docker.sock to reach the host's daemon

    Each step inspects current state and skips if already done, so this is
    safe to re-run on a partially-configured machine.

    First-time machine setup (one-liner; assumes Docker Desktop is running and
    you have an SSH key at $HOME/.ssh/home_key added to GitHub):

        irm https://raw.githubusercontent.com/overshard/taproot/master/containers/webdev/bootstrap.ps1 -OutFile bootstrap.ps1
        .\bootstrap.ps1 laptop

    Host-side dotfiles (Zed settings, ~/.ssh/config) are NOT managed by this
    script. After taproot is in the bythewood-code volume, copy them by hand:
        dotfiles/host/zed-settings.json -> $env:APPDATA\Zed\settings.json
        dotfiles/host/ssh-config        -> $HOME\.ssh\config

    Subsequent runs (from inside the cloned-in-volume taproot is fine; the
    script doesn't depend on its own location):

        .\bootstrap.ps1 desktop                # idempotent, all skips
        .\bootstrap.ps1 laptop -Force          # pull taproot, rebuild image, recreate container
        .\bootstrap.ps1 laptop -Restore        # restore data from B2 snapshot

.PARAMETER HostTag
    The restic --host tag for this machine. Use "desktop" or "laptop".

.PARAMETER Only
    Run only the named step. One of: prereqs, volumes, taproot, image,
    container, ssh, restic-password, b2-env, alpine-password, restore.

.PARAMETER Restore
    After all setup steps, run ~/scripts/restore inside the container to pull
    data from the latest B2 snapshot. Opt-in.

.PARAMETER Force
    Pull latest taproot, rebuild the image, remove the existing container,
    create a new container from the new image. Volumes (and your data) are
    untouched.

.PARAMETER TaprootRepo
    SSH URL of the taproot repository. Default: git@github.com:overshard/taproot.git

.PARAMETER TaprootBranch
    Branch to clone/pull. Default: master
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("desktop", "laptop")]
    [string]$HostTag,

    [ValidateSet(
        "prereqs", "volumes", "taproot", "image", "container",
        "ssh", "restic-password", "b2-env", "alpine-password", "restore"
    )]
    [string]$Only,

    [switch]$Restore,
    [switch]$Force,

    [string]$TaprootRepo = "git@github.com:overshard/taproot.git",
    [string]$TaprootBranch = "master"
)

$ErrorActionPreference = "Stop"

$ImageName = "overshard/webdev:latest"
$ContainerName = "bythewood-webdev"
$Volumes = @("bythewood-code", "bythewood-claude", "bythewood-ssh", "bythewood-restic")
$HelperImage = "ubuntu:24.04"
$HostKeyPath = Join-Path $HOME ".ssh\home_key"
$HostKeyPubPath = Join-Path $HOME ".ssh\home_key.pub"

function Step-Banner { param([string]$Name) Write-Host ""; Write-Host "=== $Name ===" -ForegroundColor Cyan }
function Done   { param([string]$M) Write-Host "  [done] $M" -ForegroundColor Green }
function Skip   { param([string]$M) Write-Host "  [skip] $M" -ForegroundColor DarkGray }
function Warn   { param([string]$M) Write-Host "  [warn] $M" -ForegroundColor Yellow }
function Fail   { param([string]$M) Write-Host "  [fail] $M" -ForegroundColor Red; exit 1 }

function Should-Run { param([string]$Name) return (-not $Only) -or ($Only -eq $Name) }

# ---------------------------------------------------------------------------
function Step-Prereqs {
    Step-Banner "prereqs"
    try {
        $null = docker version --format '{{.Server.Version}}' 2>$null
        Done "Docker Desktop is running"
    } catch {
        Fail "Docker Desktop is not running. Start it and re-run."
    }

    if (-not (Test-Path $HostKeyPath) -or -not (Test-Path $HostKeyPubPath)) {
        Fail @"
SSH key not found at $HostKeyPath (.pub).
Set up your keys first:
    ssh-keygen -t ed25519 -f `"$HostKeyPath`" -C bythewood-webdev
Then add the public key to GitHub:
    Get-Content `"$HostKeyPubPath`" | clip
Paste at https://github.com/settings/ssh/new
"@
    }
    Done "SSH key found at $HostKeyPath"
}

# ---------------------------------------------------------------------------
function Step-Volumes {
    Step-Banner "volumes"
    foreach ($v in $Volumes) {
        docker volume inspect $v 2>$null 1>$null
        if ($LASTEXITCODE -eq 0) {
            Skip "$v exists"
        } else {
            docker volume create --name $v | Out-Null
            Done "created $v"
        }
    }
}

# ---------------------------------------------------------------------------
function Invoke-Helper-Clone {
    param([string]$Action) # "clone" or "pull"

    $cmd = if ($Action -eq "clone") {
        "git clone --branch '$TaprootBranch' '$TaprootRepo' /code/taproot"
    } else {
        "cd /code/taproot && git fetch --all --prune && git pull --ff-only"
    }

    docker run --rm `
        --volume "${HostKeyPath}:/keys/home_key:ro" `
        --volume "bythewood-code:/code" `
        -e GIT_SSH_COMMAND="ssh -i /keys/home_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/known_hosts" `
        $HelperImage `
        sh -c "set -e; apt-get update >/dev/null && apt-get install -y --no-install-recommends git openssh-client >/dev/null && $cmd"

    if ($LASTEXITCODE -ne 0) { Fail "helper container failed during '$Action'" }
}

function Step-Taproot {
    Step-Banner "taproot"
    docker run --rm --volume "bythewood-code:/code" $HelperImage `
        test -d /code/taproot/.git 2>$null
    $exists = ($LASTEXITCODE -eq 0)

    if (-not $exists) {
        Done "cloning $TaprootRepo into bythewood-code volume"
        Invoke-Helper-Clone -Action "clone"
        return
    }

    if ($Force) {
        Done "pulling latest $TaprootBranch into existing /code/taproot"
        Invoke-Helper-Clone -Action "pull"
        return
    }

    Skip "taproot already in bythewood-code volume (use -Force to git pull)"
}

# ---------------------------------------------------------------------------
function Step-Image {
    Step-Banner "image"
    docker image inspect $ImageName 2>$null 1>$null
    $exists = ($LASTEXITCODE -eq 0)

    if ($exists -and -not $Force) {
        Skip "$ImageName already built (use -Force to rebuild)"
        return
    }

    Done "building $ImageName from /code/taproot in bythewood-code"
    docker run --rm `
        --volume "bythewood-code:/code" `
        --volume "/var/run/docker.sock:/var/run/docker.sock" `
        $HelperImage `
        sh -c "set -e; apt-get update >/dev/null && apt-get install -y --no-install-recommends docker.io >/dev/null && cd /code/taproot && docker build --tag $ImageName -f containers/webdev/Dockerfile ."

    if ($LASTEXITCODE -ne 0) { Fail "image build failed" }
}

# ---------------------------------------------------------------------------
function Step-Container {
    Step-Banner "container"
    docker container inspect $ContainerName 2>$null 1>$null
    $exists = ($LASTEXITCODE -eq 0)

    if ($exists -and $Force) {
        Done "removing existing container (-Force)"
        docker rm -f $ContainerName | Out-Null
        $exists = $false
    }

    if ($exists) {
        $running = (docker container inspect -f '{{.State.Running}}' $ContainerName)
        if ($running -eq "true") {
            Skip "$ContainerName running"
        } else {
            docker start $ContainerName | Out-Null
            Done "started existing $ContainerName"
        }
        return
    }

    Done "creating $ContainerName"
    $dockerArgs = @(
        "run", "--detach", "--init", "--restart", "unless-stopped",
        "--name", $ContainerName,
        "--volume", "bythewood-code:/home/dev/code",
        "--volume", "bythewood-claude:/home/dev/.claude",
        "--volume", "bythewood-ssh:/home/dev/.ssh",
        "--volume", "bythewood-restic:/home/dev/.restic",
        "--volume", "/var/run/docker.sock:/var/run/docker.sock",
        "-p", "8000:8000",
        "-p", "2222:22",
        $ImageName
    )
    docker @dockerArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "docker run failed" }
}

# ---------------------------------------------------------------------------
function Step-Ssh {
    Step-Banner "ssh"
    docker exec $ContainerName test -f /home/dev/.ssh/home_key 2>$null
    $keyOk = ($LASTEXITCODE -eq 0)
    docker exec $ContainerName test -f /home/dev/.ssh/home_key.pub 2>$null
    $pubOk = ($LASTEXITCODE -eq 0)
    if ($keyOk -and $pubOk) {
        Skip "home_key already in volume"
        return
    }

    docker cp $HostKeyPath "${ContainerName}:/home/dev/.ssh/home_key" | Out-Null
    docker cp $HostKeyPubPath "${ContainerName}:/home/dev/.ssh/home_key.pub" | Out-Null
    docker exec $ContainerName sudo chown dev:dev /home/dev/.ssh/home_key /home/dev/.ssh/home_key.pub | Out-Null
    docker exec $ContainerName chmod 600 /home/dev/.ssh/home_key | Out-Null
    Done "copied home_key + home_key.pub into bythewood-ssh volume"
}

# ---------------------------------------------------------------------------
function Read-Secret { param([string]$Prompt)
    $sec = Read-Host -AsSecureString -Prompt $Prompt
    return [System.Net.NetworkCredential]::new("", $sec).Password
}

function Write-File-Into-Container { param([string]$Path, [string]$Content)
    $tmp = New-TemporaryFile
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Content)
        [System.IO.File]::WriteAllBytes($tmp.FullName, $bytes)
        docker cp $tmp.FullName "${ContainerName}:${Path}" | Out-Null
        docker exec $ContainerName sudo chown dev:dev $Path | Out-Null
        docker exec $ContainerName chmod 600 $Path | Out-Null
    } finally {
        Remove-Item $tmp.FullName -Force
    }
}

# ---------------------------------------------------------------------------
function Step-ResticPassword {
    Step-Banner "restic-password"
    docker exec $ContainerName test -s /home/dev/.restic/password 2>$null
    if ($LASTEXITCODE -eq 0) {
        Skip "/home/dev/.restic/password already set"
        return
    }
    $pw = Read-Secret "Restic webdev repo password (paste from 1Password)"
    if (-not $pw) { Fail "empty password" }
    Write-File-Into-Container "/home/dev/.restic/password" "$pw`n"
    Done "wrote /home/dev/.restic/password"
}

# ---------------------------------------------------------------------------
function Step-B2Env {
    Step-Banner "b2-env"
    docker exec $ContainerName test -s /home/dev/.restic/b2-env 2>$null
    $exists = ($LASTEXITCODE -eq 0)

    if ($exists) {
        $currentText = (docker exec $ContainerName cat /home/dev/.restic/b2-env) -join "`n"
        if ($currentText -match 'RESTIC_HOST=["]?([^"\r\n]+)["]?') {
            $existingHost = $matches[1].Trim('"')
            if ($existingHost -eq $HostTag) {
                Skip "/home/dev/.restic/b2-env complete (RESTIC_HOST=$existingHost)"
            } else {
                Warn "/home/dev/.restic/b2-env has RESTIC_HOST=$existingHost (expected $HostTag)."
                Warn "Not modifying. Edit manually if wrong: docker exec -it $ContainerName nvim /home/dev/.restic/b2-env"
            }
            return
        }
        Done "appending RESTIC_HOST=$HostTag to existing b2-env"
        $newContent = $currentText.TrimEnd("`r","`n") + "`nexport RESTIC_HOST=`"$HostTag`"`n"
        Write-File-Into-Container "/home/dev/.restic/b2-env" $newContent
        return
    }

    $accountId = Read-Secret "B2 account ID"
    $accountKey = Read-Secret "B2 account key"
    if (-not $accountId -or -not $accountKey) { Fail "empty B2 credential" }
    $content = @"
export B2_ACCOUNT_ID="$accountId"
export B2_ACCOUNT_KEY="$accountKey"
export RESTIC_HOST="$HostTag"
"@
    Write-File-Into-Container "/home/dev/.restic/b2-env" "$content`n"
    Done "wrote /home/dev/.restic/b2-env with RESTIC_HOST=$HostTag"
}

# ---------------------------------------------------------------------------
function Step-AlpinePassword {
    Step-Banner "alpine-password"
    docker exec $ContainerName test -s /home/dev/.restic/alpine-password 2>$null
    if ($LASTEXITCODE -eq 0) {
        Skip "/home/dev/.restic/alpine-password already set"
        return
    }
    Write-Host "  Optional: lets ~/scripts/status query the alpine repo too." -ForegroundColor DarkGray
    $pw = Read-Secret "Alpine repo password (or empty to skip)"
    if (-not $pw) {
        Skip "no value provided"
        return
    }
    Write-File-Into-Container "/home/dev/.restic/alpine-password" "$pw`n"
    Done "wrote /home/dev/.restic/alpine-password"
}

# ---------------------------------------------------------------------------
function Step-Restore {
    Step-Banner "restore"
    if (-not $Restore -and $Only -ne "restore") {
        Skip "use -Restore to pull data from B2"
        return
    }
    Done "running ~/scripts/restore inside container"
    docker exec -it $ContainerName /home/dev/scripts/restore
}

# ---------------------------------------------------------------------------
if (Should-Run "prereqs")          { Step-Prereqs }
if (Should-Run "volumes")          { Step-Volumes }
if (Should-Run "taproot")          { Step-Taproot }
if (Should-Run "image")            { Step-Image }
if (Should-Run "container")        { Step-Container }
if (Should-Run "ssh")              { Step-Ssh }
if (Should-Run "restic-password")  { Step-ResticPassword }
if (Should-Run "b2-env")           { Step-B2Env }
if (Should-Run "alpine-password")  { Step-AlpinePassword }
if (Should-Run "restore")          { Step-Restore }

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Connect with:  docker exec -it $ContainerName tmux"
Write-Host "Or via SSH:    ssh -p 2222 dev@localhost"
