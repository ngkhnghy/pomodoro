param(
  [Parameter(Mandatory = $true)][string]$TaskName,
  [int]$WorkMinutes = 30,
  [int]$BreakMinutes = 5,
  [int]$ExpectedPomodoros = 1
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $scriptDir 'PomodoroFunctions.ps1')

Write-Host "Start task: $TaskName, Expecting $ExpectedPomodoros pomodoro(s)"
$count = 0
while ($count -lt $ExpectedPomodoros) {
  $count++
  Write-Host "`n[Task: $TaskName] Pomodoro #$count - Work $WorkMinutes min"
  Start-Timer -Minutes $WorkMinutes -Label "Work ($TaskName)"
  Register-Session -TaskName $TaskName -Minutes $WorkMinutes -Type 'Work'

  if ($count -ge $ExpectedPomodoros) { break }

  Write-Host "[Task: $TaskName] Break $BreakMinutes min"
  Start-Timer -Minutes $BreakMinutes -Label "Break ($TaskName)"
  Register-Session -TaskName $TaskName -Minutes $BreakMinutes -Type 'Break'
}

Send-Notification "Pomodoro Task Complete" "Task '$TaskName' completed $ExpectedPomodoros pomodoro(s)."
