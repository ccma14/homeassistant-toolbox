#!/usr/bin/env bash
# ==============================================================================
# Monorepo Test Runner: Home Assistant Toolbox
# Runs offline linters, component unit tests, and Home Assistant container checks.
# Usage:
#   ./scripts/test.sh              # Run all linters and all component tests
#   ./scripts/test.sh hpwh         # Run linters and only HPWH component tests
#   ./scripts/test.sh --ha         # Include Home Assistant Core check_config via Colima/Docker
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TARGET_COMPONENT=""
RUN_HA_CONTAINER=false

for arg in "$@"; do
  case "$arg" in
    --ha|--docker)
      RUN_HA_CONTAINER=true
      ;;
    -*)
      echo "Unknown flag: $arg"
      exit 1
      ;;
    *)
      TARGET_COMPONENT="$arg"
      ;;
  esac
done

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}  Home Assistant Toolbox - Monorepo Test Runner       ${NC}"
echo -e "${BLUE}======================================================${NC}"

FAILED=0

# ------------------------------------------------------------------------------
# 1. Global Static Analysis (YAML & JavaScript)
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[1/4] Running Global Static Analysis...${NC}"

# 1a. YAML Linting
YAMLLINT_CMD=""
if command -v yamllint >/dev/null 2>&1 && yamllint --version >/dev/null 2>&1; then
  YAMLLINT_CMD="yamllint"
elif command -v pyenv >/dev/null 2>&1 && PYENV_VERSION=3.12.9 yamllint --version >/dev/null 2>&1; then
  YAMLLINT_CMD="PYENV_VERSION=3.12.9 yamllint"
elif python3 -m yamllint --version >/dev/null 2>&1; then
  YAMLLINT_CMD="python3 -m yamllint"
fi

if [ -n "${YAMLLINT_CMD}" ]; then
  echo -n "  • yamllint: "
  if eval "${YAMLLINT_CMD} -c .yamllint.yaml ." >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    eval "${YAMLLINT_CMD} -c .yamllint.yaml ."
    FAILED=$((FAILED + 1))
  fi
else
  # Python fallback check for YAML syntax validity with custom Home Assistant tags (T-b)
  echo -n "  • python yaml syntax check: "
  YAML_STATUS=0
  PY_OUTPUT=$(python3 - << 'EOF'
import os, sys

try:
    import yaml
except ImportError:
    sys.exit(2)

def ignore_unknown_tag(loader, suffix, node):
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    elif isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node)
    return None

yaml.SafeLoader.add_multi_constructor('!', ignore_unknown_tag)

errors = []
for root, _, files in os.walk("."):
    if any(p in root for p in ["node_modules", ".git", "mock_config/blueprints"]):
        continue
    for f in files:
        if f.endswith(".yaml") or f.endswith(".yml"):
            p = os.path.join(root, f)
            try:
                with open(p, "r", encoding="utf-8") as yf:
                    yaml.safe_load(yf)
            except Exception as ex:
                errors.append(f"{p}: {ex}")

if errors:
    for err in errors:
        print(f"Error in {err}", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
EOF
) || YAML_STATUS=$?

  if [ ${YAML_STATUS} -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}"
  elif [ ${YAML_STATUS} -eq 2 ]; then
    echo -e "${YELLOW}[SKIP]${NC} (pyyaml not installed)"
  else
    echo -e "${RED}FAIL${NC}"
    echo "${PY_OUTPUT}"
    FAILED=$((FAILED + 1))
  fi
fi

# 1b. JavaScript Syntax Check (node --check)
echo -n "  • node syntax check (hpwh-card.js): "
if node --check hpwh/hpwh-card.js >/dev/null 2>&1; then
  echo -e "${GREEN}PASS${NC}"
else
  echo -e "${RED}FAIL${NC}"
  node --check hpwh/hpwh-card.js
  FAILED=$((FAILED + 1))
fi

# 1c. ESLint (T-a, T-c)
if [ -d "node_modules/eslint" ]; then
  echo -n "  • eslint (hpwh-card.js): "
  if npx eslint "hpwh/**/*.js" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    npx eslint "hpwh/**/*.js"
    FAILED=$((FAILED + 1))
  fi
else
  echo -e "  • eslint (hpwh-card.js): ${YELLOW}[SKIP]${NC} (eslint not installed in node_modules)"
fi

# ------------------------------------------------------------------------------
# 2. Component Unit & Fixture Tests
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[2/4] Running Component Tests...${NC}"

RUN_HPWH=true
if [ -n "${TARGET_COMPONENT}" ] && [ "${TARGET_COMPONENT}" != "hpwh" ]; then
  RUN_HPWH=false
fi

if [ "${RUN_HPWH}" = true ]; then
  echo -e "  ${YELLOW}Component: hpwh${NC}"
  
  # Card tests
  echo -n "    • test_card.js (version sync, grid options, editor schema): "
  if node hpwh/tests/test_card.js >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    node hpwh/tests/test_card.js
    FAILED=$((FAILED + 1))
  fi

  # Template formula & availability tests
  echo -n "    • test_templates.py (SoC %, boost surplus, shower metrics): "
  if python3 hpwh/tests/test_templates.py >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    python3 hpwh/tests/test_templates.py
    FAILED=$((FAILED + 1))
  fi

  # Installer tests (T-f)
  echo -n "    • test_installer.sh (edge cases, download errors, idempotency): "
  if bash hpwh/tests/test_installer.sh >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    bash hpwh/tests/test_installer.sh
    FAILED=$((FAILED + 1))
  fi
fi

# ------------------------------------------------------------------------------
# 3. Home Assistant Container Config Check (via Colima / Docker)
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[3/4] Home Assistant Core Validation...${NC}"

if [ "${RUN_HA_CONTAINER}" = true ]; then
  if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    echo "  • Preparing mock config and running 'hass --script check_config' via Colima/Docker..."
    mkdir -p "${REPO_ROOT}/hpwh/tests/mock_config/blueprints/automation/hpwh"
    cp "${REPO_ROOT}/hpwh/blueprint.yaml" "${REPO_ROOT}/hpwh/tests/mock_config/blueprints/automation/hpwh/blueprint.yaml"
    bash "${REPO_ROOT}/hpwh/install.sh" --local -c "${REPO_ROOT}/hpwh/tests/mock_config" >/dev/null
    if docker run --rm -v "${REPO_ROOT}/hpwh/tests/mock_config:/config:ro" ghcr.io/home-assistant/home-assistant:stable python3 -m homeassistant --config /config --script check_config; then
      echo -e "  • HA Core validation: ${GREEN}PASS${NC}"
    else
      echo -e "  • HA Core validation: ${RED}FAIL${NC}"
      FAILED=$((FAILED + 1))
    fi
  else
    echo -e "  ${YELLOW}Docker/Colima is not running. Start it with 'colima start' to run HA container checks.${NC}"
  fi
else
  echo -e "  ${YELLOW}[SKIP]${NC} Container check skipped (offline mode). Pass ${YELLOW}--ha${NC} to run via Colima."
fi

# ------------------------------------------------------------------------------
# 4. Summary & Status
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}[4/4] Test Summary${NC}"
if [ ${FAILED} -eq 0 ]; then
  echo -e "${GREEN}All checks and tests passed successfully!${NC}\n"
  exit 0
else
  echo -e "${RED}${FAILED} test(s) or check(s) failed.${NC}\n"
  exit 1
fi
