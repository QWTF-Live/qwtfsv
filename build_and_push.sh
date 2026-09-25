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
# has to be built and pushed before it can land here. Checked rather than
# assumed: a stale updater bakes in the pre-shard paths and nothing notices
# until the updater service fails on a deployed host.
docker pull qwtflive/updater:latest
if ! docker run --rm --entrypoint grep qwtflive/updater:latest \
     -q '/srv/shards' /updater/entrypoint.sh; then
  echo "build: qwtflive/updater:latest predates the shard layout." >&2
  echo "       Build and push ../updater first, then re-run this." >&2
  exit 1
fi

# Build with BuildKit via buildx (the legacy `docker build` builder is deprecated),
# then tag and push in a single step.
docker buildx build \
  --tag qwtflive/fortressone:latest \
  --load \
  --push \
  .
