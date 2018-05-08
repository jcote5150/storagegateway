param(
[string]$SgStackName = "appdev-primarysgw-dev",
[string]$SgGatewayName = "Storage-Gateway-For-DEV",
[string]$RegionToDeploy = "us-east-1",
[switch]$TestMode = $False
)

$ConfirmPreference = "None"

$ErrorActionPreference = "Stop"

if (Get-Module -ListAvailable -Name AWSPowershell) {
    Write-Host "Module exists"
} else {
	Write-Host "Installing Module"
	Install-PackageProvider nuget -force
	Install-Module AWSPowershell -Confirm:$false -Force
}
Import-Module AWSPowershell -Force

Set-DefaultAWSRegion us-east-1

function Get-PrivateIPofEC2InstanceInStack($sgStackName) {
	Write-Host "Get-PrivateIPofEC2InstanceInStack($sgStackName)"
	$asInstanceForSGW = (Get-EC2Instance -Filter @( @{name='tag:aws:cloudformation:stack-name'; values="$sgStackName"}))
	$sgInstanceIP = ($asInstanceForSGW | Select -ExpandProperty RunningInstance).PrivateIPAddress
}
function Enable-StorageGateway($sgStackName,$sgGatewayName) {
	Write-Host "Enable-StorageGateway($sgStackName,$sgGatewayName)"
	$sgGetInstanceIP = Get-PrivateIPofEC2InstanceInStack $sgStackName
	$sgwstack = (get-cfnstack | where {$_.StackName -eq "$sgStackName"}).StackName
	$instanceID = (Get-CFNStack -StackName $sgwstack | Get-CFNStackResources | ? resourcetype -eq "AWS::EC2::Instance").PhysicalResourceId

		Do {
			$instanceState = (Get-EC2InstanceStatus -InstanceId $instanceID).InstanceState.Name
			} while($instanceState -ne 'running')

		Do {
			$instanceStatus = (Get-EC2InstanceStatus -InstanceId $instanceID).Status.Status
		} while($instanceStatus -ne 'ok')

		Do {
			$instanceSystemStatus = (Get-EC2InstanceStatus -InstanceId $instanceID).SystemStatus.Status
		} while($instanceSystemStatus -ne 'ok')
	}
function Get-StorageGatewayActivationCode($sgStackName) {
	$activationIP = (Get-EC2Instance -Filter @( @{name='tag:aws:cloudformation:stack-name'; values="$sgStackName"})| Select -ExpandProperty RunningInstance).PrivateIPAddress
	Write-Host "The IP for this activation is going to be $activationIP"
	$requestValue1 = "http://"
	$sgwActivationIP = "$($requestValue1)$activationIP"
	$sgwActivationIP = $sgwActivationIP.Replace(' ','')
	$sgGetHeaders = (Invoke-WebRequest -uri $sgwActivationIP -UseBasicParsing -MaximumRedirection 0 -ErrorAction ignore).Headers
	($sgGetHeaders).Location.Split("=/&")[5]
}
function New-StorageGatewayActivation($sgGetActivationKey,$sgGatewayName) {
	Write-Host "New-StorageGatewayActivation($sgGetActivationKey,$sgGatewayName)"
	Enable-SGGateway -ActivationKey $sgGetActivationKey -GatewayName $sgGatewayName -GatewayType cached -GatewayRegion $regionToDeploy -GatewayTimezone GMT-6:00
}
function Get-StorageGatewayARN($sgGatewayName) {
	(Get-SGGateway | where GatewayName -eq "$sgGatewayName").GatewayARN
}
function Get-StorageGatewayBufferDisk($gatewayARN) {
	Do {
		Start-Sleep -Seconds 10
		$bufferDiskState = $null
		Try {
			$bufferDiskState = ((Get-SGLocalDisk -GatewayARN $GatewayARN).Disks | ? DiskPath -EQ /dev/xvdc).DiskStatus
		}catch {}
	} while($bufferDiskState -ne 'present')

	$getLocalBufferDisk = ((Get-SGLocalDisk -GatewayARN $gatewayARN).Disks | ? DiskPath -EQ /dev/xvdd).DiskId
	$getLocalBufferDisk
}
Function Get-StorageGatewayCachedisk($gatewayARN) {
	Do {
		$cacheDiskState = ((Get-SGLocalDisk -GatewayARN $gatewayARN).Disks | ? DiskPath -EQ /dev/xvdd).DiskStatus
		} while($cacheDiskState -ne 'present')

	$getLocalCacheDisk = ((Get-SGLocalDisk -GatewayARN $gatewayARN).Disks | ? DiskPath -EQ /dev/xvdc).DiskId
	$getLocalCacheDisk
}
Function Add-StorageGatewayBufferVolumes($buffer,$gatewayARN) {
	Add-SGUploadBuffer -GatewayARN $gatewayARN -DiskId $buffer -Force
}
Function Add-StorageGatewayCacheVolumes($cache,$gatewayARN) {
	Add-SGCache -GatewayARN $gatewayARN -DiskId $cache -Force
}
function Build-StorageGateway($sgStackName,$sgGatewayName) {
	Enable-StorageGateway -SgStackName $sgStackName -SgGatewayName $sgGatewayName
	New-StorageGatewayActivation (Get-StorageGatewayActivationCode $sgStackName) $sgGatewayName
	$gatewayARN = Get-StorageGatewayARN $sgGatewayName
	$buffer = Get-StorageGatewayBufferDisk $gatewayARN
	$cache = Get-StorageGatewayCacheDisk $gatewayARN
	Add-StorageGatewayBufferVolumes $buffer $gatewayARN
	Add-StorageGatewayCacheVolumes $cache $gatewayARN
	Add-SGResourceTag -ResourceARN $gatewayARN -Tag @( @{ Key="Name"; Value = "$sgStackName" },@{ Key = "Expense Id"; Value = "AWS-GCM-SEO-Direct"},@{ Key = "Business Entity"; Value = "SHD"},@{ Key = "Owner"; Value = "SEO"},@{ Key = "App Team"; Value = "INF"} )
}
If(-Not $TestMode) {
	Build-StorageGateway $sgStackName $sgGatewayName
}