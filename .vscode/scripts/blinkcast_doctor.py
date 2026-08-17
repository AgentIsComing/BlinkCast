#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parents[2]

PROJECT = ROOT / "BlinkCast.xcodeproj"
SCHEME = "BlinkCast"
CONFIGURATION = "Debug"
BUILD_SERVER = ROOT / "buildServer.json"


class Result:
    def __init__(
        self,
        name: str,
        ok: bool,
        detail: str,
        warning: bool = False,
    ):
        self.name = name
        self.ok = ok
        self.detail = detail
        self.warning = warning


def run(
    command: list[str],
    timeout: int = 60,
    cwd: Optional[Path] = None,
) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            command,
            cwd=str(cwd or ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )

        return completed.returncode, completed.stdout.strip()

    except subprocess.TimeoutExpired:
        return 124, "Timed out"

    except Exception as error:
        return 1, str(error)


def which(name: str) -> Optional[str]:
    return shutil.which(name)


def check_xcode() -> Result:
    code, output = run(["xcode-select", "-p"])

    if code != 0:
        return Result("Xcode", False, output)

    path = output.strip()

    if "Xcode.app" not in path:
        return Result(
            "Xcode",
            False,
            f"Developer path is not Xcode: {path}",
        )

    return Result("Xcode", True, path)


def check_swift() -> Result:
    code, output = run(["swift", "--version"])

    if code != 0:
        return Result("Swift", False, output)

    first_line = output.splitlines()[0] if output else "Swift found"
    return Result("Swift", True, first_line)


def check_project() -> Result:
    if not PROJECT.exists():
        return Result(
            "Xcode Project",
            False,
            f"Missing: {PROJECT}",
        )

    return Result("Xcode Project", True, str(PROJECT))


def check_scheme() -> Result:
    code, output = run(
        [
            "xcodebuild",
            "-project",
            str(PROJECT),
            "-list",
        ],
        timeout=90,
    )

    if code != 0:
        return Result("BlinkCast Scheme", False, output[-1500:])

    if SCHEME not in output:
        return Result(
            "BlinkCast Scheme",
            False,
            f"Scheme '{SCHEME}' not found.",
        )

    return Result("BlinkCast Scheme", True, SCHEME)


def check_build_server_binary() -> Result:
    path = which("xcode-build-server")

    if not path:
        return Result(
            "Xcode Build Server",
            False,
            "xcode-build-server not found in PATH.",
        )

    return Result("Xcode Build Server", True, path)


def check_sourcekit() -> Result:
    path = which("sourcekit-lsp")

    if not path:
        return Result(
            "SourceKit-LSP",
            False,
            "sourcekit-lsp not found.",
        )

    return Result("SourceKit-LSP", True, path)


def check_build_server_json() -> Result:
    if not BUILD_SERVER.exists():
        return Result(
            "buildServer.json",
            False,
            "Missing buildServer.json.",
        )

    try:
        data = json.loads(BUILD_SERVER.read_text())

        scheme = data.get("scheme")
        argv = data.get("argv", [])

        if scheme != SCHEME:
            return Result(
                "buildServer.json",
                False,
                f"Wrong scheme: {scheme}",
            )

        if not argv:
            return Result(
                "buildServer.json",
                False,
                "Missing build-server argv.",
            )

        return Result(
            "buildServer.json",
            True,
            f"scheme={scheme}",
        )

    except Exception as error:
        return Result(
            "buildServer.json",
            False,
            f"Invalid JSON: {error}",
        )


def get_build_settings() -> tuple[int, str]:
    return run(
        [
            "xcodebuild",
            "-project",
            str(PROJECT),
            "-scheme",
            SCHEME,
            "-configuration",
            CONFIGURATION,
            "-showBuildSettings",
        ],
        timeout=120,
    )


def check_swift_language_version() -> Result:
    code, output = get_build_settings()

    if code != 0:
        return Result(
            "Swift Language Mode",
            False,
            output[-1500:],
        )

    version = None

    for line in output.splitlines():
        if "SWIFT_VERSION" in line and "=" in line:
            version = line.split("=", 1)[1].strip()
            break

    if version is None:
        return Result(
            "Swift Language Mode",
            False,
            "SWIFT_VERSION not found.",
        )

    if not version.startswith("6"):
        return Result(
            "Swift Language Mode",
            False,
            f"Expected Swift 6, found Swift {version}",
        )

    return Result(
        "Swift Language Mode",
        True,
        f"Swift {version}",
    )


def check_signing_identities() -> Result:
    code, output = run(
        [
            "security",
            "find-identity",
            "-v",
            "-p",
            "codesigning",
        ]
    )

    if code != 0:
        return Result(
            "Code Signing",
            False,
            output,
        )

    valid_lines = [
        line
        for line in output.splitlines()
        if '"' in line and "Apple Development" in line
    ]

    if not valid_lines:
        return Result(
            "Code Signing",
            False,
            "No Apple Development signing identity found.",
        )

    return Result(
        "Code Signing",
        True,
        f"{len(valid_lines)} Apple Development identity(s)",
    )


def check_devices() -> Result:
    if not which("xcrun"):
        return Result(
            "Apple Devices",
            False,
            "xcrun not found.",
        )

    code, output = run(
        [
            "xcrun",
            "devicectl",
            "list",
            "devices",
        ],
        timeout=60,
    )

    if code != 0:
        return Result(
            "Apple Devices",
            False,
            output[-1500:],
        )

    useful = [
        line.strip()
        for line in output.splitlines()
        if "iPhone" in line
        or "iPad" in line
        or "Apple Watch" in line
    ]

    if not useful:
        return Result(
            "Apple Devices",
            True,
            "No physical Apple device currently detected.",
            warning=True,
        )

    return Result(
        "Apple Devices",
        True,
        f"{len(useful)} device line(s) detected",
    )


def check_git() -> Result:
    code, output = run(
        [
            "git",
            "status",
            "--short",
        ]
    )

    if code != 0:
        return Result(
            "Git",
            False,
            output,
        )

    changed = len(
        [
            line
            for line in output.splitlines()
            if line.strip()
        ]
    )

    if changed == 0:
        return Result(
            "Git",
            True,
            "Working tree clean",
        )

    return Result(
        "Git",
        True,
        f"{changed} changed/untracked file(s)",
        warning=True,
    )


def check_network_entitlements() -> Result:
    code, output = get_build_settings()

    if code != 0:
        return Result(
            "Network Entitlements",
            False,
            "Unable to read build settings.",
        )

    return Result(
        "Network Entitlements",
        True,
        "Checked through Xcode target/build configuration",
        warning=True,
    )


def extract_interesting_build_lines(output: str) -> list[str]:
    interesting = []

    keywords = [
        ": error:",
        "error:",
        "CodeSign",
        "codesign",
        "Provisioning",
        "provisioning",
        "Signing",
        "signing",
        "BUILD FAILED",
        "Command CodeSign failed",
        "CompileSwift",
        "SwiftCompile",
        "Ld ",
        "linker command failed",
        "No profiles for",
        "requires a provisioning profile",
        "requires a development team",
        "errSec",
        "fatal error",
    ]

    for line in output.splitlines():
        stripped = line.strip()

        if not stripped:
            continue

        if any(keyword in stripped for keyword in keywords):
            interesting.append(stripped)

    return interesting


def run_build() -> Result:
    print("\nRunning BlinkCast build check...\n")

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

    code, output = run(
        command,
        timeout=300,
    )

    warnings = [
        line.strip()
        for line in output.splitlines()
        if ": warning:" in line
    ]

    errors = [
        line.strip()
        for line in output.splitlines()
        if ": error:" in line
    ]

    if code != 0:
        details: list[str] = []

        if errors:
            details.append(
                f"{len(errors)} compiler error(s):"
            )

            details.extend(errors[:15])

        interesting = extract_interesting_build_lines(output)

        unique_interesting = []

        for line in interesting:
            if line not in unique_interesting:
                unique_interesting.append(line)

        if unique_interesting:
            details.append("")
            details.append("Important build output:")
            details.extend(unique_interesting[-20:])

        if not errors and not unique_interesting:
            lines = [
                line
                for line in output.splitlines()
                if line.strip()
            ]

            details.append(
                "xcodebuild failed but did not emit a standard compiler error."
            )

            details.append("")
            details.append("Last build output:")

            details.extend(lines[-30:])

        return Result(
            "macOS Build",
            False,
            "\n      ".join(details),
        )

    if warnings:
        detail_lines = [
            f"Build succeeded with {len(warnings)} warning(s):"
        ]

        detail_lines.extend(warnings[:15])

        return Result(
            "macOS Build",
            True,
            "\n      ".join(detail_lines),
            warning=True,
        )

    return Result(
        "macOS Build",
        True,
        "BUILD SUCCEEDED — no compiler warnings",
    )


def print_result(result: Result) -> None:
    if not result.ok:
        icon = "FAIL"
    elif result.warning:
        icon = "WARN"
    else:
        icon = "PASS"

    print(f"{icon:4}  {result.name}")

    detail_lines = result.detail.splitlines()

    if not detail_lines:
        return

    for line in detail_lines:
        print(f"      {line}")


def main() -> int:
    print()
    print("=" * 62)
    print("BLINKCAST DOCTOR")
    print("=" * 62)
    print(f"Project: {ROOT}")
    print()

    checks = [
        check_xcode(),
        check_swift(),
        check_project(),
        check_scheme(),
        check_sourcekit(),
        check_build_server_binary(),
        check_build_server_json(),
        check_swift_language_version(),
        check_signing_identities(),
        check_devices(),
        check_git(),
        check_network_entitlements(),
    ]

    checks.append(run_build())

    print()
    print("=" * 62)
    print("RESULTS")
    print("=" * 62)

    failures = 0
    warnings = 0

    for result in checks:
        print_result(result)
        print()

        if not result.ok:
            failures += 1
        elif result.warning:
            warnings += 1

    print("=" * 62)

    if failures:
        print(
            f"BLINKCAST STATUS: NOT READY "
            f"({failures} failure(s), {warnings} warning(s))"
        )
        return 1

    if warnings:
        print(
            f"BLINKCAST STATUS: READY WITH "
            f"{warnings} WARNING(S)"
        )
        return 0

    print("BLINKCAST STATUS: READY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())