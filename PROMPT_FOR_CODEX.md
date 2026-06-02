# Промт для Codex

Переделай текущую базу автозапуска команд ДЭ под GitHub remote-runner.

Требования:
1. В репозитории должна быть папка `proxmox-remote/`.
2. Пользователь запускает команды на Proxmox без `git clone` и без скачивания архива:
   ```bash
   export DE_RAW_URL="https://raw.githubusercontent.com/OWNER/REPO/main/proxmox-remote"
   curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- check
   ```
3. `run.sh` должен подтягивать нужные скрипты из GitHub raw во временную папку `/tmp/de-remote-runner`.
4. Постоянный файл допускается только один: `/root/de-inventory.env`, где лежат VMID и интерфейсы.
5. Все VMID и интерфейсы брать из inventory, не хардкодить в guest-скриптах.
6. Запуск внутрь ВМ делать через `qm guest exec <VMID> -- bash -s`.
7. Должны быть команды:
   - `check`
   - `print-inventory`
   - `ifaces <target>`
   - `status <target>`
   - `run <target>`
   - `run module1`
8. Цели: `isp`, `hq-rtr`, `br-rtr`, `hq-srv`, `br-srv`, `hq-cli`.
9. Учесть исправления:
   - На HQ-RTR интерфейсы могут быть `enp7s1/enp7s2`.
   - Не ставить пакет `vlan`.
   - Перед записью sudoers делать `mkdir -p /etc/sudoers.d`.
   - Перед banner делать `mkdir -p /etc/ssh`.
10. Модуль 2 не запускать одной кнопкой полностью, пока нет защитных проверок дисков, ISO и Docker-образов.
11. Не делать git commit/push без отдельной команды.

После правок покажи список файлов, команды проверки и возможные риски.
