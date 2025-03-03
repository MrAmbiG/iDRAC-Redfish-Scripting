<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 12.0

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
   iDRAC cmdlet using Redfish API to change iDRAC user password
.DESCRIPTION
   iDRAC cmdlet using Redfish API to change iDRAC user password. Once the iDRAC user password has changed, cmdlet will execute GET command to validate the new password was set. If using dash(-) or single quote(') in your current or new password, make sure to surround the password value with double quotes.
   Supported parameters: 
   - idrac_ip: Pass in iDRAC IP address
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC username current password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_idrac_user_account_ids: Get iDRAC user account ID details
   - idrac_user_id: Pass in the iDRAC user account ID. Note iDRAC9 supports up to 16 user accounts, iDRAC10 supports up to 32 user accounts. 
   - idrac_new_password: Pass in the new password you want to set to
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_idrac_user_account_ids
   This example will get account details for all iDRAC user account IDs.
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH -idrac_ip 192.168.0.120 -get_idrac_user_account_ids
   This example will first prompt for iDRAC username/password using Get-Credentials, then get account details for all iDRAC user account IDs.
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -idrac_user_id 2 -idrac_new_password test 
   This example shows changing root password. I pass in the current password of "calvin", pass in "2" for the user account ID and pass in the new password i want to change to which is "test".
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH -idrac_ip 192.168.0.120 -idrac_user_id 2 
   This example shows changing root password using Get-Credential. It will first prompt for current iDRAC username and password for account ID 2. Then prompt to pass in the new password you want to set. 
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH.ps1 -idrac_ip 192.168.0.120 -idrac_user_id 3 -x_auth_token "cbc7afd01e4f4543aec17e1afb31154c"
   This example using iDRAC X-auth token session will change password for user id 3. It will prompt you to enter new password for id 3.
#>

function Invoke-ChangeIdracUserPasswordREDFISH {

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
    [int]$idrac_user_id,
    [Parameter(Mandatory=$False)]
    [string]$idrac_new_password,
    [Parameter(Mandatory=$False)]
    [switch]$get_idrac_user_account_ids

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

$global:get_powershell_version

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
$get_creds = Get-Credential -Message "Pass in iDRAC username and password to run Redfish commands"
$global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
}
}

# Function to get iDRAC version installed on server 

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

# Function to get iDRAC user account details 

function get_idrac_user_acccount_details_iDRAC9
{
Write-Host "`n- iDRAC users account details -`n"

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Accounts?`$expand=*(`$levels=1)"

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

if ($result.StatusCode -ne 200)
{
    [String]::Format("- FAIL, statuscode {0} returned for GET command failure",$result.StatusCode)
    return
}
$get_result = $result.Content | ConvertFrom-Json
$get_result.Members
}

function get_idrac_user_acccount_details_iDRAC10
{
Write-Host "`n- iDRAC users account details -`n"

$uri = "https://$idrac_ip/redfish/v1/AccountService/Accounts?`$expand=*(`$levels=1)"

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

if ($result.StatusCode -ne 200)
{
    [String]::Format("- FAIL, statuscode {0} returned for GET command failure",$result.StatusCode)
    return
}
$get_result = $result.Content | ConvertFrom-Json
$get_result.Members
}

# Function to change iDRAC user account password

function change_idrac_user_password
{

if ($global:iDRAC_version -eq "old")
{
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Accounts/$idrac_user_id"
}
else
{
$uri = "https://$idrac_ip/redfish/v1/AccountService/Accounts/$idrac_user_id"
}
 
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


if ($result.StatusCode -ne 200)
{
    [String]::Format("- FAIL, statuscode {0} returned for GET command failure",$result.StatusCode)
    return
}
$get_result = $result.Content | ConvertFrom-Json
$change_username = $get_result.UserName

if ($idrac_new_password)
{
$JsonBody = '{{"Password" : "{0}"}}' -f $idrac_new_password
}
else
{
$get_new_creds = Get-Credential -UserName $change_username -Message "Pass in new password for username '$change_username', ID '$idrac_user_id'"
$global:new_credential = New-Object System.Management.Automation.PSCredential($get_new_creds.UserName, $get_new_creds.Password)
$global:get_new_user_password = $get_new_creds.Password
$get_string = (New-Object PSCredential "user",$get_new_creds.Password).GetNetworkCredential().Password
$global:JsonBody = '{{"Password" : "{0}"}}' -f $get_string
}

Write-Host "`n- INFO, executing PATCH command to change iDRAC user ID $idrac_user_id password"
 
if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $patch_result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $patch_result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
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
    
    $patch_result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $patch_result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


if ($patch_result.StatusCode -eq 200)
{
    [String]::Format("`n- PASS, statuscode {0} returned successfully for PATCH command to change iDRAC user password",$patch_result.StatusCode)
    Start-Sleep 3    
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$patch_result.StatusCode)
    return
}

if ($x_auth_token)
{
Write-Host "- INFO, X-auth token detected. If password was changed for the user ID which generated the X-Auth token, this token is no longer valid and needs to be recreated using new password."
}

}

############
# Run code #
############

get_powershell_version 
setup_idrac_creds

# Code to check for supported iDRAC version installed

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
	    if ($result.StatusCode -eq 200 -or $result.StatusCode -eq 202)
	    {
	    }
	    else
	    {
        Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API"
        $result
	    return
	    }

if ($get_idrac_user_account_ids)
{
    if ($global:iDRAC_version -eq "old")
    {
    get_idrac_user_acccount_details_iDRAC9
    }
    else
    {
    get_idrac_user_acccount_details_iDRAC10
    }
}
elseif ($idrac_user_id)
{
change_idrac_user_password
}
else
{
Write-Host "- FAIL, either invalid parameter value passed in or missing required parameter"
return
}

}




