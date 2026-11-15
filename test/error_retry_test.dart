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

  /// 상태 말풍선 전환(AnimatedSwitcher)이 끝나고 이전 말풍선이 빠질 때까지 기다린다.
  /// 애니메이션은 시작 다음 프레임부터 시간이 흐르므로 프레임을 한 번 더 그린다.
  Future<void> settleSwitch(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(kStatusSwitchDuration);
    await tester.pump(kStatusSwitchDuration);
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
        await tester.pump(kStatusSwitchDuration);
        expect(find.text(title), findsOneWidget);
      });
    }

    testWidgets('응답이 오지 않으면 timeout 오류', (tester) async {
      await pumpApp(tester, FakeMode.timeout);
      await send(tester, '안녕');

      await tester.pump(kResponseTimeout - const Duration(milliseconds: 1));
      expect(find.text('응답 시간 초과'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(kStatusSwitchDuration);
      expect(find.text('응답 시간 초과'), findsOneWidget);
    });
  });

  group('할 일 2·3 — 다시 시도는 마지막 메시지를 다시', () {
    testWidgets('다시 시도하면 같은 문장을 다시 보내고, 사용자 말풍선은 늘지 않는다', (tester) async {
      final api = await pumpApp(tester, FakeMode.server);
      await send(tester, '재시도할 질문');
      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);
      expect(find.text('서버 오류 (500)'), findsOneWidget);
      expect(api.callCount, 1);

      // 서버가 회복된 뒤 다시 시도
      api.mode = FakeMode.success;
      await tester.tap(find.text('다시 시도'));
      await settleSwitch(tester);

      expect(api.callCount, 2);
      expect(api.lastText, '재시도할 질문');
      expect(find.text('서버 오류 (500)'), findsNothing);
      expect(find.text('재시도할 질문'), findsOneWidget);

      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);
      expect(find.text('아직 미구현되었습니다.'), findsOneWidget);
      expect(find.text('재시도할 질문'), findsOneWidget);
    });

    testWidgets('다시 시도도 실패하면 오류가 다시 남는다', (tester) async {
      final api = await pumpApp(tester, FakeMode.unauthorized);
      await send(tester, '질문');
      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);

      await tester.tap(find.text('다시 시도'));
      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);
      expect(api.callCount, 2);
      expect(find.text('인증 오류 (401)'), findsOneWidget);
    });
  });

  testWidgets('할 일 4 — 타이핑 점과 오류 말풍선이 AnimatedSwitcher로 전환된다', (tester) async {
    await pumpApp(tester, FakeMode.server);
    await send(tester, '질문');

    final switcher = find.byWidgetPredicate(
      (w) => w is AnimatedSwitcher && w.duration == kStatusSwitchDuration,
    );
    expect(switcher, findsOneWidget);

    Finder children() =>
        find.descendant(of: switcher, matching: find.byType(FadeTransition));

    // 전송 중에는 타이핑 점 하나
    await tester.pump(kStatusSwitchDuration);
    expect(children(), findsOneWidget);

    // 오류가 오면 잠깐 동안 이전(타이핑 점)과 새(오류) 말풍선이 함께 있다가
    await tester.pump(latency);
    await tester.pump(kStatusSwitchDuration ~/ 2);
    expect(find.text('서버 오류 (500)'), findsOneWidget);
    expect(children(), findsNWidgets(2));

    // 전환이 끝나면 오류 말풍선만 남는다.
    await tester.pump(kStatusSwitchDuration);
    expect(children(), findsOneWidget);
    expect(find.text('서버 오류 (500)'), findsOneWidget);
  });

  group('할 일 5 — 429면 지수 백오프 1s → 2s', () {
    testWidgets('1초, 2초 뒤에 자동으로 다시 보내고, 그래도 막히면 오류', (tester) async {
      final api = await pumpApp(tester, FakeMode.rateLimited);
      await send(tester, '질문');

      // 1번째 요청이 429 → 1초 대기
      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);
      expect(api.callCount, 1);
      expect(find.text('요청이 많아 1초 뒤 다시 보내요 (1/2)'), findsOneWidget);

      // 1초가 지나기 전에는 다시 보내지 않는다.
      await tester.pump(
        const Duration(seconds: 1) -
            kStatusSwitchDuration -
            const Duration(milliseconds: 1),
      );
      expect(api.callCount, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.callCount, 2);

      // 2번째 요청도 429 → 2초 대기
      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);
      expect(find.text('요청이 많아 2초 뒤 다시 보내요 (2/2)'), findsOneWidget);
      await tester.pump(
        const Duration(seconds: 2) -
            kStatusSwitchDuration -
            const Duration(milliseconds: 1),
      );
      expect(api.callCount, 2);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.callCount, 3);

      // 3번째도 429 → 더 기다리지 않고 오류 말풍선
      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);
      expect(find.text('요청이 너무 많아요 (429)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(api.callCount, 3);
      expect(api.lastText, '질문');
    });

    testWidgets('한 번 막히고 다음에 통과하면 오류 없이 응답이 온다', (tester) async {
      final api = await pumpApp(tester, FakeMode.rateLimitedOnce);
      await send(tester, '질문');

      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);
      expect(find.text('요청이 많아 1초 뒤 다시 보내요 (1/2)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(latency);
      await settleSwitch(tester);
      expect(api.callCount, 2);
      expect(find.text('잠시 기다렸다가 다시 보내서 받은 응답입니다.'), findsOneWidget);
      expect(find.textContaining('요청이 너무 많아요'), findsNothing);
      expect(find.textContaining('다시 보내요'), findsNothing);
    });

    testWidgets('429가 아닌 오류는 자동으로 다시 보내지 않는다', (tester) async {
      final api = await pumpApp(tester, FakeMode.server);
      await send(tester, '질문');
      await tester.pump(latency);
      await tester.pump(const Duration(seconds: 10));
      expect(api.callCount, 1);
      expect(find.text('서버 오류 (500)'), findsOneWidget);
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
      await tester.pump(kStatusSwitchDuration);
      expect(find.text('서버 오류 (500)'), findsOneWidget);

      // 오류 상태에서 새로 입력해 보낼 수 있다.
      api.mode = FakeMode.success;
      await send(tester, '두 번째 질문');
      await settleSwitch(tester);
      expect(find.text('두 번째 질문'), findsOneWidget);
      // 새 요청을 보내면 이전 오류는 정리된다.
      expect(find.text('서버 오류 (500)'), findsNothing);

      await tester.pump(latency);
      await tester.pump(kStatusSwitchDuration);
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
