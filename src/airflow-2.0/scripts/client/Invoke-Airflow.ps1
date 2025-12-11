[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$profile,
        [string]$Dag,
        [string]$ListDagrun,
        [switch]$Help,
        [switch]$ListDags,
        [switch]$TriggerDag,
        [switch]$Long,
        [string]$payload,
        [string]$timeout
)

function Export-Credential
{
param(
        $Path
)
        $domain = read-host "Domain"
        $username = read-host "UserName"
        $password = read-host "Password" -assecurestring
        $credentials = @{
        "Username" = $username;
        "Password" = $password | ConvertFrom-SecureString;
        "Domain" = $domain;
    }
    $credentials | ConvertTo-Json | Out-File $path
}


$HelpText = @"

    Invoke-Airflow
    Usage:
    .\Invoke-Airflow.ps1 -profile `$profile

"@

if($Help -or (!($profile))){write-host $Helptext; Break}
$CredPath = join-path ($PsScriptRoot) "$profile.json"

if (!(Test-Path -Path $CredPath -PathType Leaf)){
    Export-Credential $CredPath
}

$Credentials = (Get-Content $CredPath) | ConvertFrom-Json

$Credentials.Password = $Credentials.Password | ConvertTo-SecureString

$uri = "https://$($Credentials.Domain)/api/v1/dags"
$credential = New-Object System.Management.Automation.PsCredential($Credentials.Username, $Credentials.Password)

if ($ListDags){
    $Resp = Invoke-WebRequest -Uri $uri -Credential $credential -Method GET
    write-host "Status : $($Resp.StatusCode), $($Resp.StatusDescription)"
    if ($Long){
        write-host "Content : $($Resp.Content)"
    }
    if ($Dag){
        $uri = $uri+"/$($Dag)"
        $Resp = Invoke-WebRequest -Uri $uri -Credential $credential -Method GET
        if ($Resp.StatusCode -eq 200){
            write-host "$Resp"
        }
    }
}

if ($ListDagrun){
    $uri = $uri+"/$($Dag)/dagRuns/$($ListDagrun)"
    $Resp = Invoke-WebRequest -Uri $uri -Credential $credential -Method GET
    if ($Resp.StatusCode -eq 200){
        write-host "$Resp"
    }

}

if ($TriggerDag){
    if ($Dag){
        $uri = $uri+"/$($Dag)/dagRuns"
        $dag_run_id = $($Dag) +"-"+ (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        if ($payload) {
            $payload = @{
                "dag_run_id" = $dag_run_id;
                "conf" = (ConvertFrom-Json $payload);
            } | ConvertTo-Json
        } else {
            $payload = @{
                "dag_run_id" = $dag_run_id;
                "conf" = @{};
            } | ConvertTo-Json
        }
        $Resp = Invoke-WebRequest -Uri $uri -Credential $credential -Method POST -ContentType 'application/json' -Body $payload
        if ($Resp.StatusCode -eq 200){
            write-host "$Resp"
            $startTime = Get-Date
        }
        $timeoutReached = $false
        $status = Invoke-WebRequest -Uri $uri/$dag_run_id -Credential $credential -Method GET | ConvertFrom-Json
        $state = $status.state
        while (($state -eq "running") -or ($state -eq "queued")) {
            Write-Host "$($(Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"))   Waiting for the DAG $Dag to finish running..."
            $currentTime = Get-Date
            $timeTaken = ($currentTime - $startTime).ToString("hh\:mm\:ss")
            if ($timeout -and ($timeTaken -ge $timeout)) {
                Write-Host -NoNewline "Status: " -ForegroundColor White
                Write-Host "Timeout reached. Exiting..." -ForegroundColor Red
                $timeoutReached = $true
                break
            }
            Start-Sleep -Seconds 5
            $status = Invoke-WebRequest -Uri $uri/$dag_run_id -Credential $credential -Method GET | ConvertFrom-Json
            $state = $status.state
        }
        if (!$timeoutReached) {
            $endTime = Get-Date
            $timeTaken = ($endTime - $startTime).ToString("hh\:mm\:ss")
            $status = Invoke-WebRequest -Uri $uri/$dag_run_id -Credential $credential -Method GET
            if ($status.StatusCode -eq 200){
                $statusContent = $status.Content | ConvertFrom-Json
                write-host "Content           : $($statusContent | ConvertTo-Json)"
                $additionalDetails = @{
                    "start_time"  = $startTime.ToString("yyyy-MM-ddTHH:mm:ss");
                    "end_time"    = $endTime.ToString("yyyy-MM-ddTHH:mm:ss");
                    "time_taken"  = $timeTaken;
                    "status"      = $state;
                } | ConvertTo-Json
                Write-Host $additionalDetails
            }
        } else {
            $status = Invoke-WebRequest -Uri $uri/$dag_run_id -Credential $credential -Method GET
            if ($status.StatusCode -eq 200) {
                $statusContent = $status.Content | ConvertFrom-Json
                write-host "Content           : $($statusContent | ConvertTo-Json)"
            }
        }
    }
}
