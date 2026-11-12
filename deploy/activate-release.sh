#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run release activation as root." >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /opt/twineprotein/releases/<release-id>" >&2
  exit 2
fi

app_root=/opt/twineprotein
release_dir="$(cd -- "$1" && pwd)"
compose_file="$release_dir/deploy/compose.production.yml"
image=twineprotein/frontend:production
release_id="$(basename "$release_dir")"
rollback_tag="twineprotein/frontend:rollback-$release_id"

[[ -f "$compose_file" ]] || { echo "Missing production Compose file: $compose_file" >&2; exit 1; }

compose() {
  docker compose -p twine-production -f "$compose_file" "$@"
}

previous_image_id="$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)"
if [[ -n "$previous_image_id" ]]; then
  docker image tag "$previous_image_id" "$rollback_tag"
fi

restore_previous() {
  echo "Release health check failed; restoring the prior image." >&2
  if [[ -n "$previous_image_id" ]]; then
    docker image tag "$rollback_tag" "$image"
    if [[ -L "$app_root/current" ]]; then
      docker compose -p twine-production \
        -f "$app_root/current/deploy/compose.production.yml" \
        up -d --no-build --wait --wait-timeout 120
    else
      compose up -d --no-build --wait --wait-timeout 120
    fi
  else
    compose down --remove-orphans
  fi
}

if ! compose up -d --build --wait --wait-timeout 120; then
  restore_previous || true
  exit 1
fi

if ! curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8081/health; then
  restore_previous || true
  exit 1
fi
printf '\n'

if [[ -L "$app_root/current" ]]; then
  previous_release="$(readlink -f "$app_root/current")"
  ln -sfn "$previous_release" "$app_root/previous.next"
  mv -Tf "$app_root/previous.next" "$app_root/previous"
fi
ln -sfn "$release_dir" "$app_root/current.next"
mv -Tf "$app_root/current.next" "$app_root/current"

echo "Activated Twine release $release_id."
