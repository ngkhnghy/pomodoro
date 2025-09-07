# PomodoroFunctions.ps1
# Thư viện các hàm dùng chung cho project Pomodoro

param()

$PomoRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "..")
$DataDir = Join-Path $PomoRoot "data"
$DataFile = Join-Path $DataDir "pomodoro.json"

function Ensure-DataFile {
  if (-not (Test-Path $DataDir)) {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
  }
  if (-not (Test-Path $DataFile)) {
    $initial = @{ tasks = @(); sessions = @() }
    $initial | ConvertTo-Json -Depth 5 | Set-Content -Path $DataFile -Encoding UTF8
  }
}

function Load-Data {
  if (-not (Test-Path $DataFile)) {
    Ensure-DataFile
  }
  $json = Get-Content -Path $DataFile -Raw
  return $json | ConvertFrom-Json
}

function Save-Data($data) {
  $data | ConvertTo-Json -Depth 5 | Set-Content -Path $DataFile -Encoding UTF8
}

function Start-Timer([int]$Minutes, [string]$Label = "Timer") {
  if ($Minutes -le 0) { return }
  $total = $Minutes * 60
  $start = Get-Date
  while ($total -gt 0) {
    $mins = [math]::Floor($total / 60)
    $secs = $total % 60
    Write-Host -NoNewline "`r[$Label] `t $mins`:$([string]::Format('{0:D2}', $secs)) "
    Start-Sleep -Seconds 1
    $total -= 1
  }
  Write-Host "`n[$Label] Completed: $Minutes minute(s) at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  try {
    [console]::Beep(900,500)
    Start-Sleep -Milliseconds 200
    [console]::Beep(1100,300)
  } catch { }
  Send-Notification "Pomodoro - $Label" "Đã hoàn tất $Label trong $Minutes phút."
}

function Record-Session([string]$TaskName, [int]$Minutes, [string]$Type) {
  $data = Load-Data
  $session = [PSCustomObject]@{
    Task = $TaskName
    Type = $Type
    Start = (Get-Date).ToString('o')
    DurationMinutes = $Minutes
  }
  $data.sessions += $session

  if ($TaskName -and $TaskName -ne '') {
    $exists = $data.tasks | Where-Object { $_.Name -eq $TaskName }
    if (-not $exists) {
      $data.tasks += [PSCustomObject]@{ Name = $TaskName; CompletedPomodoros = 0 }
    }
    # Nếu type là Work thì tăng completed pomodoro cho task
    if ($Type -eq 'Work') {
      $data.tasks | Where-Object { $_.Name -eq $TaskName } | ForEach-Object { $_.CompletedPomodoros = $_.CompletedPomodoros + 1 }
    }
  }

  Save-Data $data
}

function Get-Stats([ValidateSet('Day','Week','All')] [string]$Period = 'Day') {
  $data = Load-Data
  $now = Get-Date
  switch ($Period) {
    'Day' {
      $from = $now.Date
    }
    'Week' {
      $from = $now.Date.AddDays(-([int]($now.DayOfWeek)))
    }
    'All' {
      $from = [datetime]::MinValue
    }
  }
  $sessions = $data.sessions | Where-Object { [datetime]::Parse($_.Start) -ge $from }
  $totalMinutes = ($sessions | Measure-Object -Property DurationMinutes -Sum).Sum
  $grouped = $sessions | Group-Object -Property Task | ForEach-Object {
    [PSCustomObject]@{
      Task = $_.Name
      Sessions = $_.Count
      Minutes = ($_.Group | Measure-Object -Property DurationMinutes -Sum).Sum
    }
  }
  return [PSCustomObject]@{
    Period = $Period
    From = $from
    To = $now
    TotalMinutes = $totalMinutes
    ByTask = $grouped
  }
}