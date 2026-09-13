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

function Test-WaddleNetworkPath {
  param([Parameter(Mandatory)][string]$Path)

  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith('\\')) { return $true }

  $root = [IO.Path]::GetPathRoot($full)
  if ([string]::IsNullOrWhiteSpace($root)) { return $false }
  try {
    $device = $root.TrimEnd('\').Replace("'","''")
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$device'" -ErrorAction Stop
    return [bool]($disk -and [int]$disk.DriveType -eq 4)
  } catch {
    return $false
  }
}

function Initialize-WaddlePrelaunchFlash {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string[]]$Arguments)

  $sourceValue = [string]$env:WADDLE_PPAPI_FLASH_PATH
  if ([string]::IsNullOrWhiteSpace($sourceValue)) { return @($Arguments) }

  $source = [IO.Path]::GetFullPath($sourceValue)
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "WADDLE_PPAPI_FLASH_PRELAUNCH=FAIL source_missing=$source"
  }

  $version = if ([string]::IsNullOrWhiteSpace([string]$env:WADDLE_PPAPI_FLASH_VERSION)) { '32.0.0.303' } else { ([string]$env:WADDLE_PPAPI_FLASH_VERSION).Trim() }
  $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToUpperInvariant()
  $networkBacked = Test-WaddleNetworkPath -Path $source
  $runtime = $source
  $copied = $false
  $mode = 'repo_direct'

  if ($networkBacked) {
    $localBase = [string]$env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($localBase)) { $localBase = [IO.Path]::GetTempPath() }
    $cacheDir = Join-Path $localBase ("WaddleForever\flash-cache\$version\$($sourceHash.ToLowerInvariant())")
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    $runtime = Join-Path $cacheDir (Split-Path -Leaf $source)

    $runtimeHash = ''
    if (Test-Path -LiteralPath $runtime -PathType Leaf) {
      try { $runtimeHash = (Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash.ToUpperInvariant() } catch { $runtimeHash = '' }
    }

    if ($runtimeHash -ne $sourceHash) {
      $temporary = "$runtime.$PID.$([DateTime]::UtcNow.Ticks).tmp"
      try {
        Copy-Item -LiteralPath $source -Destination $temporary -Force
        $temporaryHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($temporaryHash -ne $sourceHash) {
          throw "WADDLE_PPAPI_FLASH_PRELAUNCH=FAIL staged_hash_mismatch source=$sourceHash staged=$temporaryHash"
        }
        if (Test-Path -LiteralPath $runtime -PathType Leaf) { Remove-Item -LiteralPath $runtime -Force }
        Move-Item -LiteralPath $temporary -Destination $runtime -Force
        $copied = $true
      } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
      }
    }

    $runtimeHash = (Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($runtimeHash -ne $sourceHash) {
      throw "WADDLE_PPAPI_FLASH_PRELAUNCH=FAIL runtime_hash_mismatch source=$sourceHash runtime=$runtimeHash path=$runtime"
    }
    $mode = 'local_hash_cache'
  }

  try { Unblock-File -LiteralPath $runtime -ErrorAction Stop } catch {}

  # Chromium plugin discovery happens during Electron process initialization.
  # Supplying PPAPI only from main.ts is too late on some SMB-backed Windows
  # clients. Bind the verified runtime DLL before CreateProcessW and also leave
  # the same path in the child environment so flash-loader.ts observes one
  # canonical value.
  $env:WADDLE_PPAPI_FLASH_SOURCE_PATH = $source
  $env:WADDLE_PPAPI_FLASH_RUNTIME_PATH = $runtime
  $env:WADDLE_PPAPI_FLASH_PATH = $runtime

  $effective = New-Object System.Collections.Generic.List[string]
  $effective.Add("--ppapi-flash-path=$runtime")
  $effective.Add("--ppapi-flash-version=$version")
  foreach ($argument in @($Arguments)) {
    $text = [string]$argument
    if ($text.StartsWith('--ppapi-flash-path=',[StringComparison]::OrdinalIgnoreCase)) { continue }
    if ($text.StartsWith('--ppapi-flash-version=',[StringComparison]::OrdinalIgnoreCase)) { continue }
    $effective.Add($text)
  }

  Write-Host "WADDLE_PPAPI_FLASH_PRELAUNCH=PASS source=$source runtime=$runtime version=$version sha256=$sourceHash network_backed=$networkBacked mode=$mode copied=$copied command_line=true"
  return @($effective.ToArray())
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

  $effectiveArguments = @(Initialize-WaddlePrelaunchFlash -Arguments $ArgumentList)

  try {
    $pidValue = [Waddle.NativeProcess]::Start($exe,$effectiveArguments,$cwd)
  } catch {
    throw "WADDLE_WIN32_PROCESS=FAIL executable=$exe working_directory=$cwd error=$($_.Exception.Message)"
  }

  if ($pidValue -le 0) { throw "WADDLE_WIN32_PROCESS=FAIL process_id_invalid=$pidValue executable=$exe" }
  Write-Host "WADDLE_WIN32_PROCESS=PASS pid=$pidValue executable=$exe shell_execute=false inherit_handles=false detached_process=true ppapi_prelaunch=true"
  return [int]$pidValue
}
