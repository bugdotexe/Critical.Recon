### Scraping Subdomains from certificates

```
cert() {
DOMAIN=$1
sed -ne 's/^\( *\)Subject:/\1/p;/X509v3 Subject Alternative Name/{
N;s/^.*\n//;:a;s/^\( *\)\(.*\), /\1\2\n\1/;ta;p;q; }' < <(
openssl x509 -noout -text -in <(
openssl s_client -ign_eof 2>/dev/null <<<$'HEAD / HTTP/1.0\r\n\r' \
-connect $domain:443 ) ) | grep -Po '((http|https):\/\/)?(([\w.-]*)\.([\w]*)\.([A-z]))\w+'
}
```
### Scraping subdomains from crt.sh
```
crtsh1() {
domain=$1
org=$(whois $domain | grep "Registrant Organization" | cut -d " " -f3,4,5,6,7)
certOrg=$(echo $org | sed "s/ /%20/g")
agent="Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.85 Safari/537.36"

curl -s -A $agent "https://crt.sh/?O=$domain&output=json" | jq -r ".[].common_name"
curl -s -A $agent "https://crt.sh/?O=$certOrg&output=json" | jq -r ".[].common_name"
}
```
```
crtsh2() {
domain=$1
CleanResults() {
    sed 's/\\n/\n/g' | \
    sed 's/\*.//g' | \
    sed -r 's/([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4})//g' | \
    sort | uniq
}
response=$(curl -s "https://crt.sh?q=%.${domain}&output=json")
results=$(echo "$response" | jq -r ".[].common_name,.[].name_value" | CleanResults)
}
```
