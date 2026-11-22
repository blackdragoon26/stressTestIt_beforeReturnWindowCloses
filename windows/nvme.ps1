# The NVMe SMART / health log (log page 2), read straight from the drive with the Windows storage
# IOCTL, as smartmontools does. Windows' own counters can leave power-on hours blank (seen on the
# ASUS's Kingston drive, which Linux reads as 19,276 h and 72.1 TB written). Needs admin.

function Get-NvmeHealth([int]$Drive) {
    try {
        if (-not ('NvmeHealthLog' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class NvmeHealthLog {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle device, uint code, byte[] inBuffer, int inSize, byte[] outBuffer, int outSize, out int returned, IntPtr overlapped);
    public static byte[] Read(int drive) {
        using (SafeFileHandle h = CreateFile(@"\\.\PhysicalDrive" + drive, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero)) {
            if (h.IsInvalid) return null;
            byte[] buf = new byte[8 + 40 + 512];
            BitConverter.GetBytes(50).CopyTo(buf, 0);   // StorageDeviceProtocolSpecificProperty
            BitConverter.GetBytes(0).CopyTo(buf, 4);    // PropertyStandardQuery
            BitConverter.GetBytes(3).CopyTo(buf, 8);    // ProtocolTypeNvme
            BitConverter.GetBytes(2).CopyTo(buf, 12);   // NVMeDataTypeLogPage
            BitConverter.GetBytes(2).CopyTo(buf, 16);   // log page 2: SMART / health information
            BitConverter.GetBytes(40).CopyTo(buf, 24);  // ProtocolDataOffset
            BitConverter.GetBytes(512).CopyTo(buf, 28); // ProtocolDataLength
            int returned;
            if (!DeviceIoControl(h, 0x002D1400, buf, buf.Length, buf, buf.Length, out returned, IntPtr.Zero)) return null;
            int offset = BitConverter.ToInt32(buf, 24);
            int length = BitConverter.ToInt32(buf, 28);
            if (length < 192 || 8 + offset + 512 > buf.Length) return null;
            byte[] log = new byte[512];
            Array.Copy(buf, 8 + offset, log, 0, 512);
            return log;
        }
    }
}
'@
        }
        $log = [NvmeHealthLog]::Read($Drive)
        if (-not $log) { return $null }
        # Data units are 1000 x 512 bytes
        return [ordered]@{
            CriticalWarning   = $log[0]
            TemperatureC      = [BitConverter]::ToUInt16($log, 1) - 273
            AvailableSparePct = $log[3]
            PercentUsed       = $log[5]
            DataReadTB        = [math]::Round([BitConverter]::ToUInt64($log, 32) * 512000 / 1e12, 2)
            DataWrittenTB     = [math]::Round([BitConverter]::ToUInt64($log, 48) * 512000 / 1e12, 2)
            PowerCycles       = [BitConverter]::ToUInt64($log, 112)
            PowerOnHours      = [BitConverter]::ToUInt64($log, 128)
            UnsafeShutdowns   = [BitConverter]::ToUInt64($log, 144)
            MediaErrors       = [BitConverter]::ToUInt64($log, 160)
            ErrorLogEntries   = [BitConverter]::ToUInt64($log, 176)
        }
    } catch { return $null }
}
