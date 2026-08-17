#!/usr/bin/env python3

from __future__ import annotations

import re
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP_NAME = "BlinkCast"

IGNORE_SUBSYSTEMS = {
    "com.apple.defaults",
    "com.apple.launchservices",
    "com.apple.cfpasteboard",
    "com.apple.hiservices",
    "com.apple.appkit",
    "com.apple.corespotlight",
    "com.apple.coreservices",
    "com.apple.appleevents",
}

IGNORE_PHRASES = [
    "found no value for key",
    "looked up value",
    "managed preferences are disabled",
    "setting {",
    "loaded: an empty base plist",
    "getting plist hint",
    "got plist data",
    "creating default menu item",
    "claimanysandboxannotationsinappleevent",
    "_aecopysandboxstatefortoken",
    "copyentitlementandsandboxstatusfromcacheorserverfortoken",
    "_aecopyentitlementfortoken",
    "couldn't find \"com.apple.private.corespotlight",
    "couldn't find \"com.apple.corespotlight",
    "couldn't find the \"com.apple.corespotlight",
    "copydata(",
    "cursoriscustomized",
    "increasecontrast",
    "nsglassdiffusionsetting",
    "appledefaultasciiinputsource",
    "appleenabledhandwritinglanguages",
    "appleironwoodallowed",
    "appledictationautoenable",
    "tisromanswitchstate",
    "tsmtimelog",
    "tsmtrace",

    # Normal Apple framework chatter
    "failed to copy the syscfgdict mg key with error: 0",
]

IGNORE_PROCESS_TEXT = [
    "libmobilegestalt.dylib",
]

RULES: list[tuple[str, list[str]]] = [
    (
        "CRASH",
        [
            "fatal error",
            "uncaught exception",
            "terminating app due to uncaught",
            "segmentation fault",
            "abort trap",
            "crashed",
            "signal 11",
            "signal 6",
        ],
    ),
    (
        "SWIFT",
        [
            "swift runtime failure",
            "unexpectedly found nil",
            "precondition failed",
            "assertion failed",
            "fatalerror",
        ],
    ),
    (
        "WEBRTC",
        [
            "rtcpeerconnection",
            "iceconnectionstate",
            "ice candidate",
            "ice gathering",
            "stun server",
            "turn server",
            "webrtc error",
            "setremotedescription failed",
            "setlocaldescription failed",
            "createoffer failed",
            "createanswer failed",
        ],
    ),
    (
        "WEBSOCKET",
        [
            "websocket failed",
            "web socket failed",
            "urlsessionwebsockettask",
            "websocket error",
            "connection closed",
            "broadcast-ended",
        ],
    ),
    (
        "NETWORK",
        [
            "nsurlerrordomain",
            "could not resolve host",
            "hostname could not be found",
            "dns lookup failed",
            "connection refused",
            "network is unreachable",
            "connection timed out",
            "connection reset",
            "nw_connection_copy_connected",
            "nw_error",
        ],
    ),
    (
        "SANDBOX",
        [
            "sandbox: deny",
            "sandbox violation",
            "operation not permitted",
            "permission denied",
            "missing entitlement",
            "requires entitlement",
        ],
    ),
    (
        "SIGNING",
        [
            "errsecinternalcomponent",
            "codesign failed",
            "code signing failed",
            "signature invalid",
            "provisioning profile",
            "signing certificate",
        ],
    ),
    (
        "CAPTURE",
        [
            "screencapturekit error",
            "scstream error",
            "screen recording permission",
            "screen capture permission denied",
            "failed to capture display",
            "failed to capture window",
        ],
    ),
    (
        "DEVICE",
        [
            "device disconnected",
            "developer mode disabled",
            "device is locked",
            "failed to install application",
            "failed to launch application",
        ],
    ),
    (
        "WARNING",
        [
            " warning:",
        ],
    ),
]


def normalize(text: str) -> str:
    return " ".join(text.strip().split())


def extract_subsystem(line: str) -> str | None:
    match = re.search(r"\[([^\]]+):[^\]]+\]", line)

    if not match:
        return None

    return match.group(1).lower()


def should_ignore(line: str) -> bool:
    lower = line.lower()

    if not lower.strip():
        return True

    if any(text in lower for text in IGNORE_PROCESS_TEXT):
        # Keep only obviously serious events from these Apple internals.
        serious = [
            "fatal",
            "crash",
            "exception",
            "abort",
        ]

        if not any(term in lower for term in serious):
            return True

    subsystem = extract_subsystem(line)

    if subsystem and subsystem in IGNORE_SUBSYSTEMS:
        serious_terms = [
            "fatal",
            "crash",
            "sandbox: deny",
            "permission denied",
            "operation not permitted",
            "uncaught exception",
        ]

        if not any(term in lower for term in serious_terms):
            return True

    if any(phrase in lower for phrase in IGNORE_PHRASES):
        return True

    # "error: 0" generally means success/no error.
    if re.search(r"\berror:\s*0\b", lower):
        return True

    return False


def classify(line: str) -> str | None:
    lower = f" {line.lower()} "

    for category, terms in RULES:
        if any(term in lower for term in terms):
            return category

    # Generic error handling — deliberately strict.
    if re.search(r"\berror:\s*(?!0\b)", lower):
        return "ERROR"

    if " failed " in lower:
        # Only accept generic failed lines if they aren't harmless
        # Apple internal/debug status messages.
        if "com.apple." not in lower and "libmobilegestalt" not in lower:
            return "ERROR"

    return None


def severity(category: str) -> str:
    if category in {
        "CRASH",
        "SWIFT",
        "SIGNING",
        "ERROR",
    }:
        return "ERROR"

    if category == "WARNING":
        return "WARNING"

    return "EVENT"


def print_event(category: str, line: str) -> None:
    timestamp = datetime.now().strftime("%H:%M:%S")

    print()
    print("=" * 78)
    print(f"[{timestamp}] [{severity(category)}] [{category}]")
    print("-" * 78)
    print(normalize(line))
    print("=" * 78)
    print()


def build_predicate() -> str:
    return (
        f'process == "{APP_NAME}" '
        f'OR senderImagePath ENDSWITH "/{APP_NAME}"'
    )


def start_log_stream() -> subprocess.Popen[str]:
    command = [
        "log",
        "stream",
        "--style",
        "compact",
        "--level",
        "info",
        "--predicate",
        build_predicate(),
    ]

    return subprocess.Popen(
        command,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )


def main() -> None:
    print()
    print("=" * 78)
    print("BLINKCAST SMART RUNTIME MONITOR")
    print("=" * 78)
    print(f"Project: {ROOT}")
    print(f"Process: {APP_NAME}")
    print()
    print("Watching for real BlinkCast problems:")
    print("  crashes")
    print("  Swift runtime failures")
    print("  WebRTC / ICE / STUN / TURN")
    print("  WebSocket failures")
    print("  network / DNS failures")
    print("  sandbox denials")
    print("  screen capture failures")
    print("  signing failures")
    print("  device failures")
    print()
    print("Normal macOS framework/debug noise is hidden.")
    print("Press Ctrl+C to stop.")
    print("=" * 78)
    print()

    process = start_log_stream()

    try:
        if process.stdout is None:
            raise RuntimeError("Could not read macOS log stream.")

        for raw_line in process.stdout:
            line = raw_line.rstrip()

            if should_ignore(line):
                continue

            category = classify(line)

            if category:
                print_event(category, line)

    except KeyboardInterrupt:
        print()
        print("[BlinkCast Logs] stopping...")

    finally:
        process.terminate()

        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()

    print("[BlinkCast Logs] stopped.")


if __name__ == "__main__":
    main()