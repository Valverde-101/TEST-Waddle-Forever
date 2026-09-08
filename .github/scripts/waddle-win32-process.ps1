Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CreateProcessW is used deliberately for interactive Waddle startup.
# - ShellExecute is never involved, so Windows Explorer/Attachment Execution
#   Services are not asked to open the network EXE.
# - bInheritHandles=FALSE prevents Electron/Chromium children from retaining
#   the launcher's stdout/stderr pipes (important for PowerShell and CI).
# - DETACHED_PROCESS prevents the GUI process from inheriting the launcher's
#   console while preserving the current process environment.
if (-not ('Waddle.NativeProcess' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Waddle {
  public static class NativeProcess {
    private const uint DETACHED_PROCESS = 0x00000008;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO {
      public uint cb;
      public string lpReserved;
      public string lpDesktop;
      public string lpTitle;
      public uint dwX;
      public uint dwY;
      public uint dwXSize;
      public uint dwYSize;
      public uint dwXCountChars;
      public uint dwYCountChars;
      public uint dwFillAttribute;
      public uint dwFlags;
      public ushort wShowWindow;
      public ushort cbReserved2;
      public IntPtr lpReserved2;
      public IntPtr hStdInput;
      public IntPtr hStdOutput;
      public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION {
      public IntPtr hProcess;
      public IntPtr hThread;
      public uint dwProcessId;
      public uint dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcessW(
      string lpApplicationName,
      StringBuilder lpCommandLine,
      IntPtr lpProcessAttributes,
      IntPtr lpThreadAttributes,
      bool bInheritHandles,
      uint dwCreationFlags,
      IntPtr lpEnvironment,
      string lpCurrentDirectory,
      ref STARTUPINFO lpStartupInfo,
      out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    private static string Quote(string value) {
      if (value == null) return "\"\"";
      if (value.Length > 0 && value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0) return value;

      var result = new StringBuilder();
      result.Append('"');
      int backslashes = 0;
      foreach (char c in value) {
        if (c == '\\') {
          backslashes++;
          continue;
        }
        if (c == '"') {
          result.Append('\\', backslashes * 2 + 1);
          result.Append('"');
          backslashes = 0;
          continue;
        }
        if (backslashes > 0) {
          result.Append('\\', backslashes);
          backslashes = 0;
        }
        result.Append(c);
      }
      if (backslashes > 0) result.Append('\\', backslashes * 2);
      result.Append('"');
      return result.ToString();
    }

    public static int Start(string fileName, string[] arguments, string workingDirectory) {
      if (String.IsNullOrWhiteSpace(fileName)) throw new ArgumentException("fileName");
      if (String.IsNullOrWhiteSpace(workingDirectory)) throw new ArgumentException("workingDirectory");

      var commandLine = new StringBuilder(Quote(fileName));
      if (arguments != null) {
        foreach (var argument in arguments) {
          commandLine.Append(' ');
          commandLine.Append(Quote(argument ?? String.Empty));
        }
      }

      var startup = new STARTUPINFO();
      startup.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFO));
      PROCESS_INFORMATION processInfo;
      bool created = CreateProcessW(
        fileName,
        commandLine,
        IntPtr.Zero,
        IntPtr.Zero,
        false,
        DETACHED_PROCESS,
        IntPtr.Zero,
        workingDirectory,
        ref startup,
        out processInfo);

      if (!created) throw new Win32Exception(Marshal.GetLastWin32Error());

      try {
        return checked((int)processInfo.dwProcessId);
      }
      finally {
        if (processInfo.hThread != IntPtr.Zero) CloseHandle(processInfo.hThread);
        if (processInfo.hProcess != IntPtr.Zero) CloseHandle(processInfo.hProcess);
      }
    }
  }
}
'@
}

function Start-WaddleWin32DetachedProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$ArgumentList,
    [Parameter(Mandatory)][string]$WorkingDirectory
  )

  $exe = [IO.Path]::GetFullPath($FilePath)
  $cwd = [IO.Path]::GetFullPath($WorkingDirectory)
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "WADDLE_WIN32_PROCESS=FAIL executable_missing=$exe"
  }
  if (-not (Test-Path -LiteralPath $cwd -PathType Container)) {
    throw "WADDLE_WIN32_PROCESS=FAIL working_directory_missing=$cwd"
  }

  try {
    $pidValue = [Waddle.NativeProcess]::Start($exe,$ArgumentList,$cwd)
  } catch {
    throw "WADDLE_WIN32_PROCESS=FAIL executable=$exe working_directory=$cwd error=$($_.Exception.Message)"
  }

  if ($pidValue -le 0) { throw "WADDLE_WIN32_PROCESS=FAIL process_id_invalid=$pidValue executable=$exe" }
  Write-Host "WADDLE_WIN32_PROCESS=PASS pid=$pidValue executable=$exe shell_execute=false inherit_handles=false detached_process=true"
  return [int]$pidValue
}
