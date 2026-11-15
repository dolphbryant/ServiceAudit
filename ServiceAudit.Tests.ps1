Describe "Enterprise Service Audit Tool - Pester v5 Suite" {
    BeforeAll {
        # Ensure functions are loaded into the test session context
        # (In practice, dot-source your script file here: . "$PSScriptRoot\ServiceAudit.ps1")
        . "$PSScriptRoot\ServiceAudit.ps1"
        $script:MockStaticDate = [datetime]"2026-11-13 12:00:00.1234567"
    }

    BeforeEach {
        # ISOLATION FIX: Create a fresh, empty workspace for EVERY individual test
        $script:TestRoot = Join-Path $env:TEMP "PesterSandbox_$(Get-Random)"
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        # Cleanup sandbox to prevent any cross-test file pollution
        if (Test-Path $script:TestRoot) {
            Remove-Item -Path $script:TestRoot -Recurse -Force
        }
    }

    Context "Get-StoppedAutomaticService (Data Collection & Pipeline Resilience)" {
        It "Should continue processing subsequent hosts when an intermediate host fails" {
            # Arrange mock behaviors for a mixed multi-host batch
            Mock Get-CimInstance { 
                return @([PSCustomObject]@{ Name='Svc1'; DisplayName='1'; State='Stopped'; StartMode='Auto'; DelayedAutoStart=$false; ExitCode=0; StartName='LocalSystem' }) 
            } -ParameterFilter { $ComputerName -eq 'SERVER-OK1' }

            Mock Get-CimInstance { 
                throw "RPC Server Unavailable" 
            } -ParameterFilter { $ComputerName -eq 'SERVER-DOWN' }

            Mock Get-CimInstance { 
                return $null # Zero matching services
            } -ParameterFilter { $ComputerName -eq 'SERVER-OK2' }

            # Act
            $results = @('SERVER-OK1', 'SERVER-DOWN', 'SERVER-OK2') | Get-StoppedAutomaticService

            # Assert complete batch execution order and resilience
            $results.Count | Should -Be 3
            $results[0].ComputerName | Should -Be 'SERVER-OK1'
            $results[0].QueryStatus  | Should -Be 'Success'
            $results[0].ServiceCount | Should -Be 1

            $results[1].ComputerName | Should -Be 'SERVER-DOWN'
            $results[1].QueryStatus  | Should -Be 'Failed'
            $results[1].ErrorMessage | Should -Match "RPC Server Unavailable"

            $results[2].ComputerName | Should -Be 'SERVER-OK2'
            $results[2].QueryStatus  | Should -Be 'Success'
            $results[2].ServiceCount | Should -Be 0
        }
    }

    Context "Export-ServiceAuditReport (Reporting, Schema & Collision Integrity)" {
        BeforeEach {
            # CONTRACT FIX: Mock Get-Date to properly handle -Format strings identically to native cmdlet
            Mock Get-Date {
                if ($Format) {
                    return $script:MockStaticDate.ToString($Format, [System.Globalization.CultureInfo]::InvariantCulture)
                }
                return $script:MockStaticDate
            }
        }

        It "Should fail explicitly when piped an empty array inventory stream" {
            {
                @() | Export-ServiceAuditReport -OutputDirectory $script:TestRoot
            } | Should -Throw "*No inventory records were received*"
        }

        It "Should generate a header-only CSV with correct schema when zero findings occur" {
            $auditRecord = [PSCustomObject]@{
                ComputerName = 'SERVER-CLEAN'
                QueryStatus  = 'Success'
                ErrorMessage = $null
                ServiceCount = 0
                Services     = $null
                Timestamp    = $script:MockStaticDate
            }

            $manifest = $auditRecord | Export-ServiceAuditReport -OutputDirectory $script:TestRoot

            Test-Path $manifest.FindingsReport | Should -Be $true
            $lines = @(Get-Content -LiteralPath $manifest.FindingsReport)
            $lines.Count | Should -Be 1
            $lines[0] | Should -BeExactly '"ComputerName","ServiceName","DisplayName","State","StartMode","DelayedAutoStart","ExitCode","ServiceAccount","AuditTimestamp"'
        }

        It "Should deterministically enforce -NoClobber, throw a collision error, and protect existing data" {
            $auditRecord = [PSCustomObject]@{
                ComputerName = 'SERVER-OK'
                QueryStatus  = 'Success'
                ErrorMessage = $null
                ServiceCount = 0
                Services     = $null
                Timestamp    = $script:MockStaticDate
            }

            # First run creates the report in the isolated sandbox
            $manifest1 = $auditRecord | Export-ServiceAuditReport -OutputDirectory $script:TestRoot
            $originalContent = Get-Content $manifest1.SummaryReport

            # Second run with identical static timestamp in the same isolated sandbox MUST trigger -NoClobber
            {
                $auditRecord | Export-ServiceAuditReport -OutputDirectory $script:TestRoot
            } | Should -Throw "*already exists*"

            # Assert that the original report file contents were untouched by the collision attempt
            (Get-Content $manifest1.SummaryReport) | Should -Be $originalContent
        }
    }
}