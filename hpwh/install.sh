#!/usr/bin/env bash
# ==============================================================================
# HPWH Component Installer for Home Assistant
# Installs hpwh.yaml package, hpwh-card.js, and registers Lovelace dashboard resource.
#
# Usage (in Home Assistant Terminal / SSH):
#   curl -sSL https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh/install.sh | bash
#
# Options:
#   -c, --config <dir>   Specify Home Assistant configuration directory
# ==============================================================================

set -euo pipefail

GITHUB_RAW="https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh"
CONFIG_DIR="${HA_CONFIG_DIR:-}"

# Parse optional arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Auto-detect configuration directory if not specified
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

if [[ ! -f "${CONFIG_DIR}/configuration.yaml" ]]; then
  echo "❌ Error: configuration.yaml not found in ${CONFIG_DIR}"
  exit 1
fi

echo "=========================================================="
echo "  Installing Heat Pump Water Heater (HPWH) Component"
echo "  Target: ${CONFIG_DIR}"
echo "=========================================================="

# Create target directories
PACKAGES_DIR="${CONFIG_DIR}/packages"
WWW_DIR="${CONFIG_DIR}/www"
STORAGE_DIR="${CONFIG_DIR}/.storage"

mkdir -p "${PACKAGES_DIR}" "${WWW_DIR}" "${STORAGE_DIR}"

# 1. Download or Copy hpwh.yaml
echo "▶ Installing sensor package (hpwh.yaml)..."
TARGET_PACKAGE="${PACKAGES_DIR}/hpwh.yaml"
# If running locally from the repo directory, use local source
LOCAL_PACKAGE="$(dirname "$0")/hpwh.yaml"
if [[ -f "${LOCAL_PACKAGE}" ]]; then
  cp "${LOCAL_PACKAGE}" "${TARGET_PACKAGE}"
elif command -v curl >/dev/null 2>&1; then
  curl -sSL "${GITHUB_RAW}/hpwh.yaml" -o "${TARGET_PACKAGE}"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${TARGET_PACKAGE}" "${GITHUB_RAW}/hpwh.yaml"
else
  echo "❌ Error: Neither curl nor wget found."
  exit 1
fi
echo "  ✔ Placed at ${TARGET_PACKAGE}"

# 2. Download or Copy hpwh-card.js
echo "▶ Installing dashboard card (hpwh-card.js)..."
TARGET_CARD="${WWW_DIR}/hpwh-card.js"
LOCAL_CARD="$(dirname "$0")/hpwh-card.js"
if [[ -f "${LOCAL_CARD}" ]]; then
  cp "${LOCAL_CARD}" "${TARGET_CARD}"
elif command -v curl >/dev/null 2>&1; then
  curl -sSL "${GITHUB_RAW}/hpwh-card.js" -o "${TARGET_CARD}"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${TARGET_CARD}" "${GITHUB_RAW}/hpwh-card.js"
fi
echo "  ✔ Placed at ${TARGET_CARD}"

# Extract card version for cache busting
CARD_VERSION="1.2.0"
if [[ -f "${TARGET_CARD}" ]]; then
  EXTRACTED_VER=$(grep -oE "const CARD_VERSION = [\"'][^\"']+[\"']" "${TARGET_CARD}" | head -1 | cut -d'"' -f2 | cut -d"'" -f2 || true)
  if [[ -n "${EXTRACTED_VER}" ]]; then
    CARD_VERSION="${EXTRACTED_VER}"
  fi
fi

# 3. Enable packages in configuration.yaml if needed
echo "▶ Checking configuration.yaml for package support..."
CONFIG_FILE="${CONFIG_DIR}/configuration.yaml"
if grep -q "packages:" "${CONFIG_FILE}" 2>/dev/null; then
  echo "  ✔ Packages already configured in configuration.yaml"
else
  echo "  • Adding packages include to configuration.yaml..."
  cp "${CONFIG_FILE}" "${CONFIG_FILE}.hpwh.bak"
  
  if grep -q "^homeassistant:" "${CONFIG_FILE}" 2>/dev/null; then
    # Insert '  packages: !include_dir_named packages' right after 'homeassistant:'
    awk '/^homeassistant:/ { print; print "  packages: !include_dir_named packages"; next }1' "${CONFIG_FILE}.hpwh.bak" > "${CONFIG_FILE}"
  else
    # Append homeassistant block with packages
    cat << 'EOF' >> "${CONFIG_FILE}"

# Home Assistant Packages (enabled by HPWH installer)
homeassistant:
  packages: !include_dir_named packages
EOF
  fi
  echo "  ✔ Added 'packages: !include_dir_named packages'"
fi

# 4. Register Lovelace Resource in .storage/lovelace_resources
echo "▶ Registering dashboard resource in Lovelace..."
python3 - << EOF
import json, os, uuid

storage_file = os.path.join("${STORAGE_DIR}", "lovelace_resources")
card_url = "/local/hpwh-card.js?v=${CARD_VERSION}"

data = {"version": 1, "minor_version": 1, "key": "lovelace_resources", "data": {"items": []}}

if os.path.exists(storage_file):
    try:
        with open(storage_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        pass

items = data.setdefault("data", {}).setdefault("items", [])

# Find existing hpwh-card entry and update version, or append new entry
found = False
for item in items:
    if isinstance(item, dict) and "/hpwh-card.js" in item.get("url", ""):
        item["url"] = card_url
        item["res_type"] = "module"
        found = True
        break

if not found:
    items.append({
        "id": uuid.uuid4().hex,
        "url": card_url,
        "res_type": "module"
    })

with open(storage_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

print("  ✔ Registered Lovelace resource: " + card_url)
EOF

echo ""
echo "=========================================================="
echo "  🎉 HPWH Installation & Update Complete!"
echo "=========================================================="
echo "Next steps in Home Assistant:"
echo "1. Reload template entities under: Settings > Developer Tools / Tools > YAML > Template Entities"
echo "2. Import the Automation Blueprint: https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fraw.githubusercontent.com%2Fccma14%2Fhomeassistant-toolbox%2Fmain%2Fhpwh%2Fblueprint.yaml"
echo "3. Add the card to your dashboard: Edit Dashboard -> + Add Card -> Heat Pump Water Heater Card"
echo "=========================================================="
