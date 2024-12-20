<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 9.0
Copyright (c) 2018, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>




<#
.Synopsis
   iDRAC cmdlet using Redfish API to either get network device IDs, get network port IDs, get network port properties or set network properties
.DESCRIPTION
   iDRAC cmdlet using Redfish API to either get network device IDs, get network port IDs, get network port properties or set network properties.
   - idrac_ip: REQUIRED, pass in iDRAC IP address
   - idrac_username: REQUIRED, pass in iDRAC username
   - idrac_password: REQUIRED, pass in iDRAC username password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_network_device_IDs: OPTIONAL, get network device and port IDs for your system.
   - get_detail_network_device_ID_info: OPTIONAL, pass in network device ID string to get detailed information. Example, pass in "NIC.Integrated.1"
   - get_detail_network_port_ID_info:  OPTIONAL, pass in network port ID string to get detailed information. Example, pass in "NIC.Integrated.1-1-1"
   - get_network_port_properties: OPTIONAL, pass in network port ID to get properties. Example, pass in "NIC.Integrated.1-1-1"
   - generate_set_properties_ini_file: OPTIONAL, generate ini file needed to set network attributes. If setting network properties, you must generate this ini file first which you will modify for setting attributes. NOTE: This file will be generated in the same directory you're executing the cmdlet from.
   - set_network_properties: OPTIONAL, pass in network port ID to set network properties in the ini file (make sure the ini file is located in the same directory you are executing the cmdlet from). "job_type" parameter is also required when setting network attributes
   - job_type: OPTIONAL, pass in "n" for creating a config job which will run now. Pass in "s" which will schedule the config job but not reboot the server. Config changes will be applied on next system manual reboot
.EXAMPLE
   .\Set-NetworkPropertiesREDFISH -idrac_ip 192.168.0.120 -username root -password calvin -get_network_port_properties NIC.Integrated.1-1-1
   This example will return network properties for port NIC.Integrated.1-1-1
.EXAMPLE
   .\Set-NetworkPropertiesREDFISH -idrac_ip 192.168.0.120 -get_network_port_properties NIC.Integrated.1-1-1
   This example will first prompt for iDRAC username and password using Get-Credentials, then return network properties for port NIC.Integrated.1-1-1
.EXAMPLE
   .\Set-NetworkPropertiesREDFISH -idrac_ip 192.168.0.120 -get_network_port_properties NIC.Integrated.1-1-1 -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708
   This example will return network properties for port NIC.Integrated.1-1-1 using iDRAC X-auth token session.
.EXAMPLE
   .\Set-Network_PropertiesREDFISH -idrac_ip 192.168.0.120 -username root -password calvin -set_network_properties NIC.Integrated.1-1-1 -job_type n
   This example will set network properties from the ini file for NIC.Integrated.1-1-1 and create a config job for now to reboot the system and apply changes
.EXAMPLE
   Examples of modified hashtable in the ini file for setting network properties. For either iSCSIBoot or FibreChannel nested hastables, you can leave it blank or remove it from the hashtable:
   {"FibreChannel":{},"iSCSIBoot":{"InitiatorIPAddress":"192.168.0.120","InitiatorNetmask":"255.255.255.0"}}
   {"FibreChannel":{"WWNN":"20:00:00:24:FF:12:FC:11"},"iSCSIBoot":{}}
#>

function Set-NetworkPropertiesREDFISH {

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
    [switch]$get_network_device_IDs,
    [Parameter(Mandatory=$False)]
    [string]$get_detail_network_device_ID_info,
    [Parameter(Mandatory=$False)]
    [string]$get_detail_network_port_ID_info,
    [Parameter(Mandatory=$False)]
    [string]$get_network_port_properties,
    [Parameter(Mandatory=$False)]
    [switch]$generate_set_properties_ini_file,
    [Parameter(Mandatory=$False)]
    [string]$set_network_properties,
    [ValidateSet("n", "s")]
    [Parameter(Mandatory=$False)]
    [string]$job_type

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

function check_supported_idrac_version
{
$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters"
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
        Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API" -ForegroundColor Yellow
	    return
	    }
	    else
	    {
	    }
return
}

# Function to get Powershell version

$global:get_powershell_version

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
check_supported_idrac_version

if ($generate_set_properties_ini_file)
{
    if (Test-Path .\set_nic_properties.ini -PathType Leaf)
    {
    Remove-Item "set_nic_properties.ini"
    }
$payload=@{"iSCSIBoot"=@{};"FibreChannel"=@{}} | ConvertTo-Json -Compress

$payload | out-string | add-content "set_nic_properties.ini"
Write-Host "`n- INFO, 'set_nic_properties.ini' file successfully created in this directory you are executing the cmdlet from" -ForegroundColor Yellow
return
}



if ($get_network_device_IDs)
{
$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters"
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
    [String]::Format("`n- PASS, statuscode {0} returned successfully to get network device IDs `n",$result.StatusCode)
    }
    else
    {
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
    }

$get_result = $result.Content | ConvertFrom-Json
$get_result = $get_result.Members
$device_ids=@()
Write-Host "- Network Device IDs Detected for iDRAC $idrac_ip -`n" -ForegroundColor Yellow
    foreach ($i in $get_result)
    {
    $i=[string]$i
    $i=$i.Split("/")[-1].Replace("}","")
    $i
    $device_ids+=$i
    }
        foreach ($i in $device_ids)
        {
        $uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/$i/NetworkDeviceFunctions"
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
        $get_result = $result.Content | ConvertFrom-Json
        $get_result = $get_result.Members
        $port_ids=@()
        Write-Host "`n- Network port IDs Detected for network ID $i -`n" -ForegroundColor Yellow
            foreach ($ii in $get_result)
            {
            $ii=[string]$ii
            $ii=$ii.Split("/")[-1].Replace("}","")
            $ii
            $port_ids+=$ii
            }
        }
Write-Host
Return
}


if ($get_detail_network_device_ID_info)
{
$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/$get_detail_network_device_ID_info"
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
    [String]::Format("`n- PASS, statuscode {0} returned successfully to get detail info for network device ID '{1}'`n",$result.StatusCode,$get_detail_network_device_ID_info)
    }
    else
    {
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
    }
    Write-Host "- Detailed information for network device ID '$get_detail_network_device_ID_info'" -ForegroundColor Yellow
    $get_result = $result.Content | ConvertFrom-Json
    $get_result
    return    
}

if ($get_detail_network_port_ID_info)
{
$get_details = $get_detail_network_port_ID_info.Split("-")
$device_id = $get_details[0]
$port_id = $get_details[0]+"-"+$get_details[1]
$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/$device_id/NetworkPorts/$port_id"
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
    [String]::Format("`n- PASS, statuscode {0} returned successfully to get detail info for port device ID '{1}'`n",$result.StatusCode,$get_detail_network_port_ID_info)
    }
    else
    {
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
    }
    Write-Host "- Detailed information for network device ID '$get_detail_network_port_ID_info'" -ForegroundColor Yellow
    $get_result = $result.Content | ConvertFrom-Json
    $get_result
Return    
}



if ($get_network_port_properties)
{
$split_properties = $get_network_port_properties.Split("-")
$device_id = $split_properties[0]
$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/$device_id/NetworkDeviceFunctions/$get_network_port_properties"
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
    [String]::Format("`n- PASS, statuscode {0} returned successfully to get properties for port device ID '{1}'`n",$result.StatusCode,$get_network_port_properties)
    }
    else
    {
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
    }
    $get_result = $result.Content | ConvertFrom-Json
    Write-Host "- iSCSIBoot properties for '$get_network_port_properties'" -ForegroundColor Yellow
        if ($get_result.iSCSIBoot.Length -eq 0)
        {
        Write-Host "`n- WARNING, no iSCSIBoot properties detected for $get_network_port_properties'`n"
        }
        else
        {
        $get_result.iSCSIBoot
        }
    Write-Host "- FibreChannel properties for '$get_network_port_properties'`n" -ForegroundColor Yellow
        if ($get_result.FibreChannel.Length -eq 0)
        {
        Write-Host "`n- WARNING, no FibreChannel properties supported for $get_network_port_properties'" 
        }
        else
        {
        $get_result.FibreChannel
        }
Return    
}

if ($set_network_properties)
{

try {
    $JsonBody = Get-Content set_nic_properties.ini -ErrorVariable RespErr
    }
catch [System.Management.Automation.ActionPreferenceRespErrException] {
    Write-Host "`n- WARNING, 'set_nic_properties.ini' file not detected. Make sure this file is located in the same directory you are running the cmdlet from"  -ForegroundColor Yellow
    $RespErr
    return
}

$JsonBody_patch_command=Get-Content set_nic_properties.ini
$JsonBody=[string]$JsonBody_patch_command

    if ($JsonBody.Contains('"FibreChannel":{}'))
    {
    $JsonBody=$JsonBody.Replace('"FibreChannel":{},',"")
    }
    if ($JsonBody.Contains('"iSCSIBoot":{}'))
    {
    $JsonBody=$JsonBody.Replace(',"iSCSIBoot":{}',"")
    }

$properties = $JsonBody | ConvertFrom-Json
$set_properties = @{}
$properties.psobject.properties | Foreach { $set_properties[$_.Name] = $_.Value }
Write-Host "`n- INFO, new property change(s) for: '$set_network_properties'" -ForegroundColor Yellow
$set_properties
$split_properties = $set_network_properties.Split("-")
$device_id = $split_properties[0]

$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/$device_id/NetworkDeviceFunctions/$set_network_properties/Settings"
    if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
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
    
    $result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
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
    $status_code = $result.StatusCode
    
    Write-Host "`n- PASS, statuscode $status_code returned successfully for PATCH command to set property pending value(s) for port device ID '$set_network_properties'" -ForegroundColor Green
    }
    else
    {
    Write-Host "`n- FAIL, status code $status_code returned for PATCH command" -ForegroundColor Red
    return
    }
  
}

if ($job_type -eq "n")
{
$get_properties = $set_network_properties.Split("-")
$device_id = $get_properties[0]

$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/$device_id/NetworkDeviceFunctions/$set_network_properties/Settings"
$JsonBody = @{"@Redfish.SettingsApplyTime"=@{"ApplyTime"="OnReset"}} | ConvertTo-Json -Compress
    if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
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
    
    $result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}
        if ($result.StatusCode -eq 202)
        {
        $status_code = $result.StatusCode
       
        Write-Host "`n- PASS, statuscode $status_code returned successfully for PATCH command to create reboot now config job for port device ID '$set_network_properties'`n" -ForegroundColor Green
        Start-Sleep 10
        }
        else
        {
        
        Write-Host "`n- FAIL, status code $status_code returned for PATCH command" -ForegroundColor Red
        return
        }
$get_result = $result.RawContent | ConvertTo-Json -Compress
$job_search = [regex]::Match($get_result, "JID_.+?r").captures.groups[0].value
$job_id = $job_search.Replace("\r","")
Write-Host "- INFO, job ID created for reboot now config job is: '$job_id'"
    
    while ($overall_job_output.JobState -ne "Scheduled")
    {
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
        if ($overall_job_output.JobState -eq "Failed") 
        {
        Write-Host
        [String]::Format("- FAIL, final job status is: {0}",$overall_job_output.JobState)
        return
        }
        
    [String]::Format("- INFO, job ID {0} not marked as scheduled, current job message: {1}",$job_id, $overall_job_output.Message)
    Start-Sleep 1
    }
    Write-Host "`n- PASS, reboot now job ID '$job_id' successfully marked as scheduled, rebooting the server`n"
    
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

Write-Host
Write-Host "- INFO, cmdlet will now poll job ID every 15 seconds until job ID '$job_id' marked completed"
Write-Host


$get_time = Get-Date -DisplayHint Time
$start_time = Get-Date
$end_time = $start_time.AddMinutes(30)

while ($overall_job_output.JobState -ne "Completed")
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
    if ($overall_job_output.JobState -eq "Failed")
    {
    Write-Host
    [String]::Format("- FAIL, job marked as failed, detailed error info: {0}",$overall_job_output)
    return
    }
    elseif ($loop_time -gt $end_time)
    {
    Write-Host "- FAIL, timeout of 30 minutes has been reached before marking the job completed"
    return
    }
    else
    {
    [String]::Format("- INFO, job not marked completed, current message: {0}",$overall_job_output.Message)
    Start-Sleep 15
    }
    }
$get_time_now = Get-Date -DisplayHint Time
$completion_time = $get_time_now - $get_time
$final_completion_time = $completion_time | select Minutes,Seconds
Write-Host "`n- PASS, '$job_id' job ID marked completed! Job completed in $final_completion_time`n" -ForegroundColor Green 

return

}

if ($job_type -eq "s")
{
$split_properties = $set_network_properties.Split("-")
$device_id = $split_properties[0]

$u = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters/$device_id/NetworkDeviceFunctions/$set_network_properties/Settings"
$JsonBody = @{"@Redfish.SettingsApplyTime"=@{"ApplyTime"="OnReset"}} | ConvertTo-Json -Compress
    if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
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
    
    $result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}
        if ($result.StatusCode -eq 202)
        {
        $status_code = $result.StatusCode
        Write-Host "`n- PASS, statuscode $status_code returned successfully for PATCH command to create staged config job for port device ID '$set_network_properties'`n" -ForegroundColor Green
        }
        else
        {
        Write-Host "`n- FAIL, status code $status_code returned for PATCH command" -ForegroundColor Red
        return
        }
$get_content = $result.RawContent | ConvertTo-Json -Compress
$get_jobID = [regex]::Match($get_content, "JID_.+?r").captures.groups[0].value
$job_id = $get_jobID.Replace("\r","")
Write-Host "- INFO, job ID created for reboot now config job is: '$job_id'"
    
    while ($overall_job_output.JobState -ne "Scheduled")
    {
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
        if ($overall_job_output.JobState -eq "Failed") 
        {
        Write-Host
        [String]::Format("- FAIL, final job status is: {0}",$overall_job_output.JobState)
        return
        }
        
    [String]::Format("- INFO, job ID {0} not marked as scheduled, current job message: {1}",$job_id, $overall_job_output.Message)
    Start-Sleep 1
    }
Write-Host "`n- PASS, staged config job ID '$job_id' successfully marked as scheduled, configuration changes will not be applied until next system manual reboot" -ForegroundColor Green
return
}

}


