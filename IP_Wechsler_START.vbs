Set objShell = CreateObject("Shell.Application")
strScript = Replace(WScript.ScriptFullName, WScript.ScriptName, "") & "IP_Wechsler.ps1"
objShell.ShellExecute "powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strScript & """", "", "runas", 0
