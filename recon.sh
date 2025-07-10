#!/usr/bin/env bash
set -euo pipefail
shopt -s nocasematch

########################################
# -----------  COLOURS  -------------- #
########################################
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
BOLD='\033[1m'
RESET='\033[0m'

log() {
    local colour="${2:-$CYAN}"
    echo -e "${colour}${BOLD}[$(date +'%I:%M:%S %p')]${RESET} $1"
}

########################################
# -------------  USAGE  -------------- #
########################################
USAGE() {
    echo "Usage: $0 -d domain.com [-o /output/base]"
    echo "Options:"
    echo "  -d, --domain    Target domain (required)"
    echo "  -o, --output    Base directory (default: ./recon)"
    exit 1
}

########################################
# --------  ARGUMENT PARSE  ---------- #
########################################
base_dir="./recon"
domain=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)  domain=$2; shift 2 ;;
        -o|--output)  base_dir=$2; shift 2 ;;
        *)            USAGE ;;
    esac
done
[[ -z "$domain" ]] && USAGE

########################################
# ------  DIRECTORY PREPARATION  ----- #
########################################
run_dir="$base_dir/$domain"

make_four() { mkdir -p "$1"/{tmp,info,subs,scans}; }

make_four "$run_dir"

tmp="$run_dir/tmp"
info="$run_dir/info"
subs="$run_dir/subs"
scans="$run_dir/scans"

# external lists
resolvers="$HOME/Tools/resolvers.txt"
subdomains="$HOME/Tools/subdomains_n0kovo_big.txt"

########################################
# --------  RECON FUNCTIONS  --------- #
########################################
Reverse_DNS() {
    log "Starting Reverse DNS Enumeration for: $domain" "$BLUE"

    > "$tmp/asn.txt"         # ensure file exists even if empty
    for ip in $(dig +short A "$domain"); do
        whois -h whois.cymru.com "$ip" | \
            awk '$1 ~ /^[0-9]+$/ {print "AS"$1}' >> "$tmp/asn.txt"
    done

    if [[ -s "$tmp/asn.txt" ]]; then
        sort -u "$tmp/asn.txt" -o "$info/asn.txt"
        log "ASN Enumeration finished: $(wc -l < "$info/asn.txt") ASNs found" "$GREEN"
    else
        touch "$info/asn.txt"
        log "No ASNs found (empty ASN list)" "$YELLOW"
    fi

    echo "https://$domain" | favfreak --shodan -o "$info/favihash.txt" &>/dev/null
    log "FaviconHash Enumeration finished" "$GREEN"

    while read -r asn; do
        whois -h whois.radb.net -- "-i origin $asn" | \
            grep -Eo "([0-9.]+){4}/[0-9]+" | uniq
    done < "$info/asn.txt" | sort -u > "$info/cidr.txt"
    log "CIDR Enumeration finished: $(wc -l < "$info/cidr.txt") CIDRs found" "$GREEN"
        mapcidr -silent < "$info/cidr.txt" | \
          dnsx -ptr -resp-only -silent -r "$resolvers" -o "$info/ptr.txt"
        log "PTR Enumeration finished: $(wc -l < "$info/ptr.txt") records found" "$GREEN"
}

Passive_Enum() {
    log "Starting Passive Subdomain Enumeration" "$BLUE"

    subfinder -exclude-sources digitorus -silent -d "$domain" -o "$subs/subfinder.subs" &>/dev/null
    assetfinder -subs-only "$domain" | anew "$subs/assetfinder.subs" &>/dev/null
    sublist3r -d "$domain" -n -o "$subs/sublist3r.subs" &>/dev/null
    findomain -r -q -t "$domain" | anew "$subs/findomain.subs" &>/dev/null
    cert-subs "$domain" | anew "$subs/cert.subs" &>/dev/null
    crtsh "$domain" | anew "$subs/crtsh.subs" &>/dev/null
    amass enum -active -alts -d "$domain" -o "$subs/amass.tmp" &>/dev/null
    awk '/FQDN/{print $1}' "$subs/amass.tmp" | anew "$subs/amass.subs" &>/dev/null
    awk '/FQDN/{print $6}' "$subs/amass.tmp" | anew "$subs/amass.subs" &>/dev/null
    gitlab-subdomains -t glpat-x7VSQETZyu3oA8zs -d "$domain" | anew "$subs/gitlab.subs" &>/dev/null
    github-subdomains -t github_pat_11BRU35uGMt4nE_4qmRKHPFBgleL0QH6uQGdxGt8a1e1ZVXIXInGSJd2jBKONT2L4GAqypK1Bv \
                      -d "$domain" -o "$subs/github.subs" &>/dev/null
    touch "$subs/virustotal.subs"  # ensure exists for count below

    cat "$subs"/*.subs | sort -u > "$subs/passive.subs"
    log "Passive Enumeration finished: $(wc -l < "$subs/passive.subs") subdomains found" "$GREEN"
}

Active_Enum() {
    log "Starting Active Subdomain Enumeration" "$BLUE"

    gobuster dns -d "$domain" --no-error --quiet --wildcard \
        -w /usr/share/seclists/Discovery/DNS/bug-bounty-program-subdomains-trickest-inventory.txt \
        -o "$tmp/gobuster.tmp" &>/dev/null
    awk '{print $2}' "$tmp/gobuster.tmp" | anew "$subs/gobuster.subs" &>/dev/null

    dnsx -silent -r "$resolvers" -w "$subdomains" -d "$domain" -o "$subs/dnsx.subs" &>/dev/null

    cat "$subs"/{gobuster.subs,dnsx.subs} | sort -u > "$subs/active.subs"
    log "Active Enumeration finished: $(wc -l < "$subs/active.subs") new subdomains found" "$GREEN"
}

Probe_Subs() {
    log "Probing live hosts" "$BLUE"

    cat "$subs"/{passive.subs,active.subs} | sort -u > "$subs/final.subs"

    while read -r sub; do virustotal "$sub" &>/dev/null; done < "$subs/final.subs"

    httpx-toolkit -list "$subs/final.subs" -random-agent \
        -H "X-Forwarded-For: 127.0.0.1" -H "X-Forwarded-Host: 127.0.0.1" \
        -fr -retries 3 -r "$resolvers" -silent -no-color > "$subs/httpx.probe"

    log "Probing finished: $(wc -l < "$subs/httpx.probe") live hosts found" "$GREEN"

    # directory tree for every discovered sub‑domain
    while read -r sub; do
        sd_dir="$run_dir/$sub"
        [[ -d "$sd_dir" ]] || make_four "$sd_dir"
    done < "$subs/final.subs"
}

nmapScan() {
    log "Starting Nmap scanning" "$BLUE"

    nmap -T4 -vv -iL "$subs/httpx.probe" --top-ports 3000 -n --open -oX "$scans/nmap.xml" &>/dev/null

    ( cd /root/Tools/tew/ && \
      go run main.go -x "$scans/nmap.xml" -dnsx "$scans/dns.json" --vhost \
          -o "$scans/hostport.txt" ) | \
      httpx-toolkit -json -o "$scans/http.json"

    jq -r '.url' "$scans/http.json" | sed -e 's/:80$//' -e 's/:443$//' | sort -u > "$scans/http.txt"
    log "Nmap scan completed: $(wc -l < "$scans/http.txt") services found" "$GREEN"
}

crawling() {
    log "Starting Spidering" "$BLUE"

    ( cd /root/gospider/ && \
      go run main.go -S "$scans/http.txt" --json | grep '{' | jq -r '.output?' ) | \
      anew "$scans/gospider.urls"

    katana -silent -xhr -aff -kf -jsl -fx -td -d 5 -jc -list "$subs/final.subs" \
           -o "$scans/katana.urls"

    waymore --providers wayback,commoncrawl,otx,urlscan,virustotal,intelx \
            -i "$domain" -mode U -oU "$scans/waymore.urls"

    echo "$domain" | gau --subs -o "$scans/gau.urls"

    [[ -f "$subs/virustotal.urls" ]] && mv "$subs/virustotal.urls" "$scans/virustotal.urls"

    cat "$scans"/*.urls | uro | httpx-toolkit -silent | anew "$scans/final.urls"

    katana -silent -xhr -aff -kf -jsl -fx -td -d 5 -jc -list "$scans/final.urls" \
           -o "$scans/katana_final.urls"

    log "Spidering finished: $(wc -l < "$scans/final.urls") URLs found" "$GREEN"
}
CIDR() {

 if [[ -s "$info/cidr.txt" ]]; then
        while read -r cidr; do
            cidr_output="$scans/cidr_pentest/$cidr"
            mkdir -p "$cidr_output"

            masscan "$cidr" -p1-65535 --rate 10000 --output-format json \
                    -oJ "$cidr_output/masscan_results.json"

            jq -r '.[] | select(.ports[0].status=="open") | "\(.ip):\(.ports[0].port)"' \
                "$cidr_output/masscan_results.json" | sort -u > "$cidr_output/alive-hosts"

            cat "$cidr_output/alive-hosts" | \
              httpx-toolkit -silent -random-agent -sc -td -ct -cl -server \
              -H "X-Forwarded-For: 127.0.0.1" -H "X-Forwarded-Host: 127.0.0.1" \
              -title -srd response | tee -a "$cidr_output/httpx.probe"
        done < "$info/cidr.txt"
    else
        log "No CIDRs – falling back to PTR lookup" "$YELLOW"
        fi
        }
########################################
# --------------- RUN --------------- #
########################################
echo
log "=== Starting reconnaissance for: $domain ===" "$MAGENTA"
log "Output will be saved in: $run_dir" "$YELLOW"

Reverse_DNS
Passive_Enum
Active_Enum
Probe_Subs
nmapScan
crawling
