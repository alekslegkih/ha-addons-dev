apcupsd-addon/
├── config.yaml
├── Dockerfile
├── apparmor.txt
├── icon.png
├── logo.png
├── rootfs/
│   ├── etc/
│   │   ├── apcupsd/
│   │   │   ├── doshutdown
│   │   │   └── apcupsd.conf 
│   │   └── s6-overlay/
│   │       └── s6-rc.d/
│   │           ├── 00-init/
│   │           │   ├── type
│   │           │   ├── up
│   │           │   └── dependencies.d/
│   │           │       └── base
│   │           │
│   │           ├── 10-apcupsd/
│   │           │   ├── type
│   │           │   ├── run
│   │           │   ├── finish
│   │           │   └── dependencies.d/
│   │           │       └── 00-init
│   │           │
│   │           └── user/
│   │               └── contents.d/
│   │                   ├── 00-init
│   │                   └── 10-apcupsd
│   │
│   └── usr/
│       └── bin/
│           ├── apcupsd_init
│           └── apcupsd_run
│
└── translations/
    ├── en.yaml
    └── ru.yaml