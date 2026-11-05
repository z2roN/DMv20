import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store.dart';
import '../widgets.dart';

/// 내 이름 설정 (처음 실행 / 메뉴에서 수정). 내 코드는 자동으로 만들어진다.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.store, this.editing = false});

  final ChatStore store;
  final bool editing;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.store.profile?.name ?? '');
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toast(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('이름(별명)을 입력해 주세요');
      return;
    }
    setState(() => _busy = true);
    await widget.store.configure(name: name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.editing) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final code = widget.store.myCode;
    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            leading: widget.editing ? const HeaderBackButton() : const AppLogo(size: 34),
            title: Text(
              widget.editing ? '내 이름 / 내 코드' : '시작하기',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SectionCard(
                      title: '내 이름',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _name,
                            maxLength: 20,
                            decoration: const InputDecoration(
                              hintText: '친구들에게 보일 이름(별명)',
                              counterText: '',
                            ),
                          ),
                          if (!widget.editing)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '시작하면 나만의 "내 코드"가 자동으로 만들어집니다.\n'
                                '친구 추가 화면에서 이 코드를 친구에게 알려 주거나, 친구의 코드를 넣어 친구가 될 수 있습니다.',
                                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.45),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.editing)
                      SectionCard(
                        title: '내 코드',
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _show ? code : '••••-••••-••••-••••',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1),
                              ),
                            ),
                            IconButton(
                              tooltip: _show ? '숨기기' : '보기',
                              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _show = !_show),
                            ),
                            IconButton(
                              tooltip: '복사',
                              icon: const Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: code));
                                _toast('내 코드를 복사했습니다');
                              },
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    GradientButton(
                      label: widget.editing ? '저장' : '시작',
                      icon: Icons.check,
                      busy: _busy,
                      onPressed: _save,
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
