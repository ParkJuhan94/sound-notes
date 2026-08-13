# 시스템 오디오 녹음 → 한국어 전사 파이프라인 — note-start / note-stop / note-status
# 개인 학습·기록 용도로만 사용. 녹음 대상 콘텐츠(강의, 영상 등)의 이용약관을 따를 것.

_NOTES_DIR="$HOME/sound-notes"
_NOTES_PID_FILE="$HOME/.sound-notes.pid"

note-start() {
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

  # ffmpeg가 avfoundation 장치를 여는 데 약간 시간이 걸림 — 조기 실패를 바로 감지
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "오류: 녹음 시작에 실패했습니다. 로그 확인: $log_path"
    cat "$log_path"
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
  local line pid name start_ts now elapsed
  line="$(cat "$_NOTES_PID_FILE")"
  pid="$(cut -d'|' -f1 <<< "$line")"
  name="$(cut -d'|' -f3 <<< "$line")"
  start_ts="$(cut -d'|' -f4 <<< "$line")"
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "PID 파일은 있지만 프로세스가 죽어있습니다. note-stop 으로 정리해주세요."
    return 1
  fi
  now=$(date +%s)
  elapsed=$(( now - start_ts ))
  printf "🔴 녹음 중: %s (%d분 %d초 경과)\n" "$name" $((elapsed / 60)) $((elapsed % 60))
}
