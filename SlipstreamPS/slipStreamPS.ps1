function Import-SlipStreamedUpdates {
    [CmdletBinding()]
    param (
        # Path to Install.WIM, or at least root of the ISO that contains it
        [Parameter(Mandatory=$true)]
        [string]$pathWIM,
        # OSVersion
        [Parameter(Mandatory=$true)]
        [ValidateSet('Windows Server 2019 Datacenter','Windows Server 2016 Datacenter','Windows 10 Professional')]
        [string]$OSVersion,
        # Defaults to deleting downloaded updates. Calling this switch will override that
        [Parameter(Mandatory=$false)]
        [switch]$keepDownloadedUpdates,
        # Defaults to NOT including DotNet. Calling this switch will override that.
        [Parameter(Mandatory=$false)]
        [switch]$IncludeDotNet,
        # Working path for dealing with required downloads and mounts, defaults to the temp folder env variable
        [Parameter(Mandatory=$false)]
        [String]
        $pathWorking = $env:TEMP

    )
    
    begin {
        # Install.WIM handling
        if ((Test-Path $pathWIM) -AND (($pathWIM | Split-Path -Leaf) -eq ".\install.wim")){
            # The path was exactly to the install.wim, no change
            Write-Verbose "Install.wim found at exact $pathWIM"
        }elseif ((Test-Path $pathWIM)) {
            # Path exists, lets assume the path points to an unpacked ISO and search for the install.wim within
            Write-Verbose "Install.wim was not exactly at $$(pathWIM) . Searching..."
            $tryToFind = Get-ChildItem $pathWIM -Recurse Install.wim
            $foundCopies = ($tryToFind | Measure-Object).count
            if ($foundCopies -eq 1){
                # FOUND!
                Write-Verbose "Found a single Install.wim at $($tryToFind.Fullname)"
                $pathWIM = $tryToFind.FullName
            }else{
                # Found none or too many, either way we're not proceeding
                Write-Verbose "Found $foundCopies of install.wim, throwing error as a result."
                Throw "Unable to find Install.Wim in or at $pathWIM"
            }
        }
        
        # Additions or Removals to this list need to also be made to the OSVersion parameter validate set.
        $OSDefinitionList = @(
            @{
                OperatingSystem = 'Windows Server 2019 Datacenter'
                Build = '1809'
                Index = 4
            },
            @{
                OperatingSystem = 'Windows Server 2016 Datacenter'
                Build = '1607'
                Index = 4
            },
            @{
                OperatingSystem = 'Windows 10 Professional'
                Build = '1903'
                Index = 6
            }
        )
        $thisOS = $OSDefinitionList | Where-Object {$_.OperatingSystem -eq $OSVersion}
        Write-Verbose "OS $($thisOS.OperatingSystem) Build $($thisOS.build) selected with Index $($thisOS.index)"

        # Create a mount path for this specific run
        $pathMount = Join-Path $pathWorking ("Mount" + (Get-Date -f hhmmss))

        $OSArchitecture = "x64"
    }
    
    process {
        # HANDLE DOWNLOADS ########################################################################################################################################################
        # Get Latest CU List
        $updateCUlist = Get-LatestCumulativeUpdate -version $thisos.build| Where-Object {$_.architecture -eq $OSArchitecture} | Select-Object -Unique
        # Check if it's already in the folder, download if not.
        if ( Test-Path ( Join-Path $pathWorking ($updateCUlist.url | Split-Path -leaf) )){
            Write-Verbose "Update CU already downloaded, using existing."
            $updateCU = Join-Path $pathWorking ($updateCUlist.url | Split-Path -leaf) | Select-Object @{Name="Path"; expression={$_}}
        }else{
            Write-Verbose "Downloading CU"
            $updateCU = $updateCUlist | Save-LatestUpdate -Path $pathWorking
        }
        # Get Latest Servicing Stack List
        $updateServicingStackList = Get-LatestServicingStackUpdate -version  $thisOS.build | Where-Object {$_.architecture -eq $OSArchitecture} | Select-Object -Unique
        # Check if it's already in the folder, download if not.
        if ( Test-Path ( Join-Path $pathWorking ($updateServicingStackList.url | Split-Path -Leaf) )){
            Write-Verbose "Update Servicing Stack already downloaded, using existing."    
            $updateServicingStack = Join-Path $pathWorking ($updateServicingStackList.url | Split-Path -Leaf) | Select-Object @{Name="Path"; expression={$_}}
        }else{
            Write-Verbose "Downloading Servicing Stack"
            $updateServicingStack =  $updateServicingStackList |  Save-LatestUpdate -Path $pathWorking
        }
        
        
        if ($IncludeDotNet) {
            # Latest .Net Update
            $updateDotNetList = Get-LatestNetFrameworkUpdate | Where-Object {$_.Architecture -eq $OSArchitecture} | Where-Object {$_.Version -eq $OSVersion}
            $updateDotNet = $updateDotNetList | Save-LatestUpdate -Path $pathWorking
        }

        # DOWNLOADS HANDLED ########################################################################################################################################################
        # Begin Install.WIM Handling #######################################################################################################################################################
        Write-Verbose "Debug"
        # Create Mount Path if it doesn't exist
        if ((Test-Path $pathMount) -eq $false){
            Write-Verbose "Creating mount folder at $pathMount "
            New-Item $pathMount -ItemType Directory
        }else{
            Write-Verbose "Mount Folder already exists at $pathMount"
        }

        Set-ItemProperty $pathWIM -Name IsReadOnly -Value $false # Set Read/Write 
        # Mount the Install.WIM
        try {
            Write-Verbose "Mounting WIMFile $($pathWIM) at $($pathMount)"
            Mount-WindowsImage -ImagePath $pathWIM -Index $thisOS.index -Path $pathMount
            # DISM /Mount-Wim /WimFile:$pathWIM /index:$thisOS.index /Mountdir:$pathMount    
        }
        catch {
            Throw "Unable to Mount the Install.wim"
        }

        # Servicing Stack import into Install.WIM
        foreach ($singleUpdate in $updateServicingStack.path){
            Write-Verbose "Importing Servicing Stack Update into Install.WIM" 
            Add-WindowsPackage -Path $pathMount -PackagePath $singleUpdate
            # DISM /image:$pathMount /Add-Package /Packagepath:$singleUpdate
            Start-Sleep -s 10
        }
        # CU import into Install.WIM
        foreach($singleUpdate in $updateCU.path){
            Write-Verbose "Importing CU Update into Install.WIM"
            Add-WindowsPackage -Path $pathMount -PackagePath $singleUpdate
            # DISM /image:$pathMount /Add-Package /Packagepath:$singleUpdate
            Start-Sleep -s 10
        }
        
        if ($IncludeDotNet) {
            # DotNet import into Install.WIM
            Write-Verbose "Importing dotNet updates into Install.WIM"
            ForEach ($dotNet in $updateDotNet) {
                Add-WindowsPackage -Path $pathMount -PackagePath $dotNet.path
                # DISM /image:$MountPath /Add-Package /Packagepath:$dotNet.path
                Start-Sleep -s 10
            }
        }
        
        # Commit Changes to WIM
        Dismount-WindowsImage -Path $pathMount -save
        # DISM /Unmount-image /Mountdir:$pathMount /commit
        Clear-WindowsCorruptMountPoint
        # DISM /Cleanup-Wim

    }
    
    end {
        # RemoveDownloadedUpdates unless Keep is triggered.
        if (!($keepDownloadedUpdates)){
            Write-Verbose "KeepDownloadedUpdates not called, removing updates"
            Remove-Item $updateCU.path
            Remove-Item $updateServicingStack.path
            if ($IncludeDotNet){
                Write-Verbose "Removing DotNet Updates"
                foreach ($one in $updateDotNet){
                    Remove-Item $one
                }
            }
        }else{
            # Not removing downloaded updates.
            Write-Verbose "KeepDownloadedUpdates called, keeping updates, no removal"
        }
    }
}