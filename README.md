# GeoBlock SSH

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A lightweight Bash script to block SSH connection attempts from specific countries using GeoIP filtering with iptables.

![GeoBlock SSH Banner](https://via.placeholder.com/800x400?text=GeoBlock+SSH)

## 🔒 Features

- Block SSH connections from specific countries using their ISO country codes
- Easy installation with automatic dependency management
- Persists across system reboots via systemd service
- Uses efficient ipset for handling large IP ranges
- Simple command-line interface for managing blocked countries
- Regular GeoIP database updates
- Minimal impact on system performance

## 📋 Requirements

- Linux system with root access
- iptables firewall (comes pre-installed on most distributions)
- Systemd init system (most modern Linux distributions)

## 🚀 Installation

### Quick Install

1. Download the script:
   ```bash
   curl -O https://raw.githubusercontent.com/yourusername/geoblock-ssh/main/geoblock-ssh.sh
   ```

2. Make it executable:
   ```bash
   chmod +x geoblock-ssh.sh
   ```

3. Run the installation:
   ```bash
   sudo ./geoblock-ssh.sh install
   ```

The installation process:
- Installs required dependencies (iptables, ipset, curl, etc.)
- Downloads the latest GeoIP database
- Sets up a systemd service for persistence
- Creates necessary configuration directories

## 📘 Usage

### Blocking Countries

Block SSH connections from specific countries using their two-letter ISO country codes:

```bash
# Block a single country (e.g., China)
sudo ./geoblock-ssh.sh block CN

# Block multiple countries at once (e.g., Russia, North Korea, and Iran)
sudo ./geoblock-ssh.sh block RU KP IR
```

### List Blocked Countries

View currently blocked countries:

```bash
sudo ./geoblock-ssh.sh list
```

### Unblocking Countries

Remove countries from the block list:

```bash
# Unblock a single country
sudo ./geoblock-ssh.sh unblock CN

# Unblock multiple countries at once
sudo ./geoblock-ssh.sh unblock RU KP
```

### Checking Status

Check if the service is running and which countries are blocked:

```bash
sudo ./geoblock-ssh.sh status
```

### Help

Display the help message:

```bash
sudo ./geoblock-ssh.sh help
```

## 🔧 How It Works

GeoBlock SSH works by:

1. **Country IP Ranges**: Downloads a free GeoIP database that maps IP address ranges to countries
2. **ipset Management**: Creates efficient IP sets for each blocked country
3. **iptables Rules**: Sets up firewall rules to block SSH connections from the specified countries
4. **Systemd Integration**: Ensures that blocks persist across system reboots

The script creates a dedicated iptables chain called `GEOBLOCK-SSH` that contains all the blocking rules, keeping your firewall configuration clean and organized.

## ⚙️ Configuration

The default configuration should work for most users, but you can modify these variables in the script if needed:

- `SSH_PORT`: Change if your SSH server runs on a non-standard port (default: 22)
- `GEOIP_DIR`: Directory where GeoIP database and country lists are stored
- `BLOCK_LIST`: File containing the list of currently blocked countries

## 🔄 Updating

The GeoIP database is downloaded during installation. To update it to the latest version:

```bash
sudo ./geoblock-ssh.sh install
```

This will re-download the database without affecting your existing configuration.

## ❓ Troubleshooting

### Common Issues

**Script doesn't block countries after reboot**
- Check if the systemd service is active: `systemctl status geoblock-ssh.service`
- If inactive, try: `systemctl start geoblock-ssh.service`

**Country code not recognized**
- Ensure you're using the correct two-letter ISO country code
- Check if the GeoIP database includes that country: `grep -i "COUNTRY_NAME" /tmp/dbip-country-lite.csv`

**Performance impact concerns**
- The script uses ipset which is designed for efficient IP range matching
- Impact on SSH connection speed should be minimal

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📊 Country Codes Reference

Here are some common ISO country codes for reference:

| Country | Code |
|---------|------|
| China | CN |
| Russia | RU |
| North Korea | KP |
| Iran | IR |
| United States | US |
| India | IN |
| Brazil | BR |
| Germany | DE |
| United Kingdom | GB |
| Japan | JP |

For a complete list of country codes, see [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2#Officially_assigned_code_elements).

---

⭐ Consider starring this repository if you find it useful!

Created with ❤️ by [Your Name]
