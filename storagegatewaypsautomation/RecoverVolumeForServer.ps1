param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[string]$RegionToDeploy = "us-east-1",
[string]$ComputerName = "$($env:computername).gcmlp.com",
[string]$InitiatorPrefix = "iqn.1991-05.com.microsoft",
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

Set-DefaultAWSRegion $regionToDeploy

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

function Convert-VariabletoLowerCase($ComputerName) {
$ComputerName.ToLower()
}

function Get-SGWVolumeForServer($name,$credentials) {
  (Get-EC2Snapshot -Credential $credentials  -filter @( @{name="description"; values="SGW Snapshot for Target Volume $name"})).VolumeId | select -Unique
}

function Get-VolumeDetails($volumeID,$credentials) {
(Get-SGVolume -GatewayARN $gatewayARN -Credential $credentials | ? { $_.VolumeId -eq $volumeID}).VolumeARN
}

function Delete-BadVolumeForSGW($volumeARN,$credentials){
  Remove-SGVolume -VolumeARN $volumeARN -Credential $credentials -Force -Confirm:$False
}

function Get-ChapAuthenticationForTarget() {
  $secretUsedToAuthenticateTarget = (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateTarget").Content
  return $secretUsedToAuthenticateTarget
}

function Get-ChapAuthenticationForInitiator() {
  $secretUsedToAuthenticateInitiator = (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateInitiator").Content
  return $secretUsedToAuthenticateInitiator
}

function Get-GatewayARN($credentials) {
	$gateway = Get-SGGateway -Credential $credentials | where GatewayName -eq "$sgGatewayName"
		   If (-not $gateway) {
		throw "ARN should not be blank"
	}
	$gatewayARN = $gateway.GatewayARN
	return $gatewayARN
}

function Get-SGWInstanceIP($gatewayARN,$credentials) {
$sgInstanceIP = ((Get-SGGatewayInformation -GatewayARN $gatewayARN).GatewayNetworkInterfaces).IPv4Address
	If (-not $sgInstanceIP) {
		throw "Instance not returned"
	}
}

Function Invoke-FindVolumesandSnapshots($volumeIds,$credentials) {
       Foreach($volume in $volumeIds) {
    $snapshots = Get-EC2Snapshot -filter @( @{name="volume-id"; values=$volume}) | Sort-Object StartTime | Select -Last 2
	$snapshots = @()+$snapshots
		   If ($snapshots.Count -lt 2) {
			$recurrentInHours = 24
}
	Else{
			$timeDiff = New-TimeSpan $snapshots[0].StartTime$snapshots[1].StartTime
			$recurrentInHours = $timeDiff.Hours
}

			$gatewayARN = Get-GatewayARN
			Add-RecoveredVolumeToSGW $snapshots[0] $gatewayARN $recurrentInHours
       }
}

Function Get-ClientToken ($length = 15) {
    $punc = 46..46
    $digits = 48..57
    $letters = 65..90 + 97..122
    $password = get-random -count $length `
        -input ($punc + $digits + $letters) |
            % -begin { $aa = $null } `
            -process {$aa += [char]$_} `
            -end {$aa}
    return $password
}

function Add-RecoveredVolumeToSGW($snapshot,$gatewayARN,$recurrentInHours,$name,$sgInstanceIP,$secretUsedToAuthenticateTarget,$secretUsedToAuthenticateInitiator) {
	Write-Host "Running function Add-RecoveredVolumesToSGW with "$snapshot.snapshotId""
	$clientToken = Get-ClientToken
	Write-Host "client-token = $clientToken"
	$volumesizeinbytes = $snapshot.VolumeSize*1024*1024*1024
	Write-Host "volumesize = $volumesizeinbytes"
	$name = Convert-VariabletoLowerCase $computerName
	Write-Host "name = $name"
	$gatewayARN = Get-GatewayARN
	Write-Host "gatewayARN = $gatewayARN"
	$sgInstanceIP = ((Get-SGGatewayInformation -GatewayARN $gatewayARN).GatewayNetworkInterfaces).IPv4Address
	Write-Host "sgInstanceIP = $sgInstanceIP"
	$secretUsedToAuthenticateTarget = (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateTarget").Content
	Write-Host "secret for target is $secretUsedToAuthenticateTarget"
	$secretUsedToAuthenticateInitiator = (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateInitiator").Content
	Write-Host "secret for initiator is $secretUsedToAuthenticateInitiator"
	$volumeAttributes = New-SGCachediSCSIVolume -GatewayARN $gatewayARN -SnapshotId $snapshot.  -VolumeSizeInBytes $volumesizeinbytes -TargetName $name -NetworkInterfaceId $sgInstanceIP -ClientToken $clientToken
	$volumeARN = $volumeAttributes.VolumeARN
	Write-Host "VolumeARN = $volumeARN"
	$targetARN = $volumeAttributes.TargetARN
	Write-Host "TargetARN = $targetARN"
	$initiatorName =  $targetARN.Split("/")[3].Split(":")[1]
	Write-Host "Initiator Name is $initiatorName"
	$initiator = "$($InitiatorPrefix):$initiatorName"
	$chapEnabled = ((Get-SGCachediSCSIVolume -VolumeARNs $volumeARN).VolumeiSCSIAttributes).ChapEnabled
	Write-Host "chap enabled = $chapEnabled"
	If ($chapEnabled -eq $false) {
		Update-SGChapCredentials -TargetARN $targetARN -InitiatorName $initiator -SecretToAuthenticateInitiator $secretUsedToAuthenticateInitiator -SecretToAuthenticateTarget $secretUsedToAuthenticateTarget

	Set-IscsiTarget $name $secretUsedToAuthenticateInitiator
	Add-TagsToVolumes $volumeARN $SgStackName $initiatorName
	Update-SnapshotScheduleForVolumes $volumeARN $recurrentInHours $initiatorName
	}
}

function Add-TagsToVolumes($volumeARN,$SgStackName,$initiatorName) {
			Add-SGResourceTag -ResourceARN $volumeARN -Tag @( @{ Key="Name";Value = "$sgStackName" },@{ Key = "VolumeName"; Value = $initiatorName},@{ Key = "Expense Id"; Value = "AWS-GCM-SEO-Direct"},@{ Key = "Business Entity"; Value = "SHD"},@{ Key = "Owner"; Value = "SEO"},@{ Key = "App Team"; Value = "INF"} )
}
function Update-SnapshotScheduleForVolumes($volumeARN,$recurrentInHours,$initiatorName) {
		$configFilePrefix = $sgStackName.Split('-')[0]
		Update-SGSnapshotSchedule -VolumeARN $volumeARN -StartAt "00" -RecurrenceInHours $recurrentInHours -Description "SGW Snapshot for Target Volume $initiatorName"
}

function Set-IscsiTarget($name,$secretUsedToAuthenticateInitiator) {
	Update-IscsiTarget
  $iSCSITarget = (Get-IscsiTarget -NodeAddress *$name).NodeAddress
	Write-Host "iSCSITarget is $iSCSITarget"
  If (-not $iSCSITarget) {
		Throw "iSCSI Target Required" }
		Else {Connect-IscsiTarget -NodeAddress $iSCSITarget -AuthenticationType MUTUALCHAP -ChapSecret $secretUsedToAuthenticateInitiator
	}
}

function Start-VolumeRecoveryForServer() {
	$roleARN = Get-Role
	Get-TemporaryCredentials $roleARN
	$credentials = Get-TemporaryCredentials $roleARN
	$name = Convert-VariabletoLowerCase $computerName
	$volumeId = Get-SGWVolumeForServer $name $credentials
	$volumeARN = Get-VolumeDetails $volumeId $credentials
	$sgwVolumeStatus = (Get-ServerVolumeStatus $volumeARN).VolumeStatus
	$gatewayARN = Get-GatewayARN $credentials
	$sgInstanceIP = Get-SGWInstanceIP $gatewayARN $credentials
	Invoke-FindVolumesandSnapshots $volumeId
}
If(-Not $TestMode) {
	Start-VolumeRecoveryForServer
  }