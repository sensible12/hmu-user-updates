import 'package:flutter/material.dart';

class OrderTypeToggle extends StatelessWidget {
  const OrderTypeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.serviceType = 'both',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String serviceType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inactiveBackground = isDark
        ? const Color(0xFF2A2A2F)
        : theme.colorScheme.outlineVariant;
    final inactiveForeground = isDark
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface;

    final availableTypes = serviceType == 'delivery'
        ? const ['delivery']
        : serviceType == 'pickup'
        ? const ['pickup']
        : const ['delivery', 'pickup'];

    return Row(
      children: availableTypes.map((type) {
        final active = value == type;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(type),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: active ? theme.colorScheme.primary : inactiveBackground,
              ),
              child: Text(
                type == 'delivery' ? 'Delivery' : 'Pick-Up',
                style: TextStyle(
                  color: active ? Colors.white : inactiveForeground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
