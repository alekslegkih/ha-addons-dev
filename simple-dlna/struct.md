simple-dlna/
├── rootfs/
│   ├── etc/
│   │   └── s6-overlay/
│   │       └── s6-rc.d
│   │           └── simple-dlna/
│   │               ├── dependencies.d
│   │               │   └── base
│   │               ├── notification-fd
│   │               ├── type
│   │               ├── run
│   │               └── finish
│   └── usr/
│       ├── bin/
│       │   └── simple-dlna.sh
│       └── local/
│           └── simple-dlna/
│               ├── core/
│               │   ├── config.sh
│               │   ├── logger.sh
│               ├── storage/
│               │   ├── detect.sh
│               │   ├── mount.sh
│               │   └── checks.sh
│               └── notify/
│                   └── ha_notify.py
├── Dockerfile
└── config.yaml
