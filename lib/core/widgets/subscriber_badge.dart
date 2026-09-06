import 'package:flutter/material.dart';

/// The green circle and white star are retained; the surrounding PNG is alpha.
class SubscriberBadge extends StatelessWidget {
  const SubscriberBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: Localizations.localeOf(context).languageCode == 'ar'
        ? 'مشترك'
        : 'Subscriber',
    image: true,
    child: Image.asset(
      'assets/images/subscriber_badge.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: 96,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.medium,
    ),
  );
}

/// Reserve space for the badge so long names cannot push it off a mobile row.
/// This is display-only: callers must use the server's verified subscription
/// flag, never a role, typed profile link, or purchase-history entry.
class SubscriberName extends StatelessWidget {
  const SubscriberName(
    this.name, {
    super.key,
    required this.isSubscriber,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.badgeSize,
  });

  final String name;
  final bool isSubscriber;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? badgeSize;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
    if (!isSubscriber) return text;
    final label = Localizations.localeOf(context).languageCode == 'ar'
        ? 'مشترك'
        : 'Subscriber';
    return Semantics(
      label: '$name, $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: textAlign == TextAlign.center
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Flexible(child: text),
          const SizedBox(width: 5),
          SubscriberBadge(size: badgeSize ?? ((style?.fontSize ?? 14) + 2)),
        ],
      ),
    );
  }
}
