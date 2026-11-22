# Apple MacBook Air 13-inch, M3 (Mac15,12). RAM and SSD size depend on the configuration bought, so they are
# listed, not compared: check them against your invoice.
# Format and every key: docs/profiles.md
@{
    Name          = 'Apple MacBook Air 13-inch, M3 (Mac15,12)'
    Detect        = 'Mac15,12'                # model identifier
    Model         = 'MacBook Air'
    Cpu           = 'M3'
    Cores         = 8                         # 4 performance + 4 efficiency
    Threads       = 8
    Gpu           = 'M3'
    Display       = '2560x1664'
    Sources = @(
        'https://support.apple.com/en-us/118551'
    )
    Verified = 'Run on a real unit 2026-11-22 (macOS 26.4.1): model, chip, cores, GPU and panel as above'
}
