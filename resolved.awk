# Parse `resolvectl status` into one TSV line per link:
#   link <TAB> current-dns-server <TAB> default-route(yes|no) <TAB> domains
# Domains are ";"-separated. Routing-only domains ("~example.com") are kept,
# with the "~" stripped, because they are how split DNS is usually set up
# (e.g. a LAN domain on Wi-Fi while a VPN holds "~."). Dropped: the catch-all
# "~." (the default-route column already says that) and reverse-lookup zones
# (*.arpa; Tailscale alone adds ~65 of them), plus duplicates.

function adddoms(   i, d) {
  for (i = 1; i <= NF; i++) {
    d = $i
    sub(/^~/, "", d)
    if (d == "." || d == "" || d ~ /\.arpa\.?$/ || index(";" doms ";", ";" d ";")) continue
    doms = doms (doms == "" ? "" : ";") d
  }
}

function emit() { printf "%s\t%s\t%s\t%s\n", link, server, def, doms }

/^Link [0-9]+ \(/ {
  if (link != "") emit()
  link = $3; gsub(/[()]/, "", link)
  server = ""; def = "no"; doms = ""; indom = 0
  next
}
/^Global/ { if (link != "") emit(); link = ""; next }
link == "" { next }
/DNS Domain:/ { indom = 1; sub(/.*DNS Domain:/, ""); adddoms(); next }
/^ *[A-Za-z ]+:/ { indom = 0 }
indom { adddoms(); next }
/Current DNS Server:/ { server = $NF }
/Default Route:/ { def = $NF }

END { if (link != "") emit() }
