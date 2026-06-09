# 📌 StickyPresenter

**Keynote 전체 화면 위에 떠 있는 스티키 노트 & 텔레프롬프터 macOS 앱**

Lucid Notes에서 영감을 받아, Keynote 프레젠테이션 중에도 메모와 대본을 볼 수 있는 플로팅 윈도우 앱입니다.

## 🔗 Links

- 🏠 [Home](https://developeracademy-postech.github.io/StickyPresenter/)
- 🛟 [Support](https://developeracademy-postech.github.io/StickyPresenter/support.html)
- 🔒 [Privacy Policy](https://developeracademy-postech.github.io/StickyPresenter/privacy.html)

## ✨ Features

### 🗒️ Floating Sticky Notes
- Keynote 전체 화면 모드 위에서도 항상 보임
- 6가지 포스트잇 색상 (Yellow, Pink, Green, Blue, Purple, Orange)
- 투명도(opacity) 조절 가능 (20% ~ 100%)
- 폰트 크기 조절
- 편집 잠금(Lock) 기능
- 드래그로 위치 이동, 리사이즈 가능
- 클립보드에서 바로 노트 생성

### 📺 Teleprompter Mode
- 프레젠테이션 대본 자동 스크롤
- 스크롤 속도 조절 (5 ~ 120 px/s)
- 폰트 크기 조절 (14pt ~ 48pt)
- 좌우 반전(Mirror) 모드 — 텔레프롬프터 유리 대응
- 재생/일시정지/되감기 컨트롤
- 상하 그라데이션 오버레이로 가독성 확보

### 🎯 Core Technical Features
- `NSPanel` + `fullScreenAuxiliary` → Keynote 전체 화면 위에 표시
- `canJoinAllSpaces` → 모든 데스크톱/Space에서 표시
- Menu Bar only 앱 (Dock 아이콘 없음)
- `nonactivatingPanel` → Keynote 포커스를 빼앗지 않음

## 🚀 Xcode Project Setup

### 1. Create New Project
1. Xcode → File → New → Project
2. **macOS** → **App** 선택
3. Product Name: `StickyPresenter`
4. Interface: **SwiftUI**
5. Language: **Swift**
6. Bundle Identifier: `com.gaebalja-ri.StickyPresenter`
7. ❌ Use Core Data 체크 해제
8. ❌ Include Tests 체크 해제

### 2. Add Source Files
프로젝트에 다음 파일들을 추가 (기존 ContentView.swift, xxxApp.swift 삭제):

```
StickyPresenter/
├── StickyPresenterApp.swift    # App entry point + AppDelegate
├── Models.swift                 # NoteColor, StickyNote model
├── NoteManager.swift            # Floating panel creation & management
├── StickyNoteView.swift         # Post-it style note UI
├── TeleprompterView.swift       # Teleprompter mode UI
└── Info.plist                   # LSUIElement = true (menu bar only)
```

### 3. Project Settings

#### Info.plist
- **Application is agent (UIElement)** → `YES` (LSUIElement = true)
  - 이렇게 하면 Dock에 앱 아이콘이 표시되지 않고, 메뉴바에서만 동작합니다.

#### Build Settings
- **macOS Deployment Target**: 14.0 이상
- **App Sandbox**: `NO` (Entitlements에서 설정)
  - 전체 화면 위에 윈도우를 띄우려면 Sandbox를 비활성화해야 합니다.

#### Signing
- Development 빌드: Automatically manage signing
- Sandbox OFF 상태이므로 Mac App Store 배포 시에는 별도 설정 필요

### 4. Build & Run
- `⌘ + R` 로 빌드
- 메뉴바에 📝 아이콘이 나타남
- 클릭하여 노트 추가, 텔레프롬프터 열기 등 사용

## 📋 Keyboard Shortcuts (Menu Bar)

| Shortcut | Action |
|----------|--------|
| ⌘N | New Sticky Note |
| ⌘V | New Note from Clipboard |
| ⌘T | Open Teleprompter |
| ⌘S | Show All Notes |
| ⌘H | Hide All Notes |
| ⌘Q | Quit App |

## 🔧 How It Works (Key Architecture)

### Why NSPanel?
일반 `NSWindow`로는 Keynote 전체 화면 위에 표시할 수 없습니다. `NSPanel`에 다음 설정을 조합해야 합니다:

```swift
let panel = NSPanel(
    contentRect: frame,
    styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)

// 최상위 윈도우 레벨
panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))

// 모든 Space + 전체 화면 앱 옆에 표시
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

// 앱 비활성화 시에도 숨기지 않음
panel.hidesOnDeactivate = false

// 포커스를 빼앗지 않음
panel.becomesKeyOnlyIfNeeded = true
```

### Window Level Hierarchy
```
.screenSaver (1000)     ← 화면 보호기
.maximumWindow (∞)      ← ✅ StickyPresenter 여기!
.popUpMenu              ← 팝업 메뉴
.mainMenu               ← 메뉴 바
.floating               ← 일반 플로팅 윈도우
.normal                 ← 일반 윈도우
```

## 🎨 Customization Ideas

- [ ] iCloud 동기화로 여러 Mac에서 노트 공유
- [ ] 글로벌 단축키 (HotKey)로 노트 토글
- [ ] Markdown 렌더링 지원
- [ ] 타이머 (프레젠테이션 시간 관리)
- [ ] Keynote AppleScript 연동 (슬라이드 넘길 때 노트 자동 변경)
- [ ] 위젯 스타일 변형 (투명 배경 텍스트만 표시)

## 📄 License

MIT License — 자유롭게 수정/배포 가능

---

Built with ❤️ for presenters who need notes on screen.
