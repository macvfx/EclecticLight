# Backlog

## Help formatting and app directory

Status: implemented in the 1.4 (build 9); GUI review pending.

- Replace the plain-text Help layout with properly styled, bold section
  headings, readable spacing, and accessible heading semantics.
- Add an alphabetical directory of apps and command-line tools to the Help
  window, reachable from the Help menu.
- Add a category view using the publisher's
  [Free Software Menu](https://eclecticlight.co/free-software-menu/) as the
  source for grouping and descriptions. Use concise attributed descriptions
  and links to the relevant product pages; record when the source was reviewed.
- Keep one shared directory dataset behind both views. Preserve membership in
  multiple categories while showing each product only once alphabetically.
- Clearly distinguish app bundles from command-line tools. Reconcile display
  names with catalog identities without inventing download mappings.
- Keep explanatory descriptions separate from the current download version's
  compatibility check; general product-page requirements may describe older
  versions as well.

Acceptance checks:

- Headings are visibly bold and accessible, rather than literal Markdown text.
- Alphabetical ordering ignores case and includes all products in the curated
  directory; category entries resolve to the same product details.
- Category grouping and descriptions are checked against the linked source.
- Product links work, long descriptions wrap, and the Help window remains
  readable at its minimum size.
- Directory content is bundled for offline Help use, with a visible source link
  for current information.

## Installomator setup in Tools menu

Status: implemented in the 1.4 (build 9); real administrator setup acceptance pending.

- Move **Install Installomator** from the main window toolbar into the
  **Tools** menu.
- Provide a dedicated setup action that actually installs Installomator,
  checks the result, and refreshes its detected availability/path.
- Investigate the existing wiring: the toolbar button currently calls
  `model.updateAll()` rather than a dedicated Installomator setup action.
  Verify the installation helper and downloaded distribution are functional,
  not merely that an executable file exists.
- Show setup progress, actionable errors, and the result in the activity log.

Acceptance checks:

- Test setup on a machine or disposable environment without Installomator,
  including when there are no out-of-date Eclectic Light apps.
- Verify the installed tool runs and can resolve a known label.
- Test already-installed behavior, network failure, administrator cancellation,
  and failed setup; none should report a successful installation incorrectly.
- Confirm setup does not trigger unrelated app updates.

## Installomator label picker and installation window

Status: implemented in the 1.4 (build 9); actual app-install acceptance pending.

- Add **Tools → Run Installomator…** to open a dedicated window.
- List the labels/apps Installomator knows, not just Eclectic Light products.
  Provide alphabetical sorting, search, refresh, and multiple selection.
- Use label data compatible with the installed Installomator version; do not
  assume a newer online label list is supported by an older local installation.
- Allow the user to select one or more labels and start installation explicitly.
  Show the selected labels before running them and handle missing Installomator.
- Run selected labels sequentially with appropriate administrator permission,
  showing current app, queue progress, per-label output and success/failure.
- Preserve diagnostic output in Show Log and provide a clear final summary.

Acceptance checks:

- Test label discovery, empty/error states, search and multi-selection.
- Test one selected label and several selected labels in a disposable environment.
- Verify the actual installed app outcomes as well as process exit status.
- Test unsupported labels, installation failures, administrator cancellation,
  and repeated runs; define whether the remaining queue stops or continues.
- Ensure only explicitly selected valid labels are passed as arguments and
  no installation starts merely by opening or refreshing the window.

## 1.4 validation record

- Official Installomator 10.9 package signature: passed.
- Label discovery using the extracted official script: passed without installation.
- Invalid/control label filtering and multi-selection queue failure handling: passed.
- Directory uniqueness, product links' host, and multi-category membership: passed.
- Real setup with administrator permission, live third-party app installs, and
  visual Help/label-picker acceptance remain pending. These have not been
  represented as completed by the automated tests.
