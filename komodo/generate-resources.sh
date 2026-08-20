#!/usr/bin/env bash
set -euo pipefail

STACKS_DIR="swarm/stacks"
OUTPUT="komodo/resources.toml"

# AJUSTE ESTES 4
SWARM="asteri"
GIT_PROVIDER="github.com"
GIT_ACCOUNT="gmnds"
REPO="gmnds/docker-infra"

BRANCH="main"

: > "$OUTPUT"

for dir in "$STACKS_DIR"/*; do
    [ -d "$dir" ] || continue

    name="$(basename "$dir")"

    files=()

    # Preferência: stack.yaml / stack.yml
    if [ -f "$dir/stack.yaml" ]; then
        files=("stack.yaml")
    elif [ -f "$dir/stack.yml" ]; then
        files=("stack.yml")
    else
        # Caso como Chatwoot: vários YAMLs
        while IFS= read -r file; do
            files+=("$(basename "$file")")
        done < <(
            find "$dir" -maxdepth 1 -type f \
                \( -name '*.yaml' -o -name '*.yml' \) \
                | sort
        )
    fi

    # Ignora diretórios sem YAML
    [ "${#files[@]}" -gt 0 ] || continue

    printf '[[stack]]\n' >> "$OUTPUT"
    printf 'name = "%s"\n' "$name" >> "$OUTPUT"
    printf '[stack.config]\n' >> "$OUTPUT"
    printf 'swarm = "%s"\n' "$SWARM" >> "$OUTPUT"
    printf 'git_provider = "%s"\n' "$GIT_PROVIDER" >> "$OUTPUT"
    printf 'git_account = "%s"\n' "$GIT_ACCOUNT" >> "$OUTPUT"
    printf 'repo = "%s"\n' "$REPO" >> "$OUTPUT"
    printf 'branch = "%s"\n' "$BRANCH" >> "$OUTPUT"
    printf 'run_directory = "%s/%s"\n' "$STACKS_DIR" "$name" >> "$OUTPUT"

    printf 'file_paths = [' >> "$OUTPUT"

    first=true
    for file in "${files[@]}"; do
        if "$first"; then
            first=false
        else
            printf ', ' >> "$OUTPUT"
        fi

        printf '"%s"' "$file" >> "$OUTPUT"
    done

    printf ']\n\n' >> "$OUTPUT"
done

echo "Gerado: $OUTPUT"
