"""NeatEditor workspace E2E: background launch, isolated library, open/edit/
switch documents, autosave, sidebar scope regression and pixel baselines.

Data isolation: the app reads `--e2e-root=<root>` (see E2ETestMode) and keeps
its documents and workspace state inside `Tests/E2E/.run/root`. The owner's
`~/Documents` library and `com.x0c.NeatEditor` defaults are never touched.

Documented regressions covered (docs/PERSISTENCE_AUTOSAVE_KNOWLEDGE_BASE.md §7):
  * launching never creates the documents folder, and only the first non-blank
    save publishes a file;
  * the sidebar lists `.md`/`.txt`/text-like extensionless files only, skipping
    hidden entries, directories and binaries, in a stable order.
"""

import os
import pathlib
import re
import time

import pytest

PROJECT_ROOT = pathlib.Path(os.environ.get("E2E_PROJECT_ROOT", pathlib.Path.cwd())).resolve()
DATA_ROOT = PROJECT_ROOT / "Tests" / "E2E" / ".run" / "root"
DOCUMENTS = DATA_ROOT / "documents"

ALPHA = DOCUMENTS / "alpha.md"
ALPHA_BODY = "Alpha document body\nsecond line\n"
BETA = DOCUMENTS / "beta.txt"
BETA_BODY = "Beta body line\n"
NOEXT = DOCUMENTS / "noext"
NOEXT_BODY = "Extensionless body\n"
EDIT_TEXT = "\nEdited by E2E\n"
DEFAULT_TITLE = re.compile(r"^\d{8}-\d{6}$")


def _dedupe(pairs):
    seen = []
    for value in pairs:
        if value not in seen:
            seen.append(value)
    return seen


def _row_names(driver):
    """Sidebar rows in AX (top-to-bottom) order; each row exposes its
    identifier on both the title and the preview static text."""
    return _dedupe(
        hit.identifier[len("sidebar.row."):]
        for hit in driver.ax().walk()
        if hit.identifier.startswith("sidebar.row.")
    )


def _changed_pixel_ratio(first, second, threshold=8):
    """Share of screenshot pixels that differ by more than `threshold`."""
    from PIL import ImageChops

    left = first.image.convert("RGB")
    right = second.image.convert("RGB")
    assert (left.width, left.height) == (right.width, right.height)
    difference = ImageChops.difference(left, right)
    counts = (
        difference.convert("L")
        .point(lambda value: 255 if value > threshold else 0)
        .histogram()
    )
    return counts[255] / (left.width * left.height)


def _wait(predicate, timeout=8.0, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return predicate()


def _tabs(driver):
    return [hit for hit in driver.ax().walk() if hit.role == "AXRadioButton"]


def _selected_tab(driver):
    for tab in _tabs(driver):
        if str(tab.value) == "1":
            return tab.label
    return None


def _tab_title_mask(shot):
    """Screenshot pixels of the title bar and tab strip.

    A blank tab is titled with the launch timestamp, so that band changes every
    run; tab titles are asserted through accessibility instead.
    """
    return [[0, 0, shot.image.width, 150]]


def _toggle_sidebar(driver, *, expect_rows):
    """Press Toggle Sidebar and re-press once if the run lost the click while
    the layout was animating (tokens are snapshot-scoped)."""

    def settled():
        rows = _row_names(driver)
        return bool(rows) == expect_rows

    for attempt in range(2):
        driver.press(label="Toggle Sidebar", role="AXButton")
        if _wait(settled, timeout=6.0):
            return
    raise AssertionError(
        f"sidebar rows expected {'visible' if expect_rows else 'hidden'}: {_row_names(driver)}"
    )


def _open_row(driver, name):
    hit = next(
        hit
        for hit in driver.ax().walk()
        if hit.identifier == f"sidebar.row.{name}"
    )
    return driver.press(hit.identifier, role=hit.role)


def _write_fixtures():
    DOCUMENTS.mkdir(parents=True, exist_ok=True)
    ALPHA.write_text(ALPHA_BODY, encoding="utf-8")
    BETA.write_text(BETA_BODY, encoding="utf-8")
    NOEXT.write_text(NOEXT_BODY, encoding="utf-8")
    (DOCUMENTS / "notes.rtf").write_text("{\\rtf1 unsupported}", encoding="utf-8")
    (DOCUMENTS / "blob").write_bytes(bytes([0x00, 0x01, 0x02, 0xFF, 0xFE, 0x00]))
    (DOCUMENTS / ".hidden.md").write_text("hidden\n", encoding="utf-8")
    (DOCUMENTS / "subdir").mkdir(exist_ok=True)
    (DOCUMENTS / "subdir" / "inner.md").write_text("nested\n", encoding="utf-8")
    # The sidebar sorts by modification date, newest first, then by name.
    base = time.time()
    os.utime(ALPHA, (base, base))
    os.utime(BETA, (base - 10, base - 10))
    os.utime(NOEXT, (base - 20, base - 20))


def test_launch_presents_background_window(app, vision):
    # Documented invariant: launching never creates the documents folder.
    assert not DOCUMENTS.exists(), (
        "the app created the documents folder at launch; "
        "docs/PERSISTENCE_AUTOSAVE_KNOWLEDGE_BASE.md §7 requires the first non-blank save to do that"
    )
    window = app.window
    assert window.title == "NeatEditor", window
    assert window.layer == 0 and window.is_on_screen, window
    shot = vision.capture("launch-empty")
    assert shot.image.width >= 2 * 720 and shot.image.height >= 2 * 480, shot.image.size
    assert 1.0 <= shot.scale_x <= 4.0, f"unexpected backing scale {shot.scale_x}"
    # Occlusion 1.0 means fully covered yet captured from the window buffer.
    colors = shot.image.convert("RGB").getcolors(maxcolors=1 << 16) or []
    assert len(colors) > 50, f"capture looks blank: {len(colors)} colors, occlusion {shot.occlusion}"


def test_sidebar_lists_only_text_files_in_stable_order(app, driver):
    _write_fixtures()
    # Relaunch so the sidebar reads the prepared folder at launch time; the
    # first visible-tab refresh path needs a menu action, which needs a key
    # window and is therefore unavailable to a background run.
    app.stop()
    app.launch()
    app.stabilize()
    rows = _wait(lambda: _row_names(driver))
    assert rows == ["alpha.md", "beta.txt", "noext"], rows
    assert sorted(p.name for p in DOCUMENTS.iterdir()) == [
        ".hidden.md", "alpha.md", "beta.txt", "blob", "noext", "notes.rtf", "subdir"
    ]


def test_open_document_matches_file_content(app, driver):
    _open_row(driver, "alpha.md")
    assert driver.wait_value("editor.text", equals=ALPHA_BODY, timeout=5.0) == ALPHA_BODY
    labels = [tab.label for tab in _tabs(driver)]
    assert "alpha.md" in labels, labels
    assert _selected_tab(driver) == "alpha.md", labels


def test_open_second_document_adds_tab(driver):
    opened = [tab.label for tab in _tabs(driver)]
    _open_row(driver, "beta.txt")
    assert driver.wait_value("editor.text", equals=BETA_BODY, timeout=5.0) == BETA_BODY
    labels = [tab.label for tab in _tabs(driver)]
    assert labels != opened, labels
    assert {"alpha.md", "beta.txt"} <= set(labels), labels
    assert _selected_tab(driver) == "beta.txt", labels


def test_edit_updates_ax_value_and_autosaves(app, driver):
    _open_row(driver, "alpha.md")
    driver.assert_value("editor.text", equals=ALPHA_BODY)
    driver.type_text("editor.text", EDIT_TEXT)
    expected = ALPHA_BODY + EDIT_TEXT
    assert driver.wait_value("editor.text", equals=expected, timeout=5.0) == expected
    # AutoSaveScheduler defaults to a two-second delay; the first non-blank save
    # publishes the buffer to the existing file inside the isolated root.
    saved = _wait(
        lambda: ALPHA.read_text(encoding="utf-8") == expected,
        timeout=10.0,
    )
    assert saved, f"autosave did not reach {ALPHA}: {ALPHA.read_text(encoding='utf-8')!r}"
    assert ALPHA.stat().st_size > 0


def test_switch_documents_via_tab_strip(driver):
    _open_row(driver, "beta.txt")
    assert driver.wait_value("editor.text", equals=BETA_BODY) == BETA_BODY
    driver.press(label="alpha.md", role="AXRadioButton")
    expected = ALPHA_BODY + EDIT_TEXT
    assert driver.wait_value("editor.text", equals=expected, timeout=5.0) == expected
    assert _selected_tab(driver) == "alpha.md", [t.label for t in _tabs(driver)]


def test_toggle_sidebar_changes_rendered_pixels(driver, vision, app):
    app.stabilize()
    before = vision.capture("editor-alpha")
    _toggle_sidebar(driver, expect_rows=False)
    app.stabilize()
    hidden = vision.capture("editor-sidebar-hidden")
    ratio = _changed_pixel_ratio(before, hidden)
    assert ratio > 0.05, f"sidebar toggle changed almost no pixels: {ratio:.4f}"
    _toggle_sidebar(driver, expect_rows=True)


def test_visual_baselines_match_unmuted_layout(driver, vision, app):
    app.stabilize()
    shot = vision.capture("editor-alpha")
    result = vision.assert_visual(
        "editor-alpha", shot=shot, mask_rects=_tab_title_mask(shot), max_diff_ratio=0.001
    )
    assert result.passed, f"editor baseline regression: {result.paths}"


def test_second_pixel_state_matches_baseline(driver, vision, app):
    _toggle_sidebar(driver, expect_rows=False)
    app.stabilize()
    shot = vision.capture("editor-sidebar-hidden")
    result = vision.assert_visual(
        "editor-sidebar-hidden",
        shot=shot,
        mask_rects=_tab_title_mask(shot),
        max_diff_ratio=0.001,
    )
    assert result.passed, f"sidebar-hidden baseline regression: {result.paths}"
    _toggle_sidebar(driver, expect_rows=True)


def test_new_document_tab_stays_unsaved(driver):
    before = {p.name for p in DOCUMENTS.iterdir()}
    tabs_before = len(_tabs(driver))
    driver.press(label="New Document", role="AXButton")
    assert _wait(lambda: len(_tabs(driver)) == tabs_before + 1, timeout=5.0), "new tab did not appear"
    time.sleep(3.0)
    assert {p.name for p in DOCUMENTS.iterdir()} == before, "a blank new document published a file"


def test_background_hotkey_opens_and_closes_search_bar(driver):
    driver.press(label="alpha.md", role="AXRadioButton")
    driver.hotkey(["cmd", "f"])
    bar = _wait(
        lambda: any(hit.identifier == "search.bar" for hit in driver.ax().walk()),
        timeout=4.0,
    )
    assert bar, "background cmd+f did not open floating search bar"
    driver.press("search.close")
    closed = _wait(
        lambda: not any(hit.identifier == "search.bar" for hit in driver.ax().walk()),
        timeout=4.0,
    )
    assert closed, "pressing search.close did not dismiss floating search bar"
