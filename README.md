# local.nmstatus — NetworkManager / VPN widget for the Omarchy bar

A bar icon that shows whether a VPN (WireGuard, OpenVPN, …) managed by
NetworkManager is up:

- **green shield with check**: at least one VPN is active
- **yellow shield**: no VPN, but a tunnel run by another program (e.g.
  Tailscale) is up
- **white shield with slash**: no VPN

| VPN up | Tailscale only | Split tunnel, DNS warning |
|:---:|:---:|:---:|
| ![Full-tunnel WireGuard with Tailscale alongside](screenshots/vpn-up.png) | ![No VPN, only Tailscale: yellow](screenshots/tailscale-only.png) | ![Split-tunnel VPN with a scrolling route list and a DNS warning](screenshots/split-tunnel.png) |

<sub>Screenshots use made-up data.</sub>

Hover for a one-line summary. Left-click opens a popup with:

- internet status (Online / No internet / Sign-in needed / Offline) and the DNS
  server(s) answering catch-all queries, with a warning if DNS can bypass an
  active VPN; split-DNS links (e.g. `tail1234.ts.net → 100.100.100.100`) are
  listed underneath
- every VPN profile: up/down switch, autoconnect switch, address, DNS,
  endpoint, full/split tunnel, allowed IPs / routes, uptime, traffic. Long
  route lists scroll in place and shrink to keep the popup on screen
- tunnels NetworkManager only mirrors ("connected (externally)", e.g.
  `tailscale0`) are shown read-only with an **external** tag: no switches,
  since toggling them from NetworkManager would fight their owner
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
