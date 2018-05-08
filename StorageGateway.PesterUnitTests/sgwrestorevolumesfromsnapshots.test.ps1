Set-StrictMode -Version Latest
. $PSScriptRoot\..\storagegatewaypsautomation\recoverVolumesfromSnapshot.ps1 -TestMode

Describe "Get Storage-Gateway Snapshot Tests" {
	 Mock Add-RecoveredVolumesToSGW {}
  Context "when function Invoke-FindVolumesandSnapshots is invoked and there are 2 volumes" {
	  Mock Get-EC2Snapshot {@([PSCustomObject]@{StartTime = "00"})}
	  Invoke-FindVolumesandSnapshots @("item1","item2")

	  It "will retrieve snapshots and process each volume" {
		  Assert-MockCalled Add-RecoveredVolumesToSGW -Times 2
		  Assert-MockCalled Get-EC2Snapshot  -Times 2
		}
  }
	Context "when function Invoke-FindVolumesandSnapshots is invoked and there are at least 2 snapshots" {
		Mock Get-EC2Snapshot {@([PSCustomObject]@{StartTime = "01/12/2017 3:02:38 PM"},[PSCustomObject]@{StartTime = "01/12/2017 5:02:40 PM"})}
		Invoke-FindVolumesandSnapshots @("item1")

	  It "will determine recurrence based on time differential between snapshots" {
		  Assert-MockCalled Add-RecoveredVolumesToSGW -Times 1 -ParameterFilter {$recurrentInHours -eq "2"}
		}
	}
	Context "when function Invoke-FindVolumesandSnapshots is invoked and there is only 1 snapshot" {
		Mock Get-EC2Snapshot {@([PSCustomObject]@{StartTime = "01/12/2017 3:02:38 PM"})}
		Invoke-FindVolumesandSnapshots @("item1")

	  It "will determine recurrence to be once per day" {
		  Assert-MockCalled Add-RecoveredVolumesToSGW -Times 1 -ParameterFilter {$recurrentInHours -eq "24"}
		}
	}
}
Describe "When function Add-RecoveredVolumesToSGW is invoked" {
		Mock Add-TagsToVolumes {}
		Mock Update-SnapshotScheduleForVolumes{}
		Mock Update-SGChapCredentials {}
		Mock New-SGCachediSCSIVolume {[PSCustomObject]@{VolumeARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F/volume/vol-007F0891AE8DDE280";TargetARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F/target/iqn.1997-05.com.amazon:jcote-9020.gcmlp.com"}}
		Mock Get-SGGateway  {[PSCustomObject]@{GatewayARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F";GatewayName = "test-gateway"}}
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = "10.100.24.68"}}}
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateTarget*"}
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateInitiator*"}

	Context "when function Add-RecoveredVolumesToSGW is invoked and no EC2 IP Address is returned" {
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = ""}}}

		It "should invoke Add-RecoveredVolumesToSGW and fail if IP address not returned" {
			{Add-RecoveredVolumesToSGW  | Should Throw "Instance not returned"}
			}
	}
	Context "when function Add-RecoveredVolumesToSGW is invoked and a user does not have access to Password Manager" {
		Mock Invoke-WebRequest {throw "is not a member of"}
		It "should throw an error if a user does not have access to the PM resource" {
			{Add-RecoveredVolumesToSGW  | Should Throw "is not a member of"}
		}
	}
	Context "when function Add-RecoveredVolumesToSGW is invoked and Gateway ARN is queried" {
		Mock Get-SGGateway  {}
		It "should return a value for Gateway ARN or fail" {
			{Add-RecoveredVolumesToSGW  | Should Throw "ARN should not be blank"}
		}
	}
	Context "when function Add-RecoveredVolumesToSGW is invoked and chap enabled is true" {
		Mock Get-SGCachediSCSIVolume {[PSCustomObject]@{VolumeiSCSIAttributes = [PSCustomObject]@{ChapEnabled = $true}}}
		Mock Get-SGGateway  {[PSCustomObject]@{GatewayARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F";GatewayName = "test-gateway"}}
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = "10.100.24.68"}}}
		$volume = [PSCustomObject]@{volumesize = "107374182400"}
		$snapshot = [PSCustomObject]@{snapshotId = "snap-0192834234234";Description = "SGW Snapshot for Target Volume aw-gofast-01.gcmlp.com";VolumeSize = 100}
		$gatewayarn = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F"
		$sgInstanceIP = "10.100.24.68"
		Add-RecoveredVolumesToSGW -gatewayARN  $gatewayarn -snapshot $snapshot -recurrentInHours "00"

		It "will not invoke Update-SGChapCredentials" {
			Assert-MockCalled Update-SGChapCredentials -Times 0
		}
	}
	Context "when function Add-RecoveredVolumesToSGW is invoked and chap enabled is false" {
		Mock Get-SGCachediSCSIVolume {[PSCustomObject]@{VolumeiSCSIAttributes = [PSCustomObject]@{ChapEnabled = $false}}}
		Mock Get-SGGateway  {[PSCustomObject]@{GatewayARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F";GatewayName = "test-gateway"}}
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = "10.100.24.68"}}}
		$volume = [PSCustomObject]@{volumesize = "107374182400"}
		$snapshot = [PSCustomObject]@{snapshotId = "snap-0192834234234";Description = "SGW Snapshot for Target Volume aw-gofast-01.gcmlp.com";VolumeSize = 100}
		$gatewayarn = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F"
		$sgInstanceIP = "10.100.24.68"
		Add-RecoveredVolumesToSGW -gatewayARN  $gatewayarn -snapshot $snapshot -recurrentInHours "00"

		It "will invoke Update-SGChapCredentials" {
			Assert-MockCalled Update-SGChapCredentials -Times 1
		}
	}
}