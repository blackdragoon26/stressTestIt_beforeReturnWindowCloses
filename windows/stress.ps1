# Verified load (-Stress): full load on every CPU thread and a large share of RAM, where every result is
# checked. Same idea as gpu-burn (github.com/wilicc/gpu-burn), which repeats one big calculation and
# compares every answer with the first: a machine that survives the load but computes a wrong answer is
# still faulty. Plain load (a busy loop, most "stress" videos) cannot see that.
#
# CPU: each thread repeats a 96 x 96 floating point matrix multiply and a SHA-256 of a 256 KB block,
#      both with fixed inputs, and compares the result with the reference worked out before the test.
# RAM: one thread fills blocks of memory with a pattern that changes every pass, then reads every word
#      back and compares it.
# The threads run below normal priority so the sensor log keeps its timing. Nothing is written to disk.

function Start-VerifiedLoad([int]$MemoryPct = 50) {
    if (-not ('StressEngine' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Security.Cryptography;
using System.Threading;
public static class StressEngine {
    static volatile bool stop;
    static Thread[] threads = new Thread[0];
    static long[][] blocks = new long[0][];
    static ulong reference;
    static long cpuRounds, cpuErrors, memPasses, memErrors, firstErrorTicks;
    public static string FirstError = "";
    public static long MemoryBytes;
    public static int CpuThreads;
    public static long CpuRounds { get { return Interlocked.Read(ref cpuRounds); } }
    public static long CpuErrors { get { return Interlocked.Read(ref cpuErrors); } }
    public static long MemPasses { get { return Interlocked.Read(ref memPasses); } }
    public static long MemErrors { get { return Interlocked.Read(ref memErrors); } }
    public static DateTime FirstErrorTime { get { long t = Interlocked.Read(ref firstErrorTicks); return t == 0 ? DateTime.MinValue : new DateTime(t, DateTimeKind.Utc).ToLocalTime(); } }

    const int N = 96;
    sealed class Work {
        public double[] a = new double[N * N], b = new double[N * N], c = new double[N * N];
        public byte[] data = new byte[256 * 1024];
        public SHA256 sha = SHA256.Create();
        public Work() {
            ulong s = 88172645463325252UL;
            for (int i = 0; i < N * N; i++) {
                s ^= s << 13; s ^= s >> 7; s ^= s << 17; a[i] = (s % 1000000) / 100000.0;
                s ^= s << 13; s ^= s >> 7; s ^= s << 17; b[i] = (s % 1000000) / 100000.0;
            }
            for (int i = 0; i < data.Length; i++) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; data[i] = (byte)s; }
        }
        public ulong Round() {
            Array.Clear(c, 0, c.Length);
            for (int i = 0; i < N; i++)
                for (int k = 0; k < N; k++) {
                    double aik = a[i * N + k];
                    int row = i * N, col = k * N;
                    for (int j = 0; j < N; j++) c[row + j] += aik * b[col + j];
                }
            ulong h = 1469598103934665603UL;
            for (int i = 0; i < c.Length; i++) { h ^= (ulong)BitConverter.DoubleToInt64Bits(c[i]); h *= 1099511628211UL; }
            byte[] d = sha.ComputeHash(data);
            for (int i = 0; i < d.Length; i++) { h ^= d[i]; h *= 1099511628211UL; }
            return h;
        }
    }

    static void Fault(string what) {
        if (Interlocked.CompareExchange(ref firstErrorTicks, DateTime.UtcNow.Ticks, 0) == 0) FirstError = what;
    }

    static void CpuWorker() {
        try {
            Work w = new Work();
            while (!stop) {
                if (w.Round() != reference) { Interlocked.Increment(ref cpuErrors); Fault("CPU: a calculation gave a different answer"); }
                Interlocked.Increment(ref cpuRounds);
            }
        } catch (Exception e) { Interlocked.Increment(ref cpuErrors); Fault("CPU thread stopped: " + e.Message); }
    }

    static ulong Mix(ulong z) {
        z += 0x9E3779B97F4A7C15UL;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }

    static void MemWorker() {
        try {
            for (ulong pass = 1; !stop; pass++) {
                ulong seed = Mix(pass);
                for (int bi = 0; bi < blocks.Length && !stop; bi++) {
                    long[] blk = blocks[bi];
                    ulong bs = seed ^ ((ulong)bi << 40);
                    for (int i = 0; i < blk.Length; i++) blk[i] = (long)Mix(bs ^ (ulong)i);
                }
                // read back in reverse order, so the check does not just hit the cache of the last writes
                for (int bi = blocks.Length - 1; bi >= 0 && !stop; bi--) {
                    long[] blk = blocks[bi];
                    ulong bs = seed ^ ((ulong)bi << 40);
                    for (int i = 0; i < blk.Length; i++) {
                        if (blk[i] != (long)Mix(bs ^ (ulong)i)) {
                            Interlocked.Increment(ref memErrors);
                            Fault("RAM: block " + bi + " word " + i + " read back wrong on pass " + pass);
                        }
                    }
                }
                if (!stop) Interlocked.Increment(ref memPasses);
            }
        } catch (Exception e) { Interlocked.Increment(ref memErrors); Fault("RAM thread stopped: " + e.Message); }
    }

    public static void Start(int cpuThreads, long memoryBytes) {
        Stop();
        stop = false;
        cpuRounds = cpuErrors = memPasses = memErrors = firstErrorTicks = 0;
        FirstError = "";
        reference = new Work().Round();
        // Memory in blocks of 64 MB; stop allocating if Windows says no
        const int words = 8 * 1024 * 1024;
        var list = new System.Collections.Generic.List<long[]>();
        try { for (long got = 0; got + words * 8L <= memoryBytes; got += words * 8L) list.Add(new long[words]); }
        catch (OutOfMemoryException) { }
        blocks = list.ToArray();
        MemoryBytes = (long)blocks.Length * words * 8L;
        CpuThreads = cpuThreads;
        var t = new System.Collections.Generic.List<Thread>();
        for (int i = 0; i < cpuThreads; i++) t.Add(new Thread(CpuWorker));
        if (blocks.Length > 0) t.Add(new Thread(MemWorker));
        threads = t.ToArray();
        foreach (Thread th in threads) { th.IsBackground = true; th.Priority = ThreadPriority.BelowNormal; th.Start(); }
    }

    public static void Stop() {
        stop = true;
        foreach (Thread th in threads) th.Join(10000);
        threads = new Thread[0];
        blocks = new long[0][];
        GC.Collect();
    }
}
'@
    }
    $os = Get-CimInstance Win32_OperatingSystem
    $freeBytes = [int64]$os.FreePhysicalMemory * 1KB
    # Leave at least 2 GB free for Windows and the monitor
    $memBytes = [int64][math]::Max(0, [math]::Min($freeBytes * $MemoryPct / 100, $freeBytes - 2GB))
    $threads = [Environment]::ProcessorCount
    [StressEngine]::Start($threads, $memBytes)
    Write-Host ("Verified load running: {0} CPU threads, {1:N1} GB of RAM under test" -f [StressEngine]::CpuThreads, ([StressEngine]::MemoryBytes / 1GB))
}

function Get-VerifiedLoadStatus {
    return [pscustomobject]@{
        CpuRounds = [StressEngine]::CpuRounds; CpuErrors = [StressEngine]::CpuErrors
        MemPasses = [StressEngine]::MemPasses; MemErrors = [StressEngine]::MemErrors
    }
}

function Stop-VerifiedLoad {
    $s = Get-VerifiedLoadStatus
    [StressEngine]::Stop()
    $first = [StressEngine]::FirstErrorTime
    $when = if ($first -ne [datetime]::MinValue) { " First at $($first.ToString('HH:mm:ss')): $([StressEngine]::FirstError)" } else { '' }

    if ($s.CpuRounds -eq 0) { Add-Result 'WARN' 'Verified CPU load' 'no rounds completed: the load did not run' }
    elseif ($s.CpuErrors -gt 0) { Add-Result 'FAIL' 'Verified CPU load' "$($s.CpuErrors) wrong results in $($s.CpuRounds) rounds on $([StressEngine]::CpuThreads) threads.$when The CPU gave wrong answers under load: a CPU, cooling or power fault" }
    else { Add-Result 'PASS' 'Verified CPU load' "$($s.CpuRounds) rounds on $([StressEngine]::CpuThreads) threads, every result correct" }

    $gb = [math]::Round([StressEngine]::MemoryBytes / 1GB, 1)
    if ([StressEngine]::MemoryBytes -eq 0) { Add-Result 'WARN' 'Verified memory load' 'no memory could be set aside for the test' }
    elseif ($s.MemErrors -gt 0) { Add-Result 'FAIL' 'Verified memory load' "$($s.MemErrors) wrong words in $gb GB over $($s.MemPasses) passes.$when Faulty RAM: confirm with MemTest86+ from USB" }
    elseif ($s.MemPasses -eq 0) { Add-Result 'WARN' 'Verified memory load' "$gb GB under test, but no full pass finished. Run longer" }
    else { Add-Result 'PASS' 'Verified memory load' "$gb GB written and read back $($s.MemPasses) times, no errors. Windows' own use of the other RAM is not covered: MemTest86+ tests all of it" }
}
