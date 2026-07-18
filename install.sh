#!/usr/bin/env bash
#
#  macify - make Ubuntu GNOME look like macOS in one script.
#
#  Bundles: WhiteSur GTK / icons / cursors, Extension Manager,
#  Dash to Dock, Blur my Shell, user-theme extension.
#
#  Usage:  ./install.sh [--help]
#
set -euo pipefail

# ── colors ──────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GREEN=$'\e[32m'
    YELLOW=$'\e[33m'; BLUE=$'\e[34m'; CYAN=$'\e[36m'; RESET=$'\e[0m'
else
    BOLD='' DIM='' RED='' GREEN='' YELLOW='' BLUE='' CYAN='' RESET=''
fi

LOG="$(mktemp /tmp/macify-XXXXXX.log)"
TMP="$(mktemp -d)"
STEP=0
TOTAL=7

banner() {
    printf '%s' "$CYAN"
    cat <<'EOF'

    ███╗   ███╗ █████╗  ██████╗██╗███████╗██╗   ██╗
    ████╗ ████║██╔══██╗██╔════╝██║██╔════╝╚██╗ ██╔╝
    ██╔████╔██║███████║██║     ██║█████╗   ╚████╔╝
    ██║╚██╔╝██║██╔══██║██║     ██║██╔══╝    ╚██╔╝
    ██║ ╚═╝ ██║██║  ██║╚██████╗██║██║        ██║
    ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝╚═╝        ╚═╝
EOF
    printf '%s' "$RESET"
    printf '    %s The macOS look for Ubuntu - one script.%s\n\n' "$DIM" "$RESET"
}

step()  { STEP=$((STEP + 1)); printf '%s[%d/%d]%s %s%s%s\n' "$BLUE" "$STEP" "$TOTAL" "$RESET" "$BOLD" "$1" "$RESET"; }
ok()    { printf '      %s✔%s %s\n' "$GREEN" "$RESET" "$1"; }
warn()  { printf '      %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
die()   { printf '\n%s✘ %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

on_error() {
    printf '\n%s✘ Step %d failed.%s Full log: %s%s%s\n' \
        "$RED" "$STEP" "$RESET" "$BOLD" "$LOG" "$RESET" >&2
    printf '%sLast lines of log:%s\n' "$DIM" "$RESET" >&2
    tail -n 10 "$LOG" >&2 || true
}
trap on_error ERR
trap 'rm -rf "$TMP"' EXIT

usage() {
    banner
    cat <<EOF
${BOLD}Usage:${RESET} ./install.sh

Installs and applies:
  • WhiteSur GTK, icon and cursor themes
  • Extension Manager + GNOME Tweaks
  • Dash to Dock (macOS-style dock) + Blur my Shell
  • Window buttons on the left, shell theme, dock styling

${BOLD}Undo:${RESET} see README.md - all changes are plain gsettings + themes.
EOF
    exit 0
}
[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && usage

# ── preflight ───────────────────────────────────────────────────────────────
banner
[ "$(id -u)" -eq 0 ] && die "Run as a normal user, not root. sudo is used only where needed."
command -v gnome-shell >/dev/null 2>&1 || die "GNOME not found - this script targets Ubuntu with GNOME."
command -v apt-get     >/dev/null 2>&1 || die "apt-get not found - this script targets Ubuntu/Debian."
printf '%sDetected:%s GNOME %s · log: %s\n\n' "$DIM" "$RESET" \
    "$(gnome-shell --version | grep -oE '[0-9.]+' | head -1)" "$LOG"

# ── steps ───────────────────────────────────────────────────────────────────
step "Installing packages"
sudo apt-get update >>"$LOG" 2>&1
sudo apt-get install -y git sassc curl python3 gnome-tweaks \
    gnome-shell-extension-manager gnome-shell-extensions >>"$LOG" 2>&1
ok "git, sassc, GNOME Tweaks, Extension Manager, user-theme extension"

step "Installing WhiteSur GTK theme"
if [ -d "$HOME/.themes/WhiteSur-Dark" ]; then
    ok "already installed - skipped (delete ~/.themes/WhiteSur-* to reinstall)"
else
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$TMP/gtk" >>"$LOG" 2>&1
    "$TMP/gtk/install.sh" -c Dark -c Light >>"$LOG" 2>&1
    ok "WhiteSur Light + Dark"
fi

step "Installing WhiteSur icons"
if [ -d "$HOME/.local/share/icons/WhiteSur-dark" ]; then
    ok "already installed - skipped"
else
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git "$TMP/icons" >>"$LOG" 2>&1
    "$TMP/icons/install.sh" >>"$LOG" 2>&1
    ok "WhiteSur icon theme"
fi

step "Installing WhiteSur cursors"
if [ -d "$HOME/.local/share/icons/WhiteSur-cursors" ]; then
    ok "already installed - skipped"
else
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-cursors.git "$TMP/cursors" >>"$LOG" 2>&1
    "$TMP/cursors/install.sh" >>"$LOG" 2>&1
    ok "WhiteSur cursors"
fi

# Install a GNOME extension from extensions.gnome.org by UUID.
install_ext() {
    local uuid="$1" name="$2" shell_ver info url
    if gnome-extensions list 2>/dev/null | grep -qx "$uuid"; then
        gnome-extensions enable "$uuid" 2>>"$LOG" || true
        ok "$name already installed - skipped"
        return 0
    fi
    shell_ver="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)"
    if ! info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_ver}")"; then
        warn "$name: not available for GNOME $shell_ver, skipped"
        return 0
    fi
    url="$(printf '%s' "$info" | python3 -c 'import json,sys;print(json.load(sys.stdin)["download_url"])')"
    curl -fsSL "https://extensions.gnome.org${url}" -o "$TMP/${uuid}.zip"
    gnome-extensions install --force "$TMP/${uuid}.zip" >>"$LOG" 2>&1
    if gnome-extensions enable "$uuid" 2>>"$LOG"; then
        ok "$name installed and enabled"
    else
        warn "$name installed - enable it after next login (Extension Manager)"
    fi
}

step "Installing extensions"
install_ext "dash-to-dock@micxgx.gmail.com" "Dash to Dock"
install_ext "blur-my-shell@aunetx"          "Blur my Shell"
gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true

step "Applying themes"
gsettings set org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark'
gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur-dark'
gsettings set org.gnome.desktop.interface cursor-theme 'WhiteSur-cursors'
gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'
if gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com 2>>"$LOG"; then
    gsettings set org.gnome.shell.extensions.user-theme name 'WhiteSur-Dark' || true
    ok "GTK, icons, cursors, shell theme → WhiteSur Dark"
else
    ok "GTK, icons, cursors → WhiteSur Dark"
    warn "shell theme: enable 'User Themes' after next login, then pick WhiteSur-Dark in Tweaks"
fi

step "Styling dock"
for kv in "dock-position 'BOTTOM'" "extend-height false" "dash-max-icon-size 48" \
          "dock-fixed false" "intellihide true" "show-apps-at-top true"; do
    # shellcheck disable=SC2086
    gsettings set org.gnome.shell.extensions.dash-to-dock $kv 2>/dev/null || true
done
ok "bottom · centered · autohide · 48px icons"

# ── done ────────────────────────────────────────────────────────────────────
printf '\n%s%s  All done.%s\n\n' "$GREEN" "$BOLD" "$RESET"
printf '  %s→%s Log out and back in for the full effect.\n' "$CYAN" "$RESET"
printf '  %s→%s Fine-tune with %sGNOME Tweaks%s or %sExtension Manager%s.\n' \
    "$CYAN" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET"
printf '  %s→%s Full log: %s\n\n' "$CYAN" "$RESET" "$LOG"
