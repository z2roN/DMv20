import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store.dart';
import '../widgets.dart';

/// 친구 추가: 친구의 코드를 넣어 요청을 보낸다. (내 코드도 여기서 복사)
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key, required this.store});

  final ChatStore store;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _code = TextEditingController();
  final _alias = TextEditingController();
  bool _busy = false;
  bool _showMine = false;

  @override
  void dispose() {
    _code.dispose();
    _alias.dispose();
    super.dispose();
  }

  void _toast(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _code.text = d!.text!.trim());
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final err = await widget.store.addFriend(_code.text, alias: _alias.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err);
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('친구 요청을 보냈습니다. 상대가 수락하면 목록에 나타납니다')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mine = widget.store.myCode;
    return Scaffold(
      body: Column(
        children: [
          const GradientHeader(
            leading: HeaderBackButton(),
            title: Text('친구 추가',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SectionCard(
                      title: '친구의 코드 넣기',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '친구에게 받은 코드를 넣고 요청을 보내세요. 친구가 수락하면 서로 목록에 나타납니다. '
                            '코드를 서로 주고받아 둘 다 넣으면 바로 친구가 됩니다.',
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.45),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _code,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              hintText: 'abcd-efgh-jkmn-pqrs',
                              suffixIcon: IconButton(
                                tooltip: '붙여넣기',
                                icon: const Icon(Icons.content_paste),
                                onPressed: _paste,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _alias,
                            maxLength: 20,
                            decoration: const InputDecoration(
                              hintText: '친구를 부를 이름 (선택, 나에게만 보임)',
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 12),
                          GradientButton(
                            label: '친구 요청 보내기',
                            icon: Icons.person_add_alt_1,
                            busy: _busy,
                            onPressed: _send,
                          ),
                        ],
                      ),
                    ),
                    SectionCard(
                      title: '내 코드',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '이 코드를 친구에게 알려 주세요. 친구가 [친구 추가]에 넣으면 나에게 요청이 옵니다.',
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.45),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    _showMine ? mine : '••••-••••-••••-••••',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: _showMine ? '숨기기' : '보기',
                                  icon: Icon(_showMine ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _showMine = !_showMine),
                                ),
                                IconButton(
                                  tooltip: '복사',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: mine));
                                    _toast('내 코드를 복사했습니다');
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '코드는 친구에게만 알려 주세요. 모르는 사람이 코드를 알면 나에게 친구 요청을 보낼 수 있습니다.',
                            style: TextStyle(fontSize: 12.5, color: cs.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
