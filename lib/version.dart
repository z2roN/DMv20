/// 앱 버전 (pubspec.yaml 의 version 과 같은 값으로 유지)
const String kAppVersion = '2.0.0';

class ChangeEntry {
  const ChangeEntry(this.version, this.date, this.notes);

  final String version;
  final String date;
  final List<String> notes;
}

/// 업데이트 내역 (최신이 위)
const List<ChangeEntry> kChangelog = [
  ChangeEntry('2.0.0', '2026-11-05', [
    '친구 코드 방식으로 변경: 내 코드를 서로 주고받아 수락한 사람만 목록에 보임 (코드를 공유하지 않은 사람은 보이지 않음)',
    '[친구 추가] 버튼 추가: 친구의 코드를 넣어 요청, 받은 요청은 수락/거절',
    '화면 분할: 넓은 화면(Windows)은 왼쪽 친구 목록 + 오른쪽 대화, 휴대폰은 기존처럼 전체 화면',
    '화면 상단 이름을 z2roN-DM 으로 표시',
    '주의: 1.x 와 호환되지 않음 (이전 모임 코드 방식의 목록·내 코드는 새로 시작)',
  ]),
  ChangeEntry('1.1.0', '2026-11-05', [
    '프로그램 이름을 z2roN_DM 으로 변경',
    '상대 이름(별명) 바꾸기: 내가 정한 이름이 "내가정한이름(상대가정한이름)" 으로 보임 (상대에게는 변화 없음)',
    '사용 설명서(PDF) 추가',
  ]),
  ChangeEntry('1.0.1', '2026-11-05', [
    '빌드 오류 수정: 공용 화면 부품의 누락된 참조(formatSize)와 진행률 타입 오류',
  ]),
  ChangeEntry('1.0.0', '2026-11-05', [
    '첫 버전: 지인 전용(초대 코드) 1:1 다이렉트 채팅, 접속자 목록(나 포함 최대 15명)',
    '파일 전송, 이미지 전송(채팅 안 미리보기, 눌러서 크게 보기)',
    '앱 암호 + 암호화 저장 + 자동 로그인(암호 기억하기)',
  ]),
];

/// 친구(요청 중 포함)로 등록 가능한 최대 인원 (나 포함)
const int kMaxMembers = 15;

/// 파일 1개 최대 크기
const int kMaxFileBytes = 300 * 1024 * 1024;
