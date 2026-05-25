<#
.SYNOPSIS
    Updates the local Windows SSH config for the currently running RunPod pod.

.DESCRIPTION
    This script looks up a RunPod pod by name or ID using runpodctl, reads its
    current SSH connection details, and writes or updates a stable SSH host entry
    called "runpod-pod" in the local SSH config file:

        C:\Users\<user>\.ssh\config

    The purpose is to keep VSCode Remote SSH stable even though RunPod may assign
    a new public IP address or SSH port whenever a pod is recreated.

    After running this script, connect via:

        ssh runpod-pod

    or in VSCode:

        Remote-SSH: Connect to Host...
        runpod-pod

.PARAMETER PodNameOrId
    The RunPod pod name or pod ID as shown by:

        runpodctl.exe pod list

.EXAMPLE
    .\update-runpod-ssh-from-pod.ps1 -PodNameOrId "Isaac-Test"

.EXAMPLE
    .\update-runpod-ssh-from-pod.ps1 -PodNameOrId "abc123xyz"

.NOTES
    Requirements:
    - runpodctl must be installed and available in PATH.
    - You must be logged in/configured with runpodctl.
    - The pod must be running and have SSH enabled.
    - The SSH key path returned by RunPod must exist locally.

    The generated SSH config block uses:
    - Host alias: runpod-pod
    - User: root
    - StrictHostKeyChecking: no
    - UserKnownHostsFile: NUL

    This avoids stale host key warnings when RunPod reuses the same alias with
    changing IP addresses.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PodNameOrId
)

# Path to the local OpenSSH config file used by Windows OpenSSH and VSCode Remote SSH.
$ConfigPath = "$env:USERPROFILE\.ssh\config"

Write-Host ""
Write-Host "Searching RunPod pod..."

# Query all pods from RunPod and parse the JSON output.
# The script expects runpodctl.exe to be available in PATH.
$Pods = runpodctl.exe pod list | ConvertFrom-Json

# Match either by pod ID or by pod name.
$Pod = $Pods | Where-Object {
    $_.id -eq $PodNameOrId -or
    $_.name -eq $PodNameOrId
}

if (-not $Pod) {
    Write-Error "Pod not found. Check the pod name or ID with: runpodctl.exe pod list"
    exit 1
}

$PodId = $Pod.id

Write-Host "Found Pod:"
Write-Host "Name: $($Pod.name)"
Write-Host "ID:   $PodId"

# Retrieve detailed pod information including SSH connection details.
$Json = runpodctl.exe pod get $PodId --output json | ConvertFrom-Json

$Ip = $Json.ssh.ip
$Port = $Json.ssh.port
$KeyPath = $Json.ssh.ssh_key.path

# Validate that RunPod returned complete SSH information.
if (-not $Ip -or -not $Port -or -not $KeyPath) {
    Write-Error "SSH information not found. Make sure the pod is running and SSH is enabled."
    exit 1
}

# Build the SSH config block.
# The alias "runpod-pod" stays stable, even when IP or port changes.
$Block = @"
Host runpod-pod
    HostName $Ip
    Port $Port
    User root
    IdentityFile $KeyPath
    StrictHostKeyChecking no
    UserKnownHostsFile NUL
"@

# Read existing SSH config if it exists; otherwise start with an empty config.
if (Test-Path $ConfigPath) {
    $Config = Get-Content $ConfigPath -Raw
}
else {
    $Config = ""
}

# Regex pattern to find and replace an existing "Host runpod-pod" block.
# This keeps the config file clean and avoids duplicate entries.
$Pattern = "(?ms)^Host runpod-pod\s+.*?(?=^Host\s|\z)"

if ($Config -match $Pattern) {
    $Config = [regex]::Replace($Config, $Pattern, $Block)
}
else {
    $Config += "`r`n$Block`r`n"
}

# Write the updated SSH config back to disk.
# ASCII encoding is used for maximum compatibility with OpenSSH on Windows.
Set-Content -Path $ConfigPath -Value $Config -Encoding ascii

Write-Host ""
Write-Host "SSH Config updated"
Write-Host ""
Write-Host "Host: runpod-pod"
Write-Host "IP:   $Ip"
Write-Host "Port: $Port"
Write-Host "Key:  $KeyPath"
Write-Host ""
Write-Host "Test with:"
Write-Host "ssh runpod-pod"