param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$ComputerName = "$($env:computername).gcmlp.com",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[string]$RegionToDeploy = "us-east-1",
[switch]$TestMode = $False
)

$ErrorActionPreference = "SilentlyContinue"

if (Get-Module -ListAvailable -Name AWSPowershell) {
    Write-Host "Module exists"
} else {
	Write-Host "Installing Module"
	Install-PackageProvider nuget -force
	Install-Module AWSPowershell -Confirm:$false -Force
}
Import-Module AWSPowershell -Force

Set-DefaultAWSRegion $RegionToDeploy

function Get-Role() {
	$environment = $SgStackName.Split('-')[0]
	$lifecycle = $SgStackName.Split('-')[2]
	$roleARN = (Get-IAMRoles | ? {$_.RoleName -like "$environment-cfnresources-$lifecycle-DeployerRole-*"}).Arn
    return $roleARN
}

function Get-TemporaryCredentials($roleARN) {
	$Response = (Use-STSRole -Region $regionToDeploy -RoleArn $roleARN  -RoleSessionName $environment).Credentials
	$Credentials = New-AWSCredentials -AccessKey $Response.AccessKeyId -SecretKey $Response.SecretAccessKey -SessionToken $Response.SessionToken
	return $Credentials
}

function Get-EventLogSource() {
	$logFileSourceExists = Get-EventLog -LogName Application -ErrorAction Ignore | ? {$_.Source -eq "SGW Health Check"}
if (! $logFileSourceExists) {
    New-EventLog -LogName Application -Source "SGW Health Check" }
}

function Set-iSCSIServiceState() {
	$msiSCSIStatus = Get-WmiObject win32_service -ComputerName localhost | where {$_.name -eq "MSiSCSI"}
	If ($msiSCSIStatus.State -eq "Stopped" -or $msiSCSIStatus.State -eq "disabled")
	{Set-Service -name MSiSCSI -startupType automatic -status running}
	Else {Write-Host "Service is already running"}
}

function Get-GatewayARN($credentials) {
	$gateway = Get-SGGateway -Credential $credentials | where GatewayName -eq "$sgGatewayName"
		   If (-not $gateway) {
		throw "ARN should not be blank"
	}
	$gatewayARN = $gateway.GatewayARN
	return $gatewayARN
}

function Get-PingResultofSGW($gatewayARN,$credentials) {
    Update-IscsiTarget
	$gatewayInfo = Get-SGGatewayInformation -GatewayARN $gatewayARN -Credential $credentials -ErrorAction SilentlyContinue
    $testConnectionStatus = Test-Connection -ComputerName $ComputerName -quiet
	$gatewayInstanceIP = ($gatewayInfo.GatewayNetworkInterfaces).Ipv4Address
	if ($testConnectionStatus -eq $True) {
    Get-SGWDetails $gatewayInfo }
    Else {Invoke-ServiceRestarts}
}

function Get-SGWDetails($gatewayInfo) {
	$gatewayState = $gatewayInfo.GatewayState
	$iscsiSessionStatus = Get-ISCSITarget | ? {$_.NodeAddress -like "*$ComputerName" }
	Write-Host "ComputerName is $computerName"
	Write-Host "gateway state is $gatewayState"
	Write-Host "iSCSISessionState is "$iscsiSessionStatus.IsConnected""
	If ($gatewayInfo.GatewayState -eq "RUNNING" -and $iscsiSessionStatus.IsConnected -eq $True) {
	Write-EventLog –LogName Application –Source "SGW Health Check" –EntryType Information –EventID 1 –Message "Storage Gateway is $gatewayState"
    New-SumoAlert "Storage Gateway is $gatewayState" "INFO"
	}
	ElseIf ($gatewayInfo.GatewayState -eq "SHUTDOWN"  -and $iscsiSessionStatus.IsConnected -eq $False) {
	Write-EventLog –LogName Application –Source "SGW Health Check" –EntryType Error –EventID 50 –Message "Storage Gateway is $gatewayState. Please wait for it to become available. Restarting iSCSI service as a precaution"
    New-SumoAlert "Storage Gateway is $gatewayState. Please wait for it to become available. Restarting iSCSI service as a precaution" "ERROR"
    Restart-Service MSiSCSI
	}
    ElseIf ($gatewayInfo.GatewayState -eq "RUNNING" -and $iscsiSessionStatus.IsConnected -eq $False) {
    Write-EventLog –LogName Application –Source "SGW Health Check" –EntryType Error –EventID 100 –Message "Storage Gateway is $gatewayState. Restarting iSCSI Service"
    New-SumoAlert "Storage Gateway is $gatewayState. Restarting iSCSI Service" "ERROR"
	Restart-Service MSiSCSI
    Update-IscsiTarget
	}
    ElseIf ($gatewayInfo.GatewayState -ne "SHUTDOWN" -or "RUNNING" -and $iscsiSessionStatus.IsConnected -eq $False) {
    Write-EventLog –LogName Application –Source "SGW Health Check" –EntryType Error –EventID 150 –Message "Storage Gateway is $gatewayState. Possible Instance Restart. Restarting Services"
    New-SumoAlert "Storage Gateway is $gatewayState. Possible Instance Restart. Restarting Services" "ERROR"
    Restart-Service MSiSCSI
    Update-IscsiTarget
    }
	ElseIf ($gatewayInfo.GatewayState -eq "RUNNING" -and $iscsiSessionStatus.IsConnected -ne $False -or $iscsiSessionStatus.IsConnected -ne $True) {
	Write-EventLog –LogName Application –Source "SGW Health Check" –EntryType Error –EventID 200 –Message "Storage Gateway is $gatewayState. Services failed to recover. Restarting Services"
    New-SumoAlert "Storage Gateway is $gatewayState. Services failed to recover. Restarting Services" "ERROR"
	Restart-Service MSiSCSI
    Update-IscsiTarget
	}
	Else {Exit}
}

function Convert-VariabletoLowerCase($ComputerName) {
$ComputerName.ToLower()
}

function Get-SGWVolumeForServer($name,$credentials) {
  (Get-EC2Snapshot -Credential $credentials  -filter @( @{name="description"; values="SGW Snapshot for Target Volume $name"})).VolumeId | select -Unique
}

function Get-VolumeDetails($volumeID,$credentials) {
(Get-SGVolume -GatewayARN $gatewayARN -Credential $credentials | ? { $_.VolumeId -eq $volumeID}).VolumeARN
}

function Get-ServerVolumeStatus($volumeARN,$credentials) {
  $sgwVolumeStatus = (Get-SGCachediSCSIVolume -VolumeARNs $volumeARN -Credential $credentials).VolumeStatus
  write-host "volume status is $sgwVolumeStatus"
  return $sgwVolumeStatus
}

function New-SumoAlert($message, $severity) {
  $url = 'https://endpoint1.collection.us2.sumologic.com/receiver/v1/http/ZaVnC4dhaV3kQ3miD09zNvhAyo5NMgUq8I1Y31T_n0xNLa3O81g43kt5YocRa2i_TxzMPeqMkxS8jLdYYCJs08TKAh0sRx5BuWF3NHvppe7E1C0UEOdciQ=='
  $payload = '{
    "message": "' + $message + '",
    "vpc": "infprd",
    "application": "goserver",
    "environment": "prd",
    "lifecycle": "prd",
    "host": "' + $env:COMPUTERNAME + '",
    "source": "StorageGateway",
    "severity": "' + $severity + '"
    }'
    Invoke-WebRequest -UseBasicParsing -Uri $url -Method:POST -Body:$payload -ContentType:'application/json' | Out-Null
}

function Invoke-ServiceRestarts(){
    Restart-Service MSiSCSI
    Update-IscsiTarget
}

function Invoke-SGWTestForLocalServer() {
	$roleARN = Get-Role
	Get-EventLogSource
	$credentials = Get-TemporaryCredentials $roleARN
	$gatewayARN = Get-GatewayARN $credentials
	Get-PingResultofSGW $gatewayARN $credentials
    $name = Convert-VariabletoLowerCase $computerName
    $volumeId = Get-SGWVolumeForServer $name $credentials
    $volumeARN = Get-VolumeDetails $volumeId $credentials
	$sgwVolumeStatus = Get-ServerVolumeStatus $volumeARN $crednetials
     if ($sgwVolumeStatus -eq "IRRECOVERABLE") {
		     New-SumoAlert "Storage Gateway is Running but a volume is marked as IRRECOVERABLE. Please log into the server and run the script d:\RecoverVolumeForServer.ps1" "SEVERE"
	      } New-SumoAlert "Storage Gateway Are Healthy!" "INFO"
}

If(-Not $TestMode) {
	Invoke-SGWTestForLocalServer
}