# ============================================
# Windows Server Health Monitor
# Version: 4.0
# Environment: companyx.local
# Purpose: Monitor Server Resources, Services,
#          Event Logs, and Network Connectivity
# ============================================

# Server Information
$ServerName = $env:COMPUTERNAME
$Date = Get-Date

# Health Thresholds
$WarningThreshold = 80
$CriticalThreshold = 90

# --------------------------------------------
# Function 1: CPU Health
# --------------------------------------------

function Get-CPUHealth {

    $CPU = Get-CimInstance Win32_Processor

    $CPUUsage = ($CPU | Measure-Object -Property LoadPercentage -Average).Average

    if ($CPUUsage -ge $CriticalThreshold) {
        $Status = "CRITICAL"
    }
    elseif ($CPUUsage -ge $WarningThreshold) {
        $Status = "WARNING"
    }
    else {
        $Status = "HEALTHY"
    }

    [PSCustomObject]@{
        Component = "CPU"
        Usage     = "$CPUUsage%"
        Status    = $Status
    }
}

# --------------------------------------------
# Function 2: Memory Health
# --------------------------------------------

function Get-MemoryHealth {

    $Memory = Get-CimInstance Win32_OperatingSystem

    $TotalMemory = $Memory.TotalVisibleMemorySize
    $FreeMemory = $Memory.FreePhysicalMemory

    $UsedMemory = $TotalMemory - $FreeMemory

    $MemoryUsage = [math]::Round(
        ($UsedMemory / $TotalMemory) * 100, 2
    )

    if ($MemoryUsage -ge $CriticalThreshold) {
        $Status = "CRITICAL"
    }
    elseif ($MemoryUsage -ge $WarningThreshold) {
        $Status = "WARNING"
    }
    else {
        $Status = "HEALTHY"
    }

    [PSCustomObject]@{
        Component = "Memory"
        Usage     = "$MemoryUsage%"
        Status    = $Status
    }
}

# --------------------------------------------
# Function 3: Disk Health
# --------------------------------------------

function Get-DiskHealth {

    $Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

    foreach ($Disk in $Disks) {

        $DiskUsage = [math]::Round(
            (($Disk.Size - $Disk.FreeSpace) / $Disk.Size) * 100, 2
        )

        if ($DiskUsage -ge $CriticalThreshold) {
            $Status = "CRITICAL"
        }
        elseif ($DiskUsage -ge $WarningThreshold) {
            $Status = "WARNING"
        }
        else {
            $Status = "HEALTHY"
        }

        [PSCustomObject]@{
            Component = "Disk $($Disk.DeviceID)"
            Usage     = "$DiskUsage%"
            Status    = $Status
        }
    }
}

# --------------------------------------------
# Function 4: Windows Service Health
# --------------------------------------------

function Get-ServiceHealth {

    # Define critical services for the domain controller
    $RequiredServices = @(
        "NTDS",
        "DNS",
        "Netlogon",
        "KDC",
        "ADWS",
        "W32Time"
    )

    foreach ($ServiceName in $RequiredServices) {

        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if ($null -eq $Service) {
            $Status = "NOT FOUND"
            $ServiceState = "Unknown"
        }
        elseif ($Service.Status -ne "Running") {
            $Status = "CRITICAL"
            $ServiceState = $Service.Status
        }
        else {
            $Status = "HEALTHY"
            $ServiceState = $Service.Status
        }

        [PSCustomObject]@{
            Component = "Service: $ServiceName"
            Usage     = $ServiceState
            Status    = $Status
        }
    }
}
# --------------------------------------------
# Function 5: Event Log Health
# --------------------------------------------

function Get-EventLogHealth {

    $StartTime = (Get-Date).AddHours(-24)
    $EventLogs = @("System", "Application")

    foreach ($LogName in $EventLogs) {

        $Events = @(
            Get-WinEvent -FilterHashtable @{
                LogName = $LogName
                Level = 1,2
                StartTime = $StartTime
            } -MaxEvents 20 -ErrorAction SilentlyContinue
        )

        $CriticalCount = @(
            $Events | Where-Object { $_.Level -eq 1 }
        ).Count

        $ErrorCount = @(
            $Events | Where-Object { $_.Level -eq 2 }
        ).Count

        $TotalCount = $Events.Count

        if ($TotalCount -gt 0) {
            $Status = "REVIEW"
        }
        else {
            $Status = "HEALTHY"
        }

        [PSCustomObject]@{
            Component = "Event Log: $LogName"
            Usage = "$TotalCount Events | $CriticalCount Critical | $ErrorCount Error"
            Status = $Status
        }
    }
}
# --------------------------------------------
# Function 6: Detailed Event Report
# --------------------------------------------

function Get-DetailedEventReport {

    $StartTime = (Get-Date).AddHours(-24)
    $EventLogs = @("System", "Application")

    foreach ($LogName in $EventLogs) {

        $Events = Get-WinEvent -FilterHashtable @{
            LogName = $LogName
            Level = 1,2
            StartTime = $StartTime
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        foreach ($Event in $Events) {

            [PSCustomObject]@{
                LogName = $LogName
                TimeCreated = $Event.TimeCreated
                EventID = $Event.Id
                Source = $Event.ProviderName
                Severity = $Event.LevelDisplayName
                Message = $Event.Message
            }
        }
    }
}

# --------------------------------------------
# Function 7: Network Connectivity Health
# --------------------------------------------

function Get-NetworkHealth {

    # Discover default gateway
    $Gateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Where-Object { $_.NextHop -ne "0.0.0.0" } |
        Sort-Object RouteMetric |
        Select-Object -First 1 -ExpandProperty NextHop

    # Test gateway connectivity
    $GatewayStatus = Test-Connection -ComputerName $Gateway -Count 2 -Quiet -ErrorAction SilentlyContinue

    if ($GatewayStatus) {
        $Status = "HEALTHY"
    }
    else {
        $Status = "CRITICAL"
    }

    [PSCustomObject]@{
        Component = "Network Gateway"
        Usage = $Gateway
        Status = $Status
    }

    # Test external connectivity
    $ExternalIP = "8.8.8.8"

    $ExternalStatus = Test-Connection -ComputerName $ExternalIP -Count 2 -Quiet -ErrorAction SilentlyContinue

    if ($ExternalStatus) {
        $Status = "HEALTHY"
    }
    else {
        $Status = "CRITICAL"
    }

    [PSCustomObject]@{
        Component = "External Connectivity"
        Usage = $ExternalIP
        Status = $Status
    }

    # Discover configured DNS server
    $DNSServer = Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object {
            $_.InterfaceAlias -eq "Ethernet" -and
            $_.ServerAddresses.Count -gt 0
        } |
        Select-Object -First 1 -ExpandProperty ServerAddresses

    # Test external DNS resolution
    try {
        $DNSResult = Resolve-DnsName google.com -Server $DNSServer -ErrorAction Stop

        $DNSStatus = "HEALTHY"
        $DNSUsage = "google.com resolved"
    }
    catch {
        $DNSStatus = "CRITICAL"
        $DNSUsage = "DNS resolution failed"
    }

    [PSCustomObject]@{
        Component = "External DNS"
        Usage = $DNSUsage
        Status = $DNSStatus
    }

    # Test Active Directory LDAP SRV record
    try {
        $ADRecord = Resolve-DnsName `
            -Name "_ldap._tcp.dc._msdcs.companyx.local" `
            -Type SRV `
            -Server $DNSServer `
            -ErrorAction Stop

        $ADStatus = "HEALTHY"
        $ADUsage = $ADRecord.NameTarget
    }
    catch {
        $ADStatus = "CRITICAL"
        $ADUsage = "AD DNS record not found"
    }

    [PSCustomObject]@{
        Component = "AD DNS Discovery"
        Usage = $ADUsage
        Status = $ADStatus
    }

}


# --------------------------------------------
# Main Health Report
# --------------------------------------------

$Results = @()

$Results += Get-CPUHealth
$Results += Get-MemoryHealth
$Results += Get-DiskHealth
$Results += Get-ServiceHealth
$Results += Get-EventLogHealth
$Results += Get-NetworkHealth
# --------------------------------------------
# Overall Server Health Status
# --------------------------------------------

if ($Results.Status -contains "CRITICAL" -or $Results.Status -contains "NOT FOUND") {
    $OverallStatus = "CRITICAL"
}
elseif ($Results.Status -contains "REVIEW" -or $Results.Status -contains "WARNING") {
    $OverallStatus = "REVIEW"
}
else {
    $OverallStatus = "HEALTHY"
}
# --------------------------------------------
# Component Health Counts
# --------------------------------------------

$HealthyCount = ($Results | Where-Object { $_.Status -eq "HEALTHY" }).Count
$WarningCount = ($Results | Where-Object { $_.Status -eq "WARNING" }).Count
$ReviewCount = ($Results | Where-Object { $_.Status -eq "REVIEW" }).Count
$CriticalCount = ($Results | Where-Object { $_.Status -eq "CRITICAL" }).Count
$NotFoundCount = ($Results | Where-Object { $_.Status -eq "NOT FOUND" }).Count

Write-Host ""
Write-Host "============================================"
Write-Host "       WINDOWS SERVER HEALTH REPORT"
Write-Host "============================================"

Write-Host "Server: $ServerName"
Write-Host "Date:   $Date"
Write-Host "Overall Status: $OverallStatus"

Write-Host ""
Write-Host "HEALTH SUMMARY"
Write-Host "--------------------------------------------"
Write-Host "Healthy Components:  $HealthyCount"
Write-Host "Review Components:   $ReviewCount"
Write-Host "Critical Components: $CriticalCount"
Write-Host "Warning Components:   $WarningCount"
Write-Host "Not Found Components:  $NotFoundCount"

Write-Host ""
Write-Host "SYSTEM HEALTH"
Write-Host "--------------------------------------------"

$Results | Format-Table Component, Usage, Status -AutoSize
# --------------------------------------------
# Export Detailed Event Report
# --------------------------------------------
$ReportDate = Get-Date -Format "yyyyMMdd_HHmmss"

$CSVPath = Join-Path $PSScriptRoot "EventReport_$ReportDate.csv"

$TextReportPath = Join-Path $PSScriptRoot "HealthReport_$ReportDate.txt"
Get-DetailedEventReport |
    Export-Csv -Path $CSVPath -NoTypeInformation

Write-Host ""
Write-Host "Detailed event report saved to:"
Write-Host $CSVPath
# --------------------------------------------
# Export Full Health Report
# --------------------------------------------

$ResultsTable = $Results |
    Format-Table Component, Usage, Status -AutoSize |
    Out-String -Width 200

$TextReport = @"
============================================
       WINDOWS SERVER HEALTH REPORT
============================================
Server: $ServerName
Date:   $Date
Overall Status: $OverallStatus

HEALTH SUMMARY
--------------------------------------------
Healthy Components:  $HealthyCount
Review Components:   $ReviewCount
Critical Components: $CriticalCount
Warning Components:  $WarningCount
Not Found Components: $NotFoundCount

SYSTEM HEALTH
--------------------------------------------

$ResultsTable
"@

$TextReport | Set-Content -Path $TextReportPath

Write-Host ""
Write-Host "Full health report saved to:"
Write-Host $TextReportPath

Write-Host "============================================"

