import 'package:flutter/material.dart';

import '../vault.dart';
import '../version.dart';
import '../widgets.dart';

/// 앱 암호 설정(처음) / 잠금 해제 화면
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.vault,
    required this.setup,
    required this.onUnlocked,
    this.onReset,
  });

  final Vault vault;

  /// true = 처음 실행(암호 만들기)
  final bool setup;
  final Future<void> Function() onUnlocked;

  /// 데이터 초기화 후 호출 (처음 상태로 돌아가기)
  final VoidCallback? onReset;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _auto = true;
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _pw.text;
    if (widget.setup) {
      if (pw.length < 4) {
        setState(() => _error = '암호는 4자 이상으로 입력하세요');
        return;
      }
      if (pw != _pw2.text) {
        setState(() => _error = '암호 확인이 일치하지 않습니다');
        return;
      }
    } else if (pw.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.setup) {
        await widget.vault.setup(pw, autoLogin: _auto);
      } else {
        final ok = await widget.vault.unlock(pw, autoLogin: _auto);
        if (!ok) {
          if (mounted) {
            setState(() {
              _busy = false;
              _error = '암호가 올바르지 않습니다';
            });
          }
          return;
        }
      }
      await widget.onUnlocked();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '오류: $e';
        });
      }
    }
  }

  Future<void> _forgot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('암호를 잊으셨나요?'),
        content: const Text(
          '암호는 복구할 수 없습니다.\n'
          '초기화하면 이 앱에 저장된 내 코드, 친구 목록, 대화 내용이 모두 삭제되고 처음 상태로 돌아갑니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('초기화')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.vault.reset();
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          // 상단 소개 영역
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: kBrandGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const AppLogo(size: 64),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'z2roN_story',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.setup
                          ? '지인끼리 1:1 다이렉트 채팅'
                          : '암호를 입력해 주세요',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'v$kAppVersion',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.setup)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            '처음 사용하시네요. 앱 암호를 만들어 주세요.\n'
                            '친구 목록과 대화 내용이 이 암호로 암호화되어 저장됩니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      TextField(
                        controller: _pw,
                        obscureText: !_show,
                        autofocus: true,
                        enabled: !_busy,
                        onSubmitted: (_) => widget.setup ? null : _submit(),
                        decoration: InputDecoration(
                          hintText: widget.setup ? '새 암호 (4자 이상)' : '암호',
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _show ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _show = !_show),
                          ),
                        ),
                      ),
                      if (widget.setup) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _pw2,
                          obscureText: !_show,
                          enabled: !_busy,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            hintText: '암호 확인',
                            prefixIcon: Icon(Icons.lock_outline, size: 20),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _auto,
                        onChanged: _busy ? null : (v) => setState(() => _auto = v ?? true),
                        title: const Text('자동 로그인', style: TextStyle(fontSize: 14)),
                        subtitle: const Text(
                          '이 기기에서는 다음부터 암호 입력 없이 열기',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!,
                              style: TextStyle(color: cs.error, fontSize: 13)),
                        ),
                      GradientButton(
                        label: widget.setup ? '시작하기' : '열기',
                        busy: _busy,
                        onPressed: _submit,
                      ),
                      if (!widget.setup)
                        TextButton(
                          onPressed: _busy ? null : _forgot,
                          child: const Text('암호를 잊었어요 (데이터 초기화)',
                              style: TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
