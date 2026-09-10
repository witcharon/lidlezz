# Lidlezz hangi Mac'lerde çalışır

Son güncelleme: 2026-09-10

## Kısa cevap

**Apple Silicon (M1 ve sonrası) MacBook Air ve MacBook Pro, macOS 14 Sonoma veya üstü.**
Intel Mac'ler desteklenmiyor. Masaüstü Mac'lerde (mini, Studio, iMac, Pro) uygulama açılır ama kapak olmadığı için asıl özelliği anlamsızdır.

## Neden bu sınırlar: kullandığımız teknolojiler

| Teknoloji | Ne için | Gereksinim |
|---|---|---|
| Swift 5 / SwiftUI / AppKit (NSStatusItem, NSPopover) | Menü çubuğu uygulaması | macOS 14 (`Package.swift` platform şartı, `LSMinimumSystemVersion 14.0`) |
| `SMAppService.daemon` | Root helper kaydı, sudoers yerine | macOS 13+ |
| `NSXPCConnection.setCodeSigningRequirement` | Helper'a yalnızca imzalı Lidlezz bağlanabilsin | macOS 13+ |
| `pmset -a disablesleep 1` | Kapak kapalıyken uyanık kalmak | Her Mac'te var; root ister (helper) |
| `pmset -a lowpowermode 1` | Çantada düşük güç | macOS 12+, Apple Silicon ve 2019+ Intel dizüstüler |
| `taskpolicy -b` | Claude Code'u verimli çekirdeklere almak | Apple Silicon'da P/E çekirdek ayrımı var; Intel'de yalnızca öncelik düşürür |
| IOHIDEventSystemClient (private API) `PMU tdie…` / `pACC,eACC MTR Temp Sensor…` | SoC sıcaklığı, 85°/95° eşikleri | Yalnızca Apple Silicon; Intel SMC anahtarları farklı, okunmaz |
| `IOPMrootDomain.AppleClamshellState` | Kapak kapalı mı | Yalnızca dizüstü; masaüstünde hep açık |
| `IOPSCopyPowerSourcesInfo`, `AppleSmartBattery` | Pil yüzdesi ve watt | Yalnızca pilli Mac'ler |
| `IOPMAssertionCreateWithName(PreventUserIdleSystemSleep)` | Kapak açıkken uyanık tutmak | Her Mac |
| `tmutil disable/enable` | Çantada Time Machine'i durdurmak | Her Mac, root |
| UserNotifications | Bildirimler | Her Mac |
| Claude Code hook'ları (`~/.claude/settings.json`) | Oturum çalışıyor/bitti/limit bekliyor | Claude Code 2.1.234+ (limit bekleme olayı için) |
| Derleme hedefi | | Yalnızca arm64; Homebrew cask `depends_on arch: :arm64` |

Sıcaklık sensörü adları çipe göre değişir: M2 ve sonrası `PMU tdie1…N`, M1 `pACC/eACC MTR Temp Sensor…`. Uygulama önce `tdie`, yoksa `ACC MTR` sensörlerinin en sıcağını alır. M4'te doğrulandı; M1'de sensör adı fallback'i kodda var ama gerçek cihazda test edilmedi.

## Uygun modeller

Tam destek = kapak kapalı mod, sıcaklık koruması, pil tabanı, E-core kısma.

### MacBook Air

| Model | Çip | Yıl | Durum |
|---|---|---|---|
| MacBook Air 13" | M1 | 2020 | Tam destek, sensör fallback'i (test edilmedi) |
| MacBook Air 13" | M2 | 2022 | Tam destek |
| MacBook Air 15" | M2 | 2023 | Tam destek |
| MacBook Air 13" / 15" | M3 | 2024 | Tam destek |
| MacBook Air 13" / 15" | M4 | 2025 | Tam destek, geliştirme makinesi |
| MacBook Air 13" / 15" | M5 | 2026 | Tam destek bekleniyor (aynı sensör ailesi), test edilmedi |

Not: MacBook Air fansızdır; kapalı kapak + çanta senaryosunda 85° kısma eşiğine MacBook Pro'dan daha çabuk ulaşır. Asıl hedef kitle burası.

### MacBook Pro

| Model | Çip | Yıl | Durum |
|---|---|---|---|
| MacBook Pro 13" | M1 | 2020 | Tam destek, sensör fallback'i (test edilmedi) |
| MacBook Pro 14" / 16" | M1 Pro, M1 Max | 2021 | Tam destek, sensör fallback'i (test edilmedi) |
| MacBook Pro 13" | M2 | 2022 | Tam destek |
| MacBook Pro 14" / 16" | M2 Pro, M2 Max | 2023 | Tam destek |
| MacBook Pro 14" / 16" | M3, M3 Pro, M3 Max | 2023 | Tam destek |
| MacBook Pro 14" / 16" | M4, M4 Pro, M4 Max | 2024 | Tam destek |
| MacBook Pro 14" | M5 | Ekim 2025 | Tam destek bekleniyor, test edilmedi |
| MacBook Pro 14" / 16" | M5 Pro, M5 Max | Mart 2026 | Tam destek bekleniyor, test edilmedi |

### Masaüstü Mac'ler (Apple Silicon)

Mac mini (M1–M4), Mac Studio (M1 Max–M4 Ultra), iMac (M1–M4), Mac Pro (M2 Ultra): uygulama açılır, sıcaklık okuma ve otomatik başlatma çalışır, ama kapak sensörü hep "açık" döner, pil yoktur. Kapak kapalı modun sağladığı hiçbir şey yoktur; bu makinelerde zaten uyku sorunu olmaz. Pazarlamada saymıyoruz.

### Desteklenmeyenler

- **Intel Mac'ler (2020 ve öncesi):** derleme arm64, sıcaklık sensörleri okunmaz, E-core yoktur. Rosetta ile de çalışmaz.
- **macOS 13 Ventura ve altı:** SwiftUI ve SMAppService gereksinimleri nedeniyle açılmaz. M1 makinelerde Sonoma'ya güncelleme ücretsiz ve mümkündür.

## macOS sürümü

Tüm Apple Silicon Mac'ler macOS 14 Sonoma, 15 Sequoia ve 26 Tahoe'yu çalıştırır. Geliştirme ve testler macOS 26.5 üzerinde yapıldı; 14 ve 15'te derleme hedefi uyumlu ama uçtan uca test edilmedi.

## Test durumu

| Ortam | Test |
|---|---|
| MacBook Air M4, macOS 26.5 | Tüm özellikler, notarize kurulum, Homebrew |
| M1 ailesi | Sensör adı fallback'i yazıldı, cihaz testi yok |
| M2, M3, M5 | Aynı sensör ailesi (`PMU tdie`), cihaz testi yok |
| macOS 14 / 15 | Derleme hedefi uyumlu, cihaz testi yok |

Kaynaklar: [exelban/stats sensör listesi](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift), [vladkens/macmon](https://github.com/vladkens/macmon), [MacRumors 2026 Mac roadmap](https://www.macrumors.com/2026/07/27/mac-roadmap-2026/), [Macworld M5 Pro/Max](https://www.macworld.com/article/2942089/macbook-pro-m5-pro-max-release-specs-price.html).
