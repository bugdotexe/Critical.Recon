#!/bin/bash

# Function to fetch and display undetected URLs for a domain
fetch_undetected_urls() {
  local domain=$1
  local api_key_index=$2
  local api_key

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
    echo ""
    return
  fi

  undetected_urls=$(echo "$response" | jq -r '(.subdomains + .domain_siblings)[], (.undetected_urls[] | .[0])')
  if [[ -z "$undetected_urls" ]]; then
  echo ""
  else
    echo "$undetected_urls" | anew orwa.urls
  fi
}

# Function to display a countdown
countdown() {
  local seconds=$1
  while [ $seconds -gt 0 ]; do
    echo
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

# Initialize variables for API key rotation
api_key_index=1
request_count=0

# Check if the argument is a file
if [ -f "$1" ]; then
  while IFS= read -r domain; do
    # Remove the scheme (http:// or https://) if present
    domain=$(echo "$domain" | sed 's|https\?://||')
    fetch_undetected_urls "$domain" $api_key_index
    countdown 20

    # Increment the request count and switch API key if needed
    request_count=$((request_count + 1))
    if [ $request_count -ge 5 ]; then
      request_count=0
      if [ $api_key_index -eq 1 ]; then
        api_key_index=2
      elif [ $api_key_index -eq 2 ]; then
        api_key_index=3
      else
        api_key_index=1
      fi
    fi
  done < "$1"
else
  # Argument is not a file, treat it as a single domain
  domain=$(echo "$1" | sed 's|https\?://||')
  fetch_undetected_urls "$domain" $api_key_index
fi
