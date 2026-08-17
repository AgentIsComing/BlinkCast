#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(
    command: list[str],
    capture: bool = True,
) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.STDOUT if capture else None,
            text=True,
        )

        output = ""
        if capture and completed.stdout:
            output = completed.stdout.strip()

        return completed.returncode, output

    except Exception as error:
        return 1, str(error)


def ensure_git_repo() -> bool:
    code, _ = run(
        [
            "git",
            "rev-parse",
            "--is-inside-work-tree",
        ]
    )

    return code == 0


def current_branch() -> str:
    code, output = run(
        [
            "git",
            "branch",
            "--show-current",
        ]
    )

    if code != 0 or not output:
        return "unknown"

    return output


def get_status() -> str:
    code, output = run(
        [
            "git",
            "status",
            "--short",
        ]
    )

    if code != 0:
        return ""

    return output


def create_checkpoint(message: str | None = None) -> int:
    status = get_status()

    if not status:
        print()
        print("Nothing changed. No checkpoint needed.")
        return 0

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if not message:
        message = f"BlinkCast checkpoint - {timestamp}"

    print()
    print("=" * 70)
    print("BLINKCAST CHECKPOINT")
    print("=" * 70)
    print(f"Branch: {current_branch()}")
    print()
    print("Changes:")
    print(status)
    print()

    code, output = run(["git", "add", "-A"])

    if code != 0:
        print("Failed to stage changes:")
        print(output)
        return 1

    code, output = run(
        [
            "git",
            "commit",
            "-m",
            message,
        ]
    )

    if code != 0:
        print("Checkpoint commit failed:")
        print(output)
        return 1

    print(output)

    code, sha = run(
        [
            "git",
            "rev-parse",
            "--short",
            "HEAD",
        ]
    )

    print()
    print("=" * 70)
    print("CHECKPOINT CREATED")
    print("=" * 70)

    if code == 0:
        print(f"Commit: {sha}")

    print(f"Message: {message}")
    print()

    return 0


def list_recent_checkpoints() -> int:
    code, output = run(
        [
            "git",
            "log",
            "--oneline",
            "--decorate",
            "-15",
        ]
    )

    if code != 0:
        print(output)
        return 1

    print()
    print("=" * 70)
    print("RECENT BLINKCAST COMMITS")
    print("=" * 70)
    print()
    print(output)
    print()

    return 0


def show_status() -> int:
    status = get_status()

    print()
    print("=" * 70)
    print("BLINKCAST GIT STATUS")
    print("=" * 70)
    print()
    print(f"Branch: {current_branch()}")
    print()

    if not status:
        print("Working tree is clean.")
    else:
        print(status)

    print()
    return 0


def main() -> int:
    if not ensure_git_repo():
        print("BlinkCast is not currently inside a Git repository.")
        return 1

    if len(sys.argv) > 1:
        command = sys.argv[1].lower()

        if command == "create":
            message = " ".join(sys.argv[2:]).strip() or None
            return create_checkpoint(message)

        if command == "list":
            return list_recent_checkpoints()

        if command == "status":
            return show_status()

    print()
    print("=" * 70)
    print("BLINKCAST CHECKPOINT MANAGER")
    print("=" * 70)
    print()
    print("[1] Create checkpoint")
    print("[2] Show Git status")
    print("[3] Show recent commits")
    print("[0] Exit")
    print()

    choice = input("Choose an option: ").strip()

    if choice == "0":
        return 0

    if choice == "1":
        message = input(
            "Checkpoint message "
            "(press Enter for automatic message): "
        ).strip()

        return create_checkpoint(message or None)

    if choice == "2":
        return show_status()

    if choice == "3":
        return list_recent_checkpoints()

    print("Invalid selection.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())