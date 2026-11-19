# HP OMEN Transcend 16-u0005TX, product number 834T6PA (2023, Intel 13th gen).
# Format and every key: docs/profiles.md
@{
    Name          = 'HP OMEN Transcend 16-u0005TX (834T6PA)'
    Detect        = 'Transcend|8BB3'        # regex against "<model> <board ID>"
    ProductNumber = '834T6PA'               # the box and invoice say 834T6PA#ACJ
    Model         = 'Transcend'
    BoardId       = '8BB3'                  # per github.com/arfelious/omen-fan-control
    Cpu           = '13700HX'
    Cores         = 16                      # 8 P-cores + 8 E-cores. The cheaper 13700H has 14 / 20
    Threads       = 24
    Gpu           = 'RTX 4070'
    GpuVramGB     = 8
    RamModules    = 2
    RamGB         = 16
    RamMatched    = $true                   # two SO-DIMMs, same part number
    RamMinMTs     = 4800                    # the i7-13700HX runs DDR5 at up to 4800 MT/s
    SsdGB         = 1000
    Display       = '2560x1600'
    DisplayMinHz  = 240
    BatteryWh     = 97                      # disputed: one listing says 45 Wh. Mismatch is only a WARN
    Pk            = 'HP|Hewlett'
    GpuTempWarn   = 87                      # -Monitor: WARN at or above (C)
    GpuMinWatts   = 95                      # -Monitor: WARN if sustained full-load GPU power is lower
    GpuSustainedNote = 'LaptopMedia: about 109 W, 2280 MHz after 30 min of gaming'
    CpuSustainedNote = 'LaptopMedia: P-cores about 3000 MHz at 82 C; this average includes E-cores, so it reads lower'
    Sources = @(
        'https://www.hp.com/ca-en/gaming-pc/laptops/2023-omen-transcend-intel.html'
        'https://laptopmedia.com/review/hp-omen-transcend-16-16-u0000-review-sleek-thin-gaming-machine-but-its-performance-is-held-back-by-the-moderate-gpu-clock/'
        'https://www.91mobiles.com/hp-transcend-16-u0005tx-834t6pa-core-i7-13th-gen-16-gb-1-tb-windows-11-laptop-price-in-india-157512?ty=specs'
    )
    Verified = 'Not yet run on a real unit'
}
