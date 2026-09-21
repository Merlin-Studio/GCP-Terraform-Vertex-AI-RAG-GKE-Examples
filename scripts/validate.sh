#!/usr/bin/env bash
# Validate every Terraform root in this repository against Cloud Foundation Fabric.
#
#   scripts/validate.sh                 every root
#   scripts/validate.sh vertex          only roots whose name contains "vertex"
#
# Needs terraform (>= 1.12.2) and git. No Google Cloud account, no credentials,
# nothing is created: `terraform init -backend=false` and `terraform validate`.
#
# The stages are FAST stages: they reach Fabric's modules by relative path, so
# they are validated where they are meant to live, under fast/stages/ in a
# Fabric checkout. This script assembles that layout in a scratch directory and
# leaves the repository untouched. CI runs this same script.
set -uo pipefail

FABRIC_REF="${FABRIC_REF:-v58.0.0}"
filter="${1:-}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${VALIDATE_WORKDIR:-$repo/.validate}"

command -v terraform >/dev/null || { echo "terraform is not on the PATH"; exit 2; }
command -v git >/dev/null || { echo "git is not on the PATH"; exit 2; }

mkdir -p "$work"
if [ -n "${FABRIC_CHECKOUT:-}" ]; then
  fabric="$FABRIC_CHECKOUT"
else
  fabric="$work/fabric"
  if [ ! -d "$fabric/modules" ]; then
    echo "Fetching Cloud Foundation Fabric $FABRIC_REF (modules only)..."
    rm -rf "$fabric"
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$FABRIC_REF" --filter=blob:none --sparse \
      https://github.com/GoogleCloudPlatform/cloud-foundation-fabric.git "$fabric" || exit 2
    git -C "$fabric" sparse-checkout set modules || exit 2
  fi
fi
[ -d "$fabric/modules" ] || { echo "no modules/ in $fabric"; exit 2; }

tree="$work/tree"
rm -rf "$tree"; mkdir -p "$tree/fast/stages"
cp -r "$fabric/modules" "$tree/modules"
# One plugin cache, so the providers download once and not once per root.
export TF_PLUGIN_CACHE_DIR="$work/plugin-cache"; mkdir -p "$TF_PLUGIN_CACHE_DIR"

# Where each generated root lives in a Fabric checkout.
for stage in "$repo"/applications/3-*/ "$repo"/foundation/2-*/; do
  [ -d "$stage" ] && cp -r "$stage" "$tree/fast/stages/$(basename "$stage")"
done
for dept in "$repo"/departments/*/DEPARTMENT-*/; do
  [ -d "$dept" ] && cp -r "$dept" "$tree/fast/stages/$(basename "$dept")"
done

pass=0; fail=0
while IFS= read -r root; do
  name="${root#"$tree/fast/stages/"}"
  [ -n "$filter" ] && [[ "$name" != *"$filter"* ]] && continue
  if ( cd "$root" \
       && terraform init -backend=false -input=false -no-color >init.log 2>&1 \
       && terraform validate -no-color >validate.log 2>&1 ); then
    pass=$((pass + 1)); printf 'ok    %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'FAIL  %s\n' "$name"
    if [ -s "$root/validate.log" ]; then sed 's/^/      /' "$root/validate.log" | tail -12
    else sed 's/^/      /' "$root/init.log" | tail -12; fi
  fi
done < <(find "$tree/fast/stages" -name versions.tf | sed 's|/versions\.tf$||' | sort -u)

printf '\n%d passed, %d failed  (Fabric %s, %s)\n' "$pass" "$fail" "$FABRIC_REF" "$(terraform version | head -1)"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
