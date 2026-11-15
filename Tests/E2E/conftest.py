import os
import pathlib
import shutil
import sys

import pytest

TOOLKIT = pathlib.Path.home() / ".macos-e2e-toolkit"
sys.path.insert(0, str(TOOLKIT / "harness"))

pytest_plugins = ["macos_e2e_harness.pytest_support"]

PROJECT_ROOT = pathlib.Path(os.environ.get("E2E_PROJECT_ROOT", pathlib.Path.cwd())).resolve()
DATA_ROOT = PROJECT_ROOT / "Tests" / "E2E" / ".run" / "root"
_extra = os.environ.get("E2E_EXTRA_ARGS", "").strip()
os.environ["E2E_EXTRA_ARGS"] = f"{_extra} --e2e-root={DATA_ROOT}".strip()


@pytest.fixture(scope="session", autouse=True)
def isolated_data_root():
    """Fresh document root for the app under test.

    The app receives it as `--e2e-root=` (see E2ETestMode), so a run never reads
    or writes the owner's `~/Documents` library or `com.x0c.NeatEditor` defaults.
    """
    if DATA_ROOT.exists():
        shutil.rmtree(DATA_ROOT)
    DATA_ROOT.parent.mkdir(parents=True, exist_ok=True)
    yield DATA_ROOT
    shutil.rmtree(DATA_ROOT, ignore_errors=True)
