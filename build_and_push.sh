#!/bin/bash
set -euo pipefail

# crashwatch is a sibling checkout, not part of this build context, so stage
# the one file the image needs. Regenerated every build: the copy in vendor/ is
# a build artefact and is not committed.
CRASHWATCH=../crashwatch/qwtf_crashwatch.py
[[ -f $CRASHWATCH ]] || { echo "build: missing $CRASHWATCH" >&2; exit 1; }
mkdir -p vendor
cp "$CRASHWATCH" vendor/qwtf_crashwatch.py

# The image takes /updater from the published updater image, so a change there
# has to be built and pushed before it can land here.
docker pull qwtflive/updater:latest

# Build with BuildKit via buildx (the legacy `docker build` builder is deprecated),
# then tag and push in a single step.
docker buildx build \
  --tag qwtflive/fortressone:latest \
  --load \
  --push \
  .
