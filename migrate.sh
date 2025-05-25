#!/bin/bash
set -euo pipefail

OLD_VERSION=${OLD_PG_VERSION:-13}
NEW_VERSION=${NEW_PG_VERSION:-16}
MIGRATION_UID=${MIGRATION_UID:-70}

OLD_DATA="/var/lib/postgresql/old"
NEW_DATA="/var/lib/postgresql/new"
OLD_BIN="/usr/lib/postgresql/$OLD_VERSION/bin"
NEW_BIN="/usr/lib/postgresql/$NEW_VERSION/bin"

# Create a 'postgres' user with the target UID, if needed
if ! getent passwd "$MIGRATION_UID" >/dev/null; then
    echo "🛠 Creating 'postgres' user with UID $MIGRATION_UID..."

    # Check if 'postgres' group exists
    if getent group postgres >/dev/null; then
        POSTGRES_GID=$(getent group postgres | cut -d: -f3)
    else
        POSTGRES_GID="$MIGRATION_UID"
        groupadd -g "$POSTGRES_GID" postgres
    fi

    useradd -u "$MIGRATION_UID" -g "$POSTGRES_GID" -d /var/lib/postgresql -s /bin/bash postgres
    mkdir -p /var/lib/postgresql
    chown -R "$MIGRATION_UID:$POSTGRES_GID" /var/lib/postgresql
else
    echo "✅ 'postgres' user with UID $MIGRATION_UID already exists"
fi
echo "✅ Running as UID $MIGRATION_UID"

# Function to run commands as the created user
as_postgres() {
    su postgres -c "$*"
}

echo "🔍 Checking directories..."
[ -d "$OLD_DATA" ] || { echo "❌ Missing $OLD_DATA"; exit 1; }
[ -d "$NEW_DATA" ] || { echo "❌ Missing $NEW_DATA"; exit 1; }

echo "🔎 Checking that new data directory is empty..."
[ -z "$(ls -A "$NEW_DATA")" ] || { echo "❌ $NEW_DATA is not empty."; exit 1; }

PG_VERSION_FILE="$OLD_DATA/PG_VERSION"
[ -f "$PG_VERSION_FILE" ] || { echo "❌ Missing $PG_VERSION_FILE"; exit 1; }

echo "📁 Initializing new data cluster..."
as_postgres "$NEW_BIN/initdb -D $NEW_DATA"
echo "✅ Initialization complete"

echo "🔎 Running pre-upgrade check..."
as_postgres "$NEW_BIN/pg_upgrade \
    --old-datadir=$OLD_DATA \
    --new-datadir=$NEW_DATA \
    --old-bindir=$OLD_BIN \
    --new-bindir=$NEW_BIN \
    --check"

echo "✅ Check passed"

echo "🚀 Starting upgrade..."
as_postgres "$NEW_BIN/pg_upgrade \
    --old-datadir=$OLD_DATA \
    --new-datadir=$NEW_DATA \
    --old-bindir=$OLD_BIN \
    --new-bindir=$NEW_BIN \
    --jobs=2 \
    --verbose \
    --copy \
    --write-planner-stats"

echo "🎉 Migration complete!"