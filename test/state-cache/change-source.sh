#!/usr/bin/env bash
# Edits the fixture's JSON source the way a later commit would: one string
# changes, a doubled space is fixed and a string is added. The Markdown source
# is left alone, so a restored parse cache still holds a valid entry for it.
#
# usage: change-source.sh <project-dir>
set -euo pipefail
cat > "$1/locales/en.json" << 'JSON'
{
  "greeting": "Welcome back, {name}!",
  "farewell": "Goodbye and good luck.",
  "cta": "Start your free trial today",
  "items": "You have {count} items in your cart",
  "empty": "Your cart is empty"
}
JSON
