# Scan Connector for Mac

**Initial public release: 0.0.1** · [Download for Apple silicon](https://github.com/canbeyz/scan-connector-for-mac/releases/latest)

**Independent community software for compatible network scanners.**

An independent Apple silicon macOS app for receiving scans from a **Brother MFC-L2820DW**. Choose a destination name and save folder once, then scan from the printer's control panel.

No Brother software, Rosetta, Python, or terminal is needed to run the app.

Experimental compatibility software. Not affiliated with, endorsed by, or supported by the printer manufacturer.

## Requirements and tested scope

- Apple silicon, with a deployment target of macOS 13 or later.
- MFC-L2820DW on the same trusted local network.
- Tested independently on Apple silicon with macOS 27. Other macOS versions have not all been tested.
- Discovery, panel reception, flatbed scanning, PDF output, and short destination names have been verified on real hardware.
- Real multi-page ADF scanning and login/wake behavior have not been exhaustively tested. Other printer models are unsupported.

## Install and set up

Open the DMG, drag **Scan Connector for Mac.app** to **Applications**, launch it, and allow local network access.

When upgrading, quit and remove the earlier app bundle before installing this version. The existing bundle identifier and settings directory are retained for preference compatibility; do not run both versions together. Recheck the login item after a rename. The 15-character limit applies to the printer destination name, not to this application's title.

This development build is ad-hoc signed and **not notarized by Apple**. If macOS blocks it, follow [Apple's instructions for opening a trusted app](https://support.apple.com/en-us/102445). Never disable Gatekeeper globally.

1. Select the printer, or expand **Enter an address manually** and enter its local IP or hostname.
2. Set **Destination** and **Save to**. Use a unique short name for each Mac, such as **OfficeMac**.
3. Click **Apply Settings**, then **Start Receiving** for initial setup.
4. On the printer, choose **Scan → to File → your destination → Start**. Menu wording varies by firmware.

Names accept 1–15 ASCII letters, digits, spaces, hyphens, and underscores, without leading/trailing spaces. Longer names have appeared blank on the tested printer. Old entries can take six minutes to expire.

**Receive scans automatically when the app opens** is enabled by default. Enable **Launch in the background at login** for startup without opening a window; macOS may require approval in System Settings → General → Login Items. Closing the window keeps reception active in the menu bar. Pause lasts for the current session. The app retries after network recovery and wake.

The Mac must remain powered on, logged in, and awake to receive scans.

## Scan appearance

| Mode or control | Result |
| --- | --- |
| Color | Color PDF images |
| Grayscale | 8-bit grayscale images |
| Text (B&W) | 1-bit black-and-white document images; no OCR |
| Enhance documents | Restores faint ink and adjusts paper tones |
| Density / Contrast | Adjusts darkness and tonal separation |
| Text threshold | Higher values turn more light-gray detail black |

Settings apply to app-started and panel-started scans and are remembered. Disable enhancement for photographs or faithful original tones. Default output is a 300 dpi PDF with enhancement enabled. Automatic source uses loaded feeder paper, otherwise the flatbed.

## Troubleshooting and privacy

If the destination is missing, keep the app running, check local network permission, then return to the printer's main menu and reopen its scan menu. If the port is in use, close other scan-button receivers; this app does not stop unrelated services.

For a certificate change, verify the device and choose **Forget This Printer**, then reconnect.

Settings are per user at ~/Library/Application Support/Mac Native Scan/Settings.json. Scans go to the chosen folder. No analytics or cloud upload is included. Read [SECURITY.md](SECURITY.md) for network limitations.

## Build and test

Install Xcode Command Line Tools:

~~~sh
zsh build.sh
"dist/Scan Connector for Mac.app/Contents/MacOS/Scan Connector for Mac" --self-test
~~~

MAC_NATIVE_SDK can override the SDK path. The app links only Apple system frameworks.

Python is needed only for development tests:

~~~sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python test_integration.py
~~~

38 native checks cover migration, startup policy, image output, names, UDP acknowledgement/deduplication, and parsing. Four printer-free fixture tests verify fragmented two-page color, grayscale, and 1-bit text PDFs, plus failure cleanup.

Optional real-device diagnostics:

~~~sh
"dist/Scan Connector for Mac.app/Contents/MacOS/Scan Connector for Mac" --discover
"dist/Scan Connector for Mac.app/Contents/MacOS/Scan Connector for Mac" --diagnose --host printer.local
~~~

These commands contact the selected printer. The separate --scan-test command moves the scanner and creates a file; load a test page first.

## Package and contribute

~~~sh
zsh package.sh
python3 scripts/export_source.py
python3 scripts/audit_release.py
~~~

Source export includes only reviewed project files, excluding build data, personal settings/scans, device identifiers, logs, and local Git metadata. Use your own Developer ID signing identity and Apple notarization for a public binary release; the current build is not notarized.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [THIRD_PARTY.md](THIRD_PARTY.md). GitHub Actions builds on an Apple silicon macOS runner and runs the local checks and fixture tests.

## License

Project-authored source is under [MIT](LICENSE). This license does not grant rights to third-party software, trademarks, or patents.
