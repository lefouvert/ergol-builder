#!/bin/sh

# loadkeys tester

test_map="$1"

XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
# regarde si la variable XDG_RUNTIME_DIR existe et n'est pas vide. Si ce n'est pas le cas, on la valorise avec /run/user/$UID
trunc="${XDG_RUNTIME_DIR}/truncated.map"

readonly SCRIPT_DIR=$(dirname "$0")
readonly LOG_FILE="${SCRIPT_DIR}/loadkey_tester.log"

assert_file_exists() {
  if [ ! -f "$1" ]; then
    echo "Error: File not found ('$1')" | tee -a "$LOG_FILE" >&2
    exit 1
  fi
}

assert_file_exists "$test_map"
readonly MAX_LINES=$(wc -l < "$test_map")

trap 'rm -f "$trunc"' EXIT INT TERM

echo "Analysis of '$test_map' ('$MAX_LINES lines')" | tee "$LOG_FILE"

for i in $(seq "$MAX_LINES"); do
  head -n "$i" < "$test_map" > "$trunc"

  error_output=$(loadkeys -u -p "$trunc" 2>&1 >/dev/null)
  if [ $? -ne 0 ]; then
    bad_line=$(tail -n 1 < "$trunc")
    {
      echo "Error detected at line '$i': '$bad_line'"
      echo "Error message : '$error_output'"
    } | tee -a "$LOG_FILE" >&2
    exit 1
  fi
done

echo "'$test_map' is a valide file" | tee -a "$LOG_FILE"
exit 0
