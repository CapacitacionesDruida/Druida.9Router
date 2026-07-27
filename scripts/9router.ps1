#requires -version 5.1
<#
Wrapper de operacion para Druida 9Router (Windows).
Funciona indistintamente con Docker (docker compose) o Podman
(podman compose / podman-compose). Autodetecta el motor disponible.
#>
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$EnvFile = Join-Path $RootDir ".env"
$EnvExample = Join-Path $RootDir ".env.example"
$ComposeFile = Join-Path $RootDir "compose.yml"
$BackupDir = Join-Path $RootDir "backups"
$VolumeName = "9router-data"

function Test-CommandExists($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-Engine {
    if ($env:COMPOSE_ENGINE) { return $env:COMPOSE_ENGINE -split ' ' }
    if (Test-CommandExists docker) {
        docker compose version *> $null
        if ($LASTEXITCODE -eq 0) { return @("docker", "compose") }
    }
    if (Test-CommandExists podman) {
        podman compose version *> $null
        if ($LASTEXITCODE -eq 0) { return @("podman", "compose") }
    }
    if (Test-CommandExists podman-compose) { return @("podman-compose") }
    throw "No se encontro 'docker compose', 'podman compose' ni 'podman-compose' en el PATH."
}

function Get-Runner {
    if ($env:CONTAINER_ENGINE) { return $env:CONTAINER_ENGINE }
    if (Test-CommandExists docker) { return "docker" }
    if (Test-CommandExists podman) { return "podman" }
    throw "No se encontro 'docker' ni 'podman' en el PATH."
}

function Invoke-Compose {
    param([string[]]$ExtraArgs, [switch]$WithHeadroom)
    $engine = Get-Engine
    $exe = $engine[0]
    $engineArgs = @()
    if ($engine.Length -gt 1) { $engineArgs = $engine[1..($engine.Length - 1)] }
    $opts = @("-f", $ComposeFile)
    if ($WithHeadroom) { $opts += @("--profile", "headroom") }
    $allArgs = $engineArgs + $opts + $ExtraArgs
    & $exe @allArgs
    if ($LASTEXITCODE -ne 0) { throw "Fallo el comando compose (exit $LASTEXITCODE)" }
}

function Assert-EnvFile {
    if (-not (Test-Path $EnvFile)) {
        Write-Error "No existe .env -- corre '.\9router.ps1 setup' primero."
        exit 1
    }
}

function New-RandomHex {
    param([int]$Bytes = 32)
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($buffer)
    } finally {
        $rng.Dispose()
    }
    -join ($buffer | ForEach-Object { $_.ToString("x2") })
}

function Test-HasFlag($flags, $name) {
    return ($flags -contains $name)
}

function Invoke-Setup {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    if (Test-Path $EnvFile) {
        Write-Host "Ya existe .env -- no se sobreescribe (borralo manualmente si queres regenerar secretos)."
        return
    }
    Copy-Item $EnvExample $EnvFile
    $jwt = New-RandomHex
    $api = New-RandomHex
    $salt = New-RandomHex
    $pass = New-RandomHex -Bytes 10

    $lines = Get-Content $EnvFile | ForEach-Object {
        $_ -replace '^JWT_SECRET=.*', "JWT_SECRET=$jwt" -replace '^API_KEY_SECRET=.*', "API_KEY_SECRET=$api" -replace '^MACHINE_ID_SALT=.*', "MACHINE_ID_SALT=$salt" -replace '^INITIAL_PASSWORD=.*', "INITIAL_PASSWORD=$pass"
    }
    Set-Content -Path $EnvFile -Value $lines

    Write-Host "Generado $EnvFile con secretos aleatorios."
    Write-Host "Password inicial del dashboard: $pass"
    Write-Host "Guardala ahora en tu gestor de contraseñas -- se pedira cambiarla en el primer login."
}

function Invoke-Start {
    param([string[]]$Flags)
    Assert-EnvFile
    $wh = Test-HasFlag $Flags "--with-headroom"
    Invoke-Compose -ExtraArgs @("up", "-d") -WithHeadroom:$wh
    Write-Host "9Router arriba. Dashboard: http://localhost:20128"
}

function Invoke-Stop {
    param([string[]]$Flags)
    $wh = Test-HasFlag $Flags "--with-headroom"
    Invoke-Compose -ExtraArgs @("down") -WithHeadroom:$wh
}

function Invoke-Restart {
    param([string[]]$Flags)
    Invoke-Stop -Flags $Flags
    Invoke-Start -Flags $Flags
}

function Invoke-Logs {
    param([string[]]$Flags)
    $svc = if ($Flags.Count -gt 0) { $Flags[0] } else { "9router" }
    Invoke-Compose -ExtraArgs @("logs", "-f", $svc)
}

function Invoke-Status {
    Invoke-Compose -ExtraArgs @("ps")
}

function Invoke-Update {
    param([string[]]$Flags)
    Assert-EnvFile
    $wh = Test-HasFlag $Flags "--with-headroom"
    Invoke-Compose -ExtraArgs @("pull") -WithHeadroom:$wh
    Invoke-Compose -ExtraArgs @("up", "-d", "--force-recreate") -WithHeadroom:$wh
}

function Invoke-Backup {
    $runner = Get-Runner
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $file = "9router-$ts.tar.gz"
    & $runner run --rm -v "${VolumeName}:/data:ro" -v "${BackupDir}:/backup" alpine sh -c "tar czf /backup/$file -C /data ."
    if ($LASTEXITCODE -ne 0) { throw "Fallo el backup (exit $LASTEXITCODE)" }
    Write-Host "Backup creado: $BackupDir\$file"
}

function Invoke-Restore {
    param([string[]]$Flags)
    $runner = Get-Runner
    if ($Flags.Count -lt 1) {
        Write-Error "Uso: .\9router.ps1 restore <archivo.tar.gz> [-y]"
        exit 1
    }
    $inputArg = $Flags[0]
    $autoYes = ($Flags -contains "-y") -or ($Flags -contains "--yes")
    $file = $inputArg
    if (-not (Test-Path $file)) {
        $candidate = Join-Path $BackupDir $inputArg
        if (Test-Path $candidate) { $file = $candidate }
    }
    if (-not (Test-Path $file)) {
        Write-Error "No se encontro el archivo de backup: $inputArg"
        exit 1
    }
    $absFile = (Resolve-Path $file).Path
    $absDir = Split-Path -Parent $absFile
    $baseName = Split-Path -Leaf $absFile

    Write-Host "ATENCION: esto extrae $absFile encima del contenido actual del volumen $VolumeName."
    Write-Host "Si queres un volumen totalmente limpio, primero '.\9router.ps1 stop' y elimina el volumen manualmente."
    if (-not $autoYes) {
        $confirm = Read-Host "Escribi 'si' para continuar"
        if ($confirm -ne "si") {
            Write-Host "Cancelado."
            exit 1
        }
    }
    & $runner run --rm -v "${VolumeName}:/data" -v "${absDir}:/backup:ro" alpine sh -c "tar xzf /backup/$baseName -C /data"
    if ($LASTEXITCODE -ne 0) { throw "Fallo la restauracion (exit $LASTEXITCODE)" }
    Write-Host "Restauracion completa desde $absFile. Reinicia el servicio: .\9router.ps1 restart"
}

function Show-Usage {
    @'
Uso: 9router.ps1 <comando> [opciones]

Comandos:
  setup                      Genera .env con secretos aleatorios (una sola vez)
  start   [--with-headroom]  Levanta el stack
  stop    [--with-headroom]  Detiene el stack
  restart [--with-headroom]  Reinicia el stack
  logs    [servicio]         Sigue los logs (default: 9router)
  status                     Muestra el estado de los contenedores
  update  [--with-headroom]  Actualiza la imagen y recrea el contenedor
  backup                     Genera un tar.gz del volumen de datos en backups/
  restore <archivo> [-y]     Restaura un backup sobre el volumen de datos
  help                       Muestra esta ayuda

Detecta automaticamente Docker o Podman. Para forzar uno:
  $env:COMPOSE_ENGINE = "podman compose"; .\9router.ps1 start
  $env:CONTAINER_ENGINE = "podman"; .\9router.ps1 backup
'@ | Write-Host
}

switch ($Command) {
    "setup"   { Invoke-Setup }
    "start"   { Invoke-Start -Flags $Rest }
    "stop"    { Invoke-Stop -Flags $Rest }
    "restart" { Invoke-Restart -Flags $Rest }
    "logs"    { Invoke-Logs -Flags $Rest }
    "status"  { Invoke-Status }
    "update"  { Invoke-Update -Flags $Rest }
    "backup"  { Invoke-Backup }
    "restore" { Invoke-Restore -Flags $Rest }
    "help"    { Show-Usage }
    default   { Write-Host "Comando desconocido: $Command"; Show-Usage; exit 1 }
}
