#!/bin/bash
MAX_JOBS=10

OUTPUT_DIR="/root/TECH_DB"
DB_FILE="$OUTPUT_DIR/tech.db"
LOCK_FILE="$DB_FILE.lock"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

WHITELIST=(
  # Servers & Proxies
  Apache Nginx IIS Varnish Caddy Lighttpd Tomcat Traefik HAProxy OpenResty
  Squid Envoy Apache-Traffic-Server "Amazon Web Services" Akamai

  # CMS
  WordPress Drupal Joomla Magento Shopify Ghost Strapi Contentful Sitecore
  AdobeExperienceManager Kentico Umbraco PrestaShop TYPO3 ConcreteCMS

  # API Technologies
  Swagger OpenAPI GraphQL Apollo REST SOAP JSON-RPC XML-RPC gRPC WebSocket
  AzureAPIManagement Kong Tyk Postman LoopBack

  # Monitoring & Analytics
  Grafana Kibana Prometheus Splunk NewRelic Datadog Sentry Airbrake ELK
  Zabbix Nagios AppDynamics Dynatrace

  # Databases & Caching
  MySQL PostgreSQL MongoDB Elasticsearch Redis Memcached Cassandra CouchDB
  SQLite Oracle MicrosoftSQLServer MariaDB Firebase Firestore CockroachDB
  InfluxDB TimescaleDB

  # Deployment & DevOps
  Docker Kubernetes Jenkins GitLab Terraform Ansible Puppet Chef AWS Azure
  GCP Heroku DigitalOcean Cloudflare Vercel Netlify OpenStack Rancher
  ArgoCD Spinnaker

  # Backend Frameworks
  Node.js Express.js Django Flask RubyOnRails SpringBoot Laravel ASP.NET
  Phoenix FastAPI Nest.js Koa.js Hapi.js Sails.js Meteor.js

  # Frontend Frameworks
  React Vue.js Angular Next.js Nuxt.js Svelte SvelteKit Ember.js Backbone.js
  Gatsby jQuery Bootstrap TailwindCSS Bulma Foundation SemanticUI "Element UI"

  # Authentication & Authorization
  OAuth JWT Okta Auth0 Keycloak CAS SAML OpenIDConnect LDAP ActiveDirectory
  PingIdentity ForgeRock Duo

  # Programming Languages
  Java Python PHP Ruby JavaScript TypeScript Go Rust Elixir Scala Kotlin
  Swift Dart Perl

  # Mobile Frameworks
  ReactNative Flutter Ionic Cordova Xamarin NativeScript

  # E-commerce Platforms
  WooCommerce BigCommerce SalesforceCommerceCloud OracleCommerce IBMWebSphereCommerce
  Shopware OpenCart ZenCart

  # Security Tools
  HashiCorpVault CloudflareZeroTrust BeyondCorp CrowdStrike PaloAltoPrismaCloud
  Qualys Nessus BurpSuite OWASPZAP

  # Message Queues & Streaming
  RabbitMQ Kafka ActiveMQ AmazonSQS RedisPubSub ZeroMQ NATS

  # Search Engines
  Solr Algolia MeiliSearch AzureSearch AWSCloudSearch

  # File Storage
  AmazonS3 GoogleCloudStorage AzureBlobStorage Minio Ceph

  # Blockchain & Web3
  Ethereum Solana Polygon Hyperledger Web3.js Ethers.js Hardhat Truffle
)

is_allowed() {
  local tech="$1"
  for allowed in "${WHITELIST[@]}"; do
    if [[ "$tech" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

random_ip() {
  echo "$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"
}

get_random_ua() {
  local uas=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    "curl/7.68.0"
    "Wget/1.20"
  )
  echo "${uas[RANDOM % ${#uas[@]}]}"
}

init_db() {
  if [[ ! -f "$DB_FILE" ]]; then
    echo -e "${YELLOW}Creating database: $DB_FILE${NC}"
    sqlite3 "$DB_FILE" "CREATE TABLE results (id INTEGER PRIMARY KEY, domain TEXT, tech TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, UNIQUE(domain, tech));"
    sqlite3 "$DB_FILE" "CREATE INDEX idx_tech ON results(tech);"
    sqlite3 "$DB_FILE" "CREATE INDEX idx_domain ON results(domain);"
  fi
}

make_api_request() {
  local domain="$1"
  local max_retries=3
  local retry_count=0
  local delay=5
  local RESP=""

  while [ $retry_count -lt $max_retries ]; do
    RESP=$(curl -s -X POST "https://api.ful.io/domain-search" \
      -H "User-Agent: $(get_random_ua)" \
      -H "X-Forwarded-For: $(random_ip)" \
      -H "Accept: application/json" \
      --form "url=$domain" \
      --connect-timeout 15 \
      --max-time 30 \
      --retry $max_retries \
      --retry-delay $delay)

    if [ $? -eq 0 ] && [ -n "$RESP" ]; then
      echo "$RESP"
      return 0
    fi

    ((retry_count++))
    sleep $delay
  done

  echo -e "${RED}Failed to retrieve data for $domain after $max_retries attempts${NC}" >&2
  return 1
}

insert_db_safe() {
  local domain="$1"
  local tech="$2"
  local tech_file="${tech// /_}"

  (
    flock -x 200
    sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO results (domain, tech) VALUES ('$domain','$tech');"

    echo "$domain" >>"$OUTPUT_DIR/$tech_file.txt"
  ) 200>"$LOCK_FILE"
}

process_domain() {
  local DOMAIN="$1"
  local CLEAN_DOMAIN=${DOMAIN#*//}
  CLEAN_DOMAIN=${CLEAN_DOMAIN//\//-}

  echo -e "${CYAN}[*] Scanning $DOMAIN...${NC}"
  local RESP
  RESP=$(make_api_request "$DOMAIN")
  if [ $? -ne 0 ]; then
    return 1
  fi

  echo "$RESP" | jq . >"$OUTPUT_DIR/$CLEAN_DOMAIN.json" 2>/dev/null

  local TECHS
  TECHS=$(echo "$RESP" | jq -r '.technologies[].technologies[].name?' | \
            grep -E '^[a-zA-Z0-9 .-]+$' | \
            grep -v "null" | \
            sort -u)

  if [[ -z "$TECHS" ]]; then
    echo -e "${YELLOW}No tech found for $DOMAIN${NC}"
    return 0
  fi

  while IFS= read -r TECH;do
    if [[ -n "$TECH" ]] && is_allowed "$TECH"; then
      insert_db_safe "$DOMAIN" "$TECH"
    fi
  done <<< "$TECHS"
}

export -f process_domain make_api_request is_allowed get_random_ua random_ip insert_db_safe
export GREEN YELLOW CYAN RED NC OUTPUT_DIR DB_FILE LOCK_FILE WHITELIST


main() {
  if [[ "$1" == "--clean" ]]; then
    echo -e "${YELLOW}Cleaning old database and lock file...${NC}"
    rm -f "$DB_FILE"
    rm -f "$LOCK_FILE"
    echo -e "${GREEN}Database cleaned. You can run your scan now.${NC}"
    exit 0
  fi

  if [[ $# -ne 1 ]]; then
    echo -e "${YELLOW}Usage: $0 <Subdomains-file>${NC}"
    echo -e "${CYAN}Tip: Run '$0 --clean' to clear the database.${NC}"
    exit 1
  fi

  local DOMAIN_FILE="$1"
  if [[ ! -f "$DOMAIN_FILE" ]]; then
    echo -e "${RED}Error: File not found: $DOMAIN_FILE${NC}"
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR"
  touch "$LOCK_FILE"
  init_db

  echo -e "${GREEN}Scanning domains from: ${DOMAIN_FILE} with $MAX_JOBS parallel jobs${NC}"
  while IFS= read -r DOMAIN; do
    DOMAIN="${DOMAIN// /}"
    [[ -z "$DOMAIN" ]] && continue

    process_domain "$DOMAIN" &

    local current_jobs
    current_jobs=$(jobs -p | wc -l)
    if [[ $current_jobs -ge $MAX_JOBS ]]; then
      wait -n
    fi
  done <"$DOMAIN_FILE"
  wait

  echo -e "${GREEN}Scan complete. Summary:${NC}"
  sqlite3 -header -column "$DB_FILE" "SELECT tech, COUNT(DISTINCT domain) AS count FROM results GROUP BY tech ORDER BY count DESC;"
}
main "$@"
