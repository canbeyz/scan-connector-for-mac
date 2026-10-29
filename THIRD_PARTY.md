# Dependencies

The app links Apple system frameworks: SwiftUI, AppKit, Foundation, Network, CryptoKit, Security, ServiceManagement, CoreGraphics, ImageIO, and PDFKit. They are supplied by macOS and retain Apple's terms.

Icon.swift draws the app icon. SF Symbols are requested from macOS at runtime.

Development-only tests import separately installed [Pillow](https://github.com/python-pillow/Pillow/blob/main/LICENSE) and [pypdf](https://github.com/py-pdf/pypdf/blob/main/LICENSE). Their licenses and transitive-component terms remain applicable. Neither package is bundled in the app or source export. requirements-dev.txt records the tested versions.

The CI workflow uses actions/checkout and actions/setup-python through GitHub; those are not app dependencies or bundled implementation source.
