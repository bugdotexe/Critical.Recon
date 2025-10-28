#!/bin/bash

RED="\e[31m"
RESET="\e[0m"
GREEN="\e[32m"

notice() { printf '\e[1;34m[INFO]\e[0m %s\n' "$*"; }
warn()   { printf '\e[1;33m[WARN]\e[0m %s\n' "$*"; }
err()    { printf '\e[1;31m[ERROR]\e[0m %s\n' "$*"; }

echo
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

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -d|--domain)
      DOMAIN=$2
      shift 2
      ;;
    -org|--org)
      ORG=$2
      shift 2
      ;;
    *)
      echo -e "[-]${RED} Usage: sh main.sh -d replit.com -org replit"
      exit 1
      ;;
  esac
done

./setup.sh

mkdir -p $ORG/$DOMAIN/ASSETS/
OUTPUT="$ORG/$DOMAIN"

echo -e "${GREEN}[+] TARGET.DOMAIN~#${RESET} $DOMAIN "
echo -e "${GREEN}[+] OUTPUT.DIR~#${RESET}    $ORG/$DOMAIN "

./assets_discovery.sh $DOMAIN "$OUTPUT/ASSETS"
