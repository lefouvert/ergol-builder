#!/bin/sh

set -u

#set -x # debug

# Expect ~5-10 seconds to execute the full script on modern hardware.

# The magic key (*) is bound to `dead_abovecomma`.

# Notes about the compose table:
#
# 1. The compose table is designed with the eurlatgr font in mind.
#
# 2. The compose table cannot have more than 256 entries.
#   In order to stay below this limit, an exclusion table is built.
#
#   Combinations matching the following rules are excluded from the global compose table:
#   - Characters reachable from one of the 4 basic layers of Ergo-L (plain, Shift, AltGr, Shift+AltGr).
#   - Characters reachable via Ergo-L's magic dead key (*).
#       This implies that AltGr+Shift+'q' (`dead_circumflex`) + 'a' won't work (^a)
#       because 'â' is already reachable via magic deadkey (*) + 'q' (â).
#   - Characters with the same dead key fallback combination but lower priority.
#       To further reduce the size of the compose table, conflicting combinations
#       sharing the same fallback character are excluded based on a priority table. For example:
#       - `dead_breve` uses '~' as its fallback character.
#       - `dead_kbreve` uses 'U' as its fallback character.
#       - `dead_tilde` uses '~' as its fallback character.
#       - `dead_tilde` is higher on the priority list than `dead_breve`
#       Since `dead_breve` is used and collides with `dead_tilde`, the priority table
#       masks `dead_breve` in favor of `dead_tilde`. Thus, 'Ã' is reachable but 'Ă' is not.
#       However, if a character allow breve but no tilde, it is reachable ('Ğ').
#       * This behavior helps shorten the compose table.
#       * This behavior allows using the '/usr/share/X11/locale/en_US.UTF-8/Compose' file
#         to discover compose combinations that do not recognize kernel dead keys like `dead_kbreve`.
#
# 3. Specific to dead_diaeresis and dead_greek:
#   Since these layers are not native but accessed via a compose key, a few points must be considered:
#   - The fallback key is the Unicode codepoint matching the hexadecimal value of the dead key.
#       This hexadecimal value can be retrieved using the `dumpkeys -l` command in a TTY.
#   - The dead key behavior is preserved only if the second key of the composition is a dead key.
#
#   A workaround can be implemented for `dead_diaeresis`
#   since its second composition key is a dead key (")" / `dead_abovecomma`).
#   However, this workaround cannot work for `dead_greek` since its second composition key is "g".
#
#   Note that the Unicode codepoints are:
#   - `dead_diaeresis`: "Є" (U+0404)
#   - `dead_greek`: "Ѝ" (U+040D)
#
#   This "hack" is located here:
#   main
#   └── build_compose
#       └── write_compose
#           └── hack_deadkey
#
#   Access to Greek characters has been dropped to alleviate the compose table
#   and avoid building more complex workarounds than the one for dead_diaeresis
#   (thereby reducing the dependency on the exclusion table).

# script's file
readonly SCRIPT_DIR=$(dirname "$0")

readonly LOG_FILE="${SCRIPT_DIR}/ergol_builder.log"
readonly TARGET="${SCRIPT_DIR}/built.map"
readonly MAP_FILE="${SCRIPT_DIR}/fr-ergol.map.gz"

# system files
readonly BARE_KEYS="/usr/share/kbd/keymaps/i386/include/linux-keys-bare.inc"
readonly ALT_KEYS="/usr/share/kbd/keymaps/i386/include/linux-with-alt-and-altgr.inc"
readonly COMPOSE_X11="/usr/share/X11/locale/en_US.UTF-8/Compose"

# generaded file
#   `dumpkeys -l > ~/…/builder/keysym.txt` (TTY only)
readonly KEYSYM="${SCRIPT_DIR}/keysym.txt"
#   /!\ TTY_FONT_MAP is not a path /!\
readonly TTY_FONT_MAP=$(zcat "/usr/share/kbd/consolefonts/eurlatgr.psfu.gz" | psfgettable - )

# Manualy made files
readonly HEADER="${SCRIPT_DIR}/header.txt"
readonly SPECIALS="${SCRIPT_DIR}/specialkeys.txt"

readonly ERGOL_NUM="${SCRIPT_DIR}/ergo-l_numrow.txt"
readonly ERGOL_UPPER="${SCRIPT_DIR}/ergo-l_upperrow.txt"
readonly ERGOL_HOME="${SCRIPT_DIR}/ergo-l_homerow.txt"
readonly ERGOL_LOWER="${SCRIPT_DIR}/ergo-l_lowerrow.txt"
readonly ERGOL_SPACE="${SCRIPT_DIR}/ergo-l_spacerow.txt"

readonly COMPOSE_ERGOL="${SCRIPT_DIR}/compose_ergol.txt"

# build compose table
readonly MAX_COMPOSE=256
compose_count=$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$COMPOSE_ERGOL" | wc -l )

readonly PRIORITY_DEAD_KEYS="
dead_acute
dead_grave
dead_circumflex
dead_diaeresis
dead_tilde
dead_caron
dead_breve
dead_macron
dead_doubleacute
dead_abovedot
dead_abovering
dead_abovecomma
dead_cedilla
dead_ogonek
dead_belowcomma
dead_stroke
dead_currency
"
#dead_greek
#"


# Unicode calculations
#   decimal ceil for codepoint for each UTF-8 byte size
readonly UTF8_MAX_1BYTE=127       # 0x7F     (7 relevant bits)
readonly UTF8_MAX_2BYTES=2047     # 0x7FF    (11 relevant bits)
readonly UTF8_MAX_3BYTES=65535    # 0xFFFF   (16 relevant bits)
readonly UTF8_MAX_4BYTES=1114111  # 0x10FFFF (Unicode absolut limit)

#   decimal bits' Mask applied to the first byte
readonly UTF8_PREFIX_1BYTE=0      # 0b00000000 (0xxxxxxx)
readonly UTF8_PREFIX_2BYTES=192   # 0b11000000 (110xxxxx)
readonly UTF8_PREFIX_3BYTES=224   # 0b11100000 (1110xxxx)
readonly UTF8_PREFIX_4BYTES=240   # 0b11110000 (1111xxxx)

#   decimal bits' mask applied for all following bytes
readonly UTF8_PREFIX_CONT=128     # 0b10000000 (10xxxxxx)

#   right shift (2^6, 2^12, 2^18)
readonly SHIFT_6BITS=64
readonly SHIFT_12BITS=4096
readonly SHIFT_18BITS=262144


# ============ ADD FILE ============

assert_file_exists() {
  # $1 path to file to test. Mandatory
  if [ ! -f "$1" ]; then
    echo "Error: File not found ('$1')" | tee -a "$LOG_FILE" >&2
    exit 1
  fi
}


draw_line() (
  _iteration="$1"
  if [ "$_iteration" -lt 1 ]; then
    echo "draw_line : not enough iteration (${_iteration} < 1)" >> "${LOG_FILE}"
    return 0
  fi

  printf "# "
  while [ "$_iteration" -gt 0 ]; do
    printf "="
    _iteration=$((_iteration - 1))
  done
  printf "\n"
)


write_title() (
  _title="$1"
  _title_len="${#_title}"

  if [ "$_title_len" -lt 1 ]; then
    echo "write_title : title too short (${_title_len} < 1)" >> "${LOG_FILE}"
    return 0
  fi

  printf "\n"
  draw_line "$_title_len"
  printf "%s\n" "# $_title"
  draw_line "$_title_len"
  printf "\n"
)


get_file_name() (
  _file_path="$1"

  _file_name=$(basename "$_file_path")
  _file_name_no_ext="${_file_name%.*}"
  printf "%s" "$_file_name_no_ext" | tr '[:upper:]' '[:lower:]'
)


add_bloc() {
  assert_file_exists "$1"
  _file_path_to_add="$1"

  write_title $(get_file_name "$_file_path_to_add")

  grep -i -v "include" "$_file_path_to_add"
}


# ======= UNICODE FUNCTIONS ========

is_codepoint() (
  _codepoint="$1"
  case "$_codepoint" in
    U+????|U+?????|U+??????)
      case "${_codepoint#U+}" in
        *[!0-9a-fA-F]*) return 1 ;;
        *) return 0 ;;
      esac ;;
    *) return 1 ;;
  esac
)


convert_codepoint_to_char() (
  _codepoint="${1#U+}"

  _dec=$(printf "%d" "0x$_codepoint")
  _oct=""

  if [ "$_dec" -le $UTF8_MAX_1BYTE ]; then
    _oct=$(printf "\\%03o" "$_dec")
  elif [ "$_dec" -le $UTF8_MAX_2BYTES ]; then
    _byte1=$(( (_dec / SHIFT_6BITS) + UTF8_PREFIX_2BYTES ))
    _byte2=$(( (_dec % SHIFT_6BITS) + UTF8_PREFIX_CONT ))
    _oct=$(printf "\\%03o\\%03o" $_byte1 $_byte2)
  elif [ "$_dec" -le $UTF8_MAX_3BYTES ]; then
    _byte1=$(( (_dec / SHIFT_12BITS) + UTF8_PREFIX_3BYTES ))
    _byte2=$(( ((_dec / SHIFT_6BITS) % SHIFT_6BITS) + UTF8_PREFIX_CONT ))
    _byte3=$(( (_dec % SHIFT_6BITS) + UTF8_PREFIX_CONT ))
    _oct=$(printf "\\%03o\\%03o\\%03o" $_byte1 $_byte2 $_byte3)
  elif [ "$_dec" -le $UTF8_MAX_4BYTES ]; then
    _byte1=$(( (_dec / SHIFT_18BITS) + UTF8_PREFIX_4BYTES ))
    _byte2=$(( ((_dec / SHIFT_12BITS) % SHIFT_6BITS) + UTF8_PREFIX_CONT ))
    _byte3=$(( ((_dec / SHIFT_6BITS) % SHIFT_6BITS) + UTF8_PREFIX_CONT ))
    _byte4=$(( (_dec % SHIFT_6BITS) + UTF8_PREFIX_CONT ))
    _oct=$(printf "\\%03o\\%03o\\%03o\\%03o" $_byte1 $_byte2 $_byte3 $_byte4)
  fi
  printf "%b" "$_oct"
)


convert_char_to_codepoint() (
  _char="$1"

  _byte_count=$(printf "%s" "$_char" | wc -c)
  if [ "$_byte_count" -eq 0 ] || [ "$_byte_count" -gt 4 ]; then
    echo "convert_char_to_codepoint : not a valid char (${_char}, bytes = $_byte_count)" >> "$LOG_FILE"
    return 1
  fi

  _hexa=$(printf "%s" "$_char" | iconv -f UTF-8 -t UTF-16BE | od -An -tx1 | tr -d ' \n')

  [ -z "$_hexa" ] && _hexa="0"

  printf "U+%04X" "0x$_hexa"
)


# ======= ERGO-L DEFINITION ========

get_unicode_comment() (
  _key="$1"

  if is_codepoint "$_key";then
    printf " # '%s'" "$(convert_codepoint_to_char "${_key}")"
  fi
)


search_modifier() (
  _key="$1"
  _modifier="$2"

  if grep -q "${_modifier}${_key}" "$KEYSYM"; then
    printf "%s" "${_modifier}${_key}"
  else
    printf "VoidSymbol"
  fi
)


write_modifier_variation() {
  _option="$1"
  _keycode="$2"
  _symbol="$3"

  _prefix=""

  case "$_option" in
    -s)  _prefix="Shift       " ;;
    -a)  _prefix="      Altgr " ;;
    -sa) _prefix="Shift Altgr " ;;
    *)   _prefix="            " ;;
  esac

  _val_base="$_symbol"
  _val_ctrl=$(search_modifier "$_symbol" "Control_")
  _val_alt=$(search_modifier "$_symbol" "Meta_")
  _val_ctrl_alt=$(search_modifier "$_val_ctrl" "Meta_")

  case "$_val_base" in
    [a-z]) _capslock_sensitive="+";;
    *)     _capslock_sensitive="" ;;
  esac

  cat << EOF
$(printf "%-68s" "${_prefix}            keycode $_keycode = ${_capslock_sensitive}${_val_base}")$(get_unicode_comment "$_val_base")
$(printf "%-68s" "${_prefix}Control     keycode $_keycode = ${_val_ctrl}")$(get_unicode_comment "$_val_ctrl")
$(printf "%-68s" "${_prefix}        Alt keycode $_keycode = ${_val_alt}")$(get_unicode_comment "$_val_alt")
$(printf "%-68s" "${_prefix}Control Alt keycode $_keycode = ${_val_ctrl_alt}")$(get_unicode_comment "$_val_ctrl_alt")
EOF
}


write_keycode() {
  _line="$1"

  set -f  # Désactive le globbing
  set -- $_line
  set +f  # Réactive le globbing

  _keycode=$(printf "%3s" "$2")

  _void="VoidSymbol"
  _plain="${4:-$_void}"
  _shifted="${5:-$_void}"
  _alt_gr="${6:-$_void}"
  _shifted_alt_gr="${7:-$_void}"

  write_modifier_variation ""    "$_keycode" "$_plain"
  write_modifier_variation "-s"  "$_keycode" "$_shifted"
  write_modifier_variation "-a"  "$_keycode" "$_alt_gr"
  write_modifier_variation "-sa" "$_keycode" "$_shifted_alt_gr"
}


processing_ergol() {
  assert_file_exists "$1"
  _file_to_process="$1"

  write_title $(get_file_name "$_file_to_process")

  while read -r _line; do
    case "$_line" in
      keycode[[:space:]]*[0-9]*) write_keycode "$_line" ;;
    esac
  done < "$_file_to_process"
}


# ========== SCAN COMPOSE ==========

get_fallback() {
    case "$1" in
        dead_currency)      echo "$"  ;;
        dead_abovering)     echo "*"  ;;
        dead_abovecomma)    echo ")"  ;;
        dead_acute)         echo "\\'";;
        dead_diaeresis)     echo '"'  ;;
        dead_grave)         echo "\`" ;;
        dead_abovedot)      echo "."  ;;
        dead_stroke)        echo "-"  ;;
        dead_macron)        echo "_"  ;;
        dead_belowcomma)    echo ";"  ;;
        dead_greek)         echo "@"  ;;
        dead_cedilla)       echo ","  ;;
        dead_ogonek)        echo ","  ;;
        dead_circumflex)    echo "^"  ;;
        dead_caron)         echo "^"  ;;
        dead_tilde)         echo "~"  ;;
        dead_doubleacute)   echo "~"  ;;
        dead_breve)         echo "~"  ;;
        dead_kbreve)        echo "U"  ;;
        dead_kcaron)        echo "c"  ;;
        dead_kdoubleacute)  echo "="  ;;
        dead_kogonek)       echo "k"  ;;
        dead_iota)          echo "i"  ;;
        dead_voiced_sound)  echo "#"  ;;
        dead_semivoiced_sound)  echo "o"  ;;
        dead_belowdot)      echo "!"  ;;
        dead_hook)          echo "?"  ;;
        dead_horn)          echo "+"  ;;
        dead_doublegrave)   echo ":"  ;;
        dead_invertedbreve) echo "n"  ;;
        *) echo "get_fallback : Unknown dead key (${1})" >> "${LOG_FILE}"
          return 1 ;;
    esac
}


hack_deadkey() (
  _dk_to_test="$1"

  case "$_dk_to_test" in
    dead_diaeresis|dead_greek) _hexcode=$(awk -v dk="$_dk_to_test" '$2 == dk {print $1}' "$KEYSYM") ;;
    *) return 0 ;;
  esac

  [ -n "$_hexcode" ] && printf "%s" "U+${_hexcode#0x}"
)


write_compose() {
  _dead_key="${1}"
  _alpha_key="${2}"
  _composed_uni="${3}"
  _composed_char="${4}"

  if [ -z "${_dead_key}" ] || [ -z "${_alpha_key}" ] || [ -z "${_composed_uni}" ] || [ -z "${_composed_char}" ]; then
    echo "write_compose : argument missing (expected : dead_key alpha_key composed_uni composed_char)" >> "${LOG_FILE}"
    return 1
  fi

  _fallback=$(get_fallback "${_dead_key}")

  if [ -z "${_fallback}" ]; then
    echo "write_compose : fallback for '$_dead_key' not found." >> "${LOG_FILE}"
    return 1
  fi

  _hacked_val=$(hack_deadkey "$_dead_key")
  _fallback="${_hacked_val:-'$_fallback'}"

  printf "%-17s" "compose ${_fallback}"
  printf "%-9s"  "'${_alpha_key}'"
  printf "%-10s" "to ${_composed_uni}"
  printf "%s\n"  "# ${_composed_char}"
}


validate_compose() {
  _codepoint="${1}"

#  if printf "%s\n" "$TTY_FONT_MAP" | grep -E -i "U\+${_codepoint#U+}([[:space:]]|$)" >/dev/null; then
#    return 0
#  fi

  if printf "%s\n" "$TTY_FONT_MAP" | awk -v cp="${_codepoint#U+}" '
    tolower($0) ~ "u\\+" tolower(cp) "([[:space:]]|$)" { found=1; exit }
    END { exit !found }
  '; then
    return 0
  fi

  echo "validate_compose : '${_codepoint}' not in \`TTY_FONT_MAP\`." >> "${LOG_FILE}"
  return 1
}


get_all_compose(){
  _dead_keys_pattern=$(echo "$PRIORITY_DEAD_KEYS" | awk '
  NF { printf (first ? "|" : "") $1; first=1 }
  ')

#  grep -E "^<(${_dead_keys_pattern})>[[:space:]]+<[a-zA-Z]>" "$COMPOSE_X11" \
#    | sed -E 's/^<([^>]+)>[[:space:]]+<([^>]+)>[[:space:]]*:[[:space:]]*"([^"]+)".*$/\1:\2:\3/' \
#    > "$tmp_compose"

  awk -v pat="^<($_dead_keys_pattern)>[[:space:]]+<[a-zA-Z]>" '
    $0 ~ pat {
      match($0, /^<[^>]+>/); dk = substr($0, RSTART+1, RLENGTH-2)
      rest = substr($0, RSTART+RLENGTH)
      match(rest, /<[^>]+>/); alpha = substr(rest, RSTART+1, RLENGTH-2)
      match($0, /"[^"]+"/); char = substr($0, RSTART+1, RLENGTH-2)

      if (dk != "" && alpha != "" && char != "") {
        print dk ":" alpha ":" char
      }
    }
  ' "$COMPOSE_X11"
}


# ======= EXCLUSION COMPOSE ========

exclude_keysym(){
  _keysym_keys_def="$1"

  while read -r _hexcode _keysym _dummy; do
    case "$_hexcode" in
      0x*) ;;
      *) continue ;;
    esac

    if [ $((_hexcode)) -gt 255 ]; then # 0x00ff
      continue
    fi

    case "$_keysym_keys_def" in
      *[[:space:]]"$_keysym"[[:space:]]*) printf "U+%s\n" "${_hexcode#0x}" ;;
    esac
  done < "$KEYSYM"
}


exclude_codepoint(){
  _codepoint_keys_def="$1"

  while read -r _identifier _dummy _dummy _plain _composed_or_shift _altgr _shift_altgr _dummy; do
    case "$_identifier" in
      compose)
        is_codepoint "$_composed_or_shift"  && printf "%s\n" "$_composed_or_shift"
        ;;
      keycode)
        is_codepoint "$_plain"              && printf "%s\n" "$_plain"
        is_codepoint "$_composed_or_shift"  && printf "%s\n" "$_composed_or_shift"
        is_codepoint "$_altgr"              && printf "%s\n" "$_altgr"
        is_codepoint "$_shift_altgr"        && printf "%s\n" "$_shift_altgr"
        ;;
      *) continue ;;
    esac
  done << EOF
$_codepoint_keys_def
EOF
}


get_dk_weight() (
  _to_scale="$1"
  _weight_found=$(echo "$PRIORITY_DEAD_KEYS" | grep -n -w "$_to_scale" | cut -d: -f1)

  printf "%s" "${_weight_found:-99}"
)


# static but faster way
get_dk_weight_fast() (
  _to_scale="$1"

  case "$_to_scale" in
    dead_acute)       printf "1" ;;
    dead_grave)       printf "2" ;;
    dead_circumflex)  printf "3" ;;
    dead_diaeresis)   printf "4" ;;
    dead_tilde)       printf "5" ;;
    dead_caron)       printf "6" ;;
    dead_breve)       printf "7" ;;
    dead_macron)      printf "8" ;;
    dead_doubleacute) printf "9" ;;
    dead_abovedot)    printf "10" ;;
    dead_abovering)   printf "11" ;;
    dead_abovecomma)  printf "12" ;;
    dead_cedilla)     printf "13" ;;
    dead_ogonek)      printf "14" ;;
    dead_belowcomma)  printf "15" ;;
    dead_stroke)      printf "16" ;;
    dead_currency)    printf "17" ;;
    *)                printf "99" ;;
  esac
)


exclude_colision(){
  assert_file_exists "$1"

  _full_compose_file="$1"

  # build priority list
  while IFS=":" read -r _deadkey _char _composed _dummy; do
    [ -z "$_deadkey" ] && continue

    _fallback_key=$(get_fallback "$_deadkey")
    [ -z "$_fallback_key" ] && continue

    _dk_weight=$(get_dk_weight "$_deadkey")

    printf "%s%s:%s:%s\n" "$_fallback_key" "$_char" "$_dk_weight" "$_composed" \
      >> "$tmp_weighted_compose"
  done < "$_full_compose_file"

  # exclude collide
  _current_combo=""
  while IFS=":" read -r _combo _weight _composed; do
    if [ "$_combo" = "$_current_combo" ]; then
      _codepoint=$(convert_char_to_codepoint "$_composed")

      printf "%s\n" "$_codepoint"
    else
      _current_combo="$_combo"
    fi
  done << EOF
$(sort -t ':' -k1,1 -k2,2n "$tmp_weighted_compose")
EOF
}


get_all_exclusion(){
  assert_file_exists "$1"
  _all_compose="$1"

  _manual_keys_def=$(cat "${SCRIPT_DIR}"/ergo-l_*.txt "$COMPOSE_ERGOL" 2>/dev/null)

  exclude_keysym "$_manual_keys_def"
  exclude_codepoint "$_manual_keys_def"
  exclude_colision "$_all_compose"
}


is_not_excluded(){
  assert_file_exists "$2"

  _to_check="$1"
  _exclusion_file="$2"

  [ -z "$_to_check" ] && return 0

  if grep -i -q -x -F "$_to_check" "$_exclusion_file"; then
    return 1
  else
    return 0
  fi
}


build_compose() {
  assert_file_exists "$COMPOSE_X11"

  get_all_compose > "$tmp_compose"
  get_all_exclusion "$tmp_compose" > "$tmp_excluded"

  while IFS=":" read -r _deadk _alpha _char; do
    _codepoint=$(convert_char_to_codepoint "$_char")

    if validate_compose "$_codepoint" \
    && is_not_excluded "$_codepoint" "$tmp_excluded"; then
      write_compose "$_deadk" "$_alpha" "$_codepoint" "$_char"
      compose_count=$((compose_count + 1))
    fi
  done < "$tmp_compose"
}


# ============== MAIN ==============

init() {
  tmp_compose="${SCRIPT_DIR}/.tmp_compose_$$"
  touch "$tmp_compose"

  tmp_excluded="${SCRIPT_DIR}/.tmp_excluded_$$"
  touch "$tmp_excluded"

  tmp_weighted_compose="${SCRIPT_DIR}/.tmp_wcompose_$$"
  touch "$tmp_weighted_compose"
}


clean_up() {
  rm -f "$tmp_compose"
  rm -f "$tmp_excluded"
  rm -f "$tmp_weighted_compose"
}


main() {
  echo "main : start" > "${LOG_FILE}"
  assert_file_exists "$HEADER"
  assert_file_exists "$KEYSYM"

  trap 'clean_up' EXIT INT TERM

  init

  {
    cat "$HEADER"
    add_bloc "$BARE_KEYS"
    add_bloc "$ALT_KEYS"
    write_title "ergo-l mapping"
    processing_ergol "$ERGOL_NUM"
    processing_ergol "$ERGOL_UPPER"
    processing_ergol "$ERGOL_HOME"
    processing_ergol "$ERGOL_LOWER"
    processing_ergol "$ERGOL_SPACE"
    add_bloc "$SPECIALS"
    write_title "compose global"
    build_compose
    add_bloc "$COMPOSE_ERGOL"
  } > "$TARGET"
  echo "${compose_count} compositions added." >> "${LOG_FILE}"

  if [ ${compose_count} -ge ${MAX_COMPOSE} ]; then
    echo "main : More than $MAX_COMPOSE entries in the composition table. Invalid map file." | tee -a "${LOG_FILE}" 1>&2
    exit 1
  else
    gzip -c9 "${TARGET}" > "${MAP_FILE}"
  fi
}

main
exit 0
