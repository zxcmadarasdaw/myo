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

Open **Super+N → VPN**, enter a link or choose a local profile, then click **Install and configure VPN**. Serpantinum checks the current mode and sing-box, shows progress and validates the profile before saving it. A working installation is reused. After setup, choose a server and press **Connect** to start the VPN.

- **Proxy** uses the architecture-specific SagerNet GitHub archive and requires the published SHA-256. During the download you can see bytes, speed and retries, or cancel. The verified binary is placed in `~/.local/share/serpantinum/vpn/bin/sing-box` after the version and configuration checks succeed.
- **TUN** uses a signed system package. On Fedora the Serpantinum installer supplies a polkit helper for the panel. It uses the official SagerNet RPM repository for the transaction and asks for administrator authentication. The panel also offers that source for Proxy if GitHub fails. PyYAML is requested only when the profile actually requires it.
- **Connection → sing-box** still lists installed binaries and accepts a path for Proxy. A working binary has to answer `sing-box version`.

When updating an existing Fedora installation of Serpantinum, run the updated Serpantinum installer to register the package helper and policy. The installer supplies `lxqt-policykit` on minimal Fedora Hyprland systems that lack a packaged authentication agent. Hyprland starts the agent at sign-in. If a Live session loses the binary at reboot, reopening the VPN tab offers setup again.

## Use

The network panel (**Super+N**) has two tabs, **Internet** and **VPN**. Switch with a click, **Ctrl+Tab** or **Ctrl+PgUp/PgDown**. **Esc** closes an open sheet first, then the panel.

The VPN tab is a large ON/OFF button with lines to four cards:

- **IP address**: the exit address, read *through the VPN* after it connects (`serpantinum vpn ipcheck`). Before that it shows *Checked after connecting*. Nothing is guessed.
- **Location**: the country of the exit IP with its flag. Before the check it shows the country from the server name and marks it *not verified*, or *Unknown* when the name has none. When the exit IP is in a different country than the name says, the card says so.
- **Select server**: opens the server picker.
- **Protocol**: VLESS, Trojan… and the mode (proxy address or TUN).

The button shows the real state: *Disconnected*, *Connecting…*, *Connected* (only after `status` confirmed that sing-box answers), *Disconnecting…* and *Error*. After an error the reason is shown under the button, and the button can be pressed again. If a status never arrives, the button stops spinning after 8 seconds.

1. **+ Add VPN subscription** (or the button itself while there is nothing to connect to). Paste the link and optionally give it a name. The subscription is downloaded, parsed and checked with `sing-box check`; if this fails, nothing is saved.
2. Press the button to connect.
3. **Select server**: the countries of *this subscription's* servers only, each with its best measured delay, then its servers. A delay is shown only when it was measured (*no answer* otherwise). Servers without a recognisable country are under *Unknown*.

### Subscriptions

Several subscriptions can be saved; one is active. The bar at the bottom shows the active one with its server count and the time of the last update. Its sheet lets you switch, rename, update and remove them. The link itself is never shown again after it is saved; only its host is.

### Appearance

**Super+H → Theme → VPN** (or the palette button in the VPN tab) edits the look of the tab, with a live preview that also shows in the open panel:

- six themes (Obsidian Glass, Liquid Noir, Midnight Blue, Graphite, Soft Neon, Pure Minimal) and your own saved ones;
- material (Matte Dark, Premium Glass, Liquid Glass, Obsidian, Minimal, Neon) with opacity, blur, border and corner radius;
- eight colours, each with a colour picker and a HEX field;
- lines: Straight, Curved, Circuit, Flow or Minimal, their width, glow and animation speed, or no animation at all;
- layout: Auto (Compact on small windows), Centered, Vertical, Horizontal, Compact, Expanded; button shape and font weight.

**Apply** stores the look, **Cancel** drops the preview, **Reset** goes back to the theme's own values, **Save as custom theme** keeps it under a name. The look is stored in the shell settings under `vpnAppearance`. It never contains a link, server or token.

Themess packages can carry a `vpn.json` with the same fields. Only the theme id and the style values above are accepted, so a package cannot carry or overwrite subscriptions, and your own saved themes are kept.

Accepted input:
- an `https://` subscription link (base64 list, Clash YAML or sing-box JSON);
- import links of other clients (`hiddify://import/…`, `sing-box://import-remote-profile?url=…`);
- one or more server links: `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`/`hy2://`, `tuic://`, `hysteria://`, `socks://`.
- a local file containing sing-box JSON, Clash YAML or a text list of supported server links. The panel copies the profile into private storage, so you can move the original file afterward.

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

Open the **Connection** sheet (the gear button in the VPN tab) and choose **TUN · whole system**. When connected, the tab shows *Connected · TUN* and *All traffic of this computer goes through the VPN*. The HTTP/SOCKS5 proxy on `127.0.0.1:2080` also keeps working. Choose **Proxy** to go back. Switching while connected reconnects in the new mode.

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
serpantinum vpn ipcheck           # exit IP and country, fetched through the running VPN
serpantinum vpn subs              # saved subscriptions (names and hosts, never links)
serpantinum vpn sub-add [--name=N]   # reads the link from stdin
serpantinum vpn sub-use ID | sub-rename ID NAME | sub-remove ID
serpantinum vpn singbox-info      # which sing-box is used, other ones found
serpantinum vpn singbox-install   # download the official release (no root)
serpantinum vpn singbox-use PATH  # use this sing-box ("" = automatic)
```

Add `--json` for machine-readable output. `vpn test` exits with:
- 0 when the config passed `sing-box check`;
- 1 on an error;
- 2 when sing-box is missing (the servers are still listed).

With `serpantinum vpn test "<link>"` the link is on your shell's command line. The script passes it on via stdin, but your shell history keeps it. Running `serpantinum vpn test` without the link asks for it instead.

## Files and privacy

| Path | Contents |
|---|---|
| `~/.config/serpantinum/vpn/source` | the active link (or pasted server links) |
| `~/.config/serpantinum/vpn/subs/ID` | each saved subscription's link |
| `~/.config/serpantinum/vpn/subscriptions.json` | subscription names, active id, update results |
| `~/.local/share/serpantinum/vpn/bin/sing-box` | the downloaded sing-box, if you used **Download** |
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

VPN Control Studio:
- [ ] Super+N → VPN tab and back (click, Ctrl+Tab, Ctrl+PgUp/PgDown): smooth switch; the Internet tab, Wi-Fi, Ethernet and Bluetooth work as before.
- [ ] Every sheet opened and closed, then the whole tab: clicks anywhere on the panel (and on the desktop and windows after closing it) still work; no invisible area catches the mouse.
- [ ] Resize the panel/monitor scale: lines follow the cards and never cross text; small sizes switch to Compact.
- [ ] sing-box **Download** with internet: progress and speed move, the result works; **Cancel** mid-way leaves nothing in `~/.local/share/serpantinum/vpn/bin`; offline gives a clear error.
- [ ] Connect: the button goes Connecting → Connected; IP and Location appear only after the check; `curl -x socks5h://127.0.0.1:2080 https://ifconfig.me` shows the same IP.
- [ ] A broken server: the button ends in Error with the reason, the internet still works without the VPN.
- [ ] Two subscriptions: switch, rename, remove; the bottom bar and the server list follow.
- [ ] Super+H → Theme → VPN: each theme, material, line style, layout, colour picker and HEX; Apply, Cancel, Reset, Save as custom theme survive a shell restart.
- [ ] GPU load with the tab open and idle (`nvtop`/`intel_gpu_top`): no constant load; with the panel closed, nothing animates.
- [ ] OBS recording and switching workspaces with the panel open: no stuck input.

Proxy and subscriptions:
- [ ] Without sing-box: the power button shows setup required. Paste a link, install and import, then confirm a server can be selected before pressing Connect.
- [ ] Block GitHub: Retry retains the original input. Try the official RPM with polkit and confirm the system binary is detected. Cancel the authorization and check that the existing profile still works.
- [ ] In Fedora Live, reboot without persistence and verify setup is offered again when the binary is gone.
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
