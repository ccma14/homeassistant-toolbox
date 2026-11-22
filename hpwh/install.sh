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
#   --local              Use local repository files instead of downloading
#   --dry-run            Display planned actions without making any changes
#   -y, --yes            Skip confirmation prompts
#   --uninstall          Remove installed package, card, and Lovelace registration
#   -h, --help           Show help
# ==============================================================================

set -euo pipefail

GITHUB_RAW="https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh"
CONFIG_DIR="${HA_CONFIG_DIR:-}"
SCRIPT_DIR=""
LOCAL_MODE=false
DRY_RUN=false
UNINSTALL=false
CONFIRM_YES=false

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
  --local              Use local files from repository checkout
  --dry-run            Show what would be done without modifying any files
  -y, --yes            Non-interactive mode
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

if ! command -v awk >/dev/null 2>&1; then
  echo "❌ Error: awk is required by this installer but was not found."
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

PACKAGES_DIR="${CONFIG_DIR}/packages"
WWW_DIR="${CONFIG_DIR}/www"
STORAGE_DIR="${CONFIG_DIR}/.storage"

# ------------------------------------------------------------------------------
# Uninstall Routine
# ------------------------------------------------------------------------------
if [[ "${UNINSTALL}" = true ]]; then
  echo "=========================================================="
  echo "  Uninstalling Heat Pump Water Heater (HPWH) Component"
  echo "  Target: ${CONFIG_DIR}"
  echo "=========================================================="

  if [[ "${DRY_RUN}" = true ]]; then
    echo "▶ [DRY-RUN] Would remove ${PACKAGES_DIR}/hpwh.yaml"
    echo "▶ [DRY-RUN] Would remove ${WWW_DIR}/hpwh-card.js"
    echo "▶ [DRY-RUN] Would unregister dashboard resource in ${STORAGE_DIR}/lovelace_resources"
    exit 0
  fi

  rm -f "${PACKAGES_DIR}/hpwh.yaml"
  rm -f "${WWW_DIR}/hpwh-card.js"
  echo "  ✔ Removed package and card files."

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

echo "=========================================================="
echo "  Installing Heat Pump Water Heater (HPWH) Component"
echo "  Target: ${CONFIG_DIR}"
if [[ "${DRY_RUN}" = true ]]; then
  echo "  Mode: DRY-RUN (no changes will be written)"
fi
echo "=========================================================="

# ------------------------------------------------------------------------------
# Check for Duplicate unique_id in Existing Configurations (I8)
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
# Safe File Fetching / Atomic Update (I1, I5, I6, I15)
# ------------------------------------------------------------------------------
fetch_and_install() {
  local rel_path="$1"
  local target_file="$2"
  local file_type="$3" # "yaml" or "js"

  if [[ "${DRY_RUN}" = true ]]; then
    echo "▶ [DRY-RUN] Would install ${rel_path} to ${target_file}"
    return 0
  fi

  local target_dir
  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}"

  local staging_file
  staging_file="$(mktemp "${target_dir}/.hpwh_staging_XXXXXX")"

  if [[ "${LOCAL_MODE}" = true && -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/${rel_path}" ]]; then
    local src_file="${SCRIPT_DIR}/${rel_path}"
    if [[ "$(cd "$(dirname "${src_file}")" && pwd)/$(basename "${src_file}")" == "$(cd "$(dirname "${target_file}")" 2>/dev/null && pwd)/$(basename "${target_file}")" ]]; then
      echo "  ✔ Source and target are identical file (${target_file}). Skipping copy."
      rm -f "${staging_file}"
      return 0
    fi
    cp "${src_file}" "${staging_file}"
  else
    local download_url="${GITHUB_RAW}/${rel_path}"
    if command -v curl >/dev/null 2>&1; then
      if ! curl -fsSL "${download_url}" -o "${staging_file}"; then
        rm -f "${staging_file}"
        echo "❌ Error: Failed to download ${download_url} (HTTP error or connection failure)."
        exit 1
      fi
    elif command -v wget >/dev/null 2>&1; then
      if ! wget -qO "${staging_file}" "${download_url}"; then
        rm -f "${staging_file}"
        echo "❌ Error: Failed to download ${download_url} with wget."
        exit 1
      fi
    fi
  fi

  # Validate downloaded / staged content before touching target (I1)
  if [[ ! -s "${staging_file}" ]]; then
    rm -f "${staging_file}"
    echo "❌ Error: Received empty file for ${rel_path}."
    exit 1
  fi

  if [[ "${file_type}" == "yaml" ]]; then
    if ! grep -q "water_heater_state_of_charge" "${staging_file}" && ! grep -q "template:" "${staging_file}"; then
      rm -f "${staging_file}"
      echo "❌ Error: Validation failed for ${rel_path}. Invalid YAML structure or unexpected content."
      exit 1
    fi
  elif [[ "${file_type}" == "js" ]]; then
    if ! grep -q "hpwh-card" "${staging_file}" && ! grep -q "HpwhCard" "${staging_file}"; then
      rm -f "${staging_file}"
      echo "❌ Error: Validation failed for ${rel_path}. Invalid JavaScript content."
      exit 1
    fi
  fi


  # Preserve user customizations if existing file has modifications (I5)
  if [[ -f "${target_file}" ]]; then
    if cmp -s "${target_file}" "${staging_file}"; then
      echo "  ✔ $(basename "${target_file}") is already up to date."
      rm -f "${staging_file}"
      return 0
    else
      local ts
      ts="$(date +%Y%m%d%H%M%S)"
      local backup_file="${target_file}.bak-${ts}"
      cp -p "${target_file}" "${backup_file}"
      echo "  ⚠ Note: Existing $(basename "${target_file}") was modified. Saved backup to ${backup_file}"
    fi
  fi

  # Atomic replacement
  mv -f "${staging_file}" "${target_file}"
  echo "  ✔ Placed at ${target_file}"
}

# ------------------------------------------------------------------------------
# 1. Install Sensor Package (hpwh.yaml)
# ------------------------------------------------------------------------------
echo "▶ Installing sensor package (hpwh.yaml)..."
fetch_and_install "hpwh.yaml" "${PACKAGES_DIR}/hpwh.yaml" "yaml"

# ------------------------------------------------------------------------------
# 2. Install Dashboard Card (hpwh-card.js)
# ------------------------------------------------------------------------------
echo "▶ Installing dashboard card (hpwh-card.js)..."
TARGET_CARD="${WWW_DIR}/hpwh-card.js"
fetch_and_install "hpwh-card.js" "${TARGET_CARD}" "js"

CARD_VERSION="1.2.0"
if [[ -f "${TARGET_CARD}" ]]; then
  EXTRACTED_VER=$(grep -oE "const CARD_VERSION = [\"'][^\"']+[\"']" "${TARGET_CARD}" | head -1 | cut -d'"' -f2 | cut -d"'" -f2 || true)
  if [[ -n "${EXTRACTED_VER}" ]]; then
    CARD_VERSION="${EXTRACTED_VER}"
  fi
fi

# ------------------------------------------------------------------------------
# 3. Safe configuration.yaml Inspection & Packages Support (I3, I4, I15)
# ------------------------------------------------------------------------------
echo "▶ Checking configuration.yaml for package support..."

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
in_ha_block = False

for idx, line in enumerate(lines):
    # Match top-level homeassistant: block
    if re.match(r"^homeassistant:\s*(?:#.*)?$", line):
        has_ha_block = True
        ha_line_idx = idx
        ha_is_simple = True
        in_ha_block = True
        continue
    elif re.match(r"^homeassistant:\s*.+", line):
        # homeassistant with inline mapping or !include
        has_ha_block = True
        ha_line_idx = idx
        ha_is_simple = False
        in_ha_block = False
        continue

    # If we hit another unindented top-level key, leave homeassistant block
    if in_ha_block and re.match(r"^[a-zA-Z0-9_-]+:", line):
        in_ha_block = False

    if in_ha_block:
        # Check child indentation
        m_child = re.match(r"^(\s+)[a-zA-Z0-9_-]+:", line)
        if m_child:
            indent_len = len(m_child.group(1))
            if ha_indent is None:
                ha_indent = indent_len

        # Check for packages under homeassistant
        m_pkg = re.match(r"^\s+packages:\s*(.*)$", line)
        if m_pkg:
            packages_configured = True
            rest = m_pkg.group(1).strip()
            m_dir = re.search(r"!include_dir_(?:merge_)?named\s+([a-zA-Z0-9_/-]+)", rest)
            if m_dir:
                packages_dir = m_dir.group(1)

result = {
    "has_ha_block": has_ha_block,
    "ha_line_idx": ha_line_idx,
    "ha_is_simple": ha_is_simple,
    "ha_indent": ha_indent,
    "packages_configured": packages_configured,
    "packages_dir": packages_dir
}
print(json.dumps(result))
EOF
)

PKG_CONFIGURED=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["packages_configured"])')
HAS_HA=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["has_ha_block"])')
HA_SIMPLE=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["ha_is_simple"])')
HA_INDENT=$(echo "${CONFIG_STATUS}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["ha_indent"])')

if [[ "${PKG_CONFIGURED}" == "True" ]]; then
  echo "  ✔ Packages already configured in configuration.yaml"
else
  if [[ "${DRY_RUN}" = true ]]; then
    echo "▶ [DRY-RUN] Would configure packages in configuration.yaml"
  else
    BACKUP_CONFIG="${CONFIG_FILE}.hpwh.bak"
    cp -p "${CONFIG_FILE}" "${BACKUP_CONFIG}"
    echo "  ℹ Backed up original configuration to ${BACKUP_CONFIG}"

    TMP_CONFIG="$(mktemp "${CONFIG_DIR}/.hpwh_cfg_XXXXXX")"

    if [[ "${HAS_HA}" == "False" ]]; then
      # Append standard homeassistant block with 2-space indentation
      cp "${CONFIG_FILE}" "${TMP_CONFIG}"
      cat << 'EOF' >> "${TMP_CONFIG}"

# Home Assistant Packages (enabled by HPWH installer)
homeassistant:
  packages: !include_dir_named packages
EOF
      mv -f "${TMP_CONFIG}" "${CONFIG_FILE}"
      echo "  ✔ Appended homeassistant block with 'packages: !include_dir_named packages'"
    elif [[ "${HA_SIMPLE}" == "True" && ( "${HA_INDENT}" == "None" || "${HA_INDENT}" == "2" ) ]]; then
      # Insert packages right below homeassistant: line
      awk '/^homeassistant:\s*(#.*)?$/ { print; print "  packages: !include_dir_named packages"; next }1' "${BACKUP_CONFIG}" > "${TMP_CONFIG}"
      mv -f "${TMP_CONFIG}" "${CONFIG_FILE}"
      echo "  ✔ Added 'packages: !include_dir_named packages' to homeassistant block"
    else
      # Complex or split configuration (I3, I4) - do not corrupt
      rm -f "${TMP_CONFIG}"
      echo "  ⚠ Note: 'homeassistant:' block uses custom indentation, inline formatting, or split includes."
      echo "    To complete package setup, please manually add the following line inside your 'homeassistant:' block:"
      echo "      packages: !include_dir_named packages"
    fi

    # Post-edit check if Home Assistant CLI is available (I10)
    if command -v ha >/dev/null 2>&1; then
      if ! ha core check >/dev/null 2>&1; then
        echo "❌ Error: Home Assistant config check failed after edit. Rolling back configuration.yaml..."
        cp -p "${BACKUP_CONFIG}" "${CONFIG_FILE}"
        exit 1
      fi
    fi
  fi
fi

# ------------------------------------------------------------------------------
# 4. Safe Lovelace Dashboard Resource Registration (I2, I7, I12, I13)
# ------------------------------------------------------------------------------
echo "▶ Registering dashboard resource in Lovelace..."

# Check if dashboard is in YAML mode
if grep -qE "^\s*mode:\s*yaml" "${CONFIG_FILE}" 2>/dev/null && grep -qE "^lovelace:" "${CONFIG_FILE}" 2>/dev/null; then
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
    try:
        with open(storage_file, "r", encoding="utf-8") as f:
            content = f.read()
            if not content.strip():
                raise ValueError("lovelace_resources is empty")
            data = json.loads(content)
    except Exception as e:
        # Abort immediately if file exists but is unparseable or corrupt (I2)
        print(f"❌ Error: Could not parse existing {storage_file}: {e}", file=sys.stderr)
        print("Aborting registration to prevent overwriting dashboard resources.", file=sys.stderr)
        sys.exit(1)

items = data.setdefault("data", {}).setdefault("items", [])

# Match exact URL without query parameters (I13)
target_base = "/local/hpwh-card.js"
found = False
modified = False

for item in items:
    if isinstance(item, dict):
        url = item.get("url", "")
        base_url = url.split("?")[0]
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

# Atomic write only if modified (preserves byte-for-byte idempotency)
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

echo ""
echo "=========================================================="
echo "  🎉 HPWH Installation & Setup Complete!"
echo "=========================================================="
echo "IMPORTANT:"
echo "Home Assistant caches Lovelace resources and packages at startup."
echo "You MUST RESTART Home Assistant for the packages and card to load."
echo ""
echo "Next steps in Home Assistant:"
echo "1. Restart Home Assistant: Developer Tools > Restart (or Settings > System > Restart)"
echo "2. Import the Automation Blueprint:"
echo "   https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fraw.githubusercontent.com%2Fccma14%2Fhomeassistant-toolbox%2Fmain%2Fhpwh%2Fblueprint.yaml"
echo "3. Add the card to your dashboard: Edit Dashboard -> + Add Card -> Heat Pump Water Heater Card"
echo "=========================================================="
