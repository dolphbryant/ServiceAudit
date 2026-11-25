# ServiceAudit

A PowerShell utility for identifying Windows services configured for **Automatic** startup that are currently in a **Stopped** state.

ServiceAudit supports local and remote Windows computers, pipeline input, structured error handling, and timestamped CSV reporting. It includes a Pester test suite for validating core functionality.

## Features

- Query the local computer by default.
- Query multiple remote computers through parameters, variables, or pipeline input.
- Retrieve service information using CIM (`Win32_Service`).
- Continue processing when individual computer queries fail.
- Distinguish successful queries from failed queries.
- Export timestamped CSV reports to a configurable directory.
- Preserve results for computers with zero matching services.
- Prevent accidental report overwrites using `-NoClobber`.
- Support automated testing with Pester 5.

## Requirements

- Windows with Windows PowerShell 5.1 or PowerShell 7.
- Appropriate permissions to query Windows services on target computers.
- WinRM connectivity and appropriate authentication for remote queries.
- Write access to the selected output directory.
- Pester 5.x for automated testing.

**Compatibility:** The script has been manually exercised under PowerShell 7 with Pester 5.9.0. Windows PowerShell 5.1 compatibility has not yet been verified.

## Files

```text
ServiceAudit/
├── Get-StoppedAutomaticServices.ps1
├── Tests/
│   └── ServiceAudit.Tests.ps1
└── README.md
```

## Getting Started

### 1. Load the functions

Open PowerShell in the project directory and dot-source the script:

```powershell
. .\Get-StoppedAutomaticServices.ps1
```

This loads the following functions into the current session:

- `Get-StoppedAutomaticService` — Collects service information and query status.
- `Export-ServiceAuditReport` — Generates CSV reports from collected audit results.

### 2. Query the local computer

```powershell
Get-StoppedAutomaticService
```

To inspect the matching services:

```powershell
$results = Get-StoppedAutomaticService

$results.Services |
    Select-Object Name, DisplayName, State, StartMode
```

### 3. Query remote computers

Specify computers directly:

```powershell
Get-StoppedAutomaticService -ComputerName SERVER01, SERVER02
```

Provide computer names using a variable:

```powershell
$servers = @('SERVER01', 'SERVER02', 'SERVER03')

$servers | Get-StoppedAutomaticService
```

Read computer names from a text file:

```powershell
Get-Content .\servers.txt |
    Get-StoppedAutomaticService
```

Each computer produces an audit result, even when the query fails.

### 4. Generate CSV reports

Query the local computer and export reports:

```powershell
Get-StoppedAutomaticService |
    Export-ServiceAuditReport
```

Specify a different output directory:

```powershell
Get-StoppedAutomaticService |
    Export-ServiceAuditReport -OutputDirectory 'C:\Reports'
```

Query several computers and export their results:

```powershell
Get-Content .\servers.txt |
    Get-StoppedAutomaticService |
    Export-ServiceAuditReport -OutputDirectory 'C:\Reports'
```

By default, reports are written to the current user's Documents directory.

## Report Types

ServiceAudit can generate three CSV reports.

| Report | Description |
|---|---|
| `StoppedAutomaticServices_<timestamp>.csv` | Services matching the audit criteria |
| `ServiceAuditFailures_<timestamp>.csv` | Computers whose CIM queries failed |
| `ServiceAuditSummary_<timestamp>.csv` | Query status and service count for every target |

The findings and summary reports are generated for successful export operations. The failures report is generated only when query failures occur.

When no matching services are found, the findings report contains the CSV headers without service records.

### Findings Report

Contains the computer name, service name, display name, current state, startup mode, delayed startup configuration, exit code, service account, and audit timestamp.

### Failures Report

Records unsuccessful queries, including the target computer, failure status, descriptive error message, and timestamp.

### Summary Report

Records every queried target, including computers that were successfully queried but had no matching services.

A failed query has an unknown service count rather than a count of zero.

## Error Handling

ServiceAudit captures individual CIM query failures as structured result objects.

For example, if `SERVER02` cannot be queried, the function records its error and continues processing subsequent computers.

Export failures, invalid output locations, and missing audit input can produce terminating errors.

**Note:** A successful service query does not indicate that the computer is healthy. Likewise, a stopped automatic service does not necessarily indicate a malfunction. Windows services may stop normally because of delayed startup, trigger-based operation, or application-specific behavior.

## Automated Testing

ServiceAudit includes a Pester v5 test suite.

Install Pester if necessary:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
```

Run the tests from the project directory:

```powershell
Invoke-Pester -Path .\Tests -Output Detailed
```

The current suite tests:

- Continued processing following a failed computer query.
- Explicit rejection of an empty inventory pipeline.
- Header-only CSV generation when no services match.
- Filename collision rejection using `-NoClobber`.

### Test Results

The initial local validation produced the following results:

| Test type | Result |
|---|---|
| Local CIM service enumeration | Passed |
| CSV export and import | Passed |
| Mixed successful and failed queries | Passed |
| Pester automated tests | All tests passing |

These results establish a working baseline for the tested scenarios, not comprehensive verification of every possible environment or failure condition.

## Known Limitations

- Remote computers are queried sequentially; large inventories may require significant execution time.
- Remote queries depend on available CIM/WinRM connectivity and permissions.
- CSV reports are generated as separate operations rather than an atomic transaction.
- The current test suite does not cover every possible I/O or remote connectivity failure.
- Windows PowerShell 5.1 compatibility requires further validation.
- The utility identifies stopped automatic services but does not determine whether their stopped state is abnormal.

## Future Improvements

Potential enhancements include broader Pester coverage, PowerShell compatibility testing, PSScriptAnalyzer integration, and automated test execution through GitHub Actions.

These improvements are not required for basic local service auditing.

## License

No license has been selected yet.
