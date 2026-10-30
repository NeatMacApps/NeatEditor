#!/usr/bin/env python3
"""Local macOS channel build planning and artifact audits (Python 3.11+)."""

import argparse
import hashlib
import json
import os
import plistlib
import re
import shlex
import subprocess
import sys
from pathlib import Path

VERSION = "1"
CHANNELS = {"direct": "developer-id", "app-store": "app-store-connect"}
MACHO_MAGIC = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
    b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


class Failure(Exception):
    def __init__(self, code, message, exit_code=1, details=None):
        super().__init__(message)
        self.code = code
        self.exit_code = exit_code
        self.details = details


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise Failure("usage", message, 2)


def run(argv, cwd=None):
    result = subprocess.run(argv, cwd=cwd, stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise Failure("command_failed", f"{argv[0]} failed", details={
            "argv": argv, "exit_code": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr,
        })
    return result.stdout, result.stderr


def read_plist(path):
    with path.open("rb") as stream:
        value = plistlib.load(stream)
    if not isinstance(value, dict):
        raise Failure("invalid_plist", f"Expected a dictionary: {path}", 2)
    return value


def text_field(value, field):
    if not isinstance(value, str) or not value or "\x00" in value:
        raise Failure("invalid_config", f"{field} must be a nonempty string", 2)
    return value


def safe_child(root, value):
    relative = Path(text_field(value, "relative path"))
    path = (root / relative).resolve()
    if relative.is_absolute() or not path.is_relative_to(root):
        raise Failure("unsafe_path", f"Path escapes the config directory: {value}", 2)
    return path


def load_config(path):
    path = path.resolve(strict=True)
    config = json.loads(path.read_text())
    allowed = {"schema_version", "project", "app_name", "bundle_id", "channels"}
    if not isinstance(config, dict) or set(config) - allowed:
        raise Failure("invalid_config", "Unknown config keys or non-object config", 2)
    if type(config.get("schema_version")) is not int or config["schema_version"] != 1:
        raise Failure("invalid_config", "schema_version must be 1", 2)
    for field in ("app_name", "bundle_id", "project"):
        text_field(config.get(field), field)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._-]*", config["app_name"]):
        raise Failure("invalid_config", "app_name must be a safe bundle basename", 2)
    if not re.fullmatch(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+", config["bundle_id"]):
        raise Failure("invalid_config", "Invalid bundle_id", 2)
    if not isinstance(config.get("channels"), dict) or set(config["channels"]) != set(CHANNELS):
        raise Failure("invalid_config", "Both direct and app-store channels are required", 2)
    for channel, item in config["channels"].items():
        if not isinstance(item, dict) or set(item) != {"scheme", "export_options"}:
            raise Failure("invalid_config", f"Invalid {channel} keys", 2)
        text_field(item["scheme"], "scheme")
        if item["scheme"].startswith("-"):
            raise Failure("invalid_config", "Scheme cannot start with '-'", 2)
        safe_child(path.parent, item["export_options"])
    safe_child(path.parent, config["project"])
    return config, path.parent


def make_plan(config_path, output, channel):
    config, root = load_config(config_path)
    project = safe_child(root, config["project"])
    if not project.is_dir() or project.suffix != ".xcodeproj":
        raise Failure("not_found", f"Generate the Xcode project first: {project}", 3)
    output = output.resolve()
    if output == root or output in root.parents:
        raise Failure("unsafe_output", "Output must not be the project root or its ancestor", 2)
    channels = list(CHANNELS) if channel == "all" else [channel]
    plans = []
    for name in channels:
        item = config["channels"][name]
        options_path = safe_child(root, item["export_options"])
        options = read_plist(options_path)
        if options.get("method") != CHANNELS[name] or options.get("destination") != "export":
            raise Failure("unsafe_export", f"{name} requires method={CHANNELS[name]} and destination=export", 2)
        team = text_field(options.get("teamID"), "teamID")
        if not re.fullmatch(r"[A-Z0-9]{10}", team):
            raise Failure("invalid_team", "Replace teamID with your 10-character Apple team identifier", 2)
        directory = output / name
        archive = directory / f"{config['app_name']}.xcarchive"
        plans.append({
            "channel": name, "directory": str(directory), "archive": str(archive),
            "export": str(directory / "export"),
            "export_options_sha256": hashlib.sha256(options_path.read_bytes()).hexdigest(),
            "commands": [
                ["xcodebuild", "-project", str(project), "-scheme", item["scheme"],
                 "-configuration", "Release", "-destination", "generic/platform=macOS",
                 "-derivedDataPath", str(directory / "DerivedData"),
                 "-archivePath", str(archive), "-resultBundlePath", str(directory / "archive.xcresult"),
                 "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "archive"],
                ["xcodebuild", "-exportArchive", "-archivePath", str(archive),
                 "-exportPath", str(directory / "export"), "-exportOptionsPlist", str(options_path)],
            ],
        })
    return {"root": str(root), "bundle_id": config["bundle_id"],
            "app_name": config["app_name"], "output": str(output), "channels": plans}


def walk_error(error):
    raise error


def macho_files(app):
    found = []
    for directory, _, files in os.walk(app, followlinks=False, onerror=walk_error):
        for name in files:
            path = Path(directory) / name
            if path.is_symlink():
                continue
            with path.open("rb") as stream:
                if stream.read(4) in MACHO_MAGIC:
                    found.append(path)
    return sorted(found)


def audit(app, channel, bundle_id, stage):
    app = app.resolve(strict=True)
    info = read_plist(app / "Contents/Info.plist")
    violations = []
    if info.get("CFBundleIdentifier") != bundle_id:
        violations.append("bundle_identifier_mismatch")
    if info.get("DistributionChannel") != channel:
        violations.append("channel_marker_mismatch")
    executable_name = text_field(info.get("CFBundleExecutable"), "CFBundleExecutable")
    executable = safe_child(app / "Contents/MacOS", executable_name)
    if not executable.is_file():
        violations.append("missing_executable")
    for key in ("CFBundleVersion", "CFBundleShortVersionString"):
        text_field(info.get(key), key)
    binaries = macho_files(app)
    architectures = []
    if executable not in binaries:
        violations.append("main_executable_not_macho")
    else:
        archs, _ = run(["/usr/bin/lipo", "-archs", str(executable)])
        architectures = archs.split()
        if stage == "release" and set(architectures) != {"arm64", "x86_64"}:
            violations.append("release_not_universal")
    sparkle_resources = []
    for directory, dirs, files in os.walk(app, followlinks=False, onerror=walk_error):
        for name in dirs + files:
            if name.casefold() == "sparkle.framework" or name.startswith("org.sparkle-project."):
                sparkle_resources.append(str((Path(directory) / name).relative_to(app)))
    sparkle_links = []
    for binary in binaries:
        dependencies, _ = run(["/usr/bin/otool", "-L", str(binary)])
        relative = binary.relative_to(app)
        inside_sparkle = any(part.casefold() == "sparkle.framework" for part in relative.parts)
        if not inside_sparkle and re.search(r"Sparkle\.framework/", dependencies, re.IGNORECASE):
            sparkle_links.append(str(relative))
    if channel == "app-store":
        if sparkle_resources or sparkle_links:
            violations.append("store_contains_sparkle")
        if any(key.startswith("SU") for key in info):
            violations.append("store_contains_updater_configuration")
    elif not sparkle_resources or not sparkle_links:
        violations.append("direct_missing_sparkle")
    sandboxed = False
    for binary in binaries:
        run(["/usr/bin/codesign", "--verify", "--strict", str(binary)])
        raw, _ = run(["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(binary)])
        entitlements = plistlib.loads(raw.encode()) if raw.strip() else {}
        details_out, details_err = run(["/usr/bin/codesign", "-dv", "--verbose=2", str(binary)])
        details = details_out + details_err
        if binary == executable:
            sandboxed = entitlements.get("com.apple.security.app-sandbox") is True
        if stage == "release":
            if entitlements.get("com.apple.security.get-task-allow") is True:
                violations.append(f"debug_entitlement:{binary.relative_to(app)}")
            if channel == "direct":
                valid = "Authority=Developer ID Application:" in details
                valid = valid and "Timestamp=" in details and "runtime" in details
            else:
                valid = any(f"Authority={prefix}" in details for prefix in (
                    "Apple Distribution:", "3rd Party Mac Developer Application:",
                    "Apple Mac OS Application Signing"))
            if not valid:
                violations.append(f"wrong_release_signature:{binary.relative_to(app)}")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    if channel == "app-store" and not sandboxed:
        violations.append("store_not_sandboxed")
    result = {"app": str(app), "channel": channel, "stage": stage,
              "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
              "sandboxed": sandboxed, "architectures": architectures,
              "macho_files_checked": len(binaries),
              "sparkle_resources": sparkle_resources, "sparkle_links": sparkle_links,
              "violations": violations, "scope": "channel_policy_only",
              "not_verified": ["functional_behavior", "notarization", "app_store_acceptance"]}
    if violations:
        raise Failure("audit_failed", "Artifact violates channel policy", details=result)
    return result


def git_snapshot(root):
    commit, _ = run(["git", "-C", str(root), "rev-parse", "HEAD"])
    dirty, _ = run(["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all",
                    "--ignore-submodules=none", "--ignored=no"], cwd=root)
    if dirty:
        raise Failure("dirty_source", "Build requires clean committed source; no changes were removed", 5)
    return commit.strip()


def execute_build(plan):
    root = Path(plan["root"])
    commit = git_snapshot(root)
    output = Path(plan["output"])
    try:
        output.mkdir(parents=True, exist_ok=False)
    except FileExistsError as error:
        raise Failure("output_exists", "Choose a new output directory; existing builds are preserved", 5) from error
    receipt = {"status": "running", "source_commit": commit, "plan": plan, "results": [],
               "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    receipt_path = output / "receipt.json"

    def save():
        temporary = output / "receipt.tmp"
        temporary.write_text(json.dumps(receipt, indent=2) + "\n")
        temporary.replace(receipt_path)

    save()
    try:
        for item in plan["channels"]:
            directory = Path(item["directory"])
            directory.mkdir()
            archive_audit = None
            for index, command in enumerate(item["commands"]):
                receipt["active_channel"] = item["channel"]
                receipt["phase"] = "archive" if index == 0 else "export"
                save()
                if git_snapshot(root) != commit:
                    raise Failure("source_drift", "Source commit changed during build", 5)
                export_options = Path(item["commands"][1][-1])
                if hashlib.sha256(export_options.read_bytes()).hexdigest() != item["export_options_sha256"]:
                    raise Failure("plan_drift", "Export options changed after planning", 5)
                log = directory / ("archive.log" if index == 0 else "export.log")
                print(f"{item['channel']}: {log}", file=sys.stderr)
                with log.open("w") as stream:
                    stream.write(json.dumps(command) + "\n")
                    stream.flush()
                    result = subprocess.run(command, cwd=root, stdin=subprocess.DEVNULL,
                                            stdout=stream, stderr=subprocess.STDOUT, check=False)
                if result.returncode:
                    raise Failure("build_failed", f"Xcode failed; full diagnostics: {log}",
                                  details={"exit_code": result.returncode, "log": str(log)})
                if index == 0:
                    app = Path(item["archive"]) / "Products/Applications" / f"{plan['app_name']}.app"
                    archive_audit = audit(app, item["channel"], plan["bundle_id"], "development")
            if git_snapshot(root) != commit:
                raise Failure("source_drift", "Source changed during build", 5)
            # Store export can be a signed installer package, not a runnable .app.
            # Audit the signed archive, but never mislabel that as exported-package validation.
            exported_apps = list(Path(item["export"]).glob("*.app"))
            export_audit = None
            if item["channel"] == "direct":
                if len(exported_apps) != 1:
                    raise Failure("export_missing_app", "Expected exactly one exported direct app")
                export_audit = audit(exported_apps[0], "direct", plan["bundle_id"], "release")
            artifacts = [str(p) for p in Path(item["export"]).iterdir()]
            if not artifacts:
                raise Failure("empty_export", "Xcode export produced no artifacts")
            if item["channel"] == "app-store":
                packages = list(Path(item["export"]).glob("*.pkg"))
                if not packages and len(exported_apps) != 1:
                    raise Failure("store_export_missing", "Expected an exported store installer package or app")
                if len(exported_apps) == 1:
                    export_audit = audit(exported_apps[0], "app-store", plan["bundle_id"], "release")
            result = {"channel": item["channel"], "status": "exported", "artifacts": artifacts,
                      "archive_audit": archive_audit, "export_audit": export_audit,
                      "requires_store_validation": item["channel"] == "app-store"}
            receipt["results"].append(result)
            versions = {(r["archive_audit"]["version"], r["archive_audit"]["build"])
                        for r in receipt["results"]}
            if len(versions) > 1:
                raise Failure("version_mismatch", "Channels do not have the same version/build")
            save()
        receipt["status"] = "exported_not_published"
        save()
        return {"status": receipt["status"], "source_commit": commit, "receipt": str(receipt_path),
                "channels": receipt["results"]}
    except (Failure, OSError, KeyboardInterrupt) as error:
        receipt["status"] = "interrupted" if isinstance(error, KeyboardInterrupt) else "failed"
        receipt["error"] = str(error)
        save()
        raise


def parser():
    result = Parser(description=__doc__)
    result.add_argument("--json", action="store_true", help="Structured result (automatic without a TTY)")
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("version", help="Read-only capability/version probe")
    for name in ("plan", "build"):
        command = commands.add_parser(name, help="Read-only plan" if name == "plan" else
                                      "Local archive/export; no upload, publication or install")
        command.add_argument("--config", type=Path, required=True, help="Channel config JSON")
        command.add_argument("--out", type=Path, required=True, help="New output directory; never overwritten")
        command.add_argument("--channel", choices=[*CHANNELS, "all"], default="all")
        if name == "build":
            command.add_argument("--dry-run", action="store_true", help="Plan only; no writes or subprocesses")
    command = commands.add_parser("audit", help="Read-only built-app channel audit; not store acceptance")
    command.add_argument("--app", type=Path, required=True)
    command.add_argument("--channel", choices=CHANNELS, required=True)
    command.add_argument("--bundle-id", required=True)
    command.add_argument("--stage", choices=["development", "release"], default="release")
    return result


def main():
    machine = "--json" in sys.argv or not sys.stdout.isatty() or not sys.stdin.isatty()
    try:
        args = parser().parse_args()
        if args.command == "version":
            data = {"version": VERSION, "commands": ["version", "plan", "build", "audit"],
                    "channels": list(CHANNELS), "remote_writes": False,
                    "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
        elif args.command == "audit":
            data = audit(args.app, args.channel, args.bundle_id, args.stage)
        else:
            data = make_plan(args.config, args.out, args.channel)
            if args.command == "build" and not args.dry_run:
                data = execute_build(data)
        envelope = {"ok": True, "data": data, "error": None, "meta": {"version": VERSION}}
        code = 0
    except (Failure, OSError, ValueError, plistlib.InvalidFileException) as error:
        if isinstance(error, Failure):
            code = error.exit_code
        elif isinstance(error, FileNotFoundError):
            code = 3
        elif isinstance(error, PermissionError):
            code = 4
        else:
            code = 1
        envelope = {"ok": False, "data": None, "error": {
            "code": error.code if isinstance(error, Failure) else type(error).__name__,
            "message": str(error), "details": getattr(error, "details", None),
            "hint": "Inspect the config/artifact and retained logs; failed builds are never deleted or retried automatically.",
        }, "meta": {"version": VERSION}}
    if machine:
        print(json.dumps(envelope))
    elif code:
        print(f"{envelope['error']['code']}: {envelope['error']['message']}")
    else:
        print(f"{args.command}: OK")
        data = envelope["data"]
        if "commands" in data and args.command == "version":
            print(f"Version {data['version']}; commands: {', '.join(data['commands'])}")
        elif args.command in ("plan", "build") and "root" in data:
            for item in data["channels"]:
                print(f"{item['channel']} → {item['export']}")
                for command in item["commands"]:
                    print(f"  {shlex.join(command)}")
        elif args.command == "audit":
            print(f"{data['channel']} / {data['stage']}: {data['version']} ({data['build']})")
            print(f"Checked {data['macho_files_checked']} Mach-O files; channel policy only.")
        else:
            print(f"{data['status']}; receipt: {data['receipt']}")
    return code


if __name__ == "__main__":
    sys.exit(main())
