<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 4.0

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
   iDRAC cmdlet using Redfish API to either get current iDRAC certs or replace certificate for iDRAC.
.DESCRIPTION
   iDRAC cmdlet using Redfish API to either get current iDRAC certs or replace certificate for iDRAC.

   Supported parameters to pass in for cmdlet:
   
   - idrac_ip: Pass in iDRAC IP
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_certs: Get current iDRAC certs
   - replace_cert_id: Replace cert, pass in the cert id.
   - replace_cert_filename: Replace cert, pass in the signed cert filename
   - reset_idrac: Reset iDRAC for new cert to get applied. Note: Starting in iDRAC9 6.00.02, iDRAC reset is no longer required after uploading new cert, cert will noe get applied immediately. 

.EXAMPLE
   Invoke-ReplaceCertificateREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_certs 
   # This example will get current iDRAC certs.
.EXAMPLE
   Invoke-ReplaceCertifiateREDFISH -idrac_ip 192.168.0.120 -get_certs 
   # This example will first prompt for iDRAC username/password using Get-Credential, then get current iDRAC certs. 
.EXAMPLE
   Invoke-ReplaceCertificateREDFISH -idrac_ip 192.168.0.120 -get_certs -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708
   # This example using iDRAC X-auth token session will get current iDRAC certs. 
.EXAMPLE
   Invoke-ReplaceCertifiateREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -replace_cert_id "SecurityCertificate.1" -replace_cert_filename signed.cer
   # This example will replace certificate 'SecurityCertificate.1'
.EXAMPLE
   Invoke-ReplaceCertifiateREDFISH -idrac_ip 192.168.0.120 -reset_idrac
   # This example will first prompt for iDRAC username/password using Get-Credential, then reset iDRAC.
#>

function Invoke-ReplaceCertificateREDFISH {

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
    [switch]$get_certs,
    [Parameter(Mandatory=$False)]
    [string]$replace_cert_id,
    [Parameter(Mandatory=$False)]
    [string]$replace_cert_filename,
    [Parameter(Mandatory=$False)]
    [switch]$reset_idrac
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

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}

# Get current iDRAC certs

function get_current_iDRAC_certs
{

Write-Host "`n- Current iDRAC certs for $idrac_ip -`n"
$expand_query ='?$expand=*($levels=1)'
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/NetworkProtocol/HTTPS/Certificates$expand_query"
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

if ($result.StatusCode -eq 200 -or $result.StatusCode -eq 202)
{
#pass
}
else
{
Write-Host "- FAIL, GET request failed to get current iDRAC certs, status code"
}

$get_result = $result.Content | ConvertFrom-Json
$get_result.Members
}




# replace iDRAC Cert

function replace_cert
{
Write-Host "`n- INFO, replacing certificate for iDRAC $idrac_ip"
$get_cert_content = Get-Content $replace_cert_filename -Raw
$get_cert_content = [string]$get_cert_content
$JsonBody = @{"CertificateType"="PEM";"CertificateUri"=@{"@odata.id"="/redfish/v1/Managers/iDRAC.Embedded.1/NetworkProtocol/HTTPS/Certificates/$replace_cert_id"};"CertificateString" = $get_cert_content}
$JsonBody = $JsonBody | ConvertTo-Json -Compress
$uri = "https://$idrac_ip/redfish/v1/CertificateService/Actions/CertificateService.ReplaceCertificate"

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

if ($post_result.StatusCode -eq 202)
{
Write-Host "- PASS, POST command passed to replace signed cert, status code 202 returned"
Write-Host "`n- INFO, Reset iDRAC to apply the pending new certificate. Until iDRAC is reset the old certificate will still be active"
}
else
{
[String]::Format("- FAIL, POST command failed to replace signed cert, statuscode {0} returned. Detail error message: {1}",$post_result.StatusCode, $post_result)
return
}
}

function reset_idrac
{
$JsonBody = @{"ResetType"="GracefulRestart"}
$JsonBody = $JsonBody | ConvertTo-Json -Compress
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Actions/Manager.Reset"

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

if ($post_result.StatusCode -eq 204)
{
Write-Host "`n- PASS, POST command passed to reset iDRAC. iDRAC will be back up within a few minutes"
}
else
{
[String]::Format("- FAIL, POST command failed to reset iDRAC, statuscode {0} returned. Detail error message: {1}",$post_result.StatusCode, $post_result)
return
}

}
# Run cmdlet

get_powershell_version 
setup_idrac_creds

# Check to validate iDRAC version detected supports this feature

$uri = "https://$idrac_ip/redfish/v1/CertificateService"
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

if ($result.StatusCode -eq 200 -or $result.StatusCode -eq 202)
{
$get_actions = $result.Content | ConvertFrom-Json
$action_name = "#CertificateService.ReplaceCertificate"
$validate_supported_idrac = $get_actions.Actions.$action_name
    try
    {
    $test = $validate_supported_idrac.GetType()
    }
    catch
    {
    Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API or incorrect iDRAC user credentials passed in.`n"
    return
    }
}
else
{
$status_code = $result.StatusCode
Write-Host "`n- FAIL, status code $status_code returned for GET request to validate iDRAC connection.`n"
return
}

if ($get_certs)
{
get_current_iDRAC_certs
}
elseif ($replace_cert_id -and $replace_cert_filename)
{
replace_cert
}
elseif ($reset_idrac)
{
reset_idrac
}
else
{
Write-Host "- WARNING, either missing or incorrect arguments detected"
}


}









