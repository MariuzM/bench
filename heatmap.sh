#!/usr/bin/env bash
#
# Turns bench.sh's table output into a color-coded heatmap.html (no
# dependencies, opens in any browser). Each row is normalized independently and
# shaded green (best) -> yellow -> red (>=4x the row's best), so you can see at a
# glance who wins each benchmark and by how much.
#
# Usage:
#   ./bench.sh > results.txt && ./heatmap.sh results.txt   # from a saved run
#   ./bench.sh | ./heatmap.sh                              # straight from a pipe
#
# Output path defaults to ./heatmap.html; override with HEATMAP_OUT=foo.html.

set -euo pipefail
OUT="${HEATMAP_OUT:-heatmap.html}"

awk -v out="$OUT" '
function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
# lower-is-better: best is the row min, color by value/best (capped at 4x).
function color_low(v,best,   r,f){
  if(best+0<=0 || v+0<=0 || v=="n/a") return "hsl(0,0%,88%)";
  r=v/best; if(r<1)r=1; f=log(r)/log(2)/2; if(f>1)f=1; if(f<0)f=0;
  return sprintf("hsl(%d,72%%,80%%)",120*(1-f));
}
# higher-is-better: best is the row max, color by best/value.
function color_high(v,best,  r,f){
  if(best+0<=0 || v+0<=0 || v=="n/a") return "hsl(0,0%,88%)";
  r=best/v; if(r<1)r=1; f=log(r)/log(2)/2; if(f>1)f=1; if(f<0)f=0;
  return sprintf("hsl(%d,72%%,80%%)",120*(1-f));
}
/====+ *TIME/   { sec="time"; next }
/RASTER FPS/    { sec="fps";  next }
/====+ *PEAK/   { sec="peak"; next }
/BINARY SIZE/   { sec="meta"; next }
index($0,"|")==0 { next }
{
  n=split($0, a, "|"); for(i=1;i<=n;i++) a[i]=trim(a[i]);
  name=a[1];
  if(name=="benchmark"){ if(nl==0){ for(i=2;i<n;i++) langs[++nl]=a[i] } next }
  if(name=="") next;
  if(sec=="time"){ tn[++tc]=name; for(i=1;i<=nl;i++) tv[name,i]=a[i+1] }
  else if(sec=="peak"){ pn[++pc]=name; for(i=1;i<=nl;i++) pv[name,i]=a[i+1] }
  else if(sec=="fps"){ for(i=1;i<=nl;i++) fv[i]=a[i+1]; havef=1 }
  else if(sec=="meta"){ mn[++mc]=name; for(i=1;i<=nl;i++) mv[name,i]=a[i+1] }
}
END{
  print "<!doctype html><html><head><meta charset=utf-8>" > out;
  print "<title>benchmark heatmap</title><style>" > out;
  print "body{font-family:sans-serif;padding:24px;color:#222}" > out;
  print "h1{font-size:20px} h2{font-size:15px;margin:22px 0 6px}" > out;
  print "table{border-collapse:collapse;font:12px ui-monospace,Menlo,monospace}" > out;
  print "td,th{border:1px solid #ddd;padding:4px 9px;text-align:center}" > out;
  print "th{background:#fafafa} td.b{text-align:left;font-weight:600;background:#f6f6f6}" > out;
  print ".legend{display:flex;align-items:center;gap:8px;margin:8px 0 18px;font:12px sans-serif}" > out;
  print ".bar{width:240px;height:14px;border:1px solid #ccc;background:linear-gradient(90deg,hsl(120,72%,80%),hsl(60,72%,80%),hsl(0,72%,80%))}" > out;
  print "</style></head><body>" > out;
  print "<h1>Benchmark heatmap</h1>" > out;
  print "<div class=legend><span>fastest / leanest</span><div class=bar></div><span>&ge;4&times; the row best</span></div>" > out;

  # --- TIME (lower better) ---
  print "<h2>Wall-clock time (s) &mdash; lower is better</h2><table><tr><th>benchmark</th>" > out;
  for(i=1;i<=nl;i++) printf "<th>%s</th>", langs[i] > out;
  print "</tr>" > out;
  for(t=1;t<=tc;t++){ r=tn[t]; best="";
    for(i=1;i<=nl;i++){ v=tv[r,i]; if(v=="n/a")continue; if(best==""||v+0<best+0)best=v }
    printf "<tr><td class=b>%s</td>", r > out;
    for(i=1;i<=nl;i++){ v=tv[r,i]; printf "<td style=\"background:%s\">%s</td>", color_low(v,best), v > out }
    print "</tr>" > out;
  }
  print "</table>" > out;

  # --- RASTER FPS (higher better) ---
  if(havef){
    print "<h2>Rasterizer throughput (frames/s) &mdash; higher is better</h2><table><tr><th>metric</th>" > out;
    for(i=1;i<=nl;i++) printf "<th>%s</th>", langs[i] > out;
    print "</tr><tr><td class=b>raster fps</td>" > out;
    best=""; for(i=1;i<=nl;i++){ v=fv[i]; if(v=="n/a")continue; if(best==""||v+0>best+0)best=v }
    for(i=1;i<=nl;i++){ v=fv[i]; printf "<td style=\"background:%s\">%s</td>", color_high(v,best), v > out }
    print "</tr></table>" > out;
  }

  # --- PEAK (lower better) ---
  print "<h2>Peak memory (MB) &mdash; lower is better</h2><table><tr><th>benchmark</th>" > out;
  for(i=1;i<=nl;i++) printf "<th>%s</th>", langs[i] > out;
  print "</tr>" > out;
  for(t=1;t<=pc;t++){ r=pn[t]; best="";
    for(i=1;i<=nl;i++){ v=pv[r,i]; if(v=="n/a")continue; if(best==""||v+0<best+0)best=v }
    printf "<tr><td class=b>%s</td>", r > out;
    for(i=1;i<=nl;i++){ v=pv[r,i]; printf "<td style=\"background:%s\">%s</td>", color_low(v,best), v > out }
    print "</tr>" > out;
  }
  print "</table>" > out;

  # --- meta: binary size / compile / SLOC (lower better) ---
  if(mc>0){
    print "<h2>Binary size / compile time / source size &mdash; lower is better</h2><table><tr><th>metric</th>" > out;
    for(i=1;i<=nl;i++) printf "<th>%s</th>", langs[i] > out;
    print "</tr>" > out;
    for(t=1;t<=mc;t++){ r=mn[t]; best="";
      for(i=1;i<=nl;i++){ v=mv[r,i]; if(v=="n/a")continue; if(best==""||v+0<best+0)best=v }
      printf "<tr><td class=b>%s</td>", r > out;
      for(i=1;i<=nl;i++){ v=mv[r,i]; printf "<td style=\"background:%s\">%s</td>", color_low(v,best), v > out }
      print "</tr>" > out;
    }
    print "</table>" > out;
  }
  print "</body></html>" > out;
}
' "${1:-/dev/stdin}"

echo "Wrote $OUT"
