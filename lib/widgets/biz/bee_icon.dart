import 'package:flutter/material.dart';

class BeeIcon extends StatelessWidget {
  final Color color;
  final double size;

  const BeeIcon({super.key, required this.color, this.size = 256});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo2.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Icon(
        Icons.account_balance_wallet_rounded,
        color: color,
        size: size,
      ),
    );
  }
}
