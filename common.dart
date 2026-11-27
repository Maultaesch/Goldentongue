import 'package:flutter/material.dart';
import '../app/theme.dart';

class GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool expanded;
  const GoldButton({super.key, required this.label, this.onPressed, this.expanded = true});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Container(
        width: expanded ? double.infinity : null,
        decoration: BoxDecoration(
          gradient: AppColors.goldGradient,
          borderRadius: radius,
          boxShadow: const [BoxShadow(color: AppColors.glow, blurRadius: 22)],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Center(
                widthFactor: expanded ? null : 1,
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool hero;
  const AppCard({super.key, required this.child, this.onTap, this.hero = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: hero
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.goldAccent),
              boxShadow: const [BoxShadow(color: AppColors.glow, blurRadius: 28)],
            )
          : null,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(AppSpacing.l + 2), child: child),
        ),
      ),
    );
  }
}

class GoldProgress extends StatelessWidget {
  final double value;
  const GoldProgress({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(children: [
        Container(height: 6, color: const Color(0xFF2A2A2A)),
        FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(height: 6, decoration: const BoxDecoration(gradient: AppColors.goldGradient)),
        ),
      ]),
    );
  }
}

class ScoreCard extends StatelessWidget {
  final String label;
  final int score;
  const ScoreCard({super.key, required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodySmall),
        const SizedBox(height: 4),
        Text('$score', style: t.displayMedium),
        const SizedBox(height: 8),
        GoldProgress(value: score / 100),
      ]),
    );
  }
}

class TagChip extends StatelessWidget {
  final String text;
  const TagChip(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.goldAccent),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.gold)),
    );
  }
}
