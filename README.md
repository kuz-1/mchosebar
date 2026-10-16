# MchoseBar

Menu bar app for the MCHOSE G75 Pro on macOS. Talks to the 2.4G dongle directly over IOHID, no web driver needed.

- battery level, low battery alerts
- polling rate, Mac/Win mode, Win lock, low latency, sleep timer
- lighting effect, brightness, speed, color

Only tested with the G75 Pro over the 2.4G dongle. Not affiliated with MCHOSE.

UI inspired by Vorssaint.

## Build

Needs macOS 14+ and Xcode command line tools.

```sh
git clone https://github.com/kuz-1/mchosebar.git
cd mchosebar
./build.sh
open build/MchoseBar.app
```

On first launch allow it in System Settings → Privacy & Security → Input Monitoring.

Without a signing cert the build is signed ad-hoc and macOS forgets the Input Monitoring permission after every rebuild. To avoid that, make a self-signed code signing cert called `MchoseBar Dev` in Keychain Access (Certificate Assistant → Create a Certificate → Code Signing).

## Debug

```sh
open -n build/MchoseBar.app --args --dump       # battery + settings
open -n build/MchoseBar.app --args --read 44    # raw read
open -n build/MchoseBar.app --args --selftest   # write test, puts everything back
```

Log: `~/Library/Logs/MchoseBar.log`

## Protocol

Dongle `41E4:2001`, usage page `FF02`, report `0x13`, 19 bytes.

- read: `[cmd, 01, 0..., sum]`
- reply/write packet: `[cmd, total, seq, len, 14 bytes, sum]`, the keyboard echoes each write packet back
- `sum` = low byte of all previous bytes, report ID included

| Read | Write | |
|---|---|---|
| `44` | `04` | settings, 128 bytes |
| `49` | `09` | colors, 490 bytes |
| `4a` | | battery |

Settings offsets: 1 polling rate (1/2/3 = 250/500/1000), 3 low latency (0 on, 2 off), 10 effect,
15 win lock, 24 sleep (minutes × 2, 0 never), 27 mode (2 Mac, 0 Win), 58+ per effect `[brightness, speed << 4 | multi]`.

## License

Copyright (C) 2026 kuz-1

GPL-3.0, see [LICENSE](LICENSE). If you share a modified version, you have to share its source under the same license.
