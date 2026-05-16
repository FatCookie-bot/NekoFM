import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class SubsonicAuth {
  const SubsonicAuth({required this.salt, required this.token});

  factory SubsonicAuth.fromPassword(String password) {
    final salt = _createSalt();
    final bytes = utf8.encode('$password$salt');
    return SubsonicAuth(salt: salt, token: md5.convert(bytes).toString());
  }

  final String salt;
  final String token;

  static String _createSalt() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
