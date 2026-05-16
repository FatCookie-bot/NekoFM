import 'package:flutter/material.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FeaturePlaceholder(
      icon: Icons.download_outlined,
      title: 'Downloads',
    );
  }
}

class _FeaturePlaceholder extends StatelessWidget {
  const _FeaturePlaceholder({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        size: 56,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: title,
      ),
    );
  }
}
