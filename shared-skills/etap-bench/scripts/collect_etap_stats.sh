#!/bin/bash
# collect_etap_stats.sh — Etap 서버에서 성능 통계를 수집한다.
# Usage: ./collect_etap_stats.sh <label> [interval_sec] [count]
#   label:        출력 파일 접두어 (예: baseline_pre, tcpip_post)
#   interval_sec: 반복 수집 간격 (기본: 0 = 1회만)
#   count:        반복 횟수 (기본: 1)
#
# 예시:
#   ./collect_etap_stats.sh baseline_pre              # 1회 스냅샷
#   ./collect_etap_stats.sh baseline_during 5 12      # 5초 간격 12회 (60초)

ETAP_HOST="solution@61.79.198.110"
ETAP_PORT=12222
LABEL=${1:?"Usage: $0 <label> [interval_sec] [count]"}
INTERVAL=${2:-0}
COUNT=${3:-1}
OUTDIR="./results/$(date +%Y-%m-%d)"

mkdir -p "$OUTDIR"

collect_once() {
    local suffix=$1
    local outfile="${OUTDIR}/${LABEL}_${suffix}.txt"

    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" > "$outfile"

    echo "--- port_info ---" >> "$outfile"
    ssh -p $ETAP_PORT $ETAP_HOST "sudo /usr/local/bin/etapcomm etap.port_info" >> "$outfile" 2>&1

    # 2026-04-29 정정: etap.total_traffic / etap.total_session 명령은 v2.x etap에 미존재
    # (Unknown function). /proc/PID/status 로 시스템 RSS 수집으로 대체.
    echo "--- proc_status (RSS) ---" >> "$outfile"
    ssh -p $ETAP_PORT $ETAP_HOST "cat /proc/\$(pgrep -x etap)/status 2>/dev/null | grep -E 'VmRSS|VmSize|Threads'" >> "$outfile" 2>&1

    echo "--- visible_tls_stats ---" >> "$outfile"
    ssh -p $ETAP_PORT $ETAP_HOST "sudo /usr/local/bin/etapcomm visible_tls.show_stats" >> "$outfile" 2>/dev/null

    # 모듈별 통계 (존재하면 수집)
    echo "--- apf_stats ---" >> "$outfile"
    ssh -p $ETAP_PORT $ETAP_HOST "etapcomm ai_prompt_filter.show_stats" >> "$outfile" 2>/dev/null

    echo "Collected: $outfile"
}

if [ "$INTERVAL" -eq 0 ]; then
    collect_once "snapshot"
else
    for i in $(seq 1 $COUNT); do
        collect_once "$(printf '%03d' $i)"
        [ "$i" -lt "$COUNT" ] && sleep "$INTERVAL"
    done
fi
