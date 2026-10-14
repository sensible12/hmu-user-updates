class LegalLinks {
  static const String baseUrl = 'https://sensible12.github.io/hmu-user-updates';
  static const String termsUrl =
      'https://sites.google.com/view/hmu-terms-and-conditions/home';
  static const String privacyUrl =
      'https://sites.google.com/view/hmu-privacy-policy/home';
  static const String accountDeletionUrl =
      'https://sites.google.com/view/hmu-deletion-process/home';

  static Uri get terms => Uri.parse(termsUrl);
  static Uri get privacy => Uri.parse(privacyUrl);
  static Uri get accountDeletion => Uri.parse(accountDeletionUrl);
}
