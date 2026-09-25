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

# Build with BuildKit via buildx (the legacy `docker build` builder is
# deprecated). Loaded but NOT pushed yet: nothing below has run the image, and
# an image that cannot start is worth catching here rather than on a host.
docker buildx build \
  --tag qwtflive/fortressone:latest \
  --load \
  .

# tf-init is the one service whose failure is fatal - S6_BEHAVIOUR_IF_STAGE2_FAILS
# stops the container - so a mistake in it costs every shard on the host. It
# shipped broken once already: the s6 `up` file ran it with /bin/sh, which on
# Ubuntu is dash, and the script needs bash for `set -o pipefail`. Nothing in a
# build catches that, because a build never starts the image.
echo "==> Smoke test: tf-init"
if ! docker run --rm --entrypoint /qwtfsv/bin/tf-init qwtflive/fortressone:latest; then
  echo "build: tf-init fails inside the image; not pushing." >&2
  exit 1
fi

# And the shards must at least be able to parse their own launcher.
echo "==> Smoke test: tf-shard argv"
if ! docker run --rm --entrypoint bash qwtflive/fortressone:latest \
     -n /qwtfsv/bin/tf-shard; then
  echo "build: tf-shard does not parse inside the image; not pushing." >&2
  exit 1
fi

docker push qwtflive/fortressone:latest
