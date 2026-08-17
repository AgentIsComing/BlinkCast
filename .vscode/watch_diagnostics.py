import os
import subprocess
import time
from pathlib import Path

ROOT = Path.cwd()

WATCH_EXTENSIONS = {
    ".swift",
    ".plist",
    ".xcconfig",
    ".entitlements",
    ".pbxproj",
}

WATCH_NAMES = {
    "project.pbxproj",
    "Package.swift",
}

IGNORE_PARTS = {
    ".git",
    ".build",
    "DerivedData",
}

DEBOUNCE_SECONDS = 1.5
POLL_INTERVAL = 0.5


def should_watch(path: Path) -> bool:
    if any(part in IGNORE_PARTS for part in path.parts):
        return False

    if path.name in WATCH_NAMES:
        return True

    if path.suffix in WATCH_EXTENSIONS:
        return True

    return False


def snapshot():
    result = {}

    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue

        if not should_watch(path):
            continue

        try:
            result[str(path)] = path.stat().st_mtime_ns
        except OSError:
            pass

    return result


def run_build():
    print("[BlinkCast Diagnostics] checking project...", flush=True)

    command = [
        "xcodebuild",
        "-project",
        "BlinkCast.xcodeproj",
        "-scheme",
        "BlinkCast",
        "-configuration",
        "Debug",
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

    if process.stdout:
        for line in process.stdout:
            print(line, end="", flush=True)

    process.wait()

    print("[BlinkCast Diagnostics] ready", flush=True)


print("[BlinkCast Diagnostics] watching", flush=True)

previous = snapshot()

run_build()

pending_change = False
last_change_time = 0.0

while True:
    time.sleep(POLL_INTERVAL)

    current = snapshot()

    if current != previous:
        previous = current
        pending_change = True
        last_change_time = time.monotonic()

    if pending_change:
        elapsed = time.monotonic() - last_change_time

        if elapsed >= DEBOUNCE_SECONDS:
            pending_change = False
            run_build()