#!/bin/bash
#
# Populate network endpoints from CSV
#
# Steps:
# 1. Validate or create workloads (IPv4/IPv6)
# 2. Retrieve existing switch network_device href
# 3. Create network_endpoints linking switch ports to workloads
#

# ======= CONFIGURATION =======
source .credentials
csv_file="network_endpoints.csv"
# =============================

# ======= COLOR DEFINITIONS =======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'
# =================================

# --- Functions ---

get_workload_href() {
  local workload="$1"
  local ipv4="$2"
  local ipv6="$3"
  local json href

  json=$(curl -sk -X GET "https://${pce_url}/api/v2/orgs/${org_id}/workloads" \
    -u "${ilo_api}:${ilo_secret}" | jq -c '.[] | {href,hostname,interfaces}')

  href=$(echo "$json" | jq -r \
    --arg w "$workload" --arg v4 "$ipv4" --arg v6 "$ipv6" \
    'select(.hostname == $w and (.interfaces[].address == $v4 or .interfaces[].address == $v6)) | .href' | head -n1)

  # If not found, create workload
  if [[ -z "$href" || "$href" == "null" ]]; then
    echo -e "${YELLOW}[INFO] Workload ${workload} not found — creating...${RESET}" >&2

    if [[ -n "$ipv4" && -n "$ipv6" ]]; then
      curl -sk -X POST "https://${pce_url}/api/v2/orgs/${org_id}/workloads" \
        -u "${ilo_api}:${ilo_secret}" \
        -H "Content-Type: application/json" \
        -d @- >/dev/null 2>&1 <<EOF
{
  "hostname": "${workload}",
  "interfaces": [
    { "name": "umwl_v4", "address": "${ipv4}" },
    { "name": "umwl_v6", "address": "${ipv6}" }
  ]
}
EOF
    elif [[ -n "$ipv4" ]]; then
      curl -sk -X POST "https://${pce_url}/api/v2/orgs/${org_id}/workloads" \
        -u "${ilo_api}:${ilo_secret}" \
        -H "Content-Type: application/json" \
        -d @- >/dev/null 2>&1 <<EOF
{
  "hostname": "${workload}",
  "interfaces": [
    { "name": "umwl", "address": "${ipv4}" }
  ]
}
EOF
    elif [[ -n "$ipv6" ]]; then
      curl -sk -X POST "https://${pce_url}/api/v2/orgs/${org_id}/workloads" \
        -u "${ilo_api}:${ilo_secret}" \
        -H "Content-Type: application/json" \
        -d @- >/dev/null 2>&1 <<EOF
{
  "hostname": "${workload}",
  "interfaces": [
    { "name": "umwl", "address": "${ipv6}" }
  ]
}
EOF
    fi

    # Re-fetch workload href
    sleep 1
    href=$(curl -sk -X GET "https://${pce_url}/api/v2/orgs/${org_id}/workloads" \
      -u "${ilo_api}:${ilo_secret}" | jq -r \
      --arg w "$workload" --arg v4 "$ipv4" --arg v6 "$ipv6" '
      .[] | select(.hostname == $w or (.interfaces[].address == $v4 or .interfaces[].address == $v6)) | .href' | head -n1)
  fi

  echo "$href"
}

get_switch_href() {
  local switch_name="$1"
  curl -sk -X GET "https://${pce_url}/api/v2/orgs/${org_id}/network_devices" \
    -u "${ilo_api}:${ilo_secret}" | jq -r \
    --arg s "$switch_name" '.[] | select(.config.name == $s) | .href' | head -n1
}

create_network_endpoint() {
  local nd_uuid="$1"
  local interface="$2"
  local workload_href="$3"
  local ifIndex="$4"

  if [[ -z "$workload_href" || "$workload_href" == "null" ]]; then
    echo -e "${RED}[ERROR] Invalid workload href for ${interface}. Skipping.${RESET}" >&2
    return
  fi

  echo -e "${CYAN}[ACTION] Creating endpoint ${interface} (ifIndex=${ifIndex}) on ${nd_uuid} for ${workload_href}${RESET}"

  response=$(curl -sk -X POST "https://${pce_url}/api/v2${nd_uuid}/network_endpoints" \
    -u "${ilo_api}:${ilo_secret}" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "config": {
    "endpoint_type": "switch_port",
    "name": "${interface}",
    "traffic_flow_id": "${ifIndex}",
    "workload_discovery": true
  },
  "workloads": [
    { "href": "${workload_href}" }
  ]
}
EOF
  )
  
  if echo "$response" | jq -e 'has("href")' &>/dev/null; then
    echo -e "${GREEN}[OK] Created endpoint ${interface}${RESET}"
  else
    echo -e "${RED}[ERROR] Failed to create endpoint ${interface}${RESET}"
    echo "Response: $response"
  fi

  echo
}

# --- Main Loop ---

echo -e "${CYAN}>>> Starting network endpoint automation...${RESET}"
tail -n +2 "$csv_file" | while IFS=',' read -r switch_name interface ifIndex workload workload_ipv4 workload_ipv6
do
  echo "====================================================="
  echo -e "${BLUE}[PROCESS] ${switch_name} -> ${interface} -> ${workload}${RESET}"

  umwl_href=$(get_workload_href "$workload" "$workload_ipv4" "$workload_ipv6")
  if [[ -z "$umwl_href" ]]; then
    echo -e "${RED}[ERROR] Failed to retrieve workload href for ${workload}${RESET}"
    continue
  fi

  nd_uuid=$(get_switch_href "$switch_name")
  if [[ -z "$nd_uuid" ]]; then
    echo -e "${RED}[ERROR] Switch ${switch_name} not found in PCE${RESET}"
    continue
  fi

  create_network_endpoint "$nd_uuid" "$interface" "$umwl_href" "$ifIndex"
  echo -e "${GREEN}[OK] Completed ${interface} for ${workload}${RESET}"
done

echo -e "${CYAN}>>> All rows processed!${RESET}"
