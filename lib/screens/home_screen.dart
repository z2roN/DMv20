import 'package:flutter/material.dart';

import '../store.dart';
import 'chat_screen.dart';
import 'member_list_screen.dart';

/// 넓은 화면(Windows, 태블릿): 왼쪽 친구 목록 + 오른쪽 대화
/// 좁은 화면(휴대폰): 목록을 누르면 대화 화면이 전체 화면으로 열림
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.onLock});

  final ChatStore store;
  final Future<void> Function() onLock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selected;

  static const double _wide = 760;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= _wide;
        if (!wide) {
          return MemberListScreen(
            store: widget.store,
            onLock: widget.onLock,
            onSelect: (id) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(store: widget.store, peerId: id)),
            ),
          );
        }
        final cs = Theme.of(context).colorScheme;
        // 선택한 친구가 삭제되었으면 선택 해제
        return ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final sel = widget.store.members.containsKey(_selected) ? _selected : null;
            return Row(
              children: [
                SizedBox(
                  width: 340,
                  child: MemberListScreen(
                    store: widget.store,
                    onLock: widget.onLock,
                    selectedId: sel,
                    onSelect: (id) => setState(() => _selected = id),
                  ),
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(
                  child: sel == null
                      ? Scaffold(
                          body: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.forum_outlined,
                                    size: 56, color: cs.primary.withOpacity(0.5)),
                                const SizedBox(height: 12),
                                Text(
                                  '왼쪽에서 친구를 선택하세요',
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ChatScreen(
                          key: ValueKey(sel),
                          store: widget.store,
                          peerId: sel,
                          showBack: false,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
