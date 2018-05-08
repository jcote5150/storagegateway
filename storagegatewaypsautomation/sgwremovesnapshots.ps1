param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[int]$daysBack = 7,
[bool]$viewOnly = $true,
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

function Get-GatewayARN() {
	$gateway = Get-SGGateway | where GatewayName -eq "$sgGatewayName"
		   If (-not $gateway) {
		throw "ARN should not be blank"
	}
	$gatewayARN = $gateway.GatewayARN
	return $gatewayARN
}

function Invoke-SnapshotCleanup($gatewayARN,$daysBack,$viewOnly) {
$volumesResult = Get-SGVolume -GatewayARN $gatewayARN
$volumes = $volumesResult.VolumeInfos
Write-Output("`nVolume List")
foreach ($volumes in $volumesResult)
  { Write-Output("`nVolume Info:")
    Write-Output("ARN:  " + $volumes.VolumeARN)
    write-Output("Type: " + $volumes.VolumeType)
  }

Write-Output("`nWhich snapshots meet the criteria?")
foreach ($volume in $volumesResult)
  {
    $volumeARN = $volume.VolumeARN

    $volumeId = ($volumeARN-split"/")[3].ToLower()

    $filter = New-Object Amazon.EC2.Model.Filter
    $filter.Name = "volume-id"
    $filter.Value.Add($volumeId)

    $snapshots = get-EC2Snapshot -Filter $filter
    Write-Output("`nFor volume-id = " + $volumeId)
    foreach ($s in $snapshots)
    {
       $d = ([DateTime]::Now).AddDays(-$daysBack)
       $meetsCriteria = $false
       if ([DateTime]::Compare($d, $s.StartTime) -gt 0)
       {
            $meetsCriteria = $true
       }

       $sb = $s.SnapshotId + ", " + $s.StartTime + ", meets criteria for delete? " + $meetsCriteria
       if ($viewOnly -AND $meetsCriteria)
       {
           $resp = Remove-EC2Snapshot -SnapshotId $s.SnapshotId -confirm:$false
           #Can get RequestId from response for troubleshooting.
           $sb = $sb + ", deleted? yes"
       }
       else {
           $sb = $sb + ", deleted? no"
       }
       Write-Host($sb)
    }
  }
}
If(-Not $TestMode) {
	$gatewayARN = Get-GatewayARN
	Invoke-SnapshotCleanup $gatewayARN $daysBack $viewOnly
}