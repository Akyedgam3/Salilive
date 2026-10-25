import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

int levelOf(num wealth) => sqrt(wealth / 50).floor() + 1;

void snack(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

class Avatar extends StatelessWidget {
  final String? url;
  final String? name;
  final double radius;
  const Avatar({super.key, this.url, this.name, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundColor: kCard, backgroundImage: CachedNetworkImageProvider(url!));
    }
    final t = (name ?? '?').trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: kPurple,
      child: Text(t.isEmpty ? '?' : t.characters.first.toUpperCase(),
          style: TextStyle(fontSize: radius * .8, fontWeight: FontWeight.bold)),
    );
  }
}

/// A gift icon: either an emoji or an image URL.
class GiftIcon extends StatelessWidget {
  final String icon;
  final double size;
  const GiftIcon(this.icon, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    if (icon.startsWith('http')) {
      return CachedNetworkImage(imageUrl: icon, width: size, height: size, fit: BoxFit.contain);
    }
    return Text(icon, style: TextStyle(fontSize: size * .85, height: 1.1));
  }
}

class LevelBadge extends StatelessWidget {
  final num wealth;
  const LevelBadge(this.wealth, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(gradient: kGradient, borderRadius: BorderRadius.circular(99)),
        child: Text('Lv.${levelOf(wealth)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      );
}

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool loading;
  const GradientButton({super.key, required this.text, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .5 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading ? null : onTap,
          child: Ink(
            height: 52,
            decoration: BoxDecoration(gradient: kGradient, borderRadius: BorderRadius.circular(16)),
            child: Center(
              child: loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      );
}
