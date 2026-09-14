#!/usr/bin/env bash
# Launch GNOME inside the DCV virtual display for an Open OnDemand desktop.
#
# The stock OOD bc_desktop gnome.sh targets GNOME 2 (gconftool-2, gnome-session
# classic), which does not exist on the GNOME 3 / 40+ shipped by the DCV-supported
# OSes (Amazon Linux 2023, RHEL/Rocky 8/9, Ubuntu). This launcher uses GNOME 3
# tooling and starts the session on its own D-Bus so it runs under the headless
# DCV virtual X server (Xdcv). It blocks until the session exits, which keeps the
# batch-connect job -- and therefore the DCV session -- alive.

# DCV starts Xdcv with an X authority cookie; point X clients at it so connecting
# to the virtual display doesn't fail with "Authorization required".
xauth_file=$(ps -o args= -C Xdcv 2>/dev/null | sed -n 's/.*-auth \([^ ]*\).*/\1/p' | head -1)
[ -n "${xauth_file}" ] && export XAUTHORITY="${xauth_file}"

# Xdcv is X11-only; force the X11 session so GNOME doesn't attempt Wayland.
export XDG_SESSION_TYPE=x11

# Compute nodes have no GPU. gnome-shell is a GL compositor and aborts (never
# acquires org.gnome.Shell) unless it can fall back to Mesa software rendering, so
# force llvmpipe. Requires the mesa-dri-drivers / mesa-libGL packages on the node.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

# Best-effort: disable screensaver/lock (ignore if the schema isn't installed).
gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true

# Start GNOME on a dedicated session bus (blocks until the desktop exits).
exec dbus-run-session -- gnome-session
