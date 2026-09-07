#!/bin/bash
# Poster fetch via Wikipedia's own non-free identification images.
#
# The preferred source (TMDB, which gave the other 52 posters their high resolution)
# is currently unreachable from this network: www.themoviedb.org and api.themoviedb.org
# both return 000 while image.tmdb.org still answers, which matches the intermittent
# Indian ISP block on TMDB found earlier. IMDb refuses scripted fetches (0 bytes).
# Wikipedia is reachable, so it is the fallback; its posters are capped at roughly
# 250-400px by non-free policy, so these are softer than the TMDB set.
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p poster
UA="Mozilla/5.0 (Macintosh) mcu-marathon/1.0 (personal)"

fetch() {
  local url="$1" i
  for i in 1 2 3 4; do
    if curl -sfL --max-time 45 -A "$UA" "$url"; then return 0; fi
    sleep $((i * 2))
  done
  return 1
}

IDS=(201 202 203 204 205 206 207 208 209 210 211 212 213)
TITLES=(
  "X-Men (film)" "X2 (film)" "X-Men: The Last Stand" "X-Men Origins: Wolverine"
  "X-Men: First Class" "The Wolverine (film)" "X-Men: Days of Future Past"
  "X-Men: Apocalypse" "Deadpool (film)" "Logan (film)" "Deadpool 2"
  "Dark Phoenix (film)" "The New Mutants (film)"
)

ok=0; missing=()
for i in "${!IDS[@]}"; do
  id="${IDS[$i]}"; title="${TITLES[$i]}"
  [ -f "poster/$id.jpg" ] && { ok=$((ok+1)); continue; }

  enc=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$title")
  # generator=images + imageinfo: pick the non-free (en-local) raster, preferring a
  # filename containing "poster"; Commons-hosted files are logos/icons, not posters.
  url=$(fetch "https://en.wikipedia.org/w/api.php?action=query&format=json&generator=images&titles=$enc&gimlimit=60&prop=imageinfo&iiprop=url|mime&iiurlwidth=600&redirects=1" \
    | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(''); raise SystemExit
cands=[]
for p in d.get('query',{}).get('pages',{}).values():
    ii=(p.get('imageinfo') or [{}])[0]
    u=ii.get('thumburl') or ii.get('url','')
    if '/wikipedia/en/' in u and ii.get('mime') in ('image/jpeg','image/png'):
        cands.append((p.get('title',''), u))
for name,u in cands:
    if 'poster' in name.lower(): print(u); raise SystemExit
print(cands[0][1] if cands else '')" 2>/dev/null)

  if [ -z "$url" ]; then missing+=("$id $title (no poster image)"); continue; fi
  if fetch "$url" > "poster/$id.jpg" && [ -s "poster/$id.jpg" ]; then
    printf '%-5s %-34s %6s KB\n' "$id" "${title:0:32}" "$(( $(wc -c < "poster/$id.jpg") / 1024 ))"
    ok=$((ok+1))
  else
    rm -f "poster/$id.jpg"; missing+=("$id $title (download failed)")
  fi
  sleep 1
done

echo ""
echo "got $ok/${#IDS[@]}"
[ ${#missing[@]} -gt 0 ] && { printf 'MISSING:\n'; printf '  %s\n' "${missing[@]}"; }
exit 0
