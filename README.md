
# Pomodoro PowerShell Toolkit

> **Note:** This project is for learning basic Shell Script (PowerShell) concepts only. It is not intended for production use or for storing important data.

This project provides a set of PowerShell scripts to help you manage your Pomodoro sessions, track tasks, and generate productivity reports. All data is stored in JSON files for easy access and history tracking.

## Features
- Start Pomodoro sessions and breaks
- Track tasks and completed Pomodoros
- View daily, weekly, and all-time statistics
- Generate summary reports
- Send notifications (supports BurntToast and Windows notifications)
- Historical data saved per day

## Directory Structure
```
data/
  pomodoro.json           # Main data file
  history/               # Daily history files
    pomodoro-YYYY-MM-DD.json
scripts/
  Get-PomodoroStats.ps1  # View statistics
  PomodoroFunctions.ps1  # Core functions (imported by other scripts)
  Start-Pomodoro.ps1     # Start a Pomodoro session
  Start-PomodoroTask.ps1 # Start a Pomodoro for a specific task
```

## Usage
1. **Import Functions**
   Import the core functions in your scripts:
   ```powershell
   . ./scripts/PomodoroFunctions.ps1
   ```
2. **Start a Pomodoro**
   ```powershell
   ./scripts/Start-Pomodoro.ps1 -Minutes 25
   ```
3. **Start a Pomodoro for a Task**
   ```powershell
   ./scripts/Start-PomodoroTask.ps1 -TaskName "Write Report" -Minutes 25
   ```
4. **View Statistics**
   ```powershell
   ./scripts/Get-PomodoroStats.ps1 -Period Day
   ./scripts/Get-PomodoroStats.ps1 -Period Week
   ./scripts/Get-PomodoroStats.ps1 -Period All
   ```

## Requirements
- PowerShell 5.1+

## Notes
- All data is stored locally in the `data` folder.
- Daily history is automatically created and updated.
- Notifications will use BurntToast if available, otherwise fallback to Windows or console output.

