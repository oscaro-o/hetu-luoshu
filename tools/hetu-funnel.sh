#!/usr/bin/env bash
#
# 河图洛书 · 漏斗报表
#
# 读 OpenLiteSpeed 访问日志里的埋点信标，算出通关漏斗和变现相关指标。
# 信标要执行 JavaScript 才会发出，所以爬虫基本不会进入统计。
#
# 用法：
#   hetu-funnel.sh                       全部日志
#   hetu-funnel.sh 2026-09-01            从这一天开始
#   hetu-funnel.sh 2026-09-01 2026-09-07 指定区间
#   hetu-funnel.sh --csv 2026-09-03      输出一行 CSV，给 cron 用
#   hetu-funnel.sh --csv yesterday       同上，自动取昨天
#
set -euo pipefail

DOMAIN="${HETU_DOMAIN:-hetu.trilumi.xyz}"
LOGDIR="${HETU_LOGDIR:-/home/$DOMAIN/logs}"

CSV=0
if [ "${1:-}" = "--csv" ]; then
  CSV=1
  shift
  DAY="${1:-yesterday}"
  [ "$DAY" = "yesterday" ] && DAY="$(date -d yesterday +%F)"
  [ "$DAY" = "today" ] && DAY="$(date +%F)"
  FROM="$DAY"; TO="$DAY"
else
  FROM="${1:-}"; TO="${2:-}"
fi

shopt -s nullglob
LOGS=("$LOGDIR/$DOMAIN.access_log"*)
if [ ${#LOGS[@]} -eq 0 ]; then
  echo "找不到日志：$LOGDIR/$DOMAIN.access_log*" >&2
  exit 1
fi

zcat -f "${LOGS[@]}" | awk -v FROM="$FROM" -v TO="$TO" -v CSV="$CSV" -v DAY="${DAY:-}" '
function qval(q, key,   m) {
  if (match(q, "[?&]" key "=[^&]*")) {
    m = substr(q, RSTART, RLENGTH)
    sub("^[?&]" key "=", "", m)
    gsub(/%3A/, ":", m); gsub(/%2F/, "/", m); gsub(/\+/, " ", m)
    return m
  }
  return ""
}
function pct(a, b) { return (b > 0) ? sprintf("%.0f%%", a * 100 / b) : "-" }
function med(arr, n,   i, mid) {
  if (n == 0) return -1
  mid = int(n / 2)
  return (n % 2) ? arr[mid + 1] : int((arr[mid] + arr[mid + 1]) / 2)
}
BEGIN {
  split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", mn, " ")
  for (i = 1; i <= 12; i++) M[mn[i]] = sprintf("%02d", i)
  split("sc_a1_intro sc_a1_wall sc_a1_cast sc_a1_fin sc_a2_main sc_a3_intro sc_a3_s1 sc_a3_s2 sc_a3_s3 sc_a3_s4 sc_a3_s5 sc_a3_end", FN, " ")
  LBL["sc_a1_intro"] = "第一场 · 开场"
  LBL["sc_a1_wall"]  = "第一场 · 刻墙"
  LBL["sc_a1_cast"]  = "第一场 · 投掷"
  LBL["sc_a1_fin"]   = "第一场 · 收束"
  LBL["sc_a2_main"]  = "第二场 · 凑够十"
  LBL["sc_a3_intro"] = "第三场 · 开场"
  LBL["sc_a3_s1"]    = "第三场 · 五行"
  LBL["sc_a3_s2"]    = "第三场 · 摆奇数"
  LBL["sc_a3_s3"]    = "第三场 · 摆偶数"
  LBL["sc_a3_s4"]    = "第三场 · 甲乙"
  LBL["sc_a3_s5"]    = "第三场 · 定盘"
  LBL["sc_a3_end"]   = "第三场 · 结算"
}
/\/_e\/p\.gif\?/ {
  if (!match($0, /\/_e\/p\.gif\?[^ "]*/)) next
  q = substr($0, RSTART, RLENGTH)
  sub(/^\/_e\/p\.gif/, "", q)
  ev = qval(q, "e"); sid = qval(q, "s")
  if (ev == "" || sid == "") next

  if (!match($0, /\[[0-9][0-9]\/[A-Za-z][a-z][a-z]\/[0-9]{4}:[0-9:]{8}/)) next
  ts = substr($0, RSTART + 1, RLENGTH - 1)
  split(ts, a, ":"); split(a[1], d, "/")
  date = d[3] "-" M[d[2]] "-" d[1]
  if (FROM != "" && date < FROM) next
  if (TO   != "" && date > TO)   next
  epoch = mktime(d[3] " " M[d[2]] " " d[1] " " a[2] " " a[3] " " a[4])

  if (dmin == "" || date < dmin) dmin = date
  if (date > dmax) dmax = date

  key = sid SUBSEP ev
  if (!(key in seen)) { seen[key] = 1; U[ev]++ }
  T[ev]++

  if (!(sid in sfirst) || epoch < sfirst[sid]) sfirst[sid] = epoch
  if (epoch > slast[sid]) slast[sid] = epoch

  # load 派生的统计一律按会话去重：重新加载页面会再发一次 load，同一个 sid 只算一次。
  # 语言也放在这里，保证它和会话数用同一个分母。
  if (ev == "load" && !(sid in loadseen)) {
    loadseen[sid] = 1
    r = qval(q, "r"); if (r == "") r = "unknown"
    REF[r]++
    if (qval(q, "n") == "1") NEWV++
    if (qval(q, "m") == "pwa") PWA++
    u = qval(q, "u"); if (u != "") UTM[u]++
    l = qval(q, "l"); if (l != "") LANGC[l]++
  }
  if (ev == "done") {
    DONE_AT[sid] = epoch
    sr = qval(q, "r"); if (sr != "") { SOLO_SUM += sr; SOLO_N++ }
  }
  if (ev == "giveup") GIVEUP++
}
END {
  sess = U["load"]; start = U["start"]; done = U["done"]
  if (CSV) {
    printf "%s,%d,%d,%d,%d,%d,%d,%.0f,%d\n", DAY, sess, start,
      U["sc_a1_fin"], U["sc_a2_main"], U["sc_a3_intro"], done,
      (SOLO_N ? SOLO_SUM / SOLO_N : 0), U["installed"]
    exit
  }
  if (sess == 0 && start == 0) {
    print "区间内没有埋点数据。"
    print "检查 1：页面是否已经部署新版本。检查 2：日志路径是否正确。"
    exit
  }

  n = 0
  for (s in DONE_AT) {
    dur = DONE_AT[s] - sfirst[s]
    if (dur >= 0 && dur < 86400) DUR[++n] = dur
  }
  for (i = 2; i <= n; i++) { v = DUR[i]; j = i - 1
    while (j > 0 && DUR[j] > v) { DUR[j+1] = DUR[j]; j-- }
    DUR[j+1] = v }
  mdur = med(DUR, n)

  printf "\n河图洛书 · 漏斗报表   %s → %s\n", dmin, dmax
  print  "==========================================================="
  print  "\n总览"
  print  "-----------------------------------------------------------"
  printf "  %6d   会话数（打开页面，已排除爬虫）\n", sess
  printf "  %6d   开始游戏 · 占会话 %s\n", start, pct(start, sess)
  printf "  %6d   通关 · 占会话 %s\n", done, pct(done, sess)
  printf "\n  完成率（通关 / 开始游戏）= %s\n", pct(done, start)
  if (SOLO_N > 0) printf "  平均自主完成率 = %.0f%%（%d 人）\n", SOLO_SUM / SOLO_N, SOLO_N
  if (mdur >= 0)  printf "  通关时长中位数 = %d 分 %02d 秒\n", int(mdur/60), mdur%60

  print  "\n分场景到达 · 去重会话 · 百分比是占会话数 · 流失是比上一步少的人"
  print  "-----------------------------------------------------------"
  prev = -1
  for (i = 1; i <= 12; i++) {
    e = FN[i]
    dl = (prev < 0) ? "--" : sprintf("%d", U[e] - prev)
    printf "  %6d   %5s   %6s   %s\n", U[e], pct(U[e], sess), dl, LBL[e]
    prev = U[e]
  }

  print  "\n变现相关 · 分母写在标签里"
  print  "-----------------------------------------------------------"
  printf "  %6d   %5s   新访客 / 会话\n", NEWV, pct(NEWV, sess)
  printf "  %6d   %5s   回访 / 会话\n", sess - NEWV, pct(sess - NEWV, sess)
  printf "  %6d   %5s   从已安装的应用启动 / 会话\n", PWA, pct(PWA, sess)
  printf "  %6d   %5s   浏览器给出安装资格 / 会话\n", U["install_prompt"], pct(U["install_prompt"], sess)
  printf "  %6d   %5s   点击安装按钮 / 有安装资格\n", U["install_click"], pct(U["install_click"], U["install_prompt"])
  printf "  %6d   %5s   完成安装 / 会话\n", U["installed"], pct(U["installed"], sess)
  printf "  %6d   %5s   通关后重玩 / 通关\n", U["restart"], pct(U["restart"], done)
  printf "  %6d   %5s   认输总次数 · 每个开始游戏的人平均\n", GIVEUP, (start ? sprintf("%.1f", GIVEUP / start) : "-")

  print  "\n语言 · 按会话"
  print  "-----------------------------------------------------------"
  for (k in LANGC) printf "  %6d   %5s   %s\n", LANGC[k], pct(LANGC[k], sess), k

  print  "\n来源 · 按会话"
  print  "-----------------------------------------------------------"
  for (k in REF) printf "  %6d   %5s   %s\n", REF[k], pct(REF[k], sess), k
  for (k in UTM) printf "  %6d   %5s   utm_source=%s\n", UTM[k], pct(UTM[k], sess), k
  print ""
}
'
