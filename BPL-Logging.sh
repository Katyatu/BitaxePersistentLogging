#!/bin/bash

bitaxeLocalIP=$(cat ./config.json | jq .bitaxeLocalIP | tr -d '"')
bitaxeName=$(cat ./config.json | jq .bitaxeName | tr -d '"')

# Graceful exit
handle_sigterm() {
  echo "Caught SIGTERM!"
  exit 0
}

# Trap SIGTERM
trap handle_sigterm SIGTERM

# Function to check dependencies
checkdeps() {
    command -v jq >/dev/null 2>&1 || { echo "Error: jq not installed"; exit 1; }
}

# Function to convert abbreviated number to full integer
convert_abbrev_number() {
    local input="$1"
    local number suffix multiplier

    # Check if input is empty
    if [ -z "$input" ]; then
        echo "Error: Empty input" >&2
        return 1
    fi

    # Extract numeric part and suffix using regex
    if [[ "$input" =~ ^([0-9]+(\.[0-9]+)?)([KMGTkmgt]?)$ ]]; then
        number="${BASH_REMATCH[1]}"
        suffix="${BASH_REMATCH[3]}"
    else
        echo "Error: Invalid format '$input'" >&2
        return 1
    fi

    # Set multiplier based on suffix
    case "${suffix^^}" in
        "") multiplier=1 ;;
        "K") multiplier=1000 ;;
        "M") multiplier=1000000 ;;
        "G") multiplier=1000000000 ;;
        "T") multiplier=1000000000000 ;;
        *)
            echo "Error: Unsupported suffix '$suffix'" >&2
            return 1
            ;;
    esac

    # Calculate result using bc, keeping decimal precision, then convert to integer
    result=$(echo "scale=0; $number * $multiplier / 1" | bc)
    echo "$result"
}

checkdeps

mkdir -p /tmp/BPL

echo "Uptime (s),Power (W),Core Voltage (mV),Input Voltage (mV),Current (mA),ASIC Temp (C),VR Temp (C),Hashrate (GH/s),Accepted Shares,Rejected Shares,Best Difficulty,Best Session Difficulty,Stratum Difficulty" > /tmp/BPL/BPL-$bitaxeName-Logging.csv

curl -X POST "$bitaxeLocalIP/api/system/restart";

sleep 5;

while true
do

  resp=$(curl -s -X GET "$bitaxeLocalIP/api/system/info")

  uptime=$(echo $resp | jq .uptimeSeconds)
  power=$(echo $resp | jq .power)
  inputVolt=$(echo $resp | jq .voltage)
  coreVolt=$(echo $resp | jq .coreVoltageActual)
  current=$(echo $resp | jq .current)
  temp=$(echo $resp | jq .temp)
  vrTemp=$(echo $resp | jq .vrTemp)
  hashrate=$(echo $resp | jq .hashRate)
  sharesAccepted=$(echo $resp | jq .sharesAccepted)
  sharesRejected=$(echo $resp | jq .sharesRejected)
  bestDiff=$(convert_abbrev_number $(echo $resp | jq .bestDiff | tr -d '"'))
  bestSessionDiff=$(convert_abbrev_number $(echo $resp | jq .bestSessionDiff | tr -d '"'))
  stratumDiff=$(convert_abbrev_number $(echo $resp | jq .stratumDiff | tr -d '"'))

  echo "$uptime,$power,$coreVolt,$inputVolt,$current,$temp,$vrTemp,$hashrate,$sharesAccepted,$sharesRejected,$bestDiff,$bestSessionDiff,$stratumDiff" >> /tmp/BPL/BPL-$bitaxeName-Logging.csv

  sleep 5

done
