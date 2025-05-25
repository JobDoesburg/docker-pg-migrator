#!/bin/bash
set -euo pipefail

OLD_VERSION=${OLD_PG_VERSION:-13}
NEW_VERSION=${NEW_PG_VERSION:-16}

OLD_DATA="/var/lib/postgresql/old"
NEW_DATA="/var/lib/postgresql/new"
OLD_BIN="/usr/lib/postgresql/$OLD_VERSION/bin"
NEW_BIN="/usr/lib/postgresql/$NEW_VERSION/bin"

# Use UID/GID from environment if set, else detect
CURRENT_UID=${UID:-$(id -u)}
CURRENT_GID=${GID:-$(id -g)}

# Ensure a valid passwd entry exists for the current UID (required by initdb/pg_upgrade)
if ! getent passwd "$CURRENT_UID" >/dev/null; then
    echo "🛠 No passwd entry for UID $CURRENT_UID. Adding entry to /etc/passwd..."
    echo "postgres:x:$CURRENT_UID:$CURRENT_GID:PostgreSQL:/var/lib/postgresql:/bin/bash" >> /etc/passwd
fi

echo "✅ Using UID=$CURRENT_UID and GID=$CURRENT_GID"

echo "🔍 Checking directories..."
[ -d "$OLD_DATA" ] || { echo "❌ Old data directory not found: $OLD_DATA"; exit 1; }
[ -d "$NEW_DATA" ] || { echo "❌ New data directory not found: $NEW_DATA"; exit 1; }

echo "🔎 Checking that new data directory is empty..."
[ -z "$(ls -A "$NEW_DATA")" ] || { echo "❌ New data directory ($NEW_DATA) is not empty. Aborting."; exit 1; }

echo "📁 Initializing new data cluster..."
"$NEW_BIN/initdb" -D "$NEW_DATA"
echo "✅ Initialization complete"

echo "🔎 Running pre-upgrade check..."
"$NEW_BIN/pg_upgrade" \
    --old-datadir="$OLD_DATA" \
    --new-datadir="$NEW_DATA" \
    --old-bindir="$OLD_BIN" \
    --new-bindir="$NEW_BIN" \
    --check
echo "✅ Check passed"

echo "🚀 Starting upgrade..."
"$NEW_BIN/pg_upgrade" \
    --old-datadir="$OLD_DATA" \
    --new-datadir="$NEW_DATA" \
    --old-bindir="$OLD_BIN" \
    --new-bindir="$NEW_BIN" \
    --jobs=2 \
    --verbose \
    --copy \
    --write-planner-stats
echo ""

echo "🎉 Migration complete!"
echo "📌 New PostgreSQL $NEW_VERSION data is ready at $NEW_DATA"
echo "🛑 Old data at $OLD_DATA remains untouched (read-only mount)"