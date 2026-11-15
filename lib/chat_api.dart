import 'dart:async';

/// AI 응답을 받아 오는 창구. 실습 2에서 실제 API 구현으로 바꿔 끼운다.
abstract class ChatApi {
  Future<String> send(String text);
}

/// 서버가 돌려준 HTTP 상태 코드 오류(실제 API에서 http 응답을 감싸 던질 형태).
class HttpStatusException implements Exception {
  const HttpStatusException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'HttpStatusException($statusCode)';
}

// ───────────────────────────────────────────────────────────────
// 실습 ④ 할 일 1 — 401·429·500·timeout을 한 상태로
//    어디서 어떤 예외가 나든 ChatError 하나로 바꿔서 화면은 이것만 본다.
// ───────────────────────────────────────────────────────────────

enum ChatErrorKind { unauthorized, rateLimited, server, timeout, unknown }

class ChatError {
  const ChatError(this.kind, {this.statusCode});

  /// 예외를 화면에서 다룰 오류 하나로 바꾼다.
  factory ChatError.from(Object error) {
    return switch (error) {
      ChatError() => error,
      TimeoutException() => const ChatError(ChatErrorKind.timeout),
      HttpStatusException(statusCode: 401) => const ChatError(
        ChatErrorKind.unauthorized,
        statusCode: 401,
      ),
      HttpStatusException(statusCode: 429) => const ChatError(
        ChatErrorKind.rateLimited,
        statusCode: 429,
      ),
      HttpStatusException(:final statusCode) when statusCode >= 500 =>
        ChatError(ChatErrorKind.server, statusCode: statusCode),
      HttpStatusException(:final statusCode) => ChatError(
        ChatErrorKind.unknown,
        statusCode: statusCode,
      ),
      _ => const ChatError(ChatErrorKind.unknown),
    };
  }

  final ChatErrorKind kind;
  final int? statusCode;

  /// 오류 말풍선 제목.
  String get title {
    final code = statusCode == null ? '' : ' ($statusCode)';
    return switch (kind) {
      ChatErrorKind.unauthorized => '인증 오류$code',
      ChatErrorKind.rateLimited => '요청이 너무 많아요$code',
      ChatErrorKind.server => '서버 오류$code',
      ChatErrorKind.timeout => '응답 시간 초과',
      ChatErrorKind.unknown => '알 수 없는 오류$code',
    };
  }

  /// 오류 말풍선 설명.
  String get description => switch (kind) {
    ChatErrorKind.unauthorized => 'API 키가 없거나 만료됐어요. 키를 확인한 뒤 다시 시도해 주세요.',
    ChatErrorKind.rateLimited => '잠시 기다렸다가 다시 보냈지만 계속 막혔어요. 조금 뒤에 다시 시도해 주세요.',
    ChatErrorKind.server => '서버에 문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
    ChatErrorKind.timeout => '제시간에 응답이 오지 않았어요. 네트워크를 확인하고 다시 시도해 주세요.',
    ChatErrorKind.unknown => '문제가 생겼어요. 다시 시도해 주세요.',
  };

  @override
  bool operator ==(Object other) =>
      other is ChatError &&
      other.kind == kind &&
      other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash(kind, statusCode);
}

/// 화면이 보는 요청 상태. 한 번에 하나만 참이 되도록 한 타입으로 묶는다.
sealed class ChatStatus {
  const ChatStatus();
}

/// 아무 요청도 없음.
class ChatIdle extends ChatStatus {
  const ChatIdle();
}

/// 응답을 기다리는 중.
class ChatSending extends ChatStatus {
  const ChatSending();
}

/// 요청이 실패해 오류를 보여 주는 중. 다음 전송이나 재시도 전까지 남는다.
class ChatFailed extends ChatStatus {
  const ChatFailed(this.error);

  final ChatError error;
}

// ───────────────────────────────────────────────────────────────
// 가짜 API — 서버 없이 오류 상황을 골라 재현한다.
// ───────────────────────────────────────────────────────────────

enum FakeMode {
  success('정상 응답'),
  unauthorized('401 인증 오류'),
  rateLimited('429 요청 과다'),
  server('500 서버 오류'),
  timeout('timeout 응답 없음');

  const FakeMode(this.label);

  final String label;
}

class FakeChatApi implements ChatApi {
  FakeChatApi({
    this.mode = FakeMode.success,
    this.latency = const Duration(milliseconds: 1200),
  });

  /// 다음 요청에 적용할 상황. 화면의 메뉴에서 바꾼다.
  FakeMode mode;

  /// 응답(또는 오류)이 오기까지 걸리는 시간.
  final Duration latency;

  /// 지금까지 받은 요청 수(테스트에서 재시도 횟수 확인용).
  int callCount = 0;

  @override
  Future<String> send(String text) async {
    callCount++;

    // 응답이 끝내 오지 않는 상황. 호출하는 쪽의 timeout이 끊어 준다.
    if (mode == FakeMode.timeout) return Completer<String>().future;

    await Future<void>.delayed(latency);
    return switch (mode) {
      FakeMode.success => '아직 미구현되었습니다.',
      FakeMode.unauthorized => throw const HttpStatusException(401),
      FakeMode.rateLimited => throw const HttpStatusException(429),
      FakeMode.server => throw const HttpStatusException(500),
      FakeMode.timeout => throw StateError('위에서 처리됨'),
    };
  }
}
