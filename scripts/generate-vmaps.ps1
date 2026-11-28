# Generates every per-platform VMAP file from the one cadence defined here.
#
#   powershell -NoProfile -File scripts/generate-vmaps.ps1                        # mobile 10 min, TV 15 min
#   powershell -NoProfile -File scripts/generate-vmaps.ps1 -IntervalMobileMin 5 -IntervalTvMin 10
#   powershell -NoProfile -File scripts/generate-vmaps.ps1 -MaxHours 24
#
# Output (project root, then copy to inoxtv-config):
#   vmap-mobile.xml        release, mobile ad unit,  plain description_url
#   vmap-tv.xml            release, TV ad unit,       encoded description_url, TV interval
#   vmap-tv-npa.xml        release, TV ad unit,       identical schedule to vmap-tv.xml, npa=1
#   vmap-mobile-test.xml   debug,   Google sample tag only (never this account)
#   vmap-tv-test.xml       debug,   Google sample tag only (never this account)
#
# IMA schedules only breaks whose timeOffset <= the content duration, so one file serves any
# title length; MaxHours is the ceiling (24h = 144 mid-rolls at 10 min, 96 at 15 min).
# The interval is a SERVER-side value: edit it here, regenerate, push - no app release.
# Never edit the generated XML by hand: the live and NPA schedules must not drift apart.
[CmdletBinding()]
param(
    [int]$IntervalMobileMin = 10,
    [int]$IntervalTvMin = 10,
    [int]$MaxHours = 24,
    [string]$OutDir = "./"
)

$ErrorActionPreference = 'Stop'

# plain sizes only: the ad-tag URL rejects the "v" suffix ("size not available");
# Ad Manager matches plain sizes against the line item's 400x300v/640x480v itself.
$SZ_MOBILE = '400x300%7C640x480%7C1280x720%7C1920x1080'
$SZ_TV     = '400x300%7C640x480%7C1280x720%7C1920x1080'
$DESC_MOBILE = 'https://inoxtv.com/watch/movies-and-shows/'
$DESC_TV     = 'https%3A%2F%2Finoxtv.com%2Fwatch%2Fmovies-and-shows%2F'
$TEST_TAG = 'https://pubads.g.doubleclick.net/gampad/ads?sz=640x480&iu=/124319096/external/single_ad_samples&ciu_szs=300x250&impl=s&gdfp_req=1&env=vp&output=vast&unviewed_position_start=1&cust_params=deployment%3Ddevsite%26sample_ct%3Dlinear&correlator='

function Get-MobTag([string]$vpos) {
    "https://pubads.g.doubleclick.net/gampad/ads?iu=/22853635592/VideoAds/VideoAdsMobile&description_url=$DESC_MOBILE&tfcd=0&npa=0&sz=$SZ_MOBILE&gdfp_req=1&unviewed_position_start=1&output=vast&env=vp&impl=s&plcmt=1&vpmute=0&vpa=auto&vpos=$vpos&correlator="
}
function Get-TvTag([string]$vpos, [string]$npa) {
    "https://pubads.g.doubleclick.net/gampad/ads?iu=/22853635592/VideoAds/videoadstv&description_url=$DESC_TV&tfcd=0&npa=$npa&sz=$SZ_TV&gdfp_req=1&unviewed_position_start=1&output=vast&env=vp&impl=s&plcmt=1&vpmute=0&vpa=auto&vpos=$vpos&correlator="
}

function Get-BreakXml([string]$offset, [string]$id, [string]$mode, [string]$vpos) {
    switch ($mode) {
        'mob'   { $tag = Get-MobTag $vpos }
        'tv'    { $tag = Get-TvTag $vpos '0' }
        'tvnpa' { $tag = Get-TvTag $vpos '1' }
        'test'  { $tag = $TEST_TAG }
    }
    @"

  <vmap:AdBreak timeOffset="$offset" breakType="linear" breakId="$id">
    <vmap:AdSource id="$id-ad" allowMultipleAds="true" followRedirects="true">
      <vmap:AdTagURI templateType="vast3"><![CDATA[$tag]]></vmap:AdTagURI>
    </vmap:AdSource>
  </vmap:AdBreak>
"@
}

function New-Vmap([string]$file, [string]$mode, [int]$stepMin) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<!--')
    [void]$sb.AppendLine("  InoxTV VMAP ad-rules document (per-platform). Pre-roll plus a mid-roll every $stepMin minutes")
    [void]$sb.AppendLine("  up to ${MaxHours}h. Change the cadence in scripts/generate-vmaps.ps1 and re-push this file:")
    [void]$sb.AppendLine('  the server holds the schedule, so no app release is ever needed for it.')
    [void]$sb.AppendLine('  Every AdTagURI carries impl=s, plcmt=1, vpmute=0, vpa=auto, vpos and a per-platform')
    [void]$sb.AppendLine('  description_url (plain for mobile, URL-encoded for connected TV), matching the rules the')
    [void]$sb.AppendLine('  app enforces for the live pre-roll tag.')
    [void]$sb.AppendLine('-->')
    [void]$sb.AppendLine('<vmap:VMAP xmlns:vmap="http://www.iab.net/videosuite/vmap" version="1.0">')
    [void]$sb.Append((Get-BreakXml 'start' 'preroll' $mode 'preroll'))
    $count = 0
    $total = [int]($MaxHours * 60 / $stepMin)
    for ($i = 1; $i -le $total; $i++) {
        $mins = $i * $stepMin
        $ts = '{0:D2}:{1:D2}:00' -f [int]($mins / 60), ($mins % 60)
        [void]$sb.Append((Get-BreakXml $ts "midroll-$i" $mode 'midroll'))
        $count++
    }
    [void]$sb.AppendLine('</vmap:VMAP>')
    [System.IO.File]::WriteAllText("$OutDir/$file", $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    Write-Host "wrote $file  (1 pre-roll + $count mid-rolls, every ${stepMin} min)"
}

Write-Host "mobile interval: ${IntervalMobileMin} min | TV interval: ${IntervalTvMin} min | ceiling: ${MaxHours}h"
New-Vmap 'vmap-mobile.xml'      'mob'   $IntervalMobileMin
New-Vmap 'vmap-tv.xml'          'tv'    $IntervalTvMin
New-Vmap 'vmap-tv-npa.xml'      'tvnpa' $IntervalTvMin
New-Vmap 'vmap-mobile-test.xml' 'test'  $IntervalMobileMin
New-Vmap 'vmap-tv-test.xml'     'test'  $IntervalTvMin
Write-Host 'done. copy the five files to inoxtv-config and push.'
