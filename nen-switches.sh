#!/bin/bash
#
# Populate Network Devices (Switches) into Illumio PCE from CSV
# Adds interactive prompt to select Network Enforcement Node (NEN)
#

# ======= CONFIGURATION =======
source .credentials
csv_file="network_switches.csv"
# =============================

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# --- Step 1: Retrieve available Network Enforcement Nodes ---
echo -e "${CYAN}>>> Fetching available Network Enforcement Nodes...${RESET}"
nen_list=$(curl -sk -X GET "https://${pce_url}/api/v2/orgs/${org_id}/network_enforcement_nodes" \
  -u "${ilo_api}:${ilo_secret}" | jq '[ .[] | {href,name} ]')

if [[ -z "$nen_list" || "$nen_list" == "[]" ]]; then
  echo -e "${RED}[ERROR] No Network Enforcement Nodes found in the PCE.${RESET}"
  exit 1
fi

echo "---------------------------------------------------------"
echo -e "${BLUE}Available Network Enforcement Nodes:${RESET}"
mapfile -t nen_names < <(echo "$nen_list" | jq -r '.[].name')

for i in "${!nen_names[@]}"; do
  printf "  [%d] %s\n" "$((i+1))" "${nen_names[$i]}"
done
echo "---------------------------------------------------------"

# Auto-select if only one
if (( ${#nen_names[@]} == 1 )); then
  nen_choice=1
  echo -e "${YELLOW}[INFO] Only one NEN found, auto-selecting: ${nen_names[0]}${RESET}"
else
  read -p "Enter the number of the NEN you wish to use: " nen_choice
fi

# Validate selection
if ! [[ "$nen_choice" =~ ^[0-9]+$ ]] || ((nen_choice < 1 || nen_choice > ${#nen_names[@]})); then
  echo -e "${RED}[ERROR] Invalid selection. Exiting.${RESET}"
  exit 1
fi

nen_href=$(echo "$nen_list" | jq -r ".[$((nen_choice - 1))].href")

echo -e "${GREEN}[INFO] Selected NEN:${RESET} ${nen_names[$((nen_choice-1))]}"
echo -e "${GREEN}[INFO] Using href:${RESET} ${nen_href}"
echo

# --- Step 2: Fetch existing network devices once ---
echo -e "${CYAN}>>> Fetching existing network devices...${RESET}"
existing_devices=$(curl -sk -X GET "https://${pce_url}/api/v2/orgs/${org_id}/network_devices" \
  -u "${ilo_api}:${ilo_secret}" | jq -c '.[] | {href, name: .config.name}')

# --- Step 3: Process each switch from CSV ---
tail -n +2 "$csv_file" | while IFS=',' read -r name description manufacturer model ip_address
do
  echo "====================================================="
  echo -e "${BLUE}[PROCESS] Switch:${RESET} ${name} (${ip_address})"

  # Check if switch already exists
  existing_href=$(echo "$existing_devices" | jq -r --arg n "$name" 'select(.name == $n) | .href')

  if [[ -n "$existing_href" ]]; then
    echo -e "${GREEN}[OK] Switch already exists in PCE:${RESET} ${existing_href}"
    continue
  fi

  # Create new switch
  echo -e "${YELLOW}[CREATE] Creating new switch:${RESET} ${name}"

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
    echo -e "${GREEN}[SUCCESS] Created:${RESET} ${name} -> ${new_href}"
  else
    echo -e "${RED}[FAIL] Failed to create:${RESET} ${name}"
    echo "Response: $response"
  fi

  echo "-----------------------------------------------"
done

echo -e "${CYAN}>>> All switches processed!${RESET}"
