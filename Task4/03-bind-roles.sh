#!/bin/bash
# =============================================================================
# Скрипт 3: Привязка пользователей к ролям Kubernetes (PropDevelopment)
# =============================================================================
# Создаёт ClusterRoleBinding и RoleBinding для связи пользователей с ролями.
# Использует группы (Groups) для масштабируемого управления доступом.
# =============================================================================

set -euo pipefail

NAMESPACE_DEV="propdevelopment-dev"

echo "=== PropDevelopment: Привязка пользователей к ролям ==="
echo ""

# -----------------------------------------------------------------------------
# ClusterRoleBinding: cluster-admins → cluster-admin (встроенная роль)
# Пользователь: devops-user
# Группа: cluster-admins
# -----------------------------------------------------------------------------
echo ">>> Привязка: cluster-admins → cluster-admin"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admins-binding
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
  annotations:
    description: "DevOps-инженеры: полный доступ к кластеру"
subjects:
  # Привязка к группе (масштабируемо: добавляй пользователей в группу)
  - kind: Group
    name: cluster-admins
    apiGroup: rbac.authorization.k8s.io
  # Явная привязка конкретного пользователя
  - kind: User
    name: devops-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
echo "    [OK] devops-user (group: cluster-admins) → cluster-admin"
echo ""

# -----------------------------------------------------------------------------
# ClusterRoleBinding: cluster-viewers → cluster-viewer
# Пользователь: analyst-user
# Группа: cluster-viewers
# -----------------------------------------------------------------------------
echo ">>> Привязка: cluster-viewers → cluster-viewer"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-viewers-binding
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
  annotations:
    description: "Бизнес-аналитики и BI-аналитики: только просмотр ресурсов кластера"
subjects:
  - kind: Group
    name: cluster-viewers
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: analyst-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
echo "    [OK] analyst-user (group: cluster-viewers) → cluster-viewer"
echo ""

# -----------------------------------------------------------------------------
# ClusterRoleBinding: cluster-operators → cluster-operator
# Пользователь: ops-user
# Группа: cluster-operators
# -----------------------------------------------------------------------------
echo ">>> Привязка: cluster-operators → cluster-operator"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-operators-binding
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
  annotations:
    description: "Инженеры по эксплуатации: управление рабочими нагрузками"
subjects:
  - kind: Group
    name: cluster-operators
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: ops-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-operator
  apiGroup: rbac.authorization.k8s.io
EOF
echo "    [OK] ops-user (group: cluster-operators) → cluster-operator"
echo ""

# -----------------------------------------------------------------------------
# ClusterRoleBinding: security-auditors → security-auditor
# Пользователь: security-user
# Группа: security-auditors
# Привилегированная роль: доступ к секретам для аудита
# -----------------------------------------------------------------------------
echo ">>> Привязка: security-auditors → security-auditor (ПРИВИЛЕГИРОВАННАЯ)"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: security-auditors-binding
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
    rbac.propdevelopment.ru/privileged: "true"
  annotations:
    description: "Специалист по ИБ: аудит безопасности, просмотр секретов и политик"
subjects:
  - kind: Group
    name: security-auditors
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: security-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: security-auditor
  apiGroup: rbac.authorization.k8s.io
EOF
echo "    [OK] security-user (group: security-auditors) → security-auditor"
echo ""

# -----------------------------------------------------------------------------
# RoleBinding: developers → namespace-developer (только в namespace dev)
# Пользователь: dev-user
# Группа: developers
# Ограничен namespace propdevelopment-dev
# -----------------------------------------------------------------------------
echo ">>> Привязка: developers → namespace-developer (namespace: ${NAMESPACE_DEV})"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: namespace-developers-binding
  namespace: ${NAMESPACE_DEV}
  labels:
    app.kubernetes.io/managed-by: propdevelopment-rbac
  annotations:
    description: "Разработчики: управление приложениями в namespace разработки"
subjects:
  - kind: Group
    name: developers
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: dev-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: namespace-developer
  apiGroup: rbac.authorization.k8s.io
EOF
echo "    [OK] dev-user (group: developers) → namespace-developer (ns: ${NAMESPACE_DEV})"
echo ""

# -----------------------------------------------------------------------------
# Проверка привязок
# -----------------------------------------------------------------------------
echo "=== Проверка ClusterRoleBindings ==="
kubectl get clusterrolebindings \
  cluster-admins-binding \
  cluster-viewers-binding \
  cluster-operators-binding \
  security-auditors-binding \
  --no-headers 2>/dev/null | \
  awk '{printf "  %-40s → %s\n", $1, $3}'
echo ""

echo "=== Проверка RoleBindings в namespace ${NAMESPACE_DEV} ==="
kubectl get rolebindings \
  namespace-developers-binding \
  -n "${NAMESPACE_DEV}" \
  --no-headers 2>/dev/null | \
  awk -v ns="${NAMESPACE_DEV}" '{printf "  %-40s → %s (ns: %s)\n", $1, $3, ns}'
echo ""

# -----------------------------------------------------------------------------
# Проверка прав пользователей (auth can-i)
# -----------------------------------------------------------------------------
echo "=== Проверка прав доступа ==="
echo ""

echo "  [devops-user] Может создавать поды? (ожидается: yes)"
kubectl auth can-i create pods --as=devops-user 2>/dev/null || echo "    (требуется запущенный кластер)"

echo "  [analyst-user] Может просматривать поды? (ожидается: yes)"
kubectl auth can-i get pods --as=analyst-user 2>/dev/null || echo "    (требуется запущенный кластер)"

echo "  [analyst-user] Может просматривать секреты? (ожидается: no)"
kubectl auth can-i get secrets --as=analyst-user 2>/dev/null || echo "    (требуется запущенный кластер)"

echo "  [ops-user] Может создавать деплои? (ожидается: yes)"
kubectl auth can-i create deployments --as=ops-user 2>/dev/null || echo "    (требуется запущенный кластер)"

echo "  [ops-user] Может просматривать секреты? (ожидается: no)"
kubectl auth can-i get secrets --as=ops-user 2>/dev/null || echo "    (требуется запущенный кластер)"

echo "  [security-user] Может просматривать секреты? (ожидается: yes)"
kubectl auth can-i get secrets --as=security-user 2>/dev/null || echo "    (требуется запущенный кластер)"

echo "  [security-user] Может удалять секреты? (ожидается: no)"
kubectl auth can-i delete secrets --as=security-user 2>/dev/null || echo "    (требуется запущенный кластер)"

echo "  [dev-user] Может создавать поды в ${NAMESPACE_DEV}? (ожидается: yes)"
kubectl auth can-i create pods --as=dev-user -n "${NAMESPACE_DEV}" 2>/dev/null || echo "    (требуется запущенный кластер)"

echo "  [dev-user] Может создавать поды в kube-system? (ожидается: no)"
kubectl auth can-i create pods --as=dev-user -n kube-system 2>/dev/null || echo "    (требуется запущенный кластер)"

echo ""
echo "[DONE] Привязки ролей созданы успешно."
