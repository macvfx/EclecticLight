# Eclectic Light Updater

Latest Mac app: **1.5.1 (build 11)** — [release notes](docs/releases/1.5.1.md).

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
./eclectic-updater.py organize           # flatten apps and collect PDF/RTF files
./eclectic-updater.py --install-installomator            # install Installomator, then exit
```

Or double-click `eclectic-updater.command` for a Terminal window that runs a
report.

## zsh version

The same tool also ships as a dependency-free zsh script (macOS's default
shell, no Python needed): `eclectic-updater.zsh`. It takes the same commands
and options as the Python version and produces identical output. Double-click
`eclectic-updater-zsh.command` for the Terminal-window report, or run it
directly:

```sh
./eclectic-updater.zsh check
./eclectic-updater.zsh update
./eclectic-updater.zsh organize
```

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
   2.14 (Universal App for Big Sur to Tahoe)`). Suite aliases map `DeepCopy`,
   `DeepArchive`, and `DeepUnarchive` to the `DeepTools` download, and `SkintM`
   to the `Skint` download. The verified [AppexIndexer 1.1 release](https://eclecticlight.co/2025/06/30/updates-to-apfelstrudel-unicode-appexindexer-appexes-ulbow-logs-and-versatility-versions/)
   is included as a supplemental entry because it isn't listed on the main
   downloads page.
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
5. **Organize** — flattens every app so its `.app` bundle sits directly in
   `/Applications/EclecticLight/`. It also moves PDF and RTF documents found in
   nested folders into the shared `/Applications/EclecticLight/ReadMe/` folder,
   adding `-2`, `-3`, and so on when document names collide, then removes only
   folders that are empty. The main folder is created on confirmation if missing.
   An identical duplicate app (same bundle id + version) is offered to the Trash;
   a different app with the same bundle filename is left in place and reported.

The WordPress `/wp-content/uploads/` root does not provide a browsable index, so
the updater doesn't guess filenames or crawl year/month directories. In the
Swift app, an unmatched app has a **Search Website** button that opens the
Eclectic Light site search in an embedded web view. Search results are for
research only; a result must be verified and added to the exception catalog
before the updater will offer its ZIP as an update.

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


## Mac app 1.1 (build 4)

The Swift app requires macOS 14 or later. Its release build supports Apple
silicon and Intel Macs. The Python and zsh commands above remain separate
frontends; the following controls are in the Mac app.

- **Not downloaded** lists catalog apps with no extracted app bundle found in
  the scanned folders. Search by name, choose **Install**, or use **Install All**.
- **Install All Compatible** installs missing apps whose latest catalog
  descriptions match the current macOS. It excludes unknowns and possible
  mismatches and includes all matching apps regardless of the search filter.
- Compatibility recognizes named macOS releases, named ranges, and explicit
  minimum versions. It is advisory and does not check hardware requirements
  or guarantee runtime behavior. Older compatible downloads are not selected
  automatically.
- **Help → Eclectic Light Updater Help** explains common workflows and errors.
- **Help → Show Log** displays persistent timestamped activity with selectable
  text and **Copy Log**. **Reveal Log in Finder** locates
  `~/Library/Logs/EclecticLightUpdater/activity.log`. The app retains roughly
  2 MB plus `activity.previous.log`; earlier versions' in-memory logs cannot
  be recovered. Review local paths before sharing a log.
- Archive diagnostics record the expected bundle ID, extraction exit status,
  every discovered app's name/version/bundle ID and relative path, unreadable
  metadata, and the selected app. A successful extraction with zero apps may
  be a command-line-only download; it is not proof of that classification.
  Multiple apps with different IDs can reveal a catalog mapping mismatch.
  Installation still selects only the expected app, not every app in a suite.

For diagnosis, retry an individual app and copy the corresponding activity
from **Show Log**. “Prepared for installation” can precede privileged file
operations; inspect subsequent completion and error messages.

### Build and validation

Open `SwiftApp/EclecticLightUpdater.xcodeproj` for the full app with icon assets,
or run `SwiftApp/build.sh` for an ad-hoc signed local Swift package build.
Run `swift test --package-path SwiftApp` for catalog, compatibility, archive
inventory, and persistent-log tests. Developer ID signing and notarization are
separate release steps; ad-hoc builds are not notarized.

## Mac app 1.2 (build 5)

- Corrected Cirrus and T2M2 catalog identities to match their downloaded bundles.
- Command-line tools appear separately with **Install Package** and download links.
  Package installation uses macOS `installer`, requests administrator permission,
  requires exactly one expected package, and records installer output and result.
  Tools remain excluded from bulk app-install actions; successful package versions are remembered across launches. Installed buttons are disabled for that version; Install All Packages skips them. External installations or removals are not detected.
- Refresh shows the folder being scanned, online catalog retrieval, and OS
  compatibility stage. The busy overlay displays the current OS and latest log activity.
- Installation results verify app identity and version at the destination and
  report success/failure counts independently of catalog refresh.

## Mac app 1.3 (build 7): Munki export

Choose **Tools → Make Munki Ready…**, select catalog entries, and choose an
output folder. Export does not depend on apps installed on this Mac or filter
by this Mac's OS compatibility. Select All includes the full displayed catalog,
even when a search is active.

The exporter downloads each distinct ZIP once per run. It selects app bundles
by catalog identity, copies each into a separate DMG, verifies the image and
checks its mounted app identity/version. CLI tools are exported as their
original installer packages. It does not re-sign the publisher's app.

Export names preserve version dots, for example `logui-1.1.dmg`.

Each run creates a new output subfolder with `export-report.txt` and
`SHA256SUMS.txt`. Only successful items are ready for import. Missing bundle
matches, ambiguous packages, extraction failures, or validation failures are
reported; failed artifacts are removed where possible.

Import successful DMGs and packages using MunkiAdmin or `munkiimport`, then
review installation paths, catalogs and assignments. Export does not modify
your Munki repository or create deployment policy. See the
[Munki import guide](https://github.com/munki/munki/wiki/munkiimport).

## Mac app 1.4 (build 9)

- Help now has bold headings and offline **Apps A–Z** and **By Category** views,
  based on the publisher's Free Software Menu reviewed September 8, 2026.
- **Tools → Install Installomator…** opens a dedicated setup window. Setup uses
  the latest official signed release package and verifies local label discovery.
  Installing the stable release can replace an existing beta version.
- **Tools → Run Installomator…** lists labels from the installed script, with
  search and multi-selection. Selected labels run sequentially with `DEBUG=0`,
  administrator permission, live output, and a final result summary. The queue
  stops at the first failure/cancellation; Stop After Current leaves the active
  operation running to completion. Reported success includes already-current apps.
- The old toolbar setup button was removed. Missing Installomator no longer
  triggers an implicit script download from the app-update action.

Validation: official package signature and extracted-script label discovery
passed; parser, directory and simulated queue tests passed. Real administrator
setup and third-party app installation have not been verified end to end.

## Mac app 1.5 (build 10)

- Recognizes macOS 27 Golden Gate in compatibility descriptions and OS labels.
- Supplements the live catalog with the publisher’s September 12, 2026
  compatibility list, matched by exact version and download URL.
- Preserves newer catalog releases, existing descriptions, hardware caveats,
  LogUI’s build 88 note, and the distinction between tested apps and CLI tools
  the publisher believes compatible. Omission from the list is not a failure.

See the [release notes and compatibility limits](docs/releases/1.5.md).

## Mac app 1.5.1 (build 11)

App discovery skips symbolic links to folders and app bundles, including
symbolic-link scan roots. This prevents linked Applications folders from
appearing as additional copies and avoids directory-link cycles. Genuine
app copies in different folders are still listed independently.
