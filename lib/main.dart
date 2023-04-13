import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'chat_gpt_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must add this line.
  await windowManager.ensureInitialized();

  final appDocumentDir = await getApplicationDocumentsDirectory();
  runApp(
    ChangeNotifierProvider(
      create: (BuildContext context) => ChatGptProvider(appDocumentDir),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatGPT Desktop',
      theme: Provider.of<ChatGptProvider>(context).isDarkMode
          ? ThemeData.dark()
          : ThemeData.light(),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<StatefulWidget> createState() {
    return _MyHomePageState();
  }
}

class ListTileWithHover extends StatefulWidget {
  final ChatGptProvider provider;
  final Conversation conversation;
  final int index;
  TextEditingController? controller;

  ListTileWithHover(
      {super.key,
      required this.provider,
      required this.index,
      required this.conversation}) {
    controller = TextEditingController(text: conversation.name);
  }

  @override
  State<ListTileWithHover> createState() => _ListTileWithHoverState();
}

class _ListTileWithHoverState extends State<ListTileWithHover> {
  bool _highlight = false;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
        onEnter: (e) => setState(() {
              _highlight = true;
            }),
        onExit: (e) => setState(() {
              _highlight = false;
            }),
        child: ListTile(
          leading: const Icon(Icons.message),
          title: Column(
            children: [
              Visibility(
                visible: !_editing,
                child: Text(
                  widget.conversation.name,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                ),
              ),
              Visibility(
                visible: _editing,
                child: TextField(
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  maxLines: 1,
                  minLines: 1,
                  controller: widget.controller,
                  onEditingComplete: () {
                    setState(() {
                      _editing = false;
                      if (widget.controller == null) return;
                      widget.conversation.name = widget.controller!.text;
                    });
                  },
                  onTapOutside: (event) {
                    setState(() {
                      _editing = false;
                      if (widget.controller == null) return;
                      widget.conversation.name = widget.controller!.text;
                    });
                  },
                ),
              ),
            ],
          ),
          trailing: Visibility(
              visible: _highlight || _editing,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Visibility(
                    visible: !_editing,
                    child: IconButton(
                      splashRadius: 20,
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.grey,
                      ),
                      onPressed: () async {
                        setState(() {
                          _editing = true;
                        });
                      },
                    ),
                  ),
                  Visibility(
                    visible: _editing,
                    child: IconButton(
                      splashRadius: 20,
                      icon: const Icon(
                        Icons.check,
                        color: Colors.grey,
                      ),
                      onPressed: () async {
                        setState(() {
                          _editing = false;
                          if (widget.controller == null) return;
                          widget.conversation.name = widget.controller!.text;
                        });
                      },
                    ),
                  ),
                  IconButton(
                    splashRadius: 20,
                    icon: const Icon(
                      Icons.delete,
                      color: Colors.red,
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete conversation'),
                          content: const Text(
                              'Are you sure you want to delete this conversation?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      final provider = widget.provider;

                      if (confirmed == true) {
                        bool deletingActive = provider.activeConversation?.id ==
                            widget.conversation.id;

                        await provider
                            .deleteConversation(widget.conversation.id);

                        if (deletingActive) {
                          provider.setActiveConversation(0);
                        }
                      }
                    },
                  ),
                ],
              )),
          onTap: () {
            final chatGptProvider =
                Provider.of<ChatGptProvider>(context, listen: false);
            if (!chatGptProvider.loading) {
              chatGptProvider.saveCurrentConversation();
              chatGptProvider.setActiveConversation(widget.index);
            }
          },
        ));
  }
}

class _MyHomePageState extends State<MyHomePage> with WindowListener {
  final TextEditingController _textEditingController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final chatGptProvider =
          Provider.of<ChatGptProvider>(context, listen: false);
      _apiKeyController.text = chatGptProvider.apiKey ?? '';
      chatGptProvider.loadConversations();
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    _saveConversationsOnClose();
  }

  void _createNewConversation(BuildContext context) {
    final chatGptProvider =
        Provider.of<ChatGptProvider>(context, listen: false);
    chatGptProvider.saveCurrentConversation();
    chatGptProvider.createNewConversation();
  }

  void _submitMessage(BuildContext context) async {
    if (Provider.of<ChatGptProvider>(context, listen: false).loading) return;

    String message = _textEditingController.text;
    if (message.isNotEmpty) {
      final apiKey =
          Provider.of<ChatGptProvider>(context, listen: false).apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: const Text('No API key is set.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }

      _textEditingController.clear();

      await Provider.of<ChatGptProvider>(context, listen: false).sendMessage(
        context,
        message,
        onError: (errorMessage) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Error'),
              content: Text(errorMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      );

      _scrollToBottom();
    }
  }

  void _showSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final chatGptProvider =
            Provider.of<ChatGptProvider>(context, listen: false);
        String dropdownValue =
            chatGptProvider.model == 'gpt-4' ? 'GPT-4' : 'GPT-3.5';
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: dropdownValue,
                      onChanged: (String? newValue) {
                        setState(() {
                          dropdownValue = newValue!;
                          chatGptProvider.setModel(
                              newValue == 'GPT-4' ? 'gpt-4' : 'gpt-3.5-turbo');
                        });
                      },
                      items: <String>['GPT-4', 'GPT-3.5']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                    TextFormField(
                      controller: _apiKeyController,
                      decoration:
                          const InputDecoration(labelText: 'ChatGPT API Key'),
                      onChanged: (val) {
                        chatGptProvider.setApiKey(val);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Dark mode'),
                      value: chatGptProvider.isDarkMode,
                      onChanged: (bool value) {
                        setState(() {
                          chatGptProvider.toggleDarkMode();
                        });
                      },
                    ),
                    Slider(
                      min: 12,
                      max: 24,
                      divisions: 12,
                      onChanged: (double value) {
                        chatGptProvider.setFontSize(value);
                      },
                      value: chatGptProvider.fontSize,
                      label: 'Font size: ${chatGptProvider.fontSize}',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _saveConversationsOnClose() {
    final chatGptProvider =
        Provider.of<ChatGptProvider>(context, listen: false);
    chatGptProvider.saveCurrentConversationSync();
  }

  void _scrollToBottom() {
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  ListTileWithHover _buildConversationTile(
      ChatGptProvider provider, int index, Conversation conversation) {
    return ListTileWithHover(
        provider: provider, index: index, conversation: conversation);
  }

  @override
  Widget build(BuildContext context) {
    final chatGptProvider = Provider.of<ChatGptProvider>(context);
    final fontStyle = TextStyle(fontSize: chatGptProvider.fontSize);

    return MaterialApp(
      theme: chatGptProvider.isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        appBar: AppBar(title: const Text('ChatGPT Desktop')),
        body: Row(
          children: [
            Expanded(
              child: Container(
                  color: Theme.of(context).colorScheme.shadow.withOpacity(0.2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: chatGptProvider.conversations.length,
                          itemBuilder: (context, index) {
                            final conversation =
                                chatGptProvider.conversations[index];
                            return _buildConversationTile(
                                chatGptProvider, index, conversation);
                          },
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10.0),
                        leading: const Icon(Icons.add),
                        title: const Text('New Conversation'),
                        onTap: () => _createNewConversation(context),
                      ),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10.0),
                        leading: const Icon(Icons.settings),
                        title: const Text('Settings'),
                        onTap: () => _showSettings(context),
                      ),
                    ],
                  )),
            ),
            const VerticalDivider(),
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        // Vertical scroll for messages
                        child: Column(
                          children: chatGptProvider.messages
                              .map((message) => Column(children: [
                                    Container(
                                        color: message.isUser
                                            ? Theme.of(context)
                                                .colorScheme
                                                .background
                                                .withOpacity(0.1)
                                            : Theme.of(context)
                                                .colorScheme
                                                .shadow
                                                .withOpacity(0.1),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  (message.isUser
                                                      ? const Icon(Icons.person,
                                                          size: 32)
                                                      : const Icon(
                                                          Icons.android,
                                                          size: 32)),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    // Wrap with expanded to give constraints
                                                    child:
                                                        SingleChildScrollView(
                                                      scrollDirection: Axis
                                                          .vertical, // Horizontal scroll for long content
                                                      child: SelectableText(
                                                          message.content,
                                                          style: fontStyle),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            ],
                                          ),
                                        )),
                                    const Divider(color: Colors.grey)
                                  ]))
                              .toList(),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.none,
                            maxLines: 5,
                            minLines: 1,
                            controller: _textEditingController,
                            onSubmitted: (val) => {
                              if (!RawKeyboard.instance.keysPressed
                                      .contains(LogicalKeyboardKey.shiftLeft) &&
                                  !RawKeyboard.instance.keysPressed
                                      .contains(LogicalKeyboardKey.shiftRight))
                                _submitMessage(context)
                              else
                                {
                                  _textEditingController.text += "\n",
                                  _textEditingController.selection =
                                      TextSelection.fromPosition(TextPosition(
                                          offset: _textEditingController
                                              .text.length))
                                }
                            },
                            decoration: const InputDecoration(
                                hintText: 'Type your message'),
                            style: fontStyle,
                          ),
                        ),
                        if (chatGptProvider.loading)
                          const CircularProgressIndicator()
                        else
                          IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: () => _submitMessage(context),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
