# sound-notes — 시스템 오디오 → 한국어 전사 노트

**macOS 전용** (BlackHole·Audio MIDI 설정·avfoundation 등 macOS 전용 기술에 의존 — Windows/Linux에서는 동작하지 않습니다)

> ⚠️ **개인 학습·기록 용도로만 사용하세요.** 녹음 대상 콘텐츠(유료 강의, 영상, 방송 등)에는
> 대부분 재배포·공유를 금지하는 이용약관이 걸려 있습니다. 이 파이프라인으로 만든 녹음 파일
> (`.wav`)과 전사 결과물(`.md`)은 **본인이 시청할 권한이 있는 콘텐츠**를 복습하기 위한 개인
> 노트로만 사용하고, 외부에 공유·배포하지 마세요.

시스템 오디오(스피커로 나가는 소리)를 BlackHole 가상 오디오 장치로 캡처해서, 로컬 Whisper
모델(Metal GPU 가속)로 한국어 전사 텍스트를 생성합니다. **인프런 강의뿐 아니라 유튜브,
화상회의 녹화, 팟캐스트 등 macOS 스피커로 재생되는 모든 오디오/영상**에 범용으로 쓸 수
있습니다. 전사 결과는 **마크다운(.md) 노트 두 개**로 저장됩니다 — 문단별 타임스탬프
(`## MM:SS`)가 붙은 버전과, 타임스탬프 없이 순수 텍스트만 있는 `_plain` 버전. 둘 다
Obsidian에서 바로 읽히고, `_plain` 쪽은 그대로 LLM에 붙여넣어 요약을 요청하기도 좋습니다.
요약 자체는 이 파이프라인의 범위 밖이며 이후 직접 또는 별도 LLM 호출로 처리하면 됩니다.

---

## ⚠️ 주의사항 (먼저 읽어주세요)

이 두 가지는 아래 설치/사용법 곳곳에서 다시 언급하지 않으니 여기서만 확인하세요.

- **배속 재생 시 `.md` 타임스탬프는 "재생된(빠른) 오디오" 기준입니다.** 1.25x, 1.5x 등으로
  들으면서 녹음하면, 예를 들어 `## 10:00`은 원본 영상의 10분 지점이 아니라 **배속으로 재생된
  오디오의 10분 지점**입니다. 원본 시간으로 되돌리려면 타임스탬프에 배속을 곱하세요
  (1.5배속이면 `10:00 × 1.5 = 15:00`).
- **듣지 않고 무음으로 녹음할 수 있습니다.** 오디오 MIDI 설정(아래 "2. 오디오 MIDI 설정"에서
  만드는 다중 출력 기기)에서 **물리 출력 장치(스피커) 행의 음량 슬라이더만 0으로** 내리세요
  — `BlackHole 2ch` 행은 완전히 독립된 슬라이더라 영향을 받지 않고 그대로 녹음되며, **전사
  정확도에도 영향이 없습니다**(장치별로 완전히 분리된 스트림이라 물리 장치 쪽 감쇠가 BlackHole
  쪽에 전달되지 않기 때문). 단, **브라우저 탭 음소거나 영상 플레이어 자체의 볼륨/음소거
  버튼은 쓰면 안 됩니다** — 소리가 OS로 나가기 *전에* 원본 신호 자체를 줄이는 것이라 BlackHole로
  가는 녹음도 같이 무음이 됩니다. (반대로 `BlackHole 2ch` 슬라이더 자체를 내리면 실제 녹음
  신호가 작아져 정확도에 영향을 줄 수 있으니 그 슬라이더는 건드리지 마세요.)

---

## 디렉터리 구조

```
~/sound-notes/
├── README.md
├── bin/
│   ├── record.sh       # BlackHole 캡처 → WAV (내부용, 직접 실행 X)
│   ├── transcribe.sh   # WAV → md 2개 (내부용, 직접 실행 X)
│   └── notes.zsh       # note-start / note-stop / note-status 함수
├── whisper.cpp/          # 클론 + Metal 빌드 결과물 + 모델 (git 저장소엔 미포함, 아래 4번 참고)
└── transcripts/          # Obsidian vault로 열어서 쓰기 좋음
    └── {제목}/
        ├── {제목}_{YYYYMMDD}_{HHMM}.wav         # 원본 녹음 (16kHz mono PCM)
        ├── {제목}_{YYYYMMDD}_{HHMM}.md          # 전사 노트 (문단별 타임스탬프 포함)
        └── {제목}_{YYYYMMDD}_{HHMM}_plain.md    # 전사 노트 (타임스탬프 없음, LLM 붙여넣기용)
```

whisper.cpp의 SRT 출력은 타임스탬프를 뽑아내는 **중간 산출물로만** 쓰이고, `.md` 두 개로
변환된 뒤 **자동으로 삭제**됩니다 — 최종적으로는 `.wav`와 `.md` 파일 두 개만 남습니다.

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
6. 생성된 기기를 우클릭 → 이름을 `Recording Output`처럼 장소에 안 묶인 이름으로 변경(추천)
7. **시스템 설정 → 사운드 → 출력**에서 이 다중 출력 기기를 선택

**노트북을 카페 ↔ 집 등 다른 곳에서 쓸 때**: 다중 출력 기기를 새로 만들 필요 없이, 기존
"다중 출력 기기" 설정 화면에서 **체크박스만 바꿔주면** 됩니다 — 예를 들어 카페에서는 이어폰/
스피커 장치(`USB Audio` 등)를 체크, 집에 가서 모니터를 연결하면 그 장치 체크 해제하고
`DELL U2719D`를 체크 + 기본 기기(마스터)도 그에 맞게 변경. `BlackHole 2ch`는 항상 체크된
채로 둡니다.

**알아두면 좋은 점**
- 다중 출력 기기 사용 중에는 **키보드 볼륨 키가 안 먹습니다** — 대신 오디오 MIDI 설정 화면의
  각 장치 행에 있는 **개별 음량 슬라이더**로 조절합니다. (녹음 다 끝난 뒤 원래 출력으로
  되돌리는 방법은 아래 트러블슈팅 "다 듣고 나서" 참고)
- `BlackHole 2ch`만 단독으로 출력 장치로 잡으면 **소리가 전혀 안 들립니다.** 반드시 물리
  장치와 함께 "다중 출력"으로 써야 합니다.
- 시스템 알림음, 타이핑 소리 등 **다른 앱 소리도 같이 녹음**됩니다. 녹음할 때는 다른 알림을
  꺼두는 게 좋습니다.
- 듣지 않고 무음으로만 녹음하는 방법은 위 "⚠️ 주의사항"을 참고하세요.

### 3. 마이크 권한 확인

macOS는 BlackHole 캡처도 "마이크 입력"으로 취급합니다. 첫 녹음 시 권한 팝업이 뜨면 **허용**을
눌러주세요. 팝업이 안 뜨거나 이미 거부했다면: **시스템 설정 → 개인정보 보호 및 보안 → 마이크**에서
사용 중인 터미널 앱(Warp 등)을 허용으로 켜주세요. 권한이 없으면 ffmpeg가 **아주 짧거나
무음인 WAV**를 만듭니다.

### 4. whisper.cpp 빌드 + 모델

whisper.cpp는 이 저장소에 포함되어 있지 않습니다 (모델 파일이 547MB로 GitHub 업로드 용량
제한을 넘고, 빌드 결과물도 이 맥 전용 바이너리라 그대로 옮겨 쓸 수 없습니다). 아래처럼
직접 clone + build 하세요:

- **저장소**: https://github.com/ggml-org/whisper.cpp
- **이 프로젝트가 빌드/검증한 버전**: `v1.9.2-17-g592feef0` (커밋 `592feef0`, 2026-08-07)
  — 최신 `master`를 그대로 써도 대체로 호환되지만, 문제가 생기면 이 커밋으로 체크아웃해보세요
  (`git checkout 592feef0`).

```bash
git clone https://github.com/ggml-org/whisper.cpp.git ~/sound-notes/whisper.cpp
cd ~/sound-notes/whisper.cpp
cmake -B build -DGGML_METAL=ON
cmake --build build --config Release -j$(sysctl -n hw.logicalcpu)
sh ./models/download-ggml-model.sh large-v3-turbo-q5_0    # 574MB 다운로드
```

`-DGGML_METAL=ON`은 Apple Silicon(M1 이상)에서 GPU 가속을 씁니다. Intel Mac은 CPU
백엔드로 동작은 하겠지만 훨씬 느릴 수 있고, 이 프로젝트에서 별도로 검증하지는 않았습니다.

**모델 선택 근거**: `large-v3-turbo`는 `large-v3`를 디코더 4층으로 증류한 모델로, `medium`
(디코더 24층, 1.53GB)보다 **빠르면서 한국어 인식률도 더 좋습니다**. `q5_0` 양자화로 574MB.
정확도를 더 올리고 싶으면 비양자화 버전(`large-v3-turbo.bin`, 1.62GB)으로 바꿀 수 있습니다:

```bash
sh ./models/download-ggml-model.sh large-v3-turbo
WHISPER_MODEL=~/sound-notes/whisper.cpp/models/ggml-large-v3-turbo.bin note-stop
```

(모델 경로는 `WHISPER_MODEL` 환경변수로, whisper.cpp 위치는 `WHISPER_DIR`로 오버라이드 가능)

**⚠️ `~/sound-notes` 폴더 자체를 나중에 다른 경로로 옮기면**, `whisper-cli` 바이너리가
빌드 시점의 절대 경로를 라이브러리 링크 경로로 갖고 있어서 `dyld: Library not loaded` 오류가
납니다. 폴더를 옮겼다면 `whisper.cpp`만 새 경로에서 다시 빌드하세요(모델 재다운로드는 불필요):
```bash
cd ~/sound-notes/whisper.cpp && rm -rf build
cmake -B build -DGGML_METAL=ON && cmake --build build --config Release -j$(sysctl -n hw.logicalcpu)
```

### 5. 셸 함수 등록

`~/.zshrc` 맨 끝에 아래 두 줄이 이미 추가되어 있습니다:

```zsh
# 시스템 오디오 녹음 → 한국어 전사 파이프라인 (개인 학습·기록 용도)
source "$HOME/sound-notes/bin/notes.zsh"
```

새 터미널을 열면 자동으로 `note-start` / `note-stop` / `note-status` 명령을 쓸 수
있습니다.

---

## 사용법

```bash
note-start "스프링부트-3강"     # 녹음 시작 (백그라운드, 프롬프트 즉시 복귀)
# ... 시청 ...
note-status                      # (선택) 현재 녹음 중인지, 몇 분 지났는지 확인
note-stop                        # 녹음 종료 → 자동으로 한국어 전사 실행
```

`note-stop` 실행이 끝나면 아래 경로에 결과물이 생깁니다:

```
~/sound-notes/transcripts/예제강의/예제강의_20260813_1430.wav
~/sound-notes/transcripts/예제강의/예제강의_20260813_1430.md
~/sound-notes/transcripts/예제강의/예제강의_20260813_1430_plain.md
```

`.md`는 아래처럼 문단별 타임스탬프(재생 기준 `MM:SS`)가 붙은 형태입니다 — 특정 구간을
다시 찾을 때 씁니다 (아래는 형식을 보여주기 위한 가상의 예시입니다):

```markdown
# 예제강의

## 00:00
안녕하세요, 오늘은 예시 주제 A에 대해 살펴보겠습니다.

## 00:15
먼저 배경을 간단히 짚고 넘어가겠습니다.
```

`_plain.md`는 타임스탬프 없이 순수 텍스트만 이어져 있습니다 — **그대로 LLM에 붙여넣어**
요약을 요청할 때 이쪽을 쓰면 됩니다(타임스탬프가 없어 노이즈가 적습니다).

**동시에 하나의 녹음만** 가능합니다. 이미 녹음 중일 때 `note-start`를 또 실행하면 안내
메시지와 함께 실패합니다 — 먼저 `note-stop`으로 끝내세요.

**같은 제목으로 여러 번 녹음해도 안전합니다.** 파일명에 분 단위 타임스탬프가 들어가서
(`{제목}_{YYYYMMDD}_{HHMM}...`) 같은 `transcripts/{제목}/` 폴더 안에 별도 파일로 쌓이고,
기존 파일을 덮어쓰지 않습니다 — 한 강의를 여러 세션(1강, 2강 이어듣기 등)에 걸쳐 녹음할 때
그냥 같은 제목을 계속 쓰면 됩니다. (아주 드물게 같은 1분 안에 `note-stop` 후 바로
`note-start`를 다시 하면 파일명이 겹쳐 덮어써질 수 있으나, `note-start`가 PID 파일로 동시
녹음 자체를 막고 있어 실제로 발생하기 어렵습니다.)

---

## 트러블슈팅

**"BlackHole 2ch 장치를 찾을 수 없습니다"**
`note-start`가 전체 오디오 장치 목록을 출력해줍니다. 확인 순서:
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

**`note-status`는 계속 "녹음 중"이라는데 나중에 보니 파일이 아예 없음**
ffmpeg 프로세스는 죽지 않은 채 BlackHole을 열지 못하고 그대로 멈춰있을 수 있습니다 —
프로세스가 살아있으니 `note-status`도 계속 "녹음 중"으로 보이지만 실제로는 아무것도
기록되고 있지 않습니다(2026-08-13 실제 발생, 16분 넘게 이 상태였음). 대화형 zsh는 `&`로
백그라운드 보낸 작업을 별도 프로세스 그룹으로 분리하는데(job control), 이 상태의 ffmpeg가
avfoundation으로 BlackHole을 열 때 조용히 멈추는 경우가 원인으로 확인됐습니다(마이크 권한은
정상이었음 - foreground 실행은 항상 즉시 성공했음). `note-start` 안에서 job control을 끄도록
고쳐서 해결했습니다. 지금은 `note-start`가 시작 직후 WAV 파일이 실제로 생겼는지 확인하고,
`note-status`도 파일이 15초 넘게 갱신되지 않으면 경고를 띄우므로 문제가 재발해도 몇 초 안에
알 수 있습니다.

**전사 결과가 같은 문장을 계속 반복함 (환각)**
Whisper 계열 모델의 흔한 실패 패턴으로, 보통 **무음/배경음악/불명확한 발화 구간**에서
나타납니다. 녹음 자체(음량)는 정상인데 이 현상이 나오면 해당 구간의 실제 오디오 내용을
의심해보세요.

**전사가 너무 느림**
`bin/transcribe.sh`의 `-t 4`는 Apple M2의 P-core 4개 기준입니다. 다른 칩이면
`sysctl -n hw.perflevel0.logicalcpu`로 P-core 개수를 확인해 값을 조정하세요. 인코딩 자체는
Metal(GPU)이 처리하므로 스레드 수를 과하게 늘려도 별 효과가 없습니다.

**`dyld: Library not loaded: @rpath/libwhisper.1.dylib`**
`~/sound-notes` 폴더를 옮긴 뒤 `whisper.cpp`를 다시 빌드하지 않아서 생기는 오류입니다.
위 "4. whisper.cpp 빌드 + 모델"의 재빌드 명령을 실행하세요.

**`.md`의 타임스탬프가 실제 진행 시간과 안 맞음**
배속 재생 때문입니다 — 위 "⚠️ 주의사항" 참고.

**Obsidian에서 `.wav`만 보이고 `.md`가 안 보임**
`.md`는 Obsidian이 기본으로 지원하므로 정상적으로 보여야 합니다. 안 보인다면 vault 캐시
문제일 수 있으니 Obsidian을 재시작하거나 사이드바를 새로고침해보세요.

**다 듣고 나서**
시스템 설정 → 사운드 → 출력을 **원래 장치로 되돌리세요**(내장 스피커, DELL 모니터 등). 다중
출력 기기를 계속 켜두면 볼륨 키가 안 먹는 등 불편할 수 있습니다.

---

## 환경변수 오버라이드

| 변수 | 기본값 | 설명 |
|---|---|---|
| `WHISPER_DIR` | `~/sound-notes/whisper.cpp` | whisper.cpp 클론/빌드 위치 |
| `WHISPER_MODEL` | `$WHISPER_DIR/models/ggml-large-v3-turbo-q5_0.bin` | 사용할 모델 파일 경로 |

사용 예시는 위 "4. whisper.cpp 빌드 + 모델"의 비양자화 모델 교체 명령 참고.
