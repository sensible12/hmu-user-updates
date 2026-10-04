import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CartBar extends StatelessWidget {
  const CartBar({
    super.key,
    required this.count,
    this.subtotal,
  });

  final int count;
  final double? subtotal;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }

    final subtotalText = subtotal == null
        ? ''
        : ' | M ${subtotal!.toStringAsFixed(2)}';
    final shadowColor = Colors.black.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.26 : 0.16,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => context.push('/cart'),
              child: Ink(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shopping_cart, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      '$count item${count > 1 ? 's' : ''}$subtotalText',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
