![실제 macOS 서재 앱의 PDF 책장, 읽기 화면과 책별 메모](Resources/Design/evidence/readme-reader-light.jpg)

# Bookshelf / 서재

**PDF를 읽고, 옆에 생각을 남기고, 읽던 맥락을 AI 클라이언트로 이어갈 수 있습니다.**

서재는 책별 메모, 로컬 OCR, 읽기 전용 MCP 서버를 갖춘 macOS PDF 리더입니다.
PDF는 원래 폴더에 두고 메모, 책갈피, 읽던 위치는 로컬 SQLite에 저장합니다.

[English](README.md) | [시작하기](docs/01-getting-started.md) |
[사용법](docs/02-reading-and-notes.md) | [CLI/MCP](docs/03-cli-and-mcp.md) |
[기여 안내](CONTRIBUTING.md)

위 화면은 직접 작성한 예시 PDF와 메모를 실제 앱에서 연 캡처입니다.
앱의 화면 문구는 한국어이며, 현재 상세 개발 문서는 영어로 제공합니다.

## 할 수 있는 일

- **읽기와 이어 읽기:** PDF 원문/텍스트 보기, 키보드 페이지 이동, 읽는 중인 책 모아보기.
- **책 옆에 메모 남기기:** 자동 저장 노트, 문장 발췌와 코멘트, 하이라이트, 책갈피, Markdown 내보내기.
- **OCR 공백을 무시한 검색:** 글자 사이 공백과 줄바꿈이 섞인 한국어/영어 본문도 검색할 수 있습니다.
- **Mac에서 OCR 실행:** OCRmyPDF와 AppleOCR로 새 PDF 사본을 만들고 원본과 비교한 뒤 선택할 수 있습니다.
- **AI 클라이언트 연결:** Claude Code나 Codex에서 책, 페이지, 검색 결과, 메모, 마지막 읽던 위치를 읽을 수 있습니다.
- **네이티브 작업 화면:** SwiftUI/AppKit, 밝게/어둡게 보기, 크기 조절이 가능한 패널을 제공합니다.

<details>
<summary>다른 실제 화면 보기</summary>

읽는 중인 책:

![읽는 중인 책과 페이지 진행률](Resources/Design/evidence/reading-shelf-light.png)

어두운 화면:

![어두운 화면의 PDF와 메모](Resources/Design/evidence/readme-reader-dark.jpg)

OCR 사본 검토:

![원본과 개선한 OCR 텍스트 비교](Resources/Design/evidence/ocr-review-dark.png)

모든 화면에는 직접 만든 예시 자료를 사용했습니다. [촬영 기록](Resources/Design/evidence/readme-capture.md)을 확인할 수 있습니다.

</details>

## 시작하기

현재는 소스를 받아 빌드하는 방식입니다. 공증된 설치 파일이나 공개 바이너리 릴리스는 없습니다.
macOS, 호환되는 Xcode/Swift 도구 체인, 빌드 보조 스크립트용 Python 3가 필요합니다.

```sh
git clone https://github.com/NomaDamas/bookshelf.git
cd bookshelf
./scripts/build-app.sh
./scripts/open-app.command
```

**PDF 추가…** (`Command-O`) 또는 **폴더 추가…** (`Command-Shift-O`)로 자료를 넣고,
책을 선택한 뒤 **메모**에 생각을 적으면 됩니다. 읽기와 메모에는 OCR 설치나 AI 계정이 필요하지 않습니다.

빌드한 앱을 `~/Applications/Bookshelf.app`에 설치하려면:

```sh
./scripts/install-local.command
```

업데이트할 때는 앱을 종료하고 소스를 갱신한 뒤, 빌드와 설치를 다시 실행하면 됩니다.
설치 스크립트는 이미 있는 빌드가 최신인지 자동으로 판단하지 않습니다.

최소 배포 대상은 macOS 14입니다. 실제 검증 환경은 Apple Silicon,
macOS 26.6.2, Xcode 27 / Swift 6.4이며, 이전 macOS와 Intel Mac의 전체 동작은 검증되지 않았습니다.
로컬 빌드는 기본적으로 임시 서명(ad-hoc signing)을 사용합니다.
`python3 scripts/release.py package`로 검증된 DMG를 만들 수 있습니다.
버전 관리, 아키텍처별 파일, 정식 서명과 GitHub 초안 릴리스는 [배포 안내](docs/09-releasing.md)를 참고하세요. [설치 및 문제 해결](docs/01-getting-started.md)
문서에서 도구 체인 선택과 별도 샘플 서재 실행을 설명합니다.

## 선택 기능: OCR과 AI 연결

OCR은 [설치 및 검토 안내](docs/04-ocr.md)를 따라 별도로 준비할 수 있습니다.
원본을 보존한 새 사본을 만들며, 앱에서 결과를 확인한 뒤 기존 책에 연결할 수 있습니다.
품질 보고서만으로 모든 글자의 정확성을 보장하지는 않습니다.

앱을 설치한 뒤 MCP 등록 도우미를 실행할 수 있습니다.

```sh
./scripts/register-mcp.command
```

설치된 Codex/Claude Code에 서버를 등록하며, 기존 `bookshelf` 등록은 유지합니다.
클라이언트를 다시 시작하고 도구 목록과 실제 호출을 확인하면 됩니다.
예: “내 서재에서 책을 찾아 집중력이라는 단어가 나오는 PDF 페이지를 근거와 함께 알려줘.”

MCP 도구는 읽기 전용입니다. CLI에는 메모 저장, 가져오기, OCR 등 쓰기 명령도 있습니다.
**AI로 이어가기**는 맥락 프롬프트를 클립보드에 복사하며, 앱 안에서 모델을 실행하지 않습니다.
연결한 AI 클라이언트는 설정에 따라 책 본문과 메모를 모델 제공자에게 전송할 수 있습니다.

## 문서

| 목적 | 안내 |
| --- | --- |
| 빌드, 설치, 첫 PDF 열기 | [시작하기](docs/01-getting-started.md) |
| 읽기, 메모, 검색, 단축키 | [사용법](docs/02-reading-and-notes.md) |
| CLI 명령과 MCP 도구 | [CLI/MCP 레퍼런스](docs/03-cli-and-mcp.md) |
| OCR 설치, 사본 검토, 원본 선택 | [OCR](docs/04-ocr.md) |
| 모듈, 데이터 흐름, 책 식별자 | [아키텍처](docs/05-architecture.md) |
| 개발 환경, 테스트 순서, 화면 검증 | [개발과 검증](docs/06-development.md) |
| 데이터 위치, 백업, 개인정보 | [데이터 안내](docs/07-data-and-privacy.md) |
| 기존 OCR 레이어 점검과 복구 | [고급 PDF 유지보수](docs/08-pdf-maintenance.md) |
| DMG 생성, 버전, 태그, GitHub Release | [배포 안내](docs/09-releasing.md) |
| 버그 제보와 코드 기여 | [CONTRIBUTING](CONTRIBUTING.md) |
| 코딩 에이전트의 작업 기준 | [AGENTS.md](AGENTS.md) |

전체 자료는 [문서 색인](docs/README.md)에서 볼 수 있습니다.
EPUB, 의미 기반 검색, 내장 모델, 기기 간 메모 동기화는 현재 구현돼 있지 않습니다.
iCloud에만 있는 PDF는 Finder에서 내려받은 뒤 읽을 수 있습니다.

## 라이선스

앱과 코어 코드는 [MIT](LICENSE)입니다. 의존성 고지는 앱 번들에 포함됩니다.
별도로 설치하는 OCR 도구에는 각 도구의 라이선스가 적용됩니다.
사용자의 책, 추출한 본문, 개인 메모는 소스 배포물에 포함하지 않습니다.
