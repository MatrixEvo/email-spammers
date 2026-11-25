# PMG Custom Blocklists (`/ips1/blocklists/`)

Blocklists synced to Proxmox Mail Gateway nodes from `https://github.com/MatrixEvo/email-spammers` via `get.sh` and consumed by `/ips1/pmg-custom-check` (`pmg-custom-check-feb2025.sh`).

---

## Universal Syntax & Comment Rules

All **6** blocklist files are processed by `sanitize_list_file()` before matching:

- **Full-line comments:** Lines starting with `#` (with or without leading spaces) are ignored.
- **Inline comments:** Anything from whitespace + `#` to end of line (`entry # reason`) is stripped cleanly.
- **Whitespace & line endings:** Leading/trailing spaces, tabs, blank lines, and Windows CRLF (`\r\n`) are automatically stripped.
- **Case sensitivity:** All domain, email, and URL matches are **case-insensitive**.
- **Missing or comments-only files:** Safely treated as no-match (never crash the mail filter).

> **Note for older PMG nodes:** When adding `#` comments to `ip_blocklist.txt`, avoid writing real IPv4 addresses inside comments until all PMG nodes are running the updated `pmg-custom-check-feb2025.sh` (older scripts ran plain `grep -q` without stripping `#`).

---

## Blocklist Files Reference

### 1. `spammers.txt`
- **Action:** `VIRUS: manual_blocklist`
- **Matching mode:** Case-insensitive Extended Regular Expression (ERE):
  - **Entries WITHOUT `@`** match **domains only** (`smtp_sender_domain_name`, `header_from_domain`, `reply_to_domain`) using `^(.+\.)?(entry)$` — so adding `dldel.com` **automatically blocks both `dldel.com` and any subdomain (`*.dldel.com`, `a.b.dldel.com`)** without needing a second `.*\.dldel.com` line, and will *not* match unrelated domains like `notdldel.com` or email addresses like `test@example.com`.
  - **Entries WITH `@`** match **full email addresses** (`smtp_sender`, `header_from_email`, `reply_to_email`) using `^(entry)$`.
- **Valid examples:**
  ```text
  # Blocks dldel.com AND all subdomains (*.dldel.com) automatically
  dldel.com

  # Blocks mail.hellosign.com and *.mail.hellosign.com (NOT hellosign.com)
  mail.hellosign.com

  # Entire abused TLD
  .*\.top

  # Numbered spam domain series
  export[0-9]+.com

  # Specific sender email or local-part wildcard
  interactivebrokers@.*          # blocks interactivebrokers@any-domain
  FromSMBC@.*
  15009567621@163.com
  ```
- **Avoid:**
  - Adding duplicate `.*\.domain.com` or `sub.domain.com` lines when `domain.com` is already listed (the backend matches subdomains automatically).
  - `marketing@` (anchored as `^marketing@$`, which never matches any real address; use `marketing@specificdomain.com` or `marketing@.*` only if intended globally).

---

### 2. `gmail_spammers.txt`
- **Action:** `VIRUS: manual_gmail_blocklist`
- **Matching mode:** Case-insensitive ERE, full-string anchored (`^(...)$`).
- **Checked against:** Full email addresses only (`smtp_sender`, `header_from_email`).
- **Valid examples:**
  ```text
  lucaspokrovskii[0-9]+@gmail.com
  aimi.mexa@gmail.com            # reported HR spammer
  kaydeli.sz@outlook.com
  ```
- **Avoid:**
  - Bare domains without `@` (e.g., `theguesthousebb.com`) — because this list only matches full email addresses with `^...$`, bare domains will never match here. Put domains in `spammers.txt` instead.

---

### 3. `spf_softfail_strict.txt`
- **Action:** `VIRUS: spf_softfail_phishing` (triggers **only** when `Received-SPF` status is not `pass`).
- **Matching mode:** **Exact literal** case-insensitive match (`grep -Fiqx`, **no regex**).
- **Checked against:** `smtp_sender_domain_name`, `header_from_domain`.
- **Valid examples:**
  ```text
  dhl.com
  maybank.com.my
  maybank2u.com.my
  advising.hsbc.com              # subdomains must be listed explicitly
  sc.com                         # literal match (does NOT match scacom)
  ```
- **Avoid:**
  - Regex syntax (`.*`, `[0-9]+`) — treated as literal text here and will not match.

---

### 4. `ip_blocklist.txt`
- **Action:** `VIRUS: manual_ip_blocklist`
- **Matching mode:** Exact single IPv4 match (`grep -Fqx`) **plus** CIDR subnet matching (`python3 ipaddress` when `/` entries exist).
- **Checked against:** `inbound_ip` extracted from `Received-SPF: client-ip=...`.
- **Valid examples:**
  ```text
  103.253.12.160                 # single IP (does NOT falsely match 103.253.12.16)
  103.253.12.160/29              # CIDR subnet (103.253.12.160 - 103.253.12.167)
  ```
- **Note:** Commenting out `# 103.253.12.160` disables the entry cleanly on updated PMG nodes.

---

### 5. `backscatter_protection.txt`
- **Action:** `VIRUS: backscatter-<domain>` (triggers only on bounce/DSN candidates where the recipient matches `<domain>` and **none** of the listed allowed IPs appear anywhere in the `.eml`).
- **Format:** `<domain> <ip1> [ip2] [ip3] ...` (space-separated).
- **Matching mode:** Boundary-safe `@<domain>` match against `To` / `smtp_to`, and boundary-safe IP search in the raw message (e.g., `118.107.238.162` will not falsely match `118.107.238.1620`, and `ipserverone.com` will not match `ipserverone.com.evil.com`).
- **Valid examples:**
  ```text
  # Format: <domain> <ip1> <ip2> ...
  singmarmarine.com 118.107.238.162
  ipserverone.com 118.107.202.189 210.5.47.28 43.228.247.186 # primary MX IPs
  prupartner.com.my 116.0.121.235 210.5.45.244 210.5.45.242
  ```

---

### 6. `url_blocklist.txt`
- **Action:** `VIRUS: manual_url_blocklist`
- **Matching mode:** Case-insensitive ERE anchored with `^(.+\.)?(entry)$` against **hostnames** extracted from `<a href>` and plain `http(s)://` URLs inside email bodies — so adding `nemaru\.click` automatically blocks `nemaru.click` and all subdomains (`*.nemaru.click`).
- **Purpose:** Confirmed phishing/malware landing domains (kept separate from `spammers.txt` so legitimate sites blocked only as marketing senders, like `linux.com` or `buzzfeed.com`, don't block emails that merely link to them).
- **Valid examples:**
  ```text
  # Confirmed phishing link domains (auto-matches main domain + all subdomains)
  domains\.extenders\.click      # credential phishing (dekwetoydrift.biz)
  nemaru\.click                  # blocks nemaru.click and *.nemaru.click
  ```
- **Avoid:**
  - Including `https://` or URL paths (`/login`) — list **hostnames/domains only**.

---

## Syncing Blocklists (`getnrd.sh` & `update.sh`)

`getnrd.sh` auto-detects its own directory (`DEST_DIR`, e.g. `/ips1/blocklists` on PMG), downloads all 6 files with cache-busting to same-filesystem temp files (`.<file>.tmp.$$`), verifies each file is non-empty and not an HTML error page, and atomically swaps via `mv -f`:

- **Production path on PMG:** `/ips1/blocklists/getnrd.sh` (deploy & run across all 8 PMGs via `./update.sh`)
- **Source repository:** `https://raw.githubusercontent.com/MatrixEvo/email-spammers/refs/heads/main/`
  - `gmail_spammers.txt`
  - `spammers.txt`
  - `ip_blocklist.txt`
  - `spf_softfail_strict.txt`
  - `backscatter_protection.txt`
  - `url_blocklist.txt`
