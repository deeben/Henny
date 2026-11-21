#!/bin/bash
# Checks the compatibility profiles and uploads them next to the Wine runtime on R2,
# where Henny looks for updates when it starts.
# Run from the repository root on a Mac signed in to wrangler: scripts/publish-profiles.sh
set -euo pipefail

PROFILES="HennyKit/Sources/HennyKit/Resources/profiles.json"
BUCKET_PATH="henny/Wine/profiles.json"
PUBLIC_URL="https://henny.deezlepower.com/Wine/profiles.json"

python3 scripts/check-profiles.py "$PROFILES"

# Henny keeps whichever copy has the higher revision, so a forgotten bump would be ignored.
# No live copy yet (or anything that isn't a profiles file) counts as revision 0.
LIVE_REVISION=$(curl -fsS "$PUBLIC_URL" 2>/dev/null | python3 -c '
import json, sys
try:
    print(int(json.load(sys.stdin)["revision"]))
except Exception:
    print(0)
' || true)
LIVE_REVISION=${LIVE_REVISION:-0}
NEW_REVISION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["revision"])' "$PROFILES")
if [ "$NEW_REVISION" -le "$LIVE_REVISION" ]; then
    echo "revision $NEW_REVISION is not higher than the live revision $LIVE_REVISION; bump it first." >&2
    exit 1
fi

# Use an installed wrangler, or else run it through npx
if command -v wrangler >/dev/null 2>&1; then
    WRANGLER=(wrangler)
else
    WRANGLER=(npx --yes wrangler)
fi
"${WRANGLER[@]}" r2 object put "$BUCKET_PATH" --remote --file "$PROFILES" \
    --content-type "application/json" --cache-control "max-age=300"
echo "Published revision $NEW_REVISION to $PUBLIC_URL"
