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
   iDRAC cmdlet using Redfish API with OEM extension to launch iDRAC HTML KVM session using your default browser..
.DESCRIPTION
   iDRAC Cmdlet using Redfish API with OEM extension to to launch iDRAC HTML KVM session using your default browser.

   Supported parameters to pass in for cmdlet:
   
   - idrac_ip: Pass in iDRAC IP
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended) NOTE: For only this cmdlet, you still need to pass in idrac_username agrument. This is needed to create the temp URI to launch KVM session.
   
.EXAMPLE
   Invoke-IdracRemoteKvmHtmlSessionREDFISH -idrac_ip 192.168.0.120
   This example will first prompt for iDRAC username and password using Get-Credentials, then launch iDRAC KVM session using your default browser.
.EXAMPLE
   Invoke-IdracRemoteKvmHtmlSessionREDFISH -idrac_ip 192.168.0.120 -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708 -idrac_username root
   This example using iDRAC X-auth token session will launch iDRAC KVM session using your default browser. 
#>

function Invoke-IdracRemoteKvmHtmlSessionREDFISH {

param(
    [Parameter(Mandatory=$True)]
    [string]$idrac_ip,
    [Parameter(Mandatory=$False)]
    [string]$idrac_username,
    [Parameter(Mandatory=$False)]
    [string]$idrac_password,
    [Parameter(Mandatory=$False)]
    [string]$x_auth_token
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
$global:get_creds_username = $get_creds.GetNetworkCredential().UserName
}
}

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}

function create_x_auth_token_session 
{
$uri = "https://$idrac_ip/redfish/v1/SessionService/Sessions"
        
        if ($idrac_password) {
            $JsonBody = @{'UserName' = $idrac_username; 'Password' = $idrac_password } | ConvertTo-Json -Compress
        }
        else {
            $JsonBody = @{'UserName' = $credential.GetNetworkCredential().UserName; 'Password' = $credential.GetNetworkCredential().Password } | ConvertTo-Json -Compress
        }

        if ($x_auth_token) {
            try {
                if ($global:get_powershell_version -gt 5) {
                    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Body $JsonBody -Method Post -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token } -ContentType 'application/json'
                }
                else {
                    Ignore-SSLCertificates
                    $result = Invoke-WebRequest -Uri $uri -Body $JsonBody -Method Post -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token } -ContentType 'application/json'
                }
            }
            catch {
                Write-Host
                $RespErr
                return
            }
        }
        else {
            try {
                if ($global:get_powershell_version -gt 5) {
                    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Body $JsonBody -Method Post -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json" } -ContentType 'application/json'
                }
                else {
                    Ignore-SSLCertificates
                    $result = Invoke-WebRequest -Uri $uri -Body $JsonBody -Method Post -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json" } -ContentType 'application/json'
                }
            }
            catch {
                Write-Host
                $RespErr
                return
            }
        }

        if ($result.StatusCode -eq 201) {
        }
        else {
            [String]::Format("`n- FAIL, POST request failed to create X-Auth token session, statuscode {0} returned", $result.StatusCode)
            return
        }

        #Write-Host "`n- PASS, new iDRAC token session successfully created`n"
        $token_property_name = "X-Auth-Token"
        $global:x_auth_token_created = $result.Headers.$token_property_name
        $global:x_auth_session_uri = $result.Headers.Location
    }

function launch_kvm_session
{

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DelliDRACCardService/Actions/DelliDRACCardService.ExportSSLCertificate"
$JsonBody = @{"SSLCertType"= "Server"} | ConvertTo-Json -Compress
Write-Host "- INFO, getting current iDRAC server SSL cert"

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

if ($result1.StatusCode -eq 202 -or $result1.StatusCode -eq 200)
{
[String]::Format("- PASS, POST command passed to get current iDRAC SSL server cert, status code {0} returned", $result1.StatusCode)
}
else
{
[String]::Format("- FAIL, POST command failed to get current iDRAC SSL server cert, statuscode {0} returned. Detail error message: {1}",$resul1t.StatusCode, $result1)
return
}


$get_content = $result1.Content | ConvertFrom-Json
$get_cert_content = $get_content.CertificateFile
#$get_cert_content | Out-File -FilePath $cert_filename -NoClobber -NoNewline
Set-Content -Path "idrac_cert_file.txt" -Value $get_cert_content

Write-Host "- INFO, getting KVM session temporary username, password using iDRAC ssl cert"

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DelliDRACCardService/Actions/DelliDRACCardService.GetKVMSession"
$JsonBody = @{"SessionTypeName"= "idrac_cert_file.txt"} | ConvertTo-Json -Compress

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

if ($result1.StatusCode -eq 202 -or $result1.StatusCode -eq 200)
{
[String]::Format("- PASS, POST command passed to get temp username/password, status code {0} returned", $result1.StatusCode)
}
else
{
[String]::Format("- FAIL, POST command failed to get temp username/password, statuscode {0} returned. Detail error message: {1}",$resul1t.StatusCode, $result1)
return
}

$get_content = $result1.Content | ConvertFrom-Json
$temp_username = $get_content.TempUsername
$temp_password = $get_content.TempPassword
Write-Host "- INFO, launching iDRAC KVM session using your default browser"
Start-Sleep 5
if ($idrac_username)
{
$uri = "https://$idrac_ip/console?username=$idrac_username&tempUsername=$temp_username&tempPassword=$temp_password"
}
else
{
$uri = "https://$idrac_ip/console?username=$get_creds_username&tempUsername=$temp_username&tempPassword=$temp_password"
}

start $uri
Remove-Item("idrac_cert_file.txt")
}

function delete_x_auth_session
{
$uri = "https://$idrac_ip$global:x_auth_session_uri"
if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Delete -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Delete -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
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
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Delete -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Delete -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}
   

    if ($result1.StatusCode -ne 202 -or $result1.StatusCode -ne 200)
    {
    $raw_content = $result1.RawContent | ConvertTo-Json -Compress
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    $raw_content
    return
    }
}

# Run cmdlet

get_powershell_version 
setup_idrac_creds

# Check to validate iDRAC version detected supports this feature

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DelliDRACCardService"
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
$get_actions = $get_result.Content | ConvertFrom-Json
$get_kvm_action_name = "#DelliDRACCardService.GetKVMSession"
$validate_supported_idrac = $get_actions.Actions.$get_kvm_action_name
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
Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API or incorrect iDRAC user credentials passed in.`n"
return
}
if (-not $x_auth_token)
{
create_x_auth_token_session
$x_auth_token = $global:x_auth_token_created
}
launch_kvm_session
if (-not $x_auth_token)
{
Start-Sleep 30
delete_x_auth_session
}

}











