param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$ComputerName = "$($env:computername).gcmlp.com",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[string]$driveLetter = "E",
[switch]$TestMode = $False
)
if (Get-Module -ListAvailable -Name AWSPowershell) {
    Write-Host "Module exists"
} else {
	Write-Host "Installing Module"
	Install-PackageProvider nuget -force
	Install-Module AWSPowershell -Confirm:$false -Force
}
Import-Module AWSPowershell -Force

Set-DefaultAWSRegion us-east-1

function Get-Role() {
	$environment = $SgStackName.Split('-')[0]
	$lifecycle = $SgStackName.Split('-')[2]
	$roleARN = (Get-IAMRoles | ? {$_.RoleName -like "$environment-cfnresources-$lifecycle-DeployerRole-*"}).Arn
	return $roleARN
}

function Get-TemporaryCredentials($roleARN) {
	$response = (Use-STSRole -Region $regionToDeploy -RoleArn $roleARN  -RoleSessionName $computerName).Credentials
	$credentials = New-AWSCredentials -AccessKey $Response.AccessKeyId -SecretKey $Response.SecretAccessKey -SessionToken $Response.SessionToken
	return $credentials
}

function Set-iSCSIServiceState() {
	$msiSCSIStatus = Get-WmiObject win32_service -ComputerName localhost | where {$_.name -eq "MSiSCSI"}
	If ($msiSCSIStatus.State -eq "Stopped" -or $msiSCSIStatus.State -eq "disabled")
	{Set-Service -name MSiSCSI -startupType automatic -status running}
	Else {Write-Host "Service is already running"}
}
function Get-ChapAuthenticationForTarget() {
 (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateTarget").Content
}

function Get-ChapAuthenticationForInitiator() {
(Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateInitiator").Content
}

function Get-GatewayARN($credentials) {
	$gateway = Get-SGGateway -credential $credentials | where GatewayName -eq "$sgGatewayName"
		   If (-not $gateway) {
		throw "ARN should not be blank"
	}
	$gatewayARN = $gateway.GatewayARN
	return $gatewayARN
}
function Get-SGWInstanceIP($gatewayARN,$credentials) {
  $sgInstanceIP = ((Get-SGGatewayInformation -GatewayARN $gatewayARN -Credential $credentials ).GatewayNetworkInterfaces).IPv4Address
	If (-not $sgInstanceIP) {
		throw "Instance not returned"
	}
  return $sgInstanceIP
}
function Create-IscsiTargetPortal($sgInstanceIP) {
    New-IscsiTargetPortal -TargetPortalAddress $SgInstanceIP
}

function Set-IscsiTargetSecurity($secretUsedToAuthenticateTarget) {
  Set-IscsiChapSecret -ChapSecret $secretUsedToAuthenticateTarget
}

function Set-IscsiTarget($computerName,$secretUsedToAuthenticateInitiator) {
  $iSCSITarget = (Get-IscsiTarget -NodeAddress *$computername).NodeAddress
  If (-not $iSCSITarget) {
		Throw "iSCSI Target Required" }
		Else {Connect-IscsiTarget -NodeAddress $iSCSITarget -AuthenticationType MUTUALCHAP -ChapSecret $secretUsedToAuthenticateInitiator -IsPersistent $true
	}
}
function Get-LocalDiskNumber() {
  Start-Sleep -s 30
  $disk = (Get-Disk -FriendlyName "Amazon Storage Gateway SCSI Disk Device")
  If (-not $disk) {
		Throw "No Disk Detected"
	}
	$diskNumber = $disk.Number
  If ($disk.Size -lt "2199023255552" ) {
  New-LocalVolumeForServerMBR $diskNumber }
  Else {New-LocalVolumeForServerGPT $diskNumber}
}
function New-LocalVolumeForServerMBR($diskNumber) {
  $diskStatus = Get-Disk
  If ($diskStatus.PartitionStyle -eq 'raw' ) {
   Get-Disk | Where Number -EQ $diskNumber | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter $driveLetter -UseMaximumSize
 }
}

function New-LocalVolumeForServerGPT($diskNumber) {
  $diskStatus = Get-Disk
  If ($diskStatus.PartitionStyle -eq 'raw' ) {
  Get-Disk | Where Number -EQ $diskNumber | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -DriveLetter $driveLetter -UseMaximumSize
}
}
function Format-VolumeForLocalServer($driveLetter) {
  Start-Sleep -s 30
  Format-Volume -DriveLetter $driveLetter -FileSystem NTFS -NewFileSystemLabel "AWS-Storage" -Confirm:$false
}

function New-VolumeForServer() {
	Set-iSCSIServiceState
	$roleARN = Get-Role
	$credentials = Get-TemporaryCredentials $roleARN
	$gatewayARN = Get-GatewayARN $credentials
	$sgInstanceIP = Get-SGWInstanceIP $gatewayARN $credentials
	Create-IscsiTargetPortal $sgInstanceIP
	$secretUsedToAuthenticateTarget = Get-ChapAuthenticationForTarget
	Set-IscsiTargetSecurity $secretUsedToAuthenticateTarget
	$secretUsedToAuthenticateInitiator = Get-ChapAuthenticationForInitiator
	Set-IscsiTarget $computername $secretUsedToAuthenticateInitiator
	Get-LocalDiskNumber
	Format-VolumeForLocalServer $driveLetter
}

If(-Not $TestMode) {
  New-VolumeForServer
}