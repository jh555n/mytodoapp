# Dayweave

iOS·Android용 기기 내 저장 중심 Todo 앱의 첫 구현입니다. Flutter로 화면과 데이터를 공유하고, iOS EventKit·WidgetKit과 Android AppWidget을 네이티브로 연결합니다.

## 현재 상태

Flutter 3.47.7·Dart 3.13.5와 Android SDK 36을 설치하고, Android·iOS 프로젝트 생성 및 패키지 설치를 완료했습니다. 이전에 실패했던 공식 SDK 다운로드는 현재 성공합니다. Gradle에는 클라우드 환경의 프록시를 별도로 설정했습니다.

실행한 검증:

- 플랫폼 설정 테스트 2개 통과: 기존 URL scheme 보존, 재실행 시 중복 방지, 백업·알림·위젯 설정 반영, 스캐폴드 없는 상태에서 실패하는 동작.
- `flutter analyze`: 오류·경고·정보 메시지 없이 통과.
- `flutter test --no-pub`: 16개 통과. 반복·공휴일 이동, SQLite 영구 저장, iCalendar, 캘린더 충돌 및 화면 등록 흐름을 검사합니다.
- 공식 Android command-line tools 아카이브 체크섬 검증, SDK 플랫폼·빌드 도구·NDK 설치 완료.
- `flutter build apk --debug --no-pub`: 성공. 결과는 `build/app/outputs/flutter-apk/app-debug.apk`입니다.

OAuth 인증, 실제 iCloud 서버, 알림, 위젯, EventKit은 실기기 검증이 필요합니다. iOS 빌드는 macOS와 Xcode에서 확인해야 합니다.

## 구현한 코드

| 영역 | 내용 |
|---|---|
| 로컬 저장 | SQLite, 재시작 후 저장 유지, 로그인 없는 사용, 자동 백업 제외 설정 |
| Todo | 추가·수정·삭제·완료·완료 취소, 메모, 우선순위, 체크리스트 |
| 화면 | 오늘, 기한 초과, 날짜 없는 수집함, 다음 7일, 검색, 카테고리 필터 |
| 카테고리 | 이름·색상·아이콘 생성 및 수정 |
| 캘린더 | 월·주 보기, 날짜 선택·길게 누르기로 등록, 일정 색상 표시 |
| 반복 | 일·주·월·년 및 간격, 원래 발생일 기준 완료 기록, 월말·윤년 처리 |
| 공휴일 | 한국 2026년 데이터, 직전/다음 업무일 이동, 주말 포함 옵션 |
| 알림 | 권한 요청, 시간대 반영, 종일 일정 오전 9시 기준, 예약 재구성 |
| Google | OAuth, 캘린더 선택, 이름·색상·이벤트 라벨 가져오기, 단일 Todo 양방향 반영 |
| Apple | iOS EventKit 전체 접근, 캘린더 이름·색상 가져오기, 앱 소유 단일 일정 수정 |
| iCloud | HTTPS CalDAV 발견·조회·등록·삭제 어댑터, 기기 보안 저장소의 앱 전용 암호 |
| 연결 해제 | 인증 연결 제거, 가져온 기기 데이터 유지/제거 선택, 외부 일정 보존 |
| 충돌 | 변경 버전 비교, 사용자 선택 전 변경 보존, Google 생성 요청의 고정 ID |
| 빠른 등록 | iOS WidgetKit 확장 및 Android AppWidget에서 `dayweave://add`로 등록 화면 열기 |

다른 앱에서 만든 기존 일정은 읽기 전용으로 보여주고, Dayweave가 만든 일정만 수정·삭제합니다. 일반 캘린더 일정과 완료 가능한 Todo를 구분합니다.

## 개발 실행

기준 SDK: 공식 Flutter 저장소의 stable **3.47.7**. Android SDK 36·빌드 도구 36.0.0·NDK 28.2.13676358을 사용합니다. iOS는 macOS와 Xcode가 필요합니다. 플랫폼 설정 스크립트에는 Node.js 22 이상을 사용합니다.

기존 체크아웃에서 작업하세요. 각 클라우드 작업은 이미 격리되어 있으므로 별도 Git worktree를 만들 필요가 없습니다.

```sh
cd /workspace/mytodoapp
source tool/cloud_env.sh
flutter --version
bash tool/bootstrap.sh
dart format lib test
flutter analyze
flutter test
node tool/configure_platforms.test.mjs
flutter run # 연결한 Android 기기 또는 에뮬레이터가 필요합니다.
```

`bootstrap.sh`는 플랫폼 파일이 없으면 공식 `flutter create`로 Android·iOS 프로젝트를 생성하고, `native/`의 브리지·매니페스트·위젯 코드를 연결한 다음 패키지를 설치합니다. 재실행 시 네이티브 오버레이가 다시 적용되므로 플랫폼 변경은 `native/`의 원본에도 반영하세요. 생성한 `pubspec.lock`도 저장소에 포함해야 합니다.

이 Linux 클라우드 환경의 설치를 다시 실행하려면 `bash tool/setup_cloud.sh`를 사용합니다. Git·curl·unzip·Python 3·APT·dpkg·Node.js 22 이상이 필요합니다. JDK 21을 작업 폴더에 설치하고 Flutter와 Android 도구를 고정 버전으로 설치하며, 환경의 프록시를 Gradle에 연결합니다. 셸이 바뀔 때마다 `source tool/cloud_env.sh`로 SDK와 캐시 경로를 활성화하세요. TLS 인증서와 Debian 패키지 서명 검증은 유지합니다.

설치 스크립트 재실행도 통과했으며, 설치·시작 지침을 클라우드 환경 설정 초안에 저장했습니다. 다음 환경에 반영하려면 환경 설정에서 변경 사항을 검토·저장하고 게시해야 합니다. 현재 작업 폴더에는 도구와 앱 소스가 준비돼 있습니다.

Android APK:

```sh
flutter build apk --debug
```

iOS 위젯 타깃 등록은 macOS에서 `xcodeproj` Ruby gem이 설치된 상태로 실행합니다. CocoaPods 설치 환경에는 보통 해당 gem이 포함됩니다.

```sh
ruby tool/configure_widget.rb
flutter build ios --simulator
```

Xcode에서 Runner와 QuickAddWidget의 서명 팀을 선택해야 실기기에 설치할 수 있습니다. iOS 최소 타깃은 위젯 설정 스크립트에서 17.0으로 맞춥니다. 게시용 Android 키·Apple 서명 설정은 별도로 준비해야 합니다.

## Google 연결 설정

Google Cloud 프로젝트에서 Calendar API와 OAuth 동의 화면을 설정하고 다음 클라이언트를 등록합니다.

- Android: 패키지 `dev.dayweave.dayweave`와 설치할 빌드의 SHA-1.
- iOS: 번들 ID `dev.dayweave.dayweave`.
- Web: Android 로그인에 전달할 server client ID.

OAuth client ID는 비밀키가 아닙니다. 실제 client secret이나 사용자 access token을 파일·명령줄·저장소에 넣지 마세요. 로그인 자격 증명은 Google SDK가 관리합니다.

```sh
GOOGLE_REVERSED_CLIENT_ID=com.googleusercontent.apps.YOUR_IOS_CLIENT \
  node tool/configure_platforms.mjs
flutter run \
  --dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT.apps.googleusercontent.com \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT.apps.googleusercontent.com
```

Google 연결은 캘린더 목록·속성 읽기와 이벤트 접근 권한을 요청합니다. 연결 후 설정 화면에서 사용할 캘린더를 직접 선택합니다. 아무 캘린더도 선택하지 않으면 일정은 가져오지 않습니다.

## Apple 및 iCloud

iOS에서는 설정의 **Apple Calendar** 연결을 권장합니다. 기기에 등록된 계정과 캘린더를 EventKit으로 사용합니다. 연결 해제는 앱의 접근을 중단하며, OS의 캘린더 권한 자체를 철회하려면 기기 설정을 이용합니다.

Android의 iCloud 직접 연결에는 Apple 계정에서 발급한 **앱 전용 암호**가 필요합니다. 앱 연결 화면에서 입력하며, 일반 Apple 로그인 암호를 사용하지 않습니다. HTTPS 연결만 허용하고 인증 정보를 임의 호스트나 리디렉션 대상으로 전달하지 않습니다. 보안 저장소에 보관한 앱 전용 암호는 연결 해제 시 제거합니다. Apple 계정에서도 암호를 취소할 수 있습니다.

CalDAV 어댑터는 아직 실제 계정으로 확인하지 않았습니다. iCloud 서버별 인증·주소 응답 및 사용자 지정 이벤트 속성 보존 여부를 검증하기 전에는 지원 완료로 간주하지 않습니다.

## 동기화·개인정보 범위

- 기본 상태에서는 Todo 내용이 앱 서버로 전송되지 않습니다. 별도 앱 서버도 없습니다.
- 선택한 캘린더에 저장하는 할 일만 해당 공급자로 전송합니다. 두 공급자를 자동으로 서로 복제하지 않습니다.
- 외부 캘린더의 이름·색상 및 Google 라벨은 가져옵니다. 아이콘·체크리스트는 앱의 기기 내 정보이며 외부 앱과 동일하게 표현되지 않습니다.
- 기기 데이터와 토큰이 자동 클라우드 백업에 포함되지 않도록 설정합니다. 실제 OS별 백업·전송 동작 검증은 남아 있습니다.
- 계정 연결 후 동기화는 연결 선택, 앱 재개, 수동 새로고침, 앱 소유 일정 변경 때 실행합니다. 백그라운드 실시간 동기화는 아직 없습니다.
- 현재 조회 범위는 이번 달 기준 과거 1년부터 미래 1년입니다.
- Android 알림은 OS가 허용하는 비정확 예약을 사용합니다. 지정한 분에 반드시 실행된다고 보장하지 않습니다.
- 알림은 향후 60일 중 가장 가까운 48개를 예약하고 앱 재개·변경 시 갱신합니다. 장기간 앱을 열지 않으면 갱신이 필요합니다.
- 잠금화면 위젯은 자유로운 잠금 상태 키보드 입력이 아니라 잠금 해제 후 빠른 등록 화면을 여는 방식입니다. Android의 잠금화면 위젯 지원은 OS·제조사에 따라 다릅니다.

## 남은 구현·검증

1. iOS 시뮬레이터 빌드, 실제 기기에서 권한·위젯·알림·백업 확인.
2. Google 실제 계정과 iCloud CalDAV 시제품 검증, 취소·권한 철회·충돌·네트워크 중단 테스트.
3. 반복 일정의 캘린더 전송: 공휴일 예외, 특정 발생일 완료, 원래 반복과 표시 날짜의 양방향 대응. 현재 반복은 로컬만 지원하며 연결된 캘린더로 전송하지 않습니다.
4. 연도별 공휴일 갱신과 사용자 휴일 입력. 알 수 없는 연도의 휴일 이동은 추측해서 확정하지 않습니다.
5. 사용자 지정 카테고리의 외부 캘린더 생성/변경 반영, 전체 앱 메타데이터의 기기 간 동기화.
6. 알림의 완료/다시 알림 액션, 자연어 날짜 입력, 사용자 선택형 ‘오늘 할 일’, 안전한 내보내기·가져오기.

## 코드 위치

- `lib/domain/`: Todo·카테고리 모델과 반복 계산.
- `lib/data/`: SQLite 저장.
- `lib/app_controller.dart`: 저장, 발생일별 완료, 연결·선택·동기화와 충돌 해결.
- `lib/services/`: Google, EventKit, CalDAV, 알림.
- `lib/ui/`: 화면과 등록/수정 폼.
- `native/`: 플랫폼 브리지와 위젯의 원본.
- `tool/`: 플랫폼 생성·통합, iOS 위젯 타깃 등록, 설정 테스트.
- `test/`: 반복 7개, 영구 저장 1개, iCalendar 2개, 컨트롤러 5개, 화면 1개 테스트.
