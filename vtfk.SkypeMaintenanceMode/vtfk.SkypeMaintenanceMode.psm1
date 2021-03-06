Function Set-ServiceAutomaticDelay
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$ComputerName,

        [Parameter(Mandatory = $True)]
        [string]$ServiceName
    )

    $command = "sc.exe \\$ComputerName config $ServiceName start= delayed-auto"
    $output = Invoke-Expression -Command $command -ErrorAction Stop

    if($LASTEXITCODE -ne 0)
    {
        Write-Host "$output -- " -ForegroundColor Red -NoNewline
        return $False
    }
    else
    {
        return $True
    }
}

Function Set-ServiceMaintenanceMode
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$ComputerName,

        [Parameter(Mandatory = $True)]
        [bool]$Enable,

        [Parameter(Mandatory = $True)]
        [string]$DisplayName,

        [Parameter(Mandatory = $True)]
        [string]$Name
    )

    if ($Enable)
    {
        try
        {
            Write-Host "Stopping service '$DisplayName' : " -ForegroundColor Cyan -NoNewline
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock { Stop-Service -Name $Using:Name -Force -ErrorAction Stop; if ((Get-Service -Name $Using:Name -ErrorAction Stop).Status -eq "Stopped") { return $True } else { return $False } } -ErrorAction Stop
            if ($result)
            {
                Write-Host "OK" -ForegroundColor Green
            }
            else
            {
                Write-Host "Not stopped ($result). Aborting maintenance mode!" -ForegroundColor Yellow
                return $False;
            }
            Write-Host "Disabling service '$DisplayName' : " -ForegroundColor Cyan -NoNewline
            $resultDisable = Invoke-Command -ComputerName $ComputerName -ScriptBlock { Set-Service -Name $Using:Name -StartupType Disabled; if ((Get-Service -Name $Using:Name -ErrorAction Stop).StartType -eq "Disabled") { return $True } else { return $False } } -ErrorAction Stop
            if ($resultDisable)
            {
                Write-Host "OK" -ForegroundColor Green
                return $True
            }
            else
            {
                Write-Host "Not disabled ($resultDisable). Aborting maintenance mode!" -ForegroundColor Yellow
                return $False;
            }
        }
        catch
        {
            Write-Host "Failed: $_ -- Aborting maintenance mode!" -ForegroundColor Red
            return $False;
        }
    }
    else
    {
        try
        {
            Write-Host "Enabling service '$DisplayName' : " -ForegroundColor Cyan -NoNewline
            $resultEnable = Set-ServiceAutomaticDelay -ComputerName $ComputerName -ServiceName $Name
            if ($resultEnable)
            {
                Write-Host "OK" -ForegroundColor Green
            }
            else
            {
                Write-Host "Not enabled ($resultEnable). Aborting maintenance mode!" -ForegroundColor Yellow
                return $False;
            }
            Write-Host "Starting service '$DisplayName' : " -ForegroundColor Cyan -NoNewline
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock { Start-Service -Name $Using:Name -Confirm:$False -ErrorAction Stop; if ((Get-Service -Name $Using:Name -ErrorAction Stop).Status -eq "Running") { return $True } else { return $False } } -ErrorAction Stop
            if ($result)
            {
                Write-Host "OK" -ForegroundColor Green
                return $True;
            }
            else
            {
                Write-Host "Not started ($result). Aborting..." -ForegroundColor Yellow
                return $False;
            }
        }
        catch
        {
            Write-Host "Failed: $_ -- Aborting..." -ForegroundColor Red
            return $False;
        }
    }
}

Function Invoke-RebootMachine
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$ComputerName
    )

    $reboot = Read-Host "Would you like me to reboot the machine? (YES|NO)"
    if ($reboot.ToLower().Trim() -eq "yes")
    {
        Write-Host "'$ComputerName' will reboot! I will wait for it to come back online (timeout 8 minutes) (Time: $(Get-Date -Format 'HH:mm:ss'))" -ForegroundColor Yellow
        Restart-Computer -ComputerName $ComputerName -Force -Wait -For WinRM -Timeout 480 -Confirm:$False
        if ((Test-NetConnection -ComputerName $ComputerName -InformationLevel Quiet))
        {
            if ((Test-NetConnection -ComputerName $ComputerName -InformationLevel Quiet -CommonTCPPort WINRM))
            {
                Write-Host "'$ComputerName' successfully rebooted! (Time: $(Get-Date -Format 'HH:mm:ss'))" -ForegroundColor Green
            }
            else
            {
                Write-Host "'$ComputerName' is responding to ping but not to WinRM after reboot! (Time: $(Get-Date -Format 'HH:mm:ss'))" -ForegroundColor Yellow
            }
        }
        else
        {
            Write-Host "'$ComputerName' is not responding to ping or WinRM after reboot! (Time: $(Get-Date -Format 'HH:mm:ss'))" -ForegroundColor Red
        }
    }
    else
    {
        Write-Host "'$ComputerName' will NOT reboot!" -ForegroundColor Green
    }
}

Function Test-ServerActive
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [string]$Server,

        [Parameter()]
        [int]$MaxTries = 50
    )

    [bool]$PingResult = $False
    [bool]$WinRMResult = $False
    [int]$PingTries = 0
    [int]$WinRMTries = 0

    # check ping
    do
    {
        $PingTries++
        Write-Host "$PingTries / $MaxTries - Pinging '$Server' : " -ForegroundColor Cyan -NoNewline
        $Result = Test-NetConnection -ComputerName $Server
        if ($Result.PingSucceeded)
        {
            $PingResult = $True
            Write-Host "OK" -ForegroundColor Green
        }
        else
        {
            if ($PingTries -ge $MaxTries)
            {
                break;
            }

            Start-Sleep -Seconds 10
        }
    } while (!$PingResult)

    # check WinRM
    if ($PingResult)
    {
        do
        {
            $WinRMTries++
            Write-Host "$WinRMTries / $MaxTries - Connecting to '$Server' : " -ForegroundColor Cyan -NoNewline
            $Result = Test-NetConnection -ComputerName $Server -CommonTCPPort WINRM
            if ($Result.TcpTestSucceeded)
            {
                $WinRMResult = $True
                Write-Host "OK" -ForegroundColor Green
            }
            else
            {
                if ($WinRMTries -ge $MaxTries)
                {
                    break;
                }

                Start-Sleep -Seconds 10
            }
        } while (!$WinRMResult)
    }

    $Output = New-Object PSObject
    $Output | Add-Member -MemberType NoteProperty -Name Server -Value $Server
    $Output | Add-Member -MemberType NoteProperty -Name PingSucceeded -Value $PingResult
    $Output | Add-Member -MemberType NoteProperty -Name TcpTestSucceeded -Value $WinRMResult
    $Output | Add-Member -MemberType NoteProperty -Name PingTries -Value $PingTries
    $Output | Add-Member -MemberType NoteProperty -Name WinRMTries -Value $WinRMTries
    $Output | Add-Member -MemberType NoteProperty -Name TriesAllowed -Value $MaxTries

    return $Output
}

Function Get-CentralManagementPool
{
    return (Get-CsPool | Where { $_.Services -match "CentralManagement:" } | Select -ExpandProperty Fqdn)
}

Function Get-MediationServers
{
    return (Get-CsPool | Where { $_.Services -match "MediationServer:" } | Select -ExpandProperty Computers)
}

Function Get-FrontEndServers
{
    return (Get-CsPool | Where { $_.Services -match "ApplicationServer:" } | Select -ExpandProperty Computers)
}

Function New-SkypeComputerDynamicParam
{
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$Name,

        [Parameter(Mandatory = $True)]
        [string[]]$Computers,

        [Parameter()]
        [boolean]$Mandatory = $true,

        [Parameter()]
        [Int]$Position = 1,

        [Parameter()]
        [Switch]$ValueFromPipeline,

        [Parameter()]
        [Switch]$ValueFromPipelineByPropertyName
    )

    $DynamicParams = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $attribute = [System.Management.Automation.ParameterAttribute]::new()

    $attribute.ParameterSetName = '__AllParameterSets'
    $attribute.Mandatory = $Mandatory
    $attribute.Position = $Position
    $attribute.ValueFromPipeline = $ValueFromPipeline -or $ValueFromPipelineByPropertyName
    $attribute.ValueFromPipelineByPropertyName = $ValueFromPipelineByPropertyName

    $attributeCollection.Add($attribute)

    $validateSetAttribute = [System.Management.Automation.ValidateSetAttribute]::new($Computers)
    $attributeCollection.Add($validateSetAttribute)

    $dynamicParam = [System.Management.Automation.RuntimeDefinedParameter]::new($Name, [string], $attributeCollection)

    $DynamicParams.Add($Name, $dynamicParam)

    return $DynamicParams
}

Function Start-MediationMaintenance
{
    param(
        [Parameter()]
        [switch]$Reboot
    )

    DynamicParam
    {
        New-SkypeComputerDynamicParam -Name ComputerName -Computers (Get-MediationServers) -Mandatory $True
    }

    Process
    {
        # Include Skype for Business functionality
        if (!(Get-Command "Get-CsUser" -ErrorAction SilentlyContinue))
        {
            Write-Host "Importing Skype tools" -ForegroundColor Green
            Import-Module "$env:ProgramFiles\Common Files\Skype for Business Server 2015\Modules\SkypeForBusiness\SkypeForBusiness.psd1"
        }
        
        if (!(Set-ServiceMaintenanceMode -ComputerName $PSBoundParameters.ComputerName -Enable $True -DisplayName 'Skype for Business Server Centralized Logging Service Agent' -Name 'RTCCLSAGT'))
        {
            return;
        }
        if (!(Set-ServiceMaintenanceMode -ComputerName $PSBoundParameters.ComputerName -Enable $True -DisplayName 'Skype for Business Server Mediation' -Name 'RTCMEDSRV'))
        {
            return;
        }
        if (!(Set-ServiceMaintenanceMode -ComputerName $PSBoundParameters.ComputerName -Enable $True -DisplayName 'Skype for Business Server Replica Replicator Agent' -Name 'REPLICA'))
        {
            return;
        }

        Write-Host "`n$($PSBoundParameters.ComputerName) were put successfully into Mediation Maintenance Mode!`n" -ForegroundColor Green

        if ($Reboot)
        {
            Invoke-RebootMachine -ComputerName $PSBoundParameters.ComputerName
        }
    }
}

Function Stop-MediationMaintenance
{
    DynamicParam
    {
        New-SkypeComputerDynamicParam -Name ComputerName -Computers (Get-MediationServers) -Mandatory $True
    }

    Process
    {
        # Include Skype for Business functionality
        if (!(Get-Command "Get-CsUser" -ErrorAction SilentlyContinue))
        {
            Write-Host "Importing Skype tools" -ForegroundColor Green
            Import-Module "$env:ProgramFiles\Common Files\Skype for Business Server 2015\Modules\SkypeForBusiness\SkypeForBusiness.psd1"
        }

        Write-Host "`n`n`n`n`n`n`n`n`n`nMAKE SURE ALL SERVERS ARE PINGABLE AND WINRM REACHABLE" -ForegroundColor Cyan
        $connectionTest = Test-ServerActive -Server $PSBoundParameters.ComputerName
        if (!$connectionTest.PingSucceeded -and !$connectionTest.TcpTestSucceeded)
        {
            Write-Host "'$($PSBoundParameters.ComputerName)' is not reachable!" -ForegroundColor Red
            return;
        }

        if (!(Set-ServiceMaintenanceMode -ComputerName $PSBoundParameters.ComputerName -Enable $False -DisplayName 'Skype for Business Server Centralized Logging Service Agent' -Name 'RTCCLSAGT'))
        {
            return;
        }
        if (!(Set-ServiceMaintenanceMode -ComputerName $PSBoundParameters.ComputerName -Enable $False -DisplayName 'Skype for Business Server Mediation' -Name 'RTCMEDSRV'))
        {
            return;
        }
        if (!(Set-ServiceMaintenanceMode -ComputerName $PSBoundParameters.ComputerName -Enable $False -DisplayName 'Skype for Business Server Replica Replicator Agent' -Name 'REPLICA'))
        {
            return;
        }

        Write-Host "`n$($PSBoundParameters.ComputerName) were taken successfully out of Mediation Maintenance Mode!`n" -ForegroundColor Green
    }
}

Function Start-FrontEndMaintenance
{
    param(
        [Parameter()]
        [switch]$Reboot
    )

    DynamicParam
    {
        New-SkypeComputerDynamicParam -Name ComputerName -Computers (Get-FrontEndServers) -Mandatory $True
    }

    Process
    {
        # Include Skype for Business functionality
        if (!(Get-Command "Get-CsUser" -ErrorAction SilentlyContinue))
        {
            Write-Host "Importing Skype tools" -ForegroundColor Green
            Import-Module "$env:ProgramFiles\Common Files\Skype for Business Server 2015\Modules\SkypeForBusiness\SkypeForBusiness.psd1"
        }

        Get-CsPoolFabricState -PoolFqdn (Get-CentralManagementPool)
        $answer = Read-Host "`n`nWere there any replicas missing? (YES|NO)"
        if ($answer.ToLower().Trim() -eq "yes")
        {
            Write-Host "Please run the following and then rerun me: " -ForegroundColor Yellow -NoNewline
            Write-Host "'Reset-CsPoolRegistrarState -ResetType QuorumLossRecovery -PoolFqdn `"$(Get-CentralManagementPool)`"'" -ForegroundColor Cyan
            return;
        }

        Invoke-CsComputerFailOver -ComputerName $PSBoundParameters.ComputerName -Confirm:$False

        Write-Host "`n$($PSBoundParameters.ComputerName) were put successfully into FrontEnd Maintenance Mode!`n" -ForegroundColor Green

        if ($Reboot)
        {
            Invoke-RebootMachine -ComputerName $PSBoundParameters.ComputerName
        }
    }
}

Function Stop-FrontEndMaintenance
{
    DynamicParam
    {
        New-SkypeComputerDynamicParam -Name ComputerName -Computers (Get-FrontEndServers) -Mandatory $True
    }

    Process
    {
        # Include Skype for Business functionality
        if (!(Get-Command "Get-CsUser" -ErrorAction SilentlyContinue))
        {
            Write-Host "Importing Skype tools" -ForegroundColor Green
            Import-Module "$env:ProgramFiles\Common Files\Skype for Business Server 2015\Modules\SkypeForBusiness\SkypeForBusiness.psd1"
        }

        Write-Host "`n`n`n`n`n`n`n`n`n`nMAKE SURE ALL SERVERS ARE PINGABLE AND WINRM REACHABLE" -ForegroundColor Cyan
        $connectionTest = Test-ServerActive -Server $PSBoundParameters.ComputerName
        if (!$connectionTest.PingSucceeded -and !$connectionTest.TcpTestSucceeded)
        {
            Write-Host "'$($PSBoundParameters.ComputerName)' is not reachable!" -ForegroundColor Red
            return;
        }

        $doComputerFailBack = $True
        while ($doComputerFailBack)
        {
            try
            {
                Invoke-CsComputerFailBack -ComputerName $PSBoundParameters.ComputerName -Confirm:$False -ErrorAction Stop
                $doComputerFailBack = $False
            }
            catch
            {
                Write-Host "$_" -ForegroundColor Red
                Write-Host "Waiting 1 minute before retrying failback - ($(Get-Date -Format 'HH:mm:ss') <-> $((Get-Date).AddMinutes(1).ToString('HH:mm:ss')))" -ForegroundColor Yellow
                Start-Sleep -Seconds 60
            }
        }

        Write-Host "`n`nWaiting 4 minutes for fabric state to settle down - ($(Get-Date -Format 'HH:mm:ss') <-> $((Get-Date).AddMinutes(4).ToString('HH:mm:ss')))" -ForegroundColor Yellow
        Start-Sleep -Seconds 240

        $checkFabricState = $True
        while ($checkFabricState)
        {
            Get-CsPoolFabricState -PoolFqdn (Get-CentralManagementPool)

            $answer = Read-Host "`n`nWere there any replicas missing? (YES|NO)"
            if ($answer.ToLower().Trim() -eq "yes")
            {
                Write-Host "`n`nWaiting 1 minute before checking fabric state again - ($(Get-Date -Format 'HH:mm:ss') <-> $((Get-Date).AddMinutes(1).ToString('HH:mm:ss')))...`n" -ForegroundColor Yellow
                Start-Sleep -Seconds 60
            }
            elseif ($answer.ToLower().Trim() -eq "no")
            {
                $checkFabricState = $False
            }
        }

        Write-Host "`n$($PSBoundParameters.ComputerName) were taken successfully out of FrontEnd Maintenance Mode!`n" -ForegroundColor Green
    }
}