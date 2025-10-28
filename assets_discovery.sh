#!/bin/bash

set -euo pipefail

RED="\e[31m"
RESET="\e[0m"
GREEN="\e[32m"
notice() { printf '\e[1;34m[INFO]\e[0m %s\n' "$*"; }
warn()   { printf '\e[1;33m[WARN]\e[0m %s\n' "$*"; }
err()    { printf '\e[1;31m[ERROR]\e[0m %s\n' "$*"; }

BANNER() {
echo -e "[+] World \e[31mOFF\e[0m,Terminal \e[32mON \e[0m"
echo -e " █████                             █████           █████
░░███                             ░░███           ░░███
 ░███████  █████ ████  ███████  ███████   ██████  ███████    ██████  █████ █████  ██████
 ░███░░███░░███ ░███  ███░░███ ███░░███  ███░░███░░░███░    ███░░███░░███ ░░███  ███░░███
 ░███ ░███ ░███ ░███ ░███ ░███░███ ░███ ░███ ░███  ░███    ░███████  ░░░█████░  ░███████
 ░███ ░███ ░███ ░███ ░███ ░███░███ ░███ ░███ ░███  ░███ ███░███░░░    ███░░░███ ░███░░░
 ████████  ░░████████░░███████░░████████░░██████   ░░█████ ░░██████  █████ █████░░██████
░░░░░░░░    ░░░░░░░░  ░░░░░███ ░░░░░░░░  ░░░░░░     ░░░░░   ░░░░░░  ░░░░░ ░░░░░  ░░░░░░
                      ███ ░███
                     ░░██████
                      ░░░░░░                                                             "
echo -e "[+] Make \e[31mCritical\e[0m great again"
}

DOMAIN=$1
OUTPUT=$2
haktrail_cookie="/root/cookie.txt"
subdomain_wordlist="/home/bugdotexe/findsomeluck/recon/wordlists/subdomains-top1million-5000.txt"

passive() {
echo
notice "Starting passive subdomain enumeration"

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} haktrailsfree "
echo "$DOMAIN" | haktrailsfree -c $haktrail_cookie --silent | anew $OUTPUT/haktrails.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@hakktrails~# Found${RESET} ${RED}$(cat "$OUTPUT/haktrails.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} cert "
sed -ne 's/^\( *\)Subject:/\1/p;/X509v3 Subject Alternative Name/{
N;s/^.*\n//;:a;s/^\( *\)\(.*\), /\1\2\n\1/;ta;p;q; }' < <(
openssl x509 -noout -text -in <(
openssl s_client -ign_eof 2>/dev/null <<<$'HEAD / HTTP/1.0\r\n\r' \
-connect $DOMAIN:443 ) ) | grep -Po '((http|https):\/\/)?(([\w.-]*)\.([\w]*)\.([A-z]))\w+' | anew "$OUTPUT/cert.subs" >/dev/null
echo -e "${GREEN}[+] PASSIVE@cert~# Found${RESET} ${RED}$(cat "$OUTPUT/cert.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} crt.sh "
curl -s "https://crt.sh?q=$DOMAIN&output=json" | jq -r '.[].name_value' | grep -Po '(\w+\.\w+\.\w+)$' | sort -u | anew $OUTPUT/crtsh.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@crt.sh~# Found${RESET} ${RED}$(cat "$OUTPUT/crtsh.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} virustotal "
curl -s "https://www.virustotal.com/vtapi/v2/domain/report?apikey=33fa7261693b5212e8018303d976050d12558802f71a6e796e3530f8c933bc2c&domain=$DOMAIN" | jq -r '.domain_siblings[]' | sort -u | anew $OUTPUT/virustotal.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@virustotal~# Found${RESET} ${RED}$(cat "$OUTPUT/virustotal.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} web.archive "
curl -s "http://web.archive.org/cdx/search/cdx?url=*.${DOMAIN}/*&output=text&fl=original&collapse=urlkey" | sed -e 's_https*://__' -e "s/\/.*//" -e 's/:.*//' -e 's/^www\.//' | anew $OUTPUT/webarchive.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@web.archive~# Found${RESET} ${RED}$(cat "$OUTPUT/webarchive.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} subfinder "
subfinder -silent -all -recursive -d $DOMAIN -o "$OUTPUT/subfinder.subs" >/dev/null
echo -e "${GREEN}[+] PASSIVE@subfinder~# Found${RESET} ${RED}$(cat "$OUTPUT/subfinder.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} assetfinder "
assetfinder -subs-only "$DOMAIN" | anew "$OUTPUT/assetfinder.subs"  >/dev/null
echo -e "${GREEN}[+] PASSIVE@assetfinder~# Found${RESET} ${RED}$(cat "$OUTPUT/assetfinder.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} chaos "
chaos -silent -key 7e42cd92-b317-420b-8eac-dbd5eb1c5516 -d "$DOMAIN" | anew "$OUTPUT/chaos.subs" >/dev/null
echo -e "${GREEN}[+] PASSIVE@chaos~# Found${RESET} ${RED}$(cat "$OUTPUT/chaos.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} shosubgo "
shosubgo -s PiILLI6oJS0U5nCHRXwNHcmMMHTWNPqU -d "$DOMAIN" -o "$OUTPUT/shosubgo.subs" >/dev/null
echo -e "${GREEN}[+] PASSIVE@shosubgo~# Found${RESET} ${RED}$(cat "$OUTPUT/shosubgo.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} gitlab "
gitlab-subdomains -t glpat-DaFJSWdR2_mjUStZjmUz-W86MQp1Omdoa3d1Cw.01.12168p8t3 -d $DOMAIN | anew $OUTPUT/gitlab.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@gitlab~# Found${RESET} ${RED}$(cat "$OUTPUT/gitlab.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} github "
github-subdomains -t $GITHUB_TOKEN -d $DOMAIN -o $OUTPUT/github.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@github~# Found${RESET} ${RED}$(cat "$OUTPUT/github.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} amass "
amass enum -d $DOMAIN -timeout 12 -v -o $OUTPUT/amass.tmp >/dev/null
cat $OUTPUT/amass.tmp | grep "FQDN" | awk '{print $1}' | sort -u | anew $OUTPUT/amass.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@amass~# Found${RESET} ${RED}$(cat "$OUTPUT/amass.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} findomain "
findomain -t $DOMAIN -q | anew $OUTPUT/findomain.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@findomain~# Found${RESET} ${RED}$(cat "$OUTPUT/findomain.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

Shodanx() {
echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} shodanx "
#shodanx subdomain -d $DOMAIN -o $OUTPUT/shodanx.subs >/dev/null
echo -e "${GREEN}[+] PASSIVE@shodanx~# Found${RESET} ${RED}$(cat "$OUTPUT/shodanx.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e
}

echo -e "${GREEN}[+] Passive Subdomain Enumeration~#${RESET} bbot "
mkdir -p "$OUTPUT/bbot"
    bbot -t "$DOMAIN" -p subdomain-enum -o "$OUTPUT/bbot" -om subdomains
echo -e "${GREEN}[+] PASSIVE@bbot~# Found${RESET} ${RED}$(find "$OUTPUT/bbot" -name "subdomains.txt" -exec cat {} + 2>/dev/null | wc -l)${RESET} ${GREEN}subdomains${RESET}"
mv $(find "$OUTPUT/bbot" -name "subdomains.txt") $OUTPUT/bbot.subs
echo -e
}

active() {
notice "Starting active subdomain enumeration"
echo -e "${GREEN}[+] Active Subdomain Enumeration~#${RESET} gobuster "
gobuster dns --domain $DOMAIN --wordlist $subdomain_wordlist -q --nc --wildcard | awk '{print $1}' | anew "$OUTPUT/gobuster.subs" >/dev/null
echo -e "${GREEN}[+] ACTIVE@gobuster~# Found${RESET} ${RED}$(cat "$OUTPUT/gobuster.subs" | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Virtual host fuzzing~#${RESET} ffuf "
ffuf -c -r -u https://$DOMAIN/ -H "Host: FUZZ.${DOMAIN}" -w $subdomain_wordlist -o $OUTPUT/ffuf.json -s >/dev/null
cat $OUTPUT/ffuf.json | jq -r '.results[].host' | anew $OUTPUT/ffuf.subs >/dev/null
echo -e "${GREEN}[+] ACTIVE@ffuf~# Found${RESET} ${RED}$(cat $OUTPUT/ffuf.subs | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

echo -e "${GREEN}[+] Active Subdomain Enumeration~#${RESET} mksub "
mksub -d $DOMAIN -l 2 -w $subdomain_wordlist -r "^[a-zA-Z0-9\.-_]+$" | dnsx -silent | anew $OUTPUT/mksub.subs
echo -e "${GREEN}[+] ACTIVE@mksub~# Found${RESET} ${RED}$(cat $OUTPUT/mksub.subs | wc -l)${RESET} ${GREEN}subdomains${RESET}"
echo -e

}

live_check() {

echo -e "${GREEN}[+] Checking live subdomains~#${RESET} httpx "
cat $OUTPUT/*.subs | sort -u | httpx -ports 80,81,443,591,2082,2087,2095,2096,3000,8000,8001,8008,8080,8083,8443,8834,8888,9000 -silent -random-agent -sc -td -ct -cl -server \
-H "X-Forwarded-For: 127.0.0.1" \
-H "Base-Url: 127.0.0.1" \
-H "Client-IP: 127.0.0.1" \
-H "Http-Url: 127.0.0.1" \
-H "Proxy-Host: 127.0.0.1" \
-H "Proxy-Url: 127.0.0.1" \
-H "Real-Ip: 127.0.0.1" \
-H "Redirect: 127.0.0.1" \
-H "Referer: 127.0.0.1" \
-H "Referrer: 127.0.0.1" \
-H "Refferer: 127.0.0.1" \
-H "Request-Uri: 127.0.0.1" \
-H "Uri: 127.0.0.1" \
-H "Url: 127.0.0.1" \
-H "X-Client-IP: 127.0.0.1" \
-H "X-Custom-IP-Authorization: 127.0.0.1" \
-H "X-Forward-For: 127.0.0.1" \
-H "X-Forwarded-By: 127.0.0.1" \
-H "X-Forwarded-For-Original: 127.0.0.1" \
-H "X-Forwarded-For: 127.0.0.1" \
-H "X-Forwarded-Host: 127.0.0.1" \
-H "X-Forwarded-Port: 443" \
-H "X-Forwarded-Port: 4443" \
-H "X-Forwarded-Port: 80" \
-H "X-Forwarded-Port: 8080" \
-H "X-Forwarded-Port: 8443" \
-H "X-Forwarded-Scheme: http" \
-H "X-Forwarded-Scheme: https" \
-H "X-Forwarded-Server: 127.0.0.1" \
-H "X-Forwarded: 127.0.0.1" \
-H "X-Forwarder-For: 127.0.0.1" \
-H "X-Host: 127.0.0.1" \
-H "X-Http-Destinationurl: 127.0.0.1" \
-H "X-Http-Host-Override: 127.0.0.1" \
-H "X-Original-Remote-Addr: 127.0.0.1" \
-H "X-Original-Url: 127.0.0.1" \
-H "X-Originating-IP: 127.0.0.1" \
-H "X-Proxy-Url: 127.0.0.1" \
-H "X-Real-Ip: 127.0.0.1" \
-H "X-Remote-Addr: 127.0.0.1" \
-H "X-Remote-IP: 127.0.0.1" \
-H "X-Rewrite-Url: 127.0.0.1" \
-H "X-True-IP: 127.0.0.1" \
-favicon -title -cname -asn -srd $OUTPUT/response | anew $OUTPUT/httpx.probe

}

passive
active
live_check
