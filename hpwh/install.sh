#!/usr/bin/env bash
# ==============================================================================
# HPWH Component Installer for Home Assistant
# Installs hpwh.yaml package, hpwh-card.js, and registers Lovelace dashboard resource.
#
# Usage (in Home Assistant Terminal / SSH):
#   curl -fsSL https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh/install.sh | bash
#
# Options:
#   -c, --config <dir>   Specify Home Assistant configuration directory
#   --local [dir]        Use local repository files instead of downloading
#   --force              Overwrite locally modified packages without confirmation
#   --dry-run            Display planned actions without making any changes
#   -y, --yes            Skip confirmation prompts
#   --uninstall          Remove installed package, card, and Lovelace registration
#   -h, --help           Show help
# ==============================================================================

set -euo pipefail

HPWH_VERSION="1.2.0"
GITHUB_RAW="https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh"
CONFIG_DIR="${HA_CONFIG_DIR:-}"
SCRIPT_DIR=""
LOCAL_MODE=false
FORCE=false
DRY_RUN=false
UNINSTALL=false
CONFIRM_YES=false

# Temporary files tracked for cleanup
TMP_FILES=()
cleanup() {
  for f in "${TMP_FILES[@]:-}"; do
    if [[ -f "${f}" ]]; then
      rm -f "${f}"
    fi
  done
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      if [[ $# -lt 2 || "$2" =~ ^- ]]; then
        echo "❌ Error: Option $1 requires a directory path argument."
        exit 1
      fi
      CONFIG_DIR="$2"
      shift 2
      ;;
    --local)
      LOCAL_MODE=true
      if [[ $# -ge 2 && ! "$2" =~ ^- ]]; then
        SCRIPT_DIR="$2"
        shift 2
      else
        shift
      fi
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -y|--yes)
      CONFIRM_YES=true
      shift
      ;;
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    -h|--help)
      cat << 'EOF'
HPWH Component Installer for Home Assistant

Usage:
  bash install.sh [options]
  curl -fsSL https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh/install.sh | bash -s -- [options]

Options:
  -c, --config <dir>   Specify Home Assistant configuration directory
  --local [dir]        Use local files from repository checkout
  --force              Overwrite local modifications in hpwh.yaml
  --dry-run            Show what would be done without modifying any files
  -y, --yes            Non-interactive mode (skip confirmation prompts)
  --uninstall          Remove installed HPWH package, card, and dashboard resource
  -h, --help           Show this help message
EOF
      exit 0
      ;;
    *)
      echo "❌ Error: Unknown option: $1"
      echo "Run with -h or --help for available options."
      exit 1
      ;;
  esac
done

# ------------------------------------------------------------------------------
# Upfront Dependency Checks (I9)
# ------------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Error: python3 is required by this installer but was not found."
  echo "Please install python3 or use the Advanced SSH & Web Terminal add-on."
  exit 1
fi

# Detect script directory (for --local mode) if not explicitly passed (I6)
if [[ -z "${SCRIPT_DIR}" && -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ "${LOCAL_MODE}" = true ]]; then
  if [[ -z "${SCRIPT_DIR}" || ! -f "${SCRIPT_DIR}/hpwh.yaml" || ! -f "${SCRIPT_DIR}/hpwh-card.js" ]]; then
    echo "❌ Error: --local specified but could not locate hpwh.yaml and hpwh-card.js in script directory."
    exit 1
  fi
else
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "❌ Error: Neither curl nor wget was found. One of them is required to download component files."
    exit 1
  fi
fi

# ------------------------------------------------------------------------------
# Locate & Validate Configuration Directory
# ------------------------------------------------------------------------------
if [[ -z "${CONFIG_DIR}" ]]; then
  if [[ -f "/config/configuration.yaml" ]]; then
    CONFIG_DIR="/config"
  elif [[ -f "/homeassistant/configuration.yaml" ]]; then
    CONFIG_DIR="/homeassistant"
  else
    echo "❌ Error: Could not locate Home Assistant configuration directory (/config or /homeassistant)."
    echo "Please specify your config directory using: bash install.sh -c /path/to/config"
    exit 1
  fi
fi

CONFIG_FILE="${CONFIG_DIR}/configuration.yaml"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "❌ Error: configuration.yaml not found in ${CONFIG_DIR}"
  exit 1
fi

# ------------------------------------------------------------------------------
# Pre-Flight Check 1: Analyze configuration.yaml (R1, R2, R3, R8)
# ------------------------------------------------------------------------------
CONFIG_STATUS=$(python3 - "${CONFIG_FILE}" << 'EOF'
import sys, re, json

config_path = sys.argv[1]
with open(config_path, "r", encoding="utf-8", errors="replace") as f:
    lines = f.readlines()

has_ha_block = False
ha_line_idx = -1
ha_is_simple = False
ha_indent = None
packages_configured = False
packages_dir = "packages"
packages_mode = "none"
lovelace_yaml_mode = False

in_ha_block = False
in_lovelace_block = False

for idx, line in enumerate(lines):
    # Match top-level homeassistant: block
    if re.match(r"^homeassistant:\s*(?:#.*)?$", line):
        has_ha_block = True
        ha_line_idx = idx
        ha_is_simple = True
        in_ha_block = True
        in_lovelace_block = False
        continue
    elif re.match(r"^homeassistant:\s*.+", line):
        has_ha_block = True
        ha_line_idx = idx
        ha_is_simple = False
        in_ha_block = False
        in_lovelace_block = False
        continue

    # Match top-level lovelace: block
    if re.match(r"^lovelace:\s*(?:#.*)?$", line):
        in_lovelace_block = True
        in_ha_block = False
        continue

    # Leaving block if another unindented top-level key is encountered
    if (in_ha_block or in_lovelace_block) and re.match(r"^[a-zA-Z0-9_-]+:", line):
        in_ha_block = False
        in_lovelace_block = False

    if in_lovelace_block:
        if re.match(r"^\s+(?:mode|resource_mode):\s*yaml", line):
            lovelace_yaml_mode = True

    if in_ha_block:
        m_child = re.match(r"^(\s+)[a-zA-Z0-9_-]+:", line)
        if m_child:
            indent_len = len(m_child.group(1))
            if ha_indent is None:
                ha_indent = indent_len

        m_pkg = re.match(r"^\s+packages:\s*(.*)$", line)
        if m_pkg:
            packages_configured = True
            rest = m_pkg.group(1).strip()
            m_dir = re.search(r"!include_dir_named\s+([a-zA-Z0-9_/-]+)", rest)
            if m_dir:
                packages_dir = m_dir.group(1)
                packages_mode = "dir_named"
            elif re.search(r"!include_dir_merge_named", rest):
                m_dir_merge = re.search(r"!include_dir_merge_named\s+([a-zA-Z0-9_/-]+)", rest)
                if m_dir_merge:
                    packages_dir = m_dir_merge.group(1)
                packages_mode = "merge_named"
            elif rest:
                packages_mode = "other"
            else:
                packages_mode = "mapping"

result = {
    "has_ha_block": has_ha_block,
    "ha_line_idx": ha_line_idx,
    "ha_is_simple": ha_is_simple,
    "ha_indent": ha_indent,
    "packages_configured": packages_configured,
    "packages_dir": packages_dir,
    "packages_mode": packages_mode,
    "lovelace_yaml_mode": lovelace_yaml_mode
}
print(json.dumps(result))
EOF
)

PKG_CONFIGURED=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["packages_configured"])')
PKG_DIR_NAME=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["packages_dir"])')
PKG_MODE=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["packages_mode"])')
HAS_HA=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["has_ha_block"])')
HA_SIMPLE=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["ha_is_simple"])')
HA_INDENT=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["ha_indent"])')
LOVELACE_YAML_MODE=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["lovelace_yaml_mode"])')

# Use detected packages directory (R1)
PACKAGES_DIR="${CONFIG_DIR}/${PKG_DIR_NAME}"
WWW_DIR="${CONFIG_DIR}/www"
STORAGE_DIR="${CONFIG_DIR}/.storage"

# Verify packages mode compatibility (R3)
if [[ "${PKG_MODE}" == "merge_named" ]]; then
  echo "❌ Error: 'packages:' is configured with !include_dir_merge_named (${PKG_DIR_NAME})."
  echo "   hpwh.yaml uses standard !include_dir_named format. In merge_named mode, each package"
  echo "   file must be enclosed under a top-level key (e.g. 'hpwh:')."
  echo "   Please see the HPWH README for manual setup instructions with merge_named."
  exit 2
fi

if [[ "${PKG_MODE}" == "mapping" || "${PKG_MODE}" == "other" ]]; then
  echo "❌ Error: 'packages:' is configured as an inline mapping or custom include in configuration.yaml."
  echo "   Please add 'hpwh: !include packages/hpwh.yaml' directly to your packages mapping."
  exit 2
fi

MANUAL_CONFIG_REQUIRED=false
if [[ "${PKG_CONFIGURED}" != "True" && "${PKG_CONFIGURED}" != "true" ]]; then
  if [[ "${HAS_HA}" == "True" || "${HAS_HA}" == "true" ]]; then
    if [[ "${HA_SIMPLE}" != "True" && "${HA_SIMPLE}" != "true" ]] || [[ "${HA_INDENT}" != "None" && "${HA_INDENT}" != "2" ]]; then
      MANUAL_CONFIG_REQUIRED=true
    fi
  fi
fi

# ------------------------------------------------------------------------------
# Pre-Flight Check 2: Parse .storage/lovelace_resources (I2, R5)
# ------------------------------------------------------------------------------
STORAGE_FILE="${STORAGE_DIR}/lovelace_resources"
if [[ -f "${STORAGE_FILE}" ]]; then
  if ! python3 - "${STORAGE_FILE}" << 'EOF' >/dev/null 2>&1; then
import sys, json
with open(sys.argv[1], "r", encoding="utf-8") as f:
    content = f.read()
    if not content.strip():
        sys.exit(1)
    data = json.loads(content)
    if not isinstance(data, dict) or "data" not in data:
        sys.exit(1)
EOF
    echo "❌ Error: Could not parse existing ${STORAGE_FILE} (invalid JSON or corrupt data)."
    echo "Aborting before making any changes to prevent overwriting dashboard resources."
    exit 1
  fi
fi

# ------------------------------------------------------------------------------
# Pre-Flight Check 3: Duplicate unique_id Check (I8, R5)
# ------------------------------------------------------------------------------
TARGET_PKG="${PACKAGES_DIR}/hpwh.yaml"
DUPLICATES=$(python3 - "${CONFIG_DIR}" "${TARGET_PKG}" << 'EOF'
import os, sys

config_dir = sys.argv[1]
target_pkg = sys.argv[2]
matches = []

for root, dirs, files in os.walk(config_dir):
    if any(p in root for p in [".git", "blueprints"]):
        continue
    for f in files:
        if f.endswith(".yaml") or f.endswith(".yml"):
            full_path = os.path.join(root, f)
            if os.path.abspath(full_path) == os.path.abspath(target_pkg) or ".hpwh.bak" in f:
                continue
            try:
                with open(full_path, "r", encoding="utf-8", errors="ignore") as fh:
                    for line in fh:
                        if "unique_id:" in line and "water_heater_state_of_charge" in line:
                            matches.append(full_path)
                            break
            except Exception:
                pass

if matches:
    print("\n".join(matches))
EOF
)

if [[ -n "${DUPLICATES}" ]]; then
  echo "⚠ Warning: Found existing 'unique_id: water_heater_state_of_charge' in:"
  while IFS= read -r dup; do
    echo "    • ${dup}"
  done <<< "${DUPLICATES}"
  echo "  Please remove or comment out legacy template sensors to avoid duplicate entity conflicts."
fi

# ------------------------------------------------------------------------------
# Uninstall Routine (R11)
# ------------------------------------------------------------------------------
if [[ "${UNINSTALL}" = true ]]; then
  echo "=========================================================="
  echo "  Uninstalling Heat Pump Water Heater (HPWH) Component"
  echo "  Target: ${CONFIG_DIR}"
  echo "=========================================================="

  if [[ "${CONFIRM_YES}" != true && -t 0 && -t 1 && -r /dev/tty ]]; then
    read -r -p "Are you sure you want to uninstall HPWH files and unregister dashboard resource? [y/N] " response </dev/tty
    case "$response" in
      [yY][eE][sS]|[yY]) ;;
      *) echo "Uninstall cancelled."; exit 0 ;;
    esac
  fi

  if [[ "${DRY_RUN}" = true ]]; then
    echo "▶ [DRY-RUN] Would backup and remove ${TARGET_PKG}"
    echo "▶ [DRY-RUN] Would remove ${WWW_DIR}/hpwh-card.js"
    echo "▶ [DRY-RUN] Would unregister dashboard resource in ${STORAGE_FILE}"
    exit 0
  fi

  if [[ -f "${TARGET_PKG}" ]]; then
    ts="$(date +%Y%m%d%H%M%S)"
    cp -p "${TARGET_PKG}" "${TARGET_PKG}.bak-${ts}"
    rm -f "${TARGET_PKG}"
    rm -f "${PACKAGES_DIR}/.hpwh_installed.sha256"
    echo "  ✔ Backed up and removed ${TARGET_PKG}"
  fi
  rm -f "${WWW_DIR}/hpwh-card.js"
  echo "  ✔ Removed card file."

  STORAGE_DIR="${STORAGE_DIR}" python3 - << 'EOF'
import os, json, sys

storage_file = os.path.join(os.environ["STORAGE_DIR"], "lovelace_resources")
if os.path.isfile(storage_file):
    try:
        with open(storage_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"❌ Error reading {storage_file}: {e}", file=sys.stderr)
        sys.exit(1)

    items = data.get("data", {}).get("items", [])
    new_items = [i for i in items if isinstance(i, dict) and i.get("url", "").split("?")[0] != "/local/hpwh-card.js"]
    if len(new_items) != len(items):
        data["data"]["items"] = new_items
        tmp_file = f"{storage_file}.tmp"
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp_file, storage_file)
        print("  ✔ Unregistered Lovelace dashboard resource.")
EOF

  if [[ -f "${CONFIG_FILE}.hpwh.bak" ]]; then
    echo "  ℹ Note: A backup of your original configuration exists at ${CONFIG_FILE}.hpwh.bak"
  fi
  echo "=========================================================="
  echo "  ✔ Uninstall complete. Restart Home Assistant to apply changes."
  echo "=========================================================="
  exit 0
fi

# ------------------------------------------------------------------------------
# Confirmation Prompt (R9)
# ------------------------------------------------------------------------------
echo "=========================================================="
echo "  Installing Heat Pump Water Heater (HPWH) Component v${HPWH_VERSION}"
echo "  Target: ${CONFIG_DIR}"
echo "  Package Directory: ${PACKAGES_DIR}"
if [[ "${DRY_RUN}" = true ]]; then
  echo "  Mode: DRY-RUN (no changes will be written)"
fi
echo "=========================================================="

if [[ "${CONFIRM_YES}" != true && "${DRY_RUN}" != true && -t 0 && -t 1 && -r /dev/tty ]]; then
  read -r -p "Proceed with installation? [y/N] " response </dev/tty
  case "$response" in
    [yY][eE][sS]|[yY]) ;;
    *) echo "Installation cancelled."; exit 0 ;;
  esac
fi

# ------------------------------------------------------------------------------
# 1. Safe File Fetching & Customization Protection (I1, R1, R4, R10)
# ------------------------------------------------------------------------------
fetch_staged_file() {
  local rel_path="$1"
  local file_type="$2"

  local staging_file
  staging_file="$(mktemp "${CONFIG_DIR}/.hpwh_staging_XXXXXX")"
  TMP_FILES+=("${staging_file}")

  if [[ "${LOCAL_MODE}" = true && -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/${rel_path}" ]]; then
    cp "${SCRIPT_DIR}/${rel_path}" "${staging_file}"
  else
    local download_url="${GITHUB_RAW}/${rel_path}"
    if command -v curl >/dev/null 2>&1; then
      if ! curl -fsSL "${download_url}" -o "${staging_file}"; then
        echo "❌ Error: Failed to download ${download_url} (HTTP error or connection failure)." >&2
        exit 1
      fi
    elif command -v wget >/dev/null 2>&1; then
      if ! wget -qO "${staging_file}" "${download_url}"; then
        echo "❌ Error: Failed to download ${download_url} with wget." >&2
        exit 1
      fi
    fi
  fi

  # Validate downloaded content
  if [[ ! -s "${staging_file}" ]]; then
    echo "❌ Error: Received empty file for ${rel_path}." >&2
    exit 1
  fi

  if [[ "${file_type}" == "yaml" ]]; then
    if ! grep -q "water_heater_state_of_charge" "${staging_file}" && ! grep -q "template:" "${staging_file}"; then
      echo "❌ Error: Validation failed for ${rel_path}. Invalid YAML structure or unexpected content." >&2
      exit 1
    fi
  elif [[ "${file_type}" == "js" ]]; then
    if ! grep -q "hpwh-card" "${staging_file}" && ! grep -q "HpwhCard" "${staging_file}"; then
      echo "❌ Error: Validation failed for ${rel_path}. Invalid JavaScript content." >&2
      exit 1
    fi
  fi

  echo "${staging_file}"
}

echo "▶ Installing sensor package (hpwh.yaml)..."
if [[ "${DRY_RUN}" = true ]]; then
  echo "▶ [DRY-RUN] Would install hpwh.yaml to ${TARGET_PKG}"
else
  mkdir -p "${PACKAGES_DIR}"
  STAGED_PKG="$(fetch_staged_file "hpwh.yaml" "yaml")"
  HASH_FILE="${PACKAGES_DIR}/.hpwh_installed.sha256"

  if [[ -f "${TARGET_PKG}" ]]; then
    CURRENT_SHA=$(python3 -c "import hashlib; print(hashlib.sha256(open('${TARGET_PKG}', 'rb').read()).hexdigest())")
    NEW_SHA=$(python3 -c "import hashlib; print(hashlib.sha256(open('${STAGED_PKG}', 'rb').read()).hexdigest())")

    if [[ "${CURRENT_SHA}" == "${NEW_SHA}" ]]; then
      echo "  ✔ hpwh.yaml is already up to date."
    else
      LAST_INSTALLED_SHA=""
      if [[ -f "${HASH_FILE}" ]]; then
        LAST_INSTALLED_SHA=$(cat "${HASH_FILE}" | tr -d ' \n\r')
      fi

      if [[ -n "${LAST_INSTALLED_SHA}" && "${CURRENT_SHA}" != "${LAST_INSTALLED_SHA}" && "${FORCE}" != true ]]; then
        # Local modifications detected (R4)
        ts="$(date +%Y%m%d%H%M%S)"
        UPSTREAM_FILE="${TARGET_PKG}.upstream-${ts}"
        cp "${STAGED_PKG}" "${UPSTREAM_FILE}"
        echo "  ⚠ Note: Existing hpwh.yaml contains local modifications."
        echo "    Your customized file was PRESERVED."
        echo "    Latest upstream package saved to: ${UPSTREAM_FILE}"
        echo "    (To overwrite local edits, re-run with --force)."
      else
        if [[ "${FORCE}" == true && -n "${LAST_INSTALLED_SHA}" && "${CURRENT_SHA}" != "${LAST_INSTALLED_SHA}" ]]; then
          ts="$(date +%Y%m%d%H%M%S)"
          cp -p "${TARGET_PKG}" "${TARGET_PKG}.bak-${ts}"
          echo "  ℹ Backed up customized hpwh.yaml to ${TARGET_PKG}.bak-${ts}"
        fi
        mv -f "${STAGED_PKG}" "${TARGET_PKG}"
        python3 -c "import hashlib; open('${HASH_FILE}', 'w').write(hashlib.sha256(open('${TARGET_PKG}', 'rb').read()).hexdigest() + '\n')"
        echo "  ✔ Placed at ${TARGET_PKG}"
        # Keep at most 3 backups
        find "${PACKAGES_DIR}" -name "hpwh.yaml.bak-*" | sort -r | tail -n +4 | xargs rm -f 2>/dev/null || true
      fi
    fi
  else
    mv -f "${STAGED_PKG}" "${TARGET_PKG}"
    python3 -c "import hashlib; open('${HASH_FILE}', 'w').write(hashlib.sha256(open('${TARGET_PKG}', 'rb').read()).hexdigest() + '\n')"
    echo "  ✔ Placed at ${TARGET_PKG}"
  fi
fi

# ------------------------------------------------------------------------------
# 2. Install Dashboard Card (hpwh-card.js) (R10)
# ------------------------------------------------------------------------------
echo "▶ Installing dashboard card (hpwh-card.js)..."
TARGET_CARD="${WWW_DIR}/hpwh-card.js"
if [[ "${DRY_RUN}" = true ]]; then
  echo "▶ [DRY-RUN] Would install hpwh-card.js to ${TARGET_CARD}"
else
  mkdir -p "${WWW_DIR}"
  STAGED_CARD="$(fetch_staged_file "hpwh-card.js" "js")"
  if [[ -f "${TARGET_CARD}" ]] && cmp -s "${TARGET_CARD}" "${STAGED_CARD}"; then
    echo "  ✔ hpwh-card.js is already up to date."
  else
    mv -f "${STAGED_CARD}" "${TARGET_CARD}"
    echo "  ✔ Placed at ${TARGET_CARD}"
  fi
fi

CARD_VERSION="${HPWH_VERSION}"
if [[ -f "${TARGET_CARD}" ]]; then
  EXTRACTED_VER=$(grep -oE "const CARD_VERSION = [\"'][^\"']+[\"']" "${TARGET_CARD}" | head -1 | cut -d'"' -f2 | cut -d"'" -f2 || true)
  if [[ -n "${EXTRACTED_VER}" ]]; then
    CARD_VERSION="${EXTRACTED_VER}"
  fi
fi

# ------------------------------------------------------------------------------
# 3. Safe configuration.yaml Python-based Edit & Verification (R2, R5)
# ------------------------------------------------------------------------------
echo "▶ Checking configuration.yaml for package support..."

if [[ "${PKG_CONFIGURED}" == "True" ]]; then
  echo "  ✔ Packages already configured in configuration.yaml (${PKG_DIR_NAME})"
elif [[ "${MANUAL_CONFIG_REQUIRED}" == true ]]; then
  echo "  ⚠ Note: 'homeassistant:' block uses custom indentation or split includes."
  echo "    Automatic editing skipped to prevent configuration corruption."
else
  if [[ "${DRY_RUN}" = true ]]; then
    echo "▶ [DRY-RUN] Would configure packages in configuration.yaml"
  else
    BACKUP_CONFIG="${CONFIG_FILE}.hpwh.bak"
    cp -p "${CONFIG_FILE}" "${BACKUP_CONFIG}"
    echo "  ℹ Backed up original configuration to ${BACKUP_CONFIG}"

    # Pure Python insertion preserving CRLF/LF line endings (R2)
    python3 - "${CONFIG_FILE}" << 'EOF'
import sys, re, os

config_path = sys.argv[1]
with open(config_path, "r", encoding="utf-8", errors="replace") as f:
    content = f.read()

newline = "\r\n" if "\r\n" in content else "\n"
lines = content.split(newline)

ha_idx = -1
for idx, line in enumerate(lines):
    if re.match(r"^homeassistant:\s*(?:#.*)?$", line):
        ha_idx = idx
        break

if ha_idx >= 0:
    lines.insert(ha_idx + 1, "  packages: !include_dir_named packages")
else:
    if lines and lines[-1] != "":
        lines.append("")
    lines.append("# Home Assistant Packages (enabled by HPWH installer)")
    lines.append("homeassistant:")
    lines.append("  packages: !include_dir_named packages")
    lines.append("")

tmp_path = f"{config_path}.tmp"
with open(tmp_path, "w", encoding="utf-8") as f:
    f.write(newline.join(lines))
os.replace(tmp_path, config_path)
EOF

    # Verify insertion result (R2)
    VERIFY_STATUS=$(python3 - "${CONFIG_FILE}" << 'EOF'
import sys, re, json
with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
    content = f.read()
packages_ok = bool(re.search(r"^\s+packages:\s*!include_dir_named\s+packages", content, re.MULTILINE))
print(json.dumps({"ok": packages_ok}))
EOF
)
    IS_OK=$(echo "${VERIFY_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["ok"])')
    if [[ "${IS_OK}" != "True" ]]; then
      echo "❌ Error: Failed to verify packages insertion in configuration.yaml. Rolling back..."
      cp -p "${BACKUP_CONFIG}" "${CONFIG_FILE}"
      exit 1
    fi
    echo "  ✔ Added 'packages: !include_dir_named packages' to configuration.yaml"
  fi
fi

# ------------------------------------------------------------------------------
# 4. Lovelace Dashboard Resource Registration (I2, R7, R8)
# ------------------------------------------------------------------------------
echo "▶ Registering dashboard resource in Lovelace..."

if [[ "${LOVELACE_YAML_MODE}" == "True" ]]; then
  echo "  ℹ Lovelace is configured in YAML mode. Add dashboard resources to configuration.yaml instead."
elif [[ "${DRY_RUN}" = true ]]; then
  echo "▶ [DRY-RUN] Would register /local/hpwh-card.js?v=${CARD_VERSION} in ${STORAGE_DIR}/lovelace_resources"
else
  mkdir -p "${STORAGE_DIR}"
  STORAGE_DIR="${STORAGE_DIR}" CARD_VERSION="${CARD_VERSION}" python3 - << 'EOF'
import os, sys, json, uuid

storage_dir = os.environ["STORAGE_DIR"]
card_ver = os.environ["CARD_VERSION"]
storage_file = os.path.join(storage_dir, "lovelace_resources")
card_url = f"/local/hpwh-card.js?v={card_ver}"

data = {"version": 1, "minor_version": 1, "key": "lovelace_resources", "data": {"items": []}}

if os.path.isfile(storage_file):
    with open(storage_file, "r", encoding="utf-8") as f:
        data = json.load(f)

items = data.setdefault("data", {}).setdefault("items", [])
target_base = "/local/hpwh-card.js"
found = False
modified = False

for item in items:
    if isinstance(item, dict):
        base_url = item.get("url", "").split("?")[0]
        if base_url == target_base:
            found = True
            if item.get("url") != card_url or item.get("res_type") != "module":
                item["url"] = card_url
                item["res_type"] = "module"
                modified = True
            break

if not found:
    items.append({
        "id": uuid.uuid4().hex,
        "url": card_url,
        "res_type": "module"
    })
    modified = True

if modified:
    tmp_file = f"{storage_file}.tmp"
    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp_file, storage_file)
    print(f"  ✔ Registered Lovelace resource: {card_url}")
else:
  print(f"  ✔ Lovelace resource is already up to date: {card_url}")
EOF
fi

# ------------------------------------------------------------------------------
# 5. Global Validation with Home Assistant CLI (R6)
# ------------------------------------------------------------------------------
if command -v ha >/dev/null 2>&1 && [[ "${DRY_RUN}" != true ]]; then
  echo "▶ Validating configuration with Home Assistant Core..."
  if ! ha core check >/dev/null 2>&1; then
    echo "❌ Error: Home Assistant config check failed. Rolling back changes..."
    if [[ -f "${CONFIG_FILE}.hpwh.bak" ]]; then
      cp -p "${CONFIG_FILE}.hpwh.bak" "${CONFIG_FILE}"
    fi
    exit 1
  fi
  echo "  ✔ Configuration validation passed."
fi

# ------------------------------------------------------------------------------
# Final Status & Next Steps (R5, R7)
# ------------------------------------------------------------------------------
echo ""
if [[ "${MANUAL_CONFIG_REQUIRED}" == true ]]; then
  echo "=========================================================="
  echo "  ⚠ INCOMPLETE: Manual Configuration Step Required"
  echo "=========================================================="
  echo "Component files were placed, but your configuration.yaml uses"
  echo "split includes or custom indentation and was not modified automatically."
  echo ""
  echo "Please complete setup by adding the following line inside your"
  echo "'homeassistant:' block in ${CONFIG_FILE}:"
  echo ""
  echo "  packages: !include_dir_named ${PKG_DIR_NAME}"
  echo ""
  echo "Then perform a FULL Home Assistant restart."
  echo "=========================================================="
  exit 2
fi

echo "=========================================================="
echo "  🎉 HPWH Installation & Setup Complete!"
echo "=========================================================="
echo "IMPORTANT:"
echo "Home Assistant loads packages and dashboard resources at startup."
echo "You MUST RESTART Home Assistant before making dashboard changes in the UI."
echo ""
echo "Next steps in Home Assistant:"
echo "1. Restart Home Assistant: Developer Tools > Restart (or Settings > System > Restart)"
echo "2. Import the Automation Blueprint:"
echo "   https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fraw.githubusercontent.com%2Fccma14%2Fhomeassistant-toolbox%2Fmain%2Fhpwh%2Fblueprint.yaml"
echo "3. Add the card to your dashboard: Edit Dashboard -> + Add Card -> Heat Pump Water Heater Card"
echo "   (If the card is not listed yet, verify resources at: https://my.home-assistant.io/redirect/lovelace_resources/)"
echo "=========================================================="
exit 0
