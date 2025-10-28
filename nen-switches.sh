#!/bin/bash
#
# Populate Network Devices (Switches) into Illumio PCE from CSV
# Adds interactive prompt to select Network Enforcement Node (NEN)
#

# ======= CONFIGURATION =======
source .credentials
csv_file="network_switches.csv"
# =============================

# --- Step 1: Retrieve available Network Enforcement Nodes ---
echo ">>> Fetching available Network Enforcement Nodes..."
nen_list=$(curl -sk -X GET "https://${pce_url}/api/v2/orgs/${org_id}/network_enforcement_nodes" \
  -u "${ilo_api}:${ilo_secret}" | jq '[ .[] | {href,name} ]')

if [[ -z "$nen_list" || "$nen_list" == "[]" ]]; then
  echo "[ERROR] No Network Enforcement Nodes found in the PCE."
  exit 1
fi

echo "---------------------------------------------------------"
echo "Available Network Enforcement Nodes:"
mapfile -t nen_names < <(echo "$nen_list" | jq -r '.[].name')

for i in "${!nen_names[@]}"; do
  printf "  [%d] %s\n" "$((i+1))" "${nen_names[$i]}"
done
echo "---------------------------------------------------------"

# Auto-select if only one
if (( ${#nen_names[@]} == 1 )); then
  nen_choice=1
  echo "[INFO] Only one NEN found, auto-selecting: ${nen_names[0]}"
else
  read -p "Enter the number of the NEN you wish to use: " nen_choice
fi

# Validate selection
if ! [[ "$nen_choice" =~ ^[0-9]+$ ]] || ((nen_choice < 1 || nen_choice > ${#nen_names[@]})); then
  echo "[ERROR] Invalid selection. Exiting."
  exit 1
fi

# Index Results
nen_href=$(echo "$nen_list" | jq -r ".[$((nen_choice - 1))].href")

echo "[INFO] Selected NEN: ${nen_names[$((nen_choice-1))]}"
echo "[INFO] Using href: ${nen_href}"
echo

# --- Step 2: Fetch existing network devices ---
echo ">>> Fetching existing network devices..."
existing_devices=$(curl -sk -X GET "https://${pce_url}/api/v2/orgs/${org_id}/network_devices" \
  -u "${ilo_api}:${ilo_secret}" | jq -c '.[] | {href, name: .config.name}')

# --- Step 3: Process each switch from CSV ---
tail -n +2 "$csv_file" | while IFS=',' read -r name description manufacturer model ip_address
do
  echo "====================================================="
  echo "[PROCESS] Switch: ${name} (${ip_address})"

  # Check if switch already exists
  existing_href=$(echo "$existing_devices" | jq -r --arg n "$name" 'select(.name == $n) | .href')

  if [[ -n "$existing_href" ]]; then
    echo "[OK] Switch already exists in PCE: ${existing_href}"
    continue
  fi

  # Create new switch
  echo "[CREATE] Creating new switch ${name}..."

  response=$(curl -sk -X POST \
    "https://${pce_url}/api/v2${nen_href}/network_devices" \
    -u "${ilo_api}:${ilo_secret}" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "name": "${name}",
  "description": "${description}",
  "device_type": "switch",
  "manufacturer": "${manufacturer}",
  "model": "${model}",
  "ip_address": "${ip_address}"
}
EOF
  )

  # Validate API response
  if echo "$response" | jq -e 'has("href")' &>/dev/null; then
    new_href=$(echo "$response" | jq -r '.href')
    echo "[SUCCESS] Created ${name} -> ${new_href}"
  else
    echo "[FAIL] Failed to create ${name}"
    echo "Response: $response"
  fi

  echo "-----------------------------------------------"
done

echo ">>> All switches processed!"
