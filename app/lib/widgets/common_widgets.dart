import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/photo_helper.dart';
import '../core/utils/currency_formatter.dart';
import 'voice_sheet.dart';

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// Paper card with hairline border (no shadow). `hero: true` adds the one
/// soft shadow allowed in the system. Cards are for KPI / hero / summary
/// blocks only; lists use [AppListRow] + [AppDivider].
class PaperCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final Gradient? gradient;
  final bool hero;
  final Color? borderColor;

  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
    this.onLongPress,
    this.radius = AppTheme.radiusMd,
    this.gradient,
    this.hero = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: gradient == null ? (color ?? AppTheme.paper) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: gradient == null
          ? Border.all(color: borderColor ?? AppTheme.hairline)
          : null,
      boxShadow: hero ? AppTheme.heroShadow : null,
    );
    // Transparent Material so ListTile-based children paint ink on a Material inside the card.
    final box = Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null && onLongPress == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        onLongPress: onLongPress,
        child: box,
      ),
    );
  }
}

/// Legacy alias.
class SoftCard extends PaperCard {
  const SoftCard({
    super.key,
    required super.child,
    super.padding,
    super.color,
    super.onTap,
    super.radius,
    super.gradient,
    bool shadow = false,
    BorderSide? side,
  }) : super(hero: shadow, borderColor: side == null ? null : null);
}

/// Subtle scale-on-press wrapper with haptic tick.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.98,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lists — the one row anatomy used everywhere
// ---------------------------------------------------------------------------

/// 1px hairline divider for list rows. `inset` lines it up with the text
/// column of an [AppListRow] (16 gutter + 40 leading + 12 gap).
class AppDivider extends StatelessWidget {
  final double inset;
  const AppDivider({super.key, this.inset = 68});
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, indent: inset, color: AppTheme.hairline);
}

/// White group that holds a stack of [AppListRow]s separated by hairlines.
/// This is the only "card" a list is allowed to live in (one nesting level).
class ListGroup extends StatelessWidget {
  final List<Widget> children;
  final double dividerInset;
  const ListGroup({super.key, required this.children, this.dividerInset = 68});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) AppDivider(inset: dividerInset),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sliver equivalent of [ListGroup]: paints a paper surface behind a sliver
/// list so rows in a CustomScrollView read as one group.
class SliverListGroup extends StatelessWidget {
  final Widget sliver;
  const SliverListGroup({super.key, required this.sliver});

  @override
  Widget build(BuildContext context) {
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      sliver: sliver,
    );
  }
}

/// The single list row: 40px leading, 15/w600 title, 13 muted subtitle,
/// right-aligned 15/w600 amount with an 11.5 label underneath. 56–64px tall.
class AppListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;

  /// Trailing amount (right aligned, tabular). Mutually exclusive with [trailing].
  final double? amount;
  final Color? amountColor;
  final String? trailingLabel;
  final Color? trailingLabelColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool chevron;
  final Color? titleColor;
  final EdgeInsetsGeometry padding;

  const AppListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.amount,
    this.amountColor,
    this.trailingLabel,
    this.trailingLabelColor,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.chevron = false,
    this.titleColor,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppTheme.gutter,
      vertical: 10,
    ),
  });

  @override
  Widget build(BuildContext context) {
    Widget? right = trailing;
    if (right == null && (amount != null || trailingLabel != null)) {
      right = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (amount != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  CurrencyFormatter.format(amount!),
                  style: AppTheme.bodyStrong.copyWith(
                    color: amountColor ?? AppTheme.ink,
                    fontFeatures: AppTheme.tabular,
                  ),
                  maxLines: 1,
                ),
              ),
            if (trailingLabel != null) ...[
              if (amount != null) const SizedBox(height: 2),
              Text(
                trailingLabel!,
                style: AppTheme.label.copyWith(
                  color: trailingLabelColor ?? AppTheme.inkMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    }

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox(width: 40, height: 40, child: Center(child: leading)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyStrong.copyWith(color: titleColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleWidget != null) ...[
                    const SizedBox(height: 2),
                    subtitleWidget!,
                  ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (right != null) ...[const SizedBox(width: 12), right],
            if (chevron) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppTheme.inkHint,
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null && onLongPress == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        child: row,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Money typography
// ---------------------------------------------------------------------------

/// Amount with a smaller, lighter ৳ sign. Tabular figures; w600 by default,
/// pass `weight: FontWeight.w700` only for hero amounts. Optional count-up.
class TakaText extends StatelessWidget {
  final double amount;
  final double size;
  final Color color;
  final bool animate;
  final FontWeight weight;
  final bool showSign;

  const TakaText(
    this.amount, {
    super.key,
    this.size = AppTheme.amountLgSize,
    this.color = AppTheme.ink,
    this.animate = false,
    this.weight = FontWeight.w600,
    this.showSign = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget build(double v) {
      final abs = v.abs();
      final number = CurrencyFormatter.format(abs, includeSymbol: false);
      final sign = v < 0 ? '−' : (showSign && v > 0 ? '+' : '');
      return RichText(
        maxLines: 1,
        text: TextSpan(
          style: AppTheme.amountLg.copyWith(
            fontSize: size,
            color: color,
            fontWeight: weight,
            letterSpacing: size >= AppTheme.amountLgSize ? -0.5 : 0,
          ),
          children: [
            if (sign.isNotEmpty) TextSpan(text: sign),
            TextSpan(
              text: '৳',
              style: TextStyle(
                fontSize: size * 0.7,
                fontWeight: FontWeight.w400,
                color: color.withValues(alpha: 0.8),
              ),
            ),
            TextSpan(text: number),
          ],
        ),
      );
    }

    if (!animate) return build(amount);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: amount),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => build(v),
    );
  }
}

/// Amount colored by sign: positive → coral (owed) / negative → emerald.
class AmountText extends StatelessWidget {
  final double amount;
  final TextStyle? style;
  final bool showSign;
  final Color positiveColor;
  final Color negativeColor;
  final Color zeroColor;

  const AmountText(
    this.amount, {
    super.key,
    this.style,
    this.showSign = false,
    this.positiveColor = AppTheme.coral,
    this.negativeColor = AppTheme.emerald,
    this.zeroColor = AppTheme.inkMuted,
  });

  @override
  Widget build(BuildContext context) {
    final color = amount > 0
        ? positiveColor
        : (amount < 0 ? negativeColor : zeroColor);
    final text = showSign && amount > 0
        ? '+${CurrencyFormatter.format(amount)}'
        : CurrencyFormatter.format(amount);
    return Text(
      text,
      style: (style ?? AppTheme.amountMd).copyWith(color: color),
    );
  }
}

/// KPI tile: muted label with a small plain icon, amount underneath.
class StatCard extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool compact;
  final String? sublabel;

  const StatCard({
    super.key,
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    this.onTap,
    this.compact = false,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.inkMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: TakaText(
              amount,
              size: compact ? AppTheme.amountMdSize : AppTheme.amountLgSize,
              color: color,
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 4),
            Text(
              sublabel!,
              style: AppTheme.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Structure
// ---------------------------------------------------------------------------

/// Section heading: 13px muted w600, 24 top / 8 bottom. Optional text action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppTheme.gutter,
      AppTheme.s24,
      AppTheme.gutter,
      AppTheme.s8,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTheme.sectionHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?trailing,
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: AppTheme.bodySmStrong,
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sticky section header delegate (for CustomScrollView).
class StickyHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  StickyHeader({required this.child, this.height = 40});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    color: AppTheme.cream,
    alignment: Alignment.centerLeft,
    child: child,
  );

  @override
  double get maxExtent => height;
  @override
  double get minExtent => height;
  @override
  bool shouldRebuild(covariant StickyHeader old) =>
      old.child != child || old.height != height;
}

/// Empty state: one muted 48px icon, one line, one button.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color color;
  final IconData? secondaryIcon;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.color = AppTheme.inkHint,
    this.secondaryIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.inkHint),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTheme.bodyStrong,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!.replaceAll('\n', ' '),
                style: AppTheme.bodySm.copyWith(color: AppTheme.inkMuted),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              PrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// People
// ---------------------------------------------------------------------------

/// Avatar: photo if file exists, else initials over a deterministic pastel.
class AvatarCircle extends StatelessWidget {
  final String name;
  final String? photoPath;
  final double size;
  final IconData? fallbackIcon;
  final bool ring;

  const AvatarCircle({
    super.key,
    required this.name,
    this.photoPath,
    this.size = 40,
    this.fallbackIcon,
    this.ring = false,
  });

  static int _hash(String s) {
    int h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static Color pastelFor(String name) =>
      AppTheme.pastels[_hash(name) % AppTheme.pastels.length];
  static Color inkFor(String name) =>
      AppTheme.pastelInks[_hash(name) % AppTheme.pastelInks.length];

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first;
    return parts.first.characters.first + parts[1].characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final bg = pastelFor(name);
    final fg = inkFor(name);
    Widget child;
    final path = photoPath;
    // existsSync() is blocking disk I/O inside build(); PhotoHelper caches
    // the answer per path so a scrolling list never stats the same file twice.
    final hasPhoto = PhotoHelper.exists(path);
    if (hasPhoto) {
      child = Image.file(
        File(path!),
        fit: BoxFit.cover,
        width: size,
        height: size,
        cacheWidth: 120,
        gaplessPlayback: true,
      );
    } else if (fallbackIcon != null) {
      child = Icon(fallbackIcon, color: fg, size: size * 0.5);
    } else {
      child = Center(
        child: Text(
          _initials,
          style: TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.w600,
            color: fg,
            height: 1,
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: ring ? Border.all(color: Colors.white, width: 2) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons & chips
// ---------------------------------------------------------------------------

/// The primary button: solid deep green, 48px, radius 12.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Color? color;
  final Color? foreground;
  final bool expanded;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.color,
    this.foreground,
    this.expanded = true,
    this.height = AppTheme.controlHeight,
  });

  @override
  Widget build(BuildContext context) {
    final btn = ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? AppTheme.indigo,
        foregroundColor: foreground ?? Colors.white,
        disabledBackgroundColor: (color ?? AppTheme.indigo).withValues(
          alpha: 0.45,
        ),
        minimumSize: Size(expanded ? double.infinity : 64, height),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// The secondary button: outlined hairline, ink text, 48px.
/// (Name kept for compatibility; it is no longer tinted.)
class TonalButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool expanded;
  final double height;

  const TonalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppTheme.ink,
    this.expanded = true,
    this.height = AppTheme.controlHeight,
  });

  @override
  Widget build(BuildContext context) {
    final btn = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: Size(expanded ? double.infinity : 64, height),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Alias with the proper name.
class SecondaryButton extends TonalButton {
  const SecondaryButton({
    super.key,
    required super.label,
    required super.onPressed,
    super.icon,
    super.expanded,
    super.height,
  });
}

/// দিলাম / পেলাম action button: 56px, flat solid colour, icon + label.
class BigActionButton extends StatelessWidget {
  final String label;
  final String? sublabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const BigActionButton({
    super.key,
    required this.label,
    this.sublabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.bodyStrong.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: AppTheme.label.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small status pill: 22px tall, 11.5 text, muted tinted background.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;
  const Pill({
    super.key,
    required this.text,
    required this.color,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: AppTheme.label.copyWith(color: fg, height: 1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Selectable filter chip (one row per screen).
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Color color;
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.color = AppTheme.indigo,
  });

  @override
  Widget build(BuildContext context) {
    final sel = selected ? AppTheme.indigo : null;
    return Material(
      color: sel ?? AppTheme.paper,
      shape: StadiumBorder(side: BorderSide(color: sel ?? AppTheme.hairline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTheme.bodySm.copyWith(
                  color: selected ? Colors.white : AppTheme.ink,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppTheme.label.copyWith(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppTheme.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick amount chips (৫০, ১০০, ৫০০, ১০০০ ...). Adds to the controller.
class QuickAmountChips extends StatelessWidget {
  final TextEditingController controller;
  final List<int> amounts;
  final VoidCallback? onChanged;
  const QuickAmountChips({
    super.key,
    required this.controller,
    this.amounts = const [50, 100, 500, 1000, 2000],
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: amounts
          .map(
            (a) => ActionChip(
              label: Text(
                '+${CurrencyFormatter.format(a.toDouble(), includeSymbol: false)}',
              ),
              backgroundColor: AppTheme.sand,
              side: BorderSide.none,
              onPressed: () {
                final current = double.tryParse(controller.text.trim()) ?? 0;
                final next = current + a;
                controller.text = next == next.roundToDouble()
                    ? next.toStringAsFixed(0)
                    : next.toString();
                controller.selection = TextSelection.collapsed(
                  offset: controller.text.length,
                );
                HapticFeedback.selectionClick();
                onChanged?.call();
              },
            ),
          )
          .toList(),
    );
  }
}

/// Dashboard quick-action tile: the one place (besides list leadings)
/// where a tinted icon is allowed.
class QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int? badge;

  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              TintedIcon(icon, color: color, size: 44),
              if (badge != null && badge! > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.coral,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.paper, width: 2),
                    ),
                    child: Text(
                      '$badge',
                      style: AppTheme.label.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySm.copyWith(height: 1.2),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/// Search input. `onChanged` is debounced (250ms) so list screens do not
/// re-filter on every keystroke.
class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  /// When provided, a mic icon appears and the transcript is passed here.
  final ValueChanged<String>? onVoice;
  final Duration debounce;
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.onVoice,
    this.debounce = const Duration(milliseconds: 250),
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _changed(String v) {
    _timer?.cancel();
    if (v.isEmpty) {
      widget.onChanged(v); // clearing should feel instant
      return;
    }
    _timer = Timer(widget.debounce, () {
      if (mounted) widget.onChanged(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final onChanged = widget.onChanged;
    final onVoice = widget.onVoice;
    final hint = widget.hint;
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      borderSide: BorderSide(color: c, width: w),
    );
    return TextField(
      controller: controller,
      onChanged: _changed,
      // Autoscroll reveals the field above the keyboard + floating nav bar.
      scrollPadding: const EdgeInsets.only(bottom: 120),
      style: AppTheme.body,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        suffixIcon: onVoice == null
            ? null
            : VoiceInputButton(
                size: 44,
                filled: false,
                title: 'নাম বলুন',
                hint: 'যাকে খুঁজছেন তার নাম বলুন',
                onResult: (t) {
                  controller?.text = t;
                  onChanged(t);
                  onVoice(t);
                },
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: b(AppTheme.hairline),
        enabledBorder: b(AppTheme.hairline),
        focusedBorder: b(AppTheme.indigo, 1.5),
      ),
    );
  }
}

/// Labelled field with large tap target.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool autofocus;
  final TextStyle? style;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.autofocus = false,
    this.style,
    this.suffix,
    this.onChanged,
    this.textInputAction,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label, style: AppTheme.sectionHeader),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          autofocus: autofocus,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          style: style ?? AppTheme.body,
          onChanged: onChanged,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, size: 22) : null,
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

/// Large money input with ৳ prefix and numeric keypad.
class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final Color color;
  final ValueChanged<String>? onChanged;
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'টাকার পরিমাণ',
    this.autofocus = false,
    this.color = AppTheme.indigo,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label, style: AppTheme.sectionHeader),
        ),
        TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: AppTheme.amountXl.copyWith(color: color),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: AppTheme.amountXl.copyWith(color: AppTheme.inkHint),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 6),
              child: Text(
                '৳',
                style: AppTheme.amountLg.copyWith(
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}

/// Date chip that opens a picker.
class DateChip extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  const DateChip({
    super.key,
    required this.date,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  String get _label {
    final n = DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final t = DateTime(n.year, n.month, n.day);
    if (d == t) return 'আজ';
    if (d == t.subtract(const Duration(days: 1))) return 'গতকাল';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(
        Icons.calendar_today_outlined,
        size: 16,
        color: AppTheme.inkMuted,
      ),
      label: Text(_label),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: firstDate ?? DateTime(2020),
          lastDate: lastDate ?? DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null) {
          onChanged(
            DateTime(
              picked.year,
              picked.month,
              picked.day,
              date.hour,
              date.minute,
            ),
          );
        }
      },
    );
  }
}

/// Segmented control (two or more options).
class Segmented<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final Color Function(T)? colorOf;
  const Segmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.colorOf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.sand,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: values.map((v) {
          final isSel = v == selected;
          final c = colorOf?.call(v) ?? AppTheme.indigo;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 40,
                decoration: BoxDecoration(
                  color: isSel ? c : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                alignment: Alignment.center,
                child: Text(
                  label(v),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySm.copyWith(
                    color: isSel ? Colors.white : AppTheme.inkMuted,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Simple "label  value" row; label left, value right (tabular).
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.body.copyWith(color: AppTheme.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppTheme.s12),
          Text(
            value,
            style: (bold ? AppTheme.title : AppTheme.bodyStrong).copyWith(
              color: valueColor ?? AppTheme.ink,
              fontFeatures: AppTheme.tabular,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }
}

/// Dotted divider (receipt look). Kept for the memo preview only.
class DottedDivider extends StatelessWidget {
  final Color color;
  const DottedDivider({super.key, this.color = AppTheme.hairline});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final count = (c.maxWidth / 8).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(width: 4, height: 1, color: color),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sheets & dialogs
// ---------------------------------------------------------------------------

/// The ONE bottom action bar used by every full-screen form / detail
/// (`Scaffold.bottomNavigationBar`) and every bottom sheet (last child of a
/// [SheetForm]). Same position everywhere: white, top hairline, 16/12 padding,
/// SafeArea below, 48px buttons; optional [secondary] to the left with a 12px
/// gap and optional [leading] block (e.g. a running total).
class BottomActionBar extends StatelessWidget {
  final Widget primary;
  final Widget? secondary;
  final Widget? leading;

  /// Rendered under the button row (e.g. a destructive text button).
  final Widget? below;
  const BottomActionBar({super.key, required this.primary, this.secondary, this.leading, this.below});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.paper,
        border: Border(top: BorderSide(color: AppTheme.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: AppTheme.s16)],
              if (secondary != null) ...[
                SizedBox(height: AppTheme.controlHeight, child: secondary),
                const SizedBox(width: 12),
              ],
              Expanded(child: SizedBox(height: AppTheme.controlHeight, child: primary)),
            ]),
            ?below,
          ]),
        ),
      ),
    );
  }
}

/// Sheet content with a pinned [BottomActionBar]: [body] scrolls, the bar
/// never does and stays above the keyboard. [AppBottomSheet.show] detects it
/// and lays the sheet out accordingly.
class SheetForm extends StatelessWidget {
  final Widget body;
  final BottomActionBar bar;
  const SheetForm({super.key, required this.body, required this.bar});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 0, AppTheme.gutter, AppTheme.s16),
          child: body,
        ),
      ),
      bar,
    ]);
  }
}

class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    bool scrollable = true,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      useSafeArea: true,
      // Sheets stay readable on tablets instead of stretching edge to edge.
      constraints: const BoxConstraints(maxWidth: AppTheme.sheetMaxWidth),
      backgroundColor: AppTheme.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXl),
        ),
      ),
      builder: (ctx) {
        final isForm = child is SheetForm;
        final content = Padding(
          padding: EdgeInsets.only(
            left: isForm ? 0 : AppTheme.gutter,
            right: isForm ? 0 : AppTheme.gutter,
            top: AppTheme.s8,
            // A SheetForm's bar carries its own padding + SafeArea.
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + (isForm ? 0 : AppTheme.s20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isForm ? AppTheme.gutter : 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTheme.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppTheme.inkMuted,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (isForm) Flexible(child: child) else child,
            ],
          ),
        );
        if (isForm) {
          // The SheetForm scrolls its own body; the action bar stays pinned.
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
            child: content,
          );
        }
        // Every sheet scrolls and is capped at 90% of the screen, so a
        // focused field is never hidden behind the keyboard — including the
        // `scrollable: false` action sheets (they are short, so the scroll
        // view is a no-op there and the layout is unchanged).
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
          ),
          child: SingleChildScrollView(
            physics: scrollable ? null : const ClampingScrollPhysics(),
            child: content,
          ),
        );
      },
    );
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'হ্যাঁ',
    String cancelLabel = 'না',
    bool danger = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.dialogMaxWidth - 48,
          ),
          child: Text(message),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? AppTheme.coral : AppTheme.indigo,
              minimumSize: const Size(96, AppTheme.controlHeight),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  /// Camera / gallery chooser. Returns true = camera, false = gallery, null = cancelled.
  static Future<bool?> pickPhotoSource(BuildContext context) {
    return show<bool>(
      context,
      title: 'ছবি নিন',
      scrollable: false,
      child: ListGroup(
        children: [
          AppListRow(
            leading: const Icon(
              Icons.photo_camera_outlined,
              color: AppTheme.inkMuted,
              size: 24,
            ),
            title: 'ক্যামেরা',
            chevron: true,
            onTap: () => Navigator.pop(context, true),
          ),
          AppListRow(
            leading: const Icon(
              Icons.photo_library_outlined,
              color: AppTheme.inkMuted,
              size: 24,
            ),
            title: 'গ্যালারি',
            chevron: true,
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }
}

/// Snack helper.
void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.coralDeep : AppTheme.ink,
      ),
    );
}

/// Relative time in Bangla: "আজ", "গতকাল", "৩ দিন আগে".
String relativeTimeBn(DateTime date) {
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(now.year, now.month, now.day);
  final days = t.difference(d).inDays;
  if (days <= 0) return 'আজ';
  if (days == 1) return 'গতকাল';
  if (days < 30) return '$days দিন আগে';
  if (days < 365) return '${(days / 30).floor()} মাস আগে';
  return '${(days / 365).floor()} বছর আগে';
}

// ---------------------------------------------------------------------------
// Headers & icons
// ---------------------------------------------------------------------------

/// The one header pattern for tab screens (খাতা / মেমো / ক্যাশ / আরও):
/// pinned + floating app bar, theme title style, trailing icon actions.
class TabHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget? bottom;
  const TabHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      floating: true,
      titleSpacing: AppTheme.gutter,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        ...actions,
        const SizedBox(width: AppTheme.s4),
      ],
      bottom: bottom == null
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: bottom!,
            ),
    );
  }
}

/// Round tinted icon — list leading positions and quick actions only.
/// 40×40 box, 20px glyph.
class TintedIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool square;
  const TintedIcon(
    this.icon, {
    super.key,
    this.color = AppTheme.indigo,
    this.size = 40,
    this.square = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(AppTheme.radiusSm) : null,
      ),
      child: Icon(
        icon,
        color: color,
        size: size >= 44 ? 22 : AppTheme.iconList,
      ),
    );
  }
}

/// Flat note / hint box: muted surface, plain 20px icon, 13px text.
class NoteBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const NoteBox({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppTheme.inkMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.s12,
        vertical: AppTheme.s12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.sand,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: AppTheme.iconList),
          const SizedBox(width: AppTheme.s8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.bodySm.copyWith(color: AppTheme.ink),
            ),
          ),
        ],
      ),
    );
  }
}
