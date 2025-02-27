<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 9.0

Copyright (c) 2017, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>

<#
.Synopsis
   iDRAC cmdlet using Redfish API to reset iDRAC to default settings
.DESCRIPTION
   iDRAC cmdlet using Redfish API to reset iDRAC to default settings. Once the action is invoked, iDRAC will reset to defaults and restart the iDRAC. iDRAC should be back up within a couple of minutes.

   PARAMETERS 
   - idrac_ip: Pass in iDRAC IP address
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC username password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_reset_possible_values: Get reset iDRAC possible values
   - reset_value: Pass in string reset value for reset iDRAC. Note: Make sure to pass in the exact string value due to case sensitive

.EXAMPLE
   Set-IdracDefaultSettingsREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -reset_idrac_possible_values 
   This example shows getting possible values for reset iDRAC  
.EXAMPLE
   Set-IdracDefaultSettingsREDFISH -idrac_ip 192.168.0.120 -reset_idrac_possible_values 
   This example will first prompt for iDRAC username/password using Get-Credentials, then get possible values for reset iDRAC
.EXAMPLE
   Set-IdracDefaultSettingsREDFISH -idrac_ip 192.168.0.120 -reset_idrac_possible_values -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708
   This example shows getting possible values for reset iDRAC using iDRAC X-auth token session
.EXAMPLE
   Set-IdracDefaultSettingsREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -reset_value ResetAllWithRootDefaults
   This example shows reset iDRAC to default settings, root user password set to calvin 
#>

function Set-IdracDefaultSettingsREDFISH {


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
    [switch]$reset_idrac_possible_values,
    [Parameter(Mandatory=$False)]
    [string]$reset_value
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
$get_creds = Get-Credential
$global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
}
}

setup_idrac_creds

if ($reset_idrac_possible_values)
{

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
$get_content = $result.Content | ConvertFrom-Json
$reset_to_default_action = "DellManager.v1_0_0#DellManager.ResetToDefaults"
$reset_to_default_possible_values = "ResetType@Redfish.AllowableValues"
Write-Host "`n- Supported possible values for iDRAC reset to defaults action -`n"
$get_content.Actions.Oem.$reset_to_default_action.$reset_to_default_possible_values
Write-Host
return
}



if ($reset_value)
{
$user_choice = Read-Host "`n- INFO, reset iDRAC using '$reset_value' option, are you sure you want to perform this operation? Type 'y' to execute or 'n' to exit: " 
if ($user_choice.ToLower() -eq 'n')
{
return

}

Write-Host "`n- INFO, reset iDRAC to default settings using '$reset_value' option"
$JsonBody = @{'ResetType'= $reset_value} | ConvertTo-Json -Compress

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Actions/Oem/DellManager.ResetToDefaults"
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

if ($result1.StatusCode -eq 200)
{
    [String]::Format("`n- PASS, statuscode {0} returned successfully for POST command to reset iDRAC to default settings",$result1.StatusCode)
    Start-Sleep 15
    
    
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    Exit
}

Write-Host -Foreground Yellow "`n- INFO, iDRAC will now reset to default settings and restart the iDRAC. iDRAC should be back up within a few minutes.`n" 
}
}



