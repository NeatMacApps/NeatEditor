# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon.png" width="128" height="128" alt="NeatEditor 앱 아이콘">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-1f6feb)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> macOS용 네이티브 일반 텍스트 편집기입니다.

**언어:** [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Français](./README.fr.md) | [Deutsch](./README.de.md)

## 스크린샷

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="NeatEditor 메인 작업 공간" width="1120" />
</p>

## 설치

**macOS 26.0+ · Apple silicon 및 Intel 지원.** macOS 전용이며 Linux 또는 Windows 버전은 없습니다.

```bash
brew install --cask x0c/tap/neateditor
```

또는 [서명 및 공증된 최신 DMG](https://github.com/NeatMacApps/NeatEditor/releases/latest)를 열고 `NeatEditor.app`을 `Applications`로 드래그하세요.

실행 후 `Command + O`로 파일을 열거나 `Command + N`으로 새 문서를 만드세요.

## 왜 NeatEditor인가

메모, 초안, 텍스트 파일을 간단히 수정할 때 사용하세요.

## 주요 특징

- **탭 관리:** 전환, 닫기, 바로 이름 바꾸기, 최근 닫은 탭 다시 열기.
- **로컬 파일:** Finder, 드래그 앤 드롭, 파일 URL 붙여넣기로 열 수 있습니다. 저장한 문서의 이름을 바꾸면 디스크 파일 이름도 바뀝니다.
- **네이티브 편집:** 줄 번호, 찾기, 실행 취소, IME 조합 입력, `Command +/-` 글자 확대·축소.
- **자동 저장:** 입력을 멈춘 지 2초 후, 탭 전환 시, 앱 비활성화 시 순서대로 저장합니다.
- **외부 수정:** 다른 편집기, 스크립트, 코딩 에이전트가 만든 변경을 처리합니다. 수정하지 않은 버퍼는 다시 읽고, 독립적인 변경은 보수적으로 병합하며, 감지된 충돌은 두 버전을 모두 보관합니다.
- **빈 내용 보호:** 비어 있거나 공백뿐인 내용은 기존 파일을 덮어쓰지 않습니다. 편집기를 비워도 디스크 파일은 비워지지 않습니다.
- **문서 폴더:** 기본값은 `~/Documents`이며 설정 → 편집기 → 문서 폴더에서 변경합니다. 새 문서는 선택한 폴더에 저장됩니다.
- **항상 보이게:** 창을 맨 위에 고정하고 익숙한 네이티브 메뉴와 제목 표시줄을 사용하세요.

동시 편집 보호는 외부 프로그램의 쓰기를 막지 않습니다. 중요한 파일은 따로 백업하세요.

## 주요 단축키

| 단축키 | 동작 |
| --- | --- |
| `Command + N` | 새 문서를 만듭니다. |
| `Command + T` | 새 탭을 하나 더 엽니다. |
| `Command + O` | 하나 이상의 로컬 텍스트 파일을 엽니다. |
| `Command + S` | 현재 탭을 즉시 저장합니다. |
| `Command + W` | 현재 탭을 저장하고 닫습니다. |
| `Shift + Command + T` | 가장 최근에 닫은 탭을 다시 엽니다. |
| `Command + F` | 현재 편집기의 인라인 찾기 바를 표시합니다. |
| `Command + =` 또는 `Command + +` | 편집기 글자를 확대합니다. |
| `Command + -` | 편집기 글자를 축소합니다. |
| `Command + ,` | 설정을 엽니다. |
| `Shift + Return` | 현재 줄 끝으로 이동해 새 줄을 넣습니다. |

<details>
<summary>소스에서 빌드하기 (Xcode)</summary>

macOS 26.0+, Xcode 26.0+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+가 필요합니다.

```bash
git clone https://github.com/NeatMacApps/NeatEditor.git
cd NeatEditor
xcodegen generate
open NeatEditor.xcodeproj
```

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

테스트와 개발 방법은 [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.

</details>

## 문서

- [기여 및 테스트](CONTRIBUTING.md)
- [릴리스 이력](CHANGELOG.md)

이슈, 제안, 풀 리퀘스트를 환영합니다.

## 라이선스

NeatEditor는 [MIT License](LICENSE)로 공개됩니다.

## 관련 도구

| 도구 | 설명 |
|---|---|
| [NeatPaste](https://github.com/NeatMacApps/NeatPaste) | 메뉴 막대의 macOS 클립보드 기록. |
| [NeatWebApp](https://github.com/NeatMacApps/NeatWebApp) | 웹사이트를 독립 macOS 앱으로 만들고 노치 런처에서 실행. |
| [HandySwitch](https://github.com/x0c/HandySwitch) | 메뉴 막대에서 다크 모드 전환과 잠자기 방지. |
| [MacResourceMonitor](https://github.com/x0c/MacResourceMonitor) | 메뉴 막대에서 CPU를 많이 쓰는 프로세스 확인. |
| [Corral](https://github.com/corral-dev/corral) | 터미널에서 코딩 에이전트 세션을 관리하고 Mac이나 iPhone에서 이어서 사용. |
