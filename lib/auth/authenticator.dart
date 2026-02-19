import 'package:dio/dio.dart';

abstract class Authenticator {
  void apply(Options options);
}
