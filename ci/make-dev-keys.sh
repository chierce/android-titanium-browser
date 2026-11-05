#!/usr/bin/env bash
# Dev keystore for fork builds.
# Upstream CI expects two base64 secrets (LOCAL_TEST_JKS, STORE_TEST_JKS).
# A fork has neither, so build.sh dies at set_keys. This generates a throwaway
# key good enough to produce an installable, self-signed APK. It is NOT the
# upstream signing key and cannot update an upstream-installed app.
set -euo pipefail

OUT=${1:-ci/keys}
mkdir -p "$OUT"

KEY_ALIAS=${KEY_ALIAS:-titanium-dev}
STORE_PASS=${STORE_PASS:-titaniumdev}
KEY_PASS=${KEY_PASS:-titaniumdev}
DAYS=${DAYS:-10000}

if [ ! -f "$OUT/test.jks" ]; then
  keytool -genkeypair \
    -keystore "$OUT/test.jks" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA -keysize 2048 -validity "$DAYS" \
    -storepass "$STORE_PASS" -keypass "$KEY_PASS" \
    -dname "CN=Titanium Dev, OU=fork build, O=local, C=US" \
    -noprompt
fi

cat > "$OUT/local.properties" <<EOF
keyAlias=$KEY_ALIAS
keyPassword=$KEY_PASS
storePassword=$STORE_PASS
EOF

echo "wrote $OUT/test.jks and $OUT/local.properties"
echo
echo "to feed the upstream CI secrets, export these two values:"
echo "  LOCAL_TEST_JKS=$(base64 -w0 "$OUT/local.properties")"
echo "  STORE_TEST_JKS=$(base64 -w0 "$OUT/test.jks")"
echo
echo "(keys/ is gitignored upstream - do not commit test.jks)"