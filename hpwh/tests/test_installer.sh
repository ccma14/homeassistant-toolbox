#!/usr/bin/env bash
# ==============================================================================
# Comprehensive Test Suite for hpwh/install.sh
# Tests fresh install, strict idempotency, configuration.yaml handling,
# download failures, Lovelace resource preservation, customization protection,
# and error recovery.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="${REPO_ROOT}/hpwh/install.sh"

echo "▶ Testing hpwh/install.sh..."

PYTHON_CMD="python3"
if python3 -c "import yaml" >/dev/null 2>&1; then
  PYTHON_CMD="python3"
elif command -v pyenv >/dev/null 2>&1 && PYENV_VERSION=3.12.9 python3 -c "import yaml" >/dev/null 2>&1; then
  PYTHON_CMD="PYENV_VERSION=3.12.9 python3"
else
  echo "FAIL: PyYAML is required to run test_installer.sh. Please install pyyaml."
  exit 1
fi

TEST_WORKSPACE="$(mktemp -d /tmp/hpwh_installer_tests_XXXXXX)"
trap 'rm -rf "${TEST_WORKSPACE}"' EXIT

# Helper for testing PyYAML parsing with custom HA tags
verify_yaml_py() {
  local yaml_file="$1"
  local python_code="$2"
  YAML_FILE="${yaml_file}" PYTHON_CODE="${python_code}" eval "${PYTHON_CMD}" - << 'EOF'
import os, sys, yaml

yaml_file = os.environ["YAML_FILE"]
code = os.environ["PYTHON_CODE"]

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

bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T1_DIR}" >/dev/null

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

bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T1_DIR}" >/dev/null

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

bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T3_DIR}" >/dev/null

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

bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T4_DIR}" >/dev/null

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
# Test 5: Download Failure Handling (B1, I1, HTML body validation)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 5: Download error handling leaves targets untouched... "
T5_DIR="${TEST_WORKSPACE}/t5"
mkdir -p "${T5_DIR}/packages" "${T5_DIR}/www"
cat << 'EOF' > "${T5_DIR}/configuration.yaml"
default_config:
EOF
echo "original-package-content" > "${T5_DIR}/packages/hpwh.yaml"
echo "original-card-content" > "${T5_DIR}/www/hpwh-card.js"

# 5a: Mock curl exiting with error code 22
MOCK_BIN="${TEST_WORKSPACE}/mock_bin"
mkdir -p "${MOCK_BIN}"
cat << 'EOF' > "${MOCK_BIN}/curl"
#!/bin/sh
echo "404: Not Found" >&2
exit 22
EOF
chmod +x "${MOCK_BIN}/curl"

set +e
ERR_OUTPUT=$(PATH="${MOCK_BIN}:/usr/bin:/bin" bash "${INSTALLER}" --yes -c "${T5_DIR}" 2>&1)
EXIT_CODE=$?
set -e

if [[ ${EXIT_CODE} -eq 0 ]]; then
  echo "FAIL: Installer succeeded despite curl error exit"
  exit 1
fi

if [[ "$(< "${T5_DIR}/packages/hpwh.yaml")" != "original-package-content" ]]; then
  echo "FAIL: packages/hpwh.yaml was corrupted by failed curl"
  exit 1
fi

# 5b: Mock curl returning 0 with an HTML error body
cat << 'EOF' > "${MOCK_BIN}/curl"
#!/bin/sh
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    echo "<html><body>404 Not Found</body></html>" > "$2"
    exit 0
  fi
  shift
done
exit 0
EOF

set +e
ERR_OUTPUT=$(PATH="${MOCK_BIN}:/usr/bin:/bin" bash "${INSTALLER}" --yes -c "${T5_DIR}" 2>&1)
EXIT_CODE=$?
set -e

if [[ ${EXIT_CODE} -eq 0 ]]; then
  echo "FAIL: Installer accepted HTML error body as valid YAML/JS"
  exit 1
fi

if ! echo "${ERR_OUTPUT}" | grep -q "Validation failed for"; then
  echo "FAIL: Did not emit validation error for HTML content"
  exit 1
fi

if [[ "$(< "${T5_DIR}/packages/hpwh.yaml")" != "original-package-content" ]]; then
  echo "FAIL: packages/hpwh.yaml was corrupted by HTML body"
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
ERR_OUTPUT=$(bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T6_DIR}" 2>&1)
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
# Test 7: Complex / Custom configuration.yaml shapes (R1, R2, R3, R5)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 7: Complex / custom configuration shapes... "

# 7a: Split config: homeassistant: !include homeassistant.yaml
T7A_DIR="${TEST_WORKSPACE}/t7a"
mkdir -p "${T7A_DIR}"
cat << 'EOF' > "${T7A_DIR}/configuration.yaml"
default_config:

homeassistant: !include homeassistant.yaml
EOF

set +e
T7A_OUT=$(bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T7A_DIR}" 2>&1)
T7A_EXIT=$?
set -e

if [[ ${T7A_EXIT} -ne 2 ]]; then
  echo "FAIL: Expected exit code 2 for split config, got ${T7A_EXIT}"
  exit 1
fi

if ! echo "${T7A_OUT}" | grep -q "INCOMPLETE: Manual Configuration Step Required"; then
  echo "FAIL: Missing INCOMPLETE banner on split config"
  exit 1
fi

verify_yaml_py "${T7A_DIR}/configuration.yaml" "
assert cfg.get('homeassistant') == 'homeassistant.yaml', 'Split include was corrupted'
"

# 7b: Custom indentation (4 spaces) -> should report INCOMPLETE and exit 2 (R5)
T7B_DIR="${TEST_WORKSPACE}/t7b"
mkdir -p "${T7B_DIR}"
cat << 'EOF' > "${T7B_DIR}/configuration.yaml"
default_config:

homeassistant:
    name: Four Space Cabin
    time_zone: UTC
EOF

set +e
T7B_OUT=$(bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T7B_DIR}" 2>&1)
T7B_EXIT=$?
set -e

if [[ ${T7B_EXIT} -ne 2 ]]; then
  echo "FAIL: Expected exit code 2 for 4-space indent config, got ${T7B_EXIT}"
  exit 1
fi

if ! echo "${T7B_OUT}" | grep -q "INCOMPLETE: Manual Configuration Step Required"; then
  echo "FAIL: Missing INCOMPLETE banner on 4-space config"
  exit 1
fi

# 7c: Comment containing # packages: -> correctly enables packages
T7C_DIR="${TEST_WORKSPACE}/t7c"
mkdir -p "${T7C_DIR}"
cat << 'EOF' > "${T7C_DIR}/configuration.yaml"
default_config:

# packages: this is a comment about packages
homeassistant:
  name: Cabin With Comment
EOF

bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T7C_DIR}" >/dev/null

verify_yaml_py "${T7C_DIR}/configuration.yaml" "
assert 'packages' in cfg['homeassistant'], 'packages was not enabled due to false comment match'
"

# 7d: Pre-existing packages include pointing to integrations/ (R1)
T7D_DIR="${TEST_WORKSPACE}/t7d"
mkdir -p "${T7D_DIR}"
cat << 'EOF' > "${T7D_DIR}/configuration.yaml"
default_config:

homeassistant:
  name: Integrations Cabin
  packages: !include_dir_named integrations
EOF

bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T7D_DIR}" >/dev/null

# Assert that package was installed into integrations/ and NOT packages/ (R1)
if [[ ! -f "${T7D_DIR}/integrations/hpwh.yaml" ]]; then
  echo "FAIL: Package was not installed into detected directory integrations/ (R1)"
  exit 1
fi

if [[ -d "${T7D_DIR}/packages" ]]; then
  echo "FAIL: Incorrect packages/ directory created when integrations was configured (R1)"
  exit 1
fi

# 7e: CRLF, inline comment and trailing spaces: homeassistant:  # core config (R2)
T7E_DIR="${TEST_WORKSPACE}/t7e"
mkdir -p "${T7E_DIR}"
printf "default_config:\r\n\r\nhomeassistant:   # core config with spaces   \r\n  name: CRLF Home\r\n" > "${T7E_DIR}/configuration.yaml"

bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T7E_DIR}" >/dev/null

verify_yaml_py "${T7E_DIR}/configuration.yaml" "
assert 'packages' in cfg['homeassistant'], 'packages was not inserted after homeassistant with trailing comment'
"

# 7f: Incompatible !include_dir_merge_named (R3)
T7F_DIR="${TEST_WORKSPACE}/t7f"
mkdir -p "${T7F_DIR}"
cat << 'EOF' > "${T7F_DIR}/configuration.yaml"
default_config:

homeassistant:
  name: Merge Named Cabin
  packages: !include_dir_merge_named pkgs
EOF

set +e
T7F_OUT=$(bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T7F_DIR}" 2>&1)
T7F_EXIT=$?
set -e

if [[ ${T7F_EXIT} -ne 2 ]]; then
  echo "FAIL: Expected exit code 2 for merge_named config, got ${T7F_EXIT}"
  exit 1
fi

if ! echo "${T7F_OUT}" | grep -q "!include_dir_merge_named"; then
  echo "FAIL: Missing explanation for merge_named incompatibility"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 8: User Customizations Preserved Without --force (R4)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 8: User-customized hpwh.yaml preserved without --force... "
T8_DIR="${TEST_WORKSPACE}/t8"
mkdir -p "${T8_DIR}"
cat << 'EOF' > "${T8_DIR}/configuration.yaml"
default_config:
EOF

# Initial install sets up hash
bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T8_DIR}" >/dev/null

# User modifies tank_cfg
sed -i.orig 's/tank_cfg = 65.0/tank_cfg = 80.0/' "${T8_DIR}/packages/hpwh.yaml"

# Run update WITHOUT --force: user file must be preserved, upstream copy saved as .upstream-*
bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T8_DIR}" >/dev/null

if ! grep -q "tank_cfg = 80.0" "${T8_DIR}/packages/hpwh.yaml"; then
  echo "FAIL: User modifications were overwritten without --force (R4)"
  exit 1
fi

UPSTREAM_COUNT=$(find "${T8_DIR}/packages" -name "hpwh.yaml.upstream-*" | wc -l | tr -d ' ')
if [[ "${UPSTREAM_COUNT}" -lt 1 ]]; then
  echo "FAIL: Upstream file was not saved as hpwh.yaml.upstream-<timestamp> (R4)"
  exit 1
fi

# Run update WITH --force: file is replaced and a backup is saved
bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes --force -c "${T8_DIR}" >/dev/null

if grep -q "tank_cfg = 80.0" "${T8_DIR}/packages/hpwh.yaml"; then
  echo "FAIL: --force did not update hpwh.yaml"
  exit 1
fi

BAK_COUNT=$(find "${T8_DIR}/packages" -name "hpwh.yaml.bak-*" | wc -l | tr -d ' ')
if [[ "${BAK_COUNT}" -lt 1 ]]; then
  echo "FAIL: Backup not created on --force overwrite"
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

# Pre-place hpwh.yaml in the directory
cp "${REPO_ROOT}/hpwh/hpwh.yaml" "${T9_DIR}/packages/hpwh.yaml"

(
  cd "${T9_DIR}/packages"
  cat "${INSTALLER}" | bash -s -- --local "${REPO_ROOT}/hpwh" --yes -c "${T9_DIR}" >/dev/null
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

OUTPUT=$(bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T10_DIR}")

if ! echo "${OUTPUT}" | grep -q "Warning: Found existing 'unique_id: water_heater_state_of_charge'"; then
  echo "FAIL: Did not warn about duplicate unique_id in templates.yaml"
  exit 1
fi
echo "PASS"

# ------------------------------------------------------------------------------
# Test 11: Uninstall and Dry-Run (I14, R11)
# ------------------------------------------------------------------------------
echo -n "  • Scenario 11: Dry-run and uninstall workflows... "
T11_DIR="${TEST_WORKSPACE}/t11"
mkdir -p "${T11_DIR}"
cat << 'EOF' > "${T11_DIR}/configuration.yaml"
default_config:
EOF

# Dry-run should not create files
bash "${INSTALLER}" --dry-run --local "${REPO_ROOT}/hpwh" --yes -c "${T11_DIR}" >/dev/null
if [[ -d "${T11_DIR}/packages" || -d "${T11_DIR}/www" ]]; then
  echo "FAIL: Dry-run created directories or files"
  exit 1
fi

# Real install followed by uninstall
bash "${INSTALLER}" --local "${REPO_ROOT}/hpwh" --yes -c "${T11_DIR}" >/dev/null
if [[ ! -f "${T11_DIR}/packages/hpwh.yaml" || ! -f "${T11_DIR}/www/hpwh-card.js" ]]; then
  echo "FAIL: Install failed prior to uninstall test"
  exit 1
fi

bash "${INSTALLER}" --uninstall --yes -c "${T11_DIR}" >/dev/null
if [[ -f "${T11_DIR}/packages/hpwh.yaml" || -f "${T11_DIR}/www/hpwh-card.js" ]]; then
  echo "FAIL: Uninstall did not remove package or card files"
  exit 1
fi

# Verify a backup was created before package removal (R11)
UNINSTALL_BAK=$(find "${T11_DIR}/packages" -name "hpwh.yaml.bak-*" | wc -l | tr -d ' ')
if [[ "${UNINSTALL_BAK}" -lt 1 ]]; then
  echo "FAIL: Backup not created on uninstall (R11)"
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
