Set-StrictMode -Version Latest
. $PSScriptRoot\..\storagegatewaypsautomation\addvolumes.ps1 -TestMode

Describe "Add Volumes Tests" {
	Mock Add-SGResourceTag {}
	Context "when function Add-VolumeToStorageGateway is invoked and chap enabled is true" {
		Mock New-SGCachediSCSIVolume {[PSCustomObject]@{VolumeARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F/volume/vol-007F0891AE8DDE280";TargetARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F/target/iqn.1997-05.com.amazon:jcote-9020.gcmlp.com"}}
		Mock Get-SGCachediSCSIVolume {[PSCustomObject]@{VolumeiSCSIAttributes = [PSCustomObject]@{ChapEnabled = $true}}}
		Mock Update-SGChapCredentials {}
		Mock Update-SGSnapshotSchedule {}
		$a = [pscustomobject]@{volumesizeinbytes = 107374182400;targetname = "aw-jcote-01.gcmlp.com";clienttoken = "019273982q3745kjsaf";snapshot = "yes";recurrence = "24";snapshotdescription = "test"}
		$gatewayarn = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F"
		Add-VolumeToStorageGateway -SgStackName appdev-primarysgw-dev -gatewayARN $gatewayarn -volumeRequirements $a -SgInstanceIP 10.100.24.68 -secretUsedToAuthenticateTarget Test123456789 -secretUsedToAuthenticateInitiator Test019283746754564

		It "will not invoke Update-SGChapCredentials" {
			Assert-MockCalled Update-SGChapCredentials -Times 0
		}
	}
	Context "when function Add-VolumeToStorageGateway is invoked and chap enabled is false" {
		Mock New-SGCachediSCSIVolume {[PSCustomObject]@{VolumeARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-019B7E68/volume/vol-0489E0B1A7A0256EB";TargetARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F/target/iqn.1997-05.com.amazon:jcote-9020.gcmlp.com"}}
		Mock Get-SGCachediSCSIVolume {[PSCustomObject]@{VolumeiSCSIAttributes = [PSCustomObject]@{ChapEnabled = $false}}}
		Mock Update-SGChapCredentials {}
		Mock Update-SGSnapshotSchedule {}
		$a = [pscustomobject]@{volumesizeinbytes = 107374182400;targetname = "aw-jcote-01.gcmlp.com";clienttoken = "019273982q3745kjsaf";snapshot = "yes";recurrence = "24";snapshotdescription = "test"}
		$gatewayarn = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F"
		Add-VolumeToStorageGateway -SgStackName appdev-primarysgw-dev -gatewayARN $gatewayarn -volumeRequirements $a -SgInstanceIP 10.100.24.68 -secretUsedToAuthenticateTarget Test123456789 -secretUsedToAuthenticateInitiator Test019283746754564

		It "will invoke Update-SGChapCredentials" {
			Assert-MockCalled Update-SGChapCredentials -Times 1
		}
	}
	Context "when function Invoke-AddGatewayVolumes is invoked" {
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateTarget*"}
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateInitiator*"}
		Mock Get-SGGateway  {[PSCustomObject]@{GatewayARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F";GatewayName = "test-gateway"}}
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = "10.100.24.68"}}}
		Mock Get-Content {'
			[
    {
        "volumesizeinbytes":  107374182400,
        "targetname":  "aw-jcote-01.gcmlp.com",
        "clienttoken":  "12345678910"
    },
    {
        "volumesizeinbytes":  107374182400,
        "targetname":  "aw-gofast-01.gcmlp.com",
        "clienttoken":  "019273982q3745kjsaf"
    },
    {
        "volumesizeinbytes":  107374182400,
        "targetname":  "jcote-9020.gcmlp.com",
        "clienttoken":  "jcote9020asdff"
    }
]'}
		Mock Add-VolumeToStorageGateway {}
		Invoke-AddGatewayVolumes -SgStackName appdev-primarysgw-dev -sgGatewayName test-gateway -RegionToDeploy us-east-1
		It "should invoke Add-VolumeToStorageGateway for each entry in the json file" {
			Assert-MockCalled Add-VolumeToStorageGateway -Times 3
		}
	}
	Context "when function Invoke-AddGatewayVolumes is invoked and no EC2 IP Address is returned" {
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateTarget*"}
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateInitiator*"}
		Mock Get-SGGateway  {[PSCustomObject]@{GatewayARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F";GatewayName = "test-gateway"}}
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = ""}}}
		It "should invoke Add-VolumeToStorageGateway and fail if IP address not returned" {
			{Invoke-AddGatewayVolumes -SgStackName appdev-primarysgw-dev -sgGatewayName test-gateway -RegionToDeploy us-east-1} | Should Throw "Instance not returned"
		}
	}
	Context "when function Invoke-AddGatewayVolumes is invoked and a user does not have access to Password Manager" {
		Mock Invoke-WebRequest {throw "is not a member of"}
		It "should throw an error if a user does not have access to the PM resource" {
			{Invoke-AddGatewayVolumes -SgStackName appdev-primarysgw-dev -sgGatewayName test-gateway -RegionToDeploy us-east-1} | Should Throw "is not a member of"
		}
	}
	Context "when function Invoke-AddGatewayVolumes is invoked and Gateway ARN is queried" {
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateTarget*"}
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateInitiator*"}
		Mock Get-SGGateway  {}
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = "10.100.24.68"}}}
		It "should return a value for Gateway ARN or fail" {
			{Invoke-AddGatewayVolumes -SgStackName appdev-primarysgw-dev -sgGatewayName test-gateway -RegionToDeploy us-east-1} | Should Throw "ARN should not be blank"
		}
	}
	Context "when function Invoke-AddGatewayVolumes is invoked and json file is invalid" {
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateTarget*"}
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateInitiator*"}
		Mock Get-SGGateway  {[PSCustomObject]@{GatewayARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F";GatewayName = "test-gateway"}}
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = "10.100.24.68"}}}
		Mock Get-Content {"test"}
		It "should fail" {
			{Invoke-AddGatewayVolumes -SgStackName appdev-primarysgw-dev -sgGatewayName test-gateway -RegionToDeploy us-east-1} | Should Throw "Invalid JSON primitive"
		}
	}
	Context "when function Invoke-AddGatewayVolumes is invoked and json file is empty" {
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateTarget*"}
		Mock Invoke-WebRequest  {[PSCustomObject]@{Content = "Test019283746754564"}} -ParameterFilter {$uri -like "*SecretUsedToAuthenticateInitiator*"}
		Mock Get-SGGateway  {[PSCustomObject]@{GatewayARN = "arn:aws:storagegateway:us-east-1:827391051751:gateway/sgw-16E5007F";GatewayName = "test-gateway"}}
		Mock Get-SGGatewayInformation {[PSCustomObject]@{GatewayNetworkInterfaces = [PSCustomObject]@{IPv4Address = "10.100.24.68"}}}
		Mock Get-Content {""}
		Mock Add-VolumeToStorageGateway {}
		It "should not call add-volumetostoragegateay function" {
			Invoke-AddGatewayVolumes -SgStackName appdev-primarysgw-dev -sgGatewayName test-gateway -RegionToDeploy us-east-1
				Assert-MockCalled Add-VolumeToStorageGateway -Times 0
		}
	}
}