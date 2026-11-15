import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lab1_chat_ui/chat_api.dart';
import 'package:lab1_chat_ui/main.dart';

/// 실습 ④ — 오류와 재시도
void main() {
  const latency = Duration(milliseconds: 1200);

  Future<FakeChatApi> pumpApp(WidgetTester tester, FakeMode mode) async {
    final api = FakeChatApi(mode: mode, latency: latency);
    await tester.pumpWidget(ChatLabApp(api: api));
    return api;
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
  }

  group('할 일 1 — 401·429·500·timeout을 한 상태로', () {
    test('예외가 ChatError 하나로 바뀐다', () {
      expect(
        ChatError.from(const HttpStatusException(401)).kind,
        ChatErrorKind.unauthorized,
      );
      expect(
        ChatError.from(const HttpStatusException(429)).kind,
        ChatErrorKind.rateLimited,
      );
      expect(
        ChatError.from(const HttpStatusException(500)).kind,
        ChatErrorKind.server,
      );
      expect(
        ChatError.from(const HttpStatusException(503)).kind,
        ChatErrorKind.server,
      );
      expect(ChatError.from(TimeoutException('')).kind, ChatErrorKind.timeout);
      expect(
        ChatError.from(const HttpStatusException(404)).kind,
        ChatErrorKind.unknown,
      );
      expect(ChatError.from(Exception('?')).kind, ChatErrorKind.unknown);
    });

    for (final (mode, title) in [
      (FakeMode.unauthorized, '인증 오류 (401)'),
      (FakeMode.server, '서버 오류 (500)'),
    ]) {
      testWidgets('${mode.label} → 오류 말풍선', (tester) async {
        await pumpApp(tester, mode);
        await send(tester, '안녕');

        // 응답 대기 중에는 타이핑 표시
        expect(find.text(title), findsNothing);
        await tester.pump(latency);
        await tester.pump();
        expect(find.text(title), findsOneWidget);
      });
    }

    testWidgets('응답이 오지 않으면 timeout 오류', (tester) async {
      await pumpApp(tester, FakeMode.timeout);
      await send(tester, '안녕');

      await tester.pump(kResponseTimeout - const Duration(milliseconds: 1));
      expect(find.text('응답 시간 초과'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('응답 시간 초과'), findsOneWidget);
    });
  });

  group('완료 기준', () {
    testWidgets('화면에 오류가 남는다', (tester) async {
      await pumpApp(tester, FakeMode.server);
      await send(tester, '안녕');
      await tester.pump(latency);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('서버 오류 (500)'), findsOneWidget);
    });

    testWidgets('오류 뒤에도 입력이 된다', (tester) async {
      final api = await pumpApp(tester, FakeMode.server);
      await send(tester, '첫 질문');
      await tester.pump(latency);
      await tester.pump();
      expect(find.text('서버 오류 (500)'), findsOneWidget);

      // 오류 상태에서 새로 입력해 보낼 수 있다.
      api.mode = FakeMode.success;
      await send(tester, '두 번째 질문');
      expect(find.text('두 번째 질문'), findsOneWidget);
      // 새 요청을 보내면 이전 오류는 정리된다.
      expect(find.text('서버 오류 (500)'), findsNothing);

      await tester.pump(latency);
      await tester.pump();
      expect(find.text('아직 미구현되었습니다.'), findsOneWidget);
    });
  });

  testWidgets('앱바 메뉴로 재현할 오류를 고른다', (tester) async {
    final api = await pumpApp(tester, FakeMode.success);

    await tester.tap(find.byTooltip('오류 재현'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('429 요청 과다').last);
    await tester.pumpAndSettle();

    expect(api.mode, FakeMode.rateLimited);
    // 정상이 아닐 때는 앱바에 지금 재현 중인 오류가 보인다.
    expect(find.text('429 요청 과다'), findsOneWidget);
  });
}
