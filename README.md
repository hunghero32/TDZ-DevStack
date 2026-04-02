<p align="center">
  <br/>
  <h1 align="center">TDZ DevStack</h1>
  <p align="center"><strong>A Modern, 100% Portable Development Environment for Windows</strong><br><em>(The Ultimate Laragon Alternative)</em></p>
</p>

## ✨ Features

- **🚀 100% Portable (USB-Ready):** Copy or move the `TDZ env` folder anywhere (another drive, another PC, or a USB stick). TDZ DevStack will automatically auto-patch all absolute paths on startup! No installation required.
- **🌐 Auto Virtual Hosts:** Create a folder `www/myproject` and instantly access it via `http://myproject.test`. No manual Apache/Hosts config needed.
- **🎨 Modern Web Dashboard:** Manage your entire stack, customize configurations, toggle PHP extensions, and view logs directly from `http://localhost:8080`.
- **🛠️ Laravel Ready:** Essential PHP extensions (`zip`, `sodium`, `pdo_sqlite`, `sqlite3`, `curl`, `mbstring`) and Composer are bundled and pre-enabled.
- **⚡ Smart Global Terminal Integrations:** Open any terminal from the DevStack and instantly use `php`, `composer`, `npm`, `node`, and `git` without polluting your Windows PATH.

---

## 🚀 Quick Start

1. **Launch:** Double-click `TDZ DevStack.cmd`
2. **Dashboard:** Your browser will automatically open `http://localhost:8080`
3. **Projects:** Drop your code into the `www/` folder
4. **Terminal:** Double-click `TDZ Terminal.cmd` (if available) or use the CLI commands.

---

## 💻 CLI Commands (`tdz.cmd`)

TDZ DevStack comes with a powerful Command Line Interface for quick operations:

```bash
# Service Management
tdz start [service]       # Start all or a specific service (apache, mysql, redis...)
tdz stop [service]        # Stop all or a specific service
tdz restart [service]     # Restart service
tdz status                # View running status and port info

# Runtime Switching
tdz use php 8.5           # Instantly switch PHP version
tdz use nodejs 24         # Instantly switch Node.js version

# Utilities
tdz dashboard             # Open the web dashboard
tdz terminal              # Open integrated terminal with fully injected PATHs
tdz ssl <domain>          # Generate local SSL certificate
tdz log [service]         # View logs
```

---

## 📂 Directory Structure

```text
TDZ env/
├── TDZ DevStack.cmd      # Main Launcher (Starts API & Services)
├── tdz.cmd               # Core CLI Tool
├── bin/                  # Portable Binaries 
│   ├── apache/           # -> Apache Server
│   ├── mysql/            # -> MySQL Database
│   ├── php/              # -> PHP Runtimes
│   ├── nodejs/           # -> Node.js & npm
│   ├── redis/            # -> Redis In-Memory DB
│   ├── composer/         # -> Composer Package Manager
│   └── git/              # -> Portable Git
├── data/                 # Database Storage (MySQL Data)
├── etc/                  # Configuration Files (Apache VirtualHosts, SSL)
├── usr/                  
│   ├── tdz.json          # Main DevStack Configuration
│   └── .tdz-root         # Internal path tracker for portability
├── www/                  # 🌐 Your Web Projects go here!
├── logs/                 # System and Service Logs
└── devstack-dashboard/   # Dashboard SPA Source Code
```

---

## ⚙️ Services & Default Ports

| Service   | Default Port | Notes |
|-----------|-------------|--------|
| **Dashboard** | `8080` | TDZ Control Panel |
| **Apache**    | `80` / `443`| Main Web Server |
| **MySQL**     | `3306`        | Default root password is empty `""` |
| **Redis**     | `6379`        | In-memory store |
| **Memcached** | `11211`       | Caching |
| **Mailpit**   | `8025` (UI)   | SMTP debugging (catch-all at `1025`) |

---

## 🔒 Security & Portability Notes

Unlike legacy environments that rely on Windows registries or hardcoded paths that break when moved:
1. **TDZ DevStack does NOT install hidden background services.** When you quit, everything shuts down cleanly.
2. **Move it anywhere:** You can zip the folder and send it to a colleague. When they run `TDZ DevStack.cmd`, an auto-repair sequence patches `httpd.conf` and `php.ini` to match their exact local directory.

---

*Built with TDZ Group ❤️ for rapid, hassle-free web development.*
