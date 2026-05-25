param(
    [Parameter(Mandatory=$true)]
    [string]$PodNameOrId
)

$ConfigPath = "$env:USERPROFILE\.ssh\config"

Write-Host ""
Write-Host "Searching RunPod pod..."

$Pods = runpodctl.exe pod list | ConvertFrom-Json

$Pod = $Pods | Where-Object {
    $_.id -eq $PodNameOrId -or
    $_.name -eq $PodNameOrId
}

if (-not $Pod) {
    Write-Error "Pod not found."
    exit 1
}

$PodId = $Pod.id

Write-Host "Found Pod:"
Write-Host "Name: $($Pod.name)"
Write-Host "ID:   $PodId"

$Json = runpodctl.exe pod get $PodId --output json | ConvertFrom-Json

$Ip = $Json.ssh.ip
$Port = $Json.ssh.port
$KeyPath = $Json.ssh.ssh_key.path

if (-not $Ip -or -not $Port -or -not $KeyPath) {
    Write-Error "SSH information not found."
    exit 1
}

$Block = @"
Host runpod-pod
    HostName $Ip
    Port $Port
    User root
    IdentityFile $KeyPath
    StrictHostKeyChecking no
    UserKnownHostsFile NUL
"@

if (Test-Path $ConfigPath) {
    $Config = Get-Content $ConfigPath -Raw
}
else {
    $Config = ""
}

$Pattern = "(?ms)^Host runpod-pod\s+.*?(?=^Host\s|\z)"

if ($Config -match $Pattern) {
    $Config = [regex]::Replace($Config, $Pattern, $Block)
}
else {
    $Config += "`r`n$Block`r`n"
}

Set-Content -Path $ConfigPath -Value $Config -Encoding ascii

Write-Host ""
Write-Host "SSH Config updated"
Write-Host ""
Write-Host "Host: runpod-pod"
Write-Host "IP:   $Ip"
Write-Host "Port: $Port"
Write-Host "Key:  $KeyPath"