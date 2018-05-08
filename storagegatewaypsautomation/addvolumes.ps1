param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[string]$RegionToDeploy = "us-east-1",
[string]$InitiatorPrefix = "iqn.1991-05.com.microsoft",
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

function Add-VolumeToStorageGateway($sgStackName,$gatewayARN,$volumeRequirements,$sgInstanceIP,$secretUsedToAuthenticateTarget,$secretUsedToAuthenticateInitiator) {
	Write-Host "Add-VolumeToStorageGateway with the following parameters $sgStackName $gatewayARN $sgInstanceIP"
	$clientToken = Get-ClientToken
	$volumeAttributes = New-SGCachediSCSIVolume -GatewayARN $gatewayARN -VolumeSizeInBytes $volumeRequirements.volumesizeinbytes -TargetName $volumeRequirements.targetName -NetworkInterfaceId $sgInstanceIP -ClientToken $clientToken
	$volumeARN = $volumeAttributes.VolumeARN
	$targetARN = $volumeAttributes.TargetARN
	$initiatorName =  $targetARN.Split("/")[3].Split(":")[1]
	$initiator = "$($InitiatorPrefix):$initiatorName"
	$chapEnabled = ((Get-SGCachediSCSIVolume -VolumeARNs $volumeARN).VolumeiSCSIAttributes).ChapEnabled
	If ($chapEnabled -eq $false) {
		Update-SGChapCredentials -TargetARN $targetARN -InitiatorName $initiator -SecretToAuthenticateInitiator $secretUsedToAuthenticateInitiator -SecretToAuthenticateTarget $secretUsedToAuthenticateTarget
	}
	Add-TagsToVolumes $volumeARN $sgStackName $volumeRequirements
	If ($volumeRequirements.snapshot -eq "yes") {
		Update-SnapshotScheduleForVolumes $volumeARN $volumeRequirements
		Write-Host "running Update-SnapshotScheduleForvolumes with the following attributes $volumeARN "$volumeRequirements.snapshot" "$volumeRequirements.recurrence""
	}
}

function Invoke-AddGatewayVolumes($sgStackName,$sgGatewayName,$regionToDeploy) {
	$secretUsedToAuthenticateTarget = (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateTarget").Content
	$secretUsedToAuthenticateInitiator = (Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -Uri "https://password.gcmlp.com:8443/v1/buildserviceuser-nonprd/StorageGateway-nonprd/SecretUsedToAuthenticateInitiator").Content
	$gateway = Get-SGGateway | where GatewayName -eq "$sgGatewayName"
	If (-not $gateway) {
		throw "ARN should not be blank"
	}
	$gatewayARN = $gateway.GatewayARN
	$sgInstanceIP = ((Get-SGGatewayInformation -GatewayARN $gatewayARN).GatewayNetworkInterfaces).IPv4Address
	If (-not $sgInstanceIP) {
		throw "Instance not returned"
	}
	$configFilePrefix = $sgStackName.Split('-')[0]
	Write-Host "Config Prefix for json file is $configFilePrefix"
	$volumes = Get-Content -Raw $configFilePrefix-volumestocreate.json | ConvertFrom-Json
	If ($volumes) {
		$volumes | ForEach-Object { Add-VolumeToStorageGateway $sgStackName $gatewayARN $_ $sgInstanceIP $secretUsedToAuthenticateTarget $secretUsedToAuthenticateInitiator }
	}
}

function Add-TagsToVolumes($volumeARN,$SgStackName,$volumeRequirements) {
		Add-SGResourceTag -ResourceARN $volumeARN -Tag @( @{ Key="Name";Value = "$sgStackName" },@{ Key = "Expense Id"; Value = "AWS-GCM-SEO-Direct"},@{ Key = "VolumeName"; Value = $volumeRequirements.targetName},@{ Key = "Business Entity"; Value = "SHD"},@{ Key = "Owner"; Value = "SEO"},@{ Key = "App Team"; Value = "INF"} )
}
function Update-SnapshotScheduleForVolumes($volumeARN,$volumeRequirements) {
		Update-SGSnapshotSchedule -VolumeARN $volumeARN -StartAt "00" -RecurrenceInHours $volumeRequirements.recurrence -Description $volumerequirements.snapshotdescription
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

If(-Not $TestMode) {
	Invoke-AddGatewayVolumes -sgStackName $sgStackName -sgGatewayName $sgGatewayName -regionToDeploy $regionToDeploy
}