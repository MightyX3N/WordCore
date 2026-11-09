#!/usr/bin/env bash
# Local Apache that behaves like a typical cPanel shared host, for testing CGI mode.
#
#   sudo bash tests/apache/setup.sh          # install config (Debian/Ubuntu)
#   sudo bash tests/apache/setup.sh deploy   # copy the current Linux build in and restart
#
# Two sites:  http://127.0.0.1:8085/wctest/  (subfolder install)
#             http://127.0.0.1:8086/         (web root install)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/dist/linux-x86_64/wordcore"

setup() {
  a2enmod -q rewrite cgi >/dev/null 2>&1 || a2enmod -q rewrite cgid >/dev/null
  a2dismod -q mpm_event >/dev/null 2>&1 || true
  a2enmod -q mpm_prefork >/dev/null 2>&1 || true
  cp "$ROOT/tests/apache/wctest.conf" /etc/apache2/sites-available/wctest.conf
  a2ensite -q wctest >/dev/null
  mkdir -p /srv/wc/logs /srv/wc/sub_root /srv/wc/root_root
  apache2ctl configtest
}

install_to() {
  local dir="$1"
  rm -rf "$dir/site"
  mkdir -p "$dir/public"
  cp "$BIN" "$dir/wordcore.cgi"
  chmod 755 "$dir/wordcore.cgi"
  cp "$ROOT/runtime/host/htaccess" "$dir/.htaccess"
  echo "static file" > "$dir/public/hello.txt"
}

deploy() {
  [ -x "$BIN" ] || { echo "build first: python3 runtime/build/build.py linux-x86_64"; exit 1; }
  install_to /srv/wc/sub_root/wctest
  install_to /srv/wc/root_root
  chown -R www-data:www-data /srv/wc/sub_root /srv/wc/root_root
  apache2ctl -k restart 2>/dev/null || apache2ctl start
  for i in $(seq 1 50); do
    curl -s -o /dev/null http://127.0.0.1:8086/ && break
    sleep 0.1
  done
}

case "${1:-setup}" in
  setup) setup ;;
  deploy) deploy ;;
  *) echo "usage: $0 [setup|deploy]"; exit 2 ;;
esac
