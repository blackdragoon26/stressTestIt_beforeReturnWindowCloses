# Sequential drive speed with the Windows file cache bypassed (FILE_FLAG_NO_BUFFERING), so the numbers
# are the drive's and not memory's. Writes a test file of random data, reads it back, checks every byte,
# and deletes it. Used for the internal SSD (full audit) and for USB sticks (-Interactive port test).

function Measure-DriveSpeed([string]$Folder, [int]$SizeMB = 1024) {
    if (-not ('DiskSpeed' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class DiskSpeed {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(SafeFileHandle h, IntPtr buf, uint count, out uint done, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint count, out uint done, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool FlushFileBuffers(SafeFileHandle h);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr VirtualAlloc(IntPtr addr, UIntPtr size, uint type, uint protect);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool VirtualFree(IntPtr addr, UIntPtr size, uint type);

    const uint NO_BUFFERING = 0x20000000, SEQUENTIAL = 0x08000000;

    static void Stamp(byte[] b, int i) { BitConverter.GetBytes((long)i).CopyTo(b, 0); }

    // Returns { write MB/s, read MB/s, chunks that read back wrong }
    public static double[] Run(string path, int chunkMB, int chunks) {
        int chunk = chunkMB * 1024 * 1024;
        byte[] pattern = new byte[chunk];
        new Random(20261122).NextBytes(pattern);   // random data: drives cannot compress it
        byte[] back = new byte[chunk];
        // Unbuffered I/O needs a sector-aligned buffer: VirtualAlloc gives a page-aligned one
        IntPtr buf = VirtualAlloc(IntPtr.Zero, (UIntPtr)(uint)chunk, 0x3000, 0x04);
        if (buf == IntPtr.Zero) throw new Exception("could not allocate the I/O buffer");
        double writeTicks = 0, readTicks = 0;
        int bad = 0;
        uint done;
        Stopwatch sw = new Stopwatch();
        try {
            using (SafeFileHandle h = CreateFile(path, 0x40000000, 0, IntPtr.Zero, 2, NO_BUFFERING, IntPtr.Zero)) {
                if (h.IsInvalid) throw new Exception("cannot create the test file (error " + Marshal.GetLastWin32Error() + ")");
                for (int i = 0; i < chunks; i++) {
                    Stamp(pattern, i);
                    Marshal.Copy(pattern, 0, buf, chunk);
                    sw.Restart();
                    if (!WriteFile(h, buf, (uint)chunk, out done, IntPtr.Zero) || done != chunk) throw new Exception("write failed (error " + Marshal.GetLastWin32Error() + ")");
                    sw.Stop(); writeTicks += sw.ElapsedTicks;
                }
                sw.Restart(); FlushFileBuffers(h); sw.Stop(); writeTicks += sw.ElapsedTicks;
            }
            using (SafeFileHandle h = CreateFile(path, 0x80000000, 1, IntPtr.Zero, 3, NO_BUFFERING | SEQUENTIAL, IntPtr.Zero)) {
                if (h.IsInvalid) throw new Exception("cannot open the test file (error " + Marshal.GetLastWin32Error() + ")");
                for (int i = 0; i < chunks; i++) {
                    sw.Restart();
                    if (!ReadFile(h, buf, (uint)chunk, out done, IntPtr.Zero) || done != chunk) throw new Exception("read failed (error " + Marshal.GetLastWin32Error() + ")");
                    sw.Stop(); readTicks += sw.ElapsedTicks;
                    Marshal.Copy(buf, back, 0, chunk);
                    Stamp(pattern, i);
                    for (int j = 0; j < chunk; j++) { if (back[j] != pattern[j]) { bad++; break; } }
                }
            }
        } finally {
            VirtualFree(buf, UIntPtr.Zero, 0x8000);
            try { File.Delete(path); } catch { }
        }
        double mb = (double)chunk * chunks / 1048576.0;
        double f = Stopwatch.Frequency;
        return new double[] { mb / Math.Max(writeTicks / f, 1e-6), mb / Math.Max(readTicks / f, 1e-6), bad };
    }
}
'@
    }
    $path = Join-Path $Folder 'secondtrust_speedtest.tmp'
    try {
        $r = [DiskSpeed]::Run($path, 4, [int][math]::Max(1, $SizeMB / 4))
        return [pscustomobject]@{ SizeMB = $SizeMB; WriteMBs = [math]::Round($r[0]); ReadMBs = [math]::Round($r[1]); BadChunks = [int]$r[2]; Error = $null }
    } catch {
        $e = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        return [pscustomobject]@{ SizeMB = $SizeMB; WriteMBs = $null; ReadMBs = $null; BadChunks = $null; Error = $e }
    } finally {
        Remove-Item $path -Force -ErrorAction SilentlyContinue
    }
}
