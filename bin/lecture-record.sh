#!/usr/bin/env bash
# 인프런 등 유료 강의의 시스템 오디오(BlackHole 2ch)를 캡처하는 녹음 스크립트.
# 개인 학습 노트 용도로만 사용 — 녹음/전사 결과물의 재배포·공유는 금지 (인프런 이용약관).
#
# 사용법: lecture-record.sh <출력.wav 경로>
# 보통 직접 실행하지 않고 lecture.zsh 의 lecture-start 함수가 백그라운드로 호출한다.
set -euo pipefail

WAV_PATH="${1:?사용법: lecture-record.sh <출력.wav 경로>}"
mkdir -p "$(dirname "$WAV_PATH")"

DEVICE_LIST="$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 || true)"
AUDIO_SECTION="$(printf '%s\n' "$DEVICE_LIST" | awk '/AVFoundation audio devices:/{flag=1} flag')"
IDX="$(printf '%s\n' "$AUDIO_SECTION" | grep "BlackHole 2ch" | grep -Eo '\[[0-9]+\]' | head -1 | tr -d '[]')"

if [[ -z "${IDX:-}" ]]; then
  echo "오류: BlackHole 2ch 오디오 장치를 찾을 수 없습니다." >&2
  echo "" >&2
  echo "현재 감지된 오디오 장치 목록:" >&2
  printf '%s\n' "$AUDIO_SECTION" >&2
  echo "" >&2
  echo "확인 사항:" >&2
  echo "  1) brew install --cask blackhole-2ch 로 설치되어 있는지" >&2
  echo "  2) 설치 후 재부팅했는지 (재부팅 전에는 장치 목록에 나타나지 않음)" >&2
  echo "  3) 마이크 권한: 시스템 설정 > 개인정보 보호 및 보안 > 마이크 에서 터미널 앱 허용 여부" >&2
  exit 1
fi

exec ffmpeg -hide_banner -loglevel warning -y \
  -f avfoundation -i ":${IDX}" \
  -ac 1 -ar 16000 -c:a pcm_s16le \
  "$WAV_PATH"
