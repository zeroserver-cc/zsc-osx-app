#!/bin/sh
# Runs this project's unit tests. There is no `.testTarget` in Package.swift
# — see its header comment for why (this machine's Xcode Command Line Tools
# ship neither XCTest nor a working swift-testing setup; getting either
# working here would require baking CLT-version-specific absolute paths
# into the manifest, which breaks on any other machine).
#
# Instead: this script compiles the real production source files under
# Sources/ZeroServerControl/{Account,Remote,Model}/ directly together with
# the hand-rolled test drivers in Scripts/tests/ (plain swiftc, one
# executable, no test framework at all) and runs the result. This is the
# same technique used for ad-hoc verification throughout this project's
# development — formalized here into a repeatable regression gate.
#
# Deliberately excludes Sources/ZeroServerControl/{UI,Controller,Login}/ and
# the App entry point — those need SwiftUI/AppKit/MenuBarExtra and are
# exercised by manual app testing (see CLAUDE.md), not by this script.
set -eu

cd "$(dirname "$0")/.."

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

echo "==> Compiling test binary"
swiftc \
  Sources/ZeroServerControl/Account/APIEnvironment.swift \
  Sources/ZeroServerControl/Account/GraphQLClient.swift \
  Sources/ZeroServerControl/Account/APIClient.swift \
  Sources/ZeroServerControl/Account/CredentialStore.swift \
  Sources/ZeroServerControl/Account/AccountSession.swift \
  Sources/ZeroServerControl/Remote/RemoteNodesController.swift \
  Sources/ZeroServerControl/Model/AccountModels.swift \
  Sources/ZeroServerControl/Model/RemoteNode.swift \
  Scripts/tests/TestSupport.swift \
  Scripts/tests/MockURLProtocol.swift \
  Scripts/tests/GraphQLClientTests.swift \
  Scripts/tests/APIClientTests.swift \
  Scripts/tests/CredentialStoreTests.swift \
  Scripts/tests/APIEnvironmentTests.swift \
  Scripts/tests/ModelDecodingTests.swift \
  Scripts/tests/RemoteNodeActionLogicTests.swift \
  Scripts/tests/RemoteNodesControllerTests.swift \
  Scripts/tests/main.swift \
  -o "$SCRATCH/zsc-control-tests"

echo "==> Running tests"
# Isolates CredentialStore's Keychain entry from the real one the shipped
# app uses — see CredentialStore.swift's comment on this env var for why
# this isn't optional (an unsigned test binary can collide with, but not
# properly manage, a signed app's real Keychain item).
ZSC_CONTROL_TEST_KEYCHAIN_SERVICE="cc.zeroserver.control.account.test-harness" "$SCRATCH/zsc-control-tests"
