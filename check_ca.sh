set -euo pipefail
ca='apps/baas/certs/track-binocle-local-ca.pem'
leaf='apps/baas/certs/localhost.pem'
expected_fp="$(openssl x509 -in "$leaf" -noout -fingerprint -sha256 | cut -d= -f2)"
for port in 4322 3001 4000 8787 8000 3002 4100 3003 4200 8200; do
  cert_file="$(mktemp)"
  verify_log="$(mktemp)"
  if ! openssl s_client -connect "127.0.0.1:${port}" -servername localhost -CAfile "$ca" -verify_hostname localhost -verify_return_error </dev/null >"$verify_log" 2>&1; then
    cat "$verify_log"
    rm -f "$cert_file" "$verify_log"
    exit 1
  fi
  openssl x509 -in "$verify_log" -out "$cert_file"
  fp="$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d= -f2)"
  subject="$(openssl x509 -in "$cert_file" -noout -subject | sed 's/^subject=//')"
  issuer="$(openssl x509 -in "$cert_file" -noout -issuer | sed 's/^issuer=//')"
  [[ "$fp" == "$expected_fp" ]]
  printf 'https://localhost:%s certificate-ok fp=%s subject=%s issuer=%s\n' "$port" "$fp" "$subject" "$issuer"
  rm -f "$cert_file" "$verify_log"
done