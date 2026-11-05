import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../net/peer_link.dart';
import '../store.dart';
import '../version.dart';
import '../widgets.dart';
import 'add_friend_screen.dart';
import 'setup_screen.dart';

/// 상대 이름(별명) 바꾸기 창. 별명을 비우면 상대가 정한 이름으로 돌아간다.
Future<void> editAlias(BuildContext context, ChatStore store, Member m) async {
  final ctl = TextEditingController(text: m.alias);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('이름(별명) 바꾸기'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('상대가 정한 이름: ${m.name}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(hintText: '내가 부를 이름 (비우면 원래대로)'),
          ),
          const Text(
            '나에게만 "내가정한이름(상대가정한이름)"으로 보이고, 상대에게는 아무 변화가 없습니다.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('저장')),
      ],
    ),
  );
  if (ok == true) store.setAlias(m.id, ctl.text);
  ctl.dispose();
}

String formatListTime(DateTime t) {
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return DateFormat('HH:mm').format(t);
  }
  if (t.year == now.year) return DateFormat('M/d').format(t);
  return DateFormat('yy/M/d').format(t);
}

/// 친구 목록 (서로 코드를 주고받아 수락된 사람만, 나 포함 최대 15명). 눌러서 1:1 대화.
/// 넓은 화면에서는 왼쪽 목록으로, 좁은 화면(휴대폰)에서는 전체 화면 목록으로 쓰인다.
class MemberListScreen extends StatefulWidget {
  const MemberListScreen({
    super.key,
    required this.store,
    required this.onLock,
    required this.onSelect,
    this.selectedId,
  });

  final ChatStore store;
  final Future<void> Function() onLock;
  final void Function(String peerId) onSelect;
  final String? selectedId;

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> with WidgetsBindingObserver {
  ChatStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.resume();
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('모두 지우고 처음으로'),
        content: const Text('내 코드, 친구 목록, 이 기기의 대화 내용이 모두 지워집니다.\n(상대방 기기의 내용은 그대로입니다)\n새로 시작하면 내 코드도 새로 만들어집니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('지우기')),
        ],
      ),
    );
    if (ok == true) await store.resetAll();
  }

  Future<void> _memberMenu(Member m) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('이름(별명) 바꾸기'),
              subtitle: const Text('내 화면에만 바뀌어 보입니다'),
              onTap: () => Navigator.pop(c, 'alias'),
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('친구 삭제'),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (v == 'alias') await editAlias(context, store, m);
    if (v == 'remove') await _confirmRemove(m);
  }

  Future<void> _confirmRemove(Member m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('친구 삭제'),
        content: Text('"${m.label}" 님을 친구 목록에서 빼고 대화를 이 기기에서 지울까요?\n(다시 친구가 되려면 코드를 다시 주고받아야 합니다)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) store.removeMember(m.id);
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('z2roN_DM 버전 정보'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in kChangelog) ...[
                  Text('v${e.version}  (${e.date})',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (final n in e.notes) Text('• $n'),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final list = store.sortedMembers;
        final online = list.where((m) => m.online).length;
        // 화면에 그릴 항목: 받은 요청 → 보낸 요청 → 친구
        final items = <Object>[
          if (store.reqIn.isNotEmpty) '친구 요청 ${store.reqIn.length}',
          ...store.reqIn,
          if (store.reqOut.isNotEmpty) '수락 대기 중 ${store.reqOut.length}',
          ...store.reqOut,
          if ((store.reqIn.isNotEmpty || store.reqOut.isNotEmpty) && list.isNotEmpty) '친구 ${list.length}',
          ...list,
        ];
        return Scaffold(
          body: Column(
            children: [
              GradientHeader(
                leading: const AppLogo(size: 34),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('z2roN-DM',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        Text('v$kAppVersion',
                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                    Text(
                      '${store.profile!.name} · 접속 $online명 · 친구 ${list.length + 1}/$kMaxMembers',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                    ),
                  ],
                ),
                actions: [
                  HeaderTextButton(
                    icon: Icons.person_add_alt_1,
                    label: '친구 추가',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AddFriendScreen(store: store)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: '메뉴',
                    offset: const Offset(0, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (v) {
                      switch (v) {
                        case 'add':
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AddFriendScreen(store: store)),
                          );
                        case 'me':
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SetupScreen(store: store, editing: true),
                            ),
                          );
                        case 'copy':
                          Clipboard.setData(ClipboardData(text: store.myCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('내 코드를 복사했습니다. 친구에게 알려 주세요')),
                          );
                        case 'reconnect':
                          store.startNetwork();
                        case 'about':
                          _showAbout();
                        case 'leave':
                          _confirmLeave();
                        case 'lock':
                          widget.onLock();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'add', child: Text('친구 추가')),
                      PopupMenuItem(value: 'copy', child: Text('내 코드 복사')),
                      PopupMenuItem(value: 'me', child: Text('내 이름 / 내 코드 보기')),
                      PopupMenuItem(value: 'reconnect', child: Text('다시 연결')),
                      PopupMenuItem(value: 'about', child: Text('버전 정보 (v$kAppVersion)')),
                      PopupMenuItem(value: 'leave', child: Text('모두 지우고 처음으로')),
                      PopupMenuItem(value: 'lock', child: Text('잠금 (로그아웃)')),
                    ],
                    child: const HeaderIconButton(icon: Icons.more_vert),
                  ),
                ],
              ),
              if (!store.brokerOk)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(store.status, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              if (store.overflow)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '친구 자리(나 포함 15명)가 가득 차서 새 친구를 받아들이지 못했습니다. '
                    '안 쓰는 친구를 길게 눌러 삭제하면 자리가 납니다.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '아직 친구가 없습니다.\n\n'
                                '위의 [친구 추가]를 눌러 친구의 코드를 넣거나,\n'
                                '내 코드를 친구에게 알려 주세요.\n'
                                '서로 수락하면 여기에 나타납니다.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                              ),
                              const SizedBox(height: 16),
                              SoftButton(
                                label: '내 코드 복사',
                                icon: Icons.copy,
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: store.myCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('내 코드를 복사했습니다')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 6, bottom: 24),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final it = items[i];
                          if (it is String) return _sectionLabel(context, it);
                          if (it is FriendReq) return _reqInRow(context, it);
                          if (it is PendingOut) return _reqOutRow(context, it);
                          return _row(context, it as Member);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Text(
        s,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  /// 받은 친구 요청: 수락 / 거절
  Widget _reqInRow(BuildContext context, FriendReq r) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Avatar(name: r.name, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('친구 요청을 보냈습니다',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton(onPressed: () => store.rejectRequest(r), child: const Text('거절')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
            onPressed: () => store.acceptRequest(r),
            child: const Text('수락'),
          ),
        ],
      ),
    );
  }

  /// 내가 보낸 요청: 상대가 수락하면 친구 목록으로 이동
  Widget _reqOutRow(BuildContext context, PendingOut o) {
    final cs = Theme.of(context).colorScheme;
    final shown = o.alias.isNotEmpty ? o.alias : '${o.code.substring(0, o.code.length < 4 ? o.code.length : 4)}…';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Avatar(name: shown, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('상대의 수락을 기다리는 중',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton(onPressed: () => store.cancelRequest(o), child: const Text('취소')),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Member m) {
    final cs = Theme.of(context).colorScheme;
    final last = store.lastOf(m.id);
    final unread = store.unread(m.id);
    final ls = store.linkState(m.id);
    final String state;
    final Color dot;
    if (!m.online) {
      state = '오프라인';
      dot = Colors.grey;
    } else if (ls == LinkState.open) {
      state = '직접 연결됨';
      dot = const Color(0xFF12B886);
    } else {
      state = '연결 중…';
      dot = const Color(0xFFF59F00);
    }
    final preview = last == null
        ? state
        : last.kind == MsgKind.text
            ? '${last.mine ? '나: ' : ''}${last.text}'
            : '${last.mine ? '나: ' : ''}${last.kind == MsgKind.image ? '[사진]' : '[파일]'} ${last.fileName}';
    return InkWell(
      onTap: () => widget.onSelect(m.id),
      onLongPress: () => _memberMenu(m),
      child: Container(
        color: widget.selectedId == m.id ? cs.primary.withOpacity(0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Stack(
              children: [
                Avatar(name: m.alias.isEmpty ? m.name : m.alias),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (last != null)
                        Text(
                          formatListTime(last.time),
                          style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 20),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unread',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
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
