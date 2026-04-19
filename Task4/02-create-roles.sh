#!/bin/bash
# =============================================================================
# Скрипт 2: Создание ролей Kubernetes для PropDevelopment
# =============================================================================
# Создаёт ClusterRole и Role согласно ролевой модели компании.
# Роли соответствуют организационной структуре PropDevelopment.
# =============================================================================

set -euo pipefail

NAMESPACE_DEV="propdevelopment-dev"

echo "=== PropDevelopment: Создание ролей Kubernetes ==="
echo ""

# -----------------------------------------------------------------------------
# ClusterRole: cluster-viewer
# Группа: cluster-viewers (бизнес-аналитики, BI-аналитики)
# Только просмотр ресурсов кластера. БЕЗ доступа к секретам.
# -----------------------------------------------------------------------------
echo ">>> Создание ClusterRole: cluster-viewer"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-viewer
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
    rbac.propdevelopment.ru/group: cluster-viewers
  annotations:
    description: "Только просмотр ресурсов кластера. Для бизнес-аналитиков и BI-аналитиков."
rules:
  # Основные рабочие нагрузки — только чтение
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - endpoints
      - namespaces
      - nodes
      - configmaps
      - events
      - persistentvolumeclaims
      - persistentvolumes
      - serviceaccounts
    verbs: ["get", "list", "watch"]
  # Деплои и масштабирование — только чтение
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch"]
  # Ingress — только чтение
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
      - networkpolicies
    verbs: ["get", "list", "watch"]
  # HPA — только чтение
  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs: ["get", "list", "watch"]
  # Jobs — только чтение
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["get", "list", "watch"]
  # ЗАПРЕЩЕНО: secrets (не включены в rules)
EOF
echo "    [OK] ClusterRole 'cluster-viewer' создана"
echo ""

# -----------------------------------------------------------------------------
# ClusterRole: cluster-operator
# Группа: cluster-operators (инженеры по эксплуатации)
# Управление рабочими нагрузками. БЕЗ доступа к секретам и RBAC.
# -----------------------------------------------------------------------------
echo ">>> Создание ClusterRole: cluster-operator"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-operator
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
    rbac.propdevelopment.ru/group: cluster-operators
  annotations:
    description: "Управление рабочими нагрузками. Для инженеров по эксплуатации."
rules:
  # Основные ресурсы — полное управление (кроме секретов)
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - pods/exec
      - pods/portforward
      - services
      - endpoints
      - configmaps
      - namespaces
      - nodes
      - persistentvolumeclaims
      - serviceaccounts
      - events
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Деплои и масштабирование — полное управление
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Ingress — полное управление
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # HPA — полное управление
  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Jobs — полное управление
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # ЗАПРЕЩЕНО: secrets, roles, rolebindings (не включены в rules)
EOF
echo "    [OK] ClusterRole 'cluster-operator' создана"
echo ""

# -----------------------------------------------------------------------------
# ClusterRole: security-auditor
# Группа: security-auditors (специалист по ИБ)
# Привилегированная роль: просмотр секретов и политик безопасности.
# ТОЛЬКО ЧТЕНИЕ — не может изменять политики.
# -----------------------------------------------------------------------------
echo ">>> Создание ClusterRole: security-auditor"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: security-auditor
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
    rbac.propdevelopment.ru/group: security-auditors
    rbac.propdevelopment.ru/privileged: "true"
  annotations:
    description: "Аудит безопасности: просмотр секретов и политик. Только для специалиста по ИБ."
rules:
  # Секреты — только чтение (привилегированный доступ)
  - apiGroups: [""]
    resources:
      - secrets
      - serviceaccounts
      - pods
      - pods/log
      - nodes
      - namespaces
      - events
      - configmaps
    verbs: ["get", "list", "watch"]
  # RBAC — только чтение
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources:
      - roles
      - rolebindings
      - clusterroles
      - clusterrolebindings
    verbs: ["get", "list", "watch"]
  # Сетевые политики — только чтение
  - apiGroups: ["networking.k8s.io"]
    resources:
      - networkpolicies
      - ingresses
    verbs: ["get", "list", "watch"]
  # Деплои — только чтение
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch"]
  # Аудит политик безопасности подов
  - apiGroups: ["policy"]
    resources:
      - poddisruptionbudgets
    verbs: ["get", "list", "watch"]
EOF
echo "    [OK] ClusterRole 'security-auditor' создана"
echo ""

# -----------------------------------------------------------------------------
# Role: namespace-developer (в namespace propdevelopment-dev)
# Группа: developers (разработчики продуктовых команд)
# Управление приложениями только в своём namespace.
# БЕЗ доступа к секретам и RBAC.
# -----------------------------------------------------------------------------
echo ">>> Создание Role: namespace-developer (namespace: ${NAMESPACE_DEV})"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: namespace-developer
  namespace: ${NAMESPACE_DEV}
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
    rbac.propdevelopment.ru/group: developers
  annotations:
    description: "Управление приложениями в namespace разработки. Для разработчиков."
rules:
  # Поды — полное управление включая exec и logs
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - pods/exec
      - pods/portforward
      - services
      - endpoints
      - configmaps
      - events
      - persistentvolumeclaims
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Деплои — полное управление
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Jobs — полное управление
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Ingress — полное управление
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # ЗАПРЕЩЕНО: secrets, roles, rolebindings (не включены в rules)
EOF
echo "    [OK] Role 'namespace-developer' создана в namespace '${NAMESPACE_DEV}'"
echo ""

# -----------------------------------------------------------------------------
# Итог
# -----------------------------------------------------------------------------
echo "=== Созданные роли ==="
echo ""
kubectl get clusterroles cluster-viewer cluster-operator security-auditor \
  --no-headers 2>/dev/null | \
  awk '{printf "  ClusterRole: %-30s\n", $1}'
kubectl get role namespace-developer -n "${NAMESPACE_DEV}" \
  --no-headers 2>/dev/null | \
  awk -v ns="${NAMESPACE_DEV}" '{printf "  Role:        %-30s (namespace: %s)\n", $1, ns}'
echo ""
echo "[DONE] Роли созданы успешно."
