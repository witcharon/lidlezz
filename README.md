# Lidlezz

Claude Code'u kapak kapalıyken çalıştır, Mac'i pişirmeden.

- `claude` çalıştığı sürece Mac'i uyanık tutar; iş bitince her şeyi geri alıp normal uykuya bırakır.
- Kapak kapanınca (harici ekran yoksa) Claude Code ağacını arka plan QoS'una alır, Low Power Mode açar, Time Machine ve fotoğraf analizini duraklatır. Kapak açılınca geri alır.
- İki ayar: pil yüzde kaça inince mod kapansın (varsayılan %15) ve otomatik açılan mod kaç dakika boşta kalınca kapansın (3-30, varsayılan 10). SoC 95°'yi geçerse de kapanır; kapak kapalıysa Mac uyutulur, oturum `claude --resume` ile sürer.
- Claude Code hook'ları oturumun ne zaman çalışıp ne zaman bittiğini bildirir; mod kendiliğinden açılır, iş bitince 2 dakika sonra kapanır.

## Kurulum

```sh
./scripts/install.sh   # derler, /Applications/Lidlezz.app olarak kurar, hook'ları ona bağlar, açar
```

İlk açılışta kurulum penceresi çıkar: sudoers kuralı, hook'lar, bildirim izni. Sadece paket istersen `./scripts/bundle.sh` → `dist/Lidlezz.app`.

Apple Silicon'da kapak kapalıyken uyanık kalmanın tek yolu `pmset disablesleep`, o da root ister.
Bunu uygulamanın içindeki küçük bir helper daemon yapar (SMAppService). Kurulumda macOS bir kez
Sistem Ayarları › Genel › Giriş Öğeleri › Arka Planda İzin Ver onayı ister. Helper yalnızca
Team ID'si eşleşen imzalı Lidlezz'den gelen çağrıları kabul eder ve sadece `pmset` ile `tmutil` çalıştırır.

İmza: `scripts/bundle.sh` makinedeki "Developer ID Application" ya da "Apple Development" sertifikasını
bulup hardened runtime ile imzalar; `SIGN_IDENTITY` ile seçebilirsin.

## Komut satırı

```sh
lidlezz                 # modu terminalde çalıştır (Ctrl-C kapatır)
lidlezz status          # sıcaklık, pil, kapak, oturumlar
lidlezz sensors         # tüm sıcaklık sensörleri
lidlezz hooks install   # ~/.claude/settings.json'a hook'ları ekle (uninstall / status)
lidlezz helper install  # helper daemon (status)
lidlezz battery 20      # modun kapanacağı pil yüzdesi
lidlezz idle 15         # otomatik açılan mod bu kadar dakika boşta kalınca kapansın (3-30)
```

CLI uygulamanın içindedir: `/Applications/Lidlezz.app/Contents/MacOS/lidlezz`. Terminalden kısa yazmak için:

```sh
ln -s /Applications/Lidlezz.app/Contents/MacOS/lidlezz ~/.local/bin/lidlezz
```

## Lisans ve yayın

- 7 gün deneme, sonra tek seferlik lisans. Anahtar `LZ-…` biçiminde, Ed25519 imzalı, çevrimdışı doğrulanır (`Sources/LidlezzCore/License.swift`).
- Satış: Stripe Payment Link → `site/thanks.html` → Cloudflare Worker (`site/worker`) anahtarı üretir. Kurulum adımları `site/README.md` içinde.
- İmzalama özel anahtarı login anahtar zincirinde "Lidlezz license signing key" olarak duruyor; `wrangler secret put LICENSE_PRIVATE_KEY` ile Worker'a verilir.
- Yayın: `scripts/release.sh` notarize edilmiş DMG ve `latest.json` üretir (Developer ID sertifikası ve `notarytool store-credentials lidlezz` gerekir). Sürüm numarası `VERSION` dosyasında.
- Uygulama açılışta ve 6 saatte bir `latest.json`'a bakar; yeni sürüm varsa panelde "Update to x.y.z" bağlantısı çıkar.
