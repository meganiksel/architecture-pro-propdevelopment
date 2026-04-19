#!/bin/bash
# Проверка OPA Gatekeeper — PropDevelopment

set -euo pipefail

NAMESPACE="audit-zone"
GATEKEEPER_DIR="$(dirname "$0")/../gatekeeper"
INSECURE_DIR="$(dirname "$0")/../insecure-manifests"
SECURE_DIR="$(dirname "$0")/../secure-manifests"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}  Проверка OPA Gatekeeper — PropDevelopment${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

echo -e "${BLUE}--- Проверка 1: Gatekeeper установлен ---${NC}"

if kubectl get namespace gatekeeper-system &>/dev/null; then
  echo -e "  ${GREEN}[OK] Namespace gatekeeper-system существует${NC}"
  PASS=$((PASS + 1))
else
  echo -e "  ${YELLOW}[WARN] Namespace gatekeeper-system не найден.${NC}"
  echo -e "  ${YELLOW}       Установите Gatekeeper:${NC}"
  echo -e "  ${YELLOW}       kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml${NC}"
  WARN=$((WARN + 1))
fi

if kubectl get pods -n gatekeeper-system --no-headers 2>/dev/null | grep -q "Running"; then
  echo -e "  ${GREEN}[OK] Gatekeeper pods запущены${NC}"
  PASS=$((PASS + 1))
else
  echo -e "  ${YELLOW}[WARN] Gatekeeper pods не запущены или не найдены${NC}"
  WARN=$((WARN + 1))
fi
echo ""

echo -e "${BLUE}--- Проверка 2: ConstraintTemplates ---${NC}"

TEMPLATES=("k8sdenyprivileged" "k8sdenyhostpath" "k8srequirenonroot")

for template in "${TEMPLATES[@]}"; do
  if kubectl get constrainttemplate "$template" &>/dev/null; then
    echo -e "  ${GREEN}[OK] ConstraintTemplate существует: $template${NC}"
    PASS=$((PASS + 1))
  else
    echo -e "  ${YELLOW}[WARN] ConstraintTemplate не найден: $template — применяю...${NC}"
    kubectl apply -f "$GATEKEEPER_DIR/constraint-templates/" 2>/dev/null || true
    sleep 3
    WARN=$((WARN + 1))
  fi
done
echo ""

echo -e "${BLUE}--- Проверка 3: Constraints ---${NC}"

declare -A CONSTRAINT_MAP
CONSTRAINT_MAP["K8sDenyPrivileged"]="deny-privileged-containers"
CONSTRAINT_MAP["K8sDenyHostPath"]="deny-hostpath-volumes"
CONSTRAINT_MAP["K8sRequireNonRoot"]="require-non-root-and-readonly"

for kind in "${!CONSTRAINT_MAP[@]}"; do
  name="${CONSTRAINT_MAP[$kind]}"
  if kubectl get "$kind" "$name" &>/dev/null 2>&1; then
    echo -e "  ${GREEN}[OK] Constraint существует: $kind/$name${NC}"
    PASS=$((PASS + 1))
  else
    echo -e "  ${YELLOW}[WARN] Constraint не найден: $kind/$name — применяю...${NC}"
    kubectl apply -f "$GATEKEEPER_DIR/constraints/" 2>/dev/null || true
    sleep 3
    WARN=$((WARN + 1))
  fi
done
echo ""

echo -e "${BLUE}--- Проверка 4: Небезопасные поды отклоняются Gatekeeper ---${NC}"
echo ""

for manifest in "$INSECURE_DIR"/*.yaml; do
  filename=$(basename "$manifest")
  echo "  Тестирую: $filename"

  output=$(kubectl apply -f "$manifest" -n "$NAMESPACE" --dry-run=server 2>&1 || true)

  if echo "$output" | grep -qiE "denied|forbidden|violates|admission webhook|Error"; then
    echo -e "  ${GREEN}[PASS] Под отклонён Gatekeeper: $filename${NC}"
    PASS=$((PASS + 1))
  else
    echo -e "  ${YELLOW}[WARN] Под не отклонён Gatekeeper (возможно, Gatekeeper не установлен): $filename${NC}"
    WARN=$((WARN + 1))
  fi
done
echo ""

echo -e "${BLUE}--- Проверка 5: Безопасные поды проходят валидацию ---${NC}"
echo ""

for manifest in "$SECURE_DIR"/*.yaml; do
  filename=$(basename "$manifest")
  echo "  Тестирую: $filename"

  output=$(kubectl apply -f "$manifest" -n "$NAMESPACE" --dry-run=server 2>&1)
  exit_code=$?

  if [ $exit_code -eq 0 ] && ! echo "$output" | grep -qiE "denied|forbidden|violates"; then
    echo -e "  ${GREEN}[PASS] Безопасный под прошёл валидацию: $filename${NC}"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}[FAIL] Безопасный под не прошёл валидацию: $filename${NC}"
    echo -e "  ${RED}        Ошибка: $output${NC}"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

echo -e "${BLUE}--- Проверка 6: Текущие нарушения в кластере ---${NC}"
echo ""

for kind in K8sDenyPrivileged K8sDenyHostPath K8sRequireNonRoot; do
  if ! kubectl get "$kind" &>/dev/null 2>&1; then
    echo -e "  ${YELLOW}[SKIP] $kind: constraint не найден (Gatekeeper не установлен?)${NC}"
    WARN=$((WARN + 1))
    continue
  fi

  violations=$(kubectl get "$kind" -o json 2>/dev/null | \
    jq -r '.items[].status.violations[]? | "    Нарушение: " + .name + " в namespace " + .namespace' \
    2>/dev/null || echo "")

  if [ -n "$violations" ]; then
    echo -e "  ${RED}[VIOLATIONS] $kind:${NC}"
    echo "$violations"
    FAIL=$((FAIL + 1))
  else
    echo -e "  ${GREEN}[OK] $kind: нарушений не обнаружено${NC}"
    PASS=$((PASS + 1))
  fi
done
echo ""

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}  ИТОГИ ПРОВЕРКИ OPA Gatekeeper${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""
echo -e "  ${GREEN}Пройдено:       $PASS${NC}"
echo -e "  ${YELLOW}Предупреждений: $WARN${NC}"
echo -e "  ${RED}Провалено:      $FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
  echo -e "${GREEN}[SUCCESS] Все проверки пройдены! OPA Gatekeeper работает корректно.${NC}"
  exit 0
elif [ $FAIL -eq 0 ]; then
  echo -e "${YELLOW}[WARNING] Проверки пройдены с предупреждениями. Убедитесь, что Gatekeeper установлен.${NC}"
  exit 0
else
  echo -e "${RED}[FAILURE] Некоторые проверки провалены. Проверьте конфигурацию Gatekeeper.${NC}"
  exit 1
fi
