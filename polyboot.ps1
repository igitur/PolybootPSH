# ----------------------------------------------------------------------------------------------------------------------
# Polyboot
# ========
# A simple program to reboot or factory-reset Polycom phones using CURL commands to interact with the phone's web UI.
# Adjust the authentication password below accordingly.
#
# Usage
# ~~~~~
# ./polyboot.ps1 (-SingleHost / -Filename) (ip address / file) (reboot / factory) (admin PW)
#
# Reboot (single phone /IP):        polyboot.ps1 -SingleHost 127.0.0.1 -Action reboot -Password 1234
# Factory Reset (single IP):        polyboot.ps1 -SingleHost 127.0.0.1 -Action factory -Password 1234
#
# Reboot (IP list, one per line):   polyboot.ps1 -Filename iplist.txt -Action reboot -Password 1234
# Factory Reset (IP list):          polyboot.ps1 -Filename iplist.txt -Action factory -Password 1234
# ----------------------------------------------------------------------------------------------------------------------

#Declare our named parameters here...
param(
    [string] $Action,
    [string] $SingleHost,
    [string] $Filename,
    [string] $Password
)

# --[ Configure these to your liking ] ---------------------------------------------------------------------------------
# Timeout between connections for a list of addresses
$timeout = 0.5

# Number of phones in a list to process before pausing (to allow server to catch up with registrations etc)
$batch_size = 40

# Pause duration after each batch
$batch_timeout = 60
# -----------------------------------------------------------------------------------------------------------------------

# Auth string glued in front of password
$auth_username = "Polycom"

# Help text
$help = "Usage:
------
polyboot.ps1 (-Filename [ip address file] or -SingleHost [single IP address]) -Action [reboot / factory] -Password (admin pw)
ex.: polyboot.ps1 -SingleHost 127.0.0.1 -Action reboot -Password 456
"

# Rebooting the phone
function Reboot ([string]$ip, [string] $password) {
    $encodedText = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($password))
         
    Invoke-WebRequest -Uri "https://$ip/form-submit/Reboot" -Method "POST" -Verbose -Headers @{
        "Authorization"  = "Basic $encodedText"; 
        "Content-Length" = "0";
        "Content-Type"   = "application/x-www-form-urlencoded";
        "Cookie"         = "Authorization=Basic $encodedText"
    }

    return    
}

# Factory-resetting the phone
function FactoryReset ([string]$ip, [string] $password) {
    $encodedText = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($password))

    Invoke-WebRequest -Uri "https://$ip/form-submit/Utilities/restorePhoneToFactory" -Method "POST" -Headers @{
        "Authorization"  = "Basic $encodedText"; 
        "Content-Length" = "0";
        "Content-Type"   = "application/x-www-form-urlencoded";
        "Cookie"         = "Authorization=Basic $encodedText"
    }

    return    
}

add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } ;

if ($Filename -ne $null -and $Filename.Length -gt 0) {
    # Multi-address (file) mode
    $admin_password = $auth_username + ":" + $Password
    try {
        $index = 0
        foreach ($line in Get-Content $Filename) {
            $ip = $line.Trim()
            if ($ip.Length -gt 0) {
                if ($Action -eq "reboot") {
                    Reboot -ip $ip -password $admin_password
                    Write-Host "Reboot instruction sent to address: $ip."
                    Start-Sleep -Seconds $timeout
                    $index++
                    if ($index % $batch_size -eq 0 -and $index -gt 1) {
                        Write-Host "Pausing for $batch_timeout seconds between batches."
                        Start-Sleep -Seconds $batch_timeout
                    }
                }
                elseif ($Action -eq "factory") {
                    FactoryReset -ip $ip -password $admin_password
                    Write-Host "Factory reset instruction sent to address: $ip."
                    Start-Sleep -Seconds $timeout
                    if ($index % $batch_size -eq 0 -and $index -gt 1) {
                        Write-Host "Pausing for '$batch_timeout seconds between batches."
                        Start-Sleep -Seconds $batch_timeout            
                    }        
                }
                else {
                    Write-Host "ERROR: $Action is an invalid action flag."
                    Write-Host $help
                    break                    
                }                    
            }
        }        
    }
    catch {
        Write-Host "ERROR: File couldn't be opened."
        Write-Host $_.Exception.Message
        Write-Host $_.Exception.StackTrace        
    }
}
elseif ($SingleHost -ne $null -and $SingleHost.Length -gt 0) {
    # Single-IP mode
    $admin_password = $auth_username + ":" + $Password
    if ($Action -eq "reboot") {
        Reboot -ip $SingleHost -password $admin_password
        Write-Host "Reboot instruction sent to address: $SingleHost"
        
    }
    elseif ($Action -eq "factory") {
        FactoryReset -ip $SingleHost -password $admin_password
        Write-Host "Factory reset instruction sent to address: $SingleHost"        
    }

    else {
        Write-Host "ERROR: $Action is an invalid action flag.')"
        Write-Host $help        
    }
}
else {
    Write-Host "Unknown mode. Use either -SingleHost or -Filename."
    Write-Host $help
}