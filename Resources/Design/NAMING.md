# 공개 이름 검토

확인일: 2026-10-16. 현재 앱 이름은 Bookside / 서재이며, 아래는 확정 전 제안입니다.
GitHub 저장소 생성, 공개 전환, 앱 식별자 변경은 이 조사에 포함하지 않았습니다.

## 제품의 중심

네이티브 macOS에서 개인 PDF를 읽고, 다시 읽고, 책마다 메모를 쌓는 서재입니다.
SwiftUI/PDFKit, Apple Vision OCR, 로컬 파일과 SQLite, 외부 Codex/Claude Code를 위한
CLI와 읽기 전용 MCP 접근을 제공합니다. 앱 내 AI 답변 생성은 현재 구현 범위가 아닙니다.

이름은 독서와 기록을 중심에 두는 편이 적합합니다. PDF나 AI를 이름에 고정하면
반복 독서, 책장, 메모라는 중심 기능을 설명하기 어렵습니다. 이는 아래 도구들의
포지셔닝과 현재 구현을 비교한 판단입니다.

## 유사 프로젝트

기능은 공식 README 또는 공식 홈페이지에서 확인했습니다. 직접 설치해 비교한 결과는 아닙니다.
GitHub의 `pushedAt`은 저장소 활동 신호이며 안정성이나 릴리스 완료를 보증하지 않습니다.

| 프로젝트 | 확인한 기능과 비교 관점 | 라이선스 / 활동 근거 |
| --- | --- | --- |
| [Readest](https://github.com/readest/readest) | EPUB/PDF 등 여러 형식, 하이라이트와 메모, 병렬 읽기. 폭넓은 독서 기능과 짧은 제품 이름의 사례 | AGPL-3.0, API 확인 push 2026-10-16. Next.js/Tauri 기반 |
| [Koodo Reader](https://github.com/koodo-reader/koodo-reader) | 책장, 독서 통계, 노트와 하이라이트 내보내기. 독서 관리 기능의 가까운 비교 대상 | AGPL-3.0, API 확인 push 2026-10-16. 여러 운영체제 지원 |
| [Sioyek](https://github.com/ahrm/sioyek) | 교재와 논문 PDF, 참조 이동과 포털. 집중해서 읽는 데 필요한 이동 조작의 비교 대상 | GPL-3.0, API 확인 push 2026-10-07. Qt 기반 |
| [Open Notebook](https://github.com/lfnovo/open-notebook) | NotebookLM과 유사한 개인 자료 기반 AI 작업 공간. 이름과 소개에서 AI 연구 기능을 전면에 둠 | MIT, API 확인 push 2026-10-13. 우리 앱의 현재 내장 기능과는 범위가 다름 |
| [Skim](https://skim-app.sourceforge.io/) | macOS PDF 읽기, 주석, 하이라이트, 책갈피와 텍스트 내보내기. 네이티브 독서 UX의 비교 대상 | 공식 홈페이지 1.7.17 표시. 이번 조사에서 라이선스 원문과 최근 커밋은 확인하지 않음 |

탐색은 `oss-explore/scripts/explore.sh 'pdf reader' --limit 7 --json`으로 시작하고,
렌더링 라이브러리, 모바일 SDK, 발표 도구를 제외한 뒤 목적에 맞는 제품을 추가 확인했습니다.
GitHub 후보는 `gh repo view`와 `gh api repos/<owner>/<repo>/readme`로 원문을 읽었습니다.

## 이름 제안

| 후보 | 발음 / 저장소 slug | 제안 이유 | 확인 범위와 단점 |
| --- | --- | --- | --- |
| **Readgrain** | 리드그레인 / `readgrain` | 읽으면서 남긴 메모와 반복 독서가 쌓인다는 의미를 부여할 수 있음. 독서 기능이 바로 연상되고 AI나 특정 형식에 묶이지 않음 | GitHub 이름 검색 0건. 웹 검색에서 동명의 독서 앱은 찾지 못함. Go 코드의 `ReadGrain` 식별자는 검색됨. 한국어 발음은 다소 김 |
| Margrove | 마그로브 / `margrove` | margin + grove에서 착안한 조어. 여백의 기록이 모여 나만의 서재가 된다는 방향 | GitHub 이름 검색 0건, 웹 검색에서 동명의 독서 앱은 찾지 못함. 철자와 뜻을 처음에 설명해야 하고 mangrove와 혼동될 수 있음 |

**추천: Readgrain.** 기능이 늘어도 “읽기와 기록이 쌓이는 도구”라는 소개를 유지하기 쉽습니다.

- 앱: `Readgrain`
- 저장소 제안: `seungwonme/readgrain`
- 영어 소개: `A native macOS reading workspace for your PDFs, notes, and AI agents.`
- 한국어 소개: `읽고, 남기고, 다시 읽는 나만의 서재.`

확인 당시 `gh api repos/seungwonme/readgrain`은 HTTP 404를 반환했습니다.
이는 조회 당시의 저장소 상태 확인이며 이름 예약, 상표 검토, 도메인 확보 결과는 아닙니다.

## 제외한 이름과 근거

- [여백 / Yeobaek](https://play.google.com/store/apps/details?id=com.yeobaek.app): 이미 독서 기록 앱이 사용합니다. [동명 독서 서비스 저장소](https://github.com/woowacourse-teams/2026-yeobaek)도 확인했습니다.
- [Pagefold](https://pagefold.app/): 이미 PDF 도구가 사용합니다.
- [Pagewell](https://github.com/pagewellai/pagewell): AI 에이전트의 문서 공유 도구가 사용합니다. 별도의 [브라우저 OCR 프로젝트](https://github.com/itzhaydar/pagewell)도 있습니다.
- [Leafory](https://github.com/NitrozDeveloper/leafory): 이미 책 탐색 앱이 사용합니다.
- [Leafmark](https://apps.apple.com/us/app/leafmark-epub-reader-notes/id6781045740): 이미 전자책 리더와 메모 앱이 사용합니다.
- [Foliary](https://foliary.uk/): 식물 관리 앱이 사용합니다.

이름 중복은 공개 검색과 GitHub 이름 검색에서 확인한 범위입니다. 검색 결과의 부재를
이름의 독점 사용 가능성으로 해석하지 않습니다.
