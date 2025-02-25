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
   iDRAC cmdlet using Redfish API with OEM extension to manage iDRAC licenses. 
.DESCRIPTION
   iDRAC cmdlet using Redfish API with OEM extension to manage iDRAC licenses. Cmdlet can either get current iDRAC licenses, export/import license either locally or network share, delete license. 

   Supported parameters to pass in for cmdlet:
   
   - idrac_ip: Pass in iDRAC IP
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_licenses: Get current iDRAC licenses. This output will also return entitlement ID for each license which is needed for exporting the license.
   - export_license: Pass in entitlement ID string of the license you want to export.
   - delete_license: Pass in entitlement ID string of the license you want to delete.
   - import_license: Pass in the name of the license file you want to import. Note: If importing from network share the license file must be in XML format.
   - get_supported_share_type_values: Get supported network share type values for export or import. 
   - share_name: Pass in the name of the network share to export the license to.
   - share_type: Pass in the share type of the network share. Pass in a value of "local" to export or import the license locally. Note: Exporting the license locally will convert the license to encoded base64 string format. Note: If you do not pass in share_type argument export import will default to local.
   - share_ipaddress: Pass in the IP address of the network share.
   - share_username: Pass in the username of the network share. This is only supported for CIFS or secure HTTP/HTTPS shares.
   - share_password: Pass in the password of the network share. This is only supported for CIFS or secure HTTP/HTTPS shares.
   - ignore_cert_warning: Ignore cert checking when using HTTPS share. Supported values are "On" and "Off". 

   
.EXAMPLE
   Invoke-IdracLicenseManagementREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_licenses 
   This example will get current iDRAC licenses. 
.EXAMPLE
   Invoke-IdracLicenseManagementREDFISH -idrac_ip 192.168.0.120 -get_licenses 
   This example will first prompt for iDRAC username and password using Get-Credentials, then get current iDRAC licenses. 
.EXAMPLE
   Invoke-IdracLicenseManagementREDFISH -idrac_ip 192.168.0.120 -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708 -get_licenses 
   This example using iDRAC X-auth token session will get current iDRAC licenses. 
.EXAMPLE
   Invoke-IdracLicenseManagementREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -export_license 9902PA_Enterprise_license -share_type local
   This example will export iDRAC license locally.
.EXAMPLE
   Invoke-IdracLicenseManagementREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -export_license 9902PA_Enterprise_license -share_type NFS -share_name /nfs -share_ipaddress "192.168.0.130"
   This example will export iDRAC license to NFS network share.
.EXAMPLE
   Invoke-IdracLicenseManagementREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -delete_license 9902PA_Enterprise_license
   This example will delete iDRAC license.
.EXAMPLE
   Invoke-IdracLicenseManagementREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -import_license 9902PA_Enterprise_exported_license.txt -share_type local
   This example will import iDRAC license locally. 
.EXAMPLE
   Invoke-IdracLicenseManagementREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -import_license 9902PA_Enterprise_export_iDRAC_license.xml -share_type NFS -share_name /nfs -share_ipaddress "192.168.0.130"
   This example will import iDRAC license from network share.
#>

function Invoke-IdracLicenseManagementREDFISH {

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
    [switch]$get_licenses,
    [Parameter(Mandatory=$False)]
    [string]$export_license,
    [Parameter(Mandatory=$False)]
    [string]$delete_license,
    [Parameter(Mandatory=$False)]
    [string]$import_license,
    [Parameter(Mandatory=$False)]
    [switch]$get_supported_share_type_values,
    [Parameter(Mandatory=$False)]
    [string]$share_name,
    [Parameter(Mandatory=$False)]
    [string]$share_type,
    [Parameter(Mandatory=$False)]
    [string]$share_ipaddress,
    [Parameter(Mandatory=$False)]
    [string]$share_username,
    [Parameter(Mandatory=$False)]
    [string]$share_password,
    [Parameter(Mandatory=$False)]
    [string]$ignore_cert_warning
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
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12,[Net.SecurityProtocolType]::TLS13
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


function get_licenses
{

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLicensableDevices"
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
}
else
{
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
$member_count = "Members@odata.count"

if ($get_content.$member_count -eq 0)
{
[String]::Format("`n- WARNING, no licenses currently installed for iDRAC $idrac_ip")
}
else
{
$count = 1
Write-Host "`n- License details for iDRAC $idrac_ip -`n"
foreach ($item in $get_content.Members)
{
Write-Host "`n- License $count -`n"
$item
$count ++
}
}

}


function get_supported_share_type_values
{

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLicenseManagementService"
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
}
else
{
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
$action_name = "#DellLicenseManagementService.ExportLicenseToNetworkShare"
$share_type_values = "ShareType@Redfish.AllowableValues"
Write-Host "`n- Supported network share types -`n"
$get_content.Actions.$action_name.$share_type_values
Write-Host
}





function export_license_locally
{
Write-Host "`n- INFO, exporting license for iDRAC $idrac_ip"

$JsonBody = @{"EntitlementID"=$export_license}
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLicenseManagementService/Actions/DellLicenseManagementService.ExportLicense"
$JsonBody = $JsonBody | ConvertTo-Json -Compress

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

if ($post_result.StatusCode -eq 200 -or $post_result.StatusCode -eq 202)
{
Write-Host "- PASS, POST command passed to export iDRAC license '$export_license'"
}
else
{
[String]::Format("- FAIL, POST command failed to export iDRAC license, statuscode {0} returned. Detail error message: {1}",$post_result.StatusCode, $post_result)
return
}

$get_content = $post_result.Content | ConvertFrom-Json
Write-Host "`n- Exported license contents -`n"
$get_content.LicenseFile
Set-Content -Path $export_license"_exported_license.txt" -Value $get_content.LicenseFile
[String]::Format("`n- Exported license content also copied to '{0}'", $export_license+"_exported_license.txt")
}


function export_license_network_share
{
Write-Host "`n- INFO, exporting license for iDRAC $idrac_ip to network share"

$JsonBody = @{"EntitlementID"=$export_license;"FileName"=$export_license+"_export_iDRAC_license.xml"}
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLicenseManagementService/Actions/DellLicenseManagementService.ExportLicenseToNetworkShare"
    if ($share_name)
    {
    $JsonBody["ShareName"] = $share_name
    }
    if ($share_type)
    {
    $JsonBody["ShareType"] = $share_type
    }
    if ($share_ipaddress)
    {
    $JsonBody["IPAddress"] = $share_ipaddress
    }
    if ($share_username)
    {
    $JsonBody["UserName"] = $share_username
    }
    if ($share_password)
    {
    $JsonBody["Password"] = $share_password
    }
    if ($ignore_cert_warning)
    {
    $JsonBody["IgnoreCertificateWarning"] = $ignore_cert_warning
    }
    
$JsonBody = $JsonBody | ConvertTo-Json -Compress

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

if ($post_result.StatusCode -eq 200 -or $post_result.StatusCode -eq 202)
{
Write-Host "- PASS, POST command passed to export iDRAC license '$export_license' to network share"
}
else
{
[String]::Format("- FAIL, POST command failed to export iDRAC license, statuscode {0} returned. Detail error message: {1}",$post_result.StatusCode, $post_result)
return
}
Start-Sleep 10


$job_id_uri = $post_result.Headers.Location

$uri = "https://$idrac_ip"+$job_id_uri
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
}
else
{
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
if ($get_content.JobState -eq "Completed")
{
$filename = $export_license+"_export_iDRAC_license.xml"
Write-Host "- PASS, license '$filename' successfully exported to network share"
}
elseif ($get_content.JobState -eq "Failed")
{
Write-Host "- FAIL, license failed to export to network share, detailed job results:`n"
$get_content
}
else
{
Write-Host "- Detailed job ID results:`n"
$get_content
}

}

function delete_license
{
Write-Host "`n- INFO, delete license for iDRAC $idrac_ip"

$JsonBody = @{"EntitlementID"=$delete_license;"DeleteOptions"="Force"}
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLicenseManagementService/Actions/DellLicenseManagementService.DeleteLicense"
$JsonBody = $JsonBody | ConvertTo-Json -Compress

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

if ($post_result.StatusCode -eq 200 -or $post_result.StatusCode -eq 202)
{
Write-Host "- PASS, POST command passed to delete iDRAC license '$delete_license'"
}
else
{
[String]::Format("- FAIL, POST command failed to delete iDRAC license, statuscode {0} returned. Detail error message: {1}",$post_result.StatusCode, $post_result)
return
}

}

function import_license_locally
{
Write-Host "`n- INFO, importing license for iDRAC $idrac_ip"
$fileExtension = [System.IO.Path]::GetExtension($import_license)
if ($fileExtension -eq ".xml")
{
Function ConvertTo-PaddedBase64 {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path $_})]
        $File
    )
    $base64Str = [Convert]::ToBase64String([IO.File]::ReadAllBytes($File))
    $paddedStr = do {
        $base64Str[0..63] -join ''
        $base64Str = $base64Str[64..$($base64Str.length)]
    } until ($base64Str.Length -eq 0)
    $paddedStr | Out-String
}

$LicenseFile = Get-Item $import_license
[string]$hostLicContent = ConvertTo-PaddedBase64 $LicenseFile.FullName
$JsonBody = @{"FQDD"="iDRAC.Embedded.1";"ImportOptions"="Force";"LicenseFile"=$hostLicContent}
}
else
{
$get_file_content = Get-Content $import_license -ErrorAction Stop | Out-String
$JsonBody = @{"FQDD"="iDRAC.Embedded.1";"ImportOptions"="Force";"LicenseFile"=$get_file_content}
}

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLicenseManagementService/Actions/DellLicenseManagementService.ImportLicense"
$JsonBody = $JsonBody | ConvertTo-Json -Compress


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

if ($post_result.StatusCode -eq 200 -or $post_result.StatusCode -eq 202)
{
Write-Host "- PASS, POST command passed to import iDRAC license locally"
}
else
{
[String]::Format("- FAIL, POST command failed to import iDRAC license, statuscode {0} returned. Detail error message: {1}",$post_result.StatusCode, $post_result)
return
}

}

function import_license_network_share
{
Write-Host "`n- INFO, importing license for iDRAC $idrac_ip from network share"

$JsonBody = @{"FQDD"="iDRAC.Embedded.1";"ImportOptions"="Force";"LicenseName"=$import_license}
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLicenseManagementService/Actions/DellLicenseManagementService.ImportLicenseFromNetworkShare"
    if ($share_name)
    {
    $JsonBody["ShareName"] = $share_name
    }
    if ($share_type)
    {
    $JsonBody["ShareType"] = $share_type
    }
    if ($share_ipaddress)
    {
    $JsonBody["IPAddress"] = $share_ipaddress
    }
    if ($share_username)
    {
    $JsonBody["UserName"] = $share_username
    }
    if ($share_password)
    {
    $JsonBody["Password"] = $share_password
    }
    if ($ignore_cert_warning)
    {
    $JsonBody["IgnoreCertificateWarning"] = $ignore_cert_warning
    }
$JsonBody = $JsonBody | ConvertTo-Json -Compress

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

if ($post_result.StatusCode -eq 200 -or $post_result.StatusCode -eq 202)
{
Write-Host "- PASS, POST command passed to import iDRAC license"
}
else
{
[String]::Format("- FAIL, POST command failed to import iDRAC license, statuscode {0} returned. Detail error message: {1}",$post_result.StatusCode, $post_result)
return
}

Start-Sleep 10


$job_id_uri = $post_result.Headers.Location

$uri = "https://$idrac_ip"+$job_id_uri
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
}
else
{
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
if ($get_content.JobState -eq "Completed")
{
Write-Host "- PASS, license successfully imported from network share"
}
elseif ($get_content.JobState -eq "Failed")
{
Write-Host "- FAIL, license failed to import from network share, detailed job results:`n"
$get_content
}
else
{
Write-Host "- Detailed job ID results:`n"
$get_content
}


}

# Run cmdlet

get_powershell_version 
setup_idrac_creds

# Check to validate iDRAC version detected supports this feature

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLicenseManagementService"
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
$action_name = "#DellLicenseManagementService.ExportLicense"
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
Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API or incorrect iDRAC user credentials passed in.`n"
return
}

if ($get_licenses)
{
get_licenses
}
elseif ($get_supported_share_type_values)
{
get_supported_share_type_values
}
elseif ($export_license -and $share_type -and $share_name -and $share_ipaddress)
{
export_license_network_share
} 
elseif ($export_license -and $share_type.ToLower() -eq "local" -or $export_license)
{
export_license_locally
}
elseif ($delete_license)
{
delete_license
}
elseif ($import_license -and $share_type -and $share_name -and $share_ipaddress)
{
import_license_network_share
} 
elseif ($import_license -and $share_type.ToLower() -eq "local" -or $import_license)
{
import_license_locally
}
else
{
Write-Host "- FAIL, either invalid parameter value passed in or missing required parameter"
return
}

}
