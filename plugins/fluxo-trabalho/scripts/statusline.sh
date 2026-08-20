#!/bin/bash
# Enriched status line based on the default Fedora PS1: [\u@\h \W]\$
# Layout: [user@host dir]  path  git-branch*  model  venv/node  time

input=$(cat)

have_jq=0
command -v jq >/dev/null 2>&1 && have_jq=1

cwd=""
model=""
transcript=""
if [ "$have_jq" -eq 1 ]; then
  cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
  model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
  model_id=$(printf '%s' "$input" | jq -r '.model.id // empty' 2>/dev/null)
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  # rate limits (só p/ Pro/Max, após 1ª resposta da API; cada janela pode faltar)
  rl_5h_pct=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
  rl_5h_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
  rl_7d_pct=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
  rl_7d_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
  cost_usd=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)
else
  # Best-effort fallback without jq (simple grep/sed, may miss escaped values)
  cwd=$(printf '%s' "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"(.*)"/\1/')
  model=$(printf '%s' "$input" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"(.*)"/\1/')
fi

[ -z "$cwd" ] && cwd="$(pwd)"
[ -z "$model" ] && model="unknown"

# epoch do início da sessão (1º timestamp do transcript) — usado p/ saber o que rodou nesta sessão
sess_start=""
if [ "$have_jq" -eq 1 ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  iso=$(jq -rs 'map(.timestamp // empty) | .[0] // empty' "$transcript" 2>/dev/null)
  [ -n "$iso" ] && sess_start=$(date -d "$iso" +%s 2>/dev/null)
fi

# ANSI colors (dim-friendly palette)
RESET=$'\033[0m'
DIM=$'\033[2m'
GRAY=$'\033[90m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
YELLOW=$'\033[33m'
MAGENTA=$'\033[35m'
RED=$'\033[31m'
ORANGE=$'\033[38;5;208m'

# ---- helpers ----
# cor conforme % de uso (cinza <60, amarelo >=60, vermelho >=85)
pct_color() {
  local p=${1%.*} c="$GRAY"
  [ "$p" -ge 60 ] 2>/dev/null && c="$YELLOW"
  [ "$p" -ge 85 ] 2>/dev/null && c="$RED"
  printf '%s' "$c"
}
# barra de progresso ▓/░ colorida: make_bar <pct> <largura>
make_bar() {
  local pct=${1%.*} width=${2:-10}
  [ -z "$pct" ] && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  local filled=$(( (pct*width + 50) / 100 )) i bar=""
  [ "$filled" -gt "$width" ] && filled=$width
  for ((i=0;i<filled;i++)); do bar="${bar}▓"; done
  for ((i=filled;i<width;i++)); do bar="${bar}░"; done
  printf '%b%s%b' "$(pct_color "$pct")" "$bar" "$RESET"
}
# duração em segundos -> "2d3h" / "3h5m" / "12m"
fmt_dur() {
  local s=${1%.*}
  [ -z "$s" ] && { printf '?'; return; }
  [ "$s" -lt 0 ] 2>/dev/null && s=0
  local d=$((s/86400)) h=$(((s%86400)/3600)) m=$(((s%3600)/60))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  else                       printf '%dm' "$m"; fi
}

# horário de expediente (ajustável) — usado p/ calcular "prazo útil" antes do reset
WORK_WINDOWS=("07:30" "11:30" "13:30" "18:00")

hm_to_epoch() {
  local day_epoch="$1" hm="$2"
  local h=${hm%%:*} m=${hm##*:}
  printf '%s' $(( day_epoch + h*3600 + m*60 ))
}

# acha o fim da última janela de expediente que termina antes do reset (ou o próprio
# reset, se ele cair dentro de uma janela — nesse caso não sobra sessão). skip_weekend=1
# pula sáb/dom (uso semanal). Retorna também o início da janela (WORK_WINDOWS) a que
# esse fim pertence, pra dar contexto do turno inteiro (ex: "07:30-11:30").
calc_deadline() {
  local reset_epoch="$1" skip_weekend="$2"
  [ -z "$reset_epoch" ] && { printf '0 0 0'; return; }
  local today_midnight=$(date -d "today 00:00:00" +%s 2>/dev/null)
  local day_epoch="$today_midnight" best=0 no_waste=0 best_start=0 i=0
  while [ "$day_epoch" -le "$reset_epoch" ] && [ "$i" -le 8 ]; do
    local dow=$(date -d "@$day_epoch" +%u 2>/dev/null)
    if [ "$skip_weekend" != "1" ] || { [ "$dow" != "6" ] && [ "$dow" != "7" ]; }; then
      local w1s=$(hm_to_epoch "$day_epoch" "${WORK_WINDOWS[0]}")
      local w1e=$(hm_to_epoch "$day_epoch" "${WORK_WINDOWS[1]}")
      local w2s=$(hm_to_epoch "$day_epoch" "${WORK_WINDOWS[2]}")
      local w2e=$(hm_to_epoch "$day_epoch" "${WORK_WINDOWS[3]}")
      local ws we
      for ws_we in "$w1s $w1e" "$w2s $w2e"; do
        ws=${ws_we% *}; we=${ws_we#* }
        if [ "$reset_epoch" -ge "$ws" ] && [ "$reset_epoch" -le "$we" ]; then
          best=$reset_epoch; no_waste=1; best_start=$ws
        fi
        if [ "$we" -le "$reset_epoch" ] && [ "$we" -gt "$best" ]; then
          best=$we; best_start=$ws
        fi
      done
    fi
    day_epoch=$(( day_epoch + 86400 ))
    i=$(( i + 1 ))
  done
  printf '%s %s %s' "$best" "$no_waste" "$best_start"
}

# soma quantos segundos de expediente (WORK_WINDOWS) existem dentro do intervalo
# [start_epoch, end_epoch] — usado p/ medir "ritmo ideal" sem contar horário de almoço
# nem fora de expediente. skip_weekend=1 pula sáb/dom.
work_seconds_between() {
  local start_epoch="$1" end_epoch="$2" skip_weekend="$3"
  [ -z "$start_epoch" ] || [ -z "$end_epoch" ] && { printf '0'; return; }
  if [ "$end_epoch" -le "$start_epoch" ] 2>/dev/null; then printf '0'; return; fi
  local day_str=$(date -d "@$start_epoch" '+%Y-%m-%d' 2>/dev/null)
  local day_epoch=$(date -d "$day_str 00:00:00" +%s 2>/dev/null)
  local total=0 i=0
  while [ "$day_epoch" -le "$end_epoch" ] && [ "$i" -le 9 ]; do
    local dow=$(date -d "@$day_epoch" +%u 2>/dev/null)
    if [ "$skip_weekend" != "1" ] || { [ "$dow" != "6" ] && [ "$dow" != "7" ]; }; then
      local w1s=$(hm_to_epoch "$day_epoch" "${WORK_WINDOWS[0]}")
      local w1e=$(hm_to_epoch "$day_epoch" "${WORK_WINDOWS[1]}")
      local w2s=$(hm_to_epoch "$day_epoch" "${WORK_WINDOWS[2]}")
      local w2e=$(hm_to_epoch "$day_epoch" "${WORK_WINDOWS[3]}")
      local ws we ov_s ov_e
      for ws_we in "$w1s $w1e" "$w2s $w2e"; do
        ws=${ws_we% *}; we=${ws_we#* }
        ov_s=$ws; [ "$ov_s" -lt "$start_epoch" ] && ov_s=$start_epoch
        ov_e=$we;  [ "$ov_e" -gt "$end_epoch" ]   && ov_e=$end_epoch
        if [ "$ov_e" -gt "$ov_s" ]; then
          total=$(( total + (ov_e - ov_s) ))
        fi
      done
    fi
    day_epoch=$(( day_epoch + 86400 ))
    i=$(( i + 1 ))
  done
  printf '%s' "$total"
}

# cor bidirecional conforme o desvio entre ritmo real e ritmo ideal de consumo:
# vermelho -> alaranjado -> verde (ideal) -> alaranjado -> vermelho
# desvio positivo = gastando mais rápido que o ideal (risco de acabar a sessão antes do fim
# do expediente); desvio negativo = gastando mais devagar (risco de desperdiçar quota no
# reset) — os dois extremos usam a mesma cor (vermelho), só o ícone diferencia a direção
pace_color() {
  local absd=${1#-}
  absd=${absd%.*}
  if   [ "$absd" -le 12 ] 2>/dev/null; then printf '%s' "$GREEN"
  elif [ "$absd" -le 28 ] 2>/dev/null; then printf '%s' "$ORANGE"
  else                                       printf '%s' "$RED"
  fi
}

# ícone único que combina direção (⏫ rápido demais / ⏬ devagar demais / 🟢 no ritmo)
# com a intensidade do desvio (mesmos limiares de pace_color: 12/28). Os dois extremos usam
# a mesma cor (vermelho) — só a direção da seta muda; nunca mistura emoji com seta de texto.
pace_icon() {
  local dev="$1"
  [ -z "$dev" ] && { printf '⚪'; return; }
  if   [ "$dev" -gt 28 ]  2>/dev/null; then printf '🔴⏫'
  elif [ "$dev" -gt 12 ]  2>/dev/null; then printf '🟠⏫'
  elif [ "$dev" -ge -12 ] 2>/dev/null; then printf '🟢'
  elif [ "$dev" -ge -28 ] 2>/dev/null; then printf '🟠⏬'
  else                                       printf '🔴⏬'
  fi
}

# versão enxuta: "<ícone-de-ritmo> HH:MM (Nm)" — ícone comunica o desvio entre ritmo
# real e ideal (calculado em segundos de expediente efetivo, exclui almoço/fora de
# horário); casos especiais viram só um símbolo curto.
pace_seg() {
  local reset_epoch="$1" skip_weekend="$2" now="$3" sess_start="$4" actual_pct="$5"
  [ -z "$reset_epoch" ] && { printf ''; return; }
  local deadline no_waste best_start
  read -r deadline no_waste best_start <<< "$(calc_deadline "$reset_epoch" "$skip_weekend")"
  if [ "$deadline" -eq 0 ] 2>/dev/null; then
    printf '%b⚪%b' "$DIM" "$RESET"
    return
  fi
  local dl_h=$(date -d "@$deadline" '+%H:%M' 2>/dev/null)
  local ws_h=$(date -d "@$best_start" '+%H:%M' 2>/dev/null)
  local shift_lbl="$dl_h"
  [ -n "$ws_h" ] && shift_lbl="${ws_h}-${dl_h}"
  local left=$(( deadline - now ))

  # ritmo ideal = % do expediente (desde o início da sessão até o prazo útil) já
  # decorrido — usa segundos de expediente efetivo (exclui almoço/fora de horário),
  # não tempo de relógio corrido
  local dev="" color="$GRAY" legend="" work_left=""
  if [ -n "$sess_start" ] && [ "$deadline" -gt "$sess_start" ] 2>/dev/null; then
    local total_work=$(work_seconds_between "$sess_start" "$deadline" "$skip_weekend")
    local elapsed_work=$(work_seconds_between "$sess_start" "$now" "$skip_weekend")
    work_left=$(( total_work - elapsed_work ))
    [ "$work_left" -lt 0 ] 2>/dev/null && work_left=0
    if [ "$total_work" -gt 0 ] 2>/dev/null; then
      local ideal_pct=$(awk -v e="$elapsed_work" -v t="$total_work" 'BEGIN{p=(e*100)/t; if(p>100)p=100; if(p<0)p=0; printf "%.0f", p}')
      dev=$(awk -v a="${actual_pct:-0}" -v i="$ideal_pct" 'BEGIN{printf "%.0f", a-i}')
      color=$(pace_color "$dev")

      # régua visual: os 5 limiares de % real (ideal-28/-12/0/+12/+28, clampados
      # 0-100), cada um colorido com a cor fixa da própria faixa (vermelho/laranja/
      # verde/laranja/vermelho) — mesma escala do ícone, traduzida de "desvio" p/
      # "% de uso" nesta hora exata
      local thresholds=( $(( ideal_pct - 28 )) $(( ideal_pct - 12 )) "$ideal_pct" $(( ideal_pct + 12 )) $(( ideal_pct + 28 )) )
      local t_colors=( "$RED" "$ORANGE" "$GREEN" "$ORANGE" "$RED" )
      local idx t
      for idx in 0 1 2 3 4; do
        t=${thresholds[$idx]}
        [ "$t" -lt 0 ] 2>/dev/null && t=0
        [ "$t" -gt 100 ] 2>/dev/null && t=100
        legend="${legend} $(printf '%b%s%%%b' "${t_colors[$idx]}" "$t" "$RESET")"
      done
    fi
  fi
  local icon=$(pace_icon "$dev")

  local legend_lbl=""
  [ -n "$legend" ] && legend_lbl=" (${legend# })"

  if [ "$no_waste" -eq 1 ] 2>/dev/null; then
    local work_left_lbl=""
    [ -n "$work_left" ] && work_left_lbl=" ($(fmt_dur "$total_work")-$(fmt_dur "$work_left"))"
    printf '%b%s%s%b%s' "$color" "$icon" "$work_left_lbl" "$RESET" "$legend_lbl"
  elif [ "$left" -le 0 ]; then
    printf '%b🔴⏬ %s%b' "$RED" "$shift_lbl" "$RESET"
  else
    printf '%b%s %s (%s)%b%s' "$color" "$icon" "$shift_lbl" "$(fmt_dur "$left")" "$RESET" "$legend_lbl"
  fi
}

# 1: full/relative path (home shortened to ~)
if [ -n "$HOME" ] && [ "$cwd" = "$HOME" ]; then
  path_display="~"
elif [ -n "$HOME" ] && [[ "$cwd" == "$HOME"/* ]]; then
  path_display="~${cwd#$HOME}"
else
  path_display="$cwd"
fi
path_seg=$(printf '%b\xf0\x9f\x93\x81 %s%b' "$GRAY" "$path_display" "$RESET")

# 3: git branch + dirty indicator (skip optional locks for speed/safety)
git_seg=""
if git --no-optional-locks -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git --no-optional-locks -C "$cwd" branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    porcelain=$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null)
    staged=$(printf '%s\n' "$porcelain" | grep -c '^[MADRC]')
    pending=$(printf '%s\n' "$porcelain" | grep -c '^.[MD?]')
    pend_color="$DIM"; [ "$pending" -gt 0 ] && pend_color="$RED"
    stag_color="$DIM"; [ "$staged" -gt 0 ] && stag_color="$YELLOW"
    counts=" $(printf '%b~%s%b' "$pend_color" "$pending" "$RESET") $(printf '%b\xe2\x9c\x93%s%b' "$stag_color" "$staged" "$RESET")"
    git_seg=$(printf '%b\xf0\x9f\x8c\xbf %s%b%s' "$GREEN" "$branch" "$RESET" "$counts")
  fi
fi

# 4: active model name + reasoning effort level (from settings.json)
effort=""
if [ "$have_jq" -eq 1 ] && [ -f "$HOME/.claude/settings.json" ]; then
  effort=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi
if [ -n "$effort" ]; then
  case "$effort" in
    low)    effort_c="$GREEN" ;;
    medium) effort_c="$YELLOW" ;;
    high)   effort_c="$MAGENTA" ;;
    xhigh|max) effort_c="$RED" ;;
    *)      effort_c="$DIM" ;;
  esac
  model_seg=$(printf '%b\xf0\x9f\xa4\x96 %s%b %b(%s)%b' "$CYAN" "$model" "$RESET" "$effort_c" "$effort" "$RESET")
else
  model_seg=$(printf '%b\xf0\x9f\xa4\x96 %s%b' "$CYAN" "$model" "$RESET")
fi

# 5a: python virtualenv
venv_seg=""
if [ -n "$VIRTUAL_ENV" ]; then
  venv_name=$(basename "$VIRTUAL_ENV")
  venv_seg=$(printf '%b\xf0\x9f\x90\x8d %s%b' "$YELLOW" "$venv_name" "$RESET")
fi

# human-readable de tokens: 1234 -> 1.2k, 1200000 -> 1.2M
fmt_tok_h() {
  local n="${1:-0}"
  if [ "$n" -ge 1000000 ] 2>/dev/null; then awk -v t="$n" 'BEGIN{printf "%.1fM", t/1000000}'
  elif [ "$n" -ge 1000 ] 2>/dev/null; then awk -v t="$n" 'BEGIN{printf "%.1fk", t/1000}'
  else printf '%s' "$n"; fi
}

# 5c: total token consumption for the session (read from transcript) — sempre visível (0 se ainda não há dado)
total_tok=0
if [ "$have_jq" -eq 1 ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Consumo real absoluto da sessão: exclui cache_read (contexto em cache relido,
  # que não é consumo novo e inflava a contagem). Soma input + cache_creation + output.
  total_tok=$(jq -s '[.[].message.usage // empty
      | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
      + (.output_tokens // 0)] | add // 0' \
    "$transcript" 2>/dev/null)
  [ -z "$total_tok" ] && total_tok=0
fi
tok_seg=$(printf '%b\xf0\x9f\x8e\x9f\xef\xb8\x8f %s%b' "$YELLOW" "$(fmt_tok_h "$total_tok")" "$RESET")

# 5d: contexto → % até a compactação + nº de compactações da sessão — sempre visível
ctx_cur=0; compactions=0
if [ "$have_jq" -eq 1 ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  ctx_cur=$(jq -s '[.[].message.usage // empty] | last
      | ((.input_tokens//0)+(.cache_creation_input_tokens//0)+(.cache_read_input_tokens//0))' \
    "$transcript" 2>/dev/null)
  [ -z "$ctx_cur" ] && ctx_cur=0
  # nº de compactações já ocorridas na sessão (marcadores possíveis)
  compactions=$(jq -s '[.[] | select((.isCompactSummary==true)
      or (.subtype=="compact_boundary")
      or (.type=="summary"))] | length' "$transcript" 2>/dev/null)
  [ -z "$compactions" ] && compactions=0
fi
# janela: modelos atuais (Sonnet 5, Opus 4.6+, Fable 5) usam 1M por padrão; só Haiku fica em 200k
case "$model_id$model" in
  *[Hh]aiku*) ctx_max=200000;  ctx_lbl="200k" ;;
  *)          ctx_max=1000000; ctx_lbl="1M" ;;
esac
# % = ocupação real da janela; perto de 100% dispara a compactação
pct=$(awk -v c="$ctx_cur" -v m="$ctx_max" 'BEGIN{p=(c*100)/m; if(p>100)p=100; printf "%.0f", p}')
ctx_cur_h=$(fmt_tok_h "$ctx_cur")
[ "$ctx_cur" -lt 1000 ] 2>/dev/null && ctx_cur_h="$ctx_cur"
# 🧠 NN% (cur/janela) │ 🗜️ Nx — cor conforme % de ocupação
ctx_seg=$(printf '\xf0\x9f\xa7\xa0 %b%s%%%b %b(%s/%s)%b \xf0\x9f\x97\x9c\xef\xb8\x8f %sx' \
  "$(pct_color "$pct")" "$pct" "$RESET" "$DIM" "$ctx_cur_h" "$ctx_lbl" "$RESET" "$compactions")

# 5g: contagens de MCP / skills / plugins (instalado / usado-na-sessão)
mcp_count=0; mcp_used=0
skills_inst=0; skills_sess=0; plug_en=0; plug_avail=0
if [ "$have_jq" -eq 1 ] && [ -f "$HOME/.claude.json" ]; then
  # instalados globalmente
  mcp_count=$(jq -r '.mcpServers // {} | length' "$HOME/.claude.json" 2>/dev/null)
  plug_en=$(jq -r '[(.enabledPlugins // {} | keys[]?),
                    (.projects // {} | to_entries[] | .value.enabledPlugins // {} | keys[]?)]
                   | unique | length' "$HOME/.claude.json" 2>/dev/null)
fi
# usados nesta sessão (via tools mcp__<servidor>__<tool> no transcript)
if [ "$have_jq" -eq 1 ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  mcp_calls=$(jq -r 'select(.type=="assistant") | .message.content[]?
                     | select(.type=="tool_use") | .name
                     | select(startswith("mcp__"))' "$transcript" 2>/dev/null \
              | sed -E 's/^mcp__//; s/__.*//' | sed '/^$/d')
  [ -n "$mcp_calls" ] && mcp_used=$(printf '%s\n' "$mcp_calls" | sort -u | grep -c .)
fi
# skills instaladas (usuário): união de ~/.claude/skills e ~/.agents/skills
skills_inst=$({ ls -1 "$HOME/.claude/skills" 2>/dev/null; ls -1 "$HOME/.agents/skills" 2>/dev/null; } | sort -u | grep -c .)
# skills usadas nesta sessão (attributionSkill ∪ chamadas do tool Skill)
if [ "$have_jq" -eq 1 ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  skl_attr=$(jq -r 'select(.attributionSkill!=null) | .attributionSkill' "$transcript" 2>/dev/null | sed '/^$/d')
  skl_call=$(jq -r 'select(.type=="assistant") | .message.content[]?
                    | select(.type=="tool_use" and .name=="Skill") | .input.skill // empty' \
             "$transcript" 2>/dev/null | sed '/^$/d')
  skl_all=$(printf '%s\n%s\n' "$skl_attr" "$skl_call" | sed '/^$/d')
  [ -n "$skl_all" ] && skills_sess=$(printf '%s\n' "$skl_all" | sort -u | grep -c .)
fi
# plugins disponíveis nos marketplaces instalados
plug_avail=$(find "$HOME/.claude/plugins/marketplaces" -mindepth 3 -maxdepth 3 -type d \
              \( -path '*/plugins/*' -o -path '*/external_plugins/*' \) 2>/dev/null | grep -c .)

mcp_seg=$(printf '%b\xf0\x9f\x94\x8c mcp %s/%s%b' "$CYAN" "${mcp_count:-0}" "${mcp_used:-0}" "$RESET")
skills_seg=$(printf '%b\xf0\x9f\xa7\xa9 skills %s/%s%b' "$CYAN" "${skills_inst:-0}" "${skills_sess:-0}" "$RESET")
plug_seg=$(printf '%b\xf0\x9f\x94\xa9 plugins %s/%s%b' "$CYAN" "${plug_en:-0}" "${plug_avail:-0}" "$RESET")

# hooks configurados (~/.claude/settings.json) vs. disparos nesta sessão
# (proxy: nº de chamadas de ferramenta, já que a maioria dos hooks é Pre/PostToolUse)
hooks_cfg=0
if [ "$have_jq" -eq 1 ] && [ -f "$HOME/.claude/settings.json" ]; then
  hooks_cfg=$(jq '[.hooks[][]?.hooks[]?] | length' "$HOME/.claude/settings.json" 2>/dev/null)
  [ -z "$hooks_cfg" ] && hooks_cfg=0
fi
hooks_fired=0
if [ "$have_jq" -eq 1 ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  hooks_fired=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' \
    "$transcript" 2>/dev/null | grep -c .)
  [ -z "$hooks_fired" ] && hooks_fired=0
fi
hooks_seg=$(printf '%b\xf0\x9f\xaa\x9d hooks %s%b %b(%s)%b' "$CYAN" "${hooks_cfg:-0}" "$RESET" "$DIM" "${hooks_fired:-0}" "$RESET")

# 5h: uso do Claude (rate limits) com barra de progresso — sempre visível (0%/n/a antes da 1ª resposta da API)
now=$(date +%s 2>/dev/null)
p5=$(awk -v p="${rl_5h_pct:-0}" 'BEGIN{printf "%.0f", p}' 2>/dev/null); [ -z "$p5" ] && p5=0
p7=$(awk -v p="${rl_7d_pct:-0}" 'BEGIN{printf "%.0f", p}' 2>/dev/null); [ -z "$p7" ] && p7=0
u5_seg=$(printf '\xe2\x8f\xb1\xef\xb8\x8f 5h %s %b%s%%%b' "$(make_bar "$p5" 16)" "$(pct_color "$p5")" "$p5" "$RESET")
u7_seg=$(printf '\xf0\x9f\x93\x85 7d %s %b%s%%%b' "$(make_bar "$p7" 16)" "$(pct_color "$p7")" "$p7" "$RESET")

u5_reset='n/a'; u7_reset='n/a'
if [ -n "$rl_5h_reset" ] && [ -n "$now" ]; then
  r5_start_epoch=$(( ${rl_5h_reset%.*} - 5*3600 ))
  r5_start_h=$(date -d "@$r5_start_epoch" '+%H:%M' 2>/dev/null)
  r5_end_h=$(date -d "@${rl_5h_reset%.*}" '+%H:%M' 2>/dev/null)
  u5_reset=$(printf '%s %s-%s' "$(fmt_dur $(( ${rl_5h_reset%.*} - now )) )" "$r5_start_h" "$r5_end_h")
fi
if [ -n "$rl_7d_reset" ] && [ -n "$now" ]; then
  r7_start_epoch=$(( ${rl_7d_reset%.*} - 7*86400 ))
  r7_start_dh=$(date -d "@$r7_start_epoch" '+%d/%m %H:%M' 2>/dev/null)
  r7_end_dh=$(date -d "@${rl_7d_reset%.*}" '+%d/%m %H:%M' 2>/dev/null)
  u7_reset=$(printf '%s %s-%s' "$(fmt_dur $(( ${rl_7d_reset%.*} - now )) )" "$r7_start_dh" "$r7_end_dh")
fi
u5_reset=$(printf '(%b\xe2\x99\xbb\xef\xb8\x8f %s%b)' "$GREEN" "$u5_reset" "$RESET")
u7_reset=$(printf '(%b\xe2\x99\xbb\xef\xb8\x8f %s%b)' "$GREEN" "$u7_reset" "$RESET")

# aviso de "prazo útil" (expediente) antes do reset — 5h considera todos os dias,
# 7d pula sábado/domingo
pace5_seg=$(pace_seg "${rl_5h_reset%.*}" 0 "$now" "$r5_start_epoch" "$p5")
pace7_seg=$(pace_seg "${rl_7d_reset%.*}" 1 "$now" "$r7_start_epoch" "$p7")

# junta segmentos com um separador, pulando vazios
join_with() {
  local sep="$1"; shift
  local out="" x
  for x in "$@"; do
    [ -z "$x" ] && continue
    if [ -z "$out" ]; then out="$x"; else out="${out}${sep}${x}"; fi
  done
  printf '%s' "$out"
}

# separador entre segmentos de uma mesma linha
SEP='  '

# custo da sessão (informado pelo próprio Claude Code no input do statusline)
# cotação USD->BRL fixa (aproximada) — sem chamada de rede a cada render da statusline
USD_BRL_RATE=5.30
cost_usd_h=$(awk -v c="${cost_usd:-0}" 'BEGIN{printf "%.2f", c}')
cost_brl_h=$(awk -v c="${cost_usd:-0}" -v r="$USD_BRL_RATE" 'BEGIN{printf "%.2f", c*r}')
cost_seg=$(printf '%b\xf0\x9f\x92\xb0 $%s%b %b(R$%s)%b' "$GREEN" "$cost_usd_h" "$RESET" "$DIM" "$cost_brl_h" "$RESET")

# Linha 1 — contexto do trabalho: pasta + branch
line1=$(join_with "$SEP" "$path_seg" "$git_seg")
# Linha 2 — modelo/effort + contexto + tokens da sessão + venv + custo da sessão
line2=$(join_with "$SEP" "$model_seg" "$ctx_seg" "$tok_seg" "$venv_seg" "$cost_seg")
# Linha 3 — ferramentas (mcp, skills, hooks)
line3=$(join_with "$SEP" "$mcp_seg" "$skills_seg" "$hooks_seg")
# Linha 4 — limites de uso do Claude (barras) + tempo até reset
line4=$(join_with "$SEP" "$u5_seg" "$u5_reset" "$pace5_seg")
line5=$(join_with "$SEP" "$u7_seg" "$u7_reset" "$pace7_seg")

# uma linha por grupo, sem bordas/colunas — pula grupos totalmente vazios
out=$(join_with $'\n' "$line1" "$line2" "$line3" "$line4" "$line5")
printf '%s' "$out"
