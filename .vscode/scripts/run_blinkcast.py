#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PROJECT = ROOT / "BlinkCast.xcodeproj"
SCHEME = "BlinkCast"
CONFIGURATION = "Debug"

DOCTOR = ROOT / ".vscode" / "scripts" / "blinkcast_doctor.py"
LOG_MONITOR = ROOT / ".vscode" / "scripts" / "log_monitor.py"


def run(command: list[str], timeout: int | None = None) -> int:
    process = subprocess.Popen(
        command,
        cwd=ROOT,
    )

    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        return 124


def run_doctor() -> bool:
    print()
    print("=" * 72)
    print("BLINKCAST PRE-FLIGHT CHECK")
    print("=" * 72)

    result = run(
        ["python3", str(DOCTOR)],
        timeout=360,
    )

    if result != 0:
        print()
        print("[BlinkCast] Doctor found a problem.")
        print("[BlinkCast] Launch cancelled.")
        return False

    return True


def build_mac() -> bool:
    print()
    print("=" * 72)
    print("BUILDING BLINKCAST FOR macOS")
    print("=" * 72)
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

    result = run(command, timeout=360)

    if result != 0:
        print()
        print("[BlinkCast] Build failed.")
        return False

    print()
    print("[BlinkCast] Build succeeded.")
    return True


def find_mac_app() -> Path | None:
    derived_data = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"

    matches = sorted(
        derived_data.glob(
            "BlinkCast-*/Build/Products/Debug/BlinkCast.app"
        ),
        key=lambda path: path.stat().st_mtime if path.exists() else 0,
        reverse=True,
    )

    if not matches:
        return None

    return matches[0]


def launch_mac() -> bool:
    app = find_mac_app()

    if app is None:
        print()
        print("[BlinkCast] Could not find BlinkCast.app.")
        return False

    print()
    print("=" * 72)
    print("LAUNCHING BLINKCAST")
    print("=" * 72)
    print(f"App: {app}")
    print()

    result = subprocess.run(
        ["open", str(app)],
        cwd=ROOT,
    )

    if result.returncode != 0:
        print("[BlinkCast] Launch failed.")
        return False

    print("[BlinkCast] App launched.")
    return True


def start_log_monitor() -> subprocess.Popen[str]:
    print()
    print("=" * 72)
    print("STARTING SMART RUNTIME MONITOR")
    print("=" * 72)
    print()

    process = subprocess.Popen(
        ["python3", str(LOG_MONITOR)],
        cwd=ROOT,
    )

    return process


def main() -> int:
    print()
    print("=" * 72)
    print("BLINKCAST DEVELOPMENT LAUNCHER")
    print("=" * 72)
    print(f"Project: {ROOT}")
    print()

    if not DOCTOR.exists():
        print(f"Missing: {DOCTOR}")
        return 1

    if not LOG_MONITOR.exists():
        print(f"Missing: {LOG_MONITOR}")
        return 1

    if not run_doctor():
        return 1

    if not build_mac():
        return 1

    monitor = start_log_monitor()

    # Give log stream a moment to initialize before launching the app.
    time.sleep(1)

    if not launch_mac():
        monitor.terminate()
        return 1

    print()
    print("=" * 72)
    print("BLINKCAST IS RUNNING")
    print("=" * 72)
    print()
    print("The runtime monitor is active.")
    print("Close BlinkCast normally when finished.")
    print("Press Ctrl+C here to stop monitoring.")
    print()

    try:
        while True:
            time.sleep(1)

            if monitor.poll() is not None:
                print()
                print("[BlinkCast] Runtime monitor stopped.")
                break

    except KeyboardInterrupt:
        print()
        print("[BlinkCast] Stopping development session...")

    finally:
        if monitor.poll() is None:
            monitor.terminate()

            try:
                monitor.wait(timeout=3)
            except subprocess.TimeoutExpired:
                monitor.kill()

    print("[BlinkCast] Development session ended.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())