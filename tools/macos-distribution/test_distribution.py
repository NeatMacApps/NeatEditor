"""Hermetic contract tests; no Xcode execution, credentials, or user data."""

import importlib.util
import io
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("distribution", Path(__file__).with_name("distribution.py"))
d = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(d)


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="distribution-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "Example.xcodeproj").mkdir()
        self.config = {"schema_version": 1, "app_name": "Example", "bundle_id": "com.example.App",
                       "project": "Example.xcodeproj", "channels": {}}
        for name, method in d.CHANNELS.items():
            options = self.root / f"{name}.plist"
            options.write_bytes(plistlib.dumps({"method": method, "destination": "export", "teamID": "TESTTEAMID"}))
            self.config["channels"][name] = {"scheme": f"Example-{name}", "export_options": options.name}
        self.config_path = self.root / "distribution.json"
        self.save_config()

    def save_config(self):
        self.config_path.write_text(json.dumps(self.config))

    def plan(self, channel="all"):
        return d.make_plan(self.config_path, self.root / "new-output", channel)

    def cli(self, *args):
        result = subprocess.run([sys.executable, str(Path(d.__file__)), *args],
                                capture_output=True, text=True, check=False, stdin=subprocess.DEVNULL)
        return result, json.loads(result.stdout)

    def make_app(self, channel="app-store"):
        app = self.root / "Example.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        info = {"CFBundleIdentifier": "com.example.App", "CFBundleExecutable": "Example",
                "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1",
                "DistributionChannel": channel}
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        (contents / "MacOS/Example").write_bytes(b"\xcf\xfa\xed\xfe" + b"fixture")
        return app

    def fake_native(self, sandboxed=True, linked=False, debug=False):
        def implementation(argv, cwd=None):
            if argv[0].endswith("otool"):
                return ("Example:\n\t@rpath/Sparkle.framework/Versions/B/Sparkle\n" if linked else "Example:\n"), ""
            if "--entitlements" in argv:
                return plistlib.dumps({"com.apple.security.app-sandbox": sandboxed,
                                       "com.apple.security.get-task-allow": debug}).decode(), ""
            if "-dv" in argv:
                return "", "Authority=Developer ID Application: Test\nTimestamp=now\nflags=runtime\n"
            return "", ""
        return implementation

    def test_plan_both_and_read_only(self):
        before = sorted(str(p.relative_to(self.root)) for p in self.root.rglob("*"))
        with patch.object(d.subprocess, "run", side_effect=AssertionError("Plan ran a subprocess")):
            result = self.plan()
        self.assertEqual([r["channel"] for r in result["channels"]], ["direct", "app-store"])
        self.assertEqual(before, sorted(str(p.relative_to(self.root)) for p in self.root.rglob("*")))
        self.assertNotEqual(result["channels"][0]["archive"], result["channels"][1]["archive"])
        for item in result["channels"]:
            self.assertIn("ARCHS=arm64 x86_64", item["commands"][0])
            self.assertNotIn("-allowProvisioningUpdates", item["commands"][0])

    def test_channel_filter(self):
        self.assertEqual(len(self.plan("app-store")["channels"]), 1)

    def test_upload_is_rejected_before_writes(self):
        for channel in d.CHANNELS:
            with self.subTest(channel=channel):
                path = self.root / f"{channel}.plist"
                original = path.read_bytes()
                options = plistlib.loads(original)
                options["destination"] = "upload"
                path.write_bytes(plistlib.dumps(options))
                with self.assertRaisesRegex(d.Failure, "destination=export"):
                    self.plan()
                path.write_bytes(original)
        self.assertFalse((self.root / "new-output").exists())

    def test_wrong_export_method(self):
        path = self.root / "app-store.plist"
        options = plistlib.loads(path.read_bytes())
        options["method"] = "developer-id"
        path.write_bytes(plistlib.dumps(options))
        with self.assertRaises(d.Failure):
            self.plan()

    def test_path_traversal_and_symlink(self):
        for project in ("../outside.xcodeproj", "/tmp/outside.xcodeproj"):
            self.config["project"] = project
            self.save_config()
            with self.assertRaises(d.Failure):
                self.plan()
        (self.root / "outside.xcodeproj").symlink_to(self.root.parent, target_is_directory=True)
        self.config["project"] = "outside.xcodeproj"
        self.save_config()
        with self.assertRaises(d.Failure):
            self.plan()

    def test_unknown_keys_and_types(self):
        for field, value in (("schema_version", True), ("app_name", "../../Example"),
                             ("bundle_id", "invalid"), ("extra", 1), ("channels", [])):
            with self.subTest(field=field):
                original = self.config.copy()
                self.config[field] = value
                self.save_config()
                with self.assertRaises(d.Failure):
                    self.plan()
                self.config = original

    def test_scheme_option_injection(self):
        self.config["channels"]["direct"]["scheme"] = "-allowProvisioningUpdates"
        self.save_config()
        with self.assertRaises(d.Failure):
            self.plan()

    def test_missing_project_exit(self):
        self.config["project"] = "Missing.xcodeproj"
        self.save_config()
        result, envelope = self.cli("plan", "--config", str(self.config_path), "--out", str(self.root / "out"))
        self.assertEqual(result.returncode, 3)
        self.assertFalse(envelope["ok"])

    def test_usage_envelope(self):
        result, envelope = self.cli("build")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(envelope["error"]["code"], "usage")

    def test_offline_version(self):
        result, envelope = self.cli("version")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(set(envelope), {"ok", "data", "error", "meta"})
        self.assertFalse(envelope["data"]["remote_writes"])
        self.assertEqual(result.stderr, "")

    def test_dry_run_has_no_writes(self):
        result, envelope = self.cli("build", "--config", str(self.config_path), "--out", str(self.root / "out"), "--dry-run")
        self.assertEqual(result.returncode, 0, envelope)
        self.assertFalse((self.root / "out").exists())

    def test_store_audit_checks_real_entitlement(self):
        app = self.make_app()
        with patch.object(d, "run", side_effect=self.fake_native()):
            self.assertTrue(d.audit(app, "app-store", "com.example.App", "development")["sandboxed"])
        with patch.object(d, "run", side_effect=self.fake_native(sandboxed=False)):
            with self.assertRaises(d.Failure) as caught:
                d.audit(app, "app-store", "com.example.App", "development")
            self.assertIn("store_not_sandboxed", caught.exception.details["violations"])

    def test_store_rejects_sparkle_link_even_without_framework(self):
        app = self.make_app()
        with patch.object(d, "run", side_effect=self.fake_native(linked=True)):
            with self.assertRaises(d.Failure) as caught:
                d.audit(app, "app-store", "com.example.App", "development")
            self.assertIn("store_contains_sparkle", caught.exception.details["violations"])

    def test_store_rejects_embedded_framework_and_config(self):
        app = self.make_app()
        (app / "Contents/Frameworks/Sparkle.framework").mkdir(parents=True)
        path = app / "Contents/Info.plist"
        info = plistlib.loads(path.read_bytes())
        info["SUFeedURL"] = "https://example.com/appcast.xml"
        path.write_bytes(plistlib.dumps(info))
        with patch.object(d, "run", side_effect=self.fake_native()):
            with self.assertRaises(d.Failure) as caught:
                d.audit(app, "app-store", "com.example.App", "development")
            self.assertIn("store_contains_sparkle", caught.exception.details["violations"])
            self.assertIn("store_contains_updater_configuration", caught.exception.details["violations"])

    def test_framework_self_reference_does_not_prove_app_linkage(self):
        app = self.make_app("direct")
        binary = app / "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"\xcf\xfa\xed\xfe" + b"fixture")
        native = self.fake_native()

        def only_framework_links(argv, cwd=None):
            if argv[0].endswith("otool") and "Sparkle.framework" in argv[-1]:
                return "Sparkle:\n\t@rpath/Sparkle.framework/Versions/B/Sparkle\n", ""
            return native(argv, cwd)

        with patch.object(d, "run", side_effect=only_framework_links), self.assertRaises(d.Failure) as caught:
            d.audit(app, "direct", "com.example.App", "development")
        self.assertIn("direct_missing_sparkle", caught.exception.details["violations"])

    def test_identity_mismatch(self):
        app = self.make_app()
        with patch.object(d, "run", side_effect=self.fake_native()):
            with self.assertRaises(d.Failure) as caught:
                d.audit(app, "app-store", "wrong.bundle.id", "development")
            self.assertIn("bundle_identifier_mismatch", caught.exception.details["violations"])

    def test_development_not_misrepresented_as_release(self):
        app = self.make_app()
        with patch.object(d, "run", side_effect=self.fake_native(debug=True)):
            with self.assertRaises(d.Failure) as caught:
                d.audit(app, "app-store", "com.example.App", "release")
            self.assertTrue(any(v.startswith("debug_entitlement:") for v in caught.exception.details["violations"]))
            self.assertTrue(any(v.startswith("wrong_release_signature:") for v in caught.exception.details["violations"]))

    def test_existing_output_is_preserved(self):
        plan = self.plan()
        output = Path(plan["output"])
        output.mkdir()
        (output / "owned.txt").write_text("preserve")
        with patch.object(d, "git_snapshot", return_value="commit"), self.assertRaises(d.Failure) as caught:
            d.execute_build(plan)
        self.assertEqual(caught.exception.exit_code, 5)
        self.assertEqual((output / "owned.txt").read_text(), "preserve")

    def test_build_failure_retains_receipt_and_full_log(self):
        plan = self.plan("direct")

        def failed(command, **kwargs):
            kwargs["stdout"].write("compiler warning: complete diagnostic\ncompiler error: fixture\n")
            return subprocess.CompletedProcess(command, 65)

        with (
            patch.object(d, "git_snapshot", return_value="commit"),
            patch.object(d.subprocess, "run", side_effect=failed),
            self.assertRaises(d.Failure),
        ):
            d.execute_build(plan)
        receipt = json.loads((Path(plan["output"]) / "receipt.json").read_text())
        self.assertEqual(receipt["status"], "failed")
        self.assertIn("complete diagnostic", (Path(plan["channels"][0]["directory"]) / "archive.log").read_text())

    def test_source_drift_stops_before_xcode(self):
        plan = self.plan()
        with (
            patch.object(d, "git_snapshot", side_effect=["commit", "changed"]),
            patch.object(d.subprocess, "run") as command,
            self.assertRaises(d.Failure) as caught,
        ):
            d.execute_build(plan)
        self.assertEqual(caught.exception.code, "source_drift")
        command.assert_not_called()

    def test_build_success_and_store_validation_limit(self):
        plan = self.plan()

        def successful(command, **kwargs):
            if "-exportArchive" in command:
                output = Path(command[command.index("-exportPath") + 1])
                output.mkdir()
                if "app-store" in str(output):
                    (output / "Example.pkg").write_text("fixture only")
                else:
                    (output / "Example.app").mkdir()
            return subprocess.CompletedProcess(command, 0)

        with (
            patch.object(d, "git_snapshot", return_value="commit"),
            patch.object(d.subprocess, "run", side_effect=successful),
            patch.object(d, "audit", return_value={"version": "1.0.0", "build": "1"}),
        ):
            result = d.execute_build(plan)
        self.assertEqual(result["status"], "exported_not_published")
        self.assertEqual(len(result["channels"]), 2)
        self.assertTrue(result["channels"][1]["requires_store_validation"])
        self.assertIsNone(result["channels"][1]["export_audit"])

    def test_export_options_drift(self):
        plan = self.plan()
        (self.root / "direct.plist").write_text("changed")
        with (
            patch.object(d, "git_snapshot", return_value="commit"),
            patch.object(d.subprocess, "run") as command,
            self.assertRaises(d.Failure) as caught,
        ):
            d.execute_build(plan)
        self.assertEqual(caught.exception.code, "plan_drift")
        command.assert_not_called()

    def test_placeholder_team_is_rejected(self):
        path = self.root / "direct.plist"
        options = plistlib.loads(path.read_bytes())
        options["teamID"] = "REPLACE_WITH_YOUR_TEAM_ID"
        path.write_bytes(plistlib.dumps(options))
        with self.assertRaises(d.Failure) as caught:
            self.plan()
        self.assertEqual(caught.exception.code, "invalid_team")

    def test_dirty_source_is_rejected(self):
        with patch.object(d, "run", side_effect=[("commit", ""), ("?? untracked.swift", "")]), self.assertRaises(d.Failure) as caught:
            d.git_snapshot(self.root)
        self.assertEqual(caught.exception.code, "dirty_source")

    def test_permission_error_envelope(self):
        with patch.object(sys, "argv", ["distribution.py", "--json", "version"]), patch.object(d, "parser", side_effect=PermissionError("fixture")):
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(d.main(), 4)
            self.assertFalse(json.loads(output.getvalue())["ok"])


if __name__ == "__main__":
    unittest.main()
