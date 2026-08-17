#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PROJECT = ROOT / "BlinkCast.xcodeproj"
SCHEME = "BlinkCast"
CONFIGURATION = "Debug"


def run(
    command: list[str],
    capture: bool = True,
    timeout: int = 120,
) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.STDOUT if capture else None,
            text=True,
            timeout=timeout,
        )

        return completed.returncode, (
            completed.stdout.strip()
            if capture and completed.stdout
            else ""
        )

    except subprocess.TimeoutExpired:
        return 124, "Timed out"

    except Exception as error:
        return 1, str(error)


def list_physical_devices() -> list[dict]:
    code, output = run(
        [
            "xcrun",
            "devicectl",
            "list",
            "devices",
            "--json-output",
            "-",
        ]
    )

    if code != 0:
        print("Could not read physical devices:")
        print(output)
        return []

    try:
        data = json.loads(output)
    except json.JSONDecodeError:
        return []

    devices = []

    result = data.get("result", {})
    raw_devices = result.get("devices", [])

    for item in raw_devices:
        hardware = item.get("hardwareProperties", {})
        connection = item.get("connectionProperties", {})
        device_props = item.get("deviceProperties", {})

        name = device_props.get("name") or item.get("name") or "Unknown Device"
        identifier = item.get("identifier")

        platform = hardware.get("platform") or ""
        product_type = hardware.get("productType") or ""
        os_version = device_props.get("osVersionNumber") or ""
        connection_type = connection.get("transportType") or ""

        if not identifier:
            continue

        devices.append(
            {
                "kind": "physical",
                "name": name,
                "id": identifier,
                "platform": platform,
                "product_type": product_type,
                "os": os_version,
                "connection": connection_type,
            }
        )

    return devices


def list_simulators() -> list[dict]:
    code, output = run(
        [
            "xcrun",
            "simctl",
            "list",
            "devices",
            "available",
            "--json",
        ]
    )

    if code != 0:
        print("Could not read simulators:")
        print(output)
        return []

    try:
        data = json.loads(output)
    except json.JSONDecodeError:
        return []

    simulators = []

    for runtime, devices in data.get("devices", {}).items():
        for item in devices:
            if not item.get("isAvailable", False):
                continue

            name = item.get("name", "Unknown Simulator")
            udid = item.get("udid")
            state = item.get("state", "Unknown")

            if not udid:
                continue

            simulators.append(
                {
                    "kind": "simulator",
                    "name": name,
                    "id": udid,
                    "runtime": runtime,
                    "state": state,
                }
            )

    return simulators


def build_for_simulator(udid: str) -> bool:
    print()
    print("Building BlinkCast for simulator...")
    print()

    code, _ = run(
        [
            "xcodebuild",
            "-project",
            str(PROJECT),
            "-scheme",
            SCHEME,
            "-configuration",
            CONFIGURATION,
            "-destination",
            f"platform=iOS Simulator,id={udid}",
            "build",
        ],
        capture=False,
        timeout=360,
    )

    return code == 0


def build_for_device(device_id: str) -> bool:
    print()
    print("Building BlinkCast for physical device...")
    print()

    code, _ = run(
        [
            "xcodebuild",
            "-project",
            str(PROJECT),
            "-scheme",
            SCHEME,
            "-configuration",
            CONFIGURATION,
            "-destination",
            f"platform=iOS,id={device_id}",
            "-allowProvisioningUpdates",
            "build",
        ],
        capture=False,
        timeout=360,
    )

    return code == 0


def find_simulator_app() -> Path | None:
    derived = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"

    matches = sorted(
        derived.glob(
            "BlinkCast-*/Build/Products/Debug-iphonesimulator/BlinkCast.app"
        ),
        key=lambda path: path.stat().st_mtime if path.exists() else 0,
        reverse=True,
    )

    return matches[0] if matches else None


def find_device_app() -> Path | None:
    derived = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"

    matches = sorted(
        derived.glob(
            "BlinkCast-*/Build/Products/Debug-iphoneos/BlinkCast.app"
        ),
        key=lambda path: path.stat().st_mtime if path.exists() else 0,
        reverse=True,
    )

    return matches[0] if matches else None


def run_simulator(device: dict) -> None:
    udid = device["id"]

    if device.get("state") != "Booted":
        print()
        print(f"Booting {device['name']}...")

        run(
            [
                "xcrun",
                "simctl",
                "boot",
                udid,
            ]
        )

    subprocess.run(
        [
            "open",
            "-a",
            "Simulator",
        ]
    )

    if not build_for_simulator(udid):
        print()
        print("Build failed.")
        return

    app = find_simulator_app()

    if app is None:
        print("Could not find built BlinkCast.app.")
        return

    print()
    print(f"Installing {app}...")

    code, output = run(
        [
            "xcrun",
            "simctl",
            "install",
            udid,
            str(app),
        ]
    )

    if code != 0:
        print(output)
        return

    bundle_id = "JaysApps.BlinkCast"

    print()
    print("Launching BlinkCast...")

    code, output = run(
        [
            "xcrun",
            "simctl",
            "launch",
            udid,
            bundle_id,
        ]
    )

    if code != 0:
        print(output)
        return

    print()
    print("BlinkCast launched on simulator.")


def run_physical(device: dict) -> None:
    device_id = device["id"]

    if not build_for_device(device_id):
        print()
        print("Build failed.")
        return

    app = find_device_app()

    if app is None:
        print("Could not find built BlinkCast.app.")
        return

    print()
    print(f"Installing BlinkCast on {device['name']}...")

    code, output = run(
        [
            "xcrun",
            "devicectl",
            "device",
            "install",
            "app",
            "--device",
            device_id,
            str(app),
        ],
        timeout=180,
    )

    if code != 0:
        print(output)
        return

    bundle_id = "JaysApps.BlinkCast"

    print()
    print("Launching BlinkCast...")

    code, output = run(
        [
            "xcrun",
            "devicectl",
            "device",
            "process",
            "launch",
            "--device",
            device_id,
            bundle_id,
        ],
        timeout=120,
    )

    if code != 0:
        print(output)
        return

    print()
    print(f"BlinkCast launched on {device['name']}.")


def print_devices(devices: list[dict]) -> None:
    print()
    print("=" * 72)
    print("BLINKCAST DEVICE MANAGER")
    print("=" * 72)
    print()

    for index, device in enumerate(devices, start=1):
        print(f"[{index}] {device['name']}")

        if device["kind"] == "physical":
            print("    Physical device")

            if device.get("product_type"):
                print(f"    Model: {device['product_type']}")

            if device.get("os"):
                print(f"    OS: {device['os']}")

            if device.get("connection"):
                print(f"    Connection: {device['connection']}")

        else:
            print("    Simulator")
            print(f"    State: {device.get('state', 'Unknown')}")

        print()

    print("[0] Exit")
    print()


def main() -> int:
    physical = list_physical_devices()
    simulators = list_simulators()

    devices = physical + simulators

    if not devices:
        print("No Apple devices or simulators were found.")
        return 1

    print_devices(devices)

    try:
        choice = input("Choose a device: ").strip()
    except KeyboardInterrupt:
        print()
        return 0

    if choice == "0":
        return 0

    try:
        index = int(choice) - 1
    except ValueError:
        print("Invalid selection.")
        return 1

    if index < 0 or index >= len(devices):
        print("Invalid selection.")
        return 1

    selected = devices[index]

    print()
    print(f"Selected: {selected['name']}")

    if selected["kind"] == "physical":
        run_physical(selected)
    else:
        run_simulator(selected)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())