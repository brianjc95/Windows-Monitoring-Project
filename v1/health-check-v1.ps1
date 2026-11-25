
# ============================================
# Windows Server Health Monitor
# Version: 1.0
# Environment: companyx.local
# Purpose: Monitor CPU, Memory, and Disk Health
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
# Main Health Report
# --------------------------------------------

$Results = @()

$Results += Get-CPUHealth
$Results += Get-MemoryHealth
$Results += Get-DiskHealth

Write-Host ""
Write-Host "============================================"
Write-Host "       WINDOWS SERVER HEALTH REPORT"
Write-Host "============================================"

Write-Host "Server: $ServerName"
Write-Host "Date:   $Date"

Write-Host ""
Write-Host "SYSTEM HEALTH"
Write-Host "--------------------------------------------"

$Results | Format-Table Component, Usage, Status -AutoSize

Write-Host "============================================"
