# Scan Connector for Mac

An Apple silicon utility for receiving scans from an MFC-L2820DW. One window answers three questions: which printer is connected, what name this Mac advertises, and where new PDFs go.

Palette: window silver #F4F6F9, paper white #FFFFFF, graphite #182639, scanner blue #1769C2, ready teal #147D68, separator #D8DFE8. Use the native SF system typeface: 27 pt semibold title, 15 pt section titles, 13 pt controls, 12 pt supporting text. No ornamental gradients in the window.

Layout: a narrow, blue-tinted equipment rail with a scanner illustration and live state; a single main configuration column aligned left. Printer selection sits first, followed by destination name and folder. A bottom control strip starts or pauses reception. Status language distinguishes printer reachability, destination registration, and an active scan.

The initial plan used identical cards for every setting. That was revised to native form rows separated by fine rules, so the window reads like a Mac utility. The memorable visual element is a simple paper path through a scanner; everything else remains quiet. Errors include a concrete recovery action. Closing the window keeps the menu bar receiver running; Quit stops it.

For scan appearance, use one horizontal mode selector (color, gray, text), then restrained density and contrast controls. Document enhancement is a visible choice because photographs need faithful tones and receipts need strong ink. Keep startup preferences together below the scan controls; a temporary pause must not silently disable future automatic reception. The additional controls stay in the existing scrollable form, avoiding another settings window or a grid of cards.

Scope: Apple silicon, macOS 13+, no Python, Rosetta, Brother binaries, or external runtime. Native Foundation networking, ImageIO, Core Graphics, and PDFKit handle discovery, scanning, and PDF creation. Name validation uses a conservative 1–15 character ASCII limit and excludes leading or trailing spaces. An inline character count makes the limit visible before registration.
