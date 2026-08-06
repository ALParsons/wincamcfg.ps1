#requires -Version 5.1
<#
.SYNOPSIS
Reads and updates Windows camera controls through DirectShow.

.EXAMPLE
.\wincamcfg.ps1 list
.\wincamcfg.ps1 get --camera 0
.\wincamcfg.ps1 set --camera all --property PowerlineFrequency --value 50Hz
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace WinCamCfg.PowerShell
{
    [ComImport, Guid("29840822-5B84-11D0-BD3B-00A0C911CE86"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface ICreateDevEnum
    {
        [PreserveSig]
        int CreateClassEnumerator(ref Guid category, out IEnumMoniker enumerator, int flags);
    }

    [ComImport, Guid("55272A00-42CB-11CE-8135-00AA004BB851"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyBag
    {
        [PreserveSig]
        int Read([MarshalAs(UnmanagedType.LPWStr)] string name,
                 [MarshalAs(UnmanagedType.Struct)] out object value,
                 IntPtr errorLog);
        [PreserveSig]
        int Write([MarshalAs(UnmanagedType.LPWStr)] string name,
                  [MarshalAs(UnmanagedType.Struct)] ref object value);
    }

    // IID_IAMVideoProcAmp from strmif.h.
    [ComImport, Guid("C6E13360-30AC-11D0-A18C-00A0C9118956"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAMVideoProcAmp
    {
        [PreserveSig]
        int GetRange(int property, out int min, out int max, out int step, out int defaultValue, out int flags);
        [PreserveSig]
        int Set(int property, int value, int flags);
        [PreserveSig]
        int Get(int property, out int value, out int flags);
    }

    [ComImport, Guid("C6E13370-30AC-11D0-A18C-00A0C9118956"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAMCameraControl
    {
        [PreserveSig]
        int GetRange(int property, out int min, out int max, out int step, out int defaultValue, out int flags);
        [PreserveSig]
        int Set(int property, int value, int flags);
        [PreserveSig]
        int Get(int property, out int value, out int flags);
    }

    public sealed class CameraInfo
    {
        public int Index { get; set; }
        public string Name { get; set; }
        public string DevicePath { get; set; }
    }

    public sealed class PropertyInfo
    {
        public string Name { get; set; }
        public string Family { get; set; }
        public int Current { get; set; }
        public string DisplayValue { get; set; }
        public string Mode { get; set; }
        public Nullable<int> Minimum { get; set; }
        public Nullable<int> Maximum { get; set; }
        public Nullable<int> Step { get; set; }
        public Nullable<int> Default { get; set; }
        public bool AutoSupported { get; set; }
        public bool ManualSupported { get; set; }
    }

    internal sealed class CameraHandle
    {
        public int Index;
        public string Name;
        public string DevicePath;
        public object Filter;
    }

    internal sealed class Descriptor
    {
        public string Name;
        public bool CameraControl;
        public int Id;
        public Descriptor(string name, bool cameraControl, int id)
        { Name = name; CameraControl = cameraControl; Id = id; }
    }

    public static class CameraManager
    {
        private const int SFalse = 1;
        private const int FlagAuto = 1;
        private const int FlagManual = 2;
        private static readonly Guid SystemDeviceEnum = new Guid("62BE5D10-60EB-11D0-BD3B-00A0C911CE86");
        private static readonly Guid VideoInputCategory = new Guid("860BB310-5D01-11D0-BD3B-00A0C911CE86");
        private static readonly Guid IUnknownId = new Guid("00000000-0000-0000-C000-000000000046");

        private static readonly Descriptor[] Properties = new Descriptor[] {
            new Descriptor("Brightness", false, 0),
            new Descriptor("Contrast", false, 1),
            new Descriptor("Hue", false, 2),
            new Descriptor("Saturation", false, 3),
            new Descriptor("Sharpness", false, 4),
            new Descriptor("Gamma", false, 5),
            new Descriptor("ColorEnable", false, 6),
            new Descriptor("WhiteBalance", false, 7),
            new Descriptor("BacklightCompensation", false, 8),
            new Descriptor("Gain", false, 9),
            new Descriptor("DigitalMultiplier", false, 10),
            new Descriptor("DigitalMultiplierLimit", false, 11),
            new Descriptor("WhiteBalanceComponent", false, 12),
            new Descriptor("PowerlineFrequency", false, 13),
            new Descriptor("Pan", true, 0),
            new Descriptor("Tilt", true, 1),
            new Descriptor("Roll", true, 2),
            new Descriptor("Zoom", true, 3),
            new Descriptor("Exposure", true, 4),
            new Descriptor("Iris", true, 5),
            new Descriptor("Focus", true, 6)
        };

        public static CameraInfo[] List()
        {
            List<CameraInfo> output = new List<CameraInfo>();
            foreach (CameraHandle camera in Enumerate())
                output.Add(new CameraInfo { Index = camera.Index, Name = camera.Name, DevicePath = camera.DevicePath });
            return output.ToArray();
        }

        public static PropertyInfo[] Get(int cameraIndex)
        {
            CameraHandle camera = Select(Enumerate(), cameraIndex);
            List<PropertyInfo> output = new List<PropertyInfo>();
            foreach (Descriptor property in Properties)
            {
                PropertyInfo value;
                if (TryGet(camera, property, out value)) output.Add(value);
            }
            return output.ToArray();
        }

        public static void Set(int cameraIndex, string propertyName, string input)
        {
            CameraHandle camera = Select(Enumerate(), cameraIndex);
            Descriptor property = Find(propertyName);
            int value = ParseValue(property.Name, input);
            int flags = String.Equals(input, "Auto", StringComparison.OrdinalIgnoreCase) ? FlagAuto : FlagManual;
            int hr;

            if (property.CameraControl)
            {
                IAMCameraControl control = camera.Filter as IAMCameraControl;
                if (control == null) throw new InvalidOperationException("The camera does not expose IAMCameraControl.");
                hr = control.Set(property.Id, value, flags);
            }
            else
            {
                IAMVideoProcAmp control = camera.Filter as IAMVideoProcAmp;
                if (control == null) throw new InvalidOperationException("The camera does not expose IAMVideoProcAmp.");
                hr = control.Set(property.Id, value, flags);
            }
            if (hr < 0) Marshal.ThrowExceptionForHR(hr, new IntPtr(-1));
        }

        private static List<CameraHandle> Enumerate()
        {
            List<CameraHandle> output = new List<CameraHandle>();
            object deviceEnumeratorObject = Activator.CreateInstance(Type.GetTypeFromCLSID(SystemDeviceEnum, true));
            ICreateDevEnum deviceEnumerator = (ICreateDevEnum)deviceEnumeratorObject;
            IEnumMoniker enumerator;
            Guid category = VideoInputCategory;
            int hr = deviceEnumerator.CreateClassEnumerator(ref category, out enumerator, 0);
            if (hr == SFalse || enumerator == null) return output;
            if (hr < 0) Marshal.ThrowExceptionForHR(hr, new IntPtr(-1));

            IMoniker[] item = new IMoniker[1];
            int index = 0;
            while (enumerator.Next(1, item, IntPtr.Zero) == 0)
            {
                IMoniker moniker = item[0];
                object filter;
                Guid iid = IUnknownId;
                moniker.BindToObject(null, null, ref iid, out filter);
                output.Add(new CameraHandle {
                    Index = index++,
                    Name = ReadBag(moniker, "FriendlyName") ?? "Camera",
                    DevicePath = ReadBag(moniker, "DevicePath"),
                    Filter = filter
                });
                item[0] = null;
            }
            return output;
        }

        private static string ReadBag(IMoniker moniker, string name)
        {
            try
            {
                object bagObject;
                Guid iid = typeof(IPropertyBag).GUID;
                moniker.BindToStorage(null, null, ref iid, out bagObject);
                IPropertyBag bag = (IPropertyBag)bagObject;
                object value;
                int hr = bag.Read(name, out value, IntPtr.Zero);
                return hr >= 0 && value != null ? value.ToString() : null;
            }
            catch { return null; }
        }

        private static CameraHandle Select(List<CameraHandle> cameras, int index)
        {
            foreach (CameraHandle camera in cameras) if (camera.Index == index) return camera;
            throw new ArgumentOutOfRangeException("index", "Camera index " + index + " was not found.");
        }

        private static Descriptor Find(string name)
        {
            foreach (Descriptor value in Properties)
                if (String.Equals(value.Name, name, StringComparison.OrdinalIgnoreCase)) return value;
            throw new ArgumentException("Unknown property: " + name);
        }

        private static bool TryGet(CameraHandle camera, Descriptor property, out PropertyInfo info)
        {
            info = null;
            int current, currentFlags, min, max, step, defaultValue, caps;
            int hrGet, hrRange;
            if (property.CameraControl)
            {
                IAMCameraControl control = camera.Filter as IAMCameraControl;
                if (control == null) return false;
                hrGet = control.Get(property.Id, out current, out currentFlags);
                if (hrGet < 0) return false;
                hrRange = control.GetRange(property.Id, out min, out max, out step, out defaultValue, out caps);
            }
            else
            {
                IAMVideoProcAmp control = camera.Filter as IAMVideoProcAmp;
                if (control == null) return false;
                hrGet = control.Get(property.Id, out current, out currentFlags);
                if (hrGet < 0) return false;
                hrRange = control.GetRange(property.Id, out min, out max, out step, out defaultValue, out caps);
            }

            info = new PropertyInfo {
                Name = property.Name,
                Family = property.CameraControl ? "CameraControl" : "VideoProcAmp",
                Current = current,
                DisplayValue = FormatValue(property.Name, current),
                Mode = (currentFlags & FlagAuto) != 0 ? "Auto" : "Manual",
                Minimum = hrRange >= 0 ? (Nullable<int>)min : null,
                Maximum = hrRange >= 0 ? (Nullable<int>)max : null,
                Step = hrRange >= 0 ? (Nullable<int>)step : null,
                Default = hrRange >= 0 ? (Nullable<int>)defaultValue : null,
                AutoSupported = hrRange >= 0 && (caps & FlagAuto) != 0,
                ManualSupported = hrRange < 0 || (caps & FlagManual) != 0
            };
            return true;
        }

        private static int ParseValue(string property, string input)
        {
            if (property == "PowerlineFrequency")
            {
                if (String.Equals(input, "Disabled", StringComparison.OrdinalIgnoreCase)) return 0;
                if (String.Equals(input, "50Hz", StringComparison.OrdinalIgnoreCase)) return 1;
                if (String.Equals(input, "60Hz", StringComparison.OrdinalIgnoreCase)) return 2;
                if (String.Equals(input, "Auto", StringComparison.OrdinalIgnoreCase)) return 3;
            }
            if (property == "ColorEnable" || property == "BacklightCompensation")
            {
                if (String.Equals(input, "Off", StringComparison.OrdinalIgnoreCase)) return 0;
                if (String.Equals(input, "On", StringComparison.OrdinalIgnoreCase)) return 1;
            }
            int value;
            if (Int32.TryParse(input, out value)) return value;
            throw new ArgumentException("Invalid value '" + input + "' for " + property + ".");
        }

        private static string FormatValue(string property, int value)
        {
            if (property == "PowerlineFrequency")
            {
                if (value == 0) return "Disabled";
                if (value == 1) return "50Hz";
                if (value == 2) return "60Hz";
                if (value == 3) return "Auto";
            }
            if (property == "ColorEnable" || property == "BacklightCompensation")
                return value == 0 ? "Off" : value == 1 ? "On" : value.ToString();
            return value.ToString();
        }
    }
}
'@

if (-not ('WinCamCfg.PowerShell.CameraManager' -as [type])) {
    Add-Type -TypeDefinition $source -Language CSharp
}

function Get-Options {
    param([string[]]$InputArguments)
    if ($InputArguments.Count -eq 0) { return @{ Command = 'help' } }
    $o = @{ Command = $InputArguments[0].ToLowerInvariant(); Camera = '0'; Property = $null; Value = $null; Output = 'text' }
    for ($i = 1; $i -lt $InputArguments.Count; $i++) {
        switch ($InputArguments[$i]) {
            '--camera' { $i++; $o.Camera = $InputArguments[$i] }
            '--property' { $i++; $o.Property = $InputArguments[$i] }
            '--value' { $i++; $o.Value = $InputArguments[$i] }
            '--output' { $i++; $o.Output = $InputArguments[$i].ToLowerInvariant() }
            default { throw "Unknown argument: $($InputArguments[$i])" }
        }
    }
    return $o
}

function Get-Indexes([string]$Selector) {
    $cameras = @([WinCamCfg.PowerShell.CameraManager]::List())
    if ($Selector -ieq 'all') { return @($cameras.Index) }
    $index = 0
    if (-not [int]::TryParse($Selector, [ref]$index)) { throw "Invalid camera selector: $Selector" }
    if ($index -notin @($cameras.Index)) { throw "Camera index $index was not found." }
    return @($index)
}

try {
    $o = Get-Options $args
    switch ($o.Command) {
        'version' { 'wincamcfg-powershell 1.1.3' }
        'list' {
            $items = @([WinCamCfg.PowerShell.CameraManager]::List())
            if ($o.Output -eq 'json') { $items | ConvertTo-Json -Depth 5 }
            else { $items | ForEach-Object { '[{0}] {1}' -f $_.Index, $_.Name } }
        }
        'get' {
            $results = foreach ($index in (Get-Indexes $o.Camera)) {
                $camera = [WinCamCfg.PowerShell.CameraManager]::List() | Where-Object Index -eq $index
                [pscustomobject]@{ index=$index; name=$camera.Name; devicePath=$camera.DevicePath; properties=@([WinCamCfg.PowerShell.CameraManager]::Get($index)) }
            }
            if ($o.Output -eq 'json') { @($results) | ConvertTo-Json -Depth 8 }
            else {
                foreach ($r in @($results)) {
                    "[$($r.index)] $($r.name)"
                    foreach ($p in $r.properties) { '  {0}: {1} [{2}]' -f $p.Name,$p.DisplayValue,$p.Mode }
                }
            }
        }
        'set' {
            if (-not $o.Property) { throw 'Specify --property.' }
            if ($null -eq $o.Value) { throw 'Specify --value.' }
            $changed = 0; $skipped = 0
            foreach ($index in (Get-Indexes $o.Camera)) {
                try {
                    [WinCamCfg.PowerShell.CameraManager]::Set($index,$o.Property,$o.Value)
                    "Set $($o.Property) to $($o.Value) on camera $index."
                    $changed++
                } catch {
                    if ($o.Camera -ine 'all') { throw }
                    $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
                    Write-Warning "Skipped camera $index. $message"
                    $skipped++
                }
            }
            if ($o.Camera -ieq 'all') {
                "Result: changed=$changed; skipped=$skipped"
                if ($changed -eq 0) { throw "No camera accepted $($o.Property)." }
            }
        }
        default {
            @'
Usage:
  .\wincamcfg.ps1 list [--output text|json]
  .\wincamcfg.ps1 get --camera <index|all> [--output text|json]
  .\wincamcfg.ps1 set --camera <index|all> --property <name> --value <value>
  .\wincamcfg.ps1 version
'@
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
