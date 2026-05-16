class ServerProfile {
  const ServerProfile({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  final String serverUrl;
  final String username;
  final String password;

  Uri get normalizedBaseUri {
    final trimmed = serverUrl.trim();
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.parse(withScheme);

    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Enter a valid server URL.');
    }

    return uri;
  }

  bool get usesPublicHttp {
    final uri = normalizedBaseUri;
    return uri.scheme == 'http' &&
        !_isLocalHost(uri.host) &&
        !_isPrivateIp(uri.host);
  }

  static bool _isLocalHost(String host) {
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  static bool _isPrivateIp(String host) {
    return host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(host);
  }
}
