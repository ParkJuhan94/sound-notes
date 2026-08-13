#!/usr/bin/env bash
# whisper.cpp(Metal 가속)로 녹음된 WAV를 한국어로 전사해 마크다운 노트 두 개를 만든다:
# {제목}.md(문단별 "## MM:SS" 타임스탬프 포함, 특정 구간 다시 찾을 때)와
# {제목}_plain.md(타임스탬프 없는 순수 텍스트, LLM에 그대로 붙여넣기용). whisper.cpp의
# SRT 출력은 중간 산출물로만 쓰고 파싱한 뒤 삭제한다.
# 개인 학습·기록 용도로만 사용 — 전사 결과물의 재배포·공유는 금지.
#
# 사용법: transcribe.sh <입력.wav 경로>
# 모델/바이너리 경로는 WHISPER_DIR, WHISPER_MODEL 환경변수로 오버라이드 가능.
set -euo pipefail

NOTES_DIR="$HOME/sound-notes"
WHISPER_DIR="${WHISPER_DIR:-$NOTES_DIR/whisper.cpp}"
WHISPER_CLI="$WHISPER_DIR/build/bin/whisper-cli"
WHISPER_MODEL="${WHISPER_MODEL:-$WHISPER_DIR/models/ggml-large-v3-turbo-q5_0.bin}"

WAV_PATH="${1:?사용법: transcribe.sh <입력.wav 경로>}"

if [[ ! -f "$WAV_PATH" ]]; then
  echo "오류: WAV 파일을 찾을 수 없습니다: $WAV_PATH" >&2
  exit 1
fi
if [[ ! -x "$WHISPER_CLI" ]]; then
  echo "오류: whisper-cli 바이너리가 없습니다: $WHISPER_CLI (whisper.cpp 빌드 필요)" >&2
  exit 1
fi
if [[ ! -f "$WHISPER_MODEL" ]]; then
  echo "오류: 모델 파일이 없습니다: $WHISPER_MODEL" >&2
  exit 1
fi

OUT_PREFIX="${WAV_PATH%.wav}"
SRT_PATH="${OUT_PREFIX}.srt"
MD_PATH="${OUT_PREFIX}.md"
PLAIN_PATH="${OUT_PREFIX}_plain.md"
NOTE_TITLE="$(basename "$(dirname "$WAV_PATH")")"

echo "전사 시작: $(basename "$WAV_PATH")"
START_TS=$(date +%s)

"$WHISPER_CLI" \
  -m "$WHISPER_MODEL" \
  -f "$WAV_PATH" \
  -l ko \
  -osrt \
  -of "$OUT_PREFIX" \
  -t 4 -pp

echo "# ${NOTE_TITLE}" > "$MD_PATH"
echo "" >> "$MD_PATH"
echo "# ${NOTE_TITLE}" > "$PLAIN_PATH"
echo "" >> "$PLAIN_PATH"

awk -v md="$MD_PATH" -v plain="$PLAIN_PATH" '
  BEGIN { RS=""; FS="\n" }
  {
    split($2, t, " --> ")
    split(t[1], hms, "[:,]")
    total_sec = hms[1] * 3600 + hms[2] * 60 + hms[3]
    mm = int(total_sec / 60)
    ss = total_sec % 60
    text = ""
    for (i = 3; i <= NF; i++) {
      line = $i
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      text = (text == "") ? line : text " " line
    }
    printf("## %02d:%02d\n", mm, ss) >> md
    print text >> md
    print "" >> md
    print text >> plain
    print "" >> plain
  }
' "$SRT_PATH"

rm -f "$SRT_PATH"

END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))

echo ""
echo "전사 완료 (${ELAPSED}초 소요)"
echo "  노트(타임스탬프 포함): ${MD_PATH}"
echo "  노트(타임스탬프 없음): ${PLAIN_PATH}"
