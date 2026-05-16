import 'dart:io';

import 'package:flutter/material.dart';

class AlbumArt extends StatelessWidget {
  const AlbumArt({
    required this.imageUri,
    required this.size,
    this.semanticLabel,
    super.key,
  });

  final Uri? imageUri;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: size,
        child: _AlbumArtImage(
          imageUri: imageUri,
          semanticLabel: semanticLabel,
          colorScheme: colorScheme,
        ),
      ),
    );
  }
}

class _AlbumArtImage extends StatelessWidget {
  const _AlbumArtImage({
    required this.imageUri,
    required this.colorScheme,
    this.semanticLabel,
  });

  final Uri? imageUri;
  final ColorScheme colorScheme;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final uri = imageUri;
    if (uri == null) {
      return _AlbumArtFallback(colorScheme: colorScheme);
    }

    if (uri.isScheme('file')) {
      return Image.file(
        File.fromUri(uri),
        fit: BoxFit.cover,
        semanticLabel: semanticLabel,
        errorBuilder: (context, error, stackTrace) =>
            _AlbumArtFallback(colorScheme: colorScheme),
      );
    }

    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) =>
          _AlbumArtFallback(colorScheme: colorScheme),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return _AlbumArtFallback(colorScheme: colorScheme, showProgress: true);
      },
    );
  }
}

class _AlbumArtFallback extends StatelessWidget {
  const _AlbumArtFallback({
    required this.colorScheme,
    this.showProgress = false,
  });

  final ColorScheme colorScheme;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: showProgress
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.album_outlined, color: colorScheme.primary),
      ),
    );
  }
}
