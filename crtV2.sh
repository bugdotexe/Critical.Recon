#!/bin/bash
domain=$1
CleanResults() {
    sed 's/\\n/\n/g' | \
    sed 's/\*.//g' | \
    sed -r 's/([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4})//g' | \
    sort | uniq
}
response=$(curl -s "https://crt.sh?q=%.${domain}&output=json")
results=$(echo "$response" | jq -r ".[].common_name,.[].name_value" | CleanResults)
