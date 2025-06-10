#!/bin/bash
# Advanced Git Secrets Hunter Framework (AGSHF)
# Version: 2.0
# Author: Your Name
# Inspired by Sharon Brizinov's research

# Configuration
CONFIG_FILE="agshf.conf"
LOG_DIR="logs"
OUTPUT_DIR="findings"
TEMP_DIR="/tmp/agshf_$(date +%s)"
TELEGRAM_BOT_TOKEN="8001910878:AAHV7sLYtsKhMRTcxaTtN1OABhwPeuofmgI"
TELEGRAM_CHAT_ID="6729179510"
MAX_REPO_SIZE_MB=500
PARALLEL_JOBS=5
DEEP_SCAN=false
VERBOSE=false
GITHUB_TOKEN=ghp_dCRrVGv3NbXweRPi8wKoVFrAID2FR3RlEpp

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        echo -e "${YELLOW}[!] Configuration file not found. Using defaults.${NC}"
    fi
}

# Initialize directories
init_dirs() {
    mkdir -p "$LOG_DIR" "$OUTPUT_DIR" "$TEMP_DIR"
}

# Logging functions
log() {
    local log_file="$LOG_DIR/$org/github.log"
}

# Error handling
error_exit() {
    log "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check dependencies
check_dependencies() {
    local deps=("git" "gh" "trufflehog" "jq" "parallel" "rg" "git-filter-repo")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error_exit "Missing dependencies: ${missing[*]}"
    fi
}

# Telegram notification
send_telegram() {
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return
    fi

    local message="$1"
    local file="$2"

    if [ -z "$file" ]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="$message" > /dev/null
    else
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
            -F chat_id="$TELEGRAM_CHAT_ID" \
            -F document=@"$file" \
            -F caption="$message" > /dev/null
    fi
}

# Get organization repositories
get_org_repos() {
    local org="$1"
    local repos_file="$TEMP_DIR/${org}_repos.json"

    log "${BLUE}[*] Fetching repositories for organization: $org${NC}"

    gh repo list "$org" --limit 1000 --json name,isPrivate,isArchived,isFork,updatedAt > "$repos_file" || {
        log "${YELLOW}[!] Failed to fetch repos for $org${NC}"
        return 1
    }

    # Filter relevant repos
    jq -r '.[] | select(.isPrivate == false) | select(.isArchived == false) | select(.isFork == false) | .name' "$repos_file"
}

# Clone repository
clone_repo() {
    local org="$1"
    local repo="$2"
    local clone_dir="$TEMP_DIR/$org/$repo"

    if [ -d "$clone_dir" ]; then
        log "${YELLOW}[!] Repository already exists: $org/$repo${NC}"
        return 0
    fi

    mkdir -p "$(dirname "$clone_dir")"

    log "${BLUE}[*] Cloning repository: $org/$repo${NC}"
    git clone --quiet "https://github.com/$org/$repo.git" "$clone_dir" || {
        log "${YELLOW}[!] Failed to clone $org/$repo${NC}"
        return 1
    }

    return 0
}

# Extract deleted files
extract_deleted_files() {
    local repo_dir="$1"
    local output_dir="$2"
    local org_repo="$3"

    pushd "$repo_dir" > /dev/null || return 1

    mkdir -p "$output_dir/deleted_files"

    # Method 1: git log diff extraction
    log "${BLUE}[*] Extracting deleted files from commit history${NC}"
    git log --diff-filter=D --summary | grep delete | awk '{print $4}' | while read -r file; do
        local commit=$(git rev-list -n 1 HEAD -- "$file")
        if [ -n "$commit" ]; then
            local safe_name=$(echo "$file" | tr '/' '_')
            git show "${commit}^:$file" > "$output_dir/deleted_files/${commit}_${safe_name}" 2>/dev/null
        fi
    done

    # Method 2: Dangling objects
    log "${BLUE}[*] Searching for dangling objects${NC}"
    mkdir -p "$output_dir/dangling_objects"
    git fsck --unreachable --dangling --no-reflogs --full 2>/dev/null | grep 'unreachable blob' | awk '{print $3}' | while read -r hash; do
        git cat-file -p "$hash" > "$output_dir/dangling_objects/$hash.blob" 2>/dev/null
    done

    # Method 3: Pack file analysis (deep scan)
    if $DEEP_SCAN; then
        log "${BLUE}[*] Performing deep scan (unpacking .pack files)${NC}"
        mkdir -p "$output_dir/pack_files"
        find .git/objects/pack -name "*.pack" | while read -r packfile; do
            local base=$(basename "$packfile" .pack)
            git unpack-objects < "$packfile" 2>/dev/null
            find .git/objects -type f | grep -v pack | while read -r obj; do
                local obj_hash=$(basename "$(dirname "$obj")")$(basename "$obj")
                git cat-file -p "$obj_hash" > "$output_dir/pack_files/$obj_hash.obj" 2>/dev/null
            done
        done
    fi

    popd > /dev/null || return 1
}

# Scan for secrets
scan_for_secrets() {
    local scan_dir="$1"
    local output_file="$2"
    local org_repo="$3"

    log "${BLUE}[*] Scanning for secrets in: $org_repo${NC}"

    # Use trufflehog with multiple detectors
    trufflehog filesystem --results=verified --json "$scan_dir"  >> "$output_file.tmp" || {
        log "${YELLOW}[!] Trufflehog scan failed for $org_repo${NC}"
        return 1
    }
    trufflehog git --results=verified --json file://"$scan_dir"  >> "$output_file.tmp" || {
        log "${YELLOW}[!] Trufflehog scan failed for $org_repo${NC}"
        return 1
    }
    # Additional custom regex scans
    log "${BLUE}[*] Running custom pattern scans${NC}"
    local custom_patterns=(
        # AWS
        '(?i)aws(.{0,20})?[''"]([A-Z0-9]{20})[''"]'
        '(?i)aws(.{0,20})?[''"]([A-Za-z0-9/+=]{40})[''"]'
        # GitHub
        '(?i)github(.{0,20})?[''"]([a-zA-Z0-9]{36})[''"]'
        '(?i)github(.{0,20})?[''"](ghp_[a-zA-Z0-9]{36})[''"]'
        # Generic API keys
        '(?i)(api|access|secret|token)(.{0,20})?[''"]([0-9a-zA-Z]{32,64})[''"]'
    )

    for pattern in "${custom_patterns[@]}"; do
        rg -i --json "$pattern" "$scan_dir" >> "$output_file.tmp"
    done

    # Process and deduplicate results
    jq -s 'flatten | unique_by(.text)' "$output_file.tmp" > "$output_file"
    rm "$output_file.tmp"

    # Verify findings and filter false positives
    local verified_count=$(jq 'length' "$output_file")
    log "${GREEN}[+] Found $verified_count potential secrets in $org_repo${NC}"

    if [ "$verified_count" -gt 0 ]; then
        send_telegram "🔍 Found $verified_count potential secrets in $org_repo" "$output_file"
    fi

    return 0
}

# Clean up repository
cleanup_repo() {
    local repo_dir="$1"
    rm -rf "$repo_dir"
}

# Process single repository
process_repo() {
    local org="$1"
    local repo="$2"
    local org_repo="$org/$repo"
    local repo_dir="$TEMP_DIR/$org/$repo"
    local output_dir="$OUTPUT_DIR/$org/$repo"

    mkdir -p "$output_dir"

    if ! clone_repo "$org" "$repo"; then
        return 1
    fi

    extract_deleted_files "$repo_dir" "$output_dir" "$org_repo"
    scan_for_secrets "$repo_dir" "$output_dir/secrets.json" "$org_repo"

    if $DEEP_SCAN; then
        scan_for_secrets "$output_dir/deleted_files" "$output_dir/deleted_secrets.json" "$org_repo (deleted)"
        scan_for_secrets "$output_dir/dangling_objects" "$output_dir/dangling_secrets.json" "$org_repo (dangling)"
        if $DEEP_SCAN; then
            scan_for_secrets "$output_dir/pack_files" "$output_dir/pack_secrets.json" "$org_repo (pack files)"
        fi
    fi

    cleanup_repo "$repo_dir"

    return 0
}
# Main function
main() {
    load_config
    init_dirs
    check_dependencies

    log "${GREEN}[+] Starting Advanced Git Secrets Hunter Framework${NC}"
    log "${GREEN}[+] Target organizations: ${ORGANIZATIONS[*]}${NC}"

    local org_count=0
    local repo_count=0
    local finding_count=0

    for org in "${ORGANIZATIONS[@]}"; do
        ((org_count++))
        local org_repos=($(get_org_repos "$org" | grep -E '^[a-zA-Z0-9_.-]+$' | grep -vE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$|^[0-9]{2}:[0-9]{2}:[0-9]{2}$'))

        log "${BLUE}[*] Processing organization: $org (${#org_repos[@]} valid repositories)${NC}"

        # Export required functions and variables
        export -f process_repo clone_repo extract_deleted_files scan_for_secrets cleanup_repo log error_exit
        export GREEN YELLOW BLUE RED NC TEMP_DIR OUTPUT_DIR DEEP_SCAN

        # Process valid repos in parallel
        for repo in "${org_repos[@]}"; do
            ((i=i%PARALLEL_JOBS))
            ((i++==0)) && wait
            (
                log "${BLUE}[*] Processing $org/$repo${NC}"
                process_repo "$org" "$repo"
            ) &
        done
        wait

        ((repo_count += ${#org_repos[@]}))
    done

    # Generate summary report
    local summary_file="$OUTPUT_DIR/summary_$(date +%Y%m%d).json"
    local finding_count=$(find "$OUTPUT_DIR" -name "*.json" -exec jq 'length' {} + | awk '{s+=$1} END {print s}')

    jq -n --arg date "$(date)" \
        --arg orgCount "$org_count" \
        --arg repoCount "$repo_count" \
        --arg findingCount "$finding_count" \
        '{
            date: $date,
            organizations: $orgCount,
            repositories: $repoCount,
            findings: $findingCount
        }' > "$summary_file"

    log "${GREEN}[+] Scan completed! Processed $repo_count repositories across $org_count organizations${NC}"
    log "${GREEN}[+] Findings saved to: $OUTPUT_DIR${NC}"
    log "${GREEN}[+] Summary report: $summary_file${NC}"

    send_telegram "✅ AGSHF scan completed:
- Organizations: $org_count
- Repositories: $repo_count
- Findings: $finding_count" "$summary_file"

    # Cleanup
    rm -rf "$TEMP_DIR"
}

    # Cleanup
# Entry point
if [ $# -eq 0 ]; then
    # Read organizations from config file
    declare -a ORGANIZATIONS=($(jq -r '.organizations[]' "$CONFIG_FILE" 2>/dev/null))
    if [ ${#ORGANIZATIONS[@]} -eq 0 ]; then
        error_exit "No organizations specified. Please provide organizations as arguments or in config file."
    fi
else
    declare -a ORGANIZATIONS=("$@")
fi

main
