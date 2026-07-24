#!/usr/bin/env bash
set -Eeuo pipefail

target="${1:-337}"
archive_base="https://cdn.kernel.org/pub/linux/kernel/v4.x/incr"

read_make_value() {
  awk -F ' *= *' -v key="$1" '$1 == key { print $2; exit }' Makefile
}

version="$(read_make_value VERSION)"
patchlevel="$(read_make_value PATCHLEVEL)"
current="$(read_make_value SUBLEVEL)"

if [[ "${version}" != "4" || "${patchlevel}" != "9" ]]; then
  echo "ERROR: expected a Linux 4.9 source tree, found ${version}.${patchlevel}.${current}."
  exit 1
fi

if ! [[ "${current}" =~ ^[0-9]+$ && "${target}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: source and target sublevels must be integers."
  exit 1
fi

if (( current > target )); then
  echo "ERROR: source Linux 4.9.${current} is newer than target 4.9.${target}."
  exit 1
fi

if (( current == target )); then
  echo "Linux 4.9.${target} is already applied."
  exit 0
fi

mkdir -p .linux-stable-patches
echo "Updating Linux 4.9.${current} to 4.9.${target} one stable release at a time."

while (( current < target )); do
  next=$((current + 1))
  patch_name="patch-4.9.${current}-${next}.xz"
  patch_path=".linux-stable-patches/${patch_name}"
  patch_url="${archive_base}/${patch_name}"

  echo "::group::Apply Linux 4.9.${current} -> 4.9.${next}"
  curl --fail --location --retry 3 --retry-all-errors \
    --silent --show-error \
    --output "${patch_path}" \
    "${patch_url}"

  if ! xz --decompress --stdout "${patch_path}" \
      | patch --batch --forward -p1; then
    echo "::endgroup::"
    echo "ERROR: Linux stable update failed at 4.9.${current} -> 4.9.${next}."
    echo "Rejected hunks:"
    find . -path ./.git -prune -o -name '*.rej' -print
    exit 1
  fi

  actual="$(read_make_value SUBLEVEL)"
  if [[ "${actual}" != "${next}" ]]; then
    echo "::endgroup::"
    echo "ERROR: Makefile reports 4.9.${actual}; expected 4.9.${next}."
    exit 1
  fi

  rm -f "${patch_path}"
  current="${next}"
  echo "::endgroup::"
done

rmdir .linux-stable-patches
echo "Linux stable update completed successfully: 4.9.${target}."
