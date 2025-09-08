
param()

$PomoRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "..")
$DataDir = Join-Path $PomoRoot "data"
$HistoryDir = Join-Path $DataDir "history"
$DataFile = Join-Path $DataDir "pomodoro.json"

function Get-CurrentDateFile {
  $today = Get-Date -Format "yyyy-MM-dd"
  return Join-Path $HistoryDir "pomodoro-$today.json"
}

function Initialize-DataFile {
  if (-not (Test-Path $DataDir)) {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
  }
  
  if (-not (Test-Path $HistoryDir)) {
    New-Item -Path $HistoryDir -ItemType Directory -Force | Out-Null
  }
  
  if (-not (Test-Path $DataFile)) {
    $initial = @{ tasks = @(); sessions = @() }
    $initial | ConvertTo-Json -Depth 5 | Set-Content -Path $DataFile -Encoding UTF8
  }
  
  $todayFile = Get-CurrentDateFile
  if (-not (Test-Path $todayFile)) {
    $initial = @{ tasks = @(); sessions = @(); date = (Get-Date -Format "yyyy-MM-dd") }
    $initial | ConvertTo-Json -Depth 5 | Set-Content -Path $todayFile -Encoding UTF8
  }
}

function Get-Data {
  if (-not (Test-Path $DataFile)) {
    Initialize-DataFile
  }
  
  $maxRetries = 5
  $retryCount = 0
  $backoffInterval = 500 # milliseconds
  $json = $null
  
  while ($retryCount -lt $maxRetries) {
    try {
      $json = Get-Content -Path $DataFile -Raw -ErrorAction Stop
      break # Success, exit the loop
    }
    catch {
      $retryCount++
      Write-Verbose "Failed to read data from $DataFile (Attempt $retryCount of $maxRetries): $($_.Exception.Message)"
      
      if ($retryCount -lt $maxRetries) {
        # Exponential backoff
        $waitTime = $backoffInterval * [Math]::Pow(2, $retryCount - 1)
        Start-Sleep -Milliseconds $waitTime
      }
      else {
        Write-Warning "Failed to read data after $maxRetries attempts: $($_.Exception.Message)"
        # Return empty data structure to prevent further errors
        return [PSCustomObject]@{ tasks = @(); sessions = @() }
      }
    }
  }
  
  if ([string]::IsNullOrWhiteSpace($json)) {
    # If the file is empty or only contains whitespace, return empty structure
    return [PSCustomObject]@{ tasks = @(); sessions = @() }
  }
  
  try {
    return $json | ConvertFrom-Json
  }
  catch {
    Write-Warning "Failed to parse JSON data: $($_.Exception.Message)"
    # Return empty data structure if JSON parsing fails
    return [PSCustomObject]@{ tasks = @(); sessions = @() }
  }
}

function Save-Data($data, [switch]$SkipDailyFile) {
  $maxRetries = 5
  $retryCount = 0
  $backoffInterval = 500 # milliseconds
  
  $jsonContent = $data | ConvertTo-Json -Depth 5
  
  # Save to main data file
  while ($retryCount -lt $maxRetries) {
    try {
      # Use Out-File with -NoNewline instead of Set-Content for better file locking behavior
      $jsonContent | Out-File -FilePath $DataFile -Encoding utf8 -NoNewline -Force
      break # Success, continue to save daily file
    }
    catch {
      $retryCount++
      Write-Verbose "Failed to save data to $DataFile (Attempt $retryCount of $maxRetries): $($_.Exception.Message)"
      
      if ($retryCount -lt $maxRetries) {
        # Exponential backoff
        $waitTime = $backoffInterval * [Math]::Pow(2, $retryCount - 1)
        Start-Sleep -Milliseconds $waitTime
      }
      else {
        Write-Warning "Failed to save data after $maxRetries attempts: $($_.Exception.Message)"
        return # Exit on failure
      }
    }
  }
  
  # Save to daily file
  if (-not $SkipDailyFile) {
    $todayFile = Get-CurrentDateFile
    $retryCount = 0
    
    # Prepare daily data - Add date information
    $dailyData = $data.PSObject.Copy()
    $dailyData | Add-Member -NotePropertyName "date" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd") -Force
    $dailyContent = $dailyData | ConvertTo-Json -Depth 5
    
    # Get only today's sessions for the daily file
    $today = (Get-Date).Date
    $todaySessions = $data.sessions | Where-Object { 
      $sessionDate = [datetime]::Parse($_.Start).Date
      $sessionDate -eq $today 
    }
    
    # If daily file exists, update it instead of overwriting
    if (Test-Path $todayFile) {
      try {
        $existingDailyData = Get-Content -Path $todayFile -Raw | ConvertFrom-Json
        # Add today's sessions while keeping historical ones
        $existingDailyData.sessions = $todaySessions
        $existingDailyData.tasks = $data.tasks
        $dailyContent = $existingDailyData | ConvertTo-Json -Depth 5
      }
      catch {
        Write-Warning "Failed to read existing daily file: $($_.Exception.Message). Creating new file."
      }
    }
    
    while ($retryCount -lt $maxRetries) {
      try {
        $dailyContent | Out-File -FilePath $todayFile -Encoding utf8 -NoNewline -Force
        return # Success, exit the function
      }
      catch {
        $retryCount++
        Write-Verbose "Failed to save data to $todayFile (Attempt $retryCount of $maxRetries): $($_.Exception.Message)"
        
        if ($retryCount -lt $maxRetries) {
          # Exponential backoff
          $waitTime = $backoffInterval * [Math]::Pow(2, $retryCount - 1)
          Start-Sleep -Milliseconds $waitTime
        }
        else {
          Write-Warning "Failed to save daily data after $maxRetries attempts: $($_.Exception.Message)"
        }
      }
    }
  }
}

function Start-Timer([int]$Minutes, [string]$Label = "Timer") {
  if ($Minutes -le 0) { return }
  $total = $Minutes * 60
  while ($total -gt 0) {
    $mins = [math]::Floor($total / 60)
    $secs = $total % 60
    Write-Host -NoNewline "`r[$Label] `t $mins`:$([string]::Format('{0:D2}', $secs)) "
    Start-Sleep -Seconds 1
    $total -= 1
  }
  Write-Host "`n[$Label] Completed: $Minutes minute(s) at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  try {
    [console]::Beep(900, 500)
    Start-Sleep -Milliseconds 200
    [console]::Beep(1100, 300)
  }
  catch { }
  Send-Notification "Pomodoro - $Label" "$Label completed in $Minutes minute(s)."
}

function Add-Session([string]$TaskName, [int]$Minutes, [string]$Type) {
  $data = Get-Data
  $session = [PSCustomObject]@{
    Task            = $TaskName
    Type            = $Type
    Start           = (Get-Date).ToString('o')
    DurationMinutes = $Minutes
  }
  $data.sessions += $session

  if ($TaskName -and $TaskName -ne '') {
    $exists = $data.tasks | Where-Object { $_.Name -eq $TaskName }
    if (-not $exists) {
      $data.tasks += [PSCustomObject]@{ Name = $TaskName; CompletedPomodoros = 0 }
    }

    if ($Type -eq 'Work') {
      $data.tasks | Where-Object { $_.Name -eq $TaskName } | ForEach-Object { $_.CompletedPomodoros = $_.CompletedPomodoros + 1 }
    }
  }

  Save-Data $data
}

function Get-Stats([ValidateSet('Day', 'Week', 'All')] [string]$Period = 'Day', [DateTime]$CustomDate = [DateTime]::Now) {
  $data = Get-Data
  $now = $CustomDate
  switch ($Period) {
    'Day' {
      $from = $now.Date
    }
    'Week' {
      $from = $now.Date.AddDays( - ([int]($now.DayOfWeek)))
    }
    'All' {
      $from = [datetime]::MinValue
    }
  }
  $sessions = $data.sessions | Where-Object { [datetime]::Parse($_.Start) -ge $from }
  $totalMinutes = ($sessions | Measure-Object -Property DurationMinutes -Sum).Sum
  $grouped = $sessions | Group-Object -Property Task | ForEach-Object {
    [PSCustomObject]@{
      Task     = $_.Name
      Sessions = $_.Count
      Minutes  = ($_.Group | Measure-Object -Property DurationMinutes -Sum).Sum
    }
  }
  return [PSCustomObject]@{
    Period       = $Period
    From         = $from
    To           = $now
    TotalMinutes = $totalMinutes
    ByTask       = $grouped
  }
}

function Get-HistoricalStats([DateTime]$Date) {
  $dateStr = $Date.ToString("yyyy-MM-dd")
  $historyFile = Join-Path $HistoryDir "pomodoro-$dateStr.json"
  
  if (-not (Test-Path $historyFile)) {
    Write-Warning "No data found for $dateStr"
    return $null
  }
  
  try {
    $historyData = Get-Content -Path $historyFile -Raw | ConvertFrom-Json
    
    $sessions = $historyData.sessions
    $totalMinutes = ($sessions | Measure-Object -Property DurationMinutes -Sum).Sum
    $grouped = $sessions | Group-Object -Property Task | ForEach-Object {
      [PSCustomObject]@{
        Task     = $_.Name
        Sessions = $_.Count
        Minutes  = ($_.Group | Measure-Object -Property DurationMinutes -Sum).Sum
      }
    }
    
    return [PSCustomObject]@{
      Period       = "Historical"
      Date         = $Date
      TotalMinutes = $totalMinutes
      ByTask       = $grouped
      Tasks        = $historyData.tasks
    }
  }
  catch {
    Write-Warning "Failed to read historical data for $dateStr`: $($_.Exception.Message)"
    return $null
  }
}

function Get-DateRange([DateTime]$StartDate, [DateTime]$EndDate) {
  $range = @()
  $current = $StartDate
  
  while ($current -le $EndDate) {
    $range += $current
    $current = $current.AddDays(1)
  }
  
  return $range
}

function Get-PomodoroSummary([int]$LastDays = 7) {
  $endDate = [DateTime]::Now.Date
  $startDate = $endDate.AddDays(-($LastDays - 1))
  $dates = Get-DateRange -StartDate $startDate -EndDate $endDate
  
  $summary = @()
  
  foreach ($date in $dates) {
    $stats = Get-HistoricalStats -Date $date
    
    if ($stats) {
      $summary += [PSCustomObject]@{
        Date         = $date
        TotalMinutes = $stats.TotalMinutes
        Tasks        = ($stats.ByTask | Measure-Object).Count
        TopTask      = if ($stats.ByTask) { ($stats.ByTask | Sort-Object -Property Minutes -Descending)[0].Task } else { "None" }
      }
    }
    else {
      $summary += [PSCustomObject]@{
        Date         = $date
        TotalMinutes = 0
        Tasks        = 0
        TopTask      = "None"
      }
    }
  }
  
  return $summary
}

function Send-Notification([string]$Title, [string]$Message) {
  if (Get-Module -ListAvailable -Name BurntToast) {
    try {
      New-BurntToastNotification -AppLogo "$PomoRoot\data\pomodoro.png" -Text $Title, $Message -ErrorAction SilentlyContinue
      return
    }
    catch {
    }
  }
  
  try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    
    $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
    $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
    $textNodes = $xml.GetElementsByTagName("text")
    $textNodes.Item(0).AppendChild($xml.CreateTextNode($Title)) | Out-Null
    $textNodes.Item(1).AppendChild($xml.CreateTextNode($Message)) | Out-Null
    
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Pomodoro Timer")
    $notifier.Show($toast)
    return
  }
  catch {
    Write-Host "Notification: $Title - $Message" -ForegroundColor Yellow
  }
}

function Register-Session([string]$TaskName, [int]$Minutes, [string]$Type) {
  Add-Session -TaskName $TaskName -Minutes $Minutes -Type $Type
}