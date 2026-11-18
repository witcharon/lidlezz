# Releasing

For maintainers with the Developer ID certificate.

1. Bump `VERSION`, then run `./scripts/release.sh`. It signs with Developer ID, notarizes, and writes `dist/Lidlezz-<v>.dmg`, `dist/Lidlezz.dmg` (same file, stable name for the "latest" download link), `dist/appcast.xml`, `dist/latest.json` and `homebrew/lidlezz.rb`.
2. Publish the GitHub release:
   `gh release create v<v> dist/Lidlezz-<v>.dmg dist/Lidlezz.dmg --repo witcharon/lidlezz`
3. Copy `dist/appcast.xml` and `dist/latest.json` into `lidlezz-web/public/` and push (the site deploys itself).
4. Put `homebrew/lidlezz.rb` into `Casks/` of `witcharon/homebrew-tap`.

One-time setup: a "Developer ID Application" certificate in the login keychain and
`xcrun notarytool store-credentials lidlezz --apple-id <id> --team-id <team> --password <app-specific password>`.

## Updates

Updates take one of two paths, depending on how the app was installed:

- **Installed from the DMG:** Sparkle checks `appcast.xml` on its own schedule, downloads, installs and relaunches. The panel has a "Check for updates…" button.
- **Installed with Homebrew** (detected from the `Caskroom` receipt): Sparkle never starts, because brew owns the app. Lidlezz reads `latest.json` instead, posts one notification per version, and the panel shows a button that copies `brew upgrade --cask lidlezz`.

The Sparkle signing key is in the keychain ("Private key for signing Sparkle updates"); its public half is embedded in `Info.plist` as `SUPublicEDKey`. `generate_appcast` only signs when that key is present.

Releases up to v0.2.4 were published from `witcharon/lidlezz-releases`; older appcast entries still point there.
