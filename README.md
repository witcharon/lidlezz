# Lidlezz

Claude Code'u kapak kapalıyken çalıştır, Mac'i pişirmeden.

- `claude` çalıştığı sürece Mac'i uyanık tutar; iş bitince her şeyi geri alıp normal uykuya bırakır.
- Kapak kapanınca (harici ekran yoksa) Claude Code ağacını arka plan QoS'una alır, Low Power Mode açar, Time Machine ve fotoğraf analizini duraklatır. Kapak açılınca geri alır.
- İki ayar: pil yüzde kaça inince mod kapansın (varsayılan %15) ve otomatik açılan mod kaç dakika boşta kalınca kapansın (3-30, varsayılan 10). SoC 95°'yi geçerse de kapanır; kapak kapalıysa Mac uyutulur, oturum `claude --resume` ile sürer.
- "Rejoin when offline": mod açıkken Mac tamamen ağsız kalırsa, seçilen kayıtlı Wi-Fi ağına (iPhone kişisel erişim noktası) yeniden bağlanır. Listede kayıtlı ağların telefon hotspot'ları çıkar. 15 sn bekler, sonra dakikada bir dener. Ağ bir kez elle bağlanmış olmalı; parola macOS'ta duruyor. Varsayılan: Never.
- Claude Code hook'ları oturumun ne zaman çalışıp ne zaman bittiğini bildirir; mod kendiliğinden açılır, iş bitince 2 dakika sonra kapanır.

## Kurulum

Kullanıcı için:

```sh
brew install --cask witcharon/tap/lidlezz
```

ya da [lidlezz-releases](https://github.com/witcharon/lidlezz-releases/releases/latest) sayfasından DMG. Geliştirici için:

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
- Satış: Stripe Payment Link → lidlezz-web (`witcharon/lidlezz-web`, Next.js, Dokploy) `/thanks` sayfası → aynı projedeki `/api/license` anahtarı üretir. Şartname: lidlezz-web/LICENSE-API.md.
- `scripts/keygen.mjs` imza çiftini üretir (bir kez, yapıldı), `scripts/sign.mjs` test anahtarı üretir.
- İptal: anahtarın içinde alıcıya bağlı, geri çevrilemez bir kimlik var. `node scripts/revoke-id.mjs <e-posta>` kimliği verir; onu `lidlezz-web/public/revoked.json` içine ekleyip deploy edersin. Uygulama listeyi güncelleme kontrolüyle birlikte çeker; sunucuya ulaşamazsa son bilinen liste geçerli kalır, kimsenin lisansı kazara düşmez. Yayınlanan dosyada e-posta yok.
- İmzalama özel anahtarı login anahtar zincirinde "Lidlezz license signing key" olarak duruyor; `wrangler secret put LICENSE_PRIVATE_KEY` ile Worker'a verilir.
- Yayın: `VERSION` dosyasını artır, `scripts/release.sh` çalıştır (Developer ID imzası, notarization, `dist/Lidlezz-<v>.dmg`, `dist/latest.json`, `homebrew/lidlezz.rb`). Sonra:
  `gh release create v<v> dist/Lidlezz-<v>.dmg dist/latest.json --repo witcharon/lidlezz-releases`,
  `homebrew/lidlezz.rb` dosyasını `witcharon/homebrew-tap` deposundaki `Casks/` altına kopyalayıp push;
  `dist/appcast.xml` ve `dist/latest.json` dosyalarını `lidlezz-web/public/` altına kopyalayıp deploy et.
- Depolar: kaynak `witcharon/lidlezz` (private), indirme `witcharon/lidlezz-releases` (public), Homebrew `witcharon/homebrew-tap` (public).
- Güncelleme iki yoldan gider, çünkü doğru yol kurulumun kaynağına bağlı:
  - **DMG ile kurulmuşsa** Sparkle devrede. `appcast.xml`'i kendi takvimiyle kontrol eder, indirir, kurar, uygulamayı yeniden başlatır. Panelde "Check for updates…" düğmesi var.
  - **Homebrew ile kurulmuşsa** (`Caskroom` kaydına bakılır) Sparkle hiç başlatılmaz, çünkü uygulamayı brew yönetiyor. Bunun yerine `latest.json` kontrol edilir, sürüm başına bir kez bildirim atılır ve panelde `brew upgrade --cask lidlezz` komutunu kopyalayan bir düğme çıkar.
- Sparkle imza anahtarı anahtar zincirinde ("Private key for signing Sparkle updates"); açık yarısı `Info.plist` içinde `SUPublicEDKey` olarak gömülü. `generate_appcast` yalnızca DMG içindeki uygulamada bu anahtar varsa imzalar.

## Desteklenen kodlama ajanları

Her araçtan iki şey isteniyor: kapak kapanınca hangi süreçlerin kısılacağı ve mümkünse ne zaman
gerçekten çalıştığı. İkincisi olmadan da sıcaklık, pil ve kısma korumaları çalışır; sadece modu
elle açman gerekir.

| Ajan | Bağlantı | Nereye yazılır |
|---|---|---|
| Claude Code | Tam. Başlangıç, araç çağrısı, bitiş, kullanım limiti beklemesi | `~/.claude/settings.json` |
| Cursor | Tam. sessionStart, beforeSubmitPrompt, preToolUse, stop, sessionEnd | `~/.cursor/hooks.json` |
| Antigravity | Tam. PreToolUse, Stop | `~/.gemini/config/hooks.json` |
| opencode | Tam. tool.execute.before, session.idle | `~/.config/opencode/plugin(s)/lidlezz.js` |
| Codex CLI | Kısmi. Yalnızca turun bittiğini bildirir | `~/.codex/config.toml` içindeki `notify` |
| Claude for Mac (Cowork) | Yok. Modu elle aç | — |

Notlar:

- **Codex'in tek olayı var.** `agent-turn-complete` dışında bir şey yok, yani turun başladığını
  öğrenemiyoruz. Bunun yerine çalışan `codex` süreci başına bir oturum açılır ve tur bitince boşta
  işaretlenir. Pratikte `codex exec` gibi tek turluk işleri tam kapsar; interaktif oturumda ilk turdan
  sonraki turlar için modu elle açık bırakman gerekir.
- **Codex'te tek bir notify komutu olabiliyor.** Kullanıcının kendi komutu varsa Lidlezz onu silmez;
  `~/.codex/lidlezz-notify.sh` adında, önce Lidlezz'e haber verip sonra eski komutu çalıştıran bir
  betik kurar. Eski komut betiğin içinde `# lidlezz-previous:` satırında saklanır ve
  `lidlezz hooks uninstall codex` ile geri konur.
- **Masaüstü uygulamaları gün boyu açık durur**, o yüzden varlıkları "çalışıyor" demek değildir.
  Modun kendiliğinden bitmesi bu araçlarda süreçlerin kaybolmasına değil, boşta kalma süresine bakar.
- Her yazıcı yalnızca kendi imzasını taşıyan kayıtlara dokunur; kullanıcının kendi hook'ları yerinde kalır.
