#!/usr/bin/env zsh
# Split a text file at the line that matches a given substring.
# Usage:
#   split_at_substring.zsh -f <input_file> -s <substring> [options]
#
# Options:
#   -f <file>           Input text file (required)
#   -s <substring>      Substring to match (required)
#   -o <prefix>         Output prefix for generated files (default: derived from input)
#   -n <occurrence>     Split at the nth occurrence (default: 1)
#   -i                  Case-insensitive match
#   --to-first          Put the matching line into the FIRST part
#   --to-second         Put the matching line into the SECOND part (default)
#   --discard           Discard the matching line (exclude from both parts)
#   -h|--help           Show help

set -euo pipefail

print_help() {
  cat <<'EOF'
Split a text file at the line which matches a given substring.

Usage:
  split_at_substring.zsh -f <input_file> -s <substring> [options]

Required:
  -f <file>           Input text file
  -s <substring>      Substring to match

Options:
  -o <prefix>         Output prefix (default: input basename without extension)
  -n <occurrence>     Split at nth match (default: 1)
  -i                  Case-insensitive match
  --to-first          Include the matching line in the FIRST part
  --to-second         Include the matching line in the SECOND part (default)
  --discard           Exclude the matching line from both parts
  -h, --help          Show this help

Outputs:
  <prefix>_part1.txt
  <prefix>_part2.txt

Examples:
  # Split at first occurrence; matching line goes to second part (default)
  split_at_substring.zsh -f logs.txt -s "ERROR"

  # Case-insensitive, include matching line in first part
  split_at_substring.zsh -f data.txt -s "header" -i --to-first

  # Split at the 3rd occurrence and discard the matching line
  split_at_substring.zsh -f input.txt -s "BREAKPOINT" -n 3 --discard
EOF
}

# -------- Parse arguments --------
input_file=""
substring=""
output_prefix=""
occurrence=1
ignore_case=0
placement="second"  # 'first' | 'second' | 'discard'

# zsh-friendly option parsing
args=("$@")
i=1
while (( i <= $#args )); do
  arg="${args[i]}"
  case "$arg" in
    -h|--help)
      print_help; exit 0 ;;
    -f)
      (( i++ ))
      input_file="${args[i]:-}"
      ;;
    -s)
      (( i++ ))
      substring="${args[i]:-}"
      ;;
    -o)
      (( i++ ))
      output_prefix="${args[i]:-}"
      ;;
    -n)
      (( i++ ))
      occurrence="${args[i]:-1}"
      if ! printf "%d" "$occurrence" >/dev/null 2>&1 || (( occurrence < 1 )); then
        echo "Error: -n <occurrence> must be a positive integer." >&2
        exit 1
      fi
      ;;
    -i)
      ignore_case=1
      ;;
    --to-first)
      placement="first"
      ;;
    --to-second)
      placement="second"
      ;;
    --discard)
      placement="discard"
      ;;
    *)
      echo "Unknown option: $arg" >&2
      print_help
      exit 1
      ;;
  esac
  (( i++ ))
done

# -------- Validate inputs --------
if [[ -z "$input_file" || -z "$substring" ]]; then
  echo "Error: -f <file> and -s <substring> are required." >&2
  print_help
  exit 1
fi

if [[ ! -f "$input_file" ]]; then
  echo "Error: Input file not found: $input_file" >&2
  exit 1
fi

# Derive default output prefix from input filename (basename without extension)
if [[ -z "$output_prefix" ]]; then
  base="${input_file:t}"           # filename only
  output_prefix="${base%.*}"       # strip last extension
  [[ -z "$output_prefix" ]] && output_prefix="$base"
fi

part1="${output_prefix}_part1.txt"
part2="${output_prefix}_part2.txt"

# -------- Perform split in one awk pass --------
# We do a substring match (not regex), optionally case-insensitive.
# Behavior:
#   - Lines BEFORE the nth match go to part1.
#   - AFTER the nth match go to part2.
#   - For the MATCHING line:
#       --to-first: goes to part1
#       --to-second: goes to part2 (default)
#       --discard: not written to any file

awk \
  -v pat="$substring" \
  -v occ="$occurrence" \
  -v placement="$placement" \
  -v out1="$part1" \
  -v out2="$part2" \
  -v ignore="$ignore_case" '
BEGIN {
  found_occurrence_line = 0
  match_count = 0
  # Open output files explicitly to ensure truncation
  close(out1); close(out2)
}
{
  line = $0
  # Substring match (case-insensitive if ignore==1)
  if (ignore == 1) {
    m = (index(tolower(line), tolower(pat)) > 0)
  } else {
    m = (index(line, pat) > 0)
  }

  if (m) {
    match_count++
  }

  # If we are EXACTLY at the line of the nth occurrence
  if (m && match_count == occ && found_occurrence_line == 0) {
    found_occurrence_line = 1
    if (placement == "first") {
      print line >> out1
    } else if (placement == "second") {
      print line >> out2
    } else if (placement == "discard") {
      # skip writing the matching line
    }
    next
  }

  # Before split point (haven’t reached nth occurrence yet)
  if (found_occurrence_line == 0) {
    print line >> out1
  } else {
    # After split point
    print line >> out2
  }
}
END {
  if (found_occurrence_line == 0) {
    # No split performed: remove possibly created files to avoid partial output confusion
    # Note: awk cannot remove files portably; we signal via exit code and message.
    printf("No match found for substring (occurrence=%d). No split performed.\n", occ) > "/dev/stderr"
    exit 1
  }
}
' "$input_file"

echo "Split complete:"
echo "  First part:  $part1"
echo "  Second part: $part2"
``
