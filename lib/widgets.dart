import 'package:flutter/material.dart';

import 'models.dart' show formatSize;
import 'theme.dart';

/// 앱 아이콘과 같은 파랑→남색 그라데이션
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6096FF), Color(0xFF463CD6)],
);

Color cardColor(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? const Color(0xFF1C1F27) : Colors.white;

/// 앱 로고 (앱 아이콘과 동일한 이미지)
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        'assets/icon/icon.png',
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(gradient: kBrandGradient),
          child: Icon(Icons.forum_rounded, color: Colors.white, size: size * 0.6),
        ),
      ),
    );
  }
}

const List<Color> _palette = [
  Color(0xFF4B55E0),
  Color(0xFF12B886),
  Color(0xFFF76707),
  Color(0xFFD6336C),
  Color(0xFF1C7ED6),
  Color(0xFF7048E8),
  Color(0xFF0CA678),
  Color(0xFFE8590C),
  Color(0xFFAE3EC9),
  Color(0xFF2B8A3E),
];

/// 이름 기반 아바타 색
Color nameColor(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _palette[h % _palette.length];
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 46, this.ring = false});

  final String name;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final label = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final c = nameColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring ? Border.all(color: Colors.white70, width: 1.5) : null,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withOpacity(0.8), c],
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// 화면 상단의 그라데이션 헤더 (뒤로가기·제목·동작 버튼)
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.bottom,
  });

  final Widget title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, bottom == null ? 14 : 10),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (leading != null) ...[leading!, const SizedBox(width: 10)],
                      Expanded(child: title),
                      for (final a in actions) ...[const SizedBox(width: 6), a],
                    ],
                  ),
                  if (bottom != null) ...[const SizedBox(height: 10), bottom!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 헤더 안의 작은 아이콘 버튼 (반투명 흰색 36px)
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// 헤더 안의 작은 글자 버튼 (예: 보내기)
class HeaderTextButton extends StatelessWidget {
  const HeaderTextButton({super.key, required this.label, this.onPressed, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.22),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onPressed,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 뒤로가기 (헤더용)
class HeaderBackButton extends StatelessWidget {
  const HeaderBackButton({super.key});

  @override
  Widget build(BuildContext context) => HeaderIconButton(
        icon: Icons.arrow_back_ios_new,
        tooltip: '뒤로',
        onPressed: () => Navigator.maybePop(context),
      );
}

/// 주요 동작 버튼 (그라데이션, 높이 42)
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final radius = BorderRadius.circular(12);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          gradient: kBrandGradient,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: kBrand.withOpacity(0.28),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else if (icon != null)
                    Icon(icon, size: 18, color: Colors.white),
                  if (busy || icon != null) const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 보조 동작 버튼 (연한 색 배경)
class SoftButton extends StatelessWidget {
  const SoftButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(12);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: c.withOpacity(0.10),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(width: 6)],
                Text(label,
                    style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 둥근 카드 영역 (제목 + 내용)
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                title!,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: cs.primary,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// 메일 서비스 선택 타일 (Gmail / 네이버 / 다음 / 직접 입력)
class ProviderTile extends StatelessWidget {
  const ProviderTile({
    super.key,
    required this.name,
    required this.color,
    required this.letter,
    required this.onTap,
    this.selected = false,
    this.icon,
  });

  final String name;
  final Color color;
  final String letter;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Material(
      color: selected ? color.withOpacity(0.12) : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? color : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: icon != null
                    ? Icon(icon, size: 18, color: Colors.white)
                    : Text(
                        letter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 첨부파일 표시

String _ext(String name) =>
    name.contains('.') ? name.split('.').last.toLowerCase() : '';

IconData fileIconFor(String name) {
  final e = _ext(name);
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'].contains(e)) {
    return Icons.image_outlined;
  }
  if (e == 'pdf') return Icons.picture_as_pdf_outlined;
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(e)) return Icons.folder_zip_outlined;
  if (['doc', 'docx', 'hwp', 'hwpx', 'txt', 'rtf'].contains(e)) {
    return Icons.description_outlined;
  }
  if (['xls', 'xlsx', 'csv'].contains(e)) return Icons.table_chart_outlined;
  if (['ppt', 'pptx'].contains(e)) return Icons.slideshow_outlined;
  if (['mp3', 'wav', 'm4a', 'flac'].contains(e)) return Icons.audiotrack_outlined;
  if (['mp4', 'mov', 'avi', 'mkv'].contains(e)) return Icons.movie_outlined;
  return Icons.insert_drive_file_outlined;
}

Color fileColorFor(String name) {
  final e = _ext(name);
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'].contains(e)) {
    return const Color(0xFF12B886);
  }
  if (e == 'pdf') return const Color(0xFFE5484D);
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(e)) return const Color(0xFFF76707);
  if (['doc', 'docx', 'hwp', 'hwpx', 'txt', 'rtf'].contains(e)) {
    return const Color(0xFF1C7ED6);
  }
  if (['xls', 'xlsx', 'csv'].contains(e)) return const Color(0xFF2B8A3E);
  if (['ppt', 'pptx'].contains(e)) return const Color(0xFFE8590C);
  return const Color(0xFF7048E8);
}

/// 보내기 전 첨부파일 칩 (종류별 아이콘 색 + 이름 + 크기 + 삭제)
class AttachChip extends StatelessWidget {
  const AttachChip({
    super.key,
    required this.name,
    required this.size,
    required this.onRemove,
  });

  final String name;
  final int size;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = fileColorFor(name);
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(fileIconFor(name), size: 17, color: c),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  formatSize(size),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 클립 모양 첨부 버튼 (작은 원형)
class ClipButton extends StatelessWidget {
  const ClipButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '파일 첨부',
      child: Material(
        color: kBrand.withOpacity(0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.attach_file, size: 20, color: kBrand),
          ),
        ),
      ),
    );
  }
}
