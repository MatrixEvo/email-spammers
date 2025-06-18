#!/usr/bin/env bash

# /ips1/blocklists/getnrd.sh

wget https://raw.githubusercontent.com/xRuffKez/NRD/refs/heads/main/lists/14-day_phishing/domains-only/nrd-phishing-14day.txt -O "/ips1/blocklists/nrd-phishing-14day.txt"
wget https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/gmail_spammers.txt -O "/ips1/blocklists/gmail_spammers.txt"
wget https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/spammers.txt -O "/ips1/blocklists/spammers.txt"
wget https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/ip_blocklist.txt -O "/ips1/blocklists/ip_blocklist.txt"
