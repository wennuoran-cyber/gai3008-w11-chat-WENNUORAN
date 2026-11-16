import 'package:flutter/material.dart';

void main() => runApp(const ChatLabApp());

class ChatLabApp extends StatelessWidget {
  const ChatLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat — 실습 1 & 4',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FE4)),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

// 채팅 메시지 모델
class ChatMessage {
  const ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();

  final List<ChatMessage> _messages = [
    const ChatMessage(text: 'Hello!', isUser: true),
    const ChatMessage(text: 'Hi! How can I help?', isUser: false),
  ];

  String? _errorMessage;
  String? _failedMessage;

  bool _isLoading = false;
  int _retryCount = 0;
  int _requestId = 0;

  // TODO 3: 사용자 메시지 전송
  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    // 이전 요청의 응답을 무효화한다.
    final requestId = ++_requestId;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));

      _errorMessage = null;
      _failedMessage = null;
      _retryCount = 0;
      _isLoading = true;
    });

    _controller.clear();

    _simulateResponse(text, requestId);
  }

  // 실습 4: 401, 429, 500, timeout 오류 시뮬레이션
  Future<void> _simulateResponse(String text, int requestId) async {
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted || requestId != _requestId) return;

    final lowerText = text.toLowerCase();

    String? error;

    if (lowerText.contains('401')) {
      error = '401: 인증에 실패했습니다.';
    } else if (lowerText.contains('429')) {
      error = '429: 요청이 너무 많습니다.';
    } else if (lowerText.contains('500')) {
      error = '500: 서버 오류가 발생했습니다.';
    } else if (lowerText.contains('timeout')) {
      error = 'Timeout: 요청 시간이 초과되었습니다.';
    }

    setState(() {
      _isLoading = false;
      _errorMessage = error;

      if (error != null) {
        _failedMessage = text;
      } else {
        _failedMessage = null;

        _messages.add(ChatMessage(text: 'AI response: $text', isUser: false));
      }
    });
  }

  // 실습 4: 마지막 실패 메시지만 다시 시도
  Future<void> _retry() async {
    if (_isLoading || _failedMessage == null) return;

    final text = _failedMessage!;
    final isRateLimit = _errorMessage?.startsWith('429') ?? false;

    final requestId = ++_requestId;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _retryCount++;
    });

    // 429 오류: 1초 -> 2초 -> 4초 -> 8초
    if (isRateLimit) {
      final exponent = (_retryCount - 1).clamp(0, 4);
      final seconds = 1 << exponent;

      await Future.delayed(Duration(seconds: seconds));
    }

    if (!mounted || requestId != _requestId) return;

    await _simulateResponse(text, requestId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('AI Chat — 실습 1 & 4')),
      body: SafeArea(
        child: Column(
          children: [
            // TODO 2: 채팅 메시지 목록
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];

                      return _Bubble(message: message);
                    },
                  ),

                  // TODO 4: 빈 채팅 화면
                  if (_messages.isEmpty)
                    const Center(
                      child: Text(
                        '무엇이든 물어보세요',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),

            // 실습 4: 로딩 및 오류 상태 전환
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isLoading
                  ? Padding(
                      key: const ValueKey('loading'),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('응답을 기다리는 중...'),
                        ],
                      ),
                    )
                  : _errorMessage != null
                  ? Padding(
                      key: const ValueKey('error'),
                      padding: const EdgeInsets.all(12),
                      child: Card(
                        color: colors.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: colors.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _retry,
                                icon: const Icon(Icons.refresh),
                                label: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),

            // TODO 3: 메시지 입력창과 전송 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '메시지를 입력하세요...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
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

// TODO 2: 사용자 오른쪽, AI 왼쪽 말풍선
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: message.isUser
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(message.text),
      ),
    );
  }
}
