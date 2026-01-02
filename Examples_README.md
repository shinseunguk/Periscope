# Periscope Examples

이 디렉토리에는 Periscope SDK를 사용하는 예제 앱들이 포함되어 있습니다.

## 예제 앱들

### 1. PeriscopeUIKitExample
UIKit을 사용하는 iOS 앱 예제입니다.

### 2. PeriscopeSwiftUIExample
SwiftUI를 사용하는 iOS 앱 예제입니다.

## 실행 방법

### Xcode로 실행하기
1. Xcode에서 각 예제 폴더를 엽니다
2. File → Add Package Dependencies 메뉴 선택
3. 상위 디렉토리의 Periscope 패키지를 추가
4. Run 버튼을 눌러 실행

### SPM으로 의존성 추가하기
```swift
dependencies: [
    .package(path: "../..")
]
```

### CocoaPods로 의존성 추가하기
```ruby
pod 'Periscope', :path => '../..'
```

## 주요 기능
- Periscope SDK 초기화
- 기본 기능 테스트
- UI 통합 예제