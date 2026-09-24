# BookScannerReader

iPhone용 책 스캔 + OCR + PDF Reader 프로토타입입니다.

## 현재 포함된 1차 기능
- 서재(책 목록) 기본 구조
- VisionKit 문서 스캔
- 1페이지/2페이지 촬영 모드
- 2페이지 촬영 시 좌/우 페이지 분리
- 첫 페이지를 기준으로 페이지 가로:세로 비율 저장(ScanProfile)
- 이후 페이지를 기준 비율의 동일 캔버스로 정규화
- OCR (한국어/영어 우선)
- 스캔 이미지 → PDF 생성
- 기존 PDF 가져오기
- PDFKit 기반 PDF Reader
- OCR 텍스트 음성 읽기(TTS)
- 사용자 책 데이터는 앱 Documents 폴더에 저장, Git 저장소와 분리

## 중요한 현재 한계
1. 2페이지 분리는 현재 중앙 50% 기준의 안전한 1차 구현입니다. 다음 단계에서 제본선 자동 검출로 교체합니다.
2. 책 중앙의 곡면(dewarp) 보정은 아직 미구현입니다.
3. 첫 사진만으로 실제 mm 단위 종이 크기를 정확히 알 수는 없습니다. 현재는 첫 페이지의 비율을 기준 규격으로 사용합니다. 실제 A4/B5/사용자 mm 입력 기능은 다음 단계에서 추가할 수 있습니다.
4. Xcode/iOS SDK가 필요한 실제 빌드 검증은 macOS + Xcode에서 수행해야 합니다.

## 권장 환경
- macOS + Xcode 최신 안정 버전
- iOS 18 이상 권장
- SwiftUI

## Xcode 프로젝트 생성 방법
1. Xcode에서 **iOS > App** 프로젝트 생성
2. Product Name: `BookScannerReader`
3. Interface: SwiftUI / Language: Swift
4. 생성된 기본 Swift 파일을 삭제하거나 대체하고, 이 폴더의 `App`, `Models`, `Services`, `Views`, `Utilities` 폴더를 프로젝트에 추가
5. `Info.plist`에 아래 Camera Usage Description 추가
   - `Privacy - Camera Usage Description`: `책과 문서를 스캔하기 위해 카메라를 사용합니다.`

## 데이터 저장 구조
앱 실행 데이터는 Git 저장소가 아니라 iPhone 앱 Documents 아래에 저장합니다.

```
Documents/
  Library.json
  Books/
    <book-id>/
      pages/
      book.pdf
```

## 다음 구현 우선순위
1. 제본선 자동 검출 및 좌/우 독립 perspective 보정
2. 기준 페이지 네 모서리 수동 조정 UI
3. 페이지 썸네일 관리/재촬영/순서 변경
4. 검색 가능한 OCR text layer PDF
5. 자동 촬영/흔들림 검사/중복 페이지 감지
6. 책 곡면(dewarp) 보정
7. 북마크/주석/전체 텍스트 검색
8. iCloud 동기화


## v0.2 추가

- `BookScannerReader.xcodeproj` 포함: Mac의 Xcode에서 바로 열 수 있는 프로젝트 구조
- 카메라 권한 설명(`Resources/Info.plist`) 포함
- GitHub Actions 빌드 검사(`.github/workflows/ios-build.yml`) 포함
- 기본 Bundle ID: `com.jssung0326.BookScannerReader` (필요 시 Xcode Signing & Capabilities에서 변경)

### iPhone에서 실행
1. Mac에서 저장소를 Clone합니다.
2. `BookScannerReader.xcodeproj`를 Xcode로 엽니다.
3. Target > Signing & Capabilities에서 자신의 Apple ID Team을 선택합니다.
4. iPhone을 연결하고 Run을 누릅니다.

> GitHub에서 TestFlight까지 자동 배포하려면 Apple Developer Program/App Store Connect 설정과 서명용 자격 증명이 추가로 필요합니다.
