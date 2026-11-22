#!/usr/bin/env bash
# ==============================================================================
# Test Suite for hpwh/install.sh
# Tests fresh install, strict idempotency, configuration.yaml handling,
# download failures, Lovelace resource preservation, and error recovery.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="${REPO_ROOT}/hpwh/install.sh"

echo "▶ Testing hpwh/install.sh..."

TEST_WORKSPACE="$(mktemp -d /tmp/hpwh_installer_tests_XXXXXX)"
trap 'rm -rf "${TEST_WORKSPACE}"' EXIT

PYTHON_CMD="python3"
if python3 -c "import yaml" >/dev/null 2>&1; then
  PYTHON_CMD="python3"
elif command -v pyenv >/dev/null 2>&1 && PYENV_VERSION=3.12.9 python3 -c "import yaml" >/dev/null 2>&1; then
  PYTHON_CMD="PYENV_VERSION=3.12.9 python3"
fi

# Helper for testing PyYAML parsing with custom HA tags
verify_yaml_py() {
  local yaml_file="$1"
  local python_code="$2"
  YAML_FILE="${yaml_file}" PYTHON_CODE="${python_code}" eval "${PYTHON_CMD}" - << 'EOF'
import os, sys

yaml_file = os.environ["YAML_FILE"]
code = os.environ["PYTHON_CODE"]

try:
    import yaml

    def ignore_unknown_tag(loader, suffix, node):
        if isinstance(node, yaml.ScalarNode):
            return loader.construct_scalar(node)
        elif isinstance(node, yaml.SequenceNode):
            return loader.construct_sequence(node)
        elif isinstance(node, yaml.MappingNode):
            return loader.construct_mapping(node)
        return None

    yaml.SafeLoader.add_multi_constructor('!', ignore_unknown_tag)

    with open(yaml_file, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    local_vars = {"cfg": cfg}
    exec(code, {}, local_vars)
except ImportError:
    with open(yaml_file, "r", encoding="utf-8") as f:
        content = f.read()
    assert "packages" in content, "packages not in content"
EOF
}

# ------------------------------------------------------------------------------
# Test 1: Fresh Installation on Bare configuration.yaml
# ------------------------------------------------------------------------------
echo -n "  • Scenario 1: Fresh install into bare configuration... "
T1_DIR="${TEST_WORKSPACE}/t1"
mkdir -p "${T1_DIR}"
cat << 'EOF' > "${T1_DIR}/configuration.yaml"
# Loads default set of integrations. Do not remove.
default_config:

automation: !include automations.yaml
script: !include scripts.yaml
EOF

bash "${INSTALLER}" --local -c "${T1_DIR}" >/dev/null

if [[ ! -f "${T1_DIR}/packages/hpwh.yaml" ]]; then
  echo "FAIL: packages/hpwh.yaml was not created"
  exit 1
fi

if [[ ! -f "${T1_DIR}/www/hpwh-card.js" ]]; then
  echo "FAIL: www/hpwh-card.js was not created"
  exit 1
fi

if [[ ! -f "${T1_DIR}/.storage/lovelace_resources" ]]; then
  echo "FAIL: .storage/lovelace_resources was not created"
  exit 1
fi

# Verify configuration.yaml structure using Python PyYAML
verify_yaml_py "${T1_DIR}/configuration.yaml" "
assert 'homeassistant' in cfg, 'homeassistant key missing'
assert 'packages' in cfg['homeassistant'], 'packages key missing'
assert cfg['homeassistant']['packages'] == 'packages', f'Unexpected packages include: {cfg[\"homeassistant\"][\"packages\"]}'
"

# Verify JSON validity and content of .storage/lovelace_resources
python3 -c "
import json
with open('${T1_DIR}/.storage/lovelace_resources') as f:
    data = json.load(f)
items = data['data']['items']
assert len(items) == 1, f'Expected 1 resource, got {len(items)}'
assert items[0]['url'].split('?')[0] == '/local/hpwh-card.js', 'Resource URL base does not match'
assert items[0]['res_type'] == 'module', 'res_type should be module'
"
echo "PASS"

# ------------------------------------------------------------------------------
# Test 2: Strict Byte-for-Byte Idempotency (B8)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 2: Strict byte-for-byte idempotency on re-run... "
CFG_BEFORE="${TEST_WORKSPACE}/t1_cfg_before.yaml"
RES_BEFORE="${TEST_WORKSPACE}/t1_res_before.json"
cp "${T1_DIR}/configuration.yaml" "${CFG_BEFORE}"
cp "${T1_DIR}/.storage/lovelace_resources" "${RES_BEFORE}"

bash "${INSTALLER}" --local -c "${T1_DIR}" >/dev/null

if ! cmp -s "${T1_DIR}/configuration.yaml" "${CFG_BEFORE}"; then
  echo "FAIL: configuration.yaml changed on re-run (not idempotent)"
  exit 1
fi

if ! cmp -s "${T1_DIR}/.storage/lovelace_resources" "${RES_BEFORE}"; then
  echo "FAIL: .storage/lovelace_resources changed on re-run (not idempotent)"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 3: Existing homeassistant: block with 2-space indentation (B4)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 3: Pre-existing homeassistant: block structure... "
T3_DIR="${TEST_WORKSPACE}/t3"
mkdir -p "${T3_DIR}"
cat << 'EOF' > "${T3_DIR}/configuration.yaml"
default_config:

homeassistant:
  name: Mountain Cabin
  unit_system: us_customary
  time_zone: America/Denver

automation: !include automations.yaml
EOF

bash "${INSTALLER}" --local -c "${T3_DIR}" >/dev/null

verify_yaml_py "${T3_DIR}/configuration.yaml" "
ha = cfg.get('homeassistant', {})
assert ha.get('name') == 'Mountain Cabin', 'Original name key lost or modified'
assert ha.get('unit_system') == 'us_customary', 'Original unit_system lost'
assert 'packages' in ha, 'packages key not inserted into homeassistant block'
"
echo "PASS"

# ------------------------------------------------------------------------------
# Test 4: Preserving existing dashboard resources in .storage
# ------------------------------------------------------------------------------
echo -n "  • Scenario 4: Preserving other existing dashboard resources... "
T4_DIR="${TEST_WORKSPACE}/t4"
mkdir -p "${T4_DIR}/.storage"
cat << 'EOF' > "${T4_DIR}/configuration.yaml"
default_config:
EOF

cat << 'EOF' > "${T4_DIR}/.storage/lovelace_resources"
{
  "version": 1,
  "minor_version": 1,
  "key": "lovelace_resources",
  "data": {
    "items": [
      {
        "id": "existing-custom-card-uuid",
        "url": "/local/other-card.js",
        "res_type": "module"
      }
    ]
  }
}
EOF

bash "${INSTALLER}" --local -c "${T4_DIR}" >/dev/null

python3 -c "
import json
with open('${T4_DIR}/.storage/lovelace_resources') as f:
    data = json.load(f)
items = data['data']['items']
assert len(items) == 2, f'Expected 2 resources, found {len(items)}'
other = [i for i in items if i.get('url') == '/local/other-card.js']
hpwh = [i for i in items if i.get('url', '').split('?')[0] == '/local/hpwh-card.js']
assert len(other) == 1, 'Existing card was lost'
assert len(hpwh) == 1, 'hpwh-card was not added'
"
echo "PASS"

# ------------------------------------------------------------------------------
# Test 5: Download Failure Handling (B1, I1)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 5: Download error handling leaves targets untouched... "
T5_DIR="${TEST_WORKSPACE}/t5"
mkdir -p "${T5_DIR}/packages" "${T5_DIR}/www"
cat << 'EOF' > "${T5_DIR}/configuration.yaml"
default_config:
EOF
echo "original-package-content" > "${T5_DIR}/packages/hpwh.yaml"
echo "original-card-content" > "${T5_DIR}/www/hpwh-card.js"

# Create a mock failing curl in a custom bin dir
MOCK_BIN="${TEST_WORKSPACE}/mock_bin"
mkdir -p "${MOCK_BIN}"
cat << 'EOF' > "${MOCK_BIN}/curl"
#!/bin/sh
# Return HTTP 404 error and exit with curl error code 22
echo "404: Not Found" >&2
exit 22
EOF
chmod +x "${MOCK_BIN}/curl"

# Run installer in a subshell without --local, using failing curl
set +e
ERR_OUTPUT=$(PATH="${MOCK_BIN}:/usr/bin:/bin" bash "${INSTALLER}" -c "${T5_DIR}" 2>&1)
EXIT_CODE=$?
set -e

if [[ ${EXIT_CODE} -eq 0 ]]; then
  echo "FAIL: Installer succeeded despite download failure"
  exit 1
fi

if [[ "$(< "${T5_DIR}/packages/hpwh.yaml")" != "original-package-content" ]]; then
  echo "FAIL: packages/hpwh.yaml was corrupted by failed download"
  exit 1
fi

if [[ "$(< "${T5_DIR}/www/hpwh-card.js")" != "original-card-content" ]]; then
  echo "FAIL: www/hpwh-card.js was corrupted by failed download"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 6: Corrupt .storage/lovelace_resources Aborts Without Loss (B2, I2)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 6: Corrupt lovelace_resources aborts safely... "
T6_DIR="${TEST_WORKSPACE}/t6"
mkdir -p "${T6_DIR}/.storage"
cat << 'EOF' > "${T6_DIR}/configuration.yaml"
default_config:
EOF
CORRUPT_CONTENT='{"version": 1, "data": {items: [UNPARSEABLE'
echo "${CORRUPT_CONTENT}" > "${T6_DIR}/.storage/lovelace_resources"

set +e
ERR_OUTPUT=$(bash "${INSTALLER}" --local -c "${T6_DIR}" 2>&1)
EXIT_CODE=$?
set -e

if [[ ${EXIT_CODE} -eq 0 ]]; then
  echo "FAIL: Installer did not abort on corrupt lovelace_resources"
  exit 1
fi

if [[ "$(< "${T6_DIR}/.storage/lovelace_resources")" != "${CORRUPT_CONTENT}" ]]; then
  echo "FAIL: Corrupt lovelace_resources was overwritten or modified"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 7: Awkward configuration.yaml shapes (B3, I3, I4)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 7: Complex / split configuration shapes... "
T7_DIR="${TEST_WORKSPACE}/t7"
mkdir -p "${T7_DIR}"

# 7a: Split config: homeassistant: !include homeassistant.yaml
cat << 'EOF' > "${T7_DIR}/configuration.yaml"
default_config:

homeassistant: !include homeassistant.yaml
EOF

bash "${INSTALLER}" --local -c "${T7_DIR}" >/dev/null

# Verify configuration was not corrupted and remains valid
verify_yaml_py "${T7_DIR}/configuration.yaml" "
assert cfg.get('homeassistant') == 'homeassistant.yaml', 'Split include was corrupted'
"

# 7b: Custom indentation (4 spaces)
cat << 'EOF' > "${T7_DIR}/configuration.yaml"
default_config:

homeassistant:
    name: Four Space Cabin
    time_zone: UTC
EOF

bash "${INSTALLER}" --local -c "${T7_DIR}" >/dev/null

# Verify indentation wasn't broken by an awkward 2-space injection
verify_yaml_py "${T7_DIR}/configuration.yaml" "
assert cfg['homeassistant']['name'] == 'Four Space Cabin'
"

# 7c: Comment containing # packages:
cat << 'EOF' > "${T7_DIR}/configuration.yaml"
default_config:

# packages: this is a comment about packages
homeassistant:
  name: Cabin With Comment
EOF

bash "${INSTALLER}" --local -c "${T7_DIR}" >/dev/null

verify_yaml_py "${T7_DIR}/configuration.yaml" "
assert 'packages' in cfg['homeassistant'], 'packages was not enabled due to false comment match'
"

# 7d: Pre-existing packages include pointing to integrations/
cat << 'EOF' > "${T7_DIR}/configuration.yaml"
default_config:

homeassistant:
  name: Integrations Cabin
  packages: !include_dir_named integrations
EOF

bash "${INSTALLER}" --local -c "${T7_DIR}" >/dev/null

# Verify packages was not duplicated
PKG_OCCURRENCES=$(grep -c "packages:" "${T7_DIR}/configuration.yaml")
if [[ "${PKG_OCCURRENCES}" -ne 1 ]]; then
  echo "FAIL: packages: was duplicated in configuration.yaml"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 8: User Customizations Preserved via Backup (B5, I5)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 8: User-customized hpwh.yaml triggers backup... "
T8_DIR="${TEST_WORKSPACE}/t8"
mkdir -p "${T8_DIR}/packages"
cat << 'EOF' > "${T8_DIR}/configuration.yaml"
default_config:
EOF

# Pre-populate with customized package
cat << 'EOF' > "${T8_DIR}/packages/hpwh.yaml"
template:
  - sensor:
      - name: "Water Heater State of Charge"
        unique_id: water_heater_state_of_charge
        # User customized tank_cfg:
        tank_cfg: 80.0
EOF

bash "${INSTALLER}" --local -c "${T8_DIR}" >/dev/null

# Verify a backup was created
BAK_COUNT=$(find "${T8_DIR}/packages" -name "hpwh.yaml.bak-*" | wc -l | tr -d ' ')
if [[ "${BAK_COUNT}" -lt 1 ]]; then
  echo "FAIL: Backup hpwh.yaml.bak-<timestamp> was not created for modified file"
  exit 1
fi

# Verify the backup has the user's custom tank_cfg
BAK_FILE=$(find "${T8_DIR}/packages" -name "hpwh.yaml.bak-*" | head -1)
if ! grep -q "tank_cfg: 80.0" "${BAK_FILE}"; then
  echo "FAIL: Backup file did not contain original user modifications"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 9: Piped Run from Awkward CWD (B6, I6)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 9: Piped run from packages subdirectory... "
T9_DIR="${TEST_WORKSPACE}/t9"
mkdir -p "${T9_DIR}/packages"
cat << 'EOF' > "${T9_DIR}/configuration.yaml"
default_config:
EOF

# Pre-place hpwh.yaml in the directory to trigger the old self-copy bug
cp "${REPO_ROOT}/hpwh/hpwh.yaml" "${T9_DIR}/packages/hpwh.yaml"

(
  cd "${T9_DIR}/packages"
  cat "${INSTALLER}" | bash -s -- --local "${REPO_ROOT}/hpwh" -c "${T9_DIR}" >/dev/null
)

if [[ ! -f "${T9_DIR}/packages/hpwh.yaml" || ! -f "${T9_DIR}/www/hpwh-card.js" ]]; then
  echo "FAIL: Files missing after piped install from packages directory"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 10: Duplicate unique_id Detection (B7, I8)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 10: Duplicate unique_id detection warning... "
T10_DIR="${TEST_WORKSPACE}/t10"
mkdir -p "${T10_DIR}"
cat << 'EOF' > "${T10_DIR}/configuration.yaml"
default_config:
EOF
cat << 'EOF' > "${T10_DIR}/templates.yaml"
- sensor:
    - name: Legacy Water Heater State of Charge
      unique_id: water_heater_state_of_charge
      state: "100"
EOF

OUTPUT=$(bash "${INSTALLER}" --local -c "${T10_DIR}")

if ! echo "${OUTPUT}" | grep -q "Warning: Found existing 'unique_id: water_heater_state_of_charge'"; then
  echo "FAIL: Did not warn about duplicate unique_id in templates.yaml"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 11: Uninstall and Dry-Run (I14)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 11: Dry-run and uninstall workflows... "
T11_DIR="${TEST_WORKSPACE}/t11"
mkdir -p "${T11_DIR}"
cat << 'EOF' > "${T11_DIR}/configuration.yaml"
default_config:
EOF

# Dry-run should not create files
bash "${INSTALLER}" --dry-run --local -c "${T11_DIR}" >/dev/null
if [[ -d "${T11_DIR}/packages" || -d "${T11_DIR}/www" ]]; then
  echo "FAIL: Dry-run created directories or files"
  exit 1
fi

# Real install followed by uninstall
bash "${INSTALLER}" --local -c "${T11_DIR}" >/dev/null
if [[ ! -f "${T11_DIR}/packages/hpwh.yaml" || ! -f "${T11_DIR}/www/hpwh-card.js" ]]; then
  echo "FAIL: Install failed prior to uninstall test"
  exit 1
fi

bash "${INSTALLER}" --uninstall -c "${T11_DIR}" >/dev/null
if [[ -f "${T11_DIR}/packages/hpwh.yaml" || -f "${T11_DIR}/www/hpwh-card.js" ]]; then
  echo "FAIL: Uninstall did not remove package or card files"
  exit 1
fi

python3 -c "
import json
with open('${T11_DIR}/.storage/lovelace_resources') as f:
    data = json.load(f)
items = data.get('data', {}).get('items', [])
hpwh = [i for i in items if '/hpwh-card.js' in i.get('url', '')]
assert len(hpwh) == 0, 'Dashboard resource was not removed on uninstall'
"
echo "PASS"

echo "All hpwh/install.sh tests passed successfully!"
