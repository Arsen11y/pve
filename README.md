# DE 09.02.06 Proxmox Remote Runner

Формат под GitHub: запуск с Proxmox напрямую из raw-файлов GitHub без clone/unzip папки.

## Что это решает

Раньше надо было скачивать архив/папку на Proxmox. Теперь достаточно одной команды `curl | bash`.

Подходит для тренировочного стенда, где ВМ управляются через Proxmox и внутри установлен `qemu-guest-agent`.

## Куда положить в репозитории

Папку `proxmox-remote/` положи в корень GitHub-репозитория, например:

```text
repo/
├── README.md
└── proxmox-remote/
    ├── run.sh
    ├── inventory.example.env
    └── scripts/
```

## Настройка raw URL

Замени в командах:

```text
OWNER/REPO/main
```

на свой путь, например:

```text
Arsen11y/de-09-02-06-trainer/dev
```

Тогда raw URL будет:

```bash
export DE_RAW_URL="https://raw.githubusercontent.com/Arsen11y/de-09-02-06-trainer/dev/proxmox-remote"
```

## Первый запуск на Proxmox

```bash
export DE_RAW_URL="https://raw.githubusercontent.com/OWNER/REPO/main/proxmox-remote"

curl -fsSL "$DE_RAW_URL/inventory.example.env" > /root/de-inventory.env
nano /root/de-inventory.env

curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- check
```

## Запуск отдельных узлов

```bash
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run isp
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run hq-rtr
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run br-rtr
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run hq-srv
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run br-srv
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run hq-cli
```

## Запуск модуля 1 подряд

```bash
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run module1
```

## Проверки

```bash
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- ifaces hq-rtr
curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- status hq-rtr
```

## Важные замечания

- На Proxmox запускать от root.
- В каждой ВМ должен работать `qemu-guest-agent`.
- VMID и интерфейсы задаются в `/root/de-inventory.env`.
- HQ-RTR по текущему исправлению использует `enp7s1/enp7s2`, а не `ens18/ens19`.
- Пакет `vlan` не устанавливается, потому что в ALT он может отсутствовать.
- Модуль 2 не запускается целиком вслепую: RAID/Docker/Samba требуют отдельной проверки.
