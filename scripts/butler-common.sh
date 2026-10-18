# Shared helpers for launch-butler.sh and test-butler.sh. Source it; don't run it.

# stop_butler ROOT — stop any Butler app running from the repo at ROOT (build/,
# test-build/ or a swift run). Only one instance can own the ⌘⌥F / ⌘⌥P hotkeys,
# so both launch scripts converge to exactly one fresh instance. Its backend
# (butler-core) exits on its own when the app goes.
stop_butler() {
    local root="$1"
    # Escape regex metacharacters in the path so pgrep/pkill match it literally.
    local root_re pattern running
    root_re="$(printf '%s' "$root" | sed 's/[][\\.*^$+?(){}|]/\\&/g')"
    pattern="^$root_re/.*/Butler$"
    running="$(pgrep -fl "$pattern" || true)"
    if [[ -n "$running" ]]; then
        echo "==> Stopping running Butler:"
        echo "$running" | sed 's/^/      PID /'
        pkill -f "$pattern" || true
        sleep 1
    else
        echo "==> No running Butler to stop"
    fi
}
