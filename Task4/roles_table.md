# Таблица ролей Kubernetes — PropDevelopment

## Организационная структура и группы пользователей

Согласно структуре компании PropDevelopment, выделены следующие группы пользователей кластера Kubernetes:

| Группа | Описание | Соответствие оргструктуре |
|--------|---------|--------------------------|
| `cluster-admins` | Привилегированные администраторы кластера | DevOps-инженеры |
| `cluster-viewers` | Только просмотр ресурсов кластера | Бизнес-аналитики, BI-аналитики |
| `cluster-operators` | Настройка и управление ресурсами кластера | Инженеры по эксплуатации |
| `security-auditors` | Аудит безопасности: просмотр секретов и политик | Специалист по ИБ |
| `developers` | Разработчики: деплой и управление приложениями в своём namespace | Разработчики продуктовых команд |

---

## Таблица ролей и полномочий

| Роль (Role/ClusterRole) | Группа пользователей | Ресурсы | Действия (verbs) | Область | Описание |
|------------------------|---------------------|---------|-----------------|---------|---------|
| `cluster-admin` (встроенная) | `cluster-admins` | `*` (все) | `*` (все) | Кластер | Полный доступ ко всем ресурсам кластера. Только для DevOps-инженеров. |
| `cluster-viewer` | `cluster-viewers` | `pods`, `services`, `deployments`, `replicasets`, `namespaces`, `nodes`, `configmaps`, `events` | `get`, `list`, `watch` | Кластер | Только чтение. Нет доступа к секретам. |
| `cluster-operator` | `cluster-operators` | `pods`, `services`, `deployments`, `replicasets`, `statefulsets`, `daemonsets`, `configmaps`, `ingresses`, `horizontalpodautoscalers` | `get`, `list`, `watch`, `create`, `update`, `patch`, `delete` | Кластер | Управление рабочими нагрузками без доступа к секретам и RBAC. |
| `security-auditor` | `security-auditors` | `secrets`, `roles`, `rolebindings`, `clusterroles`, `clusterrolebindings`, `serviceaccounts`, `networkpolicies`, `podsecuritypolicies` | `get`, `list`, `watch` | Кластер | Просмотр секретов и политик безопасности для аудита. Только чтение. |
| `namespace-developer` | `developers` | `pods`, `pods/log`, `pods/exec`, `services`, `deployments`, `replicasets`, `configmaps`, `jobs`, `cronjobs` | `get`, `list`, `watch`, `create`, `update`, `patch`, `delete` | Namespace | Управление приложениями в рамках своего namespace. Нет доступа к секретам и RBAC. |

---

## Пользователи и их роли

| Пользователь | Группа | Роль | Namespace |
|-------------|--------|------|-----------|
| `devops-user` | `cluster-admins` | `cluster-admin` | Весь кластер |
| `analyst-user` | `cluster-viewers` | `cluster-viewer` | Весь кластер |
| `ops-user` | `cluster-operators` | `cluster-operator` | Весь кластер |
| `security-user` | `security-auditors` | `security-auditor` | Весь кластер |
| `dev-user` | `developers` | `namespace-developer` | `propdevelopment-dev` |

---

## Обоснование ролевой модели

1. **`cluster-admins`** — DevOps-инженеры, которые управляют инфраструктурой. Получают встроенную роль `cluster-admin`. Группа строго ограничена.

2. **`cluster-viewers`** — Бизнес-аналитики и BI-аналитики, которым нужен мониторинг состояния кластера без права изменений. Нет доступа к секретам (ПДн, ключи API).

3. **`cluster-operators`** — Инженеры по эксплуатации, которые управляют деплоями и конфигурацией. Могут создавать/обновлять ресурсы, но не имеют доступа к секретам и RBAC.

4. **`security-auditors`** — Специалист по ИБ. Единственная роль с правом просмотра секретов (для аудита). Только чтение — не может изменять политики.

5. **`developers`** — Разработчики продуктовых команд. Ограничены своим namespace, не имеют доступа к секретам и не могут изменять RBAC.
