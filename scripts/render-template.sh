#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <template-file> <output-file>" >&2
  exit 1
fi

template_file="$1"
output_file="$2"

[[ -f "$template_file" ]] || {
  echo "Template not found: $template_file" >&2
  exit 1
}

LC_ALL=C perl -0777 -pe 's/\{\{([A-Z0-9_]+)\}\}/exists $ENV{$1} ? $ENV{$1} : $&/ge' "$template_file" > "$output_file"

if grep -Eq '\{\{[A-Z0-9_]+\}\}' "$output_file"; then
  echo "Unresolved template variables in $output_file" >&2
  grep -Eo '\{\{[A-Z0-9_]+\}\}' "$output_file" | sort -u >&2
  exit 1
fi
