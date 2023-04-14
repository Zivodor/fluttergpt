import 'package:flutter/material.dart';

class ChatScrollController {
  static final ChatScrollController _instance =
      ChatScrollController._internal();
  final ScrollController controller = ScrollController();

  factory ChatScrollController() {
    return _instance;
  }

  ChatScrollController._internal();
}
