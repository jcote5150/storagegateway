Set-StrictMode -Version Latest
. $PSScriptRoot\..\storagegatewaypsautomation\addvolumestoservers.ps1 -TestMode

Describe "Add Volumes to Local Servers" {
	Context "when function Get-ChapAuthenticationForTarget is invoked" {
		Mock Invoke-WebRequest {throw "is not a member of"}

		It "should throw an error if a user does not have access to the PM resource" {
			{Set-IscsiTargetSecurity {} | Should Throw "is not a member of"
		}
	  }
	}
	Context "when function Get-ChapAuthenticationForInitiator is invoked" {
		Mock Invoke-WebRequest {throw "is not a member of"}

		It "should throw an error if a user does not have access to the PM resource" {
			{Set-IscsiTargetSecurity {} | Should Throw "is not a member of"
		}
	  }
	}
	Context "when function Get-GatewayARN is invoked and Gateway ARN is queried" {
		It "should return a value for Gateway ARN or fail" {
			 {Get-SGGateway {} | Should Throw "ARN should not be blank"
			}
		}
	}
	Context "when function Get-SGWInstanceIP is invoked and no EC2 IP Address is returned" {
	It "should fail if no IP address is returned" {
		{Get-SGGatewayInformation {} | Should Throw "Instance not returned" }
		}
	}
	Context "when function Create-IscsiTargetPortal is invoked and no Target address is returned" {
	It "should fail if no target address is specified" {
		{New-IscsiTargetPortal {}
		}
		}
	}
}