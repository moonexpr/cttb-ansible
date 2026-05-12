#!/bin/bash
# Regenerate wordmark.png from logo.png.
#
# Crops the bottom-right region of the full sx26 logo (globe + Sudhanix
# wordmark composite at 2722x2460) so the welcome panel sidebar shows the
# "Sudhanix" wordmark with a partial globe peek — and adds right padding
# so the wordmark sits nicely left-of-center inside the image. Bottom
# padding is naturally present in the source (dark space below the text)
# so no bottom extent is added.
#
# Final output: 1200x700, transparent PNG. The welcome panel scales this
# to 48px tall on load (see roles/sudhanix-core/files/welcome/sudhanix-welcome
# — `GdkPixbuf.Pixbuf.new_from_file_at_scale(WORDMARK_PATH, -1, 48, True)`).
#
# Run from this directory after editing logo.png:
#   ./regen-wordmark.sh

set -euo pipefail
cd "$(dirname "$0")"

magick logo.png \
  -crop '2232x1476+490+984' +repage \
  -background none -gravity northwest -extent '2530x1476' \
  -resize '1200x' \
  wordmark.png

echo "wrote $(pwd)/wordmark.png"
