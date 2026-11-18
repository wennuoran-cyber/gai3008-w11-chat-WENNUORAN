import 'package:flutter/material.dart';

void main() => runApp(const ChatLabApp());

class ChatLabApp extends StatelessWidget {
  const ChatLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat — 실습 1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FE4)),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

/// 대화 한 줄. 서버 없이 화면만 만들기 위한 최소 모델.
class ChatMessage {
  const ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

/// 실습 4 — 오류 상태. status가 null이면 timeout/네트워크 오류.
class ApiError implements Exception {
  const ApiError(this.status);

  final int? status;
}

String errorMessage(ApiError e) => switch (e.status) {
      401 => '키/권한을 확인해 주세요',
      429 => '잠시 후 다시 시도해 주세요',
      500 => '응답을 받지 못했습니다',
      _ => '네트워크를 확인해 주세요',
    };

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<ChatMessage> _messages = [
    const ChatMessage(text: '오늘 뭐 배워?', isUser: true),
    const ChatMessage(text: 'AI 챗봇에 움직이는 응답을 붙입니다.', isUser: false),
    const ChatMessage(text: '타이핑 점은 왜 필요해요?', isUser: true),
    const ChatMessage(text: '응답이 1초를 넘으면 앱이 멈춘 것처럼 보이기 때문입니다.', isUser: false),
  ];

  final _controller = TextEditingController();

  bool _isLoading = false;
  String? _error; // 화면에 남는 오류 문구
  ApiError? _demoFail; // 데모용: 이 요청을 실패시킬 오류

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 데모: 문장에 401/429/500/timeout이 들어 있으면 그 오류로 실패시킨다.
  ApiError? _demoErrorFor(String text) {
    final t = text.toLowerCase();
    if (t.contains('401')) return const ApiError(401);
    if (t.contains('429')) return const ApiError(429);
    if (t.contains('500')) return const ApiError(500);
    if (t.contains('timeout')) return const ApiError(null);
    return null;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _error = null; // 오류가 남아 있어도 새 입력은 그대로 보낼 수 있다
    });
    _controller.clear();
    _demoFail = _demoErrorFor(text);
    await _requestReply(text);
  }

  Future<void> _requestReply(String prompt) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final reply = await _fakeApi(prompt);
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(text: reply, isUser: false)));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String> _fakeApi(String prompt) async {
    await Future.delayed(const Duration(milliseconds: 800));
    final fail = _demoFail;
    if (fail != null) throw fail;
    return '"$prompt"에 대한 가짜 응답입니다.';
  }

  /// 재시도 = 마지막 사용자 메시지를 다시 보낸다.
  void _retry() {
    if (_isLoading) return;
    final i = _messages.lastIndexWhere((m) => m.isUser);
    if (i < 0) return;
    _demoFail = null; // 데모: 다시 시도하면 성공
    _requestReply(_messages[i].text);
  }

  /// 목록 맨 아래 칸: 로딩 ↔ 오류 ↔ 없음을 AnimatedSwitcher로 전환.
  Widget _statusSlot() {
    final Widget child;
    if (_isLoading) {
      child = const _TypingBubble(key: ValueKey('loading'));
    } else if (_error != null) {
      child = _ErrorBubble(
        key: ValueKey('error-$_error'),
        message: _error!,
        onRetry: _retry,
      );
    } else {
      child = const SizedBox.shrink(key: ValueKey('none'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(sizeFactor: anim, child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showEmpty = _messages.isEmpty && !_isLoading && _error == null;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('AI Chat — 실습 1'),
        actions: [
          IconButton(
            tooltip: '대화 지우기',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() {
              _messages.clear();
              _error = null;
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    reverse: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return _statusSlot();
                      final message = _messages[_messages.length - index];
                      return _Bubble(message: message);
                    },
                  ),
                  if (showEmpty)
                    Center(
                      child: Text(
                        '무엇이든 물어보세요',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '메시지 입력 (401·429·500·timeout 테스트)',
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isLoading ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: isUser ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: isUser ? cs.onPrimaryContainer : cs.onSurface),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({super.key, this.note});

  final String? note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            if (note != null) ...[
              const SizedBox(width: 10),
              Flexible(child: Text(note!, style: const TextStyle(fontSize: 13))),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 18, color: cs.onErrorContainer),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(message,
                      style: TextStyle(color: cs.onErrorContainer)),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}