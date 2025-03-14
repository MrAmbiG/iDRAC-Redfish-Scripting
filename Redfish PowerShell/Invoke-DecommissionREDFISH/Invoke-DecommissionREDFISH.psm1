<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 1.0
Copyright (c) 2024, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>

<#
.Synopsis
   iDRAC cmdlet using Redfish API to run DMTF decommission action. Note this action is only supported on iDRAC10 or newer.
.DESCRIPTION
   iDRAC cmdlet using Redfish API to run DMTF decommission action. Note this action is only supported on iDRAC10 or newer.
   PARAMETERS 
   - idrac_ip: Pass in iDRAC IP address
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC username password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_types: Get supported decommission type values to pass in for POST action. Note: DMTF "All" value will run all supported DMTF types. Note: ManagerConfig DMTF type will also reboot the iDRAC. Note: all OEM types will reboot the iDRAC.
   - decommission: Perform decommission operation. Note arguments dmtf_types or oem_types is also required 
   - dmtf_types: Pass in Decommission DMTF type(s) you want to run for the Decommission action. Note if multiple types are passed in use a comma separator.
   - oem_types: Pass in Decommission OEM type(s) you want to run for the Decommission action. Note if multiple types are passed in use a comma separator.

.EXAMPLE
   Invoke-DecommissionREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_types
   This example will return supported DMTF and OEM Decommission types. 
.EXAMPLE
   Invoke-DecommissionREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -decommission -dmtf_types Logs
   This example shows running Decommission action to clear iDRAC LC and SEL logs. 
.EXAMPLE
   Invoke-DecommissionREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -decommission -dmtf_types ManagerConfig -oem_types DellFwStoreClean
   This example shows running Decommission action to reset iDRAC to default settings and remove non-recovery related firmware packages.
#>

function Invoke-DecommissionREDFISH {

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
    [switch]$get_types,
    [Parameter(Mandatory=$False)]
    [switch]$decommission,
    [Parameter(Mandatory=$False)]
    [string]$dmtf_types,
    [Parameter(Mandatory=$False)]
    [string]$oem_types
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

$global:get_powershell_version = $null

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}
get_powershell_version


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
$get_creds = Get-Credential -Message "Enter iDRAC username and password to run cmdlet"
$global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
}
}

setup_idrac_creds

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


function get_types
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
$1 = "#ComputerSystem.Decommission"
$2 = "DecommissionTypes@Redfish.AllowableValues"
$3 = "OEMDecommissionTypes@Redfish.AllowableValues"
$dmtf_supported_types = $get_content.Actions.$1.$2
$oem_supported_types = $get_content.Actions.$1.$3
Write-Host "`n- Supported Decommission DMTF types`n"
$dmtf_supported_types
Write-Host "`n- Supported Decommission OEM types`n"
$oem_supported_types
}


function run_decommission
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Decommission"
$create_payload = @{"DecommissionTypes"=@(); "OemDecommissionTypes"=@()}
if ($dmtf_types)
{
    if ($dmtf_types.Contains(","))
    {
    $create_payload["DecommissionTypes"] = $dmtf_types.Split(",")
    }
    else
    {
    $create_payload["DecommissionTypes"] += $dmtf_types
    }
}
if ($oem_types)
{
    if ($oem_types.Contains(","))
    {
    $create_payload["OemDecommissionTypes"] = $oem_types.Split(",")
    }
    else
    {
    $create_payload["OemDecommissionTypes"] += $oem_types
    }
}

$JsonBody = $create_payload | ConvertTo-Json -Compress

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
    [String]::Format("`n- PASS, statuscode {0} returned successfully for POST Decommission action",$result1.StatusCode)
}
else
{
    [String]::Format("- FAIL, POST command failed to run Decommission action, statuscode {0} returned",$result1.StatusCode)
    $result1
    return
}

}


# Run cmdlet 

if ($global:iDRAC_version -eq "old")
{
Write-Host "`n- WARNING, iDRAC version detected does not support this cmdlet"
return
}

if ($get_types)
{
get_types
}

elseif ($decommission -and $dmtf_types -or $oem_types)
{
run_decommission
}

else
{
Write-Host "- FAIL, either incorrect parameter(s) used or missing required parameters(s), please see help or examples for more information."
}

}









