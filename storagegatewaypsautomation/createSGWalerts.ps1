param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[string]$RegionToDeploy = "us-east-1",
[string]$EmailForAlerts = "jcote@gcmlp.com",
[switch]$TestMode = $False
)

Set-DefaultAWSRegion $regionToDeploy

$topicARN = (Get-SNSTopic | ? {$_.TopicArn -like "*$SgStackName*"}).TopicArn
$sgwInfo = Get-SGGateway | ? {$_.GatewayName -eq $SgGatewayName}

if (Get-Module -ListAvailable -Name AWSPowershell) {
    Write-Host "Module exists"
} else {
	Write-Host "Installing Module"
	Install-PackageProvider nuget -force
	Install-Module AWSPowershell -Confirm:$false -Force
}
Import-Module AWSPowershell -Force

function Add-SNSTopic() {
  $snsTopicExists = Get-SNSTopic | ? {$_.TopicArn -like "*$SgStackName*"}
  if (-not $snsTopicExists) {
    $snsAttribute = New-SNSTopic -Name "$SgStackName-Alerts"
    Set-SNSTopicAttribute -AttributeName DisplayName -AttributeValue "SGWAlerts" -TopicArn $snsAttribute
    Connect-SNSNotification -TopicArn $snsAttribute -Endpoint $EmailForAlerts -Protocol email
    Write-Host "Topic Created"
    } Else {Write-Host "TopicARN already exists"}
}

function New-SGWAlertCloudBytesUploaded() {
  Write-CWMetricAlarm -AlarmName $SgGatewayName-Cloud-Bytes-Uploaded `
 -AlarmDescription "StorageGateway CloudBytesUploaded Alarm" `
 -Namespace "AWS/StorageGateway" `
 -MetricName CloudBytesUploaded `
 -Dimension @{ Name="GatewayName"; Value="$SgGatewayName" }, @{ Name="GatewayId"; Value=$sgwInfo.GatewayId } `
 -AlarmAction $topicARN `
 -ComparisonOperator GreaterThanOrEqualToThreshold `
 -EvaluationPeriod 12 `
 -Period 300 `
 -Statistic Sum `
 -Threshold 500000000
}

function New-SGWAlertCloudBytesDownloaded() {
  Write-CWMetricAlarm -AlarmName $SgGatewayName-Cloud-Bytes-Downloaded `
 -AlarmDescription "StorageGateway CloudBytesDownloaded Alarm" `
 -Namespace "AWS/StorageGateway" `
 -MetricName CloudBytesUploaded `
 -Dimension @{ Name="GatewayName"; Value="$SgGatewayName" }, @{ Name="GatewayId"; Value=$sgwInfo.GatewayId } `
 -AlarmAction $topicARN `
 -ComparisonOperator GreaterThanOrEqualToThreshold `
 -EvaluationPeriod 24 `
 -Period 300 `
 -Statistic Sum `
 -Threshold 500000000
}

function New-SGWAlertUploadBufferPercentUsed() {
  Write-CWMetricAlarm -AlarmName $SgGatewayName-Upload-Buffer-Percent-Used `
 -AlarmDescription "StorageGateway Upload Buffer Percent Used Alarm" `
 -Namespace "AWS/StorageGateway" `
 -MetricName UploadBufferPercentUsed `
 -Dimension @{ Name="GatewayName"; Value="$SgGatewayName" }, @{ Name="GatewayId"; Value=$sgwInfo.GatewayId } `
 -AlarmAction $topicARN `
 -ComparisonOperator GreaterThanOrEqualToThreshold `
 -EvaluationPeriod 6 `
 -Period 300 `
 -Statistic Average `
 -Threshold 85
}

function Get-SGWVolumes($sgwInfo) {
  (Get-SGVolume -GatewayARN $sgwInfo.GatewayARN)
}

function Create-StorageGatewayAlerts() {
  Add-SNSTopic
  New-SGWAlertCloudBytesUploaded
  New-SGWAlertCloudBytesDownloaded
  New-SGWAlertUploadBufferPercentUsed
  $volumes = Get-SGWVolumes $sgwInfo
  $volumes | ForEach-Object {
	  Create-StorageGatewayVolumeAlerts $_
  }
}

function Get-VolumeName($volume) {
	Write-Host "Looking up volumeARN $volume.VolumeARN"
	((Get-SGResourceTags -ResourceARN:$volume.VolumeARN) | ? { $_.Key -ieq "VolumeName" }).Value
}

function Get-CWAlarmsForVolume($volumeName) {
	$configFilePrefix = $sgStackName.Split('-')[0]
	$volumes = Get-Content -Raw $configFilePrefix-volumestocreate.json | ConvertFrom-Json
	($volumes | ? { $_.targetname -ieq $volumeName}).cwalarms
}

function New-SGAlarm($volume, $alarmDefinition) {
	Write-CWMetricAlarm -AlarmName $SgGatewayName-$($volume.VolumeId)-$($alarmDefinition.AlarmNameSuffix) `
   -AlarmDescription $alarmDefinition.AlarmDescription `
   -Namespace "AWS/StorageGateway" `
   -MetricName $alarmDefinition.MetricName `
   -Dimension @{ Name="VolumeId"; Value="us-east-1-$($volume.VolumeId)" } `
   -AlarmAction $topicARN `
   -ComparisonOperator $alarmDefinition.ComparisonOperator `
   -EvaluationPeriod $alarmDefinition.EvaluationPeriod `
   -Period $alarmDefinition.Period `
   -Statistic $alarmDefinition.Statistic `
   -Threshold $alarmDefinition.Threshold
}

function Create-StorageGatewayVolumeAlerts($volume) {
	$volumeName = Get-VolumeName $volume
	Write-Host "Volume name is for volume is $volume is $volumeName"
	$alarms = Get-CWAlarmsForVolume $volumeName
	$alarms | ForEach-Object {
		New-SGAlarm $volume $_
	}
}

If(-Not $TestMode) {
	Create-StorageGatewayAlerts
}