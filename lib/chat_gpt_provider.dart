import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

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
      apiKey = settings['apiKey'];
      fontSize = settings['fontSize'].toDouble();
      isDarkMode = settings['isDarkMode'];
      model = settings['model'];
      notifyListeners();
    });
  }

  void loadConversations() async {
    final directory = Directory('${appDocumentDir.path}/conversations');
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
    final file = File('${appDocumentDir.path}/conversations/$fileName');
    final fileContent = jsonEncode(activeConversation?.toJson());
    await file.writeAsString(fileContent);
  }

  Future<void> deleteConversation(String id) async {
    final file = File('${appDocumentDir.path}\\conversations\\$id.json');

    if (await file.exists()) await file.delete();
    conversations.removeWhere((conversation) => conversation.id == id);
    if (activeConversation?.id == id) activeConversation = null;
    notifyListeners();
  }

  void saveCurrentConversationSync() {
    if (activeConversation == null) return;
    final fileName = '${activeConversation?.id}.json';
    final file = File('${appDocumentDir.path}/conversations/$fileName');
    final fileContent = jsonEncode(activeConversation?.toJson());
    file.writeAsStringSync(fileContent);
  }

  void setActiveConversation(int index) {
    if (index < 0 || index > conversations.length - 1) return;

    activeConversation = conversations[index];
    messages = activeConversation!.messages;
    notifyListeners();
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
    notifyListeners();
  }

  void setModel(String s) {
    model = s;
    _saveSettings();
    notifyListeners();
  }

  // Load settings from disk
  Future<Map<String, dynamic>> _loadSettings() async {
    final settingsFile = File('${appDocumentDir.path}/settings.json');
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
    final settingsFile = File('${appDocumentDir.path}/settings.json');
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

  Future<void> sendMessage(BuildContext context, String messageContent,
      {required void Function(String) onError}) async {
    loading = true;

    if (activeConversation == null) createNewConversation();

    messages.add(Message(content: messageContent, isUser: true));
    notifyListeners();

    // Define API request headers
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    // Prepare the API call body with the conversation history
    final requestBody = {
      'model': model,
      'messages': messages
          .map((message) => {
                'role': message.isUser ? 'user' : 'assistant',
                'content': message.content
              })
          .toList(),
    };

    // Make API call
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      body: jsonEncode(requestBody),
      headers: headers,
    );

    if (response.statusCode == 200) {
      // Parse ChatGPT response and add it to the messages list
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      messages.add(Message(
          content: responseData['choices'][0]['message']['content'],
          isUser: false));
    } else {
      // Call the onError callback with the error message
      onError('Error: ${response.statusCode}');
    }

    loading = false;
    notifyListeners();
  }
}

class Message {
  final String content;
  final bool isUser;

  Message({required this.content, required this.isUser});

  Message.fromJson(Map<String, dynamic> json)
      : content = json['content'],
        isUser = json['isUser'];

  Map<String, dynamic> toJson() => {
        'content': content,
        'isUser': isUser,
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
