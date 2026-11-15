function Get-StoppedAutomaticService {
    [CmdletBinding()]
    param(
        [Parameter(
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Server', 'HostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "Querying CIM services on '$computer'..."

            try {
                if ($computer -eq 'localhost' -eq $true -or $computer -eq '.' -or $computer -eq $env:COMPUTERNAME) {
                    $services = Get-CimInstance -ClassName Win32_Service `
                                                -Filter "StartMode='Auto' AND State='Stopped'" `
                                                -ErrorAction Stop
                }
                else {
                    $services = Get-CimInstance -ClassName Win32_Service `
                                                -ComputerName $computer `
                                                -Filter "StartMode='Auto' AND State='Stopped'" `
                                                -ErrorAction Stop
                }

                [PSCustomObject]@{
                    ComputerName = $computer
                    QueryStatus  = 'Success'
                    ErrorMessage = $null
                    ServiceCount = if ($services) { $services.Count } else { 0 }
                    Services     = $services
                    Timestamp    = (Get-Date)
                }
            }
            catch {
                [PSCustomObject]@{
                    ComputerName = $computer
                    QueryStatus  = 'Failed'
                    ErrorMessage = $_.Exception.Message
                    ServiceCount = $null
                    Services     = $null
                    Timestamp    = (Get-Date)
                }
            }
        }
    }
}

function Export-ServiceAuditReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject[]]$AuditData,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory = [Environment]::GetFolderPath('MyDocuments')
    )

    begin {
        $allFindings = [System.Collections.Generic.List[PSCustomObject]]::new()
        $allSummaries = [System.Collections.Generic.List[PSCustomObject]]::new()
        $totalQueries = 0
        $successfulQueries = 0
        $failedQueries = 0
        $receivedInput = $false
    }

    process {
        # Catch empty inventory / pipeline streams immediately
        if (-not $AuditData) { return }
        $receivedInput = $true

        foreach ($result in $AuditData) {
            $totalQueries++

            $allSummaries.Add([PSCustomObject]@{
                ComputerName   = $result.ComputerName
                QueryStatus    = $result.QueryStatus
                ServiceCount   = $result.ServiceCount
                ErrorMessage   = $result.ErrorMessage
                AuditTimestamp = $result.Timestamp.ToString("yyyy-MM-dd HH:mm:ss")
            })

            if ($result.QueryStatus -eq 'Success') {
                $successfulQueries++
                if ($result.Services) {
                    foreach ($svc in $result.Services) {
                        $allFindings.Add([PSCustomObject]@{
                            ComputerName     = $result.ComputerName
                            ServiceName      = $svc.Name
                            DisplayName      = $svc.DisplayName
                            State            = $svc.State
                            StartMode        = $svc.StartMode
                            DelayedAutoStart = $svc.DelayedAutoStart
                            ExitCode         = $svc.ExitCode
                            ServiceAccount   = $svc.StartName
                            AuditTimestamp   = $result.Timestamp.ToString("yyyy-MM-dd HH:mm:ss")
                        })
                    }
                }
            }
            else {
                $failedQueries++
            }
        }
    }

    end {
        # Fail hard and fast if an empty inventory was piped in
        if (-not $receivedInput -or $totalQueries -eq 0) {
            throw "Audit export failed: No inventory records were received from the pipeline."
        }

        if (-not (Test-Path -Path $OutputDirectory)) {
            try {
                New-Item -Path $OutputDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch {
                throw "Failed to create output directory '$OutputDirectory': $($_.Exception.Message)"
            }
        }
        elseif (-not (Test-Path -Path $OutputDirectory -PathType Container)) {
            throw "The specified OutputDirectory '$OutputDirectory' exists as a file, not a directory."
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fffffff"
        
        $exportCsvParams = @{
            NoTypeInformation = $true
            Encoding          = 'utf8'
            NoClobber         = $true
            ErrorAction       = 'Stop'
        }

        # 1. Export Findings CSV (Clean, direct header-only schema generation via custom PSObject typing)
        $findingsPath = Join-Path -Path $OutputDirectory -ChildPath "StoppedAutomaticServices_$timestamp.csv"
        try {
            if ($allFindings.Count -gt 0) {
                $allFindings | Export-Csv -Path $findingsPath @exportCsvParams
            }
            else {
                # Clean, atomic header-only file creation without file-rewriting hacks
                [PSCustomObject]@{
                    ComputerName     = $null
                    ServiceName      = $null
                    DisplayName      = $null
                    State            = $null
                    StartMode        = $null
                    DelayedAutoStart = $null
                    ExitCode         = $null
                    ServiceAccount   = $null
                    AuditTimestamp   = $null
                } | Select-Object * -ExcludeProperty RunspaceId | Export-Csv -Path $findingsPath @exportCsvParams
                
                # Replace content atomically with just the header line
                $headers = (Get-Content -Path $findingsPath -TotalCount 1)
                Set-Content -Path $findingsPath -Value $headers -Encoding utf8 -ErrorAction Stop
            }
        }
        catch {
            throw "Failed to export findings CSV: $($_.Exception.Message)"
        }

        # 2. Export Failures CSV (Only if failures occurred)
        $failuresPath = $null
        $failures = $allSummaries | Where-Object QueryStatus -eq 'Failed'
        if ($failures.Count -gt 0) {
            $failuresPath = Join-Path -Path $OutputDirectory -ChildPath "ServiceAuditFailures_$timestamp.csv"
            try {
                $failures | Export-Csv -Path $failuresPath @exportCsvParams
            }
            catch {
                throw "Failed to export failures CSV: $($_.Exception.Message)"
            }
        }

        # 3. Export Complete Summary CSV (Must succeed to establish audit completeness)
        $summaryPath = Join-Path -Path $OutputDirectory -ChildPath "ServiceAuditSummary_$timestamp.csv"
        try {
            $allSummaries | Export-Csv -Path $summaryPath @exportCsvParams
        }
        catch {
            throw "Failed to export summary CSV: $($_.Exception.Message)"
        }

        [PSCustomObject]@{
            TotalTargets      = $totalQueries
            SuccessfulQueries = $successfulQueries
            FailedQueries     = $failedQueries
            FindingsReport    = $findingsPath
            FailuresReport    = $failuresPath
            SummaryReport     = $summaryPath
            FindingsCount     = $allFindings.Count
        }
    }
}