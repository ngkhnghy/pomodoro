param(
  [int]$WorkMinutes = 30,
  [int]$BreakMinutes = 5,
  [int]$Cycles = 5,
  [switch]$Auto # nếu set thì sẽ tự chạy liên tục theo số cycles
)

# Dot-source functions
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $scriptDir 'PomodoroFunctions.ps1')

Write-Host "Starting Pomodoro: Work $WorkMinutes min, Break $BreakMinutes min, Cycles: $Cycles"

for ($i = 1; $i -le $Cycles; $i++) {
  Write-Host "`n--- Cycle $i of ${Cycles}: Work ($WorkMinutes min) ---"
  Start-Timer -Minutes $WorkMinutes -Label "Work"
  Register-Session -TaskName '' -Minutes $WorkMinutes -Type 'Work'

  if ($i -eq $Cycles) { break }

  Write-Host "--- Break ($BreakMinutes min) ---"
  Start-Timer -Minutes $BreakMinutes -Label "Break"
  Register-Session -TaskName '' -Minutes $BreakMinutes -Type 'Break'
}

Write-Host "All cycles completed."
Send-Notification "Pomodoro" "Completed $Cycles cycle(s)."
