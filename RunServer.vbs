' AFET Dental Care - start the system with no visible window.
' Point Task Scheduler at this file (Program: wscript.exe, Argument: this file's full path).
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "cmd /c """ & here & "\start-system.bat""", 0, False
