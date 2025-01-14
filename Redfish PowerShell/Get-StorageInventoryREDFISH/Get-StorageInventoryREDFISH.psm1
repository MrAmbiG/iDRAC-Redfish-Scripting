<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 14.0

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
   iDRAC cmdlet used to get storage inventory using Redfish API.
.DESCRIPTION
   iDRAC cmdlet used to get storage inventory using Redfish API. It will return storage information for controllers, disks or backplanes.
   - idrac_ip: Pass in iDRAC IP address
   - idrac_username: Pass in iDRAC username (Optional: Not passing in username/password parameters will prompt you to enter using Get-Credentail)
   - idrac_password: Pass in iDRAC username password (Optional: Not passing in username/password parameters will prompt you to enter using Get-Credentail)
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended).
   - get_storage_controllers: Get current storage controller FQDDs for the server.
   - get_storage_controller_details: Get detailed information for all storage controller FQDDs detected. 
   - get_virtual_disks: Pass in the controller FQDD to get current virtual disks. Example, pass in "RAID.Integrated.1-1" to get current virtual disks for integrated storage controller
   - get_virtual_disks_details: Pass in the virtual disk FQDD to get detailed information for a specific VD. Example, pass in "Disk.Virtual.0:RAID.Slot.6-1" to get detailed virtual disk information
   - get_controller_virtual_disk_details: Pass in the controller FQDD to get detailed information for all VDs detected behind this controller.
   - get_physical_disks: Pass in the controller FQDD to get physical disks. Example, pass in "RAID.Slot.6-1" to get physical disks. 
   - get_physical_disks_details: Pass in the controller FQDD to get detailed information for physical disks.
   - get_server_vds: Get all VDs detected for the server. 
.EXAMPLE
   Get-StorageInventoryREDFISH -idrac_ip 192.168.0.120 -username root -password calvin -get_storage_controllers
   This example will return all storage controller FQDDs detected.
.EXAMPLE
   Get-StorageInventoryREDFISH -idrac_ip 192.168.0.120 -get_storage_controller_details
   This example will first prompt for username,password using Get-Credential module, then return detailed information for all storage controller FQDDs detected.
.EXAMPLE
   Get-StorageInventoryREDFISH -idrac_ip 192.168.0.120 -get_storage_controllers -x_auth_token 26b2dbe2728de5b43af9e468137bf11d
   This example will return detailed information for all storage controller FQDDs detected using iDRAC X-Auth token session for authentication.
.EXAMPLE
   Get-StorageInventoryREDFISH -idrac_ip 192.168.0.120 -username root -password calvin -get_virtual_disks_details Disk.Virtual.0:RAID.Slot.6-1
   This example will return detailed information for VD Disk.Virtual.0:RAID.Slot.6-1
.EXAMPLE
   Get-StorageInventoryREDFISH -idrac_ip 192.168.0.120 -username root -password calvin -get_server_vds
   This example will return all VDs detected for all controllers in the server.
#>

function Get-StorageInventoryREDFISH {

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
    [switch]$get_storage_controllers,
    [Parameter(Mandatory=$False)]
    [switch]$get_storage_controller_details,
    [Parameter(Mandatory=$False)]
    [string]$get_virtual_disks,
    [Parameter(Mandatory=$False)]
    [string]$get_virtual_disk_details,
    [Parameter(Mandatory=$False)]
    [string]$get_controller_virtual_disk_details,
    [Parameter(Mandatory=$False)]
    [string]$get_physical_disks,
    [Parameter(Mandatory=$False)]
    [string]$get_physical_disks_details,
    [Parameter(Mandatory=$False)]
    [switch]$get_server_vds
    )

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
    ## We create an instance of TrustAll and attach it to the ServicePointManager
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
    if ($idrac_username)
    {
    $get_creds = Get-Credential -Message "Enter $idrac_username password to run cmdlet" -UserName $idrac_username
    $global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
    }
    else
    {
    $get_creds = Get-Credential -Message "Enter iDRAC username and password to run cmdlet"
    $global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
    }
}
}
setup_idrac_creds

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage"

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
    Write-Host
    $RespErr
    return
    }
}

 if ($result.StatusCode -ne 200)
	    {
        Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API"
	    return
	    }
        elseif ($result.StatusCode -eq 401)
        {
        Write-Host "`n- WARNING, invalid iDRAC username or password detected, status code 401 returned."
        return
        }
	    else
	    {
	    }

###############################################################################

if ($get_server_vds)
{

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
    $RespErr
    return
    }
}


if ($result.StatusCode -eq 200)
{
}
else
{
    [String]::Format("`n- FAIL, GET request failed to get storage controllers, statuscode {0} returned",$result.StatusCode)
    return
}

$get_content = $result.Content | ConvertFrom-Json
$odata_id = '@odata.id'
foreach ($item in $get_content.Members.$odata_id)
{
$uri = "https://$idrac_ip$item/Volumes"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
    $RespErr
    return
    }
}
if ($result.StatusCode -eq 200)
{
}
else
{
    [String]::Format("`n- FAIL, GET request failed, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
if ($get_content.Members.count -eq 0)
{
$controller_fqdd = $item.Split("/")[-1]
Write-Host "`n- INFO, no VD(s) detected for controller $controller_fqdd"
}
else
{
$odata_id = '@odata.id'
foreach ($item in $get_content.Members.$odata_id)
{
$uri = "https://$idrac_ip$item"
if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri-Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
    $RespErr
    return
    }
}
if ($result.StatusCode -eq 200)
{
}
else
{
    [String]::Format("`n- FAIL, GET request failed, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
Write-Host
$get_content
}
}

}
}

######################################################################################################

if ($get_virtual_disks)
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage/$get_virtual_disks/Volumes"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
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

$get_result=$result.Content | ConvertFrom-Json
if ($get_result.Members.count -eq 0)
{
Write-Host "`n- INFO, no virtual disks detected for controller $get_virtual_disks`n"
return
}

[String]::Format("`n- INFO, virtual disks detected for controller {0} -`n",$get_virtual_disks)
foreach ($item in $get_result.Members)
{
$odata_id = "@odata.id"
$item.$odata_id.Split("/")[-1]
}

}

####################################################################################################

if ($get_virtual_disk_details)
{
$controller_fqdd = $get_virtual_disk_details.Split(":")[-1]
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage/$controller_fqdd/Volumes/$get_virtual_disk_details"
if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
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
$get_result = $result.Content | ConvertFrom-Json
[String]::Format("`n- Detailed DMTF information for virtual disk {0}", $get_virtual_disk_details)
$get_result
$oem_content = $get_result.Oem.Dell.DellVirtualDisk
[String]::Format("- Detailed OEM information for virtual disk {0}`n", $get_virtual_disk_details)
if ($oem_content -eq $null)
{
[String]::Format("- WARNING, unable to detect or report OEM details for virtual disk {0}", $get_virtual_disk_details)
}
else
{
$oem_content
}

return

}

####################################################################################################

if ($get_controller_virtual_disk_details)
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage/$get_controller_virtual_disk_details/Volumes"
if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
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

$get_result=$result.Content | ConvertFrom-Json
if ($get_result.Members.count -eq 0)
{
Write-Host "`n- INFO, no virtual disks detected for controller $get_virtual_disks`n"
return
}

foreach ($item in $get_result.Members)
{
$odata_id = "@odata.id"
$uri = "https://$idrac_ip" + $item.$odata_id
[String]::Format("`n- INFO, detailed information for virtual disk {0} -`n",$item.$odata_id)

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
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

$result.Content | ConvertFrom-Json

}

}

#####################################################################################

if ($get_storage_controllers)
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage"
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
    [String]::Format("`n- PASS, statuscode {0} returned successfully to get storage controller(s)",$result.StatusCode)
}
else
{
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}

$get_content = $result.Content

Write-Host
$regex = [regex] '/Storage/.+?"'
$allmatches = $regex.Matches($get_content)
$get_all_matches = $allmatches.Value.Replace('/Storage/',"")
$controllers = $get_all_matches.Replace('"',"")
Write-Host "- Server controllers detected -`n"
$controllers
Write-Host
return
}

##########################################################################################################

if ($get_storage_controller_details)
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage"
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
    [String]::Format("`n- PASS, statuscode {0} returned successfully to get storage controller(s)",$result.StatusCode)
}
else
{
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
$number_of_controller_entries = $get_content.Members.Count
$count = 0
Write-Host
while ($count -ne $number_of_controller_entries)
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage"
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
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
$get_content = $get_content.Members[$count]
$get_content = [string]$get_content
$get_content = $get_content.Replace("@{@odata.id=","")
$get_content = $get_content.Replace('}',"")
$uri = "https://$idrac_ip"+$get_content
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
[String]::Format("- Detailed DMTF information for controller {0} -`n", $get_content.Id)
$result.Content | ConvertFrom-Json
[String]::Format("- Detailed OEM information for controller {0} -`n", $get_content.Id)
$oem_content = $get_content.Oem.Dell.DellController
if ($oem_content -eq $null)
{
[String]::Format("- WARNING, unable to detect or report OEM details for controller {0}", $get_content.Id)
}
else
{
$oem_content
}
Write-Host
$count+=1

}
Write-Host
return
}

#######################################################################################################

if ($get_physical_disks)
{
$query = "?`$select=Drives"
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage/$get_physical_disks" + $query

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
    $RespErr
    return
    }
}
if ($result.StatusCode -eq 200)
{
}
else
{
    [String]::Format("`n- FAIL, GET request failed, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
Write-Host "`n- Drives detected for controller $get_physical_disks -`n"

foreach ($item in $get_content.Drives)
{
$id = "@odata.id"
$drive_uri = $item.$id
$uri = "https://$idrac_ip$drive_uri"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
    $RespErr
    return
    }
}
if ($result.StatusCode -eq 200)
{
}
else
{
    [String]::Format("`n- FAIL, GET request failed, statuscode {0} returned",$result.StatusCode)
    return
}
$disk = $drive_uri.Split("/")[-1]
$get_content = $result.Content | ConvertFrom-Json
$raid_status = $get_content.Oem.Dell.DellPhysicalDisk.RaidStatus
Write-Host "$disk, RaidStatus = $raid_status"

}
}

##################################################################################################

if ($get_physical_disks_details)
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Storage/$get_physical_disks_details"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
    $RespErr
    return
    }
}
if ($result.StatusCode -eq 200)
{
}
else
{
    [String]::Format("`n- FAIL, GET request failed, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
foreach ($item in $get_content.Drives)
{
$id = "@odata.id"
$drive_uri = $item.$id
$uri = "https://$idrac_ip$drive_uri"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
    Write-Host
    $RespErr
    return
    }
}
if ($result.StatusCode -eq 200)
{
}
else
{
    [String]::Format("`n- FAIL, GET request failed, statuscode {0} returned",$result.StatusCode)
    return
}
$disk = $drive_uri.Split("/")[-1]
Write-Host "`n- Detailed DMTF drive information for $disk -`n"
$get_content = $result.Content | ConvertFrom-Json
$get_content

Write-Host "`n- Detailed OEM drive information for $disk -`n"
$get_content.Oem.Dell.DellPhysicalDisk

}
}

}








