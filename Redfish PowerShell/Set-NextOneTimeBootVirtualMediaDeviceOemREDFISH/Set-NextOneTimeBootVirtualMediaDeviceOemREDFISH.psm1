<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 8.0

Copyright (c) 2020, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>

<#
.Synopsis
  iDRAC cmdlet using Redfish API with OEM extension to set next onetime boot device to either virtual optical or virtual floppy.
.DESCRIPTION
   iDRAC cmdlet using Redfish API with OEM extension to set next onetime boot device to either virtual optical or virtual floppy. DMTF doesn't support setting virtual CD or virtual floppy as next one time boot. This cmdlet uses OEM extension to solve this issue.
   - idrac_ip: Pass in iDRAC IP address, REQUIRED
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC username password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - next_onetime_boot_device: Set next onetime boot device. Pass in '1' for virtual CD or '2' for virtual floppy
   - reboot_server: Pass in 'y' to reboot the server now to boot to onetime boot device or 'n' to not reboot the server. Passing in 'n' will still set next onetime boot device which will happen on next server manual reboot.
.EXAMPLE
   Set-NextOneTimeBootVirtualMediaDeviceOemREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -next_onetime_boot_device 1 -reboot_server y
   This example will set next onetime boot device to virtual CD and reboot the server now
.EXAMPLE
   Set-NextOneTimeBootVirtualMediaDeviceOemREDFISH -idrac_ip 192.168.0.120 -next_onetime_boot_device 1 -reboot_server y
   This example will first prompt for iDRAC username/password using Get-Credentials, then set next onetime boot device to virtual CD and reboot the server now
.EXAMPLE
   Set-NextOneTimeBootVirtualMediaDeviceOemREDFISH -idrac_ip 192.168.0.120 -next_onetime_boot_device 1 -reboot_server y -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708
   This example will set next onetime boot device to virtual CD and reboot the server now using iDRAC X-auth token session
.EXAMPLE
   Set-NextOneTimeBootVirtualMediaDeviceOemREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -next_onetime_boot_device 2 -reboot_server n
   This example will set next onetime boot device to virtual floppy and not reboot the server. Set onetime boot device is still set and will boot to this device on next manual reboot.
#>

function Set-NextOneTimeBootVirtualMediaDeviceOemREDFISH {

param(
    [Parameter(Mandatory=$True)]
    $idrac_ip,
    [Parameter(Mandatory=$False)]
    $idrac_username,
    [Parameter(Mandatory=$False)]
    $idrac_password,
    [Parameter(Mandatory=$False)]
    [string]$x_auth_token,
    [ValidateSet(1, 2)]
    [Parameter(Mandatory=$True)]
    [string]$next_onetime_boot_device,
    [ValidateSet("y", "n")]
    [Parameter(Mandatory=$True)]
    [string]$reboot_server
    )


# Function to igonre SSL certs

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

# Function to get Powershell version

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}

get_powershell_version

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

# Function to get iDRAC version

function get_iDRAC_version
{

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1?`$select=Model"


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
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
if ($get_content.Model.Contains("12G") -or $get_content.Model.Contains("13G") -or $get_content.Model.Contains("14G") -or $get_content.Model.Contains("15G") -or $get_content.Model.Contains("16G"))
{
$global:iDRAC_version = "old"
}
else
{
$global:iDRAC_version = "new"
}
}
get_iDRAC_version

# function to reboot server 

function reboot_server
{

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1"
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
$get_content = $result.Content | ConvertFrom-Json
$host_power_state = $get_content.PowerState

if ($host_power_state -eq "On")
{
Write-Host "- INFO, server power state ON, performing graceful shutdown"
$JsonBody = @{ "ResetType" = "GracefulShutdown" } | ConvertTo-Json -Compress


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
    [String]::Format("- PASS, statuscode {0} returned to gracefully shutdown the server",$result1.StatusCode)
    Start-Sleep 15
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    return
}

Start-Sleep 10
$count = 1
while ($true)
{

if ($count -eq 5)
{
Write-Host "- FAIL, retry count to validate graceful shutdown has been hit. Server will now perform a force off."
$JsonBody = @{ "ResetType" = "ForceOff" } | ConvertTo-Json -Compress


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
    [String]::Format("- PASS, statuscode {0} returned to force off the server",$result1.StatusCode)
    Start-Sleep 15
    break
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned to force off the server",$result1.StatusCode)
    return
}
}

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1"
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
$get_content = $result.Content | ConvertFrom-Json
$host_power_state = $get_content.PowerState

if ($host_power_state -eq "Off")
{
Write-Host "- PASS, verified server is in OFF state"
$host_power_state = ""
break
}
else
{
Write-Host "- INFO, server still in ON state waiting for graceful shutdown to complete, polling power status again"
Start-Sleep 15
$count++
}

}

$JsonBody = @{ "ResetType" = "On" } | ConvertTo-Json -Compress
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
    Write-Host
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    return
}
}

if ($host_power_state -eq "Off")
{
Write-Host "- INFO, server power state OFF, performing power ON operation"
$JsonBody = @{ "ResetType" = "On" } | ConvertTo-Json -Compress


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
    Start-Sleep 10
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    return
}

Start-Sleep 10
}

}

# Function to set next onetime boot device 

function set_next_onetime_boot_OEM 
{

    if ($next_onetime_boot_device -eq "1")
    {
    Write-Host "`n- INFO, setting next one time boot device to Virtual CD"
    $JsonBody = @{"ShareParameters"=@{"Target"=@("All")};"ImportBuffer"="<SystemConfiguration><Component FQDD='iDRAC.Embedded.1'><Attribute Name='ServerBoot.1#BootOnce'>Enabled</Attribute><Attribute Name='ServerBoot.1#FirstBootDevice'>VCD-DVD</Attribute></Component></SystemConfiguration>"} | ConvertTo-Json -Compress
    }
    elseif ($next_onetime_boot_device -eq "2")
    {
    Write-Host "`n- INFO, setting next one time boot device to Virtual Floppy"
    $JsonBody = @{"ShareParameters"=@{"Target"=@("All")};"ImportBuffer"="<SystemConfiguration><Component FQDD='iDRAC.Embedded.1'><Attribute Name='ServerBoot.1#BootOnce'>Enabled</Attribute><Attribute Name='ServerBoot.1#FirstBootDevice'>vFDD</Attribute></Component></SystemConfiguration>"} | ConvertTo-Json -Compress
    }
    else
    {
    Write-Host "- FAIL, invalid value passed in for 'next_onetime_boot_device' parameter"
    return
    }

if ($global:iDRAC_version -eq "old")
{
$full_method_name="EID_674_Manager."+"ImportSystemConfiguration"
}
else
{
$full_method_name="OemManager."+"ImportSystemConfiguration"
}
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Actions/Oem/$full_method_name"

# POST command to import server configuration profile file

   if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $post_result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $post_result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
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
    
    $post_result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $post_result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}
$raw_content=$post_result.RawContent | ConvertTo-Json
$find_jobID=[regex]::Match($raw_content, "JID_.+?r").captures.groups[0].value
$job_id=$find_jobID.Replace("\r","")

    if ($post_result.StatusCode -eq 202)
    {
    Write-Host
    [String]::Format("- PASS, statuscode {0} returned to successfully create Server Configuration Profile(SCP) import job: {1}",$post_result.StatusCode,$job_id)
    Write-Host
    }
    else
    {
    [String]::Format("- FAIL, statuscode {0} returned",$post_result.StatusCode)
    return
    }

$get_time_old=Get-Date -DisplayHint Time
$start_time = Get-Date
$end_time = $start_time.AddMinutes(30)

while ($true)
{
$loop_time = Get-Date
$uri ="https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/$job_id"
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

if ($overall_job_output.Message -eq "Successfully imported and applied Server Configuration Profile.")
{
Write-Host "- PASS, job ID '$job_id' successfully marked completed to set next onetime boot device"
    if ($reboot_server.ToLower() -eq "y")
    {
    Write-Host "- INFO, user selected to automaticaly reboot the server now to boot to onetime boot device"
    reboot_server
    }
    elseif ($reboot_server.ToLower() -eq "n")
    {
    Write-Host "- INFO, user selected to not automatically reboot the server. Onetime boot device is still set and will boot to this device on next manual reboot"
    }
    return
    }

elseif ($overall_job_output.Message.Contains("Fail") -or $overall_job_output.Message.Contains("fail") -or $overall_job_output.Message.Contains("Unable") -or $overall_job_output.Message.Contains("unable")) 
{
Write-Host
[String]::Format("- FAIL, final job status is: {0}",$overall_job_status.JobState)
Return
}

elseif ($loop_time -gt $end_time)
{
Write-Host "- FAIL, timeout of 30 minutes has been reached before marking the job completed"
return
}

elseif ($overall_job_output.Message -eq "Import of Server Configuration Profile operation completed with errors." -or $overall_job_output.Message -eq "Unable to complete application of configuration profile values.") 
{
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


Write-Host "- WARNING, failure detected for import job id '$job_id'. Check 'Messages' property below for more information on the failure."
$result.Content | ConvertFrom-Json
return
}

elseif ($overall_job_output.Message -eq "No changes were applied since the current component configuration matched the requested configuration.")
{
Write-Host "- INFO, import job id '$job_id' completed. No changes were applied since the current component configuration matched the requested configuration. Check iDRAC settings to see if next onetime boot device is already set."
return
}


Write-Host "- INFO, job ID '$job_id' not marked completed, checking job status again"
Start-Sleep 1
}

}

# run code

get_powershell_version
setup_idrac_creds

# Check to validate iDRAC version detected supports this feature

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1"
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

if ($get_result.StatusCode -eq 200 -or $result.StatusCode -eq 202)
{
$get_actions = $get_result.Content | ConvertFrom-Json
$scp_import_action = "OemManager.v1_0_0#OemManager.ImportSystemConfiguration"
try
{
$test = $get_actions.Actions.Oem.$scp_import_action.target.GetType()
}
catch
{
Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API or incorrect iDRAC user credentials passed in.`n"
return
}
}

set_next_onetime_boot_OEM 

}






