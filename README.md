# 인프런 강의 자동 전사 파이프라인

> ⚠️ **개인 학습 노트 용도로만 사용하세요.** 인프런 이용약관상 강의 콘텐츠의 재배포·공유는
> 금지되어 있습니다. 이 파이프라인으로 만든 녹음 파일(`.wav`)과 전사 결과물(`.md`)은
> 본인이 결제한 강의를 복습하기 위한 개인 학습 노트로만 사용하고, 외부에 공유·배포하지 마세요.

시스템 오디오(스피커로 나가는 인프런 강의 소리)를 BlackHole 가상 오디오 장치로 캡처해서,
로컬 Whisper 모델(Metal GPU 가속)로 한국어 전사 텍스트를 생성합니다. 전사 결과는 문단별
타임스탬프(`## MM:SS`)가 붙은 **단일 마크다운(.md) 노트**로 저장되어 Obsidian에서 바로
읽히고, 그대로 LLM에 붙여넣어 요약을 요청하기도 좋습니다. 요약 자체는 이 파이프라인의
범위 밖이며 이후 직접 또는 별도 LLM 호출로 처리하면 됩니다.

---

## 디렉터리 구조

```
~/lecture-transcribe/
├── README.md
├── bin/
│   ├── lecture-record.sh       # BlackHole 캡처 → WAV (내부용, 직접 실행 X)
│   ├── lecture-transcribe.sh   # WAV → md (내부용, 직접 실행 X)
│   └── lecture.zsh             # lecture-start / lecture-stop / lecture-status 함수
├── whisper.cpp/                 # 클론 + Metal 빌드 결과물 + 모델
└── transcripts/                 # Obsidian vault로 열어서 쓰기 좋음
    └── {강의명}/
        ├── {강의명}_{YYYYMMDD}_{HHMM}.wav   # 원본 녹음 (16kHz mono PCM)
        └── {강의명}_{YYYYMMDD}_{HHMM}.md    # 전사 노트 (문단별 타임스탬프 포함)
```

whisper.cpp의 SRT 출력은 타임스탬프를 뽑아내는 **중간 산출물로만** 쓰이고, `.md`로 변환된
뒤 **자동으로 삭제**됩니다 — 최종적으로는 `.wav`와 `.md`만 남습니다.

---

## 최초 설치 (한 번만)

### 1. 의존성 설치

```bash
brew install ffmpeg cmake
brew install --cask blackhole-2ch
```

`blackhole-2ch`는 설치 스크립트가 `sudo`로 pkg를 설치하므로 **Warp(또는 터미널)에서 직접**
실행해서 암호를 입력해야 합니다. 설치 후 **반드시 재부팅**하세요 — 재부팅 전에는 BlackHole이
오디오 장치 목록에 나타나지 않습니다.

### 2. 오디오 MIDI 설정 — 다중 출력 기기(Multi-Output Device) 생성

터미널로 자동화할 수 없는 GUI 설정입니다. 재부팅 후 한 번만 만들어두면 계속 재사용합니다.

1. **Spotlight**(⌘+Space) → "오디오 MIDI 설정" 실행
2. 왼쪽 하단 **`+`** → **"다중 출력 기기 생성"**
3. 오른쪽 목록에서 지금 실제로 소리를 듣는 **물리 출력 장치**(예: `DELL U2719D`, `USB Audio`,
   `MacBook Air 스피커` 등 상황에 맞는 것)와 **`BlackHole 2ch`**를 함께 체크
4. **기본 기기(마스터)**를 방금 체크한 물리 출력 장치로 지정
5. **`BlackHole 2ch` 행에만** "드리프트 보정" 체크 (물리 출력 장치 행에는 체크하지 않음)
6. 생성된 기기를 우클릭 → 이름을 `Lecture Output`처럼 장소에 안 묶인 이름으로 변경(추천)
7. **시스템 설정 → 사운드 → 출력**에서 이 다중 출력 기기를 선택

**노트북을 카페 ↔ 집 등 다른 곳에서 쓸 때**: 다중 출력 기기를 새로 만들 필요 없이, 기존
"다중 출력 기기" 설정 화면에서 **체크박스만 바꿔주면** 됩니다 — 예를 들어 카페에서는 이어폰/
스피커 장치(`USB Audio` 등)를 체크, 집에 가서 모니터를 연결하면 그 장치 체크 해제하고
`DELL U2719D`를 체크 + 기본 기기(마스터)도 그에 맞게 변경. `BlackHole 2ch`는 항상 체크된
채로 둡니다.

**알아두면 좋은 점 3가지**
- 다중 출력 기기 사용 중에는 **키보드 볼륨 키가 안 먹습니다** — 볼륨은 재생 중인 앱(브라우저 등)
  내부 슬라이더로 조절하세요. 강의 들을 때만 이 출력으로 바꾸고 평소엔 원래 출력으로 되돌리는
  걸 추천합니다.
- `BlackHole 2ch`만 단독으로 출력 장치로 잡으면 **소리가 전혀 안 들립니다.** 반드시 물리
  장치와 함께 "다중 출력"으로 써야 합니다.
- 시스템 알림음, 타이핑 소리 등 **다른 앱 소리도 같이 녹음**됩니다. 강의 들을 때는 다른 알림을
  꺼두는 게 좋습니다.

### 3. 마이크 권한 확인

macOS는 BlackHole 캡처도 "마이크 입력"으로 취급합니다. 첫 녹음 시 권한 팝업이 뜨면 **허용**을
눌러주세요. 팝업이 안 뜨거나 이미 거부했다면: **시스템 설정 → 개인정보 보호 및 보안 → 마이크**에서
사용 중인 터미널 앱(Warp 등)을 허용으로 켜주세요. 권한이 없으면 ffmpeg가 **아주 짧거나
무음인 WAV**를 만듭니다.

### 4. whisper.cpp 빌드 + 모델

이미 이 저장소에 클론·빌드되어 있습니다(`~/lecture-transcribe/whisper.cpp`). 처음부터 다시
하려면:

```bash
git clone https://github.com/ggml-org/whisper.cpp.git ~/lecture-transcribe/whisper.cpp
cd ~/lecture-transcribe/whisper.cpp
cmake -B build -DGGML_METAL=ON
cmake --build build --config Release -j$(sysctl -n hw.logicalcpu)
sh ./models/download-ggml-model.sh large-v3-turbo-q5_0    # 574MB 다운로드
```

**모델 선택 근거**: `large-v3-turbo`는 `large-v3`를 디코더 4층으로 증류한 모델로, `medium`
(디코더 24층, 1.53GB)보다 **빠르면서 한국어 인식률도 더 좋습니다**. `q5_0` 양자화로 574MB.
정확도를 더 올리고 싶으면 비양자화 버전(`large-v3-turbo.bin`, 1.62GB)으로 바꿀 수 있습니다:

```bash
sh ./models/download-ggml-model.sh large-v3-turbo
WHISPER_MODEL=~/lecture-transcribe/whisper.cpp/models/ggml-large-v3-turbo.bin lecture-stop
```

(모델 경로는 `WHISPER_MODEL` 환경변수로, whisper.cpp 위치는 `WHISPER_DIR`로 오버라이드 가능)

### 5. 셸 함수 등록

`~/.zshrc` 맨 끝에 아래 두 줄이 이미 추가되어 있습니다:

```zsh
# 인프런 강의 전사 파이프라인 (개인 학습 노트 용도)
source "$HOME/lecture-transcribe/bin/lecture.zsh"
```

새 터미널을 열면 자동으로 `lecture-start` / `lecture-stop` / `lecture-status` 명령을 쓸 수
있습니다.

---

## 사용법

```bash
lecture-start "스프링부트-3강"     # 녹음 시작 (백그라운드, 프롬프트 즉시 복귀)
# ... 강의 수강 ...
lecture-status                      # (선택) 현재 녹음 중인지, 몇 분 지났는지 확인
lecture-stop                        # 녹음 종료 → 자동으로 한국어 전사 실행
```

`lecture-stop` 실행이 끝나면 아래 경로에 결과물이 생깁니다:

```
~/lecture-transcribe/transcripts/스프링부트-3강/스프링부트-3강_20260813_1430.wav
~/lecture-transcribe/transcripts/스프링부트-3강/스프링부트-3강_20260813_1430.md
```

`.md`는 아래처럼 문단별 타임스탬프(재생 기준 `MM:SS`)가 붙은 형태입니다:

```markdown
# 스프링부트-3강

## 00:00
그래서 여러분들이 생각하실 때는 그냥 간단하게 이렇게...

## 00:07
자 그러면 어떤 걸 서비스 장애라고 이야기하는지...
```

이 파일을 **그대로 LLM에 붙여넣어** 요약을 요청하면 됩니다.

**동시에 하나의 녹음만** 가능합니다. 이미 녹음 중일 때 `lecture-start`를 또 실행하면 안내
메시지와 함께 실패합니다 — 먼저 `lecture-stop`으로 끝내세요.

---

## 트러블슈팅

**"BlackHole 2ch 장치를 찾을 수 없습니다"**
`lecture-start`가 전체 오디오 장치 목록을 출력해줍니다. 확인 순서:
1. `brew install --cask blackhole-2ch` 설치됐는지 (`brew list --cask blackhole-2ch`)
2. 설치 후 **재부팅**했는지
3. 마이크 권한 (시스템 설정 → 개인정보 보호 및 보안 → 마이크)

**녹음은 됐는데 파일이 거의 비어있음 / 전사 결과가 없음**
아래로 실제 음량을 확인하세요. `mean_volume`이 **`-90dB` 근처(디지털 무음)**면 오디오 라우팅
문제입니다 — 다중 출력 기기에 `BlackHole 2ch`가 체크돼 있는지, 시스템 출력이 그 다중 출력
기기로 설정돼 있는지 확인하세요.
```bash
ffmpeg -i "녹음파일.wav" -af volumedetect -f null - 2>&1 | grep mean_volume
```

**전사 결과가 같은 문장을 계속 반복함 (환각)**
Whisper 계열 모델의 흔한 실패 패턴으로, 보통 **무음/배경음악/불명확한 발화 구간**에서
나타납니다. 녹음 자체(음량)는 정상인데 이 현상이 나오면 해당 구간의 실제 오디오 내용을
의심해보세요.

**전사가 너무 느림**
`bin/lecture-transcribe.sh`의 `-t 4`는 Apple M2의 P-core 4개 기준입니다. 다른 칩이면
`sysctl -n hw.perflevel0.logicalcpu`로 P-core 개수를 확인해 값을 조정하세요. 인코딩 자체는
Metal(GPU)이 처리하므로 스레드 수를 과하게 늘려도 별 효과가 없습니다.

**`.md`의 타임스탬프가 실제 강의 진행 시간과 안 맞음**
배속 재생(1.25x, 1.5x 등)으로 들었다면 타임스탬프는 **"재생된(빠른) 오디오" 기준**입니다.
원본 강의 시간으로 환산하려면 타임스탬프에 배속을 곱하세요.

**Obsidian에서 `.wav`만 보이고 `.md`가 안 보임**
`.md`는 Obsidian이 기본으로 지원하므로 정상적으로 보여야 합니다. 안 보인다면 vault 캐시
문제일 수 있으니 Obsidian을 재시작하거나 사이드바를 새로고침해보세요.

**강의 다 듣고 나서**
시스템 설정 → 사운드 → 출력을 **원래 장치로 되돌리세요**(내장 스피커, DELL 모니터 등). 다중
출력 기기를 계속 켜두면 볼륨 키가 안 먹는 등 불편할 수 있습니다.

---

## 환경변수 오버라이드

| 변수 | 기본값 | 설명 |
|---|---|---|
| `WHISPER_DIR` | `~/lecture-transcribe/whisper.cpp` | whisper.cpp 클론/빌드 위치 |
| `WHISPER_MODEL` | `$WHISPER_DIR/models/ggml-large-v3-turbo-q5_0.bin` | 사용할 모델 파일 경로 |

```bash
WHISPER_MODEL=~/lecture-transcribe/whisper.cpp/models/ggml-large-v3-turbo.bin lecture-stop
```
