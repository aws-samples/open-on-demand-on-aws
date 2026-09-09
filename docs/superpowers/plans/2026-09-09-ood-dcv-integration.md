# Open OnDemand + NICE DCV Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the TurboVNC/GNOME interactive-desktop stack with NICE DCV (Amazon DCV) as the remote-desktop protocol for Open OnDemand, driven through OOD's existing reverse proxy.

**Architecture:** DCV runs on the ParallelCluster `desktop` queue compute nodes (elastic, `MinCount: 0`). OOD's `bc_desktop` app submits a Slurm job using a custom `ood_core` batch-connect template (`dcv.rb`) that creates a DCV session, wires up the DCV Simple External Authenticator for SSO, and exposes a Connect URL through OOD's reverse proxy (`/rnode/<host>/<port>/`). No ALB or target-group Lambda is used — the reverse proxy resolves the ephemeral node via `set_host`, matching how VNC works today.

**Tech Stack:** Open OnDemand 4.2 (on AL2023), `ood_core` batch-connect templates (Ruby/ERB), NICE DCV server + `nice-xdcv` + `nice-dcv-simple-external-authenticator`, GNOME (`dnf groupinstall "Desktop"`), AWS ParallelCluster 3.16 (Slurm), Apache `mod_ood_proxy`.

## Global Constraints

- Target OS for all compute/desktop nodes: **Amazon Linux 2023** (no `amazon-linux-extras`; use `dnf`).
- Open OnDemand version: **4.2** (`ondemand-release-web-4.2-1.amzn2023`).
- `ood_core` still has **no native DCV template** (ships `basic`, `vnc`, `vnc_container`, `wayvnc`) — the `dcv.rb` template must be installed into the version-pinned gem path, and re-copied on every OOD package upgrade.
- Connection path: **OOD reverse proxy** (`rnode_uri: /rnode` in `ood_portal.yml`), NOT an ALB.
- DCV is license-free on EC2; no license server.
- Do not modify the applied VNC/GNOME fallback on `ood-upgrades-2026-09`; this work lives only on `feat/ood-dcv-integration`.
- Reference implementation: `aws-samples/openondemand-dcv` (written for OOD 3.0/3.1, ALB-based — adapt to 4.2 + reverse proxy).

---

## File Structure

- `scripts/pcluster_worker_node_desktop.sh` (modify) — desktop-node bootstrap: replace TurboVNC install with DCV server + authenticator + GNOME; keep spack group + PATH.
- `assets/ood-dcv/templates/dcv.rb` (create) — ported batch-connect template (reverse-proxy URL scheme).
- `assets/ood-dcv/bc_desktop/submit.yml.erb` (create) — Slurm submission, `template: "dcv"`, `set_host`, target the `desktop` queue.
- `assets/ood-dcv/bc_desktop/form.yml` (create) — desktop app form (session timeout; desktop = dcv).
- `assets/ood-dcv/bc_desktop/manifest.yml` (create) — app manifest.
- `assets/ood-dcv/bc_desktop/info.html.erb` (create) — Connect buttons using the reverse-proxy URL.
- `scripts/install_ood.sh` (modify) — install `dcv.rb` into the gem path + install `bc_desktop`; add an upgrade-safe re-copy hook; adjust `ood_portal.yml` (host_regex, SSLProxyCheckPeer for DCV's self-signed cert).

---

## Task 1: Validate DCV-over-reverse-proxy connectivity (GATE)

This is the highest-risk unknown: the reference only demonstrated DCV through an ALB. Everything else depends on DCV's web client working behind OOD's `/rnode/<host>/<port>/` path prefix. **Do this before writing any integration code.**

**Files:** none (manual spike on one node).

- [ ] **Step 1: Launch one AL2023 desktop node manually and install DCV**

On a temporary AL2023 EC2 instance in a private subnet of the cluster VPC (t3.large+), run:

```bash
sudo dnf groupinstall "Desktop" -y
sudo rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
curl -O https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-el2023-x86_64.tgz
tar -xvzf nice-dcv-el2023-x86_64.tgz && cd nice-dcv-*-el2023-x86_64
sudo dnf install -y ./nice-dcv-server-*.rpm ./nice-xdcv-*.rpm ./nice-dcv-simple-external-authenticator-*.rpm
sudo systemctl enable --now dcvserver dcvsimpleextauth
```

- [ ] **Step 2: Set DCV web-url-path to the reverse-proxy prefix and start a session**

`web-url-path` must match the path OOD proxies under. For host `ip-10-50-2-50` on port `8443` the prefix is `/rnode/ip-10-50-2-50.ec2.internal/8443`. Set it:

```bash
HOST_FQDN=$(hostname -f); PREFIX="/rnode/${HOST_FQDN}/8443"
sudo crudini --set /etc/dcv/dcv.conf connectivity web-url-path "\"${PREFIX}\"" || \
  sudo sed -i "/^\[connectivity\]/a web-url-path=\"${PREFIX}\"" /etc/dcv/dcv.conf
sudo systemctl restart dcvserver
dcv create-session --storage-root "$HOME" test1
```

- [ ] **Step 3: Verify DCV web client loads through the OOD reverse proxy**

From the OOD portal host (which runs `mod_ood_proxy`), curl the rnode path and confirm the DCV web client HTML/assets return `200`/`301` (not `404`/`502`):

```bash
curl -ksS -o /dev/null -w "%{http_code}\n" \
  "https://localhost/rnode/${HOST_FQDN}/8443/"
```

Expected: `200` or `301`. If `502`/`404`, the `web-url-path` prefix or `mod_ood_proxy` SSL settings are wrong — see Step 4.

- [ ] **Step 4: If the proxy rejects DCV's self-signed cert, enable peer-check bypass**

DCV serves a self-signed cert on 8443. Add to the OOD reverse-proxy Apache config (temporary, for validation):

```apache
SSLProxyEngine on
SSLProxyCheckPeerName off
SSLProxyCheckPeerCN off
SSLProxyCheckPeerExpire off
```

Re-run Step 3 until it returns `200`/`301`.

- [ ] **Step 5: Record the outcome and decide**

Document in this plan file under a "Task 1 result" note: whether the DCV web client renders and connects through `/rnode/`, the exact working `web-url-path` value, and the exact Apache SSLProxy directives needed.

**GATE:** If DCV cannot be made to work through the reverse proxy after reasonable effort, STOP and escalate — the fallback is the reference's ALB approach (adds a per-node target-group updater Lambda for the elastic desktop queue), which is a materially larger change and should be re-scoped with the user.

- [ ] **Step 6: Commit the recorded findings**

```bash
git add docs/superpowers/plans/2026-09-09-ood-dcv-integration.md
git commit -m "docs: record DCV reverse-proxy connectivity spike result"
```

---

## Task 2: DCV desktop-node bootstrap script

Replace the TurboVNC install in the desktop-node script with DCV. Keep GNOME (`dnf groupinstall "Desktop"`), the `spack-users` group, and the PATH export.

**Files:**
- Modify: `scripts/pcluster_worker_node_desktop.sh`

**Interfaces:**
- Produces: an AL2023 desktop node with `dcvserver` + `dcvsimpleextauth` enabled, GNOME installed, and `web-url-path` set to `/rnode/$(hostname -f)/8443` (value confirmed in Task 1).

- [ ] **Step 1: Rewrite the script**

Replace the entire body after the license header with:

```bash
#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -euo pipefail
LOG=/var/log/configure_desktop.log

echo "[-] Installing base packages" >> "$LOG"
dnf install -y jq nmap-ncat crudini

# Add spack-users group
groupadd spack-users -g 4000 || true

echo "[-] Installing GNOME desktop" >> "$LOG"
dnf groupinstall "Desktop" -y

echo "[-] Installing NICE DCV" >> "$LOG"
rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
DCV_TGZ=/tmp/nice-dcv-el2023-x86_64.tgz
curl -fsSL -o "$DCV_TGZ" https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-el2023-x86_64.tgz
tar -xzf "$DCV_TGZ" -C /tmp
DCV_DIR=$(find /tmp -maxdepth 1 -type d -name 'nice-dcv-*-el2023-x86_64' | head -1)
dnf install -y \
  "$DCV_DIR"/nice-dcv-server-*.rpm \
  "$DCV_DIR"/nice-xdcv-*.rpm \
  "$DCV_DIR"/nice-dcv-simple-external-authenticator-*.rpm

echo "[-] Configuring DCV web-url-path for OOD reverse proxy" >> "$LOG"
HOST_FQDN=$(hostname -f)
crudini --set /etc/dcv/dcv.conf connectivity web-url-path "\"/rnode/${HOST_FQDN}/8443\""

systemctl enable --now dcvserver dcvsimpleextauth

echo "[-] Updating bashrc" >> "$LOG"
cat >> /etc/bashrc << 'EOF'
PATH=$PATH:/shared/software/bin
export XDG_RUNTIME_DIR="$HOME/.cache/dconf"
EOF

echo "DONE" >> "$LOG"
```

- [ ] **Step 2: Shellcheck the script**

Run: `shellcheck scripts/pcluster_worker_node_desktop.sh`
Expected: no errors (warnings about `set -e` with `groupadd || true` are acceptable).

- [ ] **Step 3: Commit**

```bash
git add scripts/pcluster_worker_node_desktop.sh
git commit -m "feat: install NICE DCV on desktop nodes instead of TurboVNC"
```

---

## Task 3: Port the `dcv.rb` batch-connect template to the reverse proxy

Adapt the reference template: keep `session_id` (from `work_dir`), session creation, ready-check, and external-auth SSO; replace the ALB `.dcv`-file block with the reverse-proxy URL scheme, and write `.server` = FQDN for `info.html.erb`.

**Files:**
- Create: `assets/ood-dcv/templates/dcv.rb`

**Interfaces:**
- Consumes: `context[:work_dir]` (OOD-supplied), `/etc/dcv/dcv.conf` `auth-token-verifier`.
- Produces: files in the job output dir — `.server` (host FQDN), `.session.pwd` (base64 one-time password), `.session_complete` (on close). `info.html.erb` (Task 6) reads these.

- [ ] **Step 1: Write the template**

```ruby
require "ood_core/refinements/hash_extensions"

module OodCore
  module BatchConnect
    class Factory
      using Refinements::HashExtensions

      def self.build_dcv(config)
        context = config.to_h.compact.symbolize_keys
        Templates::DCV.new(context)
      end
    end

    module Templates
      class DCV < Template
        def initialize(context = {})
          super
        end

        private

        def before_script
          <<-EOT.gsub(/^ {12}/, "")
            #{super}
            _username=$(whoami)
            # Host FQDN used by the OOD reverse proxy (set_host) and web-url-path
            dcv_server=$(hostname -f)
            printf "${dcv_server}" > .server
            # create session
            dcv create-session --storage-root "${HOME}" #{session_id}
            dcv list-sessions
            _iterator=0
            while true; do
                display=$(2>/dev/null dcv describe-session #{session_id} | awk '/X display: / { print $3 }')
                [ -n "${display}" ] && break
                if [ "$_iterator" -gt 10 ]; then echo "describe-session failed" >&2; exit 1; fi
                _iterator=$(( _iterator+1 )); sleep $_iterator
            done
            # SSO via DCV simple external authenticator
            auth_verifier=$(sed '/^[ \\t]*auth-token-verifier[ \\t]*=/!d;s/^[^=]*=[ \\t]*//;s/"//g' /etc/dcv/dcv.conf)
            if [ -n "${auth_verifier}" ]; then
                _session_pwd=$(uuidgen)
                printf "${_session_pwd}" | base64 > .session.pwd
                chmod 600 .session.pwd
                echo "${_session_pwd}" | dcvsimpleextauth add-user --user "${_username}" \\
                    --session #{session_id} --auth-dir /var/run/dcvsimpleextauth/ --append
            fi
          EOT
        end

        def run_script
          %(DISPLAY=:${display} #{super})
        end

        def after_script
          <<-EOT.gsub(/^ {12}/, "")
            #{super}
            trap "dcv close-session #{session_id}" SIGTERM
          EOT
        end

        def clean_script
          <<-EOT.gsub(/^ {12}/, "")
            #{super}
            touch .session_complete
            dcv close-session #{session_id}
          EOT
        end

        def session_id
          context.fetch(:work_dir).to_s.scan(%r{^.*/([^/]*)$})[0][0]
        end
      end
    end
  end
end
```

- [ ] **Step 2: Ruby syntax check**

Run: `ruby -c assets/ood-dcv/templates/dcv.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add assets/ood-dcv/templates/dcv.rb
git commit -m "feat: add DCV batch-connect template for reverse proxy"
```

---

## Task 4: `bc_desktop` app — form + manifest

**Files:**
- Create: `assets/ood-dcv/bc_desktop/form.yml`
- Create: `assets/ood-dcv/bc_desktop/manifest.yml`

- [ ] **Step 1: Write `form.yml`** (no instance dropdown — the `desktop` Slurm queue selects the node)

```yaml
---
attributes:
  desktop: "dcv"
  session_timeout:
    widget: select
    label: "Session timeout"
    options:
      - [ "2 hours", "2h" ]
      - [ "4 hours", "4h" ]
      - [ "8 hours", "8h" ]
      - [ "1 day", "1d" ]
form:
  - desktop
  - session_timeout
```

- [ ] **Step 2: Write `manifest.yml`**

```yaml
---
name: Desktop (DCV)
icon: fa://desktop
category: Interactive Apps
subcategory: Desktops
role: batch_connect
description: |
  Launch an interactive GNOME desktop on a compute node using NICE DCV.
```

- [ ] **Step 3: Commit**

```bash
git add assets/ood-dcv/bc_desktop/form.yml assets/ood-dcv/bc_desktop/manifest.yml
git commit -m "feat: add DCV bc_desktop form and manifest"
```

---

## Task 5: `bc_desktop` submit script (Slurm + set_host)

**Files:**
- Create: `assets/ood-dcv/bc_desktop/submit.yml.erb`

**Interfaces:**
- Consumes: cluster name via OOD cluster config; the `desktop` Slurm queue from `pcluster-config.yml`.
- Produces: a Slurm job that runs `template: "dcv"` and sets `set_host` to the node FQDN so the reverse proxy can reach it (mirrors the existing VNC `set_host` in `install_ood.sh`).

- [ ] **Step 1: Write `submit.yml.erb`**

```yaml
---
batch_connect:
  template: "dcv"
  set_host: "host=$(hostname -f)"
script:
  job_name: "dcv"
  queue_name: "desktop"
  native:
    - "-t"
    - "<%= session_timeout %>"
```

- [ ] **Step 2: Commit**

```bash
git add assets/ood-dcv/bc_desktop/submit.yml.erb
git commit -m "feat: add DCV bc_desktop Slurm submit script"
```

---

## Task 6: Connect buttons for the reverse proxy (`info.html.erb`)

Rewrite the reference (ALB) `info.html.erb` to build the reverse-proxy URL: `https://<portal>/rnode/<host FQDN>/8443/?authToken=<pwd>#<session id>`.

**Files:**
- Create: `assets/ood-dcv/bc_desktop/info.html.erb`

- [ ] **Step 1: Write `info.html.erb`**

```erb
<div>
<% data_root = ENV['OOD_DATAROOT'] %>
<% base = data_root + '/batch_connect/sys/bc_desktop/output/' + id %>
<% server_file = base + '/.server' %>
<% passwd_file = base + '/.session.pwd' %>
<% complete_file = base + '/.session_complete' %>

<% if File.exist?(complete_file) %>
  <div>Session closed</div>
<% elsif File.exist?(passwd_file) %>
  <% host = File.read(server_file).to_s.strip %>
  <% passwd = Base64.decode64(File.read(passwd_file).to_s) %>
  <% dcv_url = '/rnode/' + host + '/8443/?authToken=' + passwd + '#' + id %>
  <button class="btn btn-primary" type="submit"
          onclick="window.open('<%= dcv_url %>', '_blank')">Connect via browser</button>
  <br/><br/>
  <div>DCV desktop running on <b><%= host %></b></div>
<% else %>
  <div>Setting up connection...</div>
<% end %>
</div>
```

- [ ] **Step 2: ERB syntax check**

Run: `erb -x -T - assets/ood-dcv/bc_desktop/info.html.erb | ruby -c`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add assets/ood-dcv/bc_desktop/info.html.erb
git commit -m "feat: add DCV connect buttons for reverse proxy"
```

---

## Task 7: Wire installation into `install_ood.sh` (upgrade-safe)

Install `dcv.rb` into the version-pinned `ood_core` gem path, install the `bc_desktop` app, add SSLProxy directives + tighten `host_regex`, and add a re-copy step so OOD package upgrades don't silently drop `dcv.rb`.

**Files:**
- Modify: `scripts/install_ood.sh`

**Interfaces:**
- Consumes: the assets from Tasks 3–6 (assume the repo is checked out at `${REPO_DIR}` on the portal, as other scripts already reference repo files).
- Produces: `dcv.rb` in the gem templates dir; `bc_desktop` app configured for DCV; reverse proxy accepting DCV's self-signed cert.

- [ ] **Step 1: Add a function to locate the gem path and install `dcv.rb`**

Insert after the existing `bc_desktop` setup block (near `scripts/install_ood.sh:322`):

```bash
# --- NICE DCV batch-connect template (no native support in ood_core) ---
install_dcv_template() {
  local tmpl_dir
  tmpl_dir=$(find /opt /usr -type d -path "*ood_core*/batch_connect/templates" 2>/dev/null | head -1)
  if [ -z "$tmpl_dir" ]; then
    echo "[!] ood_core templates dir not found" >&2; return 1
  fi
  echo "[-] Installing dcv.rb into ${tmpl_dir}"
  install -m 0644 "${REPO_DIR}/assets/ood-dcv/templates/dcv.rb" "${tmpl_dir}/dcv.rb"
}
install_dcv_template
```

- [ ] **Step 2: Install the `bc_desktop` app files**

Add:

```bash
echo "[-] Installing DCV bc_desktop app"
install -d /var/www/ood/apps/sys/bc_desktop/template/desktops
install -m 0644 "${REPO_DIR}/assets/ood-dcv/bc_desktop/form.yml"        /var/www/ood/apps/sys/bc_desktop/form.yml
install -m 0644 "${REPO_DIR}/assets/ood-dcv/bc_desktop/manifest.yml"    /var/www/ood/apps/sys/bc_desktop/manifest.yml
install -m 0644 "${REPO_DIR}/assets/ood-dcv/bc_desktop/submit.yml.erb"  /var/www/ood/apps/sys/bc_desktop/submit.yml.erb
install -m 0644 "${REPO_DIR}/assets/ood-dcv/bc_desktop/info.html.erb"   /var/www/ood/apps/sys/bc_desktop/info.html.erb
```

- [ ] **Step 3: Add reverse-proxy SSL directives for DCV's self-signed cert**

Use the exact directives confirmed in Task 1. Append to the OOD reverse-proxy Apache config (the file that carries the `mod_ood_proxy` / rnode config; typically generated from `ood_portal.yml`). Add via `ood_portal.yml`'s custom directives if available, else drop-in:

```bash
cat > /etc/httpd/conf.d/ood-dcv-proxy.conf <<'EOF'
SSLProxyEngine on
SSLProxyCheckPeerName off
SSLProxyCheckPeerCN off
SSLProxyCheckPeerExpire off
EOF
```

- [ ] **Step 4: Tighten `host_regex` in `ood_portal.yml`**

The current `host_regex: '[^/]+'` (install_ood.sh:102) is wide open. Restrict to cluster private-subnet EC2 hostnames:

```bash
sed -i "s|^host_regex:.*|host_regex: 'ip-10-50-[0-9-]+\\\\.ec2\\\\.internal'|" /etc/ood/config/ood_portal.yml
```

Then regenerate + reload:

```bash
/opt/ood/ood-portal-generator/sbin/update_ood_portal
systemctl reload httpd
```

- [ ] **Step 5: Add an upgrade-safe re-copy hook**

OOD RPM upgrades replace the gem dir, dropping `dcv.rb`. Add a systemd path unit (or dnf post-transaction) to re-run `install_dcv_template`:

```bash
cat > /etc/systemd/system/ood-dcv-template.service <<EOF
[Unit]
Description=Reinstall OOD DCV batch-connect template after upgrades
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/install_dcv_template.sh
EOF
install -m 0755 /dev/stdin /usr/local/sbin/install_dcv_template.sh <<'EOF'
#!/bin/bash
tmpl_dir=$(find /opt /usr -type d -path "*ood_core*/batch_connect/templates" 2>/dev/null | head -1)
[ -n "$tmpl_dir" ] && install -m 0644 /opt/ood-dcv/dcv.rb "${tmpl_dir}/dcv.rb"
EOF
install -D -m 0644 "${REPO_DIR}/assets/ood-dcv/templates/dcv.rb" /opt/ood-dcv/dcv.rb
systemctl daemon-reload
```

Also add a dnf post-transaction trigger (so the service runs after `dnf upgrade ondemand`):

```bash
cat > /etc/dnf/plugins/post-transaction-actions.d/ood-dcv.action <<'EOF'
ondemand*:in:systemctl start ood-dcv-template.service
EOF
dnf install -y python3-dnf-plugin-post-transaction-actions
```

- [ ] **Step 6: Shellcheck**

Run: `shellcheck scripts/install_ood.sh`
Expected: no new errors introduced by the added blocks.

- [ ] **Step 7: Commit**

```bash
git add scripts/install_ood.sh
git commit -m "feat: install DCV template and bc_desktop in OOD portal setup"
```

---

## Task 8: End-to-end validation

**Files:** none (deploy + manual verification).

- [ ] **Step 1: Deploy the desktop-node change**

Upload the updated `pcluster_worker_node_desktop.sh` to the cluster config S3 bucket (the mechanism `pcluster-config.yml` already uses for `OnNodeConfigured`), then update/recreate the `desktop` queue nodes.

- [ ] **Step 2: Deploy the portal change**

Re-run the relevant portion of `install_ood.sh` on the portal (or redeploy the portal). Verify `dcv.rb` landed:

Run (read-only, on portal): `find /opt /usr -path '*batch_connect/templates/dcv.rb'`
Expected: one path printed.

- [ ] **Step 3: Launch a desktop session from the OOD dashboard**

In OOD → Interactive Apps → Desktop (DCV) → set timeout → Launch. Wait for the card to show "Connect via browser".

- [ ] **Step 4: Connect and verify GNOME renders over DCV through the reverse proxy**

Click Connect. Expected: GNOME desktop renders in-browser; no cert warning loop; URL is `/rnode/<host>/8443/...`. SSO logs in without a second password prompt.

- [ ] **Step 5: Verify clean teardown**

Delete the session in OOD. Expected: `dcv close-session` runs, `.session_complete` is written, the Slurm job ends, and the elastic node scales back down.

- [ ] **Step 6: Commit any fixes and tag the plan complete**

```bash
git add -A
git commit -m "test: validate DCV desktop end-to-end"
```

---

## Notes / open items to confirm during execution

- **Task 1 is the gate.** If DCV can't work behind `/rnode/`, escalate before proceeding (ALB fallback = larger scope).
- **Exact `ood_core` gem version/path** on OOD 4.2 — grab from the portal (read-only) during Task 7; `find` handles the version suffix.
- **DCV package URL** (`d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-el2023-x86_64.tgz`) — confirm current filename at install time; AWS occasionally revises the archive name.
- **GPU acceleration** — if the `desktop` queue moves to GPU instances, add `nice-dcv-gl` to Task 2.
- **`session_timeout`** enforcement — the reference used a `sleep`-based timeout; here it's passed to Slurm via `-t`. Confirm the Slurm job honors it and closes the DCV session on kill (the `after_script` SIGTERM trap handles the latter).
