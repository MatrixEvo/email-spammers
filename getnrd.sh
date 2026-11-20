#!/usr/bin/env bash

# /ips1/blocklists/getnrd.sh

#DEST_DIR="/ips1/blocklists"
DEST_DIR="/mnt/c/Users/8067-C1908/Documents/code/scripts/Proxmox/pmg/blocklist"
TMP_DIR="/tmp"

# Function to download and replace files safely
update_blocklist() {
    local url="$1"
    local filename="$2"
    local tmp_file="$TMP_DIR/$filename"
    local dest_file="$DEST_DIR/$filename"

    # Download the file to the temporary directory
    # -q stops the output. -O sets the output file.
    if wget -q "$url" -O "$tmp_file"; then

        # Check if the file size is greater than zero
        if [ -s "$tmp_file" ]; then
            # Replace the old file with the new file
            mv "$tmp_file" "$dest_file"
            echo "Success: The system updated $filename."
        else
            echo "Error: The downloaded file $filename is empty. The system did not replace the file."
            rm -f "$tmp_file"
        fi
    else
        echo "Error: The system could not download $filename."
        rm -f "$tmp_file"
    fi
}

# The system will process each blocklist file
update_blocklist "https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/gmail_spammers.txt" "gmail_spammers.txt"
update_blocklist "https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/spammers.txt" "spammers.txt"
update_blocklist "https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/ip_blocklist.txt" "ip_blocklist.txt"
update_blocklist "https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/spf_softfail_strict.txt" "spf_softfail_strict.txt"
update_blocklist "https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/backscatter_protection.txt" "backscatter_protection.txt"
update_blocklist "https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/url_blocklist.txt" "url_blocklist.txt"
