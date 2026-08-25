import 'package:flutter/material.dart';

import '../theme/app_dimens.dart';
import '../theme/app_tokens.dart';

/// Reference implementation of the "transaction row" component from
/// style.md, showing how a widget should pull everything — colors, text
/// styles, spacing — from the theme instead of hardcoding it.
///
/// 32dp icon chip + label + muted subtext + amount, right-aligned.
/// No card wrapper; rows separate with a hairline, not a shadow.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.amount,
    required this.isIncome,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final double amount;
  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>()!;
    final sign = isIncome ? '+' : '−'; // the sign carries meaning too —
    // color must never be the only cue (style.md accessibility rule).
    final amountColor = isIncome ? tokens.income : tokens.expense;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.txIconChip,
            height: AppSizes.txIconChip,
            decoration: BoxDecoration(
              color: tokens.chipBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: tokens.chipFg),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            '$sign ₱${amount.toStringAsFixed(0)}',
            style: tokens.amount.copyWith(color: amountColor),
          ),
        ],
      ),
    );
  }
}
