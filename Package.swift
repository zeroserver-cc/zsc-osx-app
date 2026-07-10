// swift-tools-version: 5.10
//
// This is a Swift Package Manager project rather than a traditional Xcode
// project (.xcodeproj). That's a deliberate choice, not a shortcut: SPM
// builds and runs today with just the Xcode Command Line Tools (`swift
// build`, `swift run`), and you can still open this folder directly in
// Xcode later (File > Open... on this file) to get full editing, debugging,
// and code-signing support. See CLAUDE.md for the full rationale.
//
// No `.testTarget` here — this machine has only the Xcode Command Line
// Tools, which ship neither XCTest.framework at all, nor a working
// swift-testing setup (its Testing.framework needs three separate
// hand-added linker/plugin search paths just to compile, and even after
// all of them resolve, the test bundle silently discovers zero tests at
// runtime — a CLT-only toolchain limitation, not something fixable from
// this package's manifest). Baking those CLT-version-specific absolute
// paths into unsafeFlags would also make the manifest non-portable to any
// other machine or CI, defeating the point of staying CLT-only. See
// Scripts/run-tests.sh for how this project is actually tested instead:
// plain swiftc-compiled assertion-based test drivers, no test framework
// dependency at all. If you install full Xcode.app, a proper .testTarget
// becomes straightforward to add — it was not the manifest that was
// missing, it was a fully-working Testing.framework.
import PackageDescription

let package = Package(
    name: "ZeroServerControl",

    // Required before SPM will recognize Resources/<lang>.lproj folders as
    // localizations at all (rather than treating them as opaque directory
    // resources). English is the base/fallback for any system language
    // without its own translation.
    defaultLocalization: "en",

    // MenuBarExtra (the SwiftUI API this app is built on) requires macOS 13
    // (Ventura). Do not lower this without checking every call site that
    // assumes macOS 13+ availability.
    platforms: [.macOS(.v13)],

    products: [
        .executable(name: "ZeroServerControl", targets: ["ZeroServerControl"])
    ],

    targets: [
        .executableTarget(
            name: "ZeroServerControl",
            resources: [
                // These become part of the SPM-generated resource bundle,
                // loaded at runtime via `Bundle.module`. See
                // MenuBarIconProvider.swift/AppLogoProvider.swift for how
                // they're read.
                .copy("Resources/MenuBarIcon"),
                .copy("Resources/Logo"),
                // .process() (not .copy()) is what makes SPM compile these
                // as real localizations. Text/String(localized:) resolve
                // against Bundle.main in the packaged .app, not
                // Bundle.module — see Scripts/build-app-bundle.sh for the
                // copy step that puts the compiled .lproj folders where
                // Bundle.main actually looks.
                .process("Resources/en.lproj"),
                .process("Resources/pt-BR.lproj")
            ]
        )
    ]
)
