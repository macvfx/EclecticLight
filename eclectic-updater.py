#!/usr/bin/env python3
"""Eclectic Light Updater.

Scan a Mac for apps from The Eclectic Light Company (bundle id co.eclecticlight.*),
compare installed versions against https://eclecticlight.co/downloads/, and update
out-of-date apps via Installomator labels when available.

All copies found are candidates for update — in /Applications, ~/Applications,
~/Downloads or any custom folder. Organize flattens copies into
/Applications/EclecticLight/ (created if missing) and collects their documents.

Modes:
  check     (default) scan and report only
  update    update every out-of-date copy found (Installomator label, or download)
  organize  flatten apps into /Applications/EclecticLight/, collect PDF/RTF docs

Examples:
  ./eclectic-updater.py check
  ./eclectic-updater.py check --apps-only
  ./eclectic-updater.py update --yes
  ./eclectic-updater.py update --only-label silentknight
  ./eclectic-updater.py organize --yes
  ./eclectic-updater.py --install-installomator
"""

import argparse
import datetime
import os
import plistlib
import re
import shlex
import subprocess
import sys
import threading
import time
import urllib.request
from dataclasses import dataclass, field

SITE_URL = "https://eclecticlight.co/downloads/"
BUNDLE_PREFIX = "co.eclecticlight."
INSTALLOMATOR_LABELS_URL = (
    "https://raw.githubusercontent.com/Installomator/Installomator/main/Labels.txt"
)
INSTALLOMATOR_SCRIPT_URL = (
    "https://raw.githubusercontent.com/Installomator/Installomator/main/Installomator.sh"
)
DOWNLOADS_DIR = os.path.expanduser("~/Downloads")
ECLECTICLIGHT_FOLDER = "/Applications/EclecticLight"
README_FOLDER_NAME = "ReadMe"
DEFAULT_SEARCH_DIRS = ["/Applications", os.path.expanduser("~/Applications"), DOWNLOADS_DIR]

# zip-name prefixes that do not decode cleanly to the bundle-id app name
ZIP_PREFIX_OVERRIDES = {
    "sk": "silentknight3",  # sk302.zip is SilentKnight 3 (Apple silicon)
}

# Some downloads contain multiple app bundles whose bundle-id suffixes differ
# from the suite name shown on the main downloads page.
CATALOG_ALIASES = {
    "deeparchive": ("deeptools", "DeepArchive"),
    "deepunarchive": ("deeptools", "DeepUnarchive"),
    "deepcopy": ("deeptools", "DeepCopy"),
    "skintm": ("skint", "SkintM"),
}

# Verified downloads that aren't listed on the main downloads page. Keep these
# source-backed and remove an entry if the main page starts listing it.
SUPPLEMENTAL_CATALOG = {
    "appexindexer": (
        "AppexIndexer",
        [(
            "1.1",
            "https://eclecticlight.co/wp-content/uploads/2025/06/appexindexer11.zip",
            "(Sonoma 14.6 and later)",
        )],
    ),
}


@dataclass
class App:
    path: str
    bundle_id: str
    name: str
    version: str

    def location(self):
        if self.path.startswith("/Applications"):
            return "Applications"
        if self.path.startswith(DOWNLOADS_DIR):
            return "Downloads"
        return "Custom"


@dataclass
class CatalogEntry:
    key: str
    name: str
    versions: list = field(default_factory=list)

    def latest(self):
        return max(self.versions, key=lambda v: verkey(v[0]), default=None)


def fetch(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": "eclectic-updater/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def scan_apps(dirs):
    apps = []
    for base in dirs:
        if not os.path.isdir(base):
            continue
        for root, dirnames, _ in os.walk(base):
            for name in dirnames:
                if name.endswith(".app"):
                    app = read_app(os.path.join(root, name))
                    if app:
                        apps.append(app)
            dirnames[:] = [d for d in dirnames if not d.endswith(".app")]
    return apps


def read_app(path):
    info_path = os.path.join(path, "Contents", "Info.plist")
    if not os.path.exists(info_path):
        return None
    try:
        with open(info_path, "rb") as fh:
            info = plistlib.load(fh)
    except Exception:
        return None
    bundle_id = info.get("CFBundleIdentifier", "")
    if not bundle_id.startswith(BUNDLE_PREFIX):
        return None
    name = info.get("CFBundleName") or os.path.splitext(os.path.basename(path))[0]
    version = info.get("CFBundleShortVersionString") or info.get("CFBundleVersion") or ""
    return App(path=path, bundle_id=bundle_id, name=name, version=version)


def app_key(app):
    return normalize(app.bundle_id[len(BUNDLE_PREFIX):])


def group_apps(apps):
    groups = {}
    for app in apps:
        groups.setdefault(app_key(app), []).append(app)
    return groups


def needs_organization(app):
    """True unless the app bundle is already directly inside the main folder."""
    return os.path.dirname(os.path.abspath(app.path)) != os.path.abspath(ECLECTICLIGHT_FOLDER)


def normalize(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def verkey(v):
    tokens = re.findall(r"\d+|[a-zA-Z]+", v)
    return tuple((0, int(t)) if t.isdigit() else (1, t.lower()) for t in tokens)


def clean_html(text):
    return re.sub(r"<[^>]+>", "", text).strip()


def parse_link_text(text):
    cleaned = clean_html(text)
    pre, sep, _ = cleaned.partition("(")
    pre = pre.strip()
    compat = cleaned[cleaned.find("("):] if sep else ""
    md = re.search(r"(\d+(?:\.\d+)+[a-zA-Z0-9]*)", cleaned)
    if md:
        if md.start() < len(pre):
            name = cleaned[:md.start()].strip()
        else:
            name = pre
        if name:
            return name, md.group(1), compat
    mt = re.match(r"^(.*?)\s+(\d+[a-zA-Z0-9]*)$", pre)
    if mt and mt.group(1):
        return mt.group(1).strip(), mt.group(2), compat
    if pre and not any(c.isspace() for c in pre):
        return pre, None, compat
    return None, None, None


NON_APP_PREFIXES = {
    "macappscaffold", "scriptbase", "dropsy", "basicpdfviewer",
    "help", "lockrattlerhelp", "swiftscrapbook", "macproblems",
    "ovidmetamorphosesbook1a", "ovidmetamorphosesbook1b", "salomestory",
    "elainetheladyofshalott", "latexpaper", "latextuftebk",
}


def build_catalog(html):
    entries = {}
    pattern = re.compile(
        r'<a[^>]+href="([^"]*/wp-content/uploads/[0-9]{4}/[0-9]{2}/([^"/]+\.zip))"[^>]*>(.*?)</a>([^<]*)',
        re.S,
    )
    for url, zipname, anchor, trailing in pattern.findall(html):
        zipbase = os.path.splitext(zipname)[0]

        name, version, compat = parse_link_text(anchor + trailing)

        m = re.match(r"^([a-z]+)", zipbase)
        zip_prefix = m.group(1) if m else None

        if zip_prefix and zip_prefix in ZIP_PREFIX_OVERRIDES:
            key = normalize(ZIP_PREFIX_OVERRIDES[zip_prefix])
        elif name and not any(c.isspace() for c in name) and any(c.isalpha() for c in name):
            key = normalize(name)
        elif zip_prefix:
            key = normalize(zip_prefix)
        else:
            continue

        if not version:
            name = name or re.match(r"^([a-z]+)", zipbase).group(1)
            vm = re.search(r"(\d+(?:\.\d+)*[a-zA-Z0-9]*)$", zipbase)
            version = vm.group(1) if vm else ""
            compat = ""
        if not version:
            continue

        entry = entries.setdefault(key, CatalogEntry(key=key, name=name))
        entry.versions.append((version, url, compat))
    apply_catalog_exceptions(entries)
    return entries


def apply_catalog_exceptions(entries):
    for alias, (source, display_name) in CATALOG_ALIASES.items():
        if alias in entries or source not in entries:
            continue
        source_entry = entries[source]
        entries[alias] = CatalogEntry(
            key=alias,
            name=display_name,
            versions=list(source_entry.versions),
        )
    for key, (name, versions) in SUPPLEMENTAL_CATALOG.items():
        if key not in entries:
            entries[key] = CatalogEntry(
                key=key,
                name=name,
                versions=list(versions),
            )


def fetch_installomator_labels():
    try:
        text = fetch(INSTALLOMATOR_LABELS_URL)
    except Exception:
        return set()
    return {line.strip().lower() for line in text.splitlines() if line.strip()}


def find_installomator():
    candidates = [
        "/usr/local/Installomator/Installomator.sh",
        "/usr/local/bin/Installomator.sh",
        "/usr/local/bin/installomator",
        "/opt/homebrew/bin/installomator",
        "/usr/bin/installomator",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    try:
        out = subprocess.run(
            ["which", "installomator"], capture_output=True, text=True, check=False
        )
        if out.stdout.strip() and os.path.exists(out.stdout.strip()):
            return out.stdout.strip()
    except Exception:
        pass
    return None


def install_installomator():
    print("Installomator is not installed.")
    print("It will be installed to /usr/local/Installomator/Installomator.sh")
    print("(or run: brew install installomator)")
    confirm = input("Install now? [y/N] ").strip().lower()
    if confirm != "y":
        print("Install cancelled.")
        return False
    script = (
        "mkdir -p /usr/local/Installomator && "
        "curl -fsSL " + INSTALLOMATOR_SCRIPT_URL + " "
        "-o /usr/local/Installomator/Installomator.sh && "
        "chmod 755 /usr/local/Installomator/Installomator.sh"
    )
    ok = run_privileged(script)
    if ok and os.path.exists("/usr/local/Installomator/Installomator.sh"):
        print("Installomator installed at /usr/local/Installomator/Installomator.sh")
        return True
    print("Install failed.")
    return False


# --- Administrator rights -------------------------------------------------
#
# Most of what this script does needs none: an admin user can already write to
# /Applications, so moves, new folders and empty-folder removal are tried as the
# current user first. Only what that cannot do goes through run_privileged — and
# Installomator, which always has to run as root.
#
# When rights are needed the password is asked for once, in the terminal, and
# kept for the rest of the run. Each call used to raise its own dialog.

_SUDO = {"declined": False, "keepalive": False}


def _sudo_ready():
    return subprocess.run(
        ["sudo", "-n", "true"], capture_output=True, text=True, check=False
    ).returncode == 0


def _keep_sudo_alive():
    if _SUDO["keepalive"]:
        return
    _SUDO["keepalive"] = True

    def refresh():
        while True:
            time.sleep(50)
            subprocess.run(["sudo", "-n", "-v"], capture_output=True, check=False)

    threading.Thread(target=refresh, daemon=True).start()


def run_privileged(cmd):
    """Run one shell command as root, asking for the password at most once per run."""
    if not _sudo_ready() and sys.stdin.isatty() and not _SUDO["declined"]:
        print("  Administrator rights are needed. You will be asked once for this run.")
        if subprocess.run(["sudo", "-v"], check=False).returncode != 0:
            _SUDO["declined"] = True
    if _sudo_ready():
        _keep_sudo_alive()
        return subprocess.run(["sudo", "sh", "-c", cmd], check=False).returncode == 0
    if sys.stdin.isatty():
        # Asked in the terminal and refused: do not follow up with a dialog.
        return False
    # No terminal to ask in (launched from another program): fall back to a dialog.
    escaped = cmd.replace("\\", "\\\\").replace('"', '\\"')
    osa = 'do shell script "' + escaped + '" with administrator privileges'
    return subprocess.run(["osascript", "-e", osa], check=False).returncode == 0


def _nearest_existing(path):
    path = os.path.abspath(path)
    while not os.path.exists(path):
        parent = os.path.dirname(path)
        if parent == path:
            break
        path = parent
    return path


def _can_move_unprivileged(source, dest_dir):
    """True when the current user can complete the move without leaving half of it behind.

    Both parent folders must be writable. Across volumes a move is a copy and then a
    delete, so the source must also be the user's own — otherwise the copy succeeds, the
    delete fails, and a second, elevated attempt would nest the item inside the first copy.
    """
    source_parent = os.path.dirname(os.path.abspath(source))
    target = _nearest_existing(dest_dir)
    mode = os.W_OK | os.X_OK
    if not (os.access(source_parent, mode) and os.access(target, mode)):
        return False
    try:
        if os.stat(source_parent).st_dev == os.stat(target).st_dev:
            return True
        return os.lstat(source).st_uid == os.getuid()
    except OSError:
        return False


def move_path(source, dest):
    """Move a file or bundle, as the current user if possible, as root only if not."""
    dest_dir = os.path.dirname(dest)
    if _can_move_unprivileged(source, dest_dir):
        try:
            os.makedirs(dest_dir, exist_ok=True)
            moved = subprocess.run(
                ["mv", source, dest], stderr=subprocess.DEVNULL, check=False
            ).returncode == 0
        except OSError:
            moved = False
        if moved:
            return True
        if os.path.exists(dest):
            return False
    owner = f"{os.getuid()}:{os.getgid()}"
    quoted_dir = shlex.quote(dest_dir)
    # A folder created as root is handed back to the user, so the next run needs no rights.
    return run_privileged(
        f"[ -d {quoted_dir} ] || {{ mkdir -p {quoted_dir} && chown {owner} {quoted_dir}; }}; "
        f"mv {shlex.quote(source)} {shlex.quote(dest)}"
    )


def ensure_eclecticlight_folder(yes=False):
    """Confirm and create /Applications/EclecticLight if it doesn't exist."""
    if os.path.isdir(ECLECTICLIGHT_FOLDER):
        return True
    if not yes and input(f"Create {ECLECTICLIGHT_FOLDER}? [y/N] ").strip().lower() != "y":
        print(f"Cancelled — {ECLECTICLIGHT_FOLDER} not created.")
        return False
    try:
        os.makedirs(ECLECTICLIGHT_FOLDER, exist_ok=True)
        print(f"Created {ECLECTICLIGHT_FOLDER}.")
        return True
    except OSError:
        folder = shlex.quote(ECLECTICLIGHT_FOLDER)
        if run_privileged(f"mkdir -p {folder} && chown {os.getuid()}:{os.getgid()} {folder}"):
            print(f"Created {ECLECTICLIGHT_FOLDER}.")
            return True
        print(f"Could not create {ECLECTICLIGHT_FOLDER}.")
        return False


def update_via_installomator(installomator, label):
    print(f"  running: sudo {installomator} {label}")
    return run_privileged(f'"{installomator}" {label} NOTIFY=silent')


def open_in_browser(url):
    subprocess.run(["open", url], check=False)


def move_app(app, dest_dir, yes):
    dest = os.path.join(dest_dir, os.path.basename(app.path))
    if os.path.exists(dest):
        existing = read_app(dest)
        if existing and existing.bundle_id == app.bundle_id and existing.version == app.version:
            print(f"  {app.path} is a duplicate of {dest} — trashing the duplicate")
            if yes or input(f"  trash duplicate {app.path}? [y/N] ").strip().lower() == "y":
                if trash(app.path):
                    print(f"  trashed duplicate {app.path}")
                    return True
                print("  trash failed — leaving in place")
                return False
            return False
        print(f"  already exists, skipped: {dest}")
        return False
    if not yes and input(f"  move {app.path} -> {dest}? [y/N] ").strip().lower() != "y":
        return False
    print(f"  moving to {dest}")
    return move_path(app.path, dest)


def unique_destination(folder, name):
    """Return a non-overwriting destination, adding -2, -3, ... if needed."""
    stem, ext = os.path.splitext(name)
    destination = os.path.join(folder, name)
    suffix = 2
    while os.path.exists(destination):
        destination = os.path.join(folder, f"{stem}-{suffix}{ext}")
        suffix += 1
    return destination


def collect_readme_documents():
    """Move PDFs and RTFs from nested app folders into one top-level ReadMe."""
    if not os.path.isdir(ECLECTICLIGHT_FOLDER):
        return 0
    readme_folder = os.path.join(ECLECTICLIGHT_FOLDER, README_FOLDER_NAME)
    documents = []
    for root, dirnames, filenames in os.walk(ECLECTICLIGHT_FOLDER):
        dirnames[:] = [
            name for name in dirnames
            if not name.endswith(".app")
            and os.path.abspath(os.path.join(root, name)) != os.path.abspath(readme_folder)
        ]
        for name in filenames:
            if os.path.splitext(name)[1].lower() in {".pdf", ".rtf"}:
                documents.append(os.path.join(root, name))
    if not documents:
        return 0
    moved = 0
    for source in sorted(documents):
        destination = unique_destination(readme_folder, os.path.basename(source))
        if move_path(source, destination):
            print(f"  readme: {source} -> {destination}")
            moved += 1
        else:
            print(f"  could not move readme document: {source}")
    return moved


def remove_empty_organization_folders():
    """Remove empty nested directories, never the main or ReadMe folder."""
    if not os.path.isdir(ECLECTICLIGHT_FOLDER):
        return 0
    readme_folder = os.path.abspath(os.path.join(ECLECTICLIGHT_FOLDER, README_FOLDER_NAME))
    candidates = []
    for root, dirnames, _ in os.walk(ECLECTICLIGHT_FOLDER):
        dirnames[:] = [
            name for name in dirnames
            if not name.endswith(".app")
            and os.path.abspath(os.path.join(root, name)) != readme_folder
        ]
        candidates.extend(os.path.join(root, name) for name in dirnames)
    removed = 0
    for root in reversed(candidates):
        try:
            os.rmdir(root)
            print(f"  removed empty folder {root}")
            removed += 1
        except OSError:
            # It may be empty but owned by root.
            try:
                empty = not os.listdir(root)
            except OSError:
                empty = False
            if empty and run_privileged(f"rmdir {shlex.quote(root)}"):
                print(f"  removed empty folder {root}")
                removed += 1
    return removed


def trash(path):
    script = 'tell application "Finder" to delete POSIX file "' + path.replace('"', '\\"') + '"'
    return subprocess.run(["osascript", "-e", script], check=False).returncode == 0


def deep_clean_parent(app_path, yes):
    """After trashing an old copy, remove its now-empty version folder
    (only inside /Applications/EclecticLight)."""
    parent = os.path.dirname(app_path)
    if not parent.startswith(ECLECTICLIGHT_FOLDER):
        return
    try:
        if os.listdir(parent):
            return
    except OSError:
        pass
    if not yes and input(f"  remove now-empty folder {parent}? [y/N] ").strip().lower() != "y":
        return
    try:
        os.rmdir(parent)
        print(f"  removed empty folder {parent}")
    except OSError:
        if run_privileged(f'rmdir "{parent}"'):
            print(f"  removed empty folder {parent}")
        else:
            print(f"  could not remove folder {parent}")


def download_and_install(app, entry, key, yes):
    url = entry.latest()[1]
    if not ensure_eclecticlight_folder(yes):
        print("  cancelled — no EclecticLight folder")
        return False
    tmp = f"/tmp/elu-{key}"
    os.makedirs(tmp, exist_ok=True)
    zf = os.path.join(tmp, os.path.basename(url))
    print(f"  downloading {url}")
    if subprocess.run(["curl", "-fsSL", url, "-o", zf], check=False).returncode != 0:
        print("  download failed")
        return False
    print(f"  unzipping {os.path.basename(zf)}")
    if subprocess.run(["unzip", "-o", "-q", zf, "-d", tmp], check=False).returncode != 0:
        print("  unzip failed")
        return False
    found = []
    for root, dirnames, _ in os.walk(tmp):
        for name in dirnames:
            if name.endswith(".app"):
                path = os.path.join(root, name)
                candidate = read_app(path)
                if candidate and app_key(candidate) == key:
                    found.append(path)
    if not found:
        print(f"  no matching {app.bundle_id} app found in the download")
        return False
    newest = max(found, key=lambda p: verkey(read_app(p).version if read_app(p) else ""))
    ver = entry.latest()[0]
    ver_digits = re.sub(r"\D", "", ver)
    dest_dir = os.path.join(ECLECTICLIGHT_FOLDER, f"{key}{ver_digits}")
    dest = os.path.join(dest_dir, os.path.basename(newest))
    if os.path.exists(dest):
        print(f"  {dest} already exists")
        return False
    if not yes and input(f"  move downloaded app into {dest}? [y/N] ").strip().lower() != "y":
        return False
    return move_path(newest, dest)


def analyze_groups(apps, catalog, labels):
    """Per app-key: installed copies, newest installed, update action."""
    groups = group_apps(apps)
    out = {}
    for key, copies in groups.items():
        entry = catalog.get(key)
        latest_ver = entry.latest()[0] if entry else None
        installed = [c for c in copies if c.location() == "Applications"]
        newest_inst = max(installed, key=lambda a: verkey(a.version)) if installed else None
        active = bool(newest_inst and not newest_inst.path.startswith(ECLECTICLIGHT_FOLDER))
        if newest_inst and latest_ver and verkey(newest_inst.version) < verkey(latest_ver):
            status = "outdated"
            action = "installomator" if (active and key in labels) else "download"
        elif not installed and latest_ver and verkey(max(copies, key=lambda a: verkey(a.version)).version) < verkey(latest_ver):
            status = "downloads-only-outdated"
            action = "download"
        elif not installed:
            status = "downloads-only"
            action = "—"
        else:
            status = "current"
            action = "—"
        out[key] = {
            "name": entry.name if entry else copies[0].name,
            "entry": entry,
            "latest": latest_ver,
            "copies": sorted(copies, key=lambda a: verkey(a.version), reverse=True),
            "newest_inst": newest_inst,
            "status": status,
            "action": action,
        }
    return out


def print_report(apps, catalog, labels, installomator):
    now = datetime.date.today().isoformat()
    print(f"Eclectic Light apps found on this Mac — {now}")
    print(f"Catalog source: {SITE_URL}")
    print(f"Installomator:  {installomator or 'NOT INSTALLED'}")
    print()

    info = analyze_groups(apps, catalog, labels)
    print(f"{'App':<24} {'Version':<10} {'Location':<13} {'Status':<18} Path")
    print("-" * 100)

    for key in sorted(info, key=lambda k: info[k]["name"].lower()):
        g = info[key]
        target = g["newest_inst"] or g["copies"][0]
        for copy in g["copies"]:
            if not g["entry"]:
                status = "no catalog entry"
            elif g["status"] in ("outdated", "downloads-only-outdated") and copy is target:
                status = "UPDATE AVAILABLE"
            elif g["latest"] and verkey(copy.version) >= verkey(g["latest"]):
                status = "up to date"
            elif g["latest"]:
                status = "stale copy"
            else:
                status = "no catalog entry"
            star = "*" if (g["newest_inst"] and copy is g["newest_inst"]) else " "
            print(
                f"{g['name']:<24} "
                f"{copy.version:<10} "
                f"{copy.location():<13} "
                f"{status:<18} {copy.path}{star}"
            )
        if g["status"] in ("outdated", "downloads-only-outdated"):
            print(f"    installed -> {g['latest']}  ({g['action']})")
        print()

    print()
    if not catalog:
        print("Catalog empty — run without --offline to fetch versions.")
        return

    missing = sorted(set(catalog) - set(info), key=lambda k: catalog[k].name)
    missing = [k for k in missing if k not in NON_APP_PREFIXES]
    if missing:
        print("Eclectic Light apps on the site but not installed:")
        for key in missing:
            e = catalog[key]
            print(f"    {e.name:<24} latest {e.latest()[0]}  {e.latest()[1]}")
        print()

    loose = [a for a in apps if needs_organization(a)]
    if loose:
        print(f"{len(loose)} copy/copies need organization.")
        print("Flatten them into the main folder: ./eclectic-updater.py organize")
        print()

    outdated = [g for g in info.values() if g["status"] in ("outdated", "downloads-only-outdated")]
    stale = []
    for g in info.values():
        if g["status"] == "current" and g["newest_inst"]:
            for c in g["copies"]:
                if (c is not g["newest_inst"] and c.location() == "Applications"
                        and verkey(c.version) < verkey(g["newest_inst"].version)):
                    stale.append((c, g["latest"]))

    if stale:
        print(f"{len(stale)} stale installed copy/copies of already-current apps:")
        for c, latest in stale:
            print(f"  {c.name} {c.version} (current is {latest})  {c.path}")
        print("Clean them up: ./eclectic-updater.py update")
        print()

    if not outdated and not stale:
        print("All found Eclectic Light apps are up to date.")
        return
    if outdated:
        print(f"{len(outdated)} app(s) out of date:")
        for g in sorted(outdated, key=lambda g: g["name"].lower()):
            target = g["newest_inst"] or g["copies"][0]
            print(f"  {g['name']} {target.version} -> {g['latest']}  ({g['action']})  {target.path}")
        if installomator:
            print("Run: ./eclectic-updater.py update")
        else:
            print("Run: ./eclectic-updater.py update   "
                  "(Installomator not installed — apps without a label are downloaded)")


def update_outdated(apps, catalog, labels, installomator, only_label=None, yes=False):
    info = analyze_groups(apps, catalog, labels)
    if only_label:
        info = {k: g for k, g in info.items() if k == only_label}

    outdated = {k: g for k, g in info.items() if g["status"] in ("outdated", "downloads-only-outdated")}
    stale = []
    for g in info.values():
        if g["status"] == "current" and g["newest_inst"]:
            for c in g["copies"]:
                if (c is not g["newest_inst"] and c.location() == "Applications"
                        and verkey(c.version) < verkey(g["newest_inst"].version)):
                    stale.append(c)

    if not outdated and not stale:
        print("Nothing to update.")
        return 0

    for key, g in sorted(outdated.items(), key=lambda kv: kv[1]["name"].lower()):
        target = g["newest_inst"] or g["copies"][0]
        active = bool(g["newest_inst"] and not g["newest_inst"].path.startswith(ECLECTICLIGHT_FOLDER))
        print(f"\n{g['name']}: {target.version} -> {g['latest']}")
        if g["action"] == "installomator":
            if not installomator:
                if not install_installomator():
                    continue
                installomator = find_installomator()
            if not yes and input("  update with Installomator? [y/N] ").strip().lower() != "y":
                continue
            ok = update_via_installomator(installomator, key)
            print(f"  {'OK' if ok else 'FAILED'}")
        else:
            if not yes and input("  download latest into /Applications/EclecticLight? [y/N] "
                                 ).strip().lower() != "y":
                continue
            ok = download_and_install(target, g["entry"], key, yes)
            print(f"  {'OK' if ok else 'SKIPPED/FAILED'}")

        if ok:
            for copy in g["copies"]:
                if copy.location() != "Applications":
                    continue
                if g["action"] == "installomator" and copy is target:
                    continue
                if not yes and input(f"  trash old copy {copy.path}? [y/N] ").strip().lower() != "y":
                    continue
                if trash(copy.path):
                    print(f"  trashed {copy.path}")
                    deep_clean_parent(copy.path, yes)

    if stale:
        print(f"\nCleaning up {len(stale)} stale installed copy/copies:")
        for c in stale:
            if not yes and input(f"  trash old copy {c.path}? [y/N] ").strip().lower() != "y":
                continue
            if trash(c.path):
                print(f"  trashed {c.path}")
                deep_clean_parent(c.path, yes)

    print("\nTip: ./eclectic-updater.py organize flattens apps and collects "
          "PDF/RTF files in ReadMe/.")
    return 0


def organize(apps, yes=False):
    print(f"Flattening apps into {ECLECTICLIGHT_FOLDER}/ …")
    candidates = [a for a in apps if needs_organization(a)]
    if not candidates and not os.path.isdir(ECLECTICLIGHT_FOLDER):
        print("Nothing to organize.")
        return 0
    if not ensure_eclecticlight_folder(yes):
        return 0
    moved = 0
    for app in sorted(candidates, key=lambda a: app_key(a)):
        if move_app(app, ECLECTICLIGHT_FOLDER, yes):
            moved += 1
    clean_files = yes or input(
        "  collect PDF/RTF documents and remove empty folders? [y/N] "
    ).strip().lower() == "y"
    documents = collect_readme_documents() if clean_files else 0
    removed = remove_empty_organization_folders() if clean_files else 0
    print(f"Moved {moved} app copy/copies into {ECLECTICLIGHT_FOLDER}/")
    print(f"Moved {documents} PDF/RTF document(s) into "
          f"{ECLECTICLIGHT_FOLDER}/{README_FOLDER_NAME}/")
    print(f"Removed {removed} empty folder(s)")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Update Eclectic Light Company apps")
    parser.add_argument("mode", nargs="?", default="check",
                        choices=["check", "update", "organize"],
                        help="check = report only (default); update = run updates; "
                             "organize = flatten apps and collect PDF/RTF documents")
    parser.add_argument("--also", action="append", default=[],
                        help="extra directory to scan for installed apps (repeatable)")
    parser.add_argument("--apps-only", action="store_true",
                        help="only scan /Applications and ~/Applications (skip ~/Downloads)")
    parser.add_argument("--only-label", default=None,
                        help="with update: only update this app (bundle-id app name)")
    parser.add_argument("--yes", "-y", action="store_true",
                        help="update/organize without prompting")
    parser.add_argument("--install-installomator", action="store_true",
                        help="install Installomator, then exit")
    parser.add_argument("--offline", action="store_true",
                        help="skip network fetches (catalog/labels empty)")
    args = parser.parse_args()

    if args.install_installomator:
        path = find_installomator()
        if path:
            print(f"Installomator is already installed at {path}")
        else:
            install_installomator()
        return

    scan_dirs = (["/Applications", os.path.expanduser("~/Applications")] if args.apps_only
                 else DEFAULT_SEARCH_DIRS) + args.also
    apps = scan_apps(scan_dirs)
    if not apps:
        print("No Eclectic Light apps found in: " + ", ".join(scan_dirs))
        return

    catalog = {}
    labels = set()
    if not args.offline:
        print("Fetching catalog from eclecticlight.co …")
        try:
            catalog = build_catalog(fetch(SITE_URL))
        except Exception as exc:
            print(f"Warning: could not fetch {SITE_URL}: {exc}", file=sys.stderr)
        print("Fetching Installomator labels …")
        labels = fetch_installomator_labels()

    installomator = find_installomator()

    if args.mode == "update":
        raise SystemExit(update_outdated(
            apps, catalog, labels, installomator,
            only_label=args.only_label, yes=args.yes,
        ))
    if args.mode == "organize":
        raise SystemExit(organize(apps, yes=args.yes))

    print_report(apps, catalog, labels, installomator)


if __name__ == "__main__":
    main()
