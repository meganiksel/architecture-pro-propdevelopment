#!/bin/bash
# =============================================================================
# Скрипт фильтрации Kubernetes Audit Log — PropDevelopment
# =============================================================================
# Использование:
#   ./filter-audit.sh [путь_к_audit.log] [директория_результатов]
#
# Примеры:
#   ./filter-audit.sh /var/log/audit.log ./results
#   ./filter-audit.sh audit-extract.json ./results
#   ./filter-audit.sh   # демо-режим с audit-extract.json
#
# Зависимости: jq, grep, awk
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Конфигурация
# -----------------------------------------------------------------------------
AUDIT_LOG="${1:-/var/log/audit.log}"
OUTPUT_DIR="${2:-./audit-results}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Цвета для вывода
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Счётчики
TOTAL_SUSPICIOUS=0
TOTAL_CRITICAL=0

# -----------------------------------------------------------------------------
# Проверка зависимостей
# -----------------------------------------------------------------------------
check_dependencies() {
  local missing=0
  for cmd in jq grep awk; do
    if ! command -v "$cmd" &>/dev/null; then
      echo -e "${RED}[ERROR] Не найдена утилита: $cmd${NC}"
      missing=1
    fi
  done
  if [ $missing -eq 1 ]; then
    echo "Установите недостающие утилиты и повторите запуск."
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Проверка наличия файла аудита
# -----------------------------------------------------------------------------
check_audit_log() {
  if [ ! -f "$AUDIT_LOG" ]; then
    echo -e "${YELLOW}[WARN] Файл аудита не найден: $AUDIT_LOG${NC}"
    echo "       Переключаюсь на демо-режим: audit-extract.json"
    AUDIT_LOG="$(dirname "$0")/audit-extract.json"
    if [ ! -f "$AUDIT_LOG" ]; then
      echo -e "${RED}[ERROR] Файл audit-extract.json тоже не найден.${NC}"
      echo "        Запустите: $0 /path/to/audit.log"
      exit 1
    fi
  fi
  echo -e "${GREEN}[INFO] Анализируется файл: $AUDIT_LOG${NC}"
}

# -----------------------------------------------------------------------------
# Создание директории для результатов
# -----------------------------------------------------------------------------
setup_output() {
  mkdir -p "$OUTPUT_DIR"
  echo -e "${GREEN}[INFO] Результаты сохраняются в: $OUTPUT_DIR${NC}"
}

# -----------------------------------------------------------------------------
# Вывод заголовка секции
# -----------------------------------------------------------------------------
section() {
  echo ""
  echo -e "${BLUE}================================================================${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}================================================================${NC}"
}

# -----------------------------------------------------------------------------
# Фильтрация через jq — поддерживает NDJSON и JSON-массив
# -----------------------------------------------------------------------------
jq_filter() {
  local filter="$1"
  local file="$2"
  local first_char
  first_char=$(head -c 1 "$file" 2>/dev/null || echo "")

  if [ "$first_char" = "[" ]; then
    # JSON-массив (audit-extract.json)
    jq -c ".[] | select($filter)" "$file" 2>/dev/null || true
  else
    # NDJSON — стандартный audit.log (одна строка = один JSON)
    jq -c "select($filter)" "$file" 2>/dev/null || true
  fi
}

# -----------------------------------------------------------------------------
# Подсчёт строк результата
# -----------------------------------------------------------------------------
count_results() {
  echo "$1" | grep -c "^{" 2>/dev/null || echo "0"
}

# =============================================================================
# ПРОВЕРКА 1: Доступ к секретам
# =============================================================================
check_secrets_access() {
  section "ПРОВЕРКА 1: Доступ к секретам (secrets)"

  local output_file="$OUTPUT_DIR/01-secrets-access-${TIMESTAMP}.json"
  local filter='.objectRef.resource=="secrets" and (.verb=="get" or .verb=="list" or .verb=="watch")'

  echo "Фильтр: objectRef.resource=secrets AND verb IN (get, list, watch)"
  echo ""

  local results
  results=$(jq_filter "$filter" "$AUDIT_LOG")
  local count
  count=$(count_results "$results")

  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}[OK] Подозрительных обращений к секретам не найдено.${NC}"
  else
    echo -e "${RED}[ALERT] Найдено обращений к секретам: $count${NC}"
    TOTAL_SUSPICIOUS=$((TOTAL_SUSPICIOUS + count))
    echo ""
    echo "$results" | jq -r '
      "  Время:        " + (.requestReceivedTimestamp // "unknown") +
      "\n  Пользователь: " + (.user.username // "unknown") +
      "\n  Действие:     " + (.verb // "unknown") +
      "\n  Namespace:    " + (.objectRef.namespace // "cluster-level") +
      "\n  Ресурс:       " + (.objectRef.name // "*") +
      "\n  HTTP-статус:  " + ((.responseStatus.code // 0) | tostring) +
      "\n  ---"
    ' 2>/dev/null || echo "$results"
    echo "$results" > "$output_file"
    echo -e "${YELLOW}[SAVED] $output_file${NC}"
  fi
}

# =============================================================================
# ПРОВЕРКА 2: Создание привилегированных подов
# =============================================================================
check_privileged_pods() {
  section "ПРОВЕРКА 2: Привилегированные поды (privileged: true)"

  local output_file="$OUTPUT_DIR/02-privileged-pods-${TIMESTAMP}.json"
  local filter='.objectRef.resource=="pods" and .verb=="create" and (.requestObject.spec.containers[]?.securityContext.privileged==true)'

  echo "Фильтр: resource=pods AND verb=create AND securityContext.privileged=true"
  echo ""

  local results
  results=$(jq_filter "$filter" "$AUDIT_LOG")
  local count
  count=$(count_results "$results")

  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}[OK] Привилегированных подов не обнаружено.${NC}"
  else
    echo -e "${RED}[CRITICAL] Обнаружено создание привилегированных подов: $count${NC}"
    TOTAL_SUSPICIOUS=$((TOTAL_SUSPICIOUS + count))
    TOTAL_CRITICAL=$((TOTAL_CRITICAL + count))
    echo ""
    echo "$results" | jq -r '
      "  Время:        " + (.requestReceivedTimestamp // "unknown") +
      "\n  Пользователь: " + (.user.username // "unknown") +
      "\n  Под:          " + (.objectRef.namespace // "default") + "/" + (.objectRef.name // "unknown") +
      "\n  Образ:        " + (.requestObject.spec.containers[0].image // "unknown") +
      "\n  ⚠ ОПАСНОСТЬ:  privileged=true → доступ к хосту кластера!" +
      "\n  ---"
    ' 2>/dev/null || echo "$results"
    echo "$results" > "$output_file"
    echo -e "${YELLOW}[SAVED] $output_file${NC}"
  fi
}

# =============================================================================
# ПРОВЕРКА 3: Использование kubectl exec
# =============================================================================
check_kubectl_exec() {
  section "ПРОВЕРКА 3: Использование kubectl exec (pods/exec)"

  local output_file="$OUTPUT_DIR/03-kubectl-exec-${TIMESTAMP}.json"
  local filter='.verb=="create" and .objectRef.subresource=="exec"'

  echo "Фильтр: verb=create AND subresource=exec"
  echo ""

  local results
  results=$(jq_filter "$filter" "$AUDIT_LOG")
  local count
  count=$(count_results "$results")

  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}[OK] Использование kubectl exec не обнаружено.${NC}"
  else
    echo -e "${YELLOW}[WARN] Обнаружено использование kubectl exec: $count${NC}"
    TOTAL_SUSPICIOUS=$((TOTAL_SUSPICIOUS + count))
    echo ""
    echo "$results" | jq -r '
      "  Время:        " + (.requestReceivedTimestamp // "unknown") +
      "\n  Пользователь: " + (.user.username // "unknown") +
      "\n  Под:          " + (.objectRef.namespace // "default") + "/" + (.objectRef.name // "unknown") +
      "\n  Команда:      " + ((.requestObject.command // []) | join(" ")) +
      "\n  ---"
    ' 2>/dev/null || echo "$results"
    echo "$results" > "$output_file"
    echo -e "${YELLOW}[SAVED] $output_file${NC}"
  fi
}

# =============================================================================
# ПРОВЕРКА 4: Создание RoleBinding / ClusterRoleBinding
# =============================================================================
check_rolebindings() {
  section "ПРОВЕРКА 4: Создание/изменение RoleBinding и ClusterRoleBinding"

  local output_file="$OUTPUT_DIR/04-rolebindings-${TIMESTAMP}.json"
  local filter='(.objectRef.resource=="rolebindings" or .objectRef.resource=="clusterrolebindings") and (.verb=="create" or .verb=="update" or .verb=="patch")'

  echo "Фильтр: resource IN (rolebindings, clusterrolebindings) AND verb IN (create, update, patch)"
  echo ""

  local results
  results=$(jq_filter "$filter" "$AUDIT_LOG")
  local count
  count=$(count_results "$results")

  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}[OK] Создание RoleBinding не обнаружено.${NC}"
  else
    echo -e "${RED}[CRITICAL] Обнаружено создание/изменение RoleBinding: $count${NC}"
    TOTAL_SUSPICIOUS=$((TOTAL_SUSPICIOUS + count))
    TOTAL_CRITICAL=$((TOTAL_CRITICAL + count))
    echo ""
    echo "$results" | jq -r '
      "  Время:        " + (.requestReceivedTimestamp // "unknown") +
      "\n  Пользователь: " + (.user.username // "unknown") +
      "\n  Ресурс:       " + (.objectRef.resource // "unknown") + "/" + (.objectRef.name // "unknown") +
      "\n  Namespace:    " + (.objectRef.namespace // "cluster-level") +
      "\n  RoleRef:      " + (.requestObject.roleRef.kind // "?") + "/" + (.requestObject.roleRef.name // "?") +
      "\n  Субъекты:     " + ([(.requestObject.subjects[]? | .kind + ":" + .name)] | join(", ")) +
      "\n  ---"
    ' 2>/dev/null || echo "$results"
    echo "$results" > "$output_file"
    echo -e "${YELLOW}[SAVED] $output_file${NC}"
  fi
}

# =============================================================================
# ПРОВЕРКА 5: Удаление или изменение audit-policy
# =============================================================================
check_audit_policy_tampering() {
  section "ПРОВЕРКА 5: Удаление/изменение audit-policy"

  local output_file="$OUTPUT_DIR/05-audit-policy-${TIMESTAMP}.json"

  echo "Фильтр: grep 'audit-policy' в audit.log"
  echo ""

  # Используем grep для поиска по тексту (быстрее для больших файлов)
  local grep_results
  grep_results=$(grep -i "audit-policy" "$AUDIT_LOG" 2>/dev/null || true)

  if [ -z "$grep_results" ]; then
    echo -e "${GREEN}[OK] Попыток изменения audit-policy не обнаружено.${NC}"
  else
    local count
    count=$(echo "$grep_results" | wc -l)
    echo -e "${RED}[CRITICAL] Обнаружены события с audit-policy: $count${NC}"
    TOTAL_SUSPICIOUS=$((TOTAL_SUSPICIOUS + count))
    TOTAL_CRITICAL=$((TOTAL_CRITICAL + count))
    echo ""

    # Парсим как JSON если возможно
    echo "$grep_results" | while IFS= read -r line; do
      if echo "$line" | jq -e . &>/dev/null 2>&1; then
        echo "$line" | jq -r '
          "  Время:        " + (.requestReceivedTimestamp // "unknown") +
          "\n  Пользователь: " + (.user.username // "unknown") +
          "\n  Действие:     " + (.verb // "unknown") +
          "\n  Ресурс:       " + (.objectRef.name // "unknown") +
          "\n  Имперсонация: " + (.impersonatedUser.username // "нет") +
          "\n  ⚠ ОПАСНОСТЬ:  Попытка отключить аудит кластера!" +
          "\n  ---"
        ' 2>/dev/null || echo "  Строка: $line"
      else
        echo "  Строка: $line"
      fi
    done

    echo "$grep_results" > "$output_file"
    echo -e "${YELLOW}[SAVED] $output_file${NC}"
  fi
}

# =============================================================================
# ПРОВЕРКА 6: Имперсонация пользователей
# =============================================================================
check_impersonation() {
  section "ПРОВЕРКА 6: Имперсонация пользователей (--as флаг)"

  local output_file="$OUTPUT_DIR/06-impersonation-${TIMESTAMP}.json"
  local filter='.impersonatedUser != null'

  echo "Фильтр: impersonatedUser != null"
  echo ""

  local results
  results=$(jq_filter "$filter" "$AUDIT_LOG")
  local count
  count=$(count_results "$results")

  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}[OK] Имперсонация пользователей не обнаружена.${NC}"
  else
    echo -e "${RED}[ALERT] Обнаружена имперсонация пользователей: $count${NC}"
    TOTAL_SUSPICIOUS=$((TOTAL_SUSPICIOUS + count))
    echo ""
    echo "$results" | jq -r '
      "  Время:           " + (.requestReceivedTimestamp // "unknown") +
      "\n  Реальный польз.: " + (.user.username // "unknown") +
      "\n  Имперсонирует:   " + (.impersonatedUser.username // "unknown") +
      "\n  Действие:        " + (.verb // "unknown") + " " + (.objectRef.resource // "") +
      "\n  ---"
    ' 2>/dev/null || echo "$results"
    echo "$results" > "$output_file"
    echo -e "${YELLOW}[SAVED] $output_file${NC}"
  fi
}

# =============================================================================
# ПРОВЕРКА 7: Доступ к kube-system от посторонних ServiceAccount
# =============================================================================
check_cross_namespace_access() {
  section "ПРОВЕРКА 7: Доступ к kube-system от посторонних ServiceAccount"

  local output_file="$OUTPUT_DIR/07-cross-namespace-${TIMESTAMP}.json"
  local filter='.objectRef.namespace=="kube-system" and (.user.username | startswith("system:serviceaccount:")) and (.user.username | contains(":kube-system:") | not)'

  echo "Фильтр: namespace=kube-system AND user=system:serviceaccount:* (не из kube-system)"
  echo ""

  local results
  results=$(jq_filter "$filter" "$AUDIT_LOG")
  local count
  count=$(count_results "$results")

  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}[OK] Подозрительного кросс-namespace доступа не обнаружено.${NC}"
  else
    echo -e "${RED}[ALERT] Обнаружен доступ к kube-system от посторонних SA: $count${NC}"
    TOTAL_SUSPICIOUS=$((TOTAL_SUSPICIOUS + count))
    echo ""
    echo "$results" | jq -r '
      "  Время:        " + (.requestReceivedTimestamp // "unknown") +
      "\n  ServiceAccount: " + (.user.username // "unknown") +
      "\n  Действие:     " + (.verb // "unknown") +
      "\n  Ресурс:       " + (.objectRef.resource // "unknown") + "/" + (.objectRef.name // "*") +
      "\n  ---"
    ' 2>/dev/null || echo "$results"
    echo "$results" > "$output_file"
    echo -e "${YELLOW}[SAVED] $output_file${NC}"
  fi
}

# =============================================================================
# ИТОГОВЫЙ ОТЧЁТ
# =============================================================================
print_summary() {
  section "ИТОГОВЫЙ ОТЧЁТ"

  local summary_file="$OUTPUT_DIR/SUMMARY-${TIMESTAMP}.txt"

  {
    echo "================================================================"
    echo "  ИТОГИ АНАЛИЗА KUBERNETES AUDIT LOG"
    echo "  Дата анализа: $(date)"
    echo "  Файл аудита:  $AUDIT_LOG"
    echo "================================================================"
    echo ""
    echo "  Всего подозрительных событий: $TOTAL_SUSPICIOUS"
    echo "  Из них критических:           $TOTAL_CRITICAL"
    echo ""
    echo "  Результаты сохранены в: $OUTPUT_DIR"
    echo "================================================================"
  } | tee "$summary_file"

  if [ "$TOTAL_CRITICAL" -gt 0 ]; then
    echo -e "${RED}"
    echo "  ⚠ ВНИМАНИЕ: Обнаружены КРИТИЧЕСКИЕ инциденты!"
    echo "  Требуется немедленное реагирование."
    echo -e "${NC}"
  elif [ "$TOTAL_SUSPICIOUS" -gt 0 ]; then
    echo -e "${YELLOW}"
    echo "  ⚠ Обнаружены подозрительные события. Требуется проверка."
    echo -e "${NC}"
  else
    echo -e "${GREEN}"
    echo "  ✓ Подозрительных событий не обнаружено."
    echo -e "${NC}"
  fi
}

# =============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# =============================================================================
main() {
  echo -e "${CYAN}"
  echo "================================================================"
  echo "  Kubernetes Audit Log Analyzer — PropDevelopment"
  echo "  Версия: 1.0"
  echo "================================================================"
  echo -e "${NC}"

  check_dependencies
  check_audit_log
  setup_output

  # Запуск всех проверок
  check_secrets_access
  check_privileged_pods
  check_kubectl_exec
  check_rolebindings
  check_audit_policy_tampering
  check_impersonation
  check_cross_namespace_access

  # Итоговый отчёт
  print_summary
}

# Запуск
main "$@"
