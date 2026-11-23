#!/usr/bin/env bash
# ============================================================================
#  Claude Code status line
#
#  🧠 Sonnet 5.5 │ ⚡️ high │ ctx ███░░░ 42% │ 5h ███░░░ 37% │ 7d █████░ 81% │ ↻ 5h 2h11m · 7d 3d11h │ in:48.2k out:2.1k
#
#  How it works: Claude Code pipes session data as JSON to this script's stdin.
#  The script prints one line, and Claude Code shows it as the status line.
#
#  Requires: bash, jq, a terminal with 24-bit color.
#  Docs: https://code.claude.com/docs/en/statusline
#
#  To customize, edit only the SETTINGS section below.
# ============================================================================


# ============================================================================
#  SETTINGS
# ============================================================================

# --- Which segments to show, and in what order -------------------------------
# Remove a name to hide that segment. Reorder names to reorder the line.
#   model     🧠 current model
#   effort    ⚡️ reasoning effort
#   context   context window usage bar
#   limit_5h  5-hour rate limit bar
#   limit_7d  weekly rate limit bar
#   resets    time until both limits reset
#   tokens    input/output tokens in the context window
SEGMENTS=(model effort context limit_5h limit_7d resets tokens)

# --- Bars (context, 5h, 7d) ------------------------------------------------------
BAR_WIDTH=16          # bar length in characters
BAR_SHOWS="used"      # "used" = bar fills up as you spend, "remaining" = bar drains

# --- Icons and text ------------------------------------------------------------
ICON_MODEL="🧠"
ICON_EFFORT="⚡️"
ICON_RESET="🔄"
SEPARATOR="│"         # between segments
RESET_SEPARATOR="·"   # between 5h and 7d inside the "resets" segment
LABEL_CTX="ctx"
LABEL_5H="5h"
LABEL_7D="7d"
NO_DATA="n/a"         # shown when Claude Code sends no value

# --- Colors (hex, like in CSS) -------------------------------------------------
COLOR_MODEL="#7ED6B4"      # mint
COLOR_EFFORT="#F06270"     # coral red
COLOR_TEXT="#C8C8C8"       # numbers and labels
COLOR_DIM="#6E6E6E"        # separators, "n/a"
COLOR_BAR_CTX="#7AA2F7"    # context bar: soft blue
COLOR_BAR_5H="#E8707A"     # 5-hour bar: salmon
COLOR_BAR_7D="#4EBEAC"     # weekly bar: teal
COLOR_BAR_EMPTY="#3A3A3A"  # empty part of a bar: dark gray

BOLD_MODEL=true            # true / false


# ============================================================================
#  HELPERS  (no need to edit below this line)
# ============================================================================

RESET_STYLE=$'\e[0m'
BOLD_STYLE=$'\e[1m'

# Turn "#RRGGBB" into a terminal color code.
#   text_color "#FF0000"  -> colored text
#   bg_color   "#FF0000"  -> colored background (used to draw bars)
hex_to_rgb() {
  local hex=${1#\#}
  printf '%d;%d;%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}
text_color() { printf '\e[38;2;%sm' "$(hex_to_rgb "$1")"; }
bg_color()   { printf '\e[48;2;%sm' "$(hex_to_rgb "$1")"; }

# Print text in a color:  paint "#FF0000" "hello"
paint() { printf '%s%s%s' "$(text_color "$1")" "$2" "$RESET_STYLE"; }

# Format a token count: 950 -> 950, 48213 -> 48.2k, 1200000 -> 1.2M
format_tokens() {
  local n=${1%.*}
  if   (( n >= 1000000 )); then awk -v n="$n" 'BEGIN { printf "%.1fM", n / 1000000 }'
  elif (( n >= 1000 ));    then awk -v n="$n" 'BEGIN { printf "%.1fk", n / 1000 }'
  else printf '%d' "$n"
  fi
}

# Format time left until a Unix timestamp: 3d11h, 2h11m, 25m, now
format_time_left() {
  local reset_at=$1
  if [[ -z $reset_at ]]; then printf '%s' "$NO_DATA"; return; fi

  local seconds=$(( ${reset_at%.*} - $(date +%s) ))
  if (( seconds <= 0 )); then printf 'now'; return; fi

  local days=$((    seconds / 86400 ))
  local hours=$((   seconds % 86400 / 3600 ))
  local minutes=$(( seconds % 3600 / 60 ))

  if   (( days > 0 ));  then printf '%dd%dh'   "$days"  "$hours"
  elif (( hours > 0 )); then printf '%dh%02dm' "$hours" "$minutes"
  else                       printf '%dm'      "$minutes"
  fi
}

# Draw a solid bar:  draw_bar <percent 0-100> <fill color>
# The bar is made of spaces with a colored background, so it has no gaps.
draw_bar() {
  local percent=$1 fill_color=$2

  (( percent < 0 ))   && percent=0
  (( percent > 100 )) && percent=100

  local filled=$(( (percent * BAR_WIDTH + 50) / 100 ))
  (( percent > 0 && filled == 0 )) && filled=1   # keep a sliver visible above 0%
  local empty=$(( BAR_WIDTH - filled ))

  (( filled > 0 )) && printf '%s%*s' "$(bg_color "$fill_color")"      "$filled" ''
  (( empty > 0 ))  && printf '%s%*s' "$(bg_color "$COLOR_BAR_EMPTY")" "$empty"  ''
  printf '%s ' "$RESET_STYLE"
  paint "$COLOR_TEXT" "$(printf '%3d%%' "$percent")"
}


# ============================================================================
#  READ DATA FROM CLAUDE CODE
# ============================================================================

# All values are read with one jq call. Missing values become empty strings.
# Values are separated by \x1f so empty values are not lost.
IFS=$'\x1f' read -r \
  model_name effort_level thinking_enabled \
  used_ctx used_5h reset_at_5h used_7d reset_at_7d \
  tokens_in tokens_out \
  < <(jq -r '[
        (.model.display_name // .model.id // "?"),
        (.effort.level // ""),
        (if .thinking.enabled == null then "" else .thinking.enabled end),
        (.context_window.used_percentage        // ""),
        (.rate_limits.five_hour.used_percentage // ""),
        (.rate_limits.five_hour.resets_at       // ""),
        (.rate_limits.seven_day.used_percentage // ""),
        (.rate_limits.seven_day.resets_at       // ""),
        (.context_window.total_input_tokens     // 0),
        (.context_window.total_output_tokens    // 0)
      ] | map(tostring) | join("\u001f")')


# ============================================================================
#  SEGMENTS  (one function per segment name in SEGMENTS)
# ============================================================================

segment_model() {
  local style=""
  [[ $BOLD_MODEL == true ]] && style=$BOLD_STYLE
  printf '%s %s' "$ICON_MODEL" "$style$(paint "$COLOR_MODEL" "$model_name")"
}

segment_effort() {
  local value
  if   [[ -n $effort_level ]];        then value=$effort_level
  elif [[ $thinking_enabled == true ]];  then value="think:on"
  elif [[ $thinking_enabled == false ]]; then value="think:off"
  else                                     value=$NO_DATA
  fi
  paint "$COLOR_EFFORT" "$ICON_EFFORT$value"
}

segment_tokens() {
  paint "$COLOR_TEXT" "in:$(format_tokens "$tokens_in") out:$(format_tokens "$tokens_out")"
}

# Shared logic for all bars:  usage_bar <label> <used %> <bar color>
# BAR_SHOWS decides whether the bar shows the used or the remaining share.
usage_bar() {
  local label=$1 used=$2 bar_color=$3

  paint "$COLOR_TEXT" "$label "
  if [[ -z $used ]]; then
    paint "$COLOR_DIM" "$NO_DATA"
    return
  fi

  local used_int=${used%.*}
  if [[ $BAR_SHOWS == "used" ]]; then
    draw_bar "$used_int" "$bar_color"
  else
    draw_bar $(( 100 - used_int )) "$bar_color"
  fi
}

segment_context()  { usage_bar "$LABEL_CTX" "$used_ctx" "$COLOR_BAR_CTX"; }
segment_limit_5h() { usage_bar "$LABEL_5H"  "$used_5h"  "$COLOR_BAR_5H";  }
segment_limit_7d() { usage_bar "$LABEL_7D"  "$used_7d"  "$COLOR_BAR_7D";  }

segment_resets() {
  paint "$COLOR_DIM" "$ICON_RESET"
  printf ' %s %s' "$(paint "$COLOR_BAR_5H" "$LABEL_5H")" "$(paint "$COLOR_TEXT" "$(format_time_left "$reset_at_5h")")"
  printf ' %s ' "$(paint "$COLOR_DIM" "$RESET_SEPARATOR")"
  printf '%s %s'  "$(paint "$COLOR_BAR_7D" "$LABEL_7D")" "$(paint "$COLOR_TEXT" "$(format_time_left "$reset_at_7d")")"
}


# ============================================================================
#  BUILD THE LINE
# ============================================================================

line=""
for name in "${SEGMENTS[@]}"; do
  # Skip "resets" when Claude Code sent no reset times at all
  if [[ $name == resets && -z $reset_at_5h && -z $reset_at_7d ]]; then
    continue
  fi

  part=$("segment_$name")
  if [[ -n $line ]]; then
    line+=" $(paint "$COLOR_DIM" "$SEPARATOR") "
  fi
  line+=$part
done

printf '%s\n' "$line"
