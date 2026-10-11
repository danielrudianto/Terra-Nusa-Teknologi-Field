import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';

/// Title + description above the page content — `header-title` on the web.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.description, this.action});

  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: w.ink)),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!, style: TextStyle(fontSize: 14, color: w.muted)),
                ],
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
