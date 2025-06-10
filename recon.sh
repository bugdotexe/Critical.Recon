#!/bin/bash

while [[ -n $1 ]];do                                                                                case $1 in
-d|--domain)
domain=$2
shift
;;
-o|--org)
org="$2"
shift
;;
-h|--help)
USAGE
shift
;;
esac
shift
done

mkdir -p Income/$domain
mkdir -p Income/$domain/.tmp
mkdir -p Income/$domain/.info
mkdir -p Income/$domain/subs

resolvers="${HOME}/dns-resolvers.txt"
subdomains="${HOME}/subdomains-top1million-5000.txt"


output=Income/$domain
tmp=Income/$domain/.tmp
info=Income/$domain/.info
subs=Income/$domain/subs

Reverse_DNS () {

ips=$(dig +short A "$domain" | paste -sd "|" -)
email=$(whois "$domain" | grep "Registrant Email" | grep -Eo "[[:graph:]]+@[[:graph:]]+")
org=$(whois "$domain" | grep "Registrant Organization" | cut -d ":" -f 2- | sed 's/^ *//')
for ip in $(dig +short A "$domain"); do
  asn_result=$(whois -h whois.cymru.com "$ip" | awk '$1 ~ /^[0-9]+$/ {print "AS"$1}')

  echo "$asn_result" | anew $tmp/asn.txt
  echo "[-] ASN Enumeration : Finished"
done
  echo "https://$domain" | favfreak --shodan -o $info/favihash.txt >> /dev/null
  echo "[-] FaviconHash Enumeration : Finished"

cat $tmp/asn.txt | sort -u | anew $info/asn.txt

for asn in $(cat $info/asn.txt);do
cidr_result=$(whois -h whois.radb.net  -- "-i origin $asn" | grep -Eo "([0-9.]+){4}/[0-9]+" | uniq -u)
echo "$cidr_result" | anew $tmp/cidr.txt
done
echo "[-] CIDR Enumeration : Finished"
cat $tmp/cidr.txt | sort -u | anew $info/cidr.txt
echo "[-] PTR Record Enumeration : Finished"
cat $info/cidr.txt | mapcidr -silent | dnsx -ptr -resp-only -r $resolvers -o $info/ptr.txt

}

Reverse_DNS

Passive_Enum () {
subfinder -exclude-sources digitorus -silent -d "$domain" -o "$subs/subfinder.subs"
    assetfinder -subs-only "$domain" | anew "$subs/assetfinder.subs"
    sublist3r -d "$domain" -o "$subs/sublist3r.subs" >> /dev/null
    findomain -r -q -t "$domain" | anew "$subs/findomain.subs"
    cert-subs "$domain" | anew "$subs/cert.subs"
    dnsx -silent -r "$resolvers" -w "$subdomains" -d "$domain" | anew "$subs/dnsx.subs"
    crtsh "$domain" | anew "$subs/crtsh.subs"
    amass enum -active -alts -d "$domain" -o "$subs/amass.tmp"

    # Process Amass output
    awk '/FQDN/{print $1}' "$subs/amass.tmp" | sort -u | tee "$subs/amass.subs"
    gitlab-subdomains -t gpt -d $domain | anew $subs/gitlab.subs
    github-subdomains -t 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,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 -d $domain --raw -o $subs/github.subs


    cat $subs/*.subs | sort -u | anew $subs/passive.subs
echo "[-] Passive Subdomains Enumeration : Finished"
}


Active_Enum () {

gotator -sub $subs/passive.subs -perm $subdomains -depth 1 -numbers 10 -mindup -adv -md -silent | sort -u | anew $subs/gotator.subs
puredns resolve $subs/gotator.subs -r $resolvers -q | anew $subs/puredns.subs

cat $subs/gotator.subs $subs/puredns.subs | sort -u | anew $subs/active.subs
echo "[-] Active Subdomains Enumeration : Finished"
}

Probe_Subs () {

cat $subs/passive.subs $subs/active.subs | sort -u | httpx -random-agent -fr -retries 3 -r $resolvers -silent -no-color | anew $subs/httpx.probe

}

Passive_Enum
Active_Enum
Probe_Subs
