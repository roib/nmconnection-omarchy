# local.nmstatus — NetworkManager / VPN widget for the Omarchy bar

A bar icon that shows whether a VPN (WireGuard, OpenVPN, …) managed by
NetworkManager is up:

- **green shield with check**: at least one VPN is active
- **white shield with slash**: no VPN

Hover for a one-line summary. Left-click opens a popup with:

- internet status (Online / No internet / Sign-in needed / Offline) and the DNS server(s) answering catch-all queries, with a
  warning if DNS can bypass an active VPN
- every VPN profile: up/down switch, autoconnect switch, address, endpoint,
  full/split tunnel, uptime, traffic
- every other active connection (Wi-Fi, Ethernet, …): addresses, gateway, DNS,
  signal or link speed, up/down switch
- click any address/endpoint to copy it (`wl-copy`)
- "Open connection editor" if `nm-connection-editor` is installed
  (`omarchy pkg add network-manager-applet`)

Right-click the icon to force a refresh. Updates are pushed via `nmcli monitor`,
with a polling fallback (`refreshIntervalSec`, default 10s).

Uptime is measured from when the widget saw the connection come up; for
connections already active when the shell started it shows "—".

## Install

```bash
ln -s ~/Projects/nmconnection-omarchy ~/.config/omarchy/plugins/local.nmstatus
omarchy-shell shell rescanPlugins
omarchy plugin enable local.nmstatus
omarchy bar move local.nmstatus --section right --before omarchy.network
```

Hot-reload does not pick up edits made through the symlink; after editing
files here run `omarchy restart shell`.

`./nm-status | jq .` prints the raw data the widget renders.
