---
sidebar_position: 6
title: VPN subscriptions
sidebar_label: VPN
slug: /configure/vpn
---

# VPN subscriptions

A subscription client in the network panel (**Super+N**), in the spirit of Hiddify or Happ. It runs [sing-box](https://sing-box.sagernet.org/) in one of two modes:

- **Proxy** (default): a **local proxy on 127.0.0.1**, with no root and no system-wide routing. An application uses the VPN when it is told to use the proxy.
- **TUN · whole system**: all traffic of the computer goes through the VPN, through the `serpantinum-vpn` system service (see [TUN mode](#tun-mode-whole-system)).

## Install sing-box

sing-box is not installed by the Serpantinum installer. On Fedora:

```bash
sudo dnf config-manager addrepo --from-repofile=https://sing-box.app/sing-box.repo
sudo dnf install sing-box
```

Without it the panel shows *sing-box is not installed* together with this command (with a **Copy** button) and does nothing else. Clash YAML subscriptions also need PyYAML (`sudo dnf install python3-pyyaml`); the panel says so when it is missing.

## Use

1. Open the network panel (**Super+N**). The VPN block is at the top, above the Internet card.
2. Paste the link into the field (**Ctrl+V** or the paste button), then **Save** (or Enter). The subscription is downloaded, parsed and checked with `sing-box check`.
3. **Connect**. The block shows *Connected*, the current server with its country and ping, and the proxy address.
4. Click the server chip to see countries with their best ping. Click a country to see its servers with ping, then click a server to switch to it (when disconnected, this also connects).

Accepted input:
- an `https://` subscription link (base64 list, Clash YAML or sing-box JSON);
- import links of other clients (`hiddify://import/…`, `sing-box://import-remote-profile?url=…`);
- one or more server links: `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`/`hy2://`, `tuic://`, `hysteria://`, `socks://`.

`happ://` links are encrypted by the Happ app and cannot be read; paste the original `https://` link instead.

Servers that sing-box cannot use (for example the `xhttp` transport) are skipped and counted; `serpantinum vpn test` lists them with the reason.

### Using the proxy

The proxy speaks HTTP and SOCKS5 on `127.0.0.1:2080`:

- **Firefox:** Settings → Network → *Manual proxy*: SOCKS v5, host `127.0.0.1`, port `2080`, and turn on *Proxy DNS when using SOCKS v5*.
- **Chromium:** `chromium --proxy-server="socks5://127.0.0.1:2080"`.
- **Terminal:** `export all_proxy=socks5h://127.0.0.1:2080 https_proxy=http://127.0.0.1:2080 http_proxy=http://127.0.0.1:2080`.
- **GNOME/KDE:** the system proxy settings also work for applications that honour them.

To send all of the system's traffic through the VPN instead, use TUN mode.

## TUN mode (whole system)

Open the server list (click the server chip) and choose **TUN · whole system**. When connected, the block shows *Connected · TUN* and *All traffic of this computer goes through the VPN*. The HTTP/SOCKS5 proxy on `127.0.0.1:2080` also keeps working. Choose **Proxy** to go back. Switching while connected reconnects in the new mode.

TUN needs root to create the network interface and the routes. It does not use `sudo` and does not ask for a password. Instead, the installer sets up:

| Installed file | Purpose |
|---|---|
| `/usr/libexec/serpantinum/serp-vpn-root` | root helper (root:root 755) |
| `/etc/systemd/system/serpantinum-vpn.service` | the service. It is **not** enabled at boot: only the panel or the CLI starts it |
| `/usr/share/polkit-1/actions/org.serpantinum.vpn.policy` | polkit action for the helper (admin password by default) |
| `/etc/polkit-1/rules.d/49-serpantinum-vpn.rules` | lets **only the user who ran the installer**, in an active local session, run the helper and start, stop, restart or kill **only this unit** |
| `/etc/serpantinum-vpn/` (700) → `config.json` (600) | the root config |

When you connect in TUN mode:

1. The panel sends the **server list** to the helper through `pkexec` on stdin. It never sends the subscription link.
2. The helper builds the config from its own fixed template:
   - a TUN interface `serp-tun0` with `auto_route` and `strict_route`;
   - DNS that goes over the VPN (DoH to 1.1.1.1), with port-53 queries intercepted. Only the VPN servers' own names are resolved directly (UDP 1.1.1.1), to reach them;
   - private networks go direct;
   - the Clash API on 127.0.0.1 with the same secret.

   From the servers it takes only known proxy types. It refuses chaining (`detour`) and any key that names a file. It runs `sing-box check` and only then replaces `/etc/serpantinum-vpn/config.json`. If the check fails, the previous config stays.
3. `systemctl restart serpantinum-vpn` starts it.

sing-box must be at least 1.12 and live in `/usr/bin` or `/usr/local/bin`, which is where the dnf package puts it.

**Remove** in the panel (`serpantinum vpn clear`) also deletes the root config.

### Warnings

In TUN mode the server list shows warnings:

- **Other VPNs** (yellow): Tailscale, WireGuard and other VPN interfaces (`wg*`, `tun*`, `nordlynx`…), VPN programs (OpenVPN, Xray, Clash/Mihomo, NekoRay, Hiddify, AmneziaVPN, WARP…), and active NetworkManager VPN connections. Two VPNs at once usually break each other: turn one off. The first such warning also shows in the card.
- **DNS** (grey):
  - systemd-resolved is not running;
  - `/etc/resolv.conf` does not point to systemd-resolved;
  - systemd-resolved uses DNS-over-TLS.

  In all three cases the VPN still works. These notes explain where DNS queries go.

`serpantinum vpn check` prints the same list.

### If the service hangs: Force off

A normal **Disconnect** stops the service. If sing-box does not stop (the service waits 5 s and then kills it), or the service has failed, the panel shows **Force off**. It also appears while a TUN disconnect is in progress. Force off:

1. stops the hanging action;
2. kills the service (`systemctl kill --signal=SIGKILL`), then stops it and resets its failed state;
3. runs the helper's `cleanup`, which removes the `serp-tun0` interface, sing-box's policy-routing rules (priorities 9000–9019 and table 2022) and its nftables table;
4. stops the local proxy if it runs.

From a terminal: `serpantinum vpn force-off` (or `serpantinum vpn tun off --force`). If even that fails, the manual way is:

```bash
sudo systemctl kill -s SIGKILL serpantinum-vpn; sudo systemctl stop serpantinum-vpn
sudo /usr/libexec/serpantinum/serp-vpn-root cleanup
```

The service also runs `cleanup` before every start and after every stop. Routes left by a crash therefore do not survive the next start.

## Updates

The subscription is updated with the **Update** button, and automatically every 12 hours (`updateHours` in the settings file below). A new config replaces the old one **only after `sing-box check` accepts it**. If the download fails, the provider returns a web page, the list is empty or the check fails, the last working config is kept and the panel says why. When connected, a successful update restarts the proxy with the new servers.

## Ping

Delays are measured by sing-box itself, using its Clash API delay test against `https://www.gstatic.com/generate_204`. This happens only while the network panel is open: when it opens, then every minute, and when you press the ping button.

When not connected, a short-lived sing-box without any listening proxy port is started for the measurement and stopped right after. Closing the panel stops a running measurement.

## Command line

```bash
serpantinum vpn test              # asks for the link (hidden input), prints servers, runs sing-box check
serpantinum vpn test "<link>"     # the same; saves and starts nothing
serpantinum vpn status            # state, server, proxy address, last update
serpantinum vpn set               # asks for the link and saves it (same as the panel)
serpantinum vpn update | connect | disconnect | list | ping
serpantinum vpn select "<server name>"
serpantinum vpn clear             # forget the subscription and stop the proxy
serpantinum vpn mode proxy|tun    # choose the mode (reconnects when connected)
serpantinum vpn tun on | tun off  # TUN shortcuts: switch to TUN and connect / disconnect
serpantinum vpn check             # TUN service state, DNS notes, other-VPN conflicts (tun status)
serpantinum vpn force-off         # emergency off (tun off --force)
```

Add `--json` for machine-readable output. `vpn test` exits with:
- 0 when the config passed `sing-box check`;
- 1 on an error;
- 2 when sing-box is missing (the servers are still listed).

With `serpantinum vpn test "<link>"` the link is on your shell's command line. The script passes it on via stdin, but your shell history keeps it. Running `serpantinum vpn test` without the link asks for it instead.

## Files and privacy

| Path | Contents |
|---|---|
| `~/.config/serpantinum/vpn/source` | the link (or pasted server links) |
| `~/.config/serpantinum/vpn/settings.json` | ports, update interval, selected server, Clash API secret |
| `~/.local/state/serpantinum/vpn/` | parsed servers, generated sing-box config, last update result, ping results, `sing-box.log`, pid |

- Directories are created with mode 700 and files with mode 600. None of these files are part of the repository.
- The link is passed to the helper script on stdin, never as a command-line argument (which every user could see in `ps`). It is not written to any log or to the generated config.
- sing-box listens only on 127.0.0.1. Its control API (Clash API, ports 9097 and 9098) is protected by a random secret.

Settings file keys:
- `proxyPort` (2080), `apiPort` (9097), `probePort` (9098);
- `updateHours` (12);
- `userAgent` (`v2rayN/7.0`; some providers return a different format depending on it);
- `testUrl`.

## Troubleshooting

- *Port 2080 on 127.0.0.1 is already used*: another proxy runs there. Change `proxyPort` in `settings.json`.
- *sing-box rejected the generated config*: the message contains sing-box's reason, and `serpantinum vpn test` shows which servers were read. An older sing-box may not know newer fields (e.g. from a sing-box JSON subscription); update sing-box.
- *The link returned a web page*: the link has expired, or the provider needs a different User-Agent (`userAgent`).
- `~/.local/state/serpantinum/vpn/sing-box.log` has sing-box's own messages (proxy mode). In TUN mode use `journalctl -u serpantinum-vpn`.
- *TUN mode is not installed*: run the Serpantinum installer again. The service needs systemd and polkit.
- *The system did not allow controlling the VPN service*: the polkit rule is written for the user who ran the installer. Run the installer as yourself, or check `/etc/polkit-1/rules.d/49-serpantinum-vpn.rules`.
- *TUN mode needs sing-box 1.12 or newer*: `sudo dnf upgrade sing-box`.

## Manual test checklist (Fedora + Hyprland)

- [ ] Without sing-box: the block says *sing-box is not installed*, Copy puts the dnf command into the clipboard, nothing crashes.
- [ ] Paste with Ctrl+V and with the button, then Save: the server count appears, and `ls -l ~/.config/serpantinum/vpn` shows `-rw-------`.
- [ ] `ps aux | grep serp_vpn` while saving: the link is not visible.
- [ ] Connect: `curl -x socks5h://127.0.0.1:2080 https://ifconfig.me` shows the server's address. Disconnect stops sing-box (`pgrep sing-box` is empty).
- [ ] Server list: countries and pings show. Switching the server while connected changes the address curl reports.
- [ ] Close the panel during a ping: no probe `sing-box` is left (`pgrep -a sing-box`).
- [ ] Break the link (e.g. delete a character) and Update: an explanation is shown and the old servers keep working.
- [ ] Ethernet, Wi-Fi and Bluetooth in the panel behave as before; the window fits on screen with the bar at the top and at the bottom.
- [ ] `serpantinum vpn test` and `serpantinum vpn status` with the real subscription.

TUN mode (after running the installer):
- [ ] `ls -l /usr/libexec/serpantinum/serp-vpn-root /etc/polkit-1/rules.d/49-serpantinum-vpn.rules`: root-owned. `systemctl is-enabled serpantinum-vpn` says `disabled` or `static`.
- [ ] Choose TUN and Connect: no password dialog. `curl https://ifconfig.me` (without a proxy) shows the server's address. `ip link show serp-tun0` exists. `sudo ls -l /etc/serpantinum-vpn` shows `-rw-------` root.
- [ ] DNS: `resolvectl query example.com` works, and https://dnsleaktest.com shows the VPN's DNS (Cloudflare), not your provider's.
- [ ] Switch servers while connected: the address changes. Update: the service restarts with the new config.
- [ ] Disconnect: `ip link show serp-tun0` fails, `ip rule` has no 9000-series rules, and the internet works directly.
- [ ] Run `tailscale up` (if available) or bring up a WireGuard connection: the warning appears.
- [ ] Force off while connected: everything is removed as above and the internet works.
- [ ] Another user on the same machine: `pkexec /usr/libexec/serpantinum/serp-vpn-root cleanup` asks for the admin password.
- [ ] Remove the subscription: `sudo ls /etc/serpantinum-vpn` is empty.
