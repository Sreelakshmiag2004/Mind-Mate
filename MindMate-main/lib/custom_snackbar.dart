import 'package:flutter/material.dart';

void showCustomSnackBar(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline,
  Color backgroundColor = const Color(0xFFDA8D7A),
  String actionLabel = 'Dismiss',
  VoidCallback? onAction,
}) {
  final width = MediaQuery.of(context).size.width;
  final margin = width > 600
      ? EdgeInsets.symmetric(horizontal: width * 0.3, vertical: 16)
      : EdgeInsets.symmetric(horizontal: width * 0.05, vertical: 16);

  final snackBar = SnackBar(
    content: Row(
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
    backgroundColor: backgroundColor,
    behavior: SnackBarBehavior.floating,
    margin: margin,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    duration: const Duration(seconds: 3),
    action: SnackBarAction(
      label: actionLabel,
      textColor: Colors.white,
      onPressed: onAction ?? () {},
    ),
  );
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
} 