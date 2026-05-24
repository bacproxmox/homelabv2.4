#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "arr-language-policy"
source /root/homelab-secrets/users.env 2>/dev/null || true
apt update >/dev/null
apt install -y sshpass curl jq >/dev/null
SSH_USER="${BACMASTER_USER:-bacmaster}"; SSH_PASS="${BACMASTER_PASS:-}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
SONARR_URL="http://192.168.50.102:8989"; RADARR_URL="http://192.168.50.102:7878"
key(){ sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@192.168.50.102" "sudo sed -n 's:.*<ApiKey>\\(.*\\)</ApiKey>.*:\\1:p' '$1' | head -n1" | tr -d '\r\n'; }
SONARR_KEY="$(key /opt/homelab/arr/config/sonarr/config.xml)"; RADARR_KEY="$(key /opt/homelab/arr/config/radarr/config.xml)"
api(){ local method="$1" url="$2" key="$3" path="$4" payload="${5:-}" out="$6"; if [[ "$method" == GET ]]; then curl -sS -o "$out" -w '%{http_code}' -H "X-Api-Key: $key" "$url/api/v3$path"; elif [[ "$method" == PUT ]]; then curl -sS -o "$out" -w '%{http_code}' -X PUT -H "X-Api-Key: $key" -H 'Content-Type: application/json' --data "$payload" "$url/api/v3$path"; else curl -sS -o "$out" -w '%{http_code}' -X POST -H "X-Api-Key: $key" -H 'Content-Type: application/json' --data "$payload" "$url/api/v3$path"; fi; }
cf_payload(){ local name="$1" pattern="$2"; jq -n --arg name "$name" --arg pattern "$pattern" '{name:$name,includeCustomFormatWhenRenaming:false,specifications:[{name:$name,implementation:"ReleaseTitleSpecification",implementationName:"Release Title",negate:false,required:false,fields:[{name:"value",value:$pattern}]}]}' ; }
ensure_cf(){ local app="$1" url="$2" key="$3" name="$4" pattern="$5"; api GET "$url" "$key" /customformat '' /tmp/cf-list.json >/tmp/http || true; existing="$(jq -r --arg name "$name" '.[] | select(.name==$name) | .id' /tmp/cf-list.json 2>/dev/null | head -n1)"; if [[ -n "$existing" ]]; then echo "$existing"; return; fi; payload="$(cf_payload "$name" "$pattern")"; http="$(api POST "$url" "$key" /customformat "$payload" /tmp/cf-create.json || true)"; if [[ "$http" =~ ^20[01]$ ]]; then jq -r '.id // empty' /tmp/cf-create.json; else echo "⚠️ $app custom format oluşturulamadı: $name HTTP=$http" >&2; cat /tmp/cf-create.json >&2; echo ""; fi; }
apply_scores(){ local app="$1" url="$2" key="$3" ids_json="$4"; http="$(api GET "$url" "$key" /qualityprofile '' /tmp/qp-list.json || true)"; [[ "$http" == 200 ]] || { echo "⚠️ $app quality profiles okunamadı HTTP=$http"; return 0; }; jq -c '.[]' /tmp/qp-list.json | while read -r qp; do id="$(jq -r '.id' <<<"$qp")"; updated="$(jq --argjson ids "$ids_json" '
    .minFormatScore = 300 |
    .cutoffFormatScore = 1000 |
    .formatItems = ((.formatItems // []) + [
      {format: $ids.turkish, score: 1500},
      {format: $ids.german, score: 1300},
      {format: $ids.english, score: 1000},
      {format: $ids.macedonian, score: 350},
      {format: $ids.albanian, score: 300}
    ] | unique_by(.format))' <<<"$qp")"; http2="$(api PUT "$url" "$key" "/qualityprofile/$id" "$updated" /tmp/qp-put.json || true)"; [[ "$http2" =~ ^20[01]$ ]] && echo "✅ $app quality profile güncellendi: $(jq -r '.name' <<<"$qp")" || echo "⚠️ $app quality profile güncellenemedi id=$id HTTP=$http2"; done; }
configure_app(){ local app="$1" url="$2" key="$3"; echo; echo "🌍 $app dil politikası uygulanıyor..."; [[ -n "$key" ]] || { echo "⚠️ $app API key yok"; return 0; }; tr="$(ensure_cf "$app" "$url" "$key" "LANG Turkish TR" '(?i)(^|[ ._\[-])(turkish|turkce|türkçe|\bTR\b|\bTUR\b)([ ._\]-]|$)')"; de="$(ensure_cf "$app" "$url" "$key" "LANG German DE" '(?i)(^|[ ._\[-])(german|deutsch|\bDE\b|\bGER\b)([ ._\]-]|$)')"; en="$(ensure_cf "$app" "$url" "$key" "LANG English EN" '(?i)(^|[ ._\[-])(english|\bEN\b|\bENG\b)([ ._\]-]|$)')"; mk="$(ensure_cf "$app" "$url" "$key" "LANG Macedonian MK" '(?i)(^|[ ._\[-])(macedonian|\bMK\b|\bMKD\b)([ ._\]-]|$)')"; sq="$(ensure_cf "$app" "$url" "$key" "LANG Albanian SQ" '(?i)(^|[ ._\[-])(albanian|\bSQ\b|\bALB\b)([ ._\]-]|$)')"; if [[ -n "$tr$de$en$mk$sq" ]]; then ids="$(jq -n --argjson turkish "${tr:-0}" --argjson german "${de:-0}" --argjson english "${en:-0}" --argjson macedonian "${mk:-0}" --argjson albanian "${sq:-0}" '{turkish:$turkish,german:$german,english:$english,macedonian:$macedonian,albanian:$albanian}')"; apply_scores "$app" "$url" "$key" "$ids"; else echo "⚠️ $app custom format oluşturulamadı; dil policy atlandı."; fi; }
configure_app Sonarr "$SONARR_URL" "$SONARR_KEY"
configure_app Radarr "$RADARR_URL" "$RADARR_KEY"
echo
cat <<'NOTE'
✅ Dil policy best-effort tamamlandı.
İzin verilen/pozitif diller: Turkish, German, English, Macedonian, Albanian.
Öncelik: Turkish > German > English > Macedonian > Albanian.
Not: Release title dil etiketi içermeyen kaynaklar minFormatScore nedeniyle elenebilir; final run öncesi Sonarr/Radarr Custom Formats ve Quality Profiles UI'da kontrol önerilir.
NOTE
