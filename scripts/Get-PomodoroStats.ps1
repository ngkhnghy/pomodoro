[CmdletBinding(DefaultParameterSetName = 'Regular')]
param(
  [Parameter(ParameterSetName = 'Regular')]
  [ValidateSet('Day', 'Week', 'All')]
  [string]$Period = 'Day',
  
  [Parameter(ParameterSetName = 'Historical', Mandatory = $true)]
  [DateTime]$Date,
  
  [Parameter(ParameterSetName = 'Summary', Mandatory = $true)]
  [switch]$ShowSummary,
  
  [Parameter(ParameterSetName = 'Summary')]
  [int]$LastDays = 7
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $scriptDir 'PomodoroFunctions.ps1')

# Determine which parameter set is being used
$parameterSetName = $PSCmdlet.ParameterSetName

switch ($parameterSetName) {
  'Summary' {
    $summary = Get-PomodoroSummary -LastDays $LastDays
    Write-Host "Pomodoro Summary for Last $LastDays Days"
    Write-Host "----------------------------------------"
    $summary | Format-Table -AutoSize
    $totalMinutes = ($summary | Measure-Object -Property TotalMinutes -Sum).Sum
    $avgMinutes = ($summary | Measure-Object -Property TotalMinutes -Average).Average
    Write-Host "Total minutes: $totalMinutes"
    Write-Host "Average minutes per day: $([math]::Round($avgMinutes, 2))"
  }
  
  'Historical' {
    $stats = Get-HistoricalStats -Date $Date
    if ($stats) {
      Write-Host "Pomodoro Historical Stats for $($Date.ToString('yyyy-MM-dd'))"
      Write-Host "Total focused minutes: $($stats.TotalMinutes)"

      if ($stats.ByTask) {
        $stats.ByTask | Sort-Object -Property Minutes -Descending | Format-Table -AutoSize
      }
      else {
        Write-Host "No sessions in this period."
      }

      # Show tasks summary
      if ($stats.Tasks) {
        Write-Host "`nTasks overview:"
        $stats.Tasks | Select-Object Name, CompletedPomodoros | Format-Table -AutoSize
      }
    }
    else {
      Write-Host "No data found for $($Date.ToString('yyyy-MM-dd'))"
    }
  }
  
  'Regular' {
    $stats = Get-Stats -Period $Period
    Write-Host "Pomodoro Stats ($($stats.Period)) from $($stats.From) to $($stats.To)"
    Write-Host "Total focused minutes: $($stats.TotalMinutes)"

    if ($stats.ByTask) {
      $stats.ByTask | Sort-Object -Property Minutes -Descending | Format-Table -AutoSize
    }
    else {
      Write-Host "No sessions in this period."
    }

    # Show tasks summary
    $data = Get-Data
    if ($data.tasks) {
      Write-Host "`nTasks overview:"
      $data.tasks | Select-Object Name, CompletedPomodoros | Format-Table -AutoSize
    }
  }
}
