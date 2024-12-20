<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 7.0

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
   iDRAC cmdlet using Redfish API to get iDRAC power information for the server. 
.DESCRIPTION
   iDRAC cmdlet using Redfish API to get iDRAC power information for the server. Cmdlet will support getting either all iDRAC server power information or selective information based off argument value passed in.

   Supported parameters to pass in for cmdlet:
   
   - idrac_ip: Pass in iDRAC IP
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_all_power_info: Pass in a value of "y"
   - get_specific_power_info: Pass in "1" for Power Control, "2" for Power Supply, "3" for Power Redundancy and "4" for Power Voltage
   
.EXAMPLE
   Invoke-GetIdracServerPowerInformationREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_all_power_info 
   This example will pull all iDRAC power information which includes Power Control, Power Supplies, Power Redundancy and Power Voltages
.EXAMPLE
   Invoke-GetIdracServerPowerInformationREDFISH -idrac_ip 192.168.0.120 -get_all_power_info  
   This example will first prompt for iDRAc username/password using Get-Credential, then pull all iDRAC power information which includes Power Control, Power Supplies, Power Redundancy and Power Voltages
.EXAMPLE
   Invoke-GetIdracServerPowerInformationREDFISH -idrac_ip 192.168.0.120 -get_all_power_info -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708
   This example will pull all iDRAC power information which includes Power Control, Power Supplies, Power Redundancy and Power Voltages using iDRAC X-Auth token session
.EXAMPLE
   Invoke-GetIdracServerPowerInformationREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_specific_power_info 2 
   This example will return only iDRAC Power Supply information.
#>

function Invoke-GetIdracServerPowerInformationREDFISH {

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
    [switch]$get_all_power_info,
    [ValidateSet(1,2,3,4)]
    [Parameter(Mandatory=$False)]
    [string]$get_specific_power_info
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

# Function to get Powershell version

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
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


# Get PSU information

function get_all_power_info
{

$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/Power"
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
$content = $get_result.Content | ConvertFrom-Json

$power_control = $content.PowerControl
$power_supplies = $content.PowerSupplies
$power_redundancy = $content.Redundancy
$power_voltage = $content.Voltages 
[String]::Format("`n--- Power Control Details ---`n")
$power_control
[String]::Format("`n--- Power Supply Details ---`n")
$power_supplies
[String]::Format("`n--- Power Redundancy Details ---`n")
$power_redundancy
[String]::Format("`n--- Power Voltage Details ---`n")
$power_voltage

}

}


function get_specific_power_info

{

$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/Power"
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
$content = $get_result.Content | ConvertFrom-Json

$power_control = $content.PowerControl
$power_supplies = $content.PowerSupplies
$power_redundancy = $content.Redundancy
$power_voltage = $content.Voltages 

if ($get_specific_power_info -eq "1")
{
[String]::Format("`n--- Power Control Details ---`n")
if ($power_control.Count -gt 0)
{
$power_control
}
else
{
Write-Host "- INFO, no data detected for power control"
}
}

elseif ($get_specific_power_info -eq "2")
{
[String]::Format("`n--- Power Supply Details ---`n")
if ($power_supplies.Count -gt 0)
{
$power_supplies
}
else
{
Write-Host "- INFO, no data detected for power supplies"
}
}

elseif ($get_specific_power_info -eq "3")
{
[String]::Format("`n--- Power Redundancy Details ---`n")
if ($power_redundancy.Count -gt 0)
{
$power_redundancy
}
else
{
Write-Host "- INFO, no data detected for power redundancy"
}
}

elseif ($get_specific_power_info -eq "4")
{
[String]::Format("`n--- Power Voltage Details ---`n")
if ($power_voltage.Count -gt 0)
{
$power_voltage
}
else
{
Write-Host "- INFO, no data detected for power voltage"
}
}

else
{
[String]::Format("`n- FAIL, invalid value passed in for argument get_specific_power_info")
}

}

}


# Run cmdlet

get_powershell_version 
setup_idrac_creds


if ($get_all_power_info)
{
get_all_power_info
}
elseif ($get_specific_power_info)
{
get_specific_power_info
}


}










