#!/usr/bin/env bash
# Backfill actual token data from Claude Code JSONL transcript into latest sprint JSON.
# Run from repo root during or after a sprint session.
# Safe to run multiple times — re-run after session close for complete data.
set -euo pipefail

DATA_DIR=".claude/sprints-data"
CLAUDE_PROJECTS="$HOME/.claude/projects"

# Derive project hash: replace '/' with '-' in the full path
PROJECT_HASH=$(pwd | sed 's|/|-|g')
PROJECT_DIR="$CLAUDE_PROJECTS/$PROJECT_HASH"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "No Claude project data at $PROJECT_DIR"
  echo "Expected path derived from: $(pwd)"
  exit 1
fi

# Find the most recent JSONL transcript (handles both flat and nested layouts)
latest_transcript=$(find "$PROJECT_DIR" -name "*.jsonl" -type f \
  | xargs ls -t 2>/dev/null | head -1 || true)

if [[ -z "$latest_transcript" ]]; then
  echo "No JSONL transcript found under $PROJECT_DIR"
  exit 1
fi

# Find the most recent sprint JSON
latest_json=$(ls -t "$DATA_DIR"/SPRINT_*.json 2>/dev/null | head -1 || true)
if [[ -z "$latest_json" ]]; then
  echo "No sprint data files found in $DATA_DIR"
  exit 1
fi

echo "Transcript: $latest_transcript"
echo "Sprint JSON: $latest_json"
echo ""

python3 - "$latest_transcript" "$latest_json" <<'PYEOF'
import json, sys

transcript_path = sys.argv[1]
sprint_json_path = sys.argv[2]

input_tokens          = 0
output_tokens         = 0
cache_creation_tokens = 0
cache_read_tokens     = 0
message_count         = 0

with open(transcript_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        # Usage can appear at the top level or nested under "message"
        usage = (entry.get("usage")
                 or entry.get("message", {}).get("usage")
                 or {})
        if not usage:
            continue

        input_tokens          += usage.get("input_tokens", 0)
        output_tokens         += usage.get("output_tokens", 0)
        cache_creation_tokens += usage.get("cache_creation_input_tokens", 0)
        cache_read_tokens     += usage.get("cache_read_input_tokens", 0)
        message_count         += 1

with open(sprint_json_path) as f:
    sprint_data = json.load(f)

sprint_data["actual_tokens"] = {
    "input_tokens":                input_tokens,
    "output_tokens":               output_tokens,
    "cache_creation_input_tokens": cache_creation_tokens,
    "cache_read_input_tokens":     cache_read_tokens,
    "total_tokens":                input_tokens + output_tokens,
    "message_count":               message_count,
    "source":                      "jsonl_transcript",
    "note": ("Partial if run mid-session — "
             "re-run after session close for complete data")
}

with open(sprint_json_path, "w") as f:
    json.dump(sprint_data, f, indent=2)

print(f"  input_tokens:               {input_tokens:>10,}")
print(f"  output_tokens:              {output_tokens:>10,}")
print(f"  cache_creation_tokens:      {cache_creation_tokens:>10,}")
print(f"  cache_read_tokens:          {cache_read_tokens:>10,}")
print(f"  total_tokens:               {input_tokens + output_tokens:>10,}")
print(f"  messages analyzed:          {message_count:>10,}")
print()
print(f"Backfilled into {sprint_json_path}")
PYEOF
