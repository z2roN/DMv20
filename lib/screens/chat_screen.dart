import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../models.dart';
import '../net/peer_link.dart';
import '../store.dart';
import '../widgets.dart';
import 'image_viewer.dart';
import 'member_list_screen.dart' show editAlias;

/// 1:1 채팅 화면
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.store,
    required this.peerId,
    this.showBack = true,
  });

  final ChatStore store;
  final String peerId;

  /// 왼쪽 목록과 함께 보이는 넓은 화면에서는 뒤로가기 버튼을 숨긴다
  final bool showBack;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  ChatStore get store => widget.store;

  bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    store.markRead(widget.peerId);
    store.addListener(_onChange);
  }

  @override
  void dispose() {
    store.removeListener(_onChange);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  // 대화창이 열려 있는 동안 새로 온 글은 바로 읽음 처리
  void _onChange() {
    if (store.unread(widget.peerId) > 0) store.markRead(widget.peerId);
  }

  void _toast(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  void _send() {
    final err = store.sendText(widget.peerId, _input.text);
    if (err != null) {
      _toast(err);
      return;
    }
    _input.clear();
    _focus.requestFocus();
  }

  Future<void> _pick({required bool images}) async {
    if (!store.isLinked(widget.peerId)) {
      _toast('상대와 직접 연결되어 있지 않습니다');
      return;
    }
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: images ? FileType.image : FileType.any,
    );
    if (res == null) return;
    for (final f in res.files) {
      final p = f.path;
      if (p == null) continue;
      final err = await store.sendFile(widget.peerId, p, asImage: images);
      if (err != null && mounted) _toast(err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final mem = store.members[widget.peerId];
        if (mem == null) {
          return const Scaffold(body: Center(child: Text('친구 목록에서 삭제된 사람입니다')));
        }
        final linked = store.isLinked(widget.peerId);
        final ls = store.linkState(widget.peerId);
        final String state = !mem.online
            ? '오프라인'
            : linked
                ? '직접 연결됨 (암호화)'
                : (ls == LinkState.connecting ? '연결 중…' : '연결 대기 중…');
        final msgs = store.chat(widget.peerId);
        return Scaffold(
          body: Column(
            children: [
              GradientHeader(
                leading: widget.showBack ? const HeaderBackButton() : null,
                actions: [
                  HeaderIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: '이름(별명) 바꾸기',
                    onPressed: () => editAlias(context, store, mem),
                  ),
                ],
                title: Row(
                  children: [
                    Avatar(name: mem.alias.isEmpty ? mem.name : mem.alias, size: 36, ring: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(mem.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  color: linked
                                      ? const Color(0xFF69DB7C)
                                      : (mem.online ? const Color(0xFFFFD43B) : Colors.white38),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(state,
                                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: msgs.isEmpty
                    ? Center(
                        child: Text(
                          linked ? '대화를 시작해 보세요' : '연결되면 대화할 수 있습니다',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        itemCount: msgs.length,
                        itemBuilder: (context, i) {
                          final idx = msgs.length - 1 - i;
                          final m = msgs[idx];
                          final prev = idx > 0 ? msgs[idx - 1] : null;
                          final newDay = prev == null ||
                              prev.time.day != m.time.day ||
                              prev.time.month != m.time.month ||
                              prev.time.year != m.time.year;
                          return Column(
                            children: [
                              if (newDay) _dayChip(context, m.time),
                              _Bubble(msg: m),
                            ],
                          );
                        },
                      ),
              ),
              _composer(context, linked),
            ],
          ),
        );
      },
    );
  }

  Widget _dayChip(BuildContext context, DateTime t) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        DateFormat('yyyy년 M월 d일').format(t),
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _composer(BuildContext context, bool linked) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: cardColor(context),
          border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.5))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipButton(onPressed: () => _pick(images: false)),
            IconButton(
              tooltip: '사진 보내기',
              icon: const Icon(Icons.image_outlined),
              onPressed: () => _pick(images: true),
            ),
            Expanded(
              child: Focus(
                onKeyEvent: (node, e) {
                  // Windows: Enter = 보내기, Shift+Enter = 줄바꿈
                  if (_desktop &&
                      e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _send();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: linked ? '메시지 입력' : '연결되면 보낼 수 있습니다',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: '보내기',
              icon: const Icon(Icons.send_rounded, size: 20),
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});

  final Msg msg;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mine = msg.mine;
    final bg = mine ? cs.primary : cardColor(context);
    final fg = mine ? cs.onPrimary : cs.onSurface;
    final sub = mine ? cs.onPrimary.withOpacity(0.75) : cs.onSurfaceVariant;
    Widget body;
    switch (msg.kind) {
      case MsgKind.text:
        body = SelectableText(msg.text, style: TextStyle(color: fg, fontSize: 15, height: 1.35));
      case MsgKind.image:
        body = _image(context, fg);
      case MsgKind.file:
        body = _file(context, fg, sub);
    }
    final pad = msg.kind == MsgKind.image
        ? const EdgeInsets.all(4)
        : const EdgeInsets.symmetric(horizontal: 13, vertical: 9);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) _meta(context, sub: cs.onSurfaceVariant),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: pad,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                ),
                child: body,
              ),
            ),
          ),
          if (!mine) _meta(context, sub: cs.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, {required Color sub}) {
    final IconData? icon;
    Color c = sub;
    switch (msg.status) {
      case MsgStatus.sending:
        icon = Icons.schedule;
      case MsgStatus.sent:
        icon = msg.mine ? Icons.done : null;
      case MsgStatus.delivered:
        icon = msg.mine ? Icons.done_all : null;
      case MsgStatus.failed:
        icon = Icons.error_outline;
        c = Theme.of(context).colorScheme.error;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (icon != null) Icon(icon, size: 13, color: c),
          Text(DateFormat('HH:mm').format(msg.time), style: TextStyle(fontSize: 10.5, color: sub)),
        ],
      ),
    );
  }

  bool get _busy => msg.status == MsgStatus.sending;

  Widget _image(BuildContext context, Color fg) {
    final f = File(msg.path);
    final ok = f.existsSync();
    if (!ok && !_busy) return _file(context, fg, fg.withOpacity(0.7));
    return GestureDetector(
      onTap: _busy
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(path: msg.path, title: msg.fileName),
                ),
              ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260, maxHeight: 300, minWidth: 120, minHeight: 90),
              child: ok
                  ? Image.file(
                      f,
                      fit: BoxFit.cover,
                      cacheWidth: 780,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 160,
                        height: 100,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    )
                  : const SizedBox(width: 160, height: 100),
            ),
            if (_busy)
              Container(
                color: Colors.black38,
                width: 160,
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(
                    value: msg.progress > 0 ? msg.progress : null,
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _file(BuildContext context, Color fg, Color sub) {
    final c = fileColorFor(msg.fileName);
    final failed = msg.status == MsgStatus.failed;
    return InkWell(
      onTap: _busy || failed ? null : () => OpenFilex.open(msg.path),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(fileIconFor(msg.fileName), color: c, size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  failed
                      ? '전송 실패 · ${formatSize(msg.size)}'
                      : _busy
                          ? '${(msg.progress * 100).floor()}% · ${formatSize(msg.size)}'
                          : '${formatSize(msg.size)} · 눌러서 열기',
                  style: TextStyle(color: sub, fontSize: 12),
                ),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: LinearProgressIndicator(
                      value: msg.progress > 0 ? msg.progress : null,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
