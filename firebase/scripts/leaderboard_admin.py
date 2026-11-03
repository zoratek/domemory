#!/usr/bin/env python3
"""Manage the DoMemory leaderboard: remove fake scores and control the kill switch.

Every command previews what it would change. Nothing is written without --apply.

    # Show a player's rows and block status:
    python3 leaderboard_admin.py show UID

    # Remove a player's rows from both boards and stop them writing again:
    python3 leaderboard_admin.py block UID --apply

    # Let a player write again. Their removed scores don't come back:
    python3 leaderboard_admin.py unblock UID --apply

    # Show the kill switch:
    python3 leaderboard_admin.py config

    # Turn one platform on, for that version and later:
    python3 leaderboard_admin.py config --platform ios --enable --min-version 4.6.0 --apply

    # Turn the leaderboard off everywhere:
    python3 leaderboard_admin.py config --all-off --apply

Credentials are a Firebase service-account key, passed with --credentials or
GOOGLE_APPLICATION_CREDENTIALS. Never commit the key. Requires firebase-admin:

    pip install firebase-admin

Set FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 to run against the emulator, in which
case no credentials are needed.
"""

import argparse
import os
import re
import sys

DEFAULT_DATABASE_URL = "https://domemory-c9211.firebaseio.com"
BOARDS = ("stars", "streak")
PLATFORMS = ("ios", "android")
ROOT = "leaderboard/v1"
CONFIG_PATH = "config/leaderboard"
OFF = {"enabled": False, "minVersion": ""}


def is_valid_uid(uid):
    """Firebase keys can't hold these characters, and a slash would change the path."""
    return bool(uid) and not re.search(r"[.$#\[\]/\s]", uid)


def block_updates(uid):
    updates = {f"{ROOT}/{board}/{uid}": None for board in BOARDS}
    updates[f"{ROOT}/blocked/{uid}"] = True
    return updates


def unblock_updates(uid):
    return {f"{ROOT}/blocked/{uid}": None}


def merged_config(current, platform=None, enable=False, min_version=None, all_off=False):
    """Returns the full config, so a partial or missing one can never leave a platform on."""
    config = {name: dict(OFF) for name in PLATFORMS}
    for name in PLATFORMS:
        config[name].update((current or {}).get(name) or {})
    if all_off:
        for name in PLATFORMS:
            config[name]["enabled"] = False
    elif platform:
        config[platform]["enabled"] = enable
        if min_version is not None:
            config[platform]["minVersion"] = min_version
    return config


def connect(database_url, credentials):
    try:
        import firebase_admin
        from firebase_admin import credentials as fb_credentials, db
    except ImportError:
        sys.exit("firebase-admin isn't installed. Run: pip install firebase-admin")

    if os.environ.get("FIREBASE_DATABASE_EMULATOR_HOST"):
        firebase_admin.initialize_app(
            options={"databaseURL": "https://demo-domemory-default-rtdb.firebaseio.com"}
        )
    else:
        path = credentials or os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        if not path:
            sys.exit("No credentials. Pass --credentials or set GOOGLE_APPLICATION_CREDENTIALS.")
        firebase_admin.initialize_app(fb_credentials.Certificate(path), {"databaseURL": database_url})
    return db


def show_player(db, uid):
    for board in BOARDS:
        print(f"{board}: {db.reference(f'{ROOT}/{board}/{uid}').get()}")
    print(f"blocked: {bool(db.reference(f'{ROOT}/blocked/{uid}').get())}")


def apply_updates(db, updates, apply):
    for path, value in updates.items():
        print(f"{'delete' if value is None else 'set'} /{path}" + ("" if value is None else f" = {value}"))
    if apply:
        db.reference("/").update(updates)
        print("Applied.")
    else:
        print("Preview only. Add --apply to make this change.")


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Manage the DoMemory leaderboard.")
    parser.add_argument("--credentials", help="Path to a Firebase service-account JSON")
    parser.add_argument("--database-url", default=DEFAULT_DATABASE_URL)
    commands = parser.add_subparsers(dest="command", required=True)

    for name in ("show", "block", "unblock"):
        command = commands.add_parser(name)
        command.add_argument("uid")
        if name != "show":
            command.add_argument("--apply", action="store_true")

    config = commands.add_parser("config")
    config.add_argument("--platform", choices=PLATFORMS)
    state = config.add_mutually_exclusive_group()
    state.add_argument("--enable", action="store_true")
    state.add_argument("--disable", action="store_true")
    state.add_argument("--all-off", action="store_true")
    config.add_argument("--min-version")
    config.add_argument("--apply", action="store_true")

    args = parser.parse_args(argv)
    if hasattr(args, "uid") and not is_valid_uid(args.uid):
        parser.error(f"Invalid uid: {args.uid!r}")
    if args.command == "config":
        changing = args.enable or args.disable
        if changing and not args.platform:
            parser.error("--enable and --disable need --platform.")
        if args.all_off and (args.platform or args.min_version):
            parser.error("--all-off can't be combined with --platform or --min-version.")
        if args.enable and not args.min_version:
            parser.error("--enable needs --min-version, so older apps stay off.")
        if args.min_version and not re.fullmatch(r"\d+\.\d+\.\d+", args.min_version):
            parser.error("--min-version must look like 4.6.0.")
        if args.apply and not (changing or args.all_off):
            parser.error("Nothing to apply. Pass --enable, --disable or --all-off.")
    return args


def main(argv=None):
    args = parse_args(argv)
    db = connect(args.database_url, args.credentials)

    if args.command == "show":
        show_player(db, args.uid)
    elif args.command == "block":
        show_player(db, args.uid)
        apply_updates(db, block_updates(args.uid), args.apply)
    elif args.command == "unblock":
        apply_updates(db, unblock_updates(args.uid), args.apply)
    else:
        reference = db.reference(CONFIG_PATH)
        current = reference.get()
        print(f"current: {current}")
        if args.enable or args.disable or args.all_off:
            config = merged_config(current, args.platform, args.enable, args.min_version, args.all_off)
            print(f"new: {config}")
            if args.apply:
                reference.set(config)
                print("Applied.")
            else:
                print("Preview only. Add --apply to make this change.")


if __name__ == "__main__":
    main()
