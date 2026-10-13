sealed class AppFailure implements Exception {
  final String message;
  const AppFailure(this.message);
}
class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(super.message);
}
class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message);
}
class AuthenticationFailure extends AppFailure {
  const AuthenticationFailure(super.message);
}
class ServerFailure extends AppFailure {
  const ServerFailure(super.message);
}
