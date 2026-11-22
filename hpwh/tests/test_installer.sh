#!/usr/bin/env bash
# ==============================================================================
# Test Suite for hpwh/install.sh
# Tests fresh install, idempotency, configuration.yaml handling, and Lovelace registration.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="${REPO_ROOT}/hpwh/install.sh"

echo "▶ Testing hpwh/install.sh..."

TEST_DIR="$(mktemp -d /tmp/hpwh_installer_test_XXXXXX)"
trap 'rm -rf "${TEST_DIR}"' EXIT

# ------------------------------------------------------------------------------
# Test 1: Fresh Installation on Bare configuration.yaml
# ------------------------------------------------------------------------------
echo -n "  • Scenario 1: Fresh install into bare configuration... "
cat << 'EOF' > "${TEST_DIR}/configuration.yaml"
# Loads default set of integrations. Do not remove.
default_config:

automation: !include automations.yaml
script: !include scripts.yaml
EOF

bash "${INSTALLER}" -c "${TEST_DIR}" >/dev/null

if [[ ! -f "${TEST_DIR}/packages/hpwh.yaml" ]]; then
  echo "FAIL: packages/hpwh.yaml was not created"
  exit 1
fi

if [[ ! -f "${TEST_DIR}/www/hpwh-card.js" ]]; then
  echo "FAIL: www/hpwh-card.js was not created"
  exit 1
fi

if ! grep -q "packages: !include_dir_named packages" "${TEST_DIR}/configuration.yaml"; then
  echo "FAIL: packages include missing from configuration.yaml"
  exit 1
fi

if [[ ! -f "${TEST_DIR}/.storage/lovelace_resources" ]]; then
  echo "FAIL: .storage/lovelace_resources was not created"
  exit 1
fi

# Verify JSON validity and content of .storage/lovelace_resources
python3 -c "
import json
with open('${TEST_DIR}/.storage/lovelace_resources') as f:
    data = json.load(f)
items = data['data']['items']
assert len(items) == 1, f'Expected 1 resource, got {len(items)}'
assert '/local/hpwh-card.js' in items[0]['url'], 'Resource URL does not contain /local/hpwh-card.js'
assert items[0]['res_type'] == 'module', 'res_type should be module'
"
echo "PASS"

# ------------------------------------------------------------------------------
# Test 2: Idempotency (Re-running updates cleanly without duplication)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 2: Idempotency check (re-running update)... "
bash "${INSTALLER}" -c "${TEST_DIR}" >/dev/null

# Verify packages: appears only once
PKG_COUNT=$(grep -c "packages: !include_dir_named packages" "${TEST_DIR}/configuration.yaml")
if [[ "${PKG_COUNT}" -ne 1 ]]; then
  echo "FAIL: packages line duplicated in configuration.yaml (found ${PKG_COUNT} occurrences)"
  exit 1
fi

# Verify lovelace resources has only 1 entry
python3 -c "
import json
with open('${TEST_DIR}/.storage/lovelace_resources') as f:
    data = json.load(f)
items = data['data']['items']
hpwh_items = [i for i in items if '/hpwh-card.js' in i.get('url', '')]
assert len(hpwh_items) == 1, f'Expected exactly 1 hpwh-card entry, found {len(hpwh_items)}'
"
echo "PASS"

# ------------------------------------------------------------------------------
# Test 3: Existing homeassistant: block in configuration.yaml
# ------------------------------------------------------------------------------
echo -n "  • Scenario 3: Pre-existing homeassistant: block... "
SCENARIO3_DIR="$(mktemp -d /tmp/hpwh_installer_scenario3_XXXXXX)"
trap 'rm -rf "${TEST_DIR}" "${SCENARIO3_DIR}"' EXIT

cat << 'EOF' > "${SCENARIO3_DIR}/configuration.yaml"
default_config:

homeassistant:
  name: Mountain Cabin
  unit_system: us_customary
  time_zone: America/Denver

automation: !include automations.yaml
EOF

bash "${INSTALLER}" -c "${SCENARIO3_DIR}" >/dev/null

if ! grep -q "packages: !include_dir_named packages" "${SCENARIO3_DIR}/configuration.yaml"; then
  echo "FAIL: packages include missing from pre-existing homeassistant block"
  exit 1
fi

if ! grep -q "name: Mountain Cabin" "${SCENARIO3_DIR}/configuration.yaml"; then
  echo "FAIL: existing configuration inside homeassistant block was deleted"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 4: Preserving other existing Lovelace resources
# ------------------------------------------------------------------------------
echo -n "  • Scenario 4: Preserving existing dashboard resources... "
SCENARIO4_DIR="$(mktemp -d /tmp/hpwh_installer_scenario4_XXXXXX)"
mkdir -p "${SCENARIO4_DIR}/.storage"
trap 'rm -rf "${TEST_DIR}" "${SCENARIO3_DIR}" "${SCENARIO4_DIR}"' EXIT

cat << 'EOF' > "${SCENARIO4_DIR}/configuration.yaml"
default_config:
EOF

cat << 'EOF' > "${SCENARIO4_DIR}/.storage/lovelace_resources"
{
  "version": 1,
  "minor_version": 1,
  "key": "lovelace_resources",
  "data": {
    "items": [
      {
        "id": "1111222233334444",
        "url": "/local/other-card.js",
        "res_type": "module"
      }
    ]
  }
}
EOF

bash "${INSTALLER}" -c "${SCENARIO4_DIR}" >/dev/null

python3 -c "
import json
with open('${SCENARIO4_DIR}/.storage/lovelace_resources') as f:
    data = json.load(f)
items = data['data']['items']
assert len(items) == 2, f'Expected 2 resources, found {len(items)}'
other = [i for i in items if i['url'] == '/local/other-card.js']
hpwh = [i for i in items if '/hpwh-card.js' in i['url']]
assert len(other) == 1, 'Pre-existing card was lost'
assert len(hpwh) == 1, 'hpwh-card was not added'
"
echo "PASS"

echo "All hpwh/install.sh tests passed successfully!\n"
