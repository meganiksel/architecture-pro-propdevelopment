#!/bin/bash
# Проверка PodSecurity Admission Controller — PropDevelopment

set -euo pipefail

NAMESPACE="audit-zone"
INSECURE_DIR="$(dirname "$0")/../insecure-manifests"
SECURE_DIR="$(dirname "$0")/../secure-manifests"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  Проверка PodSecurity Admission Controller${NC}"
echo -e "${BLUE}  Namespace: $NAMESPACE${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

echo ">>> Проверка namespace $NAMESPACE..."
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo -e "${YELLOW}[WARN] Namespace $NAMESPACE не найден. Создаю...${NC}"
  kubectl apply -f "$(dirname "$0")/../01-create-namespace.yaml"
  sleep 2
fi

# Проверяем метки PodSecurity
ENFORCE_LABEL=$(kubectl get namespace "$NAMESPACE" \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")

if [ "$ENFORCE_LABEL" = "restricted" ]; then
  echo -e "${GREEN}[OK] PodSecurity enforce=restricted установлен на namespace $NAMESPACE${NC}"
  PASS=$((PASS + 1))
else
  echo -e "${RED}[FAIL] PodSecurity enforce=restricted НЕ установлен. Текущее значение: '${ENFORCE_LABEL}'${NC}"
  FAIL=$((FAIL + 1))
fi
echo ""

echo -e "${BLUE}--- Тест 1: Небезопасные поды должны быть ОТКЛОНЕНЫ ---${NC}"
echo ""

for manifest in "$INSECURE_DIR"/*.yaml; do
  filename=$(basename "$manifest")
  echo "  Применяю: $filename"

  if kubectl apply -f "$manifest" -n "$NAMESPACE" --dry-run=server 2>&1 | grep -qi "forbidden\|violates\|denied\|error"; then
    echo -e "  ${GREEN}[PASS] Под ОТКЛОНЁН (ожидаемо): $filename${NC}"
    PASS=$((PASS + 1))
  else
    # Пробуем реальное применение
    if kubectl apply -f "$manifest" -n "$NAMESPACE" 2>&1 | grep -qi "forbidden\|violates\|denied"; then
      echo -e "  ${GREEN}[PASS] Под ОТКЛОНЁН (ожидаемо): $filename${NC}"
      PASS=$((PASS + 1))
    else
      echo -e "  ${RED}[FAIL] Под НЕ был отклонён (неожиданно): $filename${NC}"
      echo -e "  ${RED}        PodSecurity Admission может быть не настроен!${NC}"
      FAIL=$((FAIL + 1))
      # Удаляем случайно созданный под
      kubectl delete -f "$manifest" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    fi
  fi
done
echo ""

echo -e "${BLUE}--- Тест 2: Безопасные поды должны ПРОЙТИ валидацию ---${NC}"
echo ""

for manifest in "$SECURE_DIR"/*.yaml; do
  filename=$(basename "$manifest")
  echo "  Применяю: $filename"

  output=$(kubectl apply -f "$manifest" -n "$NAMESPACE" 2>&1)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo -e "  ${GREEN}[PASS] Под создан успешно: $filename${NC}"
    PASS=$((PASS + 1))
    # Удаляем тестовый под
    kubectl delete -f "$manifest" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
  else
    echo -e "  ${RED}[FAIL] Под НЕ был создан: $filename${NC}"
    echo -e "  ${RED}        Ошибка: $output${NC}"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  ИТОГИ ПРОВЕРКИ PodSecurity Admission${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo -e "  ${GREEN}Пройдено: $PASS${NC}"
echo -e "  ${RED}Провалено: $FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}[SUCCESS] Все проверки пройдены! PodSecurity Admission работает корректно.${NC}"
  exit 0
else
  echo -e "${RED}[FAILURE] Некоторые проверки провалены. Проверьте конфигурацию PodSecurity.${NC}"
  exit 1
fi
