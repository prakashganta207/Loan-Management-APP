/// Thrown by the service layer when input breaks a business rule.
/// Screens show [message] directly to the user.
class ValidationException implements Exception {
  const ValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}
