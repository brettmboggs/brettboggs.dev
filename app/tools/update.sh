#!/usr/bin/env bash
#
# Pull the latest app and put it on the phone. The one command to run.
#
#   ./app/tools/update.sh
#
# Xcode rewrites the generated project when you open it, which makes git
# refuse to pull. The project is regenerated on every build anyway, so
# those edits are thrown away first.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

git checkout -- app 2>/dev/null
git pull --ff-only || { echo "Could not pull. Paste the lines above into the conversation."; exit 1; }
exec ./app/tools/install.sh
