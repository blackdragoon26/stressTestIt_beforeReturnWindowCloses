# ASUS VivoBook 15 X515DA (Ryzen 5 3500U). The machine this kit was developed and tested on.
# Format and every key: docs/profiles.md
@{
    Name          = 'ASUS VivoBook 15 X515DA (Ryzen 5 3500U)'
    Detect        = 'X515DA'
    ProductNumber = ''                      # ASUS firmware stores none: check skipped
    Model         = 'X515DA'
    BoardId       = 'X515DA'
    Cpu           = '3500U'
    Cores         = 4
    Threads       = 8
    Gpu           = 'Radeon'
    GpuVramGB     = 0                       # integrated graphics: no NVIDIA checks
    RamModules    = 2
    RamGB         = 8
    RamMatched    = $false                  # 4 GB soldered + 4 GB in the slot: part numbers differ by design
    RamMinMTs     = 2400
    SsdGB         = 512
    Display       = '1920x1080'
    DisplayMinHz  = 60
    BatteryWh     = 37
    Pk            = 'ASUS'
    GpuTempWarn   = 87
    GpuMinWatts   = 0
    GpuSustainedNote = ''
    CpuSustainedNote = ''
    Sources = @(
        'https://asus.com/us/laptops/for-home/all-series/vivobook-15-f512-amd/techspec'
    )
    Verified = 'Full audit run 2026-11-19; NVMe hours and TB written match Linux smartctl'
}
