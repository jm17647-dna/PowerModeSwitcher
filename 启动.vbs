' PowerModeSwitcher 启动器（不经过 cmd，双击即可）
Option Explicit
Dim fso, sh, dir, exe, ahk, svc, col, running
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
exe = dir & "\AutoHotkey64.exe"
ahk = dir & "\PowerModeSwitcher.ahk"

If Not fso.FileExists(exe) Then
  MsgBox "找不到 AutoHotkey64.exe，请确认它和本文件在同一个文件夹：" & vbCrLf & dir, 16, "启动失败"
  WScript.Quit 1
End If
If Not fso.FileExists(ahk) Then
  MsgBox "找不到 PowerModeSwitcher.ahk，请确认它和本文件在同一个文件夹：" & vbCrLf & dir, 16, "启动失败"
  WScript.Quit 1
End If

If AlreadyRunning() Then
  MsgBox "电源模式切换器已经在运行了。" & vbCrLf & vbCrLf & _
         "去右下角任务栏的 ∧ 里找它（蓝/粉/绿的小图标），" & vbCrLf & _
         "按 Alt+Q 切换，或右键菜单。", 64, "已经在运行"
  WScript.Quit 0
End If

sh.CurrentDirectory = dir
On Error Resume Next
sh.Run """" & exe & """ """ & ahk & """", 1, False
If Err.Number <> 0 Then
  MsgBox "启动失败：" & Err.Description, 16, "启动失败"
  WScript.Quit 1
End If
On Error Goto 0

WScript.Sleep 2000
If Not AlreadyRunning() Then
  MsgBox "程序被调用了，但 2 秒内没看到它跑起来。" & vbCrLf & vbCrLf & _
         "1) 先看 logs 目录里最新的日志写了什么" & vbCrLf & _
         "2) 可能是杀毒软件拦了 AutoHotkey64.exe" & vbCrLf & _
         "3) 路径：" & dir, 48, "没启动起来"
  WScript.Quit 1
End If

Function AlreadyRunning()
  Dim svc2, list, p
  AlreadyRunning = False
  On Error Resume Next
  Set svc2 = GetObject("winmgmts:\\.\root\cimv2")
  If Err.Number <> 0 Then
    Err.Clear
    AlreadyRunning = False
    Exit Function
  End If
  Set list = svc2.ExecQuery("select ProcessId from Win32_Process where Name='AutoHotkey64.exe'")
  For Each p In list
    AlreadyRunning = True
  Next
  On Error Goto 0
End Function