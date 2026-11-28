#!/bin/bash
# Generates every per-platform VMAP file from the one cadence defined here.
#
#   bash scripts/generate-vmaps.sh                       # defaults: mobile 10 min, TV 10 min
#   bash scripts/generate-vmaps.sh --interval-mobile 5 --interval-tv 10
#   bash scripts/generate-vmaps.sh --max-hours 24
#
# Output (project root, then copy to inoxtv-config):
#   vmap-mobile.xml        release, mobile ad unit,  plain description_url, every_N minutes
#   vmap-tv.xml            release, TV ad unit,       encoded description_url, TV interval
#   vmap-tv-npa.xml        release, TV ad unit,       identical schedule to vmap-tv.xml, npa=1
#   vmap-mobile-test.xml   debug,   Google sample tag only (never this account)
#   vmap-tv-test.xml       debug,   Google sample tag only (never this account)
#
# IMA schedules only breaks whose timeOffset <= the content duration, so one file serves any
# title length; --max-hours is the ceiling (24h = 144 mid-rolls at 10 min, 96 at 15 min).
# The interval is a SERVER-side value: edit it here, regenerate, push — no app release.
set -euo pipefail

INTERVAL_MOBILE_MIN=10
INTERVAL_TV_MIN=10
MAX_HOURS=24
OUT_DIR="f:/Projects/Android/inoxtv/app/inoxtv"

while [ $# -gt 0 ]; do
  case "$1" in
    --interval-mobile) INTERVAL_MOBILE_MIN="$2"; shift 2 ;;
    --interval-tv)     INTERVAL_TV_MIN="$2";     shift 2 ;;
    --max-hours)       MAX_HOURS="$2";           shift 2 ;;
    --out-dir)         OUT_DIR="$1";             shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Tag templates ────────────────────────────────────────────────────────────
# plain sizes only: the ad-tag URL rejects the "v" suffix ("size not available");
# Ad Manager matches plain sizes against the line item's 400x300v/640x480v itself.
SZ_MOBILE="400x300%7C640x480%7C1280x720%7C1920x1080"
SZ_TV="400x300%7C640x480%7C1280x720%7C1920x1080"
DESC_MOBILE="https://inoxtv.com/watch/movies-and-shows/"
DESC_TV="https%3A%2F%2Finoxtv.com%2Fwatch%2Fmovies-and-shows%2F"
TEST_TAG="https://pubads.g.doubleclick.net/gampad/ads?sz=640x480&iu=/124319096/external/single_ad_samples&ciu_szs=300x250&impl=s&gdfp_req=1&env=vp&output=vast&unviewed_position_start=1&cust_params=deployment%3Ddevsite%26sample_ct%3Dlinear&correlator="

mob_tag() { echo "https://pubads.g.doubleclick.net/gampad/ads?iu=/22853635592/VideoAds/VideoAdsMobile&description_url=${DESC_MOBILE}&tfcd=0&npa=0&sz=${SZ_MOBILE}&gdfp_req=1&unviewed_position_start=1&output=vast&env=vp&impl=s&plcmt=1&vpmute=0&vpa=auto&vpos=$1&correlator="; }
tv_tag()  { echo "https://pubads.g.doubleclick.net/gampad/ads?iu=/22853635592/VideoAds/videoadstv&description_url=${DESC_TV}&tfcd=0&npa=$2&sz=${SZ_TV}&gdfp_req=1&unviewed_position_start=1&output=vast&env=vp&impl=s&plcmt=1&vpmute=0&vpa=auto&vpos=$1&correlator="; }

emit_break() { # $1=timeOffset $2=breakId $3=mode $4=vpos
  local tag
  case "$3" in
    mob)   tag=$(mob_tag "$4") ;;
    tv)    tag=$(tv_tag "$4" 0) ;;
    tvnpa) tag=$(tv_tag "$4" 1) ;;
    test)  tag="$TEST_TAG" ;;
  esac
  echo ""
  echo "  <vmap:AdBreak timeOffset=\"$1\" breakType=\"linear\" breakId=\"$2\">"
  echo "    <vmap:AdSource id=\"$2-ad\" allowMultipleAds=\"false\" followRedirects=\"true\">"
  echo "      <vmap:AdTagURI templateType=\"vast3\"><![CDATA[$tag]]></vmap:AdTagURI>"
  echo "    </vmap:AdSource>"
  echo "  </vmap:AdBreak>"
}

gen() { # $1=file $2=mode $3=interval-minutes
  local file="$OUT_DIR/$1" mode="$2" step="$3" i ts breaks=0
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!--'
    echo "  InoxTV VMAP ad-rules document (per-platform). Pre-roll plus a mid-roll every ${step} minutes"
    echo "  up to ${MAX_HOURS}h. Change the cadence in scripts/generate-vmaps.sh and re-push this file:"
    echo "  the server holds the schedule, so no app release is ever needed for it."
    echo "  Every AdTagURI carries impl=s, plcmt=1, vpmute=0, vpa=auto, vpos and a per-platform"
    echo "  description_url (plain for mobile, URL-encoded for connected TV), matching the rules the"
    echo "  app enforces for the live pre-roll tag."
    echo '-->'
    echo '<vmap:VMAP xmlns:vmap="http://www.iab.net/videosuite/vmap" version="1.0">'
    emit_break "start" "preroll" "$mode" "preroll"
    for i in $(seq 1 $((MAX_HOURS * 60 / step))); do
      ts=$(printf "%02d:%02d:00" $((i*step/60)) $((i*step%60)))
      emit_break "$ts" "midroll-$i" "$mode" "midroll"
      breaks=$((breaks + 1))
    done
    echo '</vmap:VMAP>'
  } > "$file"
  echo "wrote $1  (1 pre-roll + $breaks mid-rolls, every ${step} min)"
}

echo "mobile interval: ${INTERVAL_MOBILE_MIN} min | TV interval: ${INTERVAL_TV_MIN} min | ceiling: ${MAX_HOURS}h"
gen vmap-mobile.xml       mob   "$INTERVAL_MOBILE_MIN"
gen vmap-tv.xml           tv    "$INTERVAL_TV_MIN"
gen vmap-tv-npa.xml       tvnpa "$INTERVAL_TV_MIN"
gen vmap-mobile-test.xml  test  "$INTERVAL_MOBILE_MIN"
gen vmap-tv-test.xml      test  "$INTERVAL_TV_MIN"
echo "done. copy the five files to inoxtv-config and push."