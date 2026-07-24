#!/usr/bin/env bash

# /ips1/blocklists/getnrd.sh

#wget https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/dga30.txt -O "/ips1/blocklists/dga30.txt"
wget https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/gmail_spammers.txt -O "/ips1/blocklists/gmail_spammers.txt"
wget https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/spammers.txt -O "/ips1/blocklists/spammers.txt"
wget https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/ip_blocklist.txt -O "/ips1/blocklists/ip_blocklist.txt"
wget https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/spf_softfail_strict.txt -O "/ips1/blocklists/spf_softfail_strict.txt"
wget https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/backscatter_protection.txt -O "/ips1/blocklists/backscatter_protection.txt"
