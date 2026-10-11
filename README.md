# Server Hardening & Automation Toolkit

Automated security hardening and deployment toolkit for **Ubuntu Server** and **Windows Server**. This project provides scripts to streamline secure server configuration, strengthen remote access controls, apply firewall policies, and automate essential security tasks.

## Repository Structure

```text
.
├── Ubuntu_Server_Security_Setup.sh
├── Windows_Server_Security_Setup.ps1
└── README.md
```

## 1. Ubuntu Server Security Setup

**Script:** `Ubuntu_Server_Security_Setup.sh`

Automates Ubuntu Server configuration and security hardening by applying network settings, firewall rules, brute-force protection, security updates, and application deployment.

### Key Features

- **Privilege Validation:** Verifies root privileges before executing administrative operations.
- **Network Configuration:** Detects network interfaces, gateways, subnet prefixes, and DNS settings.
- **Static IP Configuration:** Backs up existing Netplan configurations with timestamps and applies static network settings using `netplan try` with automatic rollback support.
- **Firewall Hardening:** Configures UFW with a default-deny incoming policy and restricts SSH access to a trusted source IP.
- **Brute-Force Protection:** Installs and configures Fail2ban to help mitigate repeated authentication attempts.
- **Automated Security Updates:** Configures `unattended-upgrades` to automate applicable security updates.
- **Odoo Deployment:** Automates Odoo installation and configuration with PostgreSQL.
- **Reverse Proxy & HTTPS:** Configures Nginx as a reverse proxy and supports HTTPS for local domains.
- **Execution Safety:** Requests user confirmation before applying changes.
- **Configuration Reporting:** Generates a final summary of applied settings and security controls.

### Installation & Usage

Run the following commands on the Ubuntu Server:

```bash
chmod +x Ubuntu_Server_Security_Setup.sh
sudo ./Ubuntu_Server_Security_Setup.sh
```

Review the requested settings and confirm the configuration before proceeding.

## 2. Windows Server Security Setup

**Script:** `Windows_Server_Security_Setup.ps1`

Automates Windows Server security baseline configuration, network settings, remote administration hardening, endpoint protection, and account security policies.

### Key Features

- **Dynamic Configuration:** Prompts the administrator for static IPv4 settings and trusted remote management IP addresses.
- **Network Configuration:** Configures static IPv4 addressing, gateway settings, and DNS servers.
- **OpenSSH Hardening:** Configures SSH access restrictions, including trusted-source firewall rules and authentication attempt limits.
- **RDP Security:** Enables Remote Desktop with Network Level Authentication (NLA) and restricts access to trusted sources.
- **Windows Firewall:** Enables firewall protection across all network profiles and applies remote access restrictions.
- **ICMP Restrictions:** Configures firewall rules to block inbound ICMP echo requests.
- **Account Lockout Policies:** Configures account lockout after five failed sign-in attempts for a 30-minute period.
- **User Account Control:** Applies the intended UAC security settings.
- **Microsoft Defender:** Enables real-time protection and updates security intelligence where supported.
- **Windows Updates:** Uses the `PSWindowsUpdate` PowerShell module to facilitate update management.
- **Error Handling & Reporting:** Uses `try/catch` error handling and generates a structured summary of applied security controls.

### Installation & Usage

1. Open **PowerShell as Administrator**.
2. Navigate to the directory containing the script.
3. Run the following commands:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
.\Windows_Server_Security_Setup.ps1
```

Review the requested configuration and verify the resulting security settings after execution.

## Security Considerations

- Run these scripts only on systems you own or are explicitly authorized to administer.
- Test configurations in a virtual machine or staging environment before deploying them to production.
- Back up existing configurations before making network or firewall changes.
- Verify trusted IP addresses and remote access rules before applying changes to avoid losing administrative connectivity.
- Review the generated reports and validate the resulting settings independently.

**Note:** Actual behavior depends on the server operating system version, installed components, permissions, and script implementation. Review the scripts before execution.

## Author

### Mohammed Fadhl Al-Moshtaher

Cybersecurity | Server Hardening | Security Automation
