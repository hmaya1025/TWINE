#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root to configure the Twine Nginx site and Certbot." >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
available=/etc/nginx/sites-available/twineprotein.com
enabled=/etc/nginx/sites-enabled/twineprotein.com
certificate=/etc/letsencrypt/live/twineprotein.com/fullchain.pem
private_key=/etc/letsencrypt/live/twineprotein.com/privkey.pem
webroot=/var/www/letsencrypt
marker='Managed by Twine deployment'
expected_ipv4=177.7.57.250

for command in nginx certbot systemctl curl getent; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

if [[ -e "$available" ]] && ! grep -Fq "$marker" "$available"; then
  echo "Refusing to replace unmanaged Nginx config: $available" >&2
  exit 1
fi
if [[ -e "$enabled" || -L "$enabled" ]]; then
  if [[ ! -L "$enabled" ]] || [[ "$(readlink -f "$enabled")" != "$available" ]]; then
    echo "Refusing to replace unmanaged Nginx site link: $enabled" >&2
    exit 1
  fi
fi

active_configs="$(nginx -T 2>/dev/null | awk '
  /^# configuration file / { file = $4; sub(/:$/, "", file) }
  /server_name[^;]*twineprotein[.]com/ { print file }
' | sort -u || true)"
while IFS= read -r config; do
  [[ -z "$config" ]] && continue
  if [[ "$config" != "$enabled" && "$config" != "$available" ]]; then
    echo "Refusing to overlap an existing Twine host in $config" >&2
    exit 1
  fi
done <<< "$active_configs"

for domain in twineprotein.com www.twineprotein.com; do
  mapfile -t addresses < <(getent ahostsv4 "$domain" | awk '{ print $1 }' | sort -u)
  if [[ "${#addresses[@]}" -ne 1 || "${addresses[0]}" != "$expected_ipv4" ]]; then
    printf 'DNS for %s must resolve only to %s before TLS setup; got: %s\n' \
      "$domain" "$expected_ipv4" "${addresses[*]:-(no IPv4 records)}" >&2
    exit 1
  fi
done

mkdir -p "$webroot"
chmod 0755 "$webroot"
if [[ -s "$certificate" && -s "$private_key" ]]; then
  desired_config="$script_dir/nginx-domain.conf"
  needs_certificate=false
else
  desired_config="$script_dir/nginx-domain-bootstrap.conf"
  needs_certificate=true
fi

install_config() {
  local source="$1"
  local backup=''
  local created_link=false

  if [[ -f "$available" ]]; then
    backup="$(mktemp)"
    cp -p "$available" "$backup"
  fi
  install -m 0644 "$source" "$available.tmp"
  mv -f "$available.tmp" "$available"
  if [[ ! -e "$enabled" && ! -L "$enabled" ]]; then
    ln -s "$available" "$enabled"
    created_link=true
  fi

  if ! nginx -t; then
    if [[ -n "$backup" ]]; then
      mv -f "$backup" "$available"
    else
      rm -f "$available"
    fi
    if [[ "$created_link" == true ]]; then
      rm -f "$enabled"
    fi
    nginx -t || true
    return 1
  fi
  if [[ -n "$backup" ]]; then
    rm -f "$backup"
  fi
  systemctl reload nginx
}

install_config "$desired_config"

if [[ "$needs_certificate" == true ]]; then
  certbot certonly \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    --webroot --webroot-path "$webroot" \
    --cert-name twineprotein.com \
    --domain twineprotein.com \
    --domain www.twineprotein.com

  if [[ ! -s "$certificate" || ! -s "$private_key" ]]; then
    echo "Certbot did not create the expected Twine certificate." >&2
    exit 1
  fi

  install_config "$script_dir/nginx-domain.conf"
  certbot renew --dry-run --cert-name twineprotein.com
fi

hook=/etc/letsencrypt/renewal-hooks/deploy/50-twine-reload-nginx
install -D -m 0755 "$script_dir/reload-nginx-after-renewal.sh" "$hook"
systemctl enable --now certbot.timer

nginx -t
systemctl reload nginx
curl --fail --silent --show-error --resolve twineprotein.com:443:127.0.0.1 \
  https://twineprotein.com/health
printf '\nTwine TLS site is configured.\n'
