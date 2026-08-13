# 시스템 오디오 녹음 → 한국어 전사 파이프라인 — note-start / note-stop / note-status
# 개인 학습·기록 용도로만 사용. 녹음 대상 콘텐츠(강의, 영상 등)의 이용약관을 따를 것.

_NOTES_DIR="$HOME/sound-notes"
_NOTES_PID_FILE="$HOME/.sound-notes.pid"

note-start() {
  # 대화형 zsh(job control 켜짐)에서는 `&`로 백그라운드 보낸 작업이 별도
  # 프로세스 그룹으로 분리되는데, 이 상태의 ffmpeg가 avfoundation으로
  # BlackHole을 열 때 조용히 멈춰버리는 경우가 있었다(2026-08-13 실제 발생 -
  # 같은 스크립트가 job control 없는 비대화형 셸에서는 매번 정상 동작했음).
  # 이 함수 안에서만 job control을 꺼서 그 문제를 피한다.
  setopt LOCAL_OPTIONS NO_MONITOR

  local name="$1"
  if [[ -z "$name" ]]; then
    echo "사용법: note-start <제목>"
    return 1
  fi
  if [[ -f "$_NOTES_PID_FILE" ]]; then
    echo "이미 녹음 중입니다: $(cut -d'|' -f3 "$_NOTES_PID_FILE")"
    echo "먼저 note-stop 을 실행하세요."
    return 1
  fi

  if ! ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -q "BlackHole 2ch"; then
    echo "오류: BlackHole 2ch 장치를 찾을 수 없습니다. 아래 오디오 장치 목록을 확인하세요:"
    ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | awk '/AVFoundation audio devices:/{flag=1} flag'
    echo ""
    echo "확인 사항: 1) blackhole-2ch 설치 여부  2) 설치 후 재부팅 여부  3) 마이크 권한(시스템 설정 > 개인정보 보호 및 보안 > 마이크)"
    return 1
  fi

  local safe_name="${name// /_}"
  safe_name="${safe_name//\//_}"
  local ts
  ts="$(date +%Y%m%d_%H%M)"
  local out_dir="$_NOTES_DIR/transcripts/${safe_name}"
  mkdir -p "$out_dir"
  local wav_path="${out_dir}/${safe_name}_${ts}.wav"
  local log_path="${out_dir}/.record_${ts}.log"

  nohup "$_NOTES_DIR/bin/record.sh" "$wav_path" > "$log_path" 2>&1 &
  local pid=$!
  disown

  # ffmpeg가 avfoundation 장치를 여는 데 약간 시간이 걸림 — 조기 실패를 바로 감지.
  # 프로세스가 살아있는 것만으로는 부족하다 — 마이크 권한(TCC)이 이 실행에 대해
  # 조용히 거부되면 ffmpeg가 죽지도 않고 파일도 안 만든 채 그대로 멈춰버릴 수 있다
  # (2026-08-13 실제 발생 - 16분 넘게 "녹음 중"으로 표시됐지만 WAV가 아예 생성 안 됨).
  # 그래서 WAV 파일이 실제로 생겼는지까지 확인한다.
  sleep 2
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "오류: 녹음 시작에 실패했습니다. 로그 확인: $log_path"
    cat "$log_path"
    return 1
  fi
  if [[ ! -f "$wav_path" ]]; then
    kill -9 "$pid" 2>/dev/null
    echo "오류: ffmpeg는 떠 있지만 녹음 파일이 만들어지지 않았습니다 — 오디오 장치를"
    echo "열지 못하고 멈춰있는 상태로 보입니다. 로그(보통 비어있음): $log_path"
    cat "$log_path"
    echo "확인할 것: 1) 마이크 권한(시스템 설정 → 개인정보 보호 및 보안 → 마이크)"
    echo "          2) 한 번 더 note-start 재시도 (드물게 일시적일 수 있음)"
    return 1
  fi

  echo "$pid|$wav_path|$safe_name|$(date +%s)" > "$_NOTES_PID_FILE"
  echo "🎙  녹음 시작: $safe_name"
  echo "    저장 위치: $wav_path"
  echo "    중지: note-stop"
}

note-stop() {
  if [[ ! -f "$_NOTES_PID_FILE" ]]; then
    echo "현재 진행 중인 녹음이 없습니다."
    return 1
  fi

  local line pid wav_path name
  line="$(cat "$_NOTES_PID_FILE")"
  pid="$(cut -d'|' -f1 <<< "$line")"
  wav_path="$(cut -d'|' -f2 <<< "$line")"
  name="$(cut -d'|' -f3 <<< "$line")"

  if kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid"
    local waited=0
    while kill -0 "$pid" 2>/dev/null && (( waited < 15 )); do
      sleep 1
      waited=$((waited + 1))
    done
  fi

  rm -f "$_NOTES_PID_FILE"

  if [[ ! -s "$wav_path" ]]; then
    echo "오류: 녹음 파일이 비어있거나 없습니다: $wav_path"
    return 1
  fi

  echo "⏹  녹음 종료: $name"
  echo "    전사를 시작합니다 (모델 로딩 포함 다소 시간이 걸릴 수 있습니다)..."
  "$_NOTES_DIR/bin/transcribe.sh" "$wav_path"
}

note-status() {
  if [[ ! -f "$_NOTES_PID_FILE" ]]; then
    echo "현재 녹음 중인 항목이 없습니다."
    return 0
  fi
  local line pid wav_path name start_ts now elapsed
  line="$(cat "$_NOTES_PID_FILE")"
  pid="$(cut -d'|' -f1 <<< "$line")"
  wav_path="$(cut -d'|' -f2 <<< "$line")"
  name="$(cut -d'|' -f3 <<< "$line")"
  start_ts="$(cut -d'|' -f4 <<< "$line")"
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "PID 파일은 있지만 프로세스가 죽어있습니다. note-stop 으로 정리해주세요."
    return 1
  fi
  now=$(date +%s)
  elapsed=$(( now - start_ts ))

  # 프로세스 생존만으로는 실제로 녹음되고 있는지 알 수 없다 - 마이크 권한이
  # 조용히 막히면 ffmpeg가 죽지 않은 채 파일만 안 늘어나는 상태가 될 수 있다.
  if [[ ! -f "$wav_path" ]]; then
    printf "⚠️  프로세스는 살아있지만 녹음 파일이 아직 없습니다(%d초 경과) — 멈춰있을 수\n" "$elapsed"
    echo "    있습니다. 마이크 권한(시스템 설정 → 개인정보 보호 및 보안 → 마이크)을 확인하세요."
    return 1
  fi
  local mtime staleness
  mtime="$(stat -f %m "$wav_path" 2>/dev/null)"
  if [[ -n "$mtime" ]]; then
    staleness=$(( now - mtime ))
    if (( staleness > 15 )); then
      printf "⚠️  프로세스는 살아있지만 파일이 %d초째 갱신되지 않고 있습니다 — 녹음이 멈춘\n" "$staleness"
      echo "    것으로 보입니다. 마이크 권한을 확인하고 note-stop 후 다시 시작해보세요."
      return 1
    fi
  fi

  printf "🔴 녹음 중: %s (%d분 %d초 경과)\n" "$name" $((elapsed / 60)) $((elapsed % 60))
}
