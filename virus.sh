#!/bin/bash

fetch_domain_data() {
  local domain=$1
  local api_key_index=$2
  local api_key

  # Select API key based on index
  if [ $api_key_index -eq 1 ]; then
    api_key="9fc7f01403ba4de38f1aa345964d3ed1d0e9f43ee46f831169f602c1d0524900"
  elif [ $api_key_index -eq 2 ]; then
    api_key="6a1f07c7f9a912d59f06d0f4d30bc1d3aaa78ded215eb91d1b67568b5113dcf6"
  else
    api_key="cf72564720f2bb4262f8ccab471e634a1aaf4f405c203c327b7f8ad7736e89be"
  fi

  local URL="https://www.virustotal.com/vtapi/v2/domain/report?apikey=$api_key&domain=$domain"

   response=$(curl -s "$URL")
  if [[ $? -ne 0 ]]; then
    echo -e "\033[1;31m[!] Failed to fetch data for $domain\033[0m"
    return 1
  fi

   verbose_msg=$(echo "$response" | jq -r '.verbose_msg')
  if [[ "$verbose_msg" != "Domain found in dataset" ]]; then
    echo -e "\033[1;33m[!] Domain not found in VirusTotal dataset: $domain\033[0m"
    return 1
  fi

   echo -e "\033[1;32m[+] Processing $domain\033[0m"
  ips=$(echo "$response" | jq -r '.resolutions[].ip_address' | sort -u)
  if [[ -n "$ips" ]]; then
    echo -e "\033[1;36mIP Addresses:\033[0m"
    echo "$ips"
    echo "$ips" | anew virustotal.ips >/dev/null
  fi

  
  detected_urls=$(echo "$response" | jq -r '.detected_urls[].url?')
  undetected_urls=$(echo "$response" | jq -r '.undetected_urls[]? | .[0]')
  all_urls=$(echo -e "$detected_urls\n$undetected_urls" | sort -u)

  if [[ -n "$all_urls" ]]; then
    echo -e "\n\033[1;36mURLs:\033[0m"
    echo "$all_urls"
    echo "$all_urls" | anew virustotal.urls >/dev/null
  fi

   subdomains=$(echo "$response" | jq -r '.subdomains[]?' | sort -u)
  if [[ -n "$subdomains" ]]; then
    echo -e "\n\033[1;36mSubdomains:\033[0m"
    echo "$subdomains"
    echo "$subdomains" | anew virustotal.subdomains >/dev/null
  fi

    siblings=$(echo "$response" | jq -r '.domain_siblings[]?' | sort -u)
  if [[ -n "$siblings" ]]; then
    echo -e "\n\033[1;36mDomain Siblings:\033[0m"
    echo "$siblings"
    echo "$siblings" | anew virustotal.siblings >/dev/null
  fi

    echo -e "\n\033[1;35mSummary for $domain:\033[0m"
  echo "IPs:        $(echo "$ips" | wc -l)"
  echo "URLs:       $(echo "$all_urls" | wc -l)"
  echo "Subdomains: $(echo "$subdomains" | wc -l)"
  echo "Siblings:   $(echo "$siblings" | wc -l)"

  return 0
}
countdown() {
  local seconds=$1
  while [ $seconds -gt 0 ]; do
    echo -ne "\033[1;34mWaiting: $seconds seconds...\033[0m\r"
    sleep 1
    : $((seconds--))
  done
  echo -ne "\033[0K"  # Clear the countdown line
}

# Check if an argument is provided
if [ -z "$1" ]; then
  echo -e "\033[1;31mUsage: $0 <domain or file_with_domains>\033[0m"
  exit 1
fi
api_key_index=1
request_count=0

if [ -f "$1" ]; then
  total_domains=$(wc -l < "$1")
  current_domain=1

  while IFS= read -r domain; do
    domain=$(echo "$domain" | sed 's|https\?://||')

    echo -e "\n\033[1;33m[+] Processing domain $current_domain of $total_domains\033[0m"
    fetch_domain_data "$domain" $api_key_index

   
    request_count=$((request_count + 1))
    if [ $request_count -ge 5 ]; then
      request_count=0
      api_key_index=$((api_key_index % 3 + 1))
      echo -e "\033[1;35m[•] Rotating to API key $api_key_index\033[0m"
    fi

    current_domain=$((current_domain + 1))
    countdown 20
  done < "$1"
else
    domain=$(echo "$1" | sed 's|https\?://||')
  fetch_domain_data "$domain" $api_key_index
fi

echo -e "\n\033[1;32m[+] Processing complete!\033[0m"
echo -e "\033[1;35mFinal Results Summary:\033[0m"
echo "IPs:        $(wc -l < virustotal.ips 2>/dev/null || echo 0)"
echo "URLs:       $(wc -l < virustotal.urls 2>/dev/null || echo 0)"
echo "Subdomains: $(wc -l < virustotal.subdomains 2>/dev/null || echo 0)"
echo "Siblings:   $(wc -l < virustotal.siblings 2>/dev/null || echo 0)"
