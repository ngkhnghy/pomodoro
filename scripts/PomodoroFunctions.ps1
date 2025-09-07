
param()

$PomoRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "..")
$DataDir = Join-Path $PomoRoot "data"
$DataFile = Join-Path $DataDir "pomodoro.json"

function Initialize-DataFile {
  if (-not (Test-Path $DataDir)) {
    New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
  }
  if (-not (Test-Path $DataFile)) {
    $initial = @{ tasks = @(); sessions = @() }
    $initial | ConvertTo-Json -Depth 5 | Set-Content -Path $DataFile -Encoding UTF8
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

function Save-Data($data) {
  $maxRetries = 5
  $retryCount = 0
  $backoffInterval = 500 # milliseconds
  
  $jsonContent = $data | ConvertTo-Json -Depth 5
  
  while ($retryCount -lt $maxRetries) {
    try {
      # Use Out-File with -NoNewline instead of Set-Content for better file locking behavior
      $jsonContent | Out-File -FilePath $DataFile -Encoding utf8 -NoNewline -Force
      return # Success, exit the function
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
    # Nếu type là Work thì tăng completed pomodoro cho task
    if ($Type -eq 'Work') {
      $data.tasks | Where-Object { $_.Name -eq $TaskName } | ForEach-Object { $_.CompletedPomodoros = $_.CompletedPomodoros + 1 }
    }
  }

  Save-Data $data
}

function Get-Stats([ValidateSet('Day', 'Week', 'All')] [string]$Period = 'Day') {
  $data = Get-Data
  $now = Get-Date
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

function Send-Notification([string]$Title, [string]$Message) {
  # Using BurntToast module if available
  if (Get-Module -ListAvailable -Name BurntToast) {
    try {
      New-BurntToastNotification -AppLogo "$PomoRoot\data\pomodoro.png" -Text $Title, $Message -ErrorAction SilentlyContinue
      return
    }
    catch {
      # Fallback to built-in method if BurntToast fails
    }
  }
  
  # Windows 10/11 built-in notification
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
    # Fallback if Windows APIs not available
    Write-Host "Notification: $Title - $Message" -ForegroundColor Yellow
  }
}

function Register-Session([string]$TaskName, [int]$Minutes, [string]$Type) {
  # This function wraps Add-Session for compatibility
  Add-Session -TaskName $TaskName -Minutes $Minutes -Type $Type
}