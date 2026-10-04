import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class NetworkErrorService {
  static const String defaultNoInternetMessage =
      'No internet connection. Please check your network and try again.';

  static const String defaultTimeoutMessage =
      'The request timed out. Please check your internet connection and try again.';

  static bool isConnectivityIssue(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException) {
      return true;
    }

    if (error is AuthException && _looksLikeConnectivityIssue(error.message)) {
      return true;
    }

    if (error is PostgrestException && _looksLikeConnectivityIssue(error.message)) {
      return true;
    }

    if (error is StorageException && _looksLikeConnectivityIssue(error.message)) {
      return true;
    }

    return _looksLikeConnectivityIssue(error.toString());
  }

  static String toUserMessage(
    Object error, {
    String fallback = defaultNoInternetMessage,
  }) {
    if (error is TimeoutException) {
      return defaultTimeoutMessage;
    }

    if (isConnectivityIssue(error)) {
      final msg = error.toString().toLowerCase();
      if (msg.contains('timed out') || msg.contains('timeout')) {
        return defaultTimeoutMessage;
      }
      return fallback;
    }

    if (error is AuthException) {
      return error.message;
    }

    if (error is PostgrestException) {
      return error.message;
    }

    return error.toString();
  }

  static Future<bool> hasInternetConnection() async {
    try {
      final results = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return results.isNotEmpty && results[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool _looksLikeConnectivityIssue(dynamic error) {
    final message = error.toString().toLowerCase();
    return message.contains('socket') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('failed host lookup') ||
        message.contains('no address associated with hostname') ||
        message.contains('clientexception') ||
        message.contains('xmlhttprequest') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('network is unreachable') ||
        message.contains('handshake') ||
        message.contains('offline') ||
        message.contains('os error') ||
        message.contains('authretryablefetchexception');
  }
}
