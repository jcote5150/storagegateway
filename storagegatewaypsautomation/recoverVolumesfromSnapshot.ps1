param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[string]$RegionToDeploy = "us-east-1",
[string]$InitiatorPrefix = "iqn.1991-05.com.microsoft",
[switch]$TestMode = $False
)

$ConfirmPreference = "None"

if (Get-Module -ListAvailable -Name AWSPowershell) {
    Write-Host "Module exists"
} else {
	Write-Host "Installing Module"
	Install-PackageProvider nuget -force
	Install-Module AWSPowershell -Confirm:$false -Force
}
Import-Module AWSPowershell -Force

Set-DefaultAWSRegion $regionToDeploy

Function Get-SGWSnapshots() {
       (Get-EC2Snapshot -filter @( @{name="description"; values="SGW Snapshot for Target *"})).VolumeId | select -Unique
}

Function Invoke-FindVolumesandSnapshots($volumeIds) {
       Foreach($volumeId in $volumeIds) {
    $snapshots = Get-EC2Snapshot -filter @( @{name="volume-id"; values=$volumeId}) | Sort-Object StartTime | Select -Last 2

$snapshots = @()+$snapshots
		   If ($snapshots.Count -lt 2) {
$recurrentInHours = 24
}
Else{
    $timeDiff = New-TimeSpan $snapshots[0].StartTime$snapshots[1].StartTime
    $recurrentInHours = $timeDiff.Hours
}

	$gatewayARN = Get-GatewayARN
    Add-RecoveredVolumesToSGW $snapshots[0] $gatewayARN $recurrentInHours
       }
}

function Get-GatewayARN()
{
	$gateway = Get-SGGateway | where GatewayName -eq "$sgGatewayName"
		   If (-not $gateway) {
		throw "ARN should not be blank"
	}
	$gatewayARN = $gateway.GatewayARN
	$sgInstanceIP = ((Get-SGGatewayInformation -GatewayARN $gatewayARN).GatewayNetworkInterfaces).IPv4Address
	If (-not $sgInstanceIP) {
		throw "Instance not returned"
	}
	return $gatewayARN
}

function Add-RecoveredVolumesToSGW($snapshot, $gatewayARN, $recurrentInHours) {
	Write-Host "Running function Add-RecoveredVolumesToSGW with "$snapshot.snapshotId""
	$secretUsedToAuthenticateTarget = (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateTarget").Content
	$secretUsedToAuthenticateInitiator = (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateInitiator").Content
	$clientToken = Get-ClientToken
	$volumesizeinbytes = $snapshot.VolumeSize*1024*1024*1024
    $sgInstanceIP = ((Get-SGGatewayInformation -GatewayARN $gatewayARN).GatewayNetworkInterfaces).IPv4Address
	$volumeAttributes = New-SGCachediSCSIVolume -GatewayARN $gatewayARN -SnapshotId $snapshot.snapshotId -VolumeSizeInBytes $volumesizeinbytes -TargetName $snapshot.Description.Split(' ')[5] -NetworkInterfaceId $sgInstanceIP -ClientToken $clientToken
	$volumeARN = $volumeAttributes.VolumeARN
	$targetARN = $volumeAttributes.TargetARN
	$initiatorName =  $targetARN.Split("/")[3].Split(":")[1]
	$initiator = "$($InitiatorPrefix):$initiatorName"
	$chapEnabled = ((Get-SGCachediSCSIVolume -VolumeARNs $volumeARN).VolumeiSCSIAttributes).ChapEnabled
	Write-Host "chap enabled = $chapEnabled"
	If ($chapEnabled -eq $false) {
		Update-SGChapCredentials -TargetARN $targetARN -InitiatorName $initiator -SecretToAuthenticateInitiator $secretUsedToAuthenticateInitiator -SecretToAuthenticateTarget $secretUsedToAuthenticateTarget
	}
	Add-TagsToVolumes $volumeARN $sgStackName $initiatorName
	Update-SnapshotScheduleForVolumes $volumeARN $recurrentInHours $initiatorName
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

function Add-TagsToVolumes($volumeARN,$SgStackName,$initiatorName) {
		Add-SGResourceTag -ResourceARN $volumeARN -Tag @( @{ Key="Name";Value = "$sgStackName" },@{ Key = "VolumeName"; Value = $initiatorName},@{ Key = "Expense Id"; Value = "AWS-GCM-SEO-Direct"},@{ Key = "Business Entity"; Value = "SHD"},@{ Key = "Owner"; Value = "SEO"},@{ Key = "App Team"; Value = "INF"} )
}
function Update-SnapshotScheduleForVolumes($volumeARN, $recurrentInHours,$initiatorName) {
		Update-SGSnapshotSchedule -VolumeARN $volumeARN -StartAt "00" -RecurrenceInHours $recurrentInHours -Description "SGW Snapshot for Target Volume $initiatorName"
}

If(-Not $TestMode) {
	$volumeIds = Get-SGWSnapshots
	Invoke-FindVolumesandSnapshots $volumeIds
}