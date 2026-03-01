import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../shared/shared.dart';
import '../../../services/ai_summary_service.dart';
import '../../../services/consultant_action_executor.dart';
import '../../../models/consultant_action.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({
    super.key,
    this.childId,
    this.childName,
    this.sessionId,
  });

  final String? childId;
  final String? childName;
  final String? sessionId;

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AISummaryService _summaryService = AISummaryService();
  final ConsultantActionExecutor _actionExecutor = ConsultantActionExecutor();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _chatScrollController = ScrollController();
  String? _activeSessionId;
  String? _lastRenderedSessionId;
  int _lastRenderedItemCount = -1;
  String _lastRenderedTail = '';
  bool _isCreatingSession = false;
  bool _isSendingMessage = false;

  @override
  void initState() {
    super.initState();
    _activeSessionId = widget.sessionId;
    if (_activeSessionId == null) {
      _createNewSession();
    }
  }

  @override
  void dispose() {
    _chatScrollController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _scrollToLatestMessage({
    bool animated = true,
    int retries = 3,
  }) {
    if (!_chatScrollController.hasClients) {
      if (retries <= 0 || !mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scrollToLatestMessage(animated: animated, retries: retries - 1);
      });
      return;
    }

    final target = _chatScrollController.position.maxScrollExtent;
    if (animated) {
      _chatScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _chatScrollController.jumpTo(target);
    }

    if (retries <= 0 || !mounted) {
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) {
        return;
      }
      _scrollToLatestMessage(animated: false, retries: retries - 1);
    });
  }

  void _scheduleAutoScrollIfNeeded({
    required String sessionId,
    required int itemCount,
    required String tail,
  }) {
    final sessionChanged = _lastRenderedSessionId != sessionId;
    final contentChanged =
        _lastRenderedItemCount != itemCount || _lastRenderedTail != tail;

    if (!sessionChanged && !contentChanged) {
      return;
    }

    _lastRenderedSessionId = sessionId;
    _lastRenderedItemCount = itemCount;
    _lastRenderedTail = tail;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scrollToLatestMessage(
        animated: !sessionChanged,
        retries: sessionChanged ? 5 : 3,
      );
    });
  }

  Future<void> _createNewSession() async {
    if (_isCreatingSession) {
      return;
    }

    setState(() {
      _isCreatingSession = true;
    });

    try {
      final docRef = await _summaryService.startConsultantSession(
        childId: widget.childId,
        childName: widget.childName,
      );

      if (mounted) {
        setState(() {
          _activeSessionId = docRef.id;
        });
      }
    } catch (e, stack) {
      debugPrint('ChatbotPage: Failed to start session: $e');
      debugPrint('Stack: $stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to start: $e'),
          backgroundColor: AppColors.error(context),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingSession = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _auth.currentUser?.uid;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI Consultant')),
        body: Center(
          child: Text(
            'Please sign in to continue.',
            style: AppTextStyles.bodyMedium(context),
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('AI Consultant'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton.icon(
              onPressed: () => _showRecentChats(context, userId),
              icon: const Icon(Icons.history),
              label: const Text('History'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildContextBar(context),
            Expanded(
              child: _activeSessionId == null
                  ? _buildEmptyState(context)
                  : _buildSessionConversation(
                      context,
                      userId,
                      _activeSessionId!,
                    ),
            ),
            _buildComposer(context, userId),
          ],
        ),
      ),
    );
  }

  Widget _buildContextBar(BuildContext context) {
    final title = (widget.childName != null && widget.childName!.trim().isNotEmpty)
      ? widget.childName!
      : 'General consultation';

    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingMd,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Context: $title',
              style: AppTextStyles.labelLarge(context),
            ),
          ),
          AppSpacing.gapSm,
          TextButton.icon(
            onPressed: _isCreatingSession ? null : _createNewSession,
            icon: const Icon(Icons.add),
            label: const Text('Start New Session'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final message = _isCreatingSession
        ? 'Starting a new AI session...'
        : 'Start a session from a child card to see insights here.';

    return Center(
      child: Text(
        message,
        style: AppTextStyles.bodyMedium(context),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSessionConversation(
    BuildContext context,
    String userId,
    String sessionId,
  ) {
    final docStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('chat')
        .doc(sessionId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView(
            padding: AppSpacing.paddingMd,
            children: const [
              _ThinkingBubble(),
            ],
          );
        }

        if (snapshot.hasError) {
          return ListView(
            padding: AppSpacing.paddingMd,
            children: [
              Text(
                'Unable to load this session.',
                style: AppTextStyles.bodyMedium(context),
              ),
            ],
          );
        }

        final data = snapshot.data?.data();
        if (data == null) {
          return ListView(
            padding: AppSpacing.paddingMd,
            children: [
              Text(
                'This session is unavailable.',
                style: AppTextStyles.bodyMedium(context),
              ),
            ],
          );
        }

        final status = data['status'];
        final state = status is Map<String, dynamic>
            ? status['state'] as String?
            : status as String?;
        var response = (data['response'] as String?)?.trim() ?? '';
        final messages = _parseMessages(data);
        final pending = state == 'PENDING' || state == 'PROCESSING';
        final hasUserMessage =
          messages.any((message) => message.role == _ChatRole.user);

        // Parse and execute actions from response
        if (response.isNotEmpty) {
          final action = ConsultantAction.tryParse(response, widget.childId ?? '');
          if (action != null && hasUserMessage && !_isSendingMessage) {
            // Execute action in background
            _executeConsultantAction(action, response);
          }
          // Clean response text (remove action tags)
          response = ConsultantAction.cleanResponse(response);
        }

        final displayMessages = List<_ChatMessage>.from(messages);
        if (response.isNotEmpty) {
          final lastMessage = displayMessages.isNotEmpty
              ? displayMessages.last
              : null;
          if (lastMessage == null || lastMessage.role != _ChatRole.assistant) {
            displayMessages.add(
              _ChatMessage(role: _ChatRole.assistant, content: response),
            );
          } else if (lastMessage.content != response) {
            displayMessages.add(
              _ChatMessage(role: _ChatRole.assistant, content: response),
            );
          }
        }

        if (displayMessages.isEmpty && response.isEmpty && !pending) {
          return ListView(
            padding: AppSpacing.paddingMd,
            children: [
              Text(
                'Ask a question to start the conversation.',
                style: AppTextStyles.bodyMedium(context),
                textAlign: TextAlign.center,
              ),
            ],
          );
        }

        final itemCount = displayMessages.length + (pending ? 1 : 0);
        final tail = displayMessages.isEmpty
            ? (pending ? 'pending' : '')
            : '${displayMessages.last.role.name}:${displayMessages.last.content}:${pending ? 'pending' : ''}';
        _scheduleAutoScrollIfNeeded(
          sessionId: sessionId,
          itemCount: itemCount,
          tail: tail,
        );

        return ListView.separated(
          controller: _chatScrollController,
          padding: AppSpacing.paddingMd,
          itemCount: displayMessages.length + (pending ? 1 : 0),
          separatorBuilder: (_, __) => AppSpacing.gapSm,
          itemBuilder: (context, index) {
            if (pending && index == displayMessages.length) {
              return const _ThinkingBubble();
            }

            final message = displayMessages[index];
            return _ChatMessageBubble(message: message);
          },
        );
      },
    );
  }

  Widget _buildComposer(BuildContext context, String userId) {
    final canSend = !_isSendingMessage;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: AppSpacing.md,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSendMessage(userId),
                style: AppTextStyles.bodyMedium(context),
                decoration: InputDecoration(
                  hintText: 'Ask a follow-up question',
                  hintStyle: AppTextStyles.bodySmall(context),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.lg),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: AppSpacing.paddingSm,
                ),
              ),
            ),
            AppSpacing.gapSm,
            FilledButton(
              onPressed: canSend ? () => _handleSendMessage(userId) : null,
              child: _isSendingMessage
                  ? SizedBox(
                      width: AppSpacing.lg,
                      height: AppSpacing.lg,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  List<_ChatMessage> _parseMessages(Map<String, dynamic> data) {
    final rawMessages = data['messages'];
    if (rawMessages is! List) {
      return const [];
    }

    return rawMessages
        .whereType<Map<String, dynamic>>()
        .map((entry) {
          final role = (entry['role'] as String?)?.trim().toLowerCase();
          final content = (entry['content'] as String?)?.trim();
          if (role == null || content == null || content.isEmpty) {
            return null;
          }
          return _ChatMessage(
            role: role == 'assistant' ? _ChatRole.assistant : _ChatRole.user,
            content: content,
          );
        })
        .whereType<_ChatMessage>()
        .toList(growable: false);
  }

  Future<void> _handleSendMessage(String userId) async {
    if (_isSendingMessage) {
      return;
    }

    if (_activeSessionId == null) {
      await _createNewSession();
      if (_activeSessionId == null) {
        return;
      }
    }

    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _isSendingMessage = true;
    });
    _scrollToLatestMessage(retries: 5);

    try {
      await _summaryService.sendConsultantMessage(
        sessionId: _activeSessionId!,
        message: text,
      );

      if (!mounted) {
        return;
      }

      _messageController.clear();
      _messageFocusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scrollToLatestMessage(retries: 5);
      });
    } catch (e, stack) {
      debugPrint('ChatbotPage: Failed to send message: $e');
      debugPrint('Stack: $stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to send: $e'),
          backgroundColor: AppColors.error(context),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  Future<void> _executeConsultantAction(ConsultantAction action, String fullResponse) async {
    try {
      final result = await _actionExecutor.executeAction(action);
      
      if (!mounted) return;

      // Show success notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $result'),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 3),
        ),
      );

      debugPrint('Action executed: ${action.type} - $result');
    } catch (e) {
      if (!mounted) return;

      // Show error notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action failed: $e'),
          backgroundColor: AppColors.error(context),
          duration: const Duration(seconds: 4),
        ),
      );

      debugPrint('Action failed: ${action.type} - $e');
    }
  }

  Future<void> _showRecentChats(BuildContext context, String userId) async {
    final sheet = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _RecentChatsSheet(userId: userId),
    );

    if (sheet == null || !mounted) {
      return;
    }

    setState(() {
      _activeSessionId = sheet;
    });
  }
}

class _AIResponseCard extends StatelessWidget {
  const _AIResponseCard({required this.response});

  final String response;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: AppSpacing.paddingMd,
      child: Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppSpacing.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: colorScheme.primary,
                  size: AppSpacing.lg,
                ),
                AppSpacing.gapSm,
                Text(
                  'AI Consultant',
                  style: AppTextStyles.titleMedium(context).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            AppSpacing.gapSm,
            MarkdownBody(
              data: response,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: AppTextStyles.bodyMedium(context),
                listBullet: AppTextStyles.bodyMedium(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({required this.role, required this.content});

  final _ChatRole role;
  final String content;
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.role == _ChatRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            color: isUser
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppSpacing.lg),
          ),
          child: isUser
              ? Text(
                  message.content,
                  style: AppTextStyles.bodyMedium(context).copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                )
              : MarkdownBody(
                  data: message.content,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
                    p: AppTextStyles.bodyMedium(context),
                    listBullet: AppTextStyles.bodyMedium(context),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: AppSpacing.paddingSm,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppSpacing.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: AppSpacing.lg,
              height: AppSpacing.lg,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            AppSpacing.gapSm,
            Text(
              'Thinking...',
              style: AppTextStyles.bodyMedium(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Thinking...',
            style: AppTextStyles.bodyMedium(context),
          ),
          AppSpacing.gapSm,
          SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              color: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentChatsSheet extends StatelessWidget {
  const _RecentChatsSheet({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('chat')
        .orderBy('createTime', descending: true)
        .limit(10)
        .snapshots();

    return SafeArea(
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent Chats',
                style: AppTextStyles.titleMedium(context).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              AppSpacing.gapSm,
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Text(
                        'No recent sessions yet.',
                        style: AppTextStyles.bodyMedium(context),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final childName =
                            (data['childName'] as String?)?.trim().isNotEmpty == true
                                ? data['childName'] as String
                                : 'General';
                        final timestamp = data['createTime'] as Timestamp?;
                        final timeLabel = timestamp == null
                            ? 'Just now'
                            : DateFormat.MMMd().add_jm().format(timestamp.toDate());

                        return ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(childName, style: AppTextStyles.bodyMedium(context)),
                          subtitle: Text(timeLabel, style: AppTextStyles.bodySmall(context)),
                          onTap: () => Navigator.of(context).pop(doc.id),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
