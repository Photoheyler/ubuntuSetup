#!/bin/bash

cd /home/jetson || exit 1

# Snap-kompatibler Profilpfad
FIREFOX_PROFILE_DIR="$HOME/.mozilla/firefox/kiosk-profile"

# 1. Clean up stale instances and ONLY lockfiles (nicht das ganze Profil löschen!)
echo "[INFO] Cleaning up stale instances..."
pkill -9 -f "firefox" 2>/dev/null
find "$FIREFOX_PROFILE_DIR" -name "*lock*" -delete 2>/dev/null
docker compose down --remove-orphans 2>/dev/null

cleanup() {
    trap '' EXIT INT TERM HUP
    echo -e "\n[INFO] Shutting down..."

    # 1. Kill the browser immediately
    kill -9 "$BROWSER_PID" "$WATCHER_PID" 2>/dev/null
    pkill -9 -f "firefox" 2>/dev/null

    # 2. Stop containers
    docker compose down --timeout 2 2>/dev/null

    # 3. Pause terminal so errors remain visible
    echo "[INFO] Closing terminal in 2 seconds..."
    sleep 2

    # 4. Stop log streaming and exit
    kill "$LOGS_PID" 2>/dev/null
    exit 0
}

trap cleanup EXIT INT TERM HUP

# 2. Start containers and stream logs
echo "[INFO] Starting Docker containers..."
docker compose up -d
docker compose logs -f &
LOGS_PID=$!

# Monitor container: kills Firefox immediately if the container exits
CONTAINER_ID=$(docker compose ps -q | head -n 1)
(
    docker wait "$CONTAINER_ID" >/dev/null 2>&1
    pkill -9 -f "firefox" 2>/dev/null
) &
WATCHER_PID=$!

# 3. Wait for port 80
echo "[INFO] Waiting for port 80..."
until (echo > /dev/tcp/127.0.0.1/80) 2>/dev/null; do
    if ! docker ps -q --no-trunc | grep -q "^$CONTAINER_ID"; then
        echo "[ERROR] Container stopped unexpectedly before port 80 was ready."
        cleanup
    fi
    sleep 0.2
done

# 4. Prepare / Update Firefox Kiosk Profile configuration
mkdir -p "$FIREFOX_PROFILE_DIR"

cat << 'EOF' > "$FIREFOX_PROFILE_DIR/user.js"
// Touch, Zoom & Virtual Keyboard
user_pref("dom.w3c_touch_events.enabled", 1);
user_pref("ui.osk.enabled", true);
user_pref("ui.osk.detect_physical_keyboard", false);
user_pref("apz.touch_start_tolerance", 0.0);

// Zoom komplett sperren (verhindert Zoom bei 3-Finger Desktop-Swipes)
user_pref("apz.allow_zooming", false);
user_pref("browser.gesture.pinch.in", "");
user_pref("browser.gesture.pinch.out", "");
user_pref("browser.gesture.pinch.latched", false);
user_pref("browser.gesture.pinch.threshold", 1000);

// Disable GNOME / Firefox Splash, Animations & First Run
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "http://localhost:80");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.aboutwelcome.showModal", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.newtabpage.activity-stream.firstrun.didSeeAboutWelcome", true);
user_pref("browser.newtabpage.introShown", true);
user_pref("toolkit.cosmeticAnimations.enabled", false);
user_pref("browser.uitour.enabled", false);

// Suppress telemetry, updates and defaults
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("app.update.auto", false);
user_pref("app.update.enabled", false);
EOF

# 5. Launch Firefox Snap (DESKTOP_STARTUP_ID="" unterdrückt den GNOME-Start-Splash)
echo "[INFO] Launching Firefox..."
firefox \
    --profile "$FIREFOX_PROFILE_DIR" \
    --kiosk "http://localhost:80" \
    --no-remote \
    2>/dev/null &

BROWSER_PID=$!

# 6. Wait for Firefox to exit (triggers cleanup with sleep delay)
wait "$BROWSER_PID" 2>/dev/null