# Hands-on tests (-Interactive): the faults only a person can see or hear, each recorded in the report.
# Screen colours, every key and the touchpad, speakers left and right, microphone, webcam, every USB port
# (with a real read and write speed test), and the other ports. Windows Forms and the built-in sound and
# MCI recording APIs only: nothing is installed.

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('HandsOn' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class HandsOn {
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int mciSendString(string cmd, StringBuilder ret, int len, IntPtr callback);
    public static int Mci(string cmd) { StringBuilder sb = new StringBuilder(256); return mciSendString(cmd, sb, sb.Capacity, IntPtr.Zero); }
    public static bool IsDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

    // A 16-bit stereo WAV: a tone, or a sweep from f0 to f1, with a volume per channel
    public static byte[] Tone(double f0, double f1, double seconds, double left, double right) {
        int rate = 44100, n = (int)(rate * seconds);
        MemoryStream ms = new MemoryStream();
        BinaryWriter w = new BinaryWriter(ms);
        w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + n * 4); w.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
        w.Write(16); w.Write((short)1); w.Write((short)2); w.Write(rate); w.Write(rate * 4); w.Write((short)4); w.Write((short)16);
        w.Write(Encoding.ASCII.GetBytes("data")); w.Write(n * 4);
        double phase = 0;
        for (int i = 0; i < n; i++) {
            double f = f0 * Math.Pow(f1 / f0, (double)i / n);
            phase += 2 * Math.PI * f / rate;
            double fade = Math.Min(1.0, Math.Min(i, n - i) / (rate * 0.02));   // 20 ms fade: no clicks
            double s = Math.Sin(phase) * 0.6 * fade;
            w.Write((short)(s * left * 32767)); w.Write((short)(s * right * 32767));
        }
        w.Flush();
        return ms.ToArray();
    }

    // Loudest sample of a PCM WAV file, from 0 to 1 (-1 if the file has no audio)
    public static double Peak(string path) {
        byte[] b = File.ReadAllBytes(path);
        int i = 12, start = -1, len = 0, bits = 16;
        while (i + 8 <= b.Length) {
            string id = Encoding.ASCII.GetString(b, i, 4);
            int size = BitConverter.ToInt32(b, i + 4);
            if (id == "fmt ") bits = BitConverter.ToInt16(b, i + 22);
            if (id == "data") { start = i + 8; len = Math.Min(size, b.Length - start); break; }
            i += 8 + size + (size & 1);
        }
        if (start < 0 || len <= 0) return -1;
        double peak = 0;
        if (bits == 16) { for (int j = start; j + 1 < start + len; j += 2) { double v = Math.Abs((int)BitConverter.ToInt16(b, j)) / 32768.0; if (v > peak) peak = v; } }
        else { for (int j = start; j < start + len; j++) { double v = Math.Abs(b[j] - 128) / 128.0; if (v > peak) peak = v; } }
        return peak;
    }
}
'@
}

function Read-Choice([string]$Question, [string[]]$Allowed) {
    while ($true) {
        $a = "$(Read-Host "$Question [$($Allowed -join '/')]")".Trim().ToLower()
        if ($Allowed -contains $a) { return $a }
    }
}

function Invoke-Sound([byte[]]$Wav) {
    $sp = New-Object Media.SoundPlayer (New-Object IO.MemoryStream (, $Wav))
    $sp.PlaySync()
}

# ---------- screen ----------
function Test-Screen {
    Write-Host 'Full-screen colours follow. Look closely at the whole screen for each one. Any key or click: next colour. Esc: stop.'
    $steps = @(
        @{ C = [Drawing.Color]::Black; T = 'Black: look for lit dots (stuck pixels) and light leaking at the edges' }
        @{ C = [Drawing.Color]::White; T = 'White: look for dark dots (dead pixels), dust under the glass, dim or yellow patches' }
        @{ C = [Drawing.Color]::FromArgb(255, 0, 0); T = 'Red: look for any dot that is not red' }
        @{ C = [Drawing.Color]::FromArgb(0, 255, 0); T = 'Green: look for any dot that is not green' }
        @{ C = [Drawing.Color]::FromArgb(0, 0, 255); T = 'Blue: look for any dot that is not blue' }
        @{ C = [Drawing.Color]::FromArgb(128, 128, 128); T = 'Grey: look for patches, bands or blotches (uneven backlight, pressure marks)' }
    )
    $form = New-Object Windows.Forms.Form
    $form.FormBorderStyle = 'None'; $form.WindowState = 'Maximized'; $form.TopMost = $true; $form.KeyPreview = $true
    $lbl = New-Object Windows.Forms.Label
    $lbl.Dock = 'Bottom'; $lbl.Height = 40; $lbl.TextAlign = 'MiddleCenter'; $lbl.Font = New-Object Drawing.Font('Segoe UI', 13)
    $form.Controls.Add($lbl)
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 3500
    $st = @{ i = 0; stopped = $false }
    $show = {
        $s = $steps[$st.i]
        $form.BackColor = $s.C; $lbl.BackColor = $s.C
        $lbl.ForeColor = if ($s.C.GetBrightness() -gt 0.45) { [Drawing.Color]::Black } else { [Drawing.Color]::White }
        $lbl.Text = "$($st.i + 1) of $($steps.Count). $($s.T). Any key: next. Esc: stop."
        $lbl.Visible = $true; $timer.Stop(); $timer.Start()
    }
    $next = { $st.i++; if ($st.i -ge $steps.Count) { $form.Close() } else { & $show } }
    $timer.Add_Tick({ $lbl.Visible = $false; $timer.Stop() })   # the hint hides itself so it covers nothing
    $form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $st.stopped = $true; $form.Close() } else { & $next } })
    $form.Add_MouseClick({ & $next })
    $lbl.Add_MouseClick({ & $next })
    $form.Add_Shown({ [Windows.Forms.Cursor]::Hide(); & $show })
    [void]$form.ShowDialog()
    [Windows.Forms.Cursor]::Show(); $timer.Dispose(); $form.Dispose()
    if ($st.stopped) { Add-Result 'INFO' 'Screen: pixels' "stopped at colour $($st.i + 1) of $($steps.Count)"; return }
    if (Read-YesNo 'Did you see any dot of the wrong colour (a dead or stuck pixel)?') {
        Add-Result 'FAIL' 'Screen: pixels' 'dead or stuck pixel seen. Photograph it on the colour where it shows best, today'
    } else { Add-Result 'PASS' 'Screen: pixels' 'no dead or stuck pixel seen on 6 colours' }
    if (Read-YesNo 'Did you see light leaking at the edges, or patches, bands or blotches?') {
        Add-Result 'WARN' 'Screen: backlight' 'uneven light seen. A soft halo around bright objects on a black screen is normal for mini-LED; patches or bands on grey are not. Photograph it in a dark room'
    } else { Add-Result 'PASS' 'Screen: backlight' 'even on black, white and grey' }
}

# ---------- keyboard and touchpad ----------
function Test-Keyboard {
    # "Label|virtual key code|width" (an underscore in a label shows as a space). The first six rows are the main keyboard and must all register.
    $main = @(
        'Esc|27 F1|112 F2|113 F3|114 F4|115 F5|116 F6|117 F7|118 F8|119 F9|120 F10|121 F11|122 F12|123 Del|46'
        '`|192 1|49 2|50 3|51 4|52 5|53 6|54 7|55 8|56 9|57 0|48 -|189 =|187 Back|8|2'
        'Tab|9|1.5 Q|81 W|87 E|69 R|82 T|84 Y|89 U|85 I|73 O|79 P|80 [|219 ]|221 \|220|1.5'
        'Caps|20|1.75 A|65 S|83 D|68 F|70 G|71 H|72 J|74 K|75 L|76 ;|186 ''|222 Enter|13|2.25'
        'Shift|160|2.25 Z|90 X|88 C|67 V|86 B|66 N|78 M|77 ,|188 .|190 /|191 Shift|161|2.75'
        'Ctrl|162|1.25 Win|91|1.25 Alt|164|1.25 Space|32|5 Alt|165|1.25 Ctrl|163|1.25 Left|37 Up|38 Down|40 Right|39'
    )
    $extra = @(
        'Ins|45 Home|36 End|35 PgUp|33 PgDn|34 PrtSc|44 Menu|93 Pause|19 NumLk|144 ISO\|226'
        'Num0|96 Num1|97 Num2|98 Num3|99 Num4|100 Num5|101 Num6|102 Num7|103 Num8|104 Num9|105 Num*|106 Num+|107 Num-|109 Num.|110 Num/|111'
    )
    $u = 52
    $form = New-Object Windows.Forms.Form
    $form.Text = 'SecondTrust: keyboard and touchpad'
    $form.StartPosition = 'CenterScreen'; $form.KeyPreview = $true; $form.TopMost = $true
    $form.BackColor = [Drawing.Color]::White
    $form.Font = New-Object Drawing.Font('Segoe UI', 10)
    $form.ClientSize = New-Object Drawing.Size((17 * $u + 32), (11 * $u + 40))
    $st = @{ Labels = @{}; Names = @{}; Required = New-Object System.Collections.Generic.List[int]; Pressed = @{}; Down = @{}; LastUp = @{}; Chatter = @{}; Other = @{} }

    $head = New-Object Windows.Forms.Label
    $head.Location = New-Object Drawing.Point(16, 8); $head.Size = New-Object Drawing.Size((17 * $u), 44)
    $head.Text = "Press every key once; each turns black when it registers. If F1 to F12 change volume or brightness instead, hold Fn. The Windows key opens Start: press Esc, then click back here. Then click, right-click and scroll on the touchpad."
    $form.Controls.Add($head)

    $pointerMark = {
        param([string]$id)
        if ($st.Labels.ContainsKey($id)) { $st.Labels[$id].BackColor = [Drawing.Color]::Black; $st.Labels[$id].ForeColor = [Drawing.Color]::White }
        $st.Pressed[$id] = $true
    }
    $mouse = {
        if ($_.Button -eq 'Left') { & $pointerMark 'click-left' }
        elseif ($_.Button -eq 'Right') { & $pointerMark 'click-right' }
        elseif ($_.Button -eq 'Middle') { & $pointerMark 'click-middle' }
    }

    $y = 60
    $rowIndex = 0
    foreach ($row in ($main + $extra + 'Left_click|click-left|2 Right_click|click-right|2 Scroll_up|wheel-up|2 Scroll_down|wheel-down|2')) {
        $x = 16
        if ($rowIndex -eq $main.Count) { $y += 12 }   # a gap before the optional rows
        foreach ($tok in ($row -split ' ')) {
            $p = $tok -split '\|'
            $w = if ($p.Count -ge 3) { [double]$p[2] } else { 1 }
            $l = New-Object Windows.Forms.Label
            $l.Text = $p[0] -replace '_', ' '; $l.TextAlign = 'MiddleCenter'; $l.BorderStyle = 'FixedSingle'
            $l.Location = New-Object Drawing.Point([int]$x, [int]$y)
            $l.Size = New-Object Drawing.Size([int]($w * $u - 4), [int]($u - 8))
            $l.BackColor = [Drawing.Color]::White
            if ($rowIndex -ge $main.Count -and $rowIndex -lt ($main.Count + $extra.Count)) { $l.ForeColor = [Drawing.Color]::Gray }
            $l.Add_MouseDown($mouse)
            $form.Controls.Add($l)
            $key = if ($p[1] -match '^\d+$') { [int]$p[1] } else { $p[1] }
            $st.Labels[$key] = $l; $st.Names[$key] = $p[0] -replace '_', ' '
            if ($rowIndex -lt $main.Count) { $st.Required.Add([int]$p[1]) }
            $x += $w * $u
        }
        $y += $u
        $rowIndex++
    }
    $status = New-Object Windows.Forms.Label
    $status.Location = New-Object Drawing.Point(16, ($y + 8)); $status.Size = New-Object Drawing.Size((12 * $u), 28)
    $form.Controls.Add($status)
    $done = New-Object Windows.Forms.Label
    $done.Text = 'Finished'; $done.TextAlign = 'MiddleCenter'; $done.BorderStyle = 'FixedSingle'
    $done.BackColor = [Drawing.Color]::Black; $done.ForeColor = [Drawing.Color]::White
    $done.Location = New-Object Drawing.Point((16 + 14 * $u), ($y + 4)); $done.Size = New-Object Drawing.Size((3 * $u - 4), 34)
    $done.Add_Click({ $form.Close() })
    $form.Controls.Add($done)
    $form.ClientSize = New-Object Drawing.Size((17 * $u + 32), ($y + 50))

    $refresh = { $n = @($st.Required | Where-Object { $st.Pressed.ContainsKey($_) }).Count; $status.Text = "$n of $($st.Required.Count) main keys registered" }
    & $refresh

    # Shift, Ctrl and Alt arrive as one code; the left and right keys are told apart by their live state
    $sideOf = { param([int]$vk) switch ($vk) {
            16 { if ([HandsOn]::IsDown(161)) { 161 } else { 160 } }
            17 { if ([HandsOn]::IsDown(163)) { 163 } else { 162 } }
            18 { if ([HandsOn]::IsDown(165)) { 165 } else { 164 } }
            default { $vk } } }

    $form.Add_PreviewKeyDown({ $_.IsInputKey = $true })   # so Tab and the arrows reach KeyDown
    $form.Add_KeyDown({
        $e = $_
        $vk = & $sideOf ([int]$e.KeyValue)
        $now = [Environment]::TickCount
        if (-not $st.Down[$vk]) {
            # Chatter: the key "pressed again" within 40 ms of letting go, faster than a finger can
            if ($st.LastUp.ContainsKey($vk) -and ($now - $st.LastUp[$vk]) -lt 40) { $st.Chatter[$vk] = 1 + [int]$st.Chatter[$vk] }
            $st.Down[$vk] = $true
            if ($st.Labels.ContainsKey($vk)) { $st.Labels[$vk].BackColor = [Drawing.Color]::Black; $st.Labels[$vk].ForeColor = [Drawing.Color]::White }
            else { $st.Other["$($e.KeyCode)"] = $true }
            $st.Pressed[$vk] = $true
            & $refresh
        }
        $e.Handled = $true; $e.SuppressKeyPress = $true
    })
    $form.Add_KeyUp({
        $e = $_
        $now = [Environment]::TickCount
        $vks = switch ([int]$e.KeyValue) { 16 { 160, 161 } 17 { 162, 163 } 18 { 164, 165 } default { [int]$e.KeyValue } }
        foreach ($vk in @($vks)) {
            if ($st.Down[$vk] -and -not [HandsOn]::IsDown($vk)) { $st.Down[$vk] = $false; $st.LastUp[$vk] = $now }
        }
        # Print Screen only sends a key-up
        if ([int]$e.KeyValue -eq 44 -and -not $st.Pressed[44]) {
            $st.Pressed[44] = $true; $st.Labels[44].BackColor = [Drawing.Color]::Black; $st.Labels[44].ForeColor = [Drawing.Color]::White
        }
        $e.Handled = $true
    })
    $form.Add_MouseDown($mouse)
    $form.Add_MouseWheel({ if ($_.Delta -gt 0) { & $pointerMark 'wheel-up' } else { & $pointerMark 'wheel-down' } })
    [void]$form.ShowDialog()
    $form.Dispose()

    $missing = @($st.Required | Where-Object { -not $st.Pressed.ContainsKey($_) } | ForEach-Object { $st.Names[$_] })
    if ($missing.Count -eq 0) { Add-Result 'PASS' 'Keyboard' "all $($st.Required.Count) main keys registered" }
    else { Add-Result 'FAIL' 'Keyboard' "$($missing.Count) of $($st.Required.Count) main keys never registered: $($missing -join ' '). Try them again in Notepad; a key that does not work is a fault" }
    $chat = @($st.Chatter.Keys | ForEach-Object { "$($st.Names[$_]) x$($st.Chatter[$_])" })
    if ($chat.Count -gt 0) { Add-Result 'WARN' 'Keyboard chatter' "keys that registered twice for one press: $($chat -join ', '). Press them slowly in Notepad and watch for doubled letters" }
    $extraHit = @($st.Pressed.Keys | Where-Object { $_ -is [int] -and $st.Required -notcontains $_ } | ForEach-Object { $st.Names[$_] } | Where-Object { $_ })
    if ($extraHit.Count -gt 0) { Add-Result 'INFO' 'Keyboard extra keys' "also registered: $($extraHit -join ' ')" }
    $ptr = @('click-left', 'click-right', 'wheel-up', 'wheel-down')
    $ptrMissing = @($ptr | Where-Object { -not $st.Pressed.ContainsKey($_) } | ForEach-Object { $st.Names[$_] })
    if ($ptrMissing.Count -eq 0) { Add-Result 'PASS' 'Touchpad' 'left click, right click and scrolling registered' }
    else { Add-Result 'FAIL' 'Touchpad' "never registered: $($ptrMissing -join ', ')" }
}

# ---------- speakers ----------
function Test-Speakers {
    Write-Host 'Unplug headphones and set the volume to about half.'
    $tests = @(
        @{ Name = 'Speakers: left'; Q = 'Did you hear the tone from the LEFT side only?'; Wav = [HandsOn]::Tone(440, 440, 1.5, 1, 0) }
        @{ Name = 'Speakers: right'; Q = 'Did you hear the tone from the RIGHT side only?'; Wav = [HandsOn]::Tone(660, 660, 1.5, 0, 1) }
        @{ Name = 'Speakers: sweep'; Q = 'Was the rising tone clear all the way, with no rattle, buzz or crackle?'; Wav = [HandsOn]::Tone(60, 12000, 6, 1, 1) }
    )
    foreach ($t in $tests) {
        do { Invoke-Sound $t.Wav; $a = Read-Choice "$($t.Q) (r = play again)" @('y', 'n', 'r') } while ($a -eq 'r')
        if ($a -eq 'y') { Add-Result 'PASS' $t.Name 'heard as expected' }
        else { Add-Result 'FAIL' $t.Name 'not as expected. Check the sound output in Settings, System, Sound, then try again' }
    }
}

# ---------- microphone ----------
function Test-Microphone {
    $wav = Join-Path $env:TEMP 'secondtrust_mic.wav'
    Remove-Item $wav -Force -ErrorAction SilentlyContinue
    [void](Read-Host 'Press Enter, then count out loud from one to five (4 seconds of recording)')
    $rc = [HandsOn]::Mci('open new type waveaudio alias strec')
    if ($rc -ne 0) { Add-Result 'WARN' 'Microphone' "Windows could not open a recording device (MCI error $rc)"; return }
    [void][HandsOn]::Mci('set strec bitspersample 16 channels 1 samplespersec 44100 bytespersec 88200 alignment 2')
    [void][HandsOn]::Mci('record strec')
    Write-Host 'Recording...'
    Start-Sleep -Seconds 4
    [void][HandsOn]::Mci('stop strec')
    $rc = [HandsOn]::Mci("save strec `"$wav`"")
    [void][HandsOn]::Mci('close strec')
    if ($rc -ne 0 -or -not (Test-Path $wav)) { Add-Result 'WARN' 'Microphone' "the recording could not be saved (MCI error $rc)"; return }
    $peak = [HandsOn]::Peak($wav)
    Write-Host 'Playing it back...'
    try { (New-Object Media.SoundPlayer $wav).PlaySync() } catch { }
    $heard = Read-YesNo 'Did you hear your own voice clearly?'
    Remove-Item $wav -Force -ErrorAction SilentlyContinue   # your voice is not kept in the report
    $lvl = [math]::Round(100 * [math]::Max(0, $peak))
    if ($peak -lt 0.02) { Add-Result 'FAIL' 'Microphone' "the recording was silent (peak $lvl%). Check Settings, Privacy, Microphone (allow desktop apps) and the mute key, then test again" }
    elseif (-not $heard) { Add-Result 'FAIL' 'Microphone' "sound was recorded (peak $lvl%) but not clearly. Test again in a quiet room" }
    else { Add-Result 'PASS' 'Microphone' "recorded and played back clearly (peak level $lvl%)" }
}

# ---------- webcam ----------
function Test-Webcam {
    try { Start-Process 'microsoft.windows.camera:' -ErrorAction Stop }
    catch { Add-Result 'WARN' 'Webcam picture' 'the Camera app did not open. Open any camera app and check by hand'; return }
    $ok = Read-YesNo 'In the Camera app: is the picture sharp and steady, with no lines, dead spots or colour cast? (close the app after)'
    if ($ok) { Add-Result 'PASS' 'Webcam picture' 'clear picture' } else { Add-Result 'FAIL' 'Webcam picture' 'picture faulty. Photograph the screen' }
}

# ---------- USB ports ----------
function Test-UsbPorts {
    Write-Host 'You need a USB stick or drive with 300 MB free. One test file is written to it and deleted; nothing else is touched.'
    Write-Host 'For USB-C ports, use a USB-C stick or an adapter.'
    $n = 0
    [void][int]::TryParse("$(Read-Host 'How many USB ports do you want to test? (0 to skip)')", [ref]$n)
    $done = New-Object System.Collections.Generic.List[object]
    for ($i = 1; $i -le $n; $i++) {
        $name = "$(Read-Host "Port $i of ${n}: unplug the stick, type a name for this port (for example left USB-A) and press Enter")".Trim()
        if (-not $name) { $name = "port $i" }
        $before = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter)" })
        Write-Host "Now plug the stick into '$name'. Waiting up to 2 minutes..."
        $vol = $null
        $deadline = (Get-Date).AddMinutes(2)
        while (-not $vol -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 700
            $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and ($before -notcontains "$($_.DriveLetter)") } | Select-Object -First 1
        }
        if (-not $vol) { Add-Result 'FAIL' "USB port: $name" 'no drive appeared within 2 minutes. A dead port, or the stick: try the stick in another port'; continue }
        Start-Sleep -Seconds 2
        $dev = try { (Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction Stop | Get-Disk -ErrorAction Stop).FriendlyName } catch { "drive $($vol.DriveLetter):" }
        if ($vol.SizeRemaining -lt 300MB) { Add-Result 'WARN' "USB port: $name" "$dev detected, but it has less than 300 MB free: speed not tested"; continue }
        Write-Host "Testing $dev on ${name}: 256 MB written and read back..."
        $sp = Measure-DriveSpeed -Folder "$($vol.DriveLetter):\" -SizeMB 256
        if ($sp.Error) { Add-Result 'WARN' "USB port: $name" "$dev detected, speed test failed: $($sp.Error)" }
        elseif ($sp.BadChunks -gt 0) { Add-Result 'FAIL' "USB port: $name" "$dev read back different data in $($sp.BadChunks) blocks. Try another stick; if it repeats, the port corrupts data" }
        else {
            $speedNote = if ($sp.ReadMBs -lt 42) { ', USB 2 speed (the port or the stick)' } else { '' }
            Add-Result 'PASS' "USB port: $name" "$dev, read $($sp.ReadMBs) MB/s, write $($sp.WriteMBs) MB/s, data intact$speedNote"
            $done.Add([pscustomobject]@{ Port = $name; Device = $dev; ReadMBs = $sp.ReadMBs; WriteMBs = $sp.WriteMBs })
        }
        Write-Host 'Done. Unplug the stick.'
    }
    if ($done.Count -gt 0) {
        $done | Export-Csv (Join-Path $OutDir 'usb_ports.csv') -NoTypeInformation
        # Same stick in every port: a port far slower than the best one is running at a lower USB speed
        if ($done.Count -ge 2) {
            $best = ($done | Measure-Object ReadMBs -Maximum).Maximum
            foreach ($d in @($done | Where-Object { $_.ReadMBs -lt 0.5 * $best })) {
                Add-Result 'WARN' "USB port speed: $($d.Port)" "$($d.ReadMBs) MB/s against $best MB/s on the best port with the same stick. Check the port's rated speed; if it should be fast, it is faulty"
            }
        }
    }
}

# ---------- other ports ----------
function Test-OtherPorts {
    $asks = @(
        @{ Name = 'HDMI / display out'; Q = 'Connect a monitor or TV to HDMI (and to USB-C if it supports display). Did each show a picture?' }
        @{ Name = 'Headphone jack'; Q = 'Plug in headphones. A tone plays left, then right. Did you hear both, on the correct sides?'; Wav = $true }
        @{ Name = 'USB-C charging'; Q = 'If the laptop charges over USB-C: plug in a USB-C charger (100 W or more). Did Windows show it charging?' }
        @{ Name = 'Charger port and cable'; Q = 'With the laptop''s own charger, wiggle the plug gently. Did charging stay on, with no flicker?' }
    )
    foreach ($a in $asks) {
        if ($a.Wav) {
            $c = Read-Choice "$($a.Name): play the test tone? (y = play, s = skip)" @('y', 's')
            if ($c -eq 's') { Add-Result 'INFO' $a.Name 'skipped'; continue }
            Invoke-Sound ([HandsOn]::Tone(440, 440, 1.2, 1, 0)); Invoke-Sound ([HandsOn]::Tone(660, 660, 1.2, 0, 1))
        }
        $r = Read-Choice "$($a.Q) (s = skip, not available)" @('y', 'n', 's')
        if ($r -eq 'y') { Add-Result 'PASS' $a.Name 'works' }
        elseif ($r -eq 'n') { Add-Result 'FAIL' $a.Name 'did not work. Try another cable or device to rule them out' }
        else { Add-Result 'INFO' $a.Name 'skipped' }
    }
}

# ---------- menu ----------
Section 'Hands-on tests'
$handsOn = [ordered]@{
    '1' = @('Screen colours: dead pixels and backlight', 'Test-Screen')
    '2' = @('Keyboard and touchpad: every key, clicks and scrolling', 'Test-Keyboard')
    '3' = @('Speakers: left, right and a sweep for rattles', 'Test-Speakers')
    '4' = @('Microphone: record and play back', 'Test-Microphone')
    '5' = @('Webcam: picture', 'Test-Webcam')
    '6' = @('USB ports: each port with a speed test', 'Test-UsbPorts')
    '7' = @('Other ports: HDMI, headphones, charging', 'Test-OtherPorts')
}
foreach ($k in $handsOn.Keys) { Write-Host "  $k  $($handsOn[$k][0])" }
$pick = "$(Read-Host 'Which tests? Press Enter for all, or type numbers such as 1 2 6')".Trim()
$chosen = if ($pick) { @($pick -split '[\s,]+' | Where-Object { $handsOn.Contains($_) }) } else { @($handsOn.Keys) }
foreach ($k in $chosen) {
    Write-Host "`n--- $($handsOn[$k][0]) ---" -ForegroundColor Cyan
    try { & $handsOn[$k][1] }
    catch { Add-Result 'WARN' "Hands-on: $($handsOn[$k][0])" "the test could not run: $($_.Exception.Message)" }
}
