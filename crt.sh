#!/bin/bash
domain=$1
org=$(whois $domain | grep "Registrant Organization" | cut -d " " -f3,4,5,6,7)
certOrg=$(echo $org | sed "s/ /%20/g")
agent="Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.85 Safari/537.36"

curl -s -A $agent "https://crt.sh/?O=$domain&output=json" | jq -r ".[].common_name"
curl -s -A $agent "https://crt.sh/?O=$certOrg&output=json" | jq -r ".[].common_name" 
