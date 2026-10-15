#!/usr/bin/env bash
# Writes the directory pages of download.agentuxos.org. R2 serves objects,
# not directories, so each directory gets an index.html listing what the
# bucket holds there; a Cloudflare URL rewrite rule on the zone serves
# <path>/index.html for any <path>/ (see the README's Downloads section).
#
# usage: download-index.sh
#   rebuilds index.html in /, iso/, and every directory under iso/.
# Sourced helpers: the caller exports the AWS_* variables for R2 and
# R2_ACCOUNT_ID, as publish-iso.sh does.
set -euo pipefail

bucket=agentux-downloads
# --only-show-errors is an option of cp, not of ls (which rejects it).
s3() {
    local quiet=(--only-show-errors)
    [[ $1 == ls ]] && quiet=()
    aws s3 --endpoint-url "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" "${quiet[@]}" "$@"
}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# human SIZE_IN_BYTES
human() {
    awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u); i = 1; while (b >= 1000 && i < 5) { b /= 1000; i++ }
        printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i] }'
}

# page PATH TITLE ROWS_FILE: writes $work/page.html. ROWS_FILE has lines
# "kind<TAB>name<TAB>size<TAB>date" (kind dir or file).
page() {
    local path=$1 title=$2 rows=$3 parent=""
    [[ $path != / ]] && parent='<tr><td><a href="../">../</a></td><td></td><td></td></tr>'
    {
        cat <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title · AgentUX downloads</title>
<style>
  :root { color-scheme: dark; --ink: #0b0d10; --mist: #e7eaef; --slate: #949dab; --lime: #c6f36b; --line: #1d2229; }
  body { margin: 0; background: var(--ink); color: var(--mist); font: 15px/1.5 ui-monospace, "Martian Mono", Menlo, Consolas, monospace; }
  main { max-width: 860px; margin: 0 auto; padding: 32px 16px; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  p { color: var(--slate); margin: 0 0 24px; }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 6px 8px; border-bottom: 1px solid var(--line); white-space: nowrap; }
  td:first-child { width: 100%; white-space: normal; word-break: break-all; }
  td + td { color: var(--slate); text-align: right; }
  a { color: var(--lime); text-decoration: none; }
  a:hover { text-decoration: underline; }
</style>
</head>
<body>
<main>
<h1>$title</h1>
<p>AgentUX ISOs, checksums and signatures. Verify a download: <a href="https://github.com/agentux-os/agentux-os#downloads">README</a>.</p>
<table>
$parent
EOF
        while IFS=$'\t' read -r kind name size date; do
            n=$(esc <<<"$name")
            if [[ $kind == dir ]]; then
                echo "<tr><td><a href=\"$n/\">$n/</a></td><td></td><td></td></tr>"
            else
                echo "<tr><td><a href=\"$n\">$n</a></td><td>$(human "$size")</td><td>$date</td></tr>"
            fi
        done <"$rows"
        echo '</table>'
        echo '</main>'
        echo '</body>'
        echo '</html>'
    } >"$work/page.html"
}

# rows PREFIX: lists one level of the bucket under PREFIX ("" or "iso/...")
# as page() rows, directories first, index.html itself left out.
rows() {
    local prefix=$1
    s3 ls "s3://$bucket/$prefix" >"$work/ls" || true
    {
        awk '$1 == "PRE" { sub("/$", "", $2); print "dir\t" $2 }' "$work/ls" | sort -r
        awk '$1 != "PRE" && $4 != "index.html" && $4 != "" { print "file\t" $4 "\t" $3 "\t" $1 }' "$work/ls" | sort
    } >"$work/rows"
}

put() { s3 cp "$work/page.html" "s3://$bucket/$1index.html" --content-type "text/html; charset=utf-8" --cache-control "public, max-age=300"; }

rows ""
page / "download.agentuxos.org" "$work/rows"
put ""

rows "iso/"
page /iso/ "iso/" "$work/rows"
put "iso/"
awk -F'	' '$1 == "dir" { print $2 }' "$work/rows" >"$work/dirs"
while read -r d; do
    rows "iso/$d/"
    page "/iso/$d/" "iso/$d/" "$work/rows"
    put "iso/$d/"
    echo "index: iso/$d/"
done <"$work/dirs"
echo "index: / and iso/"
