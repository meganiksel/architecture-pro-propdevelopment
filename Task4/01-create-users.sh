#!/bin/bash
# =============================================================================
# Скрипт 1: Создание пользователей Kubernetes для PropDevelopment
# =============================================================================
# Создаёт пользователей через механизм сертификатов X.509 (CSR).
# Каждый пользователь получает клиентский сертификат, подписанный CA кластера.
# =============================================================================

set -euo pipefail

CLUSTER_NAME="minikube"
NAMESPACE_DEV="propdevelopment-dev"

echo "=== PropDevelopment: Создание пользователей Kubernetes ==="
echo ""

# -----------------------------------------------------------------------------
# Функция создания пользователя через CSR
# -----------------------------------------------------------------------------
create_user() {
  local USERNAME=$1
  local GROUP=$2

  echo ">>> Создание пользователя: ${USERNAME} (группа: ${GROUP})"

  # 1. Генерация приватного ключа
  openssl genrsa -out "${USERNAME}.key" 2048 2>/dev/null
  echo "    [OK] Приватный ключ: ${USERNAME}.key"

  # 2. Создание Certificate Signing Request (CSR)
  # CN = имя пользователя, O = группа (используется Kubernetes для RBAC)
  openssl req -new \
    -key "${USERNAME}.key" \
    -out "${USERNAME}.csr" \
    -subj "/CN=${USERNAME}/O=${GROUP}" 2>/dev/null
  echo "    [OK] CSR создан: ${USERNAME}.csr"

  # 3. Создание CertificateSigningRequest в Kubernetes
  CSR_BASE64=$(cat "${USERNAME}.csr" | base64 | tr -d '\n')

  cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USERNAME}-csr
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 31536000  # 1 год
  usages:
    - client auth
EOF
  echo "    [OK] CSR отправлен в Kubernetes"

  # 4. Одобрение CSR
  kubectl certificate approve "${USERNAME}-csr"
  echo "    [OK] CSR одобрен"

  # 5. Получение подписанного сертификата
  sleep 2
  kubectl get csr "${USERNAME}-csr" -o jsonpath='{.status.certificate}' | \
    base64 --decode > "${USERNAME}.crt"
  echo "    [OK] Сертификат получен: ${USERNAME}.crt"

  # 6. Создание kubeconfig для пользователя
  CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  CLUSTER_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

  kubectl config set-credentials "${USERNAME}" \
    --client-certificate="${USERNAME}.crt" \
    --client-key="${USERNAME}.key" \
    --embed-certs=true

  kubectl config set-context "${USERNAME}-context" \
    --cluster="${CLUSTER_NAME}" \
    --user="${USERNAME}"

  echo "    [OK] Контекст создан: ${USERNAME}-context"
  echo ""
}

# -----------------------------------------------------------------------------
# Создание namespace для разработчиков
# -----------------------------------------------------------------------------
echo ">>> Создание namespace: ${NAMESPACE_DEV}"
kubectl create namespace "${NAMESPACE_DEV}" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "${NAMESPACE_DEV}" \
  environment=development \
  team=propdevelopment \
  --overwrite
echo "    [OK] Namespace создан: ${NAMESPACE_DEV}"
echo ""

# -----------------------------------------------------------------------------
# Создание пользователей
# -----------------------------------------------------------------------------

# 1. DevOps-инженер — полный доступ к кластеру
create_user "devops-user" "cluster-admins"

# 2. Бизнес-аналитик — только просмотр ресурсов кластера
create_user "analyst-user" "cluster-viewers"

# 3. Инженер по эксплуатации — настройка кластера
create_user "ops-user" "cluster-operators"

# 4. Специалист по ИБ — аудит безопасности (просмотр секретов и политик)
create_user "security-user" "security-auditors"

# 5. Разработчик — управление приложениями в своём namespace
create_user "dev-user" "developers"

# -----------------------------------------------------------------------------
# Итог
# -----------------------------------------------------------------------------
echo "=== Созданные пользователи ==="
echo ""
echo "  Пользователь       | Группа              | Назначение"
echo "  -------------------|---------------------|---------------------------"
echo "  devops-user        | cluster-admins      | DevOps-инженер (полный доступ)"
echo "  analyst-user       | cluster-viewers     | Бизнес-аналитик (только чтение)"
echo "  ops-user           | cluster-operators   | Инженер по эксплуатации"
echo "  security-user      | security-auditors   | Специалист по ИБ (аудит)"
echo "  dev-user           | developers          | Разработчик (namespace: ${NAMESPACE_DEV})"
echo ""
echo "=== Файлы сертификатов ==="
ls -la *.key *.crt *.csr 2>/dev/null || true
echo ""
echo "[DONE] Пользователи созданы успешно."
