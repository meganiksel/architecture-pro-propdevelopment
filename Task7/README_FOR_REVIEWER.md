# Task 7: Политики безопасности подов (Pod Security)

## Описание задания

Настройка политик безопасности для Kubernetes-кластера PropDevelopment с использованием:
- **Pod Security Admission (PSA)** — встроенный механизм Kubernetes (v1.25+)
- **OPA Gatekeeper** — расширенные политики через CRD
- **Kubernetes Audit Policy** — аудит событий безопасности

---

## Структура файлов

```
Task7/
├── 01-create-namespace.yaml              # Namespace с метками PSA (restricted)
├── audit-policy.yaml                     # Политика аудита Kubernetes
├── insecure-manifests/                   # Небезопасные поды (для демонстрации блокировки)
│   ├── 01-privileged-pod.yaml            # Pod с privileged: true
│   ├── 02-hostpath-pod.yaml              # Pod с монтированием hostPath
│   └── 03-root-user-pod.yaml             # Pod запущенный от root (uid=0)
├── secure-manifests/                     # Безопасные поды (соответствуют restricted)
│   ├── 01-secure.yaml                    # Исправленный privileged → non-privileged
│   ├── 02-secure.yaml                    # Исправленный hostPath → emptyDir
│   └── 03-secure.yaml                    # Исправленный root → runAsNonRoot
├── gatekeeper/
│   ├── constraint-templates/             # Шаблоны ограничений OPA (Rego)
│   │   ├── privileged.yaml               # ConstraintTemplate: запрет privileged
│   │   ├── hostpath.yaml                 # ConstraintTemplate: запрет hostPath
│   │   └── runasnonroot.yaml             # ConstraintTemplate: обязательный non-root
│   └── constraints/                      # Экземпляры ограничений
│       ├── privileged.yaml               # Constraint: применить к namespace propdevelopment
│       ├── hostpath.yaml                 # Constraint: применить к namespace propdevelopment
│       └── runasnonroot.yaml             # Constraint: применить к namespace propdevelopment
└── verify/
    ├── verify-admission.sh               # Проверка блокировки небезопасных подов
    └── validate-security.sh              # Валидация конфигурации безопасности
```

---

## Предварительные требования

- Kubernetes кластер v1.25+
- `kubectl` настроен и подключён к кластеру
- OPA Gatekeeper установлен в кластере
- Права администратора кластера

### Установка OPA Gatekeeper (если не установлен)

```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.14.0/deploy/gatekeeper.yaml
```

Дождаться готовности:
```bash
kubectl wait --for=condition=Ready pods --all -n gatekeeper-system --timeout=120s
```

---

## Порядок применения

### Шаг 1: Создать namespace с политиками PSA

```bash
kubectl apply -f 01-create-namespace.yaml
```

Проверить метки namespace:
```bash
kubectl get namespace propdevelopment --show-labels
```

Ожидаемый результат:
```
NAME              STATUS   AGE   LABELS
propdevelopment   Active   ...   pod-security.kubernetes.io/enforce=restricted,...
```

### Шаг 2: Применить OPA Gatekeeper ConstraintTemplates

```bash
kubectl apply -f gatekeeper/constraint-templates/privileged.yaml
kubectl apply -f gatekeeper/constraint-templates/hostpath.yaml
kubectl apply -f gatekeeper/constraint-templates/runasnonroot.yaml
```

Дождаться создания CRD:
```bash
kubectl wait --for=condition=Established crd/k8spspprivilegedcontainer.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8spspallowedrepos.constraints.gatekeeper.sh --timeout=60s
```

### Шаг 3: Применить Constraints

```bash
kubectl apply -f gatekeeper/constraints/privileged.yaml
kubectl apply -f gatekeeper/constraints/hostpath.yaml
kubectl apply -f gatekeeper/constraints/runasnonroot.yaml
```

### Шаг 4: Настроить Audit Policy (опционально, для kube-apiserver)

Файл [`audit-policy.yaml`](audit-policy.yaml) необходимо разместить на control-plane ноде и указать в конфигурации kube-apiserver:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit.log
    - --audit-log-maxage=30
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
```

---

## Проверка работы политик

### Тест 1: Небезопасные поды должны быть ЗАБЛОКИРОВАНЫ

```bash
# Попытка создать privileged pod — должна быть отклонена
kubectl apply -f insecure-manifests/01-privileged-pod.yaml
# Ожидаемый результат: Error from server (Forbidden): ...

# Попытка создать pod с hostPath — должна быть отклонена
kubectl apply -f insecure-manifests/02-hostpath-pod.yaml
# Ожидаемый результат: Error from server (Forbidden): ...

# Попытка создать pod от root — должна быть отклонена
kubectl apply -f insecure-manifests/03-root-user-pod.yaml
# Ожидаемый результат: Error from server (Forbidden): ...
```

### Тест 2: Безопасные поды должны быть РАЗРЕШЕНЫ

```bash
# Безопасный pod без privileged
kubectl apply -f secure-manifests/01-secure.yaml
# Ожидаемый результат: pod/secure-pod-1 created

# Безопасный pod с emptyDir вместо hostPath
kubectl apply -f secure-manifests/02-secure.yaml
# Ожидаемый результат: pod/secure-pod-2 created

# Безопасный pod с runAsNonRoot
kubectl apply -f secure-manifests/03-secure.yaml
# Ожидаемый результат: pod/secure-pod-3 created
```

### Тест 3: Автоматическая проверка

```bash
# Запустить скрипт проверки admission
chmod +x verify/verify-admission.sh
./verify/verify-admission.sh

# Запустить полную валидацию безопасности
chmod +x verify/validate-security.sh
./verify/validate-security.sh
```

---

## Описание политик безопасности

### Pod Security Admission (PSA)

Namespace `propdevelopment` настроен с уровнем **`restricted`** — наиболее строгий уровень:

| Метка | Значение | Описание |
|-------|----------|----------|
| `pod-security.kubernetes.io/enforce` | `restricted` | Блокировать нарушения |
| `pod-security.kubernetes.io/audit` | `restricted` | Логировать нарушения |
| `pod-security.kubernetes.io/warn` | `restricted` | Предупреждать о нарушениях |

Уровень `restricted` запрещает:
- Запуск от root (`runAsNonRoot: true` обязателен)
- Privileged контейнеры
- Монтирование hostPath
- Повышение привилегий (`allowPrivilegeEscalation: false`)
- Небезопасные capabilities (только `NET_BIND_SERVICE` разрешён)
- Небезопасные seccomp профили

### OPA Gatekeeper Constraints

| Constraint | Тип нарушения | Действие |
|------------|---------------|----------|
| `no-privileged-containers` | `privileged: true` | `deny` |
| `no-hostpath-volumes` | `hostPath` volume | `deny` |
| `require-run-as-non-root` | `runAsUser: 0` или отсутствие `runAsNonRoot` | `deny` |

### Audit Policy

Политика аудита настроена для записи:
- **RequestResponse** — для операций с секретами, RBAC, Pod Security
- **Request** — для операций с подами, деплойментами
- **Metadata** — для остальных ресурсов
- **None** — для системных запросов (health checks, metrics)

---

## Соответствие требованиям безопасности

### 152-ФЗ (Персональные данные)
- ✅ Изоляция namespace с персональными данными
- ✅ Запрет доступа к хост-системе через hostPath
- ✅ Аудит всех операций с данными

### ISO/IEC 27001
- ✅ Принцип минимальных привилегий (non-root, no capabilities)
- ✅ Защита от эскалации привилегий
- ✅ Логирование событий безопасности

### CIS Kubernetes Benchmark
- ✅ 5.2.1 — Запрет privileged контейнеров
- ✅ 5.2.2 — Запрет hostPID
- ✅ 5.2.3 — Запрет hostIPC
- ✅ 5.2.4 — Запрет hostNetwork
- ✅ 5.2.6 — Запрет root контейнеров
- ✅ 5.2.8 — Запрет hostPath

---

## Очистка ресурсов

```bash
# Удалить безопасные поды
kubectl delete -f secure-manifests/

# Удалить Constraints
kubectl delete -f gatekeeper/constraints/

# Удалить ConstraintTemplates
kubectl delete -f gatekeeper/constraint-templates/

# Удалить namespace
kubectl delete namespace propdevelopment
```

---

## Известные ограничения

1. **OPA Gatekeeper** требует отдельной установки — не входит в стандартный Kubernetes
2. **PSA** работает только с Kubernetes v1.25+ (в более ранних версиях использовался PodSecurityPolicy)
3. **Audit Policy** требует доступа к control-plane ноде для настройки kube-apiserver
4. Некоторые легитимные системные поды (например, CNI плагины) могут требовать исключений из политик

---

## Контакты

Архитектор безопасности: команда PropDevelopment Security  
Дата создания: 2024  
Версия: 1.0
