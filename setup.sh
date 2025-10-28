#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

HAKTRAILS_COOKIE="/root/cookie.txt"
GOPATH_DEFAULT="${GOPATH:-$HOME/go}"
GOBIN_DEFAULT="${GOBIN:-$GOPATH_DEFAULT/bin}"
SHELL_RC_FILES=("$HOME/.bashrc" "$HOME/.zshrc")

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

notice() { printf '\e[1;34m[INFO]\e[0m %s\n' "$*"; }
warn()   { printf '\e[1;33m[WARN]\e[0m %s\n' "$*"; }
err()    { printf '\e[1;31m[ERROR]\e[0m %s\n' "$*"; }

declare -A apt_tools=(
    [subfinder]=subfinder
    [gh]=gh
    [jq]=jq
    [findomain]=findomain
    [assetfinder]=assetfinder
    [gobuster]=gobuster
    [nuclei]=nuclei
    [sublist3r]=sublist3r
    [pipx]=pipx
    [amass]=amass
    [dirsearch]=dirsearch
    [ffuf]=ffuf
    [waymore]=waymore

)

install_apt_packages() {
    local -a to_install=()

    for cmd in "${!apt_tools[@]}"; do
        if ! command_exists "$cmd"; then
            pkg="${apt_tools[$cmd]}"
            warn "  -> '$cmd' not found, will attempt to install package: $pkg"
            to_install+=("$pkg")
        fi
    done

    if ! command_exists go; then
        warn "'go' not found, will attempt to install 'golang' package"
        to_install+=("golang")
    fi

    if [ ${#to_install[@]} -eq 0 ]; then
        return 0
    fi

    notice "Installing missing packages: ${to_install[*]}"
    sudo apt update -y
    if ! sudo apt install -y --no-install-recommends "${to_install[@]}"; then
        warn "apt install reported failures. Some tools may still be missing."
    fi

    for pkg in "${to_install[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            warn "Package '$pkg' may not exist in apt repos on this system. Consider installing manually or via distribution-specific repos."
        fi
    done
}

setup_go_environment() {
    export GOPATH="$GOPATH_DEFAULT"
    export GOBIN="${GOBIN:-$GOBIN_DEFAULT}"

    if command_exists go && [ -z "${GOROOT:-}" ]; then
        GOROOT_VAL="$(go env GOROOT 2>/dev/null || true)"
        [ -n "$GOROOT_VAL" ] && export GOROOT="$GOROOT_VAL"
    fi

    export PATH="$PATH:$GOBIN"
    mkdir -p "$GOPATH" "$GOBIN"

    local line
    line=$'### Go environment (added by recon/setup.sh)\nexport GOPATH="$HOME/go"\nexport GOBIN="$GOPATH/bin"\nexport PATH="$PATH:$GOBIN"'
    for rc in "${SHELL_RC_FILES[@]}"; do
        if [ -f "$rc" ]; then
            if ! grep -q "setup.sh" "$rc"; then
                notice "Appending Go env to $rc"
                printf '\n%s\n' "$line" >>"$rc"
            fi
        fi
    done
}

install_go_tools() {
    if ! command_exists go; then
        warn "go is not available in PATH. Attempting to install via apt..."
        install_apt_packages
        if ! command_exists go; then
            err "go still not found. Skipping go-based tool installs."
            return 1
        fi
    fi

    setup_go_environment

    declare -A go_tools=(
        [gitlab-subdomains]=github.com/gwen001/gitlab-subdomains@latest
        [github-subdomains]=github.com/gwen001/github-subdomains@latest
        [github-endpoints]=github.com/gwen001/github-endpoints@latest
        [shosubgo]=github.com/incogbyte/shosubgo@latest
        [chaos]=github.com/projectdiscovery/chaos-client/cmd/chaos@latest
        [dnsx]=github.com/projectdiscovery/dnsx/cmd/dnsx@latest
        [mksub]=github.com/trickest/mksub@latest
        [httpx]=github.com/projectdiscovery/httpx/cmd/httpx@latest
        [haktrailsfree]=github.com/rix4uni/haktrailsfree@latest
        [cent]=github.com/xm1k3/cent/v2@latest
        [hakrawler]=github.com/hakluke/hakrawler@latest
        [unfurl]=github.com/tomnomnom/unfurl@latest
        [gau]=github.com/lc/gau/v2/cmd/gau@latest
        [katana]=github.com/projectdiscovery/katana/cmd/katana@latest
        [urlfinder]=github.com/projectdiscovery/urlfinder/cmd/urlfinder@latest

    )

    for cmd in "${!go_tools[@]}"; do
        pkg="${go_tools[$cmd]}"
        if ! command_exists "$cmd"; then
            notice "Installing $cmd ($pkg)..."
            GOBIN="$GOBIN" go install -v "$pkg"
        else
           return 0
        fi
    done
}

install_pipx_tools() {
    if ! command_exists pipx; then
        warn "pipx not found; installing pipx via python3 -m pip (user install)."
        if command_exists python3; then
            python3 -m pip install --user pipx
            python3 -m pipx ensurepath || true
            export PATH="$PATH:$HOME/.local/bin"
        else
            err "python3 not found; cannot install pipx. Skipping pipx tool installs."
            return 1
        fi
    fi

    declare -a pipx_tools=(shodanx bbot)

    for tool in "${pipx_tools[@]}"; do
        if ! command_exists "$tool"; then
            notice "Installing $tool via pipx..."
            pipx install "$tool" || warn "pipx install of $tool failed — you may need to install manually."
        else
            return 0
        fi
    done
}

configure_tools() {
    if command_exists nuclei; then
        if [ -z "${NUCLEI_TEMPLATES_DIR:-}" ]; then
            NUCLEI_TEMPLATES_DIR="$HOME/.local/nuclei-templates"
        fi
        if [ ! -d "$NUCLEI_TEMPLATES_DIR" ] || [ -z "$(ls -A "$NUCLEI_TEMPLATES_DIR" 2>/dev/null || true)" ]; then
            notice "Nuclei templates not found in $NUCLEI_TEMPLATES_DIR. Running 'nuclei -ut' to fetch templates."
            nuclei -ut || warn "nuclei template update failed."
        else
            return 0
        fi
    fi


    if command_exists cent; then
        if [ -n "${NUCLEI_TEMPLATES_DIR:-}" ] && [ -d "$NUCLEI_TEMPLATES_DIR" ]; then
            notice "Running cent to process templates in $NUCLEI_TEMPLATES_DIR..."
            cent -p "$NUCLEI_TEMPLATES_DIR" || warn "cent processing failed or is not applicable."
        else
            warn "cent installed but nuclei templates directory not found; skipping cent."
        fi
    fi
}

check_haktrails() {
    if [ ! -f "$HAKTRAILS_COOKIE" ]; then
        warn "Haktrails cookie not found at '$HAKTRAILS_COOKIE'. Create it and re-run this check if you need haktrailsfree."
        return 0
    fi

    if ! command_exists haktrailsfree; then
        warn "haktrailsfree not installed; cannot check cookie expiry."
        return 0
    fi

    if echo "goflink.com" | haktrailsfree -c /root/cookie.txt --silent | grep -q "Cookie Expired:"; then
    warn "Go get a new: https://securitytrails.com/list/apex_domain/krazeplanet.com?page=1"
    else
    return 0
    fi
}

main() {
    notice "Starting Dependency Check."

    install_apt_packages || warn "install_apt_packages had issues."
    install_go_tools || warn "install_go_tools had issues (see messages above)."
    install_pipx_tools || warn "install_pipx_tools had issues."
    configure_tools || warn "configure_tools had issues."
    check_haktrails || warn "check_haktrails had issues."
}

main "$@"
