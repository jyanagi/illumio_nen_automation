# Illumio Network Automation Scripts

These shell scripts automate the creation of **Network Devices (i.e., Switches)** and **Network Endpoints (Switch Ports + Workloads)** within an **Illumio Policy Compute Engine (PCE)** environment using Illumio REST API to support **Network Enforcement Node** deployments.

---

## ⚙️ Overview

This repository includes two primary scripts:

| Script | Purpose |
|---------|----------|
| `nen-switches.sh` | Imports network switches (Network Devices) from a CSV file and registers them in the Illumio PCE. |
| `nen-endpoints.sh` | Creates unmanaged workloads (if not already present) and links them to switch ports as **Network Endpoints**. |

Each script uses the Illumio REST API and `jq` for JSON parsing.
---
## 🧩 1. Clone the Repository
```bash
git clone https://github.com/jyanagi/illumio-nen-automation.git
cd illumio-nen-automation
```
---

## 🔐 2. Configure Your PCE Credentials

Update the .credentials file with your Illumio PCE connection details:

```bash
# .credentials
pce_url="your.pce.domain:8443"
org_id="org #"
ilo_api="api_username_or_key"
ilo_secret="api_secret_or_token"
```

---

## 🧾 3. Populate the CSV Files

network_switches.csv

Define the switches you want to register in Illumio.

Example:

```csv
name,description,manufacturer,model,ip_address
API_CISCO_SW_01,Core switch for lab,Cisco,9000,172.31.255.1
API_CISCO_SW_02,Distribution switch,Cisco,9000,172.31.255.2
```

network_endpoints.csv

Define switch interfaces and workloads that should be linked as network endpoints.

Example:

```csv
switch_name,interface,ifIndex,workload,workload_ipv4,workload_ipv6
API_CISCO_SW_01,GigabitEthernet1/0/11,11,umwl-cisco-iot-11,192.168.234.11,2001::c:11
API_CISCO_SW_01,GigabitEthernet1/0/12,12,umwl-cisco-iot-12,192.168.234.12,2001::c:12
API_CISCO_SW_02,GigabitEthernet1/0/11,11,umwl-cisco-iot-13,192.168.234.13,2001::c:13
```

---

## 🔧 4. Make Scripts Executable

Before running the scripts, give them execute permissions:

```bash
chmod +x nen-switches.sh
chmod +x nen-endpoints.sh
```

---

## 🚀 5. Run the Scripts in Order

### Step 1 — Register Network Switches

This will read network_switches.csv and create the defined switches (Network Devices) inside the Illumio PCE.

```bash
./nen-switches.sh
```

Example Output:
```
>>> Fetching available Network Enforcement Nodes...
---------------------------------------------------------
Available Network Enforcement Nodes:
  [1] Illumio Network Enforcement Node - nen-01.de.mo
  [2] Illumio Network Enforcement Node - nen-02.de.mo
---------------------------------------------------------
Enter the number of the NEN you wish to use: 2
[INFO] Selected NEN: Illumio Network Enforcement Node - nen-02.de.mo
[INFO] Using href: /orgs/2/network_enforcement_nodes/434c3bca-1d2b-4a84-9498-c28afc1eb0a3

>>> Fetching existing network devices...
```
### Step 2 — Register Network Endpoints

This script uses network_endpoints.csv to:
1.	Validate or create unmanaged workloads in the PCE.
2.	Link each workload to the corresponding switch port as a network endpoint.
```bash
./nen-endpoints.sh
```
Example Output:
```
>>> Starting network endpoint automation...
=====================================================
[PROCESS] API_CISCO_SW_01 -> GigabitEthernet1/0/11 -> umwl-cisco-iot-11
[INFO] Workload umwl-cisco-iot-11 not found — creating...
[ACTION] Creating endpoint GigabitEthernet1/0/11 (ifIndex=11) on /orgs/2/network_devices/... for /orgs/2/workloads/6ebeede9-9fdc-4a66-9071-0a30df210593
[OK] Created endpoint GigabitEthernet1/0/11
>>> All rows processed!
```
---
## 🧠 What These Scripts Do

| Script | Functionality |
|---------|----------|
| `nen-switches.sh` | Reads network_switches.csv, interacts with the Illumio API to create or verify switches (Network Devices) and assigns them to the selected Network Enforcement Node (NEN). |
| `nen-endpoints.sh` | Reads network_endpoints.csv, creates unmanaged workloads (if missing), retrieves switch and workload href references, and then POSTs them to create corresponding network_endpoints. |

---
## ✅ Requirements

These scripts depend on:
*	bash
*	curl
*	jq (for JSON parsing)
*	Access to an Illumio PCE API endpoint

### Install jq (if missing):

**RHEL / CentOS / Fedora**
```bash
sudo dnf install curl jq -y
```
**Ubuntu / Debian**
```bash
sudo apt install curl jq -y
```
---
## 🧩 Example Workflow Summary
```bash
# Clone repository
git clone https://github.com/jyanagi/illumio-nen-automation.git
cd illumio-nen-automation

# Configure credentials
nano .credentials

# Edit CSVs
nano network_switches.csv
nano network_endpoints.csv

# Make executable
chmod +x nen-switches.sh nen-endpoints.sh

# Run scripts
./nen-switches.sh
./nen-endpoints.sh
```
---
## 🛡️ Notes

Always verify your API credentials before execution.

Use test or staging PCEs before running in production.

---
## 💡 Troubleshooting
| Issue | Possible Cause | Solution |
| :---- | :------------- | :------- |
| message body does not match declared format | Malformed JSON (e.g., bad workload href) | Ensure workloads are created properly and script output shows valid /orgs/2/workloads/... hrefs |
| Switch not found in PCE | Switch name mismatch between CSV and PCE | Check the exact switch name in Illumio |
| jq: command not found | Missing dependency | Install jq (see above) |
| Workloads duplicated | CSV contains repeated hostnames or IPs | Remove duplicatges from network_endpoints.csv |






