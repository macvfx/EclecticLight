#!/bin/zsh
# Eclectic Light Updater (zsh) — feature-parallel port of eclectic-updater.py
setopt rematch_pcre

SITE_URL="https://eclecticlight.co/downloads/"
BUNDLE_PREFIX="co.eclecticlight."
INSTALLOMATOR_LABELS_URL="https://raw.githubusercontent.com/Installomator/Installomator/main/Labels.txt"
INSTALLOMATOR_SCRIPT_URL="https://raw.githubusercontent.com/Installomator/Installomator/main/Installomator.sh"
DOWNLOADS_DIR="$HOME/Downloads"
ECLECTICLIGHT_FOLDER="/Applications/EclecticLight"
README_FOLDER_NAME="ReadMe"
DEFAULT_SEARCH_DIRS=("/Applications" "$HOME/Applications" "$DOWNLOADS_DIR")
SELF="eclectic-updater.zsh"

typeset -A ZIP_PREFIX_OVERRIDES
ZIP_PREFIX_OVERRIDES[sk]=silentknight3

typeset -A CATALOG_ALIAS_SOURCE CATALOG_ALIAS_NAME
CATALOG_ALIAS_SOURCE[deeparchive]=deeptools
CATALOG_ALIAS_NAME[deeparchive]=DeepArchive
CATALOG_ALIAS_SOURCE[deepunarchive]=deeptools
CATALOG_ALIAS_NAME[deepunarchive]=DeepUnarchive
CATALOG_ALIAS_SOURCE[deepcopy]=deeptools
CATALOG_ALIAS_NAME[deepcopy]=DeepCopy
CATALOG_ALIAS_SOURCE[skintm]=skint
CATALOG_ALIAS_NAME[skintm]=SkintM

typeset -A NON_APP
for __x in macappscaffold scriptbase dropsy basicpdfviewer help lockrattlerhelp \
           swiftscrapbook macproblems ovidmetamorphosesbook1a ovidmetamorphosesbook1b \
           salomestory elainetheladyofshalott latexpaper latextuftebk; do
  NON_APP[$__x]=1
done

typeset -a APPS
typeset -A GROUPS
typeset -a KEYS
typeset -A CATALOG
typeset -a CATALOG_KEYS
typeset -A LABELS
typeset -A INFO

usage() {
  cat <<EOF
Usage: $SELF [mode] [options]

Modes:
  check     (default) scan and report only
  update    update every out-of-date copy found (Installomator label, or download)
  organize  flatten apps into /Applications/EclecticLight/, collect PDF/RTF docs

Options:
  --apps-only               only scan /Applications and ~/Applications
  --also DIR                extra directory to scan (repeatable)
  --only-label NAME         with update: only update this app
  --yes, -y                 update/organize without prompting
  --install-installomator   install Installomator, then exit
  --offline                 skip network fetches (catalog/labels empty)
  -h, --help                show this help
EOF
}

fld() {
  local -a f
  f=("${(@s:|:)1}")
  print -r -- "${f[$2]}"
}

gld() {
  local -a f
  f=("${(@s:^:)1}")
  print -r -- "${f[$2]}"
}
path_of() { fld "$1" 1 }
bundle_of() { fld "$1" 2 }
name_of() { fld "$1" 3 }
version_of() { fld "$1" 4 }

normalize() { print -r -- "${${1:l}//[^a-z0-9]/}" }

app_key() { normalize "${$(bundle_of "$1")#$BUNDLE_PREFIX}" }

app_location() {
  [[ "$1" == "/Applications"* ]] && { print -r -- "Applications"; return 0 }
  [[ "$1" == "$DOWNLOADS_DIR"* ]] && { print -r -- "Downloads"; return 0 }
  print -r -- "Custom"
}

needs_organization() {
  [[ "${$(path_of "$1"):h}" != "$ECLECTICLIGHT_FOLDER" ]]
}

ver_less() {
  local a b x y
  local -a ta tb
  local -i i
  a="$1"; b="$2"
  ta=($(print -r -- "$a" | grep -oE '[0-9]+|[a-zA-Z]+'))
  tb=($(print -r -- "$b" | grep -oE '[0-9]+|[a-zA-Z]+'))
  for ((i = 1; i <= ${#ta} && i <= ${#tb}; i++)); do
    x="${ta[$i]}"; y="${tb[$i]}"
    if [[ "$x" =~ '^[0-9]+$' && "$y" =~ '^[0-9]+$' ]]; then
      (( x < y )) && return 0
      (( x > y )) && return 1
    elif [[ "$x" =~ '^[0-9]+$' ]]; then
      return 1
    elif [[ "$y" =~ '^[0-9]+$' ]]; then
      return 0
    else
      [[ "${x:l}" < "${y:l}" ]] && return 0
      [[ "${x:l}" > "${y:l}" ]] && return 1
    fi
  done
  (( ${#ta} < ${#tb} )) && return 0
  (( ${#ta} > ${#tb} )) && return 1
  return 1
}

trim() {
  local s
  s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  print -r -- "$s"
}

clean_html() { print -r -- "$1" | sed 's/<[^>]*>//g' }

parse_link_text() {
  local cleaned pre compat v pos name n2
  cleaned="$(clean_html "$1")"
  pre="$cleaned"; compat=""
  if [[ "$cleaned" == *"("* ]]; then
    pre="${cleaned%%\(*}"
    compat="(${cleaned#*\(}"
  fi
  pre="$(trim "$pre")"
  if [[ "$cleaned" =~ '(\d+(?:\.\d+)+[a-zA-Z0-9]*)' ]]; then
    v="${match[1]}"; pos="$mbegin[1]"; name=""
    if (( pos <= ${#pre} )); then
      (( pos > 1 )) && name="$(trim "${cleaned[1,$((pos - 1))]}")"
    else
      name="$pre"
    fi
    if [[ -n "$name" ]]; then
      print -r -- "$name"; print -r -- "$v"; print -r -- "$compat"
      return 0
    fi
  fi
  if [[ "$pre" =~ '^(.*?)[[:space:]]+([0-9]+[a-zA-Z0-9]*)$' ]]; then
    n2="$(trim "${match[1]}")"
    if [[ -n "$n2" ]]; then
      print -r -- "$n2"; print -r -- "${match[2]}"; print -r -- "$compat"
      return 0
    fi
  fi
  if [[ -n "$pre" && "$pre" != *[[:space:]]* ]]; then
    print -r -- "$pre"; print -r -- ""; print -r -- "$compat"
    return 0
  fi
  print -r -- ""; print -r -- ""; print -r -- "$compat"
}

fetch() {
  curl -fsSL --max-time 30 -A "eclectic-updater-zsh/1.0" "$1" 2>/dev/null
}

build_catalog() {
  local html rest url zipname anchor trailing zipbase name version compat
  local zip_prefix key endpos
  local -a pl
  local -i count
  CATALOG=(); CATALOG_KEYS=()
  html="$1"
  rest="$html"
  count=0
  while [[ "$rest" =~ '(?s)<a[^>]+href="([^"]*/wp-content/uploads/[0-9]{4}/[0-9]{2}/([^"/]+\.zip))"[^>]*>(.*?)</a>([^<]*)' ]]; do
    endpos=$((mend[4] + 1))
    url="${match[1]}"; zipname="${match[2]}"; anchor="${match[3]}"; trailing="${match[4]}"
    zipbase="${zipname%.zip}"
    pl=( "${(@f)$(parse_link_text "${anchor}${trailing}")}" )
    name="${pl[1]}"; version="${pl[2]}"; compat="${pl[3]}"
    zip_prefix="${zipbase%%[^a-z]*}"
    key=""
    if [[ -n "$zip_prefix" && -n "${ZIP_PREFIX_OVERRIDES[$zip_prefix]}" ]]; then
      key="$(normalize "${ZIP_PREFIX_OVERRIDES[$zip_prefix]}")"
    elif [[ -n "$name" && "$name" != *[[:space:]]* && "$name" == *[a-zA-Z]* ]]; then
      key="$(normalize "$name")"
    elif [[ -n "$zip_prefix" ]]; then
      key="$(normalize "$zip_prefix")"
    fi
    if [[ -z "$key" ]]; then
      (( count++ > 2000 )) && break
      rest="${rest[$endpos,-1]}"
      continue
    fi
    if [[ -z "$version" ]]; then
      [[ -z "$name" ]] && name="$zip_prefix"
      if [[ "$zipbase" =~ '([0-9]+(\.[0-9]+)*[a-zA-Z0-9]*)$' ]]; then version="${match[1]}"; else version=""; fi
      compat=""
    fi
    if [[ -z "$version" ]]; then
      (( count++ > 2000 )) && break
      rest="${rest[$endpos,-1]}"
      continue
    fi
    if [[ -z "${CATALOG[$key]}" ]]; then
      CATALOG[$key]="$name"$'\n'"$version|$url|$compat"
      CATALOG_KEYS+=("$key")
    else
      CATALOG[$key]="${CATALOG[$key]}"$'\n'"$version|$url|$compat"
    fi
    (( count++ > 2000 )) && break
    rest="${rest[$endpos,-1]}"
  done
  apply_catalog_exceptions
}

apply_catalog_exceptions() {
  local alias source
  for alias in deeparchive deepunarchive deepcopy skintm; do
    source="${CATALOG_ALIAS_SOURCE[$alias]}"
    [[ -n "${CATALOG[$alias]}" || -z "${CATALOG[$source]}" ]] && continue
    CATALOG[$alias]="${CATALOG_ALIAS_NAME[$alias]}"$'\n'"${CATALOG[$source]#*$'\n'}"
    CATALOG_KEYS+=("$alias")
  done
  if [[ -z "${CATALOG[appexindexer]}" ]]; then
    CATALOG[appexindexer]="AppexIndexer"$'\n'"1.1|https://eclecticlight.co/wp-content/uploads/2025/06/appexindexer11.zip|(Sonoma 14.6 and later)"
    CATALOG_KEYS+=(appexindexer)
  fi
}

catalog_name() { print -r -- "${CATALOG[$1]%%$'\n'*}" }

catalog_latest() {
  local best rec v
  local -a recs
  recs=( "${(@f)${CATALOG[$1]#*$'\n'}}" )
  best=""
  for rec in "${recs[@]}"; do
    v="$(fld "$rec" 1)"
    if [[ -z "$best" ]] || ver_less "$(fld "$best" 1)" "$v"; then
      best="$rec"
    fi
  done
  print -r -- "$best"
}

fetch_installomator_labels() {
  local text line
  LABELS=()
  text="$(fetch "$INSTALLOMATOR_LABELS_URL")" || return 1
  while IFS= read -r line; do
    [[ -n "$line" ]] && LABELS[${line:l}]=1
  done <<< "$text"
}

find_installomator() {
  local p w
  for p in /usr/local/Installomator/Installomator.sh /usr/local/bin/Installomator.sh \
           /usr/local/bin/installomator /opt/homebrew/bin/installomator /usr/bin/installomator; do
    [[ -x "$p" ]] && { print -r -- "$p"; return 0 }
  done
  w="$(command -v installomator 2>/dev/null)"
  [[ -n "$w" && -x "$w" ]] && { print -r -- "$w"; return 0 }
  return 1
}

read_app() {
  local app info bundle name ver
  app="$1"
  info="$app/Contents/Info.plist"
  [[ -f "$info" ]] || return 1
  bundle="$(plutil -extract CFBundleIdentifier raw -o - "$info" 2>/dev/null)" || return 1
  [[ "$bundle" == "$BUNDLE_PREFIX"* ]] || return 1
  name="$(plutil -extract CFBundleName raw -o - "$info" 2>/dev/null)" || name="${${app:t}%.app}"
  ver="$(plutil -extract CFBundleShortVersionString raw -o - "$info" 2>/dev/null)"
  [[ -z "$ver" ]] && ver="$(plutil -extract CFBundleVersion raw -o - "$info" 2>/dev/null)"
  print -r -- "$app|$bundle|$name|$ver"
}

scan_apps() {
  local dir app rec
  local -a found
  APPS=()
  for dir in "$@"; do
    [[ -d "$dir" ]] || continue
    found=( "${(@f)$(find "$dir" -type d -name '*.app' -print -prune)}" )
    for app in "${found[@]}"; do
      rec="$(read_app "$app")" || continue
      APPS+=("$rec")
    done
  done
}

group_apps() {
  local rec k
  GROUPS=(); KEYS=()
  for rec in "${APPS[@]}"; do
    k="$(app_key "$rec")"
    if [[ -z "${GROUPS[$k]}" ]]; then
      GROUPS[$k]="$rec"
      KEYS+=("$k")
    else
      GROUPS[$k]="${GROUPS[$k]}"$'\n'"$rec"
    fi
  done
}

sort_copies_desc() {
  local rec v
  local -a out
  local -i inserted i
  out=()
  for rec in "$@"; do
    v="$(version_of "$rec")"
    inserted=0
    for ((i = 1; i <= ${#out}; i++)); do
      if ver_less "$v" "$(version_of "${out[$i]}")"; then
        out=( "${out[@]:0:$((i - 1))}" "$rec" "${out[@]:$((i - 1))}" )
        inserted=1
        break
      fi
    done
    (( inserted )) || out+=("$rec")
  done
  print -rl -- "${out[@]}"
}

group_name() { gld "$1" 1 }
group_latest() { local v; v="$(gld "$1" 2)"; [[ "$v" == "-" ]] && v=""; print -r -- "$v" }
group_status() { gld "$1" 3 }
group_action() { gld "$1" 4 }
group_newest_inst() { local v; v="$(gld "$1" 5)"; [[ "$v" == "-" ]] && v=""; print -r -- "$v" }
group_copies() { gld "$1" 6 }
group_target() {
  local ni
  local -a cp
  ni="$(group_newest_inst "$1")"
  if [[ -n "$ni" ]]; then print -r -- "$ni"; return 0; fi
  cp=( "${(@f)$(group_copies "$1")}" )
  print -r -- "${cp[1]}"
}

analyze_groups() {
  local k c gname ni_or_dash latest_or_dash
  local entry_name latest latest_ver newest_inst newest_all active st action
  local copies_joined
  local -a copies installed sorted
  INFO=()
  group_apps
  for k in "${KEYS[@]}"; do
    copies=( "${(@f)GROUPS[$k]}" )
    entry_name=""; latest=""; latest_ver=""
    if [[ -n "${CATALOG[$k]}" ]]; then
      entry_name="$(catalog_name "$k")"
      latest="$(catalog_latest "$k")"
      latest_ver="$(fld "$latest" 1)"
    fi
    installed=()
    for c in "${copies[@]}"; do
      [[ "$(path_of "$c")" == "/Applications"* ]] && installed+=("$c")
    done
    newest_inst=""; newest_all=""
    for c in "${installed[@]}"; do
      [[ -z "$newest_inst" ]] || ver_less "$(version_of "$newest_inst")" "$(version_of "$c")" || continue
      newest_inst="$c"
    done
    for c in "${copies[@]}"; do
      [[ -z "$newest_all" ]] || ver_less "$(version_of "$newest_all")" "$(version_of "$c")" || continue
      newest_all="$c"
    done
    active=0
    if [[ -n "$newest_inst" && "$(path_of "$newest_inst")" != "$ECLECTICLIGHT_FOLDER"* ]]; then
      active=1
    fi
    st="current"; action="—"
    if [[ -n "$newest_inst" && -n "$latest_ver" ]]; then
      if ver_less "$(version_of "$newest_inst")" "$latest_ver"; then
        st="outdated"
        if (( active )) && [[ -n "${LABELS[$k]}" ]]; then action="installomator"; else action="download"; fi
      fi
    elif [[ -n "$latest_ver" && -n "$newest_all" ]]; then
      if ver_less "$(version_of "$newest_all")" "$latest_ver"; then
        st="downloads-only-outdated"; action="download"
      else
        st="downloads-only"
      fi
    elif [[ -z "$newest_inst" ]]; then
      st="downloads-only"
    fi
    gname="${entry_name:-$(name_of "${copies[1]}")}"
    sorted=( "${(@f)$(sort_copies_desc "${copies[@]}")}" )
    copies_joined="${(F)sorted}"
    ni_or_dash="$newest_inst"; [[ -z "$ni_or_dash" ]] && ni_or_dash="-"
    latest_or_dash="$latest_ver"; [[ -z "$latest_or_dash" ]] && latest_or_dash="-"
    INFO[$k]="$gname^$latest_or_dash^$st^$action^$ni_or_dash^$copies_joined"
  done
}

run_privileged() {
  local cmd osa
  cmd="$1"
  if sudo -n true 2>/dev/null; then
    sudo sh -c "$cmd" 2>/dev/null
    return $?
  fi
  osa="do shell script \"${cmd//\"/\\\"}\" with administrator privileges"
  osascript -e "$osa" >/dev/null 2>&1
  return $?
}

confirm_yn() {
  local a
  read "a?$1"
  [[ "${a:l}" == "y" ]]
}

ensure_eclecticlight_folder() {
  local yes
  yes="$1"
  [[ -d "$ECLECTICLIGHT_FOLDER" ]] && return 0
  if [[ "$yes" != "1" ]]; then
    confirm_yn "Create $ECLECTICLIGHT_FOLDER? [y/N] " || {
      print -r -- "Cancelled — $ECLECTICLIGHT_FOLDER not created."
      return 1
    }
  fi
  if mkdir -p "$ECLECTICLIGHT_FOLDER" 2>/dev/null; then
    print -r -- "Created $ECLECTICLIGHT_FOLDER."
    return 0
  fi
  if run_privileged "mkdir -p \"$ECLECTICLIGHT_FOLDER\""; then
    print -r -- "Created $ECLECTICLIGHT_FOLDER."
    return 0
  fi
  print -r -- "Could not create $ECLECTICLIGHT_FOLDER."
  return 1
}

install_installomator() {
  print -r -- "Installomator is not installed."
  print -r -- "It will be installed to /usr/local/Installomator/Installomator.sh"
  print -r -- "(or run: brew install installomator)"
  confirm_yn "Install now? [y/N] " || { print -r -- "Install cancelled."; return 1 }
  if run_privileged "mkdir -p /usr/local/Installomator && curl -fsSL $INSTALLOMATOR_SCRIPT_URL -o /usr/local/Installomator/Installomator.sh && chmod 755 /usr/local/Installomator/Installomator.sh" \
    && [[ -x /usr/local/Installomator/Installomator.sh ]]; then
    print -r -- "Installomator installed at /usr/local/Installomator/Installomator.sh"
    return 0
  fi
  print -r -- "Install failed."
  return 1
}

update_via_installomator() {
  local installomator label
  installomator="$1"; label="$2"
  print -r -- "  running: sudo $installomator $label"
  run_privileged "\"$installomator\" $label NOTIFY=silent"
}

trash() {
  local p
  p="${1//\"/\\\"}"
  osascript -e "tell application \"Finder\" to delete POSIX file \"$p\"" >/dev/null 2>&1
}

deep_clean_parent() {
  local app_path yes parent
  app_path="$1"; yes="$2"
  parent="${app_path:h}"
  [[ "$parent" == "$ECLECTICLIGHT_FOLDER"* ]] || return 0
  [[ -d "$parent" ]] || return 0
  [[ -n "$(ls -A "$parent" 2>/dev/null)" ]] && return 0
  if [[ "$yes" != "1" ]]; then
    confirm_yn "  remove now-empty folder $parent? [y/N] " || return 0
  fi
  if rmdir "$parent" 2>/dev/null; then
    print -r -- "  removed empty folder $parent"
  elif run_privileged "rmdir \"$parent\""; then
    print -r -- "  removed empty folder $parent"
  else
    print -r -- "  could not remove folder $parent"
  fi
}

move_app() {
  local rec dest_dir yes p dest existing
  rec="$1"; dest_dir="$2"; yes="$3"
  p="$(path_of "$rec")"
  dest="$dest_dir/${p:t}"
  if [[ -e "$dest" ]]; then
    existing="$(read_app "$dest")" || existing=""
    if [[ -n "$existing" ]] && [[ "$(bundle_of "$existing")" == "$(bundle_of "$rec")" ]] \
       && [[ "$(version_of "$existing")" == "$(version_of "$rec")" ]]; then
      print -r -- "  $p is a duplicate of $dest — trashing the duplicate"
      if [[ "$yes" == "1" ]] || confirm_yn "  trash duplicate $p? [y/N] "; then
        if trash "$p"; then
          print -r -- "  trashed duplicate $p"
          return 0
        fi
        print -r -- "  trash failed — leaving in place"
        return 1
      fi
      return 1
    fi
    print -r -- "  already exists, skipped: $dest"
    return 1
  fi
  if [[ "$yes" != "1" ]] && ! confirm_yn "  move $p -> $dest? [y/N] "; then
    return 1
  fi
  print -r -- "  moving to $dest"
  run_privileged "mkdir -p \"$dest_dir\" && mv \"$p\" \"$dest\""
}

unique_destination() {
  local folder name stem ext destination suffix
  folder="$1"; name="$2"
  if [[ "$name" == *.* ]]; then
    stem="${name%.*}"; ext=".${name##*.}"
  else
    stem="$name"; ext=""
  fi
  destination="$folder/$name"
  suffix=2
  while [[ -e "$destination" ]]; do
    destination="$folder/$stem-$suffix$ext"
    (( suffix++ ))
  done
  print -r -- "$destination"
}

collect_readme_documents() {
  local readme source destination
  local -a documents
  readme="$ECLECTICLIGHT_FOLDER/$README_FOLDER_NAME"
  documents=()
  while IFS= read -r -d '' source; do documents+=("$source"); done < <(
    find "$ECLECTICLIGHT_FOLDER" \
      \( -type d \( -name '*.app' -o -path "$readme" \) -prune \) -o \
      \( -type f \( -iname '*.pdf' -o -iname '*.rtf' \) -print0 \)
  )
  DOCS_MOVED=0
  for source in "${documents[@]}"; do
    destination="$(unique_destination "$readme" "${source:t}")"
    if run_privileged "mkdir -p \"$readme\" && mv \"$source\" \"$destination\""; then
      print -r -- "  readme: $source -> $destination"
      (( DOCS_MOVED++ ))
    else
      print -r -- "  could not move readme document: $source"
    fi
  done
}

remove_empty_organization_folders() {
  local readme folder i
  local -a folders
  readme="$ECLECTICLIGHT_FOLDER/$README_FOLDER_NAME"
  folders=()
  while IFS= read -r -d '' folder; do folders+=("$folder"); done < <(
    find "$ECLECTICLIGHT_FOLDER" \
      \( -type d \( -name '*.app' -o -path "$readme" \) -prune \) -o \
      \( -type d -print0 \)
  )
  FOLDERS_REMOVED=0
  for (( i = ${#folders}; i >= 1; i-- )); do
    folder="${folders[$i]}"
    [[ "$folder" == "$ECLECTICLIGHT_FOLDER" || "$folder" == "$readme" ]] && continue
    [[ -n "$(ls -A "$folder" 2>/dev/null)" ]] && continue
    if rmdir "$folder" 2>/dev/null || run_privileged "rmdir \"$folder\""; then
      print -r -- "  removed empty folder $folder"
      (( FOLDERS_REMOVED++ ))
    fi
  done
}

download_and_install() {
  local rec key yes latest url tmp zf newest nv r v ver digits dest_dir dest app
  local -a found
  rec="$1"; key="$2"; yes="$3"
  latest="$(catalog_latest "$key")"
  url="$(fld "$latest" 2)"
  [[ -n "$url" ]] || return 1
  ensure_eclecticlight_folder "$yes" || { print -r -- "  cancelled — no EclecticLight folder"; return 1 }
  tmp="/tmp/elu-$key"
  rm -rf "$tmp"; mkdir -p "$tmp"
  zf="$tmp/${url:t}"
  print -r -- "  downloading $url"
  curl -fsSL --max-time 120 "$url" -o "$zf" || { print -r -- "  download failed"; return 1 }
  print -r -- "  unzipping ${zf:t}"
  unzip -o -q "$zf" -d "$tmp" || { print -r -- "  unzip failed"; return 1 }
  found=()
  while IFS= read -r app; do found+=("$app"); done < <(find "$tmp" -type d -name '*.app' -print -prune)
  newest=""; nv=""
  for app in "${found[@]}"; do
    r="$(read_app "$app")" || continue
    [[ "$(app_key "$r")" == "$key" ]] || continue
    v="$(version_of "$r")"
    if [[ -z "$newest" ]] || ver_less "$nv" "$v"; then
      newest="$app"; nv="$v"
    fi
  done
  if [[ -z "$newest" ]]; then
    print -r -- "  no matching co.eclecticlight.$key app found in the download"
    return 1
  fi
  ver="$(fld "$latest" 1)"
  digits="${ver//[^0-9]/}"
  dest_dir="$ECLECTICLIGHT_FOLDER/$key$digits"
  dest="$dest_dir/${newest:t}"
  if [[ -e "$dest" ]]; then
    print -r -- "  $dest already exists"
    return 1
  fi
  if [[ "$yes" != "1" ]] && ! confirm_yn "  move downloaded app into $dest? [y/N] "; then
    return 1
  fi
  run_privileged "mkdir -p \"$dest_dir\" && mv \"$newest\" \"$dest\""
}

sorted_group_keys() {
  print -rl -- "${KEYS[@]}" | while read -r k; do
    print -r -- "$(group_name "${INFO[$k]}")|$k"
done | LC_ALL=C sort -f -s -t '|' -k1,1 | while read -r line; do
    print -r -- "${line#*|}"
  done
}

collect_stale() {
  local k g ni nv c
  local -a cp
  for k in "${KEYS[@]}"; do
    g="${INFO[$k]}"
    [[ "$(group_status "$g")" == "current" ]] || continue
    ni="$(group_newest_inst "$g")"
    [[ -n "$ni" ]] || continue
    nv="$(version_of "$ni")"
    cp=( "${(@f)$(group_copies "$g")}" )
    for c in "${cp[@]}"; do
      [[ "$(path_of "$c")" == "/Applications"* && "$c" != "$ni" ]] || continue
      ver_less "$(version_of "$c")" "$nv" || continue
      print -r -- "$c"
    done
  done
}

print_report() {
  local now k g name st latest target newest_inst c p v loc sts star
  local ck mk mv mu r out
  local -a sorted copies missing loose stale outdated_groups
  now="$(date +%F)"
  print -r -- "Eclectic Light apps found on this Mac — $now"
  print -r -- "Catalog source: $SITE_URL"
  print -r -- "Installomator:  ${INSTALLOMATOR:-NOT INSTALLED}"
  print -r -- ""
  analyze_groups
  printf '%-24s %-10s %-13s %-18s %s\n' App Version Location Status Path
  print -r -- "----------------------------------------------------------------------------------------------------"
  sorted=( "${(@f)$(sorted_group_keys)}" )
  for k in "${sorted[@]}"; do
    g="${INFO[$k]}"
    name="$(group_name "$g")"
    st="$(group_status "$g")"
    latest="$(group_latest "$g")"
    target="$(group_target "$g")"
    newest_inst="$(group_newest_inst "$g")"
    copies=( "${(@f)$(group_copies "$g")}" )
    for c in "${copies[@]}"; do
      p="$(path_of "$c")"; v="$(version_of "$c")"; loc="$(app_location "$p")"
      if [[ -z "$latest" ]]; then
        sts="no catalog entry"
      elif { [[ "$st" == "outdated" || "$st" == "downloads-only-outdated" ]] } && [[ "$c" == "$target" ]]; then
        sts="UPDATE AVAILABLE"
      elif ! ver_less "$v" "$latest"; then
        sts="up to date"
      else
        sts="stale copy"
      fi
      star=" "
      [[ -n "$newest_inst" && "$c" == "$newest_inst" ]] && star="*"
      printf '%-24s %-10s %-13s %-18s %s%s\n' "$name" "$v" "$loc" "$sts" "$p" "$star"
    done
    if [[ "$st" == "outdated" || "$st" == "downloads-only-outdated" ]]; then
      print -r -- "    installed -> $latest  ($(group_action "$g"))"
    fi
    print -r -- ""
  done
  print -r -- ""
  if [[ ${#CATALOG} -eq 0 ]]; then
    print -r -- "Catalog empty — run without --offline to fetch versions."
    return 0
  fi
  missing=()
  for ck in "${CATALOG_KEYS[@]}"; do
    [[ -n "${INFO[$ck]}" ]] && continue
    [[ -n "${NON_APP[$ck]}" ]] && continue
    missing+=("$ck")
  done
  if [[ ${#missing} -gt 0 ]]; then
    print -r -- "Eclectic Light apps on the site but not installed:"
    for mk in "${(@f)$(print -rl -- "${missing[@]}" | while read -r line; do print -r -- "$(catalog_name "$line")|$line"; done | LC_ALL=C sort -s -t '|' -k1,1 | while read -r line; do print -r -- "${line#*|}"; done)}"; do
      mv="$(fld "$(catalog_latest "$mk")" 1)"
      mu="$(fld "$(catalog_latest "$mk")" 2)"
      printf '    %-24s latest %s  %s\n' "$(catalog_name "$mk")" "$mv" "$mu"
    done
    print -r -- ""
  fi
  loose=()
  for r in "${APPS[@]}"; do
    needs_organization "$r" && loose+=("$r")
  done
  if [[ ${#loose} -gt 0 ]]; then
    print -r -- "${#loose} copy/copies need organization."
    print -r -- "Flatten them into the main folder: ./$SELF organize"
    print -r -- ""
  fi
  stale=()
  out="$(collect_stale)"
  [[ -n "$out" ]] && stale=( "${(@f)$out}" )
  outdated_groups=()
  for k in "${KEYS[@]}"; do
    st="$(group_status "${INFO[$k]}")"
    [[ "$st" == "outdated" || "$st" == "downloads-only-outdated" ]] && outdated_groups+=("$k")
  done
  if [[ ${#stale} -gt 0 ]]; then
    print -r -- "${#stale} stale installed copy/copies of already-current apps:"
    for c in "${stale[@]}"; do
      print -r -- "  $(name_of "$c") $(version_of "$c") (current is $(group_latest "${INFO[$(app_key "$c")]}"))  $(path_of "$c")"
    done
    print -r -- "Clean them up: ./$SELF update"
    print -r -- ""
  fi
  if [[ ${#outdated_groups} -eq 0 && ${#stale} -eq 0 ]]; then
    print -r -- "All found Eclectic Light apps are up to date."
    return 0
  fi
  if [[ ${#outdated_groups} -gt 0 ]]; then
    print -r -- "${#outdated_groups} app(s) out of date:"
    for k in "${outdated_groups[@]}"; do
      g="${INFO[$k]}"
      target="$(group_target "$g")"
      print -r -- "  $(group_name "$g") $(version_of "$target") -> $(group_latest "$g")  ($(group_action "$g"))  $(path_of "$target")"
    done
    if [[ -n "$INSTALLOMATOR" ]]; then
      print -r -- "Run: ./$SELF update"
    else
      print -r -- "Run: ./$SELF update   (Installomator not installed — apps without a label are downloaded)"
    fi
  fi
}

update_outdated() {
  local only_label yes k st ni nv c key g name latest action target tver ok cp
  local -a info_keys outdated stale_recs copies
  only_label="$1"; yes="$2"
  analyze_groups
  info_keys=( "${(@f)$(sorted_group_keys)}" )
  outdated=(); stale_recs=()
  for k in "${info_keys[@]}"; do
    [[ -n "$only_label" && "$k" != "$only_label" ]] && continue
    st="$(group_status "${INFO[$k]}")"
    if [[ "$st" == "outdated" || "$st" == "downloads-only-outdated" ]]; then
      outdated+=("$k")
    elif [[ "$st" == "current" ]]; then
      ni="$(group_newest_inst "${INFO[$k]}")"
      [[ -n "$ni" ]] || continue
      nv="$(version_of "$ni")"
      copies=( "${(@f)$(group_copies "${INFO[$k]}")}" )
      for c in "${copies[@]}"; do
        [[ "$(path_of "$c")" == "/Applications"* && "$c" != "$ni" ]] || continue
        ver_less "$(version_of "$c")" "$nv" || continue
        stale_recs+=("$c")
      done
    fi
  done
  if [[ ${#outdated} -eq 0 && ${#stale_recs} -eq 0 ]]; then
    print -r -- "Nothing to update."
    return 0
  fi
  for key in "${outdated[@]}"; do
    g="${INFO[$key]}"
    name="$(group_name "$g")"
    latest="$(group_latest "$g")"
    action="$(group_action "$g")"
    target="$(group_target "$g")"
    tver="$(version_of "$target")"
    print -r -- ""
    print -r -- "$name: $tver -> $latest"
    ok=0
    if [[ "$action" == "installomator" ]]; then
      if [[ -z "$INSTALLOMATOR" ]]; then
        install_installomator || continue
        INSTALLOMATOR="$(find_installomator)"
        [[ -n "$INSTALLOMATOR" ]] || continue
      fi
      [[ "$yes" == "1" ]] || confirm_yn "  update with Installomator? [y/N] " || continue
      if update_via_installomator "$INSTALLOMATOR" "$key"; then
        ok=1; print -r -- "  OK"
      else
        print -r -- "  FAILED"
      fi
    else
      [[ "$yes" == "1" ]] || confirm_yn "  download latest into /Applications/EclecticLight? [y/N] " || continue
      if download_and_install "$target" "$key" "$yes"; then
        ok=1; print -r -- "  OK"
      else
        print -r -- "  SKIPPED/FAILED"
      fi
    fi
    if (( ok )); then
      copies=( "${(@f)$(group_copies "$g")}" )
      for c in "${copies[@]}"; do
        cp="$(path_of "$c")"
        [[ "$cp" == "/Applications"* ]] || continue
        [[ "$action" == "installomator" && "$c" == "$target" ]] && continue
        [[ "$yes" == "1" ]] || confirm_yn "  trash old copy $cp? [y/N] " || continue
        if trash "$cp"; then
          print -r -- "  trashed $cp"
          deep_clean_parent "$cp" "$yes"
        fi
      done
    fi
  done
  if [[ ${#stale_recs} -gt 0 ]]; then
    print -r -- ""
    print -r -- "Cleaning up ${#stale_recs} stale installed copy/copies:"
    for c in "${stale_recs[@]}"; do
      cp="$(path_of "$c")"
      [[ "$yes" == "1" ]] || confirm_yn "  trash old copy $cp? [y/N] " || continue
      if trash "$cp"; then
        print -r -- "  trashed $cp"
        deep_clean_parent "$cp" "$yes"
      fi
    done
  fi
  print -r -- ""
  print -r -- "Tip: ./$SELF organize flattens apps and collects PDF/RTF files in ReadMe/."
  return 0
}

organize() {
  local yes rec c moved
  local -a candidates sorted
  yes="$1"
  print -r -- "Flattening apps into $ECLECTICLIGHT_FOLDER/ …"
  candidates=()
  for rec in "${APPS[@]}"; do
    needs_organization "$rec" && candidates+=("$rec")
  done
  if [[ ${#candidates} -eq 0 && ! -d "$ECLECTICLIGHT_FOLDER" ]]; then
    print -r -- "Nothing to organize."
    return 0
  fi
  ensure_eclecticlight_folder "$yes" || return 1
  sorted=( "${(@f)$(print -rl -- "${candidates[@]}" | while read -r line; do print -r -- "$(app_key "$line")|$line"; done | sort | while read -r line; do print -r -- "${line#*|}"; done)}" )
  moved=0
  for c in "${sorted[@]}"; do
    move_app "$c" "$ECLECTICLIGHT_FOLDER" "$yes" && (( moved++ ))
  done
  DOCS_MOVED=0
  FOLDERS_REMOVED=0
  if [[ "$yes" == "1" ]] || confirm_yn "  collect PDF/RTF documents and remove empty folders? [y/N] "; then
    collect_readme_documents
    remove_empty_organization_folders
  fi
  print -r -- "Moved $moved app copy/copies into $ECLECTICLIGHT_FOLDER/"
  print -r -- "Moved $DOCS_MOVED PDF/RTF document(s) into $ECLECTICLIGHT_FOLDER/$README_FOLDER_NAME/"
  print -r -- "Removed $FOLDERS_REMOVED empty folder(s)"
}

mode="check"
apps_only=0
yes=0
offline=0
do_install_installomator=0
only_label=""
also=()

while (( $# )); do
  case "$1" in
    check|update|organize) mode="$1" ;;
    --apps-only) apps_only=1 ;;
    --yes|-y) yes=1 ;;
    --offline) offline=1 ;;
    --install-installomator) do_install_installomator=1 ;;
    --only-label) shift; only_label="$1" ;;
    --only-label=*) only_label="${1#*=}" ;;
    --also) shift; also+=("$1") ;;
    --also=*) also+=("${1#*=}") ;;
    -h|--help) usage; exit 0 ;;
    *) print -r -- "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if (( do_install_installomator )); then
  local_p="$(find_installomator)"
  if [[ -n "$local_p" ]]; then
    print -r -- "Installomator is already installed at $local_p"
  else
    install_installomator
  fi
  exit 0
fi

scan_dirs=("${DEFAULT_SEARCH_DIRS[@]}")
(( apps_only )) && scan_dirs=(/Applications "$HOME/Applications")
scan_dirs+=("${also[@]}")

scan_apps "${scan_dirs[@]}"
if [[ ${#APPS} -eq 0 ]]; then
  print -r -- "No Eclectic Light apps found in: ${(j:, :)scan_dirs}"
  exit 0
fi

if (( ! offline )); then
  print -r -- "Fetching catalog from eclecticlight.co …"
  if html="$(fetch "$SITE_URL")"; then
    build_catalog "$html"
  else
    print -r -- "Warning: could not fetch $SITE_URL" >&2
  fi
  print -r -- "Fetching Installomator labels …"
  fetch_installomator_labels
fi

INSTALLOMATOR="$(find_installomator)"

case "$mode" in
  update) update_outdated "$only_label" "$yes" ;;
  organize) organize "$yes" ;;
  *) print_report ;;
esac
exit 0
