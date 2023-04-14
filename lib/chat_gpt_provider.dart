import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttergpt/chat_scroll_controller.dart';
import 'package:uuid/uuid.dart';
import 'package:dart_openai/openai.dart';
import 'package:flutter_gpt_tokenizer/flutter_gpt_tokenizer.dart';

class ChatGptProvider with ChangeNotifier {
  String? apiKey;
  List<Message> messages = [];
  List<Conversation> conversations = [];
  Conversation? activeConversation;
  Directory appDocumentDir;
  bool isDarkMode = true;
  double fontSize = 14;
  String? model;
  bool loading = false;

  ChatGptProvider(this.appDocumentDir) {
    _loadSettings().then((settings) {
      setApiKey(settings['apiKey']);
      setFontSize(settings['fontSize'].toDouble());
      isDarkMode = settings['isDarkMode'];
      setModel(settings['model']);
      notifyListeners();
    });
  }

  void loadConversations() async {
    final directory =
        Directory('${appDocumentDir.path}/FlutterGPT/conversations');
    if (!await directory.exists()) {
      await directory.create();
    }
    final files = directory.listSync();
    for (final file in files) {
      if (file is File) {
        try {
          final fileContent = await file.readAsString();
          final conversationJson = jsonDecode(fileContent);
          final conversation = Conversation.fromJson(conversationJson);
          conversations.add(conversation);
        } catch (e) {
          if (kDebugMode) {
            print('Error loading conversation: $e');
          }
        }
      }
    }

    conversations.sort((a, b) => b.createdDate.compareTo(a.createdDate));

    if (conversations.isNotEmpty) {
      setActiveConversation(0);
    }

    notifyListeners();
  }

  Future<void> saveCurrentConversation() async {
    if (activeConversation == null) return;

    final fileName = '${activeConversation?.id}.json';
    final file =
        File('${appDocumentDir.path}/FlutterGPT/conversations/$fileName');
    final fileContent = jsonEncode(activeConversation?.toJson());
    await file.writeAsString(fileContent);
  }

  Future<void> deleteConversation(String id) async {
    final file =
        File('${appDocumentDir.path}\\FlutterGPT\\conversations\\$id.json');

    if (await file.exists()) await file.delete();
    conversations.removeWhere((conversation) => conversation.id == id);
    if (activeConversation?.id == id) activeConversation = null;
    notifyListeners();
  }

  void saveCurrentConversationSync() {
    if (activeConversation == null) return;
    final fileName = '${activeConversation?.id}.json';
    final file =
        File('${appDocumentDir.path}/FlutterGPT/conversations/$fileName');
    final fileContent = jsonEncode(activeConversation?.toJson());
    file.writeAsStringSync(fileContent);
  }

  Future<void> setActiveConversation(int index) async {
    if (index < 0 || index > conversations.length - 1) return;

    activeConversation = conversations[index];
    messages = activeConversation!.messages;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 50));
    scrollToBottomAnimated();
  }

  void createNewConversation() {
    final newConversation = Conversation(
        name: 'Conversation ${conversations.length + 1}',
        id: const Uuid().v4(),
        createdDate: DateTime.now());
    conversations.insert(0, newConversation);
    setActiveConversation(0);
  }

  // Set API Key and save it
  void setApiKey(String key) {
    apiKey = key;
    _saveSettings();
    if (apiKey != null) OpenAI.apiKey = apiKey!;
    notifyListeners();
  }

  void setModel(String s) {
    model = s;
    _saveSettings();
    notifyListeners();
  }

  // Load settings from disk
  Future<Map<String, dynamic>> _loadSettings() async {
    final settingsFile =
        File('${appDocumentDir.path}/FlutterGPT/settings.json');
    if (await settingsFile.exists()) {
      final jsonString = await settingsFile.readAsString();
      return jsonDecode(jsonString) as Map<String, dynamic>;
    }
    return {
      'apiKey': '',
      'isDarkMode': true,
      'fontSize': 14,
      'model': 'gpt-3.5-turbo'
    };
  }

  // Save settings to disk
  Future<void> _saveSettings() async {
    final settingsFile =
        File('${appDocumentDir.path}/FlutterGPT/settings.json');
    final settings = {
      'apiKey': apiKey,
      'isDarkMode': isDarkMode,
      'fontSize': fontSize,
      'model': model,
    };
    await settingsFile.writeAsString(jsonEncode(settings));
  }

  void toggleDarkMode() {
    isDarkMode = !isDarkMode;
    _saveSettings();
    notifyListeners();
  }

  void setFontSize(double newSize) {
    fontSize = newSize;
    _saveSettings();
    notifyListeners();
  }

  Future<ConversationStatistics> getConversationStatistics() async {
    num tokenEstimation = 0;
    int maxTokens = model == "gpt-4" ? 8192 : 4096;
    int count = 0;

    for (var i = messages.length - 1; i >= 0; i--) {
      var message = messages[i];
      tokenEstimation +=
          await Tokenizer().count(message.content, modelName: model!);
      if (tokenEstimation > maxTokens && count > 0) break;

      count++;
    }

    return ConversationStatistics(
        tokenCount: tokenEstimation as int,
        truncatedMessageCount: messages.length - count);
  }

  Future<void> sendMessage(BuildContext context, String messageContent,
      {required void Function(String) onError}) async {
    loading = true;

    if (activeConversation == null) createNewConversation();

    messages.add(Message(content: messageContent, role: "user"));
    notifyListeners();

    List<OpenAIChatCompletionChoiceMessageModel> request = [];

    num tokenEstimation = 0;
    int maxTokens = model == "gpt-4" ? 8192 : 4096;

    for (var i = messages.length - 1; i >= 0; i--) {
      var message = messages[i];
      tokenEstimation +=
          await Tokenizer().count(message.content, modelName: model!);
      if (tokenEstimation > maxTokens && request.isNotEmpty) break;

      request.add(OpenAIChatCompletionChoiceMessageModel(
          role: message.role == "user"
              ? OpenAIChatMessageRole.user
              : OpenAIChatMessageRole.assistant,
          content: message.content));
    }

    request = request.reversed.toList();

    Stream<OpenAIStreamChatCompletionModel> chatStream =
        OpenAI.instance.chat.createStream(
      model: "gpt-3.5-turbo",
      messages: request,
    );
    var buffer = StringBuffer();
    messages.add(Message(content: buffer.toString(), role: "assistant"));

    chatStream.listen(
        (chatStreamEvent) {
          if (chatStreamEvent.choices[0].delta.content == "null" ||
              chatStreamEvent.choices[0].delta.content == null) return;
          buffer.write(chatStreamEvent.choices[0].delta.content);
          messages.last.content = buffer.toString();
          notifyListeners();
          scrollToBottom();
        },
        onDone: () {
          loading = false;
          notifyListeners();
        },
        cancelOnError: true,
        onError: (err) {
          loading = false;
          onError('Error: $err');
          notifyListeners();
        });

    notifyListeners();
    scrollToBottom();
  }

  scrollToBottom() {
    var controller = ChatScrollController().controller;
    controller.jumpTo(controller.position.maxScrollExtent);
  }

  scrollToBottomAnimated() {
    var controller = ChatScrollController().controller;
    controller.animateTo(controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500), curve: Curves.decelerate);
  }
}

class Message {
  String content;
  final String role;

  Message({required this.content, required this.role});

  Message.fromJson(Map<String, dynamic> json)
      : content = json['content'],
        role = json['role'];

  Map<String, dynamic> toJson() => {
        'content': content,
        'role': role,
      };
}

class Conversation {
  String id;
  String name;
  DateTime createdDate;
  List<Message> messages;

  Conversation(
      {required this.name,
      required this.createdDate,
      required this.id,
      List<Message>? messages})
      : messages = messages ?? [];

  factory Conversation.fromJson(Map<String, dynamic> json) {
    Conversation conv = Conversation(
      name: json['name'],
      id: json['id'],
      createdDate: DateTime.parse(json['createdDate']),
      messages: (json['messages'] as List)
          .map((messageJson) => Message.fromJson(messageJson))
          .toList(),
    );
    return conv;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdDate': createdDate.toIso8601String(),
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }
}

class ConversationStatistics {
  final int tokenCount;
  final int truncatedMessageCount;

  ConversationStatistics(
      {required this.tokenCount, required this.truncatedMessageCount});
}
