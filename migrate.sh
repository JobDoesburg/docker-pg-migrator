#!/bin/bash
set -euo pipefail

OLD_VERSION=${OLD_PG_VERSION:-13}
NEW_VERSION=${NEW_PG_VERSION:-16}

OLD_DATA="/var/lib/postgresql/old"
NEW_DATA="/var/lib/postgresql/new"
OLD_BIN="/usr/lib/postgresql/$OLD_VERSION/bin"
NEW_BIN="/usr/lib/postgresql/$NEW_VERSION/bin"

echo "🔍 Checking directories..."
if [ ! -d "$OLD_DATA" ]; then
    echo "❌ Old PostgreSQL data directory not found at $OLD_DATA!"
    exit 1
fi

if [ ! -d "$NEW_DATA" ]; then
    echo "❌ New PostgreSQL data directory not found at $NEW_DATA!"
    exit 1
fi

echo "🔍 Checking ownership of old data directory..."

PG_VERSION_FILE="$OLD_DATA/PG_VERSION"
if [ ! -f "$PG_VERSION_FILE" ]; then
    echo "❌ PG_VERSION file not found in old data directory. Is this a valid cluster?"
    exit 1
fi

FILE_UID=$(stat -c "%u" "$PG_VERSION_FILE")
CURRENT_UID=$(id -u)

if [ "$CURRENT_UID" -ne "$FILE_UID" ]; then
    echo "❌ Current user (UID $CURRENT_UID) does not match owner of PG_VERSION (UID $FILE_UID)"
    echo "💡 To fix this, run the container as UID $FILE_UID:"
    echo ""
    echo "    user: \"$FILE_UID:$FILE_UID\""
    echo ""
    echo "🛑 Aborting to avoid permission errors."
    exit 1
fi

echo "✅ UID check passed (running as correct user: $CURRENT_UID)"
echo ""

echo "🔎 Checking that new data directory is empty..."
if [ "$(ls -A "$NEW_DATA")" ]; then
    echo "❌ New data directory ($NEW_DATA) is not empty. Aborting for safety."
    exit 1
fi

echo "🔍 Verifying old cluster version..."
DETECTED_VERSION=$($OLD_BIN/pg_controldata "$OLD_DATA" | grep 'pg_control version number' || true)
if [[ -z "$DETECTED_VERSION" ]]; then
    echo "❌ Could not read pg_control data from old cluster. Is this a valid PostgreSQL $OLD_VERSION cluster?"
    exit 1
fi

echo "✅ Old cluster seems valid"
echo ""

echo "📦 PostgreSQL Upgrade"
echo "🔧 Old Version: $OLD_VERSION"
echo "🆕 New Version: $NEW_VERSION"
echo ""

echo "📁 Initializing new data cluster..."
$NEW_BIN/initdb -D "$NEW_DATA"
echo "✅ Initialization complete"
echo ""

echo "🔎 Running pre-upgrade check..."
"$NEW_BIN/pg_upgrade" \
    --old-datadir="$OLD_DATA" \
    --new-datadir="$NEW_DATA" \
    --old-bindir="$OLD_BIN" \
    --new-bindir="$NEW_BIN" \
    --check
echo "✅ Check passed"
echo ""

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
echo "📌 Your new PostgreSQL $NEW_VERSION data is ready at $NEW_DATA"
echo "🛑 The old data at $OLD_DATA remains untouched (read-only mount)"