function Import-SlipStreamedUpdates {
    [CmdletBinding()]
    param (
        [string]$WIMPath,
        [switch]$keepDownloadedUpdates
    )
    
    begin {
        if(Test-Path $WimPath){
            Throw "Unable to find Install.Wim at $wimFile"
        }
        
        $OSDefinitionList = @(
            @{
            OperatingSystem = 'Windows Server 2019 Datacenter'
            Build = '1809'
            Index = 4
            IncludeDotNet = $False
            },
            @{
                OperatingSystem = 'Windows Server 2016 Datacenter'
                Build = '1607'
                Index = 4
                IncludeDotNet = $False
            },
            @{
                OperatingSystem = 'Windows 10 Professional'
                Build = '1903'
                Index = 6
                IncludeDotNet = $True
            }
        )
        
        $BaseFolder = "D:\slipstream\$($OS.OperatingSystem)"
        $UpdatesPath = "$($BaseFolder)\updates\*"
        $MountPath = "$($BaseFolder)\mount"
        $WimFile = "$($BaseFolder)\original\sources\install.wim"
        $servicingPath = "$($BaseFolder)\servicing\*"
        $dotNetPath = "$($BaseFolder)\dotNet\*"
        $OSArchitecture = "x64"
        
        # -- OS Specific
        $OSName = $OS.OperatingSystem
        $OSVersion = $OS.Build
        $IndexNum = $slipstream.index
        # -- End OS Specific
        
        Write-Host "Running updates on $($slipstream.OperatingSystem)" -BackgroundColor Red -ForegroundColor Black
                
    }
    
    process {
        # Get Latest CU
        $updateCUObject = Get-LatestCumulativeUpdate -version $OSVersion| Where-Object {$_.architecture -eq $OSArchitecture} | Select-Object -Unique
        # Check if it's already in the folder, download if not.
        if ( Test-Path | Join-Path .\ ($updateCUObject.url | Split-Path -leaf) ){
            Write-Verbose "Update CU already downloaded, using existing."    
            $updateCUObject.path = Join-Path .\ ($updateCUObject.url | Split-Path -leaf)
        }else{
            Write-Verbose "Downloading CU"
            $updateCU = $updateCUObject | Save-LatestUpdate
        }
        # Get Latest Servicing Stack
        $updateServicingStackObject = Get-LatestServicingStackUpdate -version  $OSVersion | Where-Object {$_.architecture -eq $OSArchitecture} | Select-Object -Unique
        # Check if it's already in the folder, download if not.
        if ( Test-Path | Join-Path .\ ($updateServicingStackObject.url | Split-Path -Leaf) ){
            Write-Verbose "Update Servicing Stack already downloaded, using existing."    
            $updateServicingStack = Join-Path .\ ($updateServicingStackObject.url | Split-Path -Leaf)
        }else{
            Write-Verbose "Downloading Servicing Stack"
            $updateServicingStack =  $updateServicingStackObject |  Save-LatestUpdate
        }
        
        
        
        
        
    }
    
    end {
        # RemoveDownloadedUpdates unless Keep is triggered.
        if (!($keepDownloadedUpdates)){
            Write-Verbose "KeepDownloadedUpdates not called, removing updates"
            Remove-Item $updateCU.path
            Remove-Item $updateServicingStack.path
        }else{
            # Not removing downloaded updates.
            Write-Verbose "KeepDownloadedUpdates called, keeping updates, no removal"
        }
    }
}
