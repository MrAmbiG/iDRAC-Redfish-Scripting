<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 10.0

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
  iDRAC cmdlet using Redfish API with OEM extension to perform a repository update from a supported network share
.DESCRIPTION
  iDRAC cmdlet using Redfish API with OEM extension to perform a repository update from a supported network share. Recommended to use HTTPS share "downloads.dell.com" repository for updates or you can create and use a custom repository using Dell Repository Manager (DRM) utility.
   - idrac_ip: Pass in iDRAC IP address
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_firmware_versions_only: Get current firmware versions of devices in the server.
   - get_repo_update_list: Get device firmware versions that can be updated from the repository you are using. NOTE: You must first perform install from repository with ApplyUpdate set to False before using this argument. This argument will use the catalog file you just passed in to check for firmware differences.
   - get_job_queue: Get iDRAC current job queue, will report all job IDs.
   - install_from_repository: Perform installation from repository. You must also pass in other required parameters needed to perform this operation. See -examples for examples of executing install from repository.
   - network_share_IPAddress: Pass in IP address of the network share which contains the repository. Domain name string is also valid to pass in.
   - ShareName: Pass in the network share name of the repository.
   - ShareType: Pass in share type of the network share. Supported network shares are: NFS, CIFS, HTTP and HTTPS
   - Username: Network share username if your network share has auth enabled.
   - Password: Network share username password if your network share has auth enabled.
   - IgnoreCertWarning: Supported values are Off and On. This argument is only supported if using HTTPS for share type'
   - ApplyUpdate: Pass in True if you want to apply the updates. Pass in False will not apply updates. NOTE: This argument is optional. If you don't pass in the argument, default value is True.
   - RebootNeeded: Pass in True to reboot the server immediately to apply updates which need a server reboot. False means the updates will get staged but not get applied until next manual server reboot. NOTE: This argument is optional. If you don't pass in this argument, default value is False
   - catalogFile: Name of the catalog file on the repository. If the catalog file name is Catalog.xml on the network share, you don't need to pass in this argument
 

.EXAMPLE
   Invoke-InstallFromRepositoryOemREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_firmware_versions_only 
   This example will get current firmware versions for the devices in the server.
.EXAMPLE
   Invoke-InstallFromRepositoryOemREDFISH -idrac_ip 192.168.0.120 -get_firmware_versions_only 
   This example will first prompt for iDRAC username/password using Get-Credentials, then get current firmware versions for the devices in the server.
.EXAMPLE
   Invoke-InstallFromRepositoryOemREDFISH -idrac_ip 192.168.0.120 -get_firmware_versions_only -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708
   This example will get current firmware versions for the devices in the server using iDRAC X-auth token session. 
.EXAMPL
   Invoke-InstallFromRepositoryOemREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_repo_update_list 
   This example will check the Catalog file on the repository and compare against current FW versions on the server. If there is a FW version difference detected, it will report output in XML format. NOTE: You must first run install from repository using a catalog file with apply update set to false before using this argument since it needs access to your catalog file.
.EXAMPLE
   Invoke-InstallFromRepositoryOemREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -install_from_repository -ShareType HTTPS -network_share_IPAddress "downloads.dell.com" -ApplyUpdate True -RebootNeeded True 
   This example will perform repository update using HTTPS share which contains the repository. This will immediately apply the updates and reboot the server if needed to apply updates. NOTE: This example is using Dell's HTTP repository which is recommended to be used. If you don't use this repository, you will need to use Dell Repository Manager (DRM) utility to create a custom repository.
.EXAMPLE
   Invoke-InstallFromRepositoryOemREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -install_from_repository -ShareType NFS -network_share_IPAddress 192.168.0.130 -ShareName /nfs -ApplyUpdate True -RebootNeeded True 
   This example will perform repository update using NFS share which contains custom repository. This will imediately apply the udpates and reboot the server if needed to apply updates.
#>

function Invoke-InstallFromRepositoryOemREDFISH {


param(
    [Parameter(Mandatory=$True)]
    $idrac_ip,
    [Parameter(Mandatory=$False)]
    $idrac_username,
    [Parameter(Mandatory=$False)]
    $idrac_password,
    [Parameter(Mandatory=$False)]
    [string]$x_auth_token,
    [Parameter(Mandatory=$False)]
    [switch]$get_firmware_versions_only,
    [Parameter(Mandatory=$False)]
    [switch]$get_repo_update_list,
    [Parameter(Mandatory=$False)]
    [switch]$get_job_queue,
    [Parameter(Mandatory=$False)]
    [switch]$install_from_repository,
    [Parameter(Mandatory=$False)]
    [string]$network_share_IPAddress,
    [Parameter(Mandatory=$False)]
    [string]$ShareName,
    [ValidateSet("NFS", "HTTP", "HTTPS", "CIFS")]
    [Parameter(Mandatory=$False)]
    [string]$ShareType,
    [Parameter(Mandatory=$False)]
    [string]$Username,
    [Parameter(Mandatory=$False)]
    [string]$Password,
    [Parameter(Mandatory=$False)]
    [string]$IgnoreCertWarning,
    [Parameter(Mandatory=$False)]
    [string]$ApplyUpdate,
    [Parameter(Mandatory=$False)]
    [string]$RebootNeeded,
    [Parameter(Mandatory=$False)]
    [string]$catalogFile
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

# function to get Powershell version

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}


# Function to get firmware versions only

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
$get_fw_inventory = $get_result.Content | ConvertFrom-Json
$get_fw_inventory.Members

return
}

# Function to get iDRAC job queue

function get_job_queue
{
Write-Host
Write-Host "--- Getting Job Queue For iDRAC $idrac_ip ---"
Write-Host

$expand_query ='?$expand=*($levels=1)'
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs$expand_query"
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
$get_job_queue = $get_result.Content | ConvertFrom-Json


if ($get_job_queue.Members.count -eq 0)
{
Write-Host "-INFO, current iDRAC Job Queue is empty`n"
}
else
{
$get_job_queue.Members
}


return
}



# Function to get repo update list

function get_repo_update_list
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSoftwareInstallationService/Actions/DellSoftwareInstallationService.GetRepoBasedUpdateList"
$JsonBody = @{} | ConvertTo-Json -Compress
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
$post_result_search = $post_result.Content | ConvertFrom-Json
$post_result_search.PackageList
}




# Function install from repository

function install_from_repository
{
$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs"
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
$get_job_id_uris = $get_result.Content | ConvertFrom-Json
$current_job_ids = @()
foreach ($item in $get_job_id_uris.Members)
{
$convert_to_string = [string]$item
$get_job_id = $convert_to_string.Split("/")[-1].Replace("}","")
$current_job_ids += $get_job_id
}


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellSoftwareInstallationService/Actions/DellSoftwareInstallationService.InstallFromRepository"
$JsonBody= @{}

if ( $network_share_IPAddress ) 
{
$JsonBody["IPAddress"] = $network_share_IPAddress
}
if ( $ShareType ) 
{
$JsonBody["ShareType"] = $ShareType
}
if ( $ShareName ) 
{
$JsonBody["ShareName"] = $ShareName
}
if ( $Username ) 
{
$JsonBody["UserName"] = $Username
}
if ( $Password ) 
{
$JsonBody["Password"] = $Password
}
if ( $IgnoreCertWarning ) 
{
$JsonBody["IgnoreCertWarning"] = $IgnoreCertWarning
}
if ( $ApplyUpdate ) 
{
$JsonBody["ApplyUpdate"] = $ApplyUpdate
}
if ( $RebootNeeded ) 
{
    if ( $RebootNeeded -eq "True")
    {
    $JsonBody["RebootNeeded"] = $true
    $reboot_needed_flag = "True"
    }
    if ( $RebootNeeded -eq "False")
    {
    $JsonBody["RebootNeeded"] = $false
    $reboot_needed_flag = "False"
    }
}
else
{
$no_reboot_flag = "True"
}

if ( $CatalogFile ) 
{
$JsonBody["CatalogFile"] = $CatalogFile
}

Write-Host "`n- INFO, arguments and values passed in for Action 'DellSoftwareInstallationService.InstallFromRepository'"
foreach ($item in $JsonBody)
{
$item    
}

$JsonBody = $JsonBody| ConvertTo-Json -Compress
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
        Write-Host "`n- PASS, POST command passed for OEM Action 'InstallFromRepository', status code 202 returned"
        }
try
{
$repo_job_id = $post_result.Headers["Location"].Split("/")[-1]
}
catch
{
Write-Host "`n- FAIL, unable to locate job ID URI in POST headers output"
return
}
Write-Host "- PASS, repository job ID '$repo_job_id' successfully created, cmdlet will loop checking the job status until marked completed"

$start_time=Get-Date -DisplayHint Time
Start-Sleep 5
$message_count = 1

while ($true)
{
$uri ="https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/$repo_job_id"
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
if ($overall_job_output.JobState -eq "Completed")
{
break
}
elseif ($overall_job_output.Message -eq "Job failed." -or $overall_job_output.Message -eq "Failed")
    {
    Write-Host
    [String]::Format("- FAIL, job not marked as completed, detailed error info: {0}",$overall_job_output)
    return
    }
elseif ($overall_job_output.Message -eq "Package successfully downloaded." -and $message_count -eq 1)
{
Write-Host "`n- INFO, repository package successfully downloaded. If firmware version difference detected for any device, update job ID will get created`n"
$message_count += 1
}
else
    {
    $get_current_time=Get-Date -DisplayHint Time
    $get_time_query=$get_current_time - $start_time
    $current_job_execution_time = [String]::Format("{0}:{1}:{2}",$get_time_query.Hours,$get_time_query.Minutes,$get_time_query.Seconds)
    [String]::Format("- INFO, repository job ID {0} not marked completed, current status: {1}",$repo_job_id,$overall_job_output.Message)
    Start-Sleep 10
    }
}

Start-Sleep 3
Write-Host
[String]::Format("- PASS, {0} job ID marked as completed!",$repo_job_id)
Write-Host "`n- Detailed final job status results:"
$uri ="https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/$repo_job_id"
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
$overall_job_output


$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs"
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
$get_job_id_uris_new = $result.Content | ConvertFrom-Json
$latest_job_ids = @()
foreach ($item in $get_job_id_uris_new.Members)
{
$convert_to_string = [string]$item
$get_job_id_new = $convert_to_string.Split("/")[-1].Replace("}","")
$latest_job_ids += $get_job_id_new

}
[System.Collections.ArrayList]$latest_job_ids = $latest_job_ids
$latest_job_ids.Remove($repo_job_id)
$new_update_job_ids = @()


foreach ($item in $latest_job_ids)
{
    if  ($current_job_ids -notcontains $item)
    {
    $new_update_job_ids += $item
    }
}
$set_true_boolean = $true
$set_false_boolean = $false
#if ($new_update_job_ids.Count -eq 0 -and $ApplyUpdate -eq $set_false_boolean -and $RebootNeeded -eq $set_false_boolean -or $RebootNeeded -eq $set_true_boolean)
if ($new_update_job_ids.Count -eq 0 -and $ApplyUpdate -eq "False")
{
Write-Host "- INFO, ApplyUpdate = False detected. Execute cmdlet again using argument 'get_repo_update_list' to see if any firmware differences were detected or execute 'get_job_queue' to check if any downloaded jobs were created."
return
}

if ($new_update_job_ids.Count -eq 0)
{
Write-Host "- INFO, no update job id(s) created. All server components firmware version match the firmware version packages on the repository"
return
}

if ($reboot_needed_flag -eq "False" -or $no_reboot_flag -eq "True")
{
Write-Host "`n- INFO, 'RebootNeeded' argument set to False or missing, no reboot executed. Check overall Job Queue for status of update jobs using 'get_job_queue' argument. If any job ID(s) are marked as scheduled, these will execute on next server manual reboot.`n"
return
}
 
Write-Host "- INFO, update job(s) created due to firmware version difference detected. Cmdlet will now loop through each update job ID until all are marked completed"
Write-Host "- INFO, if iDRAC firmware version change detected, this update job will execute last`n"

foreach ($item in $new_update_job_ids)
{   
while ($true)
{
$RID_search = [string]$item
if ($RID_search.Contains("RID"))
{
break
}

$uri ="https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/$item"
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
if ($overall_job_output.Message -eq "Job failed." -or $overall_job_output.Message -eq "Failed")
    {
    Write-Host
    [String]::Format("- FAIL, job not marked as completed, detailed error info: {0}",$overall_job_output)
    Write-Host "`n- WARNING, script will exit due to job failure detected. Check the overall job queue for status on any other update jobs which were also executed."
    return
    }
elseif ($overall_job_output.JobState -eq "Completed")
{
Write-Host
[String]::Format("- PASS, {0} job ID marked as completed!",$item)
Write-Host "`n- Detailed final job status results:"
$uri ="https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/$item"
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
$overall_job_output
break
}

else
    {
    [String]::Format("- INFO, update job ID {0} not marked completed, current status: {1}",$item,$overall_job_output.Message)
    Start-Sleep 10
    }
}
}



Write-Host "`n- Execution of 'InstallFromRepositoryOemREDFISH' cmdlet complete -`n"
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
Write-Host "`n- INFO, iDRAC version detected does not support this feature using Redfish API`n"
$get_result
return
}




if ($get_firmware_versions_only)
{
get_firmware_versions
}

elseif ($get_repo_update_list)
{
get_repo_update_list
}

elseif ($install_from_repository)
{
install_from_repository
}

elseif ($get_job_queue)
{
get_job_queue
}

else
{
Write-Host "- FAIL, either incorrect parameter(s) used or missing required parameters(s)"
}


}





