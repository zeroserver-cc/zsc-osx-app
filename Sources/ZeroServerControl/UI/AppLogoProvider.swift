import AppKit
import SwiftUI

/// Loads the full-color brand logo (see Scripts/generate-icons.sh) shown at
/// the top of LoginView. Unlike MenuBarIconProvider's glyphs, this is never
/// marked `isTemplate` — the green/black brand mark should render as-is.
enum AppLogoProvider {
    static var image: Image {
        Image(nsImage: loadImage())
    }

    private static func loadImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        if let rep1x = loadRepresentation(named: "AppLogo") {
            image.addRepresentation(rep1x)
        }
        if let rep2x = loadRepresentation(named: "AppLogo@2x") {
            image.addRepresentation(rep2x)
        }
        return image
    }

    /// Same two-route lookup as MenuBarIconProvider.loadRepresentation:
    /// Contents/Resources/Logo (where build-app-bundle.sh copies these
    /// PNGs as plain files for the packaged .app) first, then Bundle.module
    /// (the SPM resource bundle used by `swift run` during development).
    private static func loadRepresentation(named name: String) -> NSImageRep? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Logo"),
           let rep = NSImage(contentsOf: url)?.representations.first {
            return rep
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Logo"),
           let rep = NSImage(contentsOf: url)?.representations.first {
            return rep
        }
        return nil
    }
}
