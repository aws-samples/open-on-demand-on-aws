# Debugging DCV desktop nodes

How to get onto a live desktop compute node and diagnose DCV virtual-session
failures directly, instead of relying on one-shot Open OnDemand `output.log`s
(the node is torn down when the batch-connect job ends).

## Hold a desktop node interactively

Batch-connect jobs release the node within ~30s of failing, which is too short
to inspect. Grab a node yourself and keep it:

```bash
# On the head node:
salloc -p desktop -t 20:00        # allocate a desktop node for 20 min
squeue                            # note the JOBID and the node name (e.g. desktop-dy-desktop-cr-1)

# Get an interactive shell on the allocated node (whichever works on the cluster):
srun --jobid=<JOBID> --pty bash   # preferred
# or:
ssh <nodename>                    # head node can SSH compute nodes by name
```

Run diagnostics as the OOD user (e.g. `Admin`), not root — DCV virtual sessions
are per-user and behave differently under `sudo`.

Release the node when done: `exit` the shell, then `scancel <JOBID>`.

## DCV log locations (on the node)

Per-session logs live in `/var/log/dcv/` and are named by user + session id:

| File | Shows |
|------|-------|
| `server.log` | session manager: create/close, `virtual-session-start-timeout`, "Failed while waiting for outputs" |
| `Xdcv.<user>.<sid>.log` | the virtual X server bring-up; where it stalls (e.g. hangs at `Initializing extension GLX`) |
| `dcv-xsession.<user>.<sid>.log` | `session-starter`: the exact `Xdcv` launch command + `Cannot read display number from Xdcv` |
| `agent.<user>.<sid>.log` | in-session agent |

The batch-connect `output.log` (on shared home, e.g.
`~/ondemand/data/sys/dashboard/batch_connect/sys/bc_desktop/<cluster>/output/<sid>/output.log`)
tails these on failure — see the diagnostics block in
`assets/ood-dcv/templates/dcv.rb`.

## Diagnostic bundle

Run this on a held node as the OOD user; it answers the common failure causes.

```bash
U=$(id -u)

echo "===== 1. did the desktop-node bootstrap run? ====="
# The dcvserver software-GL drop-in is the reliability fix (see below).
cat /etc/systemd/system/dcvserver.service.d/10-software-gl.conf 2>/dev/null \
  || echo "NO dcvserver software-GL drop-in"

echo "===== 2. is a software GL driver installed? ====="
rpm -qa | grep -iE 'mesa|glvnd|llvm' | sort
ls /usr/lib64/dri/*swrast* 2>/dev/null || echo "NO swrast driver"

echo "===== 3. hostname resolvable? ====="
hostname; getent hosts "$(hostname)" || echo "hostname NOT resolvable"

echo "===== 4. does a DCV virtual session get a display + auto-launch a desktop? ====="
dcv create-session --storage-root "$HOME" diag
for i in $(seq 1 10); do
  d=$(dcv describe-session diag 2>/dev/null | awk '/X display:/{print $3}')
  [ -n "$d" ] && break; sleep 2
done
echo "display => '${d:-NONE}'"
tail -n 25 /var/log/dcv/Xdcv."$USER".diag.log 2>/dev/null
ps -u "$USER" -o comm= | grep -Eq 'gnome-shell|mutter' \
  && echo ">> DCV auto-started a desktop" || echo ">> no auto desktop"
dcv close-session diag 2>/dev/null; true
```

## Root causes found (and their fixes)

1. **Intermittent "Failed while waiting for outputs" / Xdcv hangs at
   `Initializing extension GLX`.**
   On a no-GPU node, Xdcv's GLX init stalls probing for a hardware DRI driver and
   never falls back to `swrast`, so it never reports its display
   (`dcv-xsession.log`: `Cannot read display number from Xdcv`).
   **Fix:** pin Mesa to llvmpipe **on the `dcvserver` service** (it forks Xdcv,
   which inherits the unit's `Environment=`). A `dcvserver.service.d` drop-in with
   `LIBGL_ALWAYS_SOFTWARE=1` + `GALLIUM_DRIVER=llvmpipe`. `/etc/environment` does
   **not** work — systemd services don't source it. Set in
   `scripts/configure_desktop_node.sh`.
   Verify: `Xdcv.<user>.<sid>.log` should show `IGLX: Loaded and initialized
   swrast` right after `Initializing extension GLX`.

   NOTE: software GL is necessary but not sufficient — see cause 3.

2. **Intermittent "Failed while waiting for outputs" even with swrast loaded
   (the primary cause).**
   Multiple desktop jobs packed onto one node create concurrent DCV virtual
   sessions for the *same* user; they contend on shared home / D-Bus / devices
   (DCV explicitly warns against this) and Xdcv intermittently fails to report its
   display. Confirmed on a live node: 3 sessions created rapidly -> flaky; 3
   sessions created sequentially with cleanup between -> 3/3 succeed.
   **Fix:** run one DCV session per node -- `--exclusive` in the desktop job's
   sbatch `native` args (`assets/ood-dcv/bc_desktop/submit.yml.erb` and
   `scripts/configure_ood_for_pcs.sh`).

3. **Desktop dies / "connection has been lost" (`Could not get owner of name
   'org.gnome.Shell'`).**
   A DCV virtual session already launches the OS default desktop (GNOME on
   AL2023) itself, wired to the user's real D-Bus + `systemd --user`. Launching a
   second `gnome-session` from OOD (via `dbus-run-session`) runs on an isolated
   bus and fails.
   **Fix:** don't launch a desktop from OOD. `run_script` in
   `assets/ood-dcv/templates/dcv.rb` skips the desktop script and just holds the
   batch job open until the DCV session ends.

## Notes

- Don't run multiple virtual sessions for the same user on one node at once — DCV
  warns against it (shared home / D-Bus / devices).
- Desktop nodes are dynamic (`MinCount: 0`); a new job usually provisions a fresh
  node. To test a bootstrap change, re-upload the script and ensure no warm node
  is reused:
  ```bash
  aws s3 cp scripts/configure_desktop_node.sh \
    s3://<cluster-config-bucket>/configure_desktop_node.sh
  sinfo -p desktop -N        # confirm nodes are idle/powered down before launching
  ```
