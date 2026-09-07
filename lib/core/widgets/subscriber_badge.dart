import 'package:flutter/material.dart';

/// Displays the user's original JPG unchanged through a circular viewport.
/// The 342px crop sits just inside the green circle's antialiased JPEG edge,
/// excluding its surrounding black rectangle without redrawing the artwork.
class SubscriberBadge extends StatelessWidget {
  const SubscriberBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: Localizations.localeOf(context).languageCode == 'ar'
        ? 'مشترك'
        : 'Subscriber',
    image: true,
    child: SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: size * 626 / 342,
          maxWidth: size * 626 / 342,
          minHeight: size * 548 / 342,
          maxHeight: size * 548 / 342,
          child: Image.asset(
            'assets/images/subscriber_badge_source.jpg',
            width: size * 626 / 342,
            height: size * 548 / 342,
            fit: BoxFit.fill,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    ),
  );
}

/// Reserve space for the badge so long names cannot push it off a mobile row.
/// This is display-only: callers must use the server's effective member-access
/// verdict (verified YouTube membership, store subscription, or admin grant),
/// never a role, typed profile link, or unverified purchase-history entry.
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
