#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PROJECT = ROOT / "BlinkCast.xcodeproj"
SCHEME = "BlinkCast"
CONFIGURATION = "Debug"

WATCH_EXTENSIONS = {
    ".swift",
    ".plist",
    ".xcconfig",
    ".entitlements",
    ".pbxproj",
    ".json",
}

WATCH_NAMES = {
    "project.pbxproj",
    "Package.swift",
    "Package.resolved",
    "buildServer.json",
}

IGNORE_PARTS = {
    ".git",
    ".build",
    "DerivedData",
    ".swiftpm",
}

POLL_INTERVAL = 0.5
DEBOUNCE_SECONDS = 1.5


def should_watch(path: Path) -> bool:
    if any(part in IGNORE_PARTS for part in path.parts):
        return False

    if path.name in WATCH_NAMES:
        return True

    return path.suffix.lower() in WATCH_EXTENSIONS


def snapshot() -> dict[str, int]:
    files: dict[str, int] = {}

    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue

        if not should_watch(path):
            continue

        try:
            files[str(path)] = path.stat().st_mtime_ns
        except OSError:
            pass

    return files


def classify_line(line: str) -> str | None:
    lower = line.lower()

    # Swift/compiler errors
    if ": error:" in lower:
        return "SWIFT"

    # Compiler warnings
    if ": warning:" in lower:
        return "WARNING"

    # Actual signing failures only
    signing_failure_terms = [
        "errsecinternalcomponent",
        "command codesign failed",
        "codesign failed",
        "code signing is required",
        "code signing error",
        "no signing certificate",
        "no profiles for",
        "requires a provisioning profile",
        "requires a development team",
        "provisioning profile",
        "signing certificate",
        "doesn't include signing certificate",
        "does not include signing certificate",
    ]

    if any(term in lower for term in signing_failure_terms):
        return "SIGNING"

    # Linker
    if "linker command failed" in lower:
        return "LINKER"

    if lower.startswith("ld:") or " ld: " in lower:
        return "LINKER"

    # Networking/runtime-ish text if it ever appears in build output
    if "nsurlerror" in lower:
        return "NETWORK"

    if "websocket error" in lower or "web socket error" in lower:
        return "WEBSOCKET"

    if "webrtc error" in lower or "ice candidate error" in lower:
        return "WEBRTC"

    # Device-related actual failures
    device_failure_terms = [
        "device not found",
        "unable to find a destination",
        "failed to locate device",
        "device is locked",
        "developer mode is disabled",
    ]

    if any(term in lower for term in device_failure_terms):
        return "DEVICE"

    # Overall build failure
    if "** build failed **" in lower:
        return "BUILD"

    return None


def run_build() -> None:
    print()
    print("=" * 70)
    print("[BlinkCast Diagnostics] Checking whole project...")
    print("=" * 70)
    print()

    command = [
        "xcodebuild",
        "-project",
        str(PROJECT),
        "-scheme",
        SCHEME,
        "-configuration",
        CONFIGURATION,
        "-destination",
        "platform=macOS",
        "build",
    ]

    process = subprocess.Popen(
        command,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    warnings: list[str] = []
    errors: list[str] = []
    categories: dict[str, list[str]] = {}

    if process.stdout:
        for raw_line in process.stdout:
            line = raw_line.rstrip()

            category = classify_line(line)

            if category:
                categories.setdefault(category, []).append(line)

            if ": warning:" in line.lower():
                warnings.append(line)

            if ": error:" in line.lower():
                errors.append(line)

            print(raw_line, end="", flush=True)

    return_code = process.wait()

    print()
    print("=" * 70)

    if return_code == 0:
        if warnings:
            print(
                f"[BlinkCast Diagnostics] READY WITH "
                f"{len(warnings)} WARNING(S)"
            )
        else:
            print("[BlinkCast Diagnostics] READY — NO BUILD PROBLEMS")
    else:
        print("[BlinkCast Diagnostics] BUILD FAILED")

    print("=" * 70)

    real_categories = {
        key: value
        for key, value in categories.items()
        if value
    }

    if real_categories:
        print()
        print("Problem Summary")
        print("-" * 70)

        preferred_order = [
            "SWIFT",
            "SIGNING",
            "LINKER",
            "NETWORK",
            "WEBSOCKET",
            "WEBRTC",
            "DEVICE",
            "WARNING",
            "BUILD",
        ]

        for category in preferred_order:
            lines = real_categories.get(category)

            if not lines:
                continue

            print()
            print(f"[{category}]")

            seen: set[str] = set()

            for line in lines:
                if line in seen:
                    continue

                seen.add(line)
                print(line)

    else:
        print()
        print("Problem Summary")
        print("-" * 70)
        print("No errors or warnings detected.")

    print()
    print("[BlinkCast Diagnostics] waiting for changes...")
    print()


def main() -> None:
    print()
    print("=" * 70)
    print("BLINKCAST CONTINUOUS DIAGNOSTICS")
    print("=" * 70)
    print(f"Project: {ROOT}")
    print(f"Scheme:  {SCHEME}")
    print()
    print("Watching:")
    print("  Swift files")
    print("  Xcode project files")
    print("  Entitlements")
    print("  plist/config files")
    print()
    print(f"Change debounce: {DEBOUNCE_SECONDS:.1f} seconds")
    print()
    print("Press Ctrl+C to stop.")
    print("=" * 70)
    print()

    previous = snapshot()

    run_build()

    pending_change = False
    last_change_time = 0.0

    try:
        while True:
            time.sleep(POLL_INTERVAL)

            current = snapshot()

            if current != previous:
                previous = current
                pending_change = True
                last_change_time = time.monotonic()

                print(
                    "[BlinkCast Diagnostics] change detected...",
                    flush=True,
                )

            if pending_change:
                elapsed = time.monotonic() - last_change_time

                if elapsed >= DEBOUNCE_SECONDS:
                    pending_change = False
                    run_build()

    except KeyboardInterrupt:
        print()
        print()
        print("[BlinkCast Diagnostics] stopped.")


if __name__ == "__main__":
    main()