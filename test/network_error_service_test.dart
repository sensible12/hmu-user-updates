import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hmu/core/services/network_error_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('NetworkErrorService Tests', () {
    test('Identifies SocketException as connectivity issue', () {
      final error = const SocketException('Failed host lookup: db.supabase.co');
      expect(NetworkErrorService.isConnectivityIssue(error), isTrue);
      expect(
        NetworkErrorService.toUserMessage(error),
        equals(NetworkErrorService.defaultNoInternetMessage),
      );
    });

    test('Identifies TimeoutException as connectivity issue with timeout message', () {
      final error = TimeoutException('Connection timed out after 15s');
      expect(NetworkErrorService.isConnectivityIssue(error), isTrue);
      expect(
        NetworkErrorService.toUserMessage(error),
        equals(NetworkErrorService.defaultTimeoutMessage),
      );
    });

    test('Identifies http.ClientException as connectivity issue', () {
      final error = http.ClientException('XMLHttpRequest error');
      expect(NetworkErrorService.isConnectivityIssue(error), isTrue);
      expect(
        NetworkErrorService.toUserMessage(error),
        equals(NetworkErrorService.defaultNoInternetMessage),
      );
    });

    test('Identifies AuthException with network failure as connectivity issue', () {
      const error = AuthException('ClientException with SocketException: Failed host lookup');
      expect(NetworkErrorService.isConnectivityIssue(error), isTrue);
      expect(
        NetworkErrorService.toUserMessage(error),
        equals(NetworkErrorService.defaultNoInternetMessage),
      );
    });

    test('Does not classify invalid credentials as connectivity issue', () {
      const error = AuthException('Invalid login credentials');
      expect(NetworkErrorService.isConnectivityIssue(error), isFalse);
      expect(
        NetworkErrorService.toUserMessage(error),
        equals('Invalid login credentials'),
      );
    });

    test('Identifies PostgrestException with network timeout as connectivity issue', () {
      const error = PostgrestException(message: 'Connection timed out on query');
      expect(NetworkErrorService.isConnectivityIssue(error), isTrue);
      expect(
        NetworkErrorService.toUserMessage(error),
        equals(NetworkErrorService.defaultTimeoutMessage),
      );
    });
  });
}
