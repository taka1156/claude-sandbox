#!/usr/bin/env bash
# Egress allowlist firewall for the dev container. Runs as root via sudo (postStartCommand).
# Fails closed: everything is resolved BEFORE rules are flushed, and DROP policies are set first,
# so a failure midway never leaves the container with open egress.
set -euo pipefail
IFS=$'\n\t'

ALLOWED_DOMAINS=(
  api.anthropic.com
  statsig.anthropic.com
  sentry.io
  claude.ai
  registry.npmjs.org
  marketplace.visualstudio.com
  vscode.blob.core.windows.net
  update.code.visualstudio.com
)

# ---- 1. Resolve everything up front (no rule changes yet) ----
gh_meta="$(curl -fsS --connect-timeout 10 https://api.github.com/meta)"
mapfile -t GH_CIDRS < <(jq -r '(.web + .api + .git)[]' <<<"$gh_meta" | grep -v ':' | sort -u)
[[ ${#GH_CIDRS[@]} -gt 0 ]] || { echo "ERROR: no GitHub IPv4 ranges" >&2; exit 1; }

DOMAIN_IPS=()
for d in "${ALLOWED_DOMAINS[@]}"; do
  mapfile -t ips < <(dig +short A "$d" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
  [[ ${#ips[@]} -gt 0 ]] || { echo "ERROR: failed to resolve $d" >&2; exit 1; }
  DOMAIN_IPS+=("${ips[@]}")
done

HOST_IP="$(ip route | awk '/default/ {print $3; exit}')"
[[ -n "$HOST_IP" ]] || { echo "ERROR: host IP not found" >&2; exit 1; }
HOST_NET="${HOST_IP%.*}.0/24"

DOCKER_DNS_RULES="$(iptables-save -t nat | grep '127\.0\.0\.11' || true)"

# ---- 2. Close first ----
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
ip6tables -P INPUT DROP   2>/dev/null || true
ip6tables -P FORWARD DROP 2>/dev/null || true
ip6tables -P OUTPUT DROP  2>/dev/null || true

# ---- 3. Rebuild rules ----
iptables -F; iptables -X
iptables -t nat -F; iptables -t nat -X
iptables -t mangle -F; iptables -t mangle -X
ip6tables -F 2>/dev/null || true
ipset destroy allowed-hosts 2>/dev/null || true

# Restore Docker embedded DNS (127.0.0.11) NAT rules
if [[ -n "$DOCKER_DNS_RULES" ]]; then
  iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
  iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
  while IFS= read -r rule; do
    eval "iptables -t nat $rule"
  done <<<"$DOCKER_DNS_RULES"
fi

# loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT  2>/dev/null || true
ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

# established
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# host network (VS Code server / port forwarding)
iptables -A INPUT  -s "$HOST_NET" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NET" -j ACCEPT

# allowlist
ipset create allowed-hosts hash:net
for c in "${GH_CIDRS[@]}";   do ipset add -exist allowed-hosts "$c"; done
for i in "${DOMAIN_IPS[@]}"; do ipset add -exist allowed-hosts "$i"; done
iptables -A OUTPUT -m set --match-set allowed-hosts dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# ---- 4. Verify ----
if curl -fsS --connect-timeout 5 https://example.com >/dev/null 2>&1; then
  echo "ERROR: firewall check failed - example.com is reachable" >&2; exit 1
fi
curl -fsS --connect-timeout 5 https://api.github.com/zen >/dev/null \
  || { echo "ERROR: firewall check failed - api.github.com unreachable" >&2; exit 1; }
echo "Firewall configured: ${#GH_CIDRS[@]} GitHub ranges + ${#ALLOWED_DOMAINS[@]} domains allowed"
