import 'package:flutter/material.dart';

const _supportedIconExtensions = <String>[
  'png',
  'jpg',
  'jpeg',
  'webp',
  'bmp',
  'gif',
];

final _explicitExtensionPattern = RegExp(r'\.[^./\\]+$');

/// Returns the image paths to try for an icon configuration value.
///
/// A path with an explicit supported extension is returned unchanged. An
/// extensionless path is treated as an icon family. Dark themes prefer its
/// `-white` variant and light themes prefer `-black`, then fall back to color,
/// the unsuffixed image, and finally the opposite-contrast variant.
List<String> buildIconPathCandidates(String path, Brightness brightness) {
  if (_explicitExtensionPattern.hasMatch(path)) return <String>[path];

  final preferredSuffix = brightness == Brightness.dark ? '-white' : '-black';
  final oppositeSuffix = brightness == Brightness.dark ? '-black' : '-white';
  final suffixes = <String>[preferredSuffix, '-color', '', oppositeSuffix];

  return <String>[
    for (final suffix in suffixes)
      for (final extension in _supportedIconExtensions)
        '$path$suffix.$extension',
  ];
}
