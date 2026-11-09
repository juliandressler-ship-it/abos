#!/bin/sh
# Startet den lokalen MCP-Server der Abos-App für Claude.
# Sucht die installierte App zuerst in /Applications, dann in ~/Applications,
# zuletzt per Spotlight über die Bundle-ID.

for app in "/Applications/Abos.app" "$HOME/Applications/Abos.app"; do
  if [ -x "$app/Contents/MacOS/Abos" ]; then
    exec "$app/Contents/MacOS/Abos" --mcp
  fi
done

app=$(mdfind "kMDItemCFBundleIdentifier == 'de.juliandressler.Abos'" 2>/dev/null | head -n 1)
if [ -n "$app" ] && [ -x "$app/Contents/MacOS/Abos" ]; then
  exec "$app/Contents/MacOS/Abos" --mcp
fi

echo "Abos.app wurde nicht gefunden. Bitte zuerst die App installieren." >&2
exit 1
