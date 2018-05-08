param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[string]$RegionToDeploy = "us-east-1",
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

Set-DefaultAWSRegion $RegionToDeploy

function Get-GatewayARN() {
	$gateway = Get-SGGateway | ? {$_.GatewayName -eq $sgGatewayName }

		   If (-not $gateway) {
		throw "ARN should not be blank"
	}

	$gatewayARN = $gateway.GatewayARN
	return $gatewayARN
}

function Get-SGWVolumes() {
	$gatewayARN = Get-GatewayARN
	(Get-SGVolume -GatewayARN $gatewayARN).VolumeId
}

function Get-SGWSnapshots($volumeIds) {
	ForEach($volumeId in $volumeIds) {
		$snapshots = Get-EC2Snapshot -filter @( @{name="volume-id"; values=$volumeId})
		Tag-SGWSnapshots $snapshots
	}
}

function Tag-SGWSnapshots($snapshots) {
	ForEach($snapshot in $snapshots) {
		$volumeName = $snapshots.Description.Split(' ')[5]
		New-EC2Tag -Resource $snapshots.snapshotId -Tag @( @{ Key="Name";Value = $SgGatewayName },@{ Key = "Expense Id"; Value = "AWS-GCM-SEO-Direct"},@{ Key = "VolumeName"; Value = $volumeName},@{ Key = "Business Entity"; Value = "SHD"},@{ Key = "Owner"; Value = "SEO"},@{ Key = "App Team"; Value = "INF"} )
	}
}

If(-Not $TestMode) {
	Get-SGWVolumes $gatewayARN
	$volumeIds = Get-SGWVolumes $gatewayARN
	Get-SGWSnapshots $volumeIds
}