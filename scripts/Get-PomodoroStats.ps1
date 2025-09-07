param(
  [ValidateSet('Day','Week','All')]
  [string]$Period = 'Day'
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $scriptDir 'PomodoroFunctions.ps1')

$stats = Get-Stats -Period $Period
Write-Host "Pomodoro Stats ($($stats.Period)) from $($stats.From) to $($stats.To)"
Write-Host "Total focused minutes: $($stats.TotalMinutes)"

if ($stats.ByTask) {
  $stats.ByTask | Sort-Object -Property Minutes -Descending | Format-Table -AutoSize
} else {
  Write-Host "No sessions in this period."
}

# Show tasks summary
$data = Load-Data
if ($data.tasks) {
  Write-Host "`nTasks overview:"
  $data.tasks | Select-Object Name, CompletedPomodoros | Format-Table -AutoSize
}
