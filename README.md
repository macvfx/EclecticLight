# Eclectic Light Updater

Scans a Mac for apps from **The Eclectic Light Company** (bundle id
`co.eclecticlight.*` — Howard Oakley's utilities such as SilentKnight,
SystHist, xattred, Ulbow, LockRattler…), compares every copy found against the
latest on <https://eclecticlight.co/downloads/>, and offers to update the
out-of-date ones — via
[Installomator](https://github.com/Installomator/Installomator) when a label
exists, otherwise by downloading the newest build into
`/Applications/EclecticLight/`.

## Requirements

- macOS with Command Line Tools (ships `/usr/bin/python3`)
- Internet access (only needed to fetch the catalog + labels)

## Usage

```sh
./eclectic-updater.py check              # scan + report (default)
./eclectic-updater.py check --apps-only  # skip ~/Downloads
./eclectic-updater.py update             # update all out-of-date copies found
./eclectic-updater.py update --yes       # update without prompting
./eclectic-updater.py update --only-label silentknight   # single app
./eclectic-updater.py organize           # move copies into /Applications/EclecticLight
./eclectic-updater.py --install-installomator            # install Installomator, then exit
```

Or double-click `eclectic-updater.command` for a Terminal window that runs a
report.

## What it scans

- `/Applications` (including the `/Applications/EclecticLight/` subfolder)
- `~/Applications`
- `~/Downloads` (you can restrict with `--apps-only`, or add more with `--also`)
- every `.app` whose bundle id starts with `co.eclecticlight.` is kept

All copies are candidates: the active copy in `/Applications`, older copies
archived in `/Applications/EclecticLight/`, and apps sitting in `~/Downloads`.

## How it works

1. **Scan** — walks the folders above, reads each `Info.plist`, filters by
   bundle id, and groups copies by app.
2. **Catalog** — fetches the downloads page and extracts every download link,
   decoding app name, version and OS-compatibility note (e.g. `SilentKnight
   2.14 (Universal App for Big Sur to Tahoe)`).
3. **Installomator** — fetches `Labels.txt` live and auto-matches labels by
   name (`silentknight`, `silnite`, `ulbow`, `xattred`, `cormorant`, …). Future
   labels are picked up automatically.
4. **Update** — for each out-of-date app:
   - active copy in `/Applications` with a label → `sudo <installomator> <label>`;
   - otherwise → downloads the newest zip, expands it, and moves the `.app`
     into `/Applications/EclecticLight/<name><version>/`;
   - old copies are offered for deletion to the Trash, then their now-empty
     version folder under `/Applications/EclecticLight/` is removed too.
   If `/Applications/EclecticLight` doesn't exist yet, you're asked to confirm
   before it is created.
5. **Organize** — moves every copy not already under `/Applications/EclecticLight`
   into that folder, named `<name><version>` like the rest (e.g. `skint109/`).
   The folder is created on confirmation if missing. A copy that is an identical
   duplicate of an already-organized app (same bundle id + version) is offered
   to the Trash instead of being skipped forever.

Privilege prompts use passwordless `sudo` when configured, otherwise an
AppleScript admin-password dialog. Nothing is downloaded or modified by
`check` — only `update`/`organize` change anything, and always with a prompt
unless you pass `--yes`.

## Notes

- The site lists several versions of one app for different macOS releases (e.g.
  SilentKnight 1.x/2.x, and SilentKnight 3 for Apple silicon under a different
  bundle id `co.eclecticlight.SilentKnight3`). The newest is used and the
  compatibility string is shown so you can judge.
- Apps on the site you don't have are listed for discovery; Tinderbox/help-book
  downloads are filtered out.