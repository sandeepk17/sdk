import 'package:analysis_server/src/analysis_server_abstract.dart';
import 'package:analyzer/exception/exception.dart';
import 'package:analyzer/instrumentation/instrumentation.dart';

/// An instrumentation service to show instrumentation errors as error
/// notifications to the user.
class ErrorNotifier extends NoopInstrumentationService {
  AbstractAnalysisServer server;

  @override
  void logException(dynamic exception, [StackTrace stackTrace]) {
    if (exception is SilentException) {
      // Silent exceptions should not be reported to the user.
      return;
    }

    var message = 'Internal error';
    if (exception is CaughtException && exception.message != null) {
      message = exception.message;
    }

    server.sendServerErrorNotification(message, exception, stackTrace,
        fatal: exception is FatalException);
  }
}

/// Server may throw a [FatalException] to send a fatal error response to the
/// IDEs.
class FatalException extends CaughtException {
  FatalException(String message, Object exception, stackTrace)
      : super.withMessage(message, exception, stackTrace);
}
