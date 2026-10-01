.pragma library

// Pure helpers for the local.nmstatus widget. Kept free of QML types so they
// can be exercised with plain node.

var vpnTypes = ["wireguard", "vpn", "tun"]

function isVpn(profile) {
  return !!profile && vpnTypes.indexOf(profile.type) !== -1
}

function parse(text) {
  try {
    var state = JSON.parse(text)
    if (!state || !Array.isArray(state.profiles)) return null
    return state
  } catch (e) {
    return null
  }
}

function vpnProfiles(state) {
  if (!state) return []
  return state.profiles.filter(isVpn).sort(function(a, b) {
    if (a.active !== b.active) return a.active ? -1 : 1
    return a.name.localeCompare(b.name)
  })
}

// VPNs NetworkManager runs itself. Tunnels another program owns (e.g.
// tailscale0, "connected (externally)") are listed but read-only, and don't
// count as "VPN up": they usually only carry their own private network.
function activeVpns(state) {
  return vpnProfiles(state).filter(function(p) { return p.active && !p.external })
}

function externalTunnels(state) {
  return vpnProfiles(state).filter(function(p) { return p.active && p.external })
}

function otherConnections(state) {
  if (!state) return []
  return state.profiles.filter(function(p) { return !isVpn(p) && p.active })
}

var typeLabels = {
  "802-11-wireless": "Wi-Fi",
  "802-3-ethernet": "Ethernet",
  "wireguard": "WireGuard",
  "vpn": "VPN",
  "tun": "Tunnel",
  "bridge": "Bridge",
  "bond": "Bond",
  "vlan": "VLAN",
  "gsm": "Mobile",
  "bluetooth": "Bluetooth"
}

function typeLabel(profile) {
  if (!profile) return ""
  if (profile.type === "vpn" && profile.serviceType) return profile.serviceType
  return typeLabels[profile.type] || profile.type
}

var connectivityBad = ["limited", "portal", "none"]

function connectivityOk(state) {
  return !state || connectivityBad.indexOf(state.connectivity) === -1
}

// Plain-language names for NM connectivity states.
var connectivityLabels = {
  "full": "Online",
  "limited": "No internet",
  "portal": "Sign-in needed",
  "none": "Offline"
}

function connectivityLabel(state) {
  return state ? (connectivityLabels[state.connectivity] || "") : ""
}

// DNS "leak": a full-tunnel VPN is up but some non-VPN link still answers
// catch-all queries (systemd-resolved "Default Route: yes"). Split tunnels
// don't count: general DNS outside the tunnel is expected there. Links
// flagged default route but with no DNS server (e.g. an idle tailscale0)
// can't answer.
function dnsLeaks(state) {
  var vpns = activeVpns(state).filter(function(p) { return p.fullTunnel })
  if (vpns.length === 0 || !state.dns) return false
  var vpnDevices = vpns.map(function(p) { return p.device })
  return state.dns.some(function(l) {
    return l.defaultRoute && l.server && vpnDevices.indexOf(l.link) === -1
  })
}

// DNS for a connection: what NM reports, or else what systemd-resolved has
// for its device (set directly by e.g. tailscaled). Returns display text.
function connectionDns(state, profile) {
  if (!profile) return ""
  if ((profile.dns || []).length > 0) return profile.dns.join(", ")
  if (!state || !state.dns || !profile.device) return ""
  var link = state.dns.filter(function(l) { return l.link === profile.device && l.server })[0]
  if (!link) return ""
  return link.server + ((link.domains || []).length ? " · " + link.domains.join(", ") : "")
}

function defaultDns(state) {
  if (!state || !state.dns) return []
  return state.dns.filter(function(l) { return l.defaultRoute && l.server })
}

// Links that only answer their own domains (split DNS), e.g. tailnet names
// via Tailscale's MagicDNS, or the LAN's domain while a VPN takes the rest.
function splitDns(state) {
  if (!state || !state.dns) return []
  return state.dns.filter(function(l) {
    return !l.defaultRoute && l.server && (l.domains || []).length > 0
  })
}

function summary(state) {
  if (!state) return "NetworkManager: loading…"
  var parts = []
  var vpns = activeVpns(state)
  if (vpns.length === 0) parts.push("VPN: off")
  else parts.push("VPN: " + vpns.map(function(p) {
    return p.name + (p.fullTunnel ? " (full tunnel)" : " (split)")
  }).join(", "))
  externalTunnels(state).forEach(function(p) {
    parts.push(typeLabel(p) + ": " + p.name + " (external)")
  })
  otherConnections(state).forEach(function(p) {
    parts.push(typeLabel(p) + ": " + (p.ssid || p.name))
  })
  if (!connectivityOk(state)) parts.push(connectivityLabel(state))
  if (dnsLeaks(state)) parts.push("DNS outside VPN")
  return parts.join(" · ")
}

function formatBytes(n) {
  if (n === undefined || n === null) return "—"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  var v = Number(n)
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  return (i === 0 ? v : v.toFixed(v >= 100 ? 0 : 1)) + " " + units[i]
}

function formatUptime(seconds) {
  if (!(seconds > 0)) return "—"
  var s = Math.floor(seconds)
  var d = Math.floor(s / 86400); s %= 86400
  var h = Math.floor(s / 3600); s %= 3600
  var m = Math.floor(s / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  if (m > 0) return m + "m"
  return Math.floor(seconds) + "s"
}

// What goes through a tunnel: WireGuard allowed IPs, or the routes NM
// installed for other VPN types.
function tunnelRoutes(profile) {
  if (!profile) return []
  return (profile.type === "wireguard" ? profile.allowedIps : profile.routes) || []
}

function routesLabel(profile) {
  return profile && profile.type === "wireguard" ? "Allowed IPs" : "Routes"
}

var routeHints = { "0.0.0.0/0": "all IPv4", "::/0": "all IPv6" }

function routeHint(cidr) {
  return routeHints[cidr] || ""
}

function stripPrefix(addr) {
  return String(addr || "").replace(/\/\d+$/, "")
}

// Track when connections become active. `seen` maps uuid -> epoch seconds
// (0 = was already active when we started, so the true start is unknown).
function updateSince(seen, state, nowSec, initial) {
  var next = {}
  if (!state) return seen || {}
  state.profiles.forEach(function(p) {
    if (!p.active) return
    if (seen && seen[p.uuid] !== undefined) next[p.uuid] = seen[p.uuid]
    else next[p.uuid] = initial ? 0 : nowSec
  })
  return next
}
