<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 6.0

Copyright (c) 2021, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>

<#
.Synopsis
   iDRAC cmdlet using Redfish DMTF to perform firmware rollback for supported devices.
.DESCRIPTION
   iDRAC cmdlet using Redfish DMTF to perform firmware rollback for supported devices. 

   Supported parameters to pass in for cmdlet:
   
   - idrac_ip: Pass in iDRAC IP
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - view_fw_inventory_only: Get current firmware inventory for all devices. 
   - get_rollback_devices: Get current supported devices for rollback support. NOTE: If you don't see a device listed, this means either rollback is not supported or there is no N-1 image stored in the iDRAC for this device. For supported devices for rollback support, check iDRAC user guide.
   - rollback_uri: Pass in the complete PREVIOUS URI for the device you want to rollback the firmware. 
   - reboot_server: Pass in "y" to automatically reboot the server to apply the update or "n" to not reboot the server. Passing in "n" means the update job will still get scheduled and will execute on next server manual reboot. NOTE: There are devices which perform an update immediately and devices that need a reboot to apply the update. For more details on this behavior, refer to Lifecycle Controller User Guide update section.

.EXAMPLE
   Set -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -view_fw_inventory_only 
   This example will only return Firmware inventory for all devices in the server.
.EXAMPLE
   Set -idrac_ip 192.168.0.120 -view_fw_inventory_only 
   This example will first prompt for iDRAC username/password using Get-Credential, then return Firmware inventory for all devices in the server.
.EXAMPLE
   Set -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_rollback_devices 
   This example will return only supported rollback devices detected using iDRAC X-Auth token session. 
.EXAMPLE
   Set -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -rollback_uri "/redfish/v1/UpdateService/FirmwareInventory/Previous-159-2.11.2__BIOS.Setup.1-1" -reboot_server y
   This example will reboot the server now to rollback BIOS fimrware. 
#>

function Set-DeviceFirmwareRollbackREDFISH {

# Required, optional parameters needed to be passed in when cmdlet is executed

param(
    [Parameter(Mandatory=$True)]
    [string]$idrac_ip,
    [Parameter(Mandatory=$False)]
    [string]$idrac_username,
    [Parameter(Mandatory=$False)]
    [string]$idrac_password,
    [Parameter(Mandatory=$False)]
    [string]$x_auth_token,
    [Parameter(Mandatory=$False)]
    [switch]$view_fw_inventory_only,
    [Parameter(Mandatory=$False)]
    [switch]$get_rollback_devices,
    [Parameter(Mandatory=$False)]
    [string]$rollback_uri,
    [ValidateSet("y", "n")]
    [Parameter(Mandatory=$False)]
    [string]$reboot_server
    )


# Function to ignore SSL certs

function Ignore-SSLCertificates
{
    $Provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $Compiler = $Provider.CreateCompiler()
    $Params = New-Object System.CodeDom.Compiler.CompilerParameters
    $Params.GenerateExecutable = $false
    $Params.GenerateInMemory = $true
    $Params.IncludeDebugInformation = $false
    $Params.ReferencedAssemblies.Add("System.DLL") > $null
    $TASource=@'
        namespace Local.ToolkitExtensions.Net.CertificatePolicy
        {
            public class TrustAll : System.Net.ICertificatePolicy
            {
                public bool CheckValidationResult(System.Net.ServicePoint sp,System.Security.Cryptography.X509Certificates.X509Certificate cert, System.Net.WebRequest req, int problem)
                {
                    return true;
                }
            }
        }
'@ 
    $TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
    $TAAssembly=$TAResults.CompiledAssembly
    $TrustAll = $TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
    [System.Net.ServicePointManager]::CertificatePolicy = $TrustAll
}

# Function to set up iDRAC credentials 

function setup_idrac_creds
{

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12

if ($x_auth_token)
{
$global:x_auth_token = $x_auth_token
}
elseif ($idrac_username -and $idrac_password)
{
$user = $idrac_username
$pass= $idrac_password
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$global:credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)
}
else
{
$get_creds = Get-Credential
$global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
}
}


# Function to get Powershell Version

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}


# Function get current firmware versions

function get_firmware_versions
{
Write-Host
Write-Host "--- Getting Firmware Inventory For iDRAC $idrac_ip ---"
Write-Host

$expand_query ='?$expand=*($levels=1)'
$uri = "https://$idrac_ip/redfish/v1/UpdateService/FirmwareInventory$expand_query"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}
    $get_fw_inventory = $result.Content | ConvertFrom-Json
    $get_fw_inventory.Members
    break
}



# Function to get rollback devices 

function get_rollback_devices
{
$uri = "https://$idrac_ip/redfish/v1/UpdateService/FirmwareInventory"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $get_result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $get_result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $get_result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $get_result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

Write-Host "`n- Supported Rollback Devices -`n"
$get_content = $get_result.Content | ConvertFrom-Json
foreach ($item in $get_content.Members)
{
$item=[string]$item
if ($item.Contains("Previous"))
{
$item.Split("=")[-1].Replace("}","")
}    
}
Write-Host
return
}


# Function Install rollback image, query job status, reboot server if requested

function rollback_image_query_job_status_reboot_server

{

Write-Host "`n- INFO, creating rollback job ID for URI '$rollback_uri'"
$uri = "https://$idrac_ip/redfish/v1/UpdateService/Actions/UpdateService.SimpleUpdate"
$JsonBody = @{'ImageURI'= $rollback_uri} | ConvertTo-Json -Compress
if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}
 
if ($result1.StatusCode -eq 202)
{
    $job_id_search=$result1.Headers['Location']
    $job_id=$job_id_search.Split("/")[-1]
    [String]::Format("`n- PASS, statuscode {0} returned successfully for POST command to create update job ID '{1}'",$result1.StatusCode, $job_id)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned. Detail error message: {1}",$result1.StatusCode,$result1)
    break
}

# Loop job status until marked completed or scheduled 

$get_time_old=Get-Date -DisplayHint Time
$start_time = Get-Date
$end_time = $start_time.AddMinutes(30)
$force_count=0
Write-Host "- INFO, script will now loop polling the job status every 5 seconds until marked either scheduled or completed`n"
while ($true)
{
$loop_time = Get-Date
$uri ="https://$idrac_ip/redfish/v1/TaskService/Tasks/$job_id"

if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

$overall_job_output=$result.Content | ConvertFrom-Json
if ($overall_job_output.Messages.Message.Contains("Fail") -or $overall_job_output.Messages.Message.Contains("Failed") -or $overall_job_output.Messages.Message.Contains("fail") -or $overall_job_output.Messages.Message.Contains("failed") -or $overall_job_output.Messages.Message.Contains("Job for this device is already present") -or $overall_job_output.Messages.Message.Contains("Unable") -or $overall_job_output.Messages.Message.Contains("unable"))
{
Write-Host
[String]::Format("- FAIL, job id $job_id marked as failed, error message: {0}",$overall_job_output.Messages.Message)
break
}
elseif ($loop_time -gt $end_time)
{
Write-Host "- FAIL, timeout of 30 minutes has been reached before marking the job completed"
break
}

elseif ($overall_job_output.Messages.Message -eq "Task successfully scheduled.")
{
Write-Host "`n- PASS, job ID '$job_id' successfully marked as scheduled"
$job_completed = "no"
break
}
elseif ($overall_job_output.Messages.Message -eq "The specified job has completed successfully." -or $overall_job_output.Messages.Message -eq  "Job completed successfully." -or $overall_job_output.Messages.Message.Contains("complete"))
{
$get_current_time=Get-Date -DisplayHint Time
$final_time=$get_current_time-$get_time_old
$final_completion_time=$final_time | select Minutes,Seconds
Write-Host "`n- PASS, job ID '$job_id' successfully marked as completed"
Write-Host "`nRollback firmware job execution time:"
$final_completion_time
return
}
else
{
Write-Host "- Job ID '$job_id' not marked scheduled or completed, checking job status again"
Start-Sleep 5
}

}


if ($reboot_server.ToLower() -eq "n")
{
Write-Host "- INFO, user selected to not automatically reboot the server. Rollback job is scheduled and will execute on next server manual reboot"
return
}

elseif ($reboot_server.ToLower() -eq "y")
{
Write-Host "- INFO, user selected to reboot the server now to rollback device firmware."
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

if ($result.StatusCode -eq 200)
{
    [String]::Format("- PASS, statuscode {0} returned successfully to get current power state",$result.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result.StatusCode)
    break
}

$result_output = $result.Content | ConvertFrom-Json
$power_state = $result_output.PowerState

if ($power_state -eq "On")
{
Write-Host "- INFO, Server current power state is ON, performing graceful shutdown"



$JsonBody = @{ "ResetType" = "GracefulShutdown"
    } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned to attempt graceful server shutdown",$result1.StatusCode)
    Start-Sleep 15
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    break
}

$count = 1
while($true)
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

$result_output = $result.Content | ConvertFrom-Json
$power_state = $result_output.PowerState

if ($power_state -eq "Off")
{
Write-Host "- PASS, validated server in OFF state"
break
}
elseif ($count -eq 5)
{
Write-Host "- INFO, server did not accept graceful shutdown request, performing force off"

$JsonBody = @{ "ResetType" = "ForceOff"
    } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned to force power OFF the server",$result1.StatusCode)
    Start-Sleep 15
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    break
}

}
else
{
Write-Host "- INFO, server still in ON state waiting for graceful shutdown to complete, will check server status again in 1 minute"
$count++
Start-Sleep 60
continue
}
}

$JsonBody = @{ "ResetType" = "On"
    } | ConvertTo-Json -Compress

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned successfully to power ON the server",$result1.StatusCode)
    $power_state = "On"
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    break
}
}


if ($power_state -eq "Off")
{
$JsonBody = @{ "ResetType" = "On"
    } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"

# POST command to power ON the server

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned successfully to power ON the server",$result1.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    break
}
}
}

else
{
Write-Host "- WARNING, either missing or incorrect value passed in for reboot_server argument. Job ID is scheduled and will execute on next server manual reboot"
return 
}

# Loop job status until marked completed 

$get_time_old=Get-Date -DisplayHint Time
$start_time = Get-Date
$end_time = $start_time.AddMinutes(50)
$force_count=0
Write-Host "- INFO, script will now loop polling the job status every 30 seconds until marked completed`n"
while ($true)
{
$loop_time = Get-Date
$uri ="https://$idrac_ip/redfish/v1/TaskService/Tasks/$job_id"

if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

$overall_job_output=$result.Content | ConvertFrom-Json

if ($overall_job_output.Messages.Message.Contains("Fail") -or $overall_job_output.Messages.Message.Contains("Failed") -or $overall_job_output.Messages.Message.Contains("fail") -or $overall_job_output.Messages.Message.Contains("failed"))
{
Write-Host
[String]::Format("- FAIL, job id $job_id marked as failed, error message: {0}",$overall_job_output.Messages.Message)
break
}
elseif ($loop_time -gt $end_time)
{
Write-Host "- FAIL, timeout of 50 minutes has been reached before marking the job completed"
break
}
elseif ($overall_job_output.Messages.Message -eq "The specified job has completed successfully." -or $overall_job_output.Messages.Message -eq  "Job completed successfully." -or $overall_job_output.Messages.Message.Contains("complete"))
{
$get_current_time=Get-Date -DisplayHint Time
$final_time=$get_current_time-$get_time_old
$final_completion_time=$final_time | select Minutes,Seconds
Write-Host "`n- PASS, job ID '$job_id' successfully marked as completed"
Write-Host "`nRollback Firmware job execution time:"
$final_completion_time
break
}
else
{
Write-Host "- Job ID '$job_id' not marked completed, checking job status again"
Start-Sleep 30
}

}


}

# Run cmdlet

get_powershell_version
setup_idrac_creds

# Code to check for supported iDRAC version installed

$query_parameter = "?`$expand=*(`$levels=1)" 
$uri = "https://$idrac_ip/redfish/v1/UpdateService/FirmwareInventory$query_parameter"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $get_result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $get_result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $get_result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $get_result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}
if ($get_result.StatusCode -eq 200 -or $result.StatusCode -eq 202)
{
}
else
{
Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API or incorrect iDRAC user credentials passed in.`n"
$get_result
return
}


if ($view_fw_inventory_only)
{
get_firmware_versions
}

elseif ($get_rollback_devices)
{
get_rollback_devices
}

elseif ($rollback_uri)
{
rollback_image_query_job_status_reboot_server
}

else
{
Write-Host "- FAIL, either incorrect parameter(s) used or missing required parameters(s)"
}

}









