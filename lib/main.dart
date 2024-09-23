import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  // google_generative_ai state
  GenerativeModel? _model;
  String _apiKey = '';
  final TextEditingController _textFieldController = TextEditingController();

  // flutter_chat_ui state
  final List<types.Message> _messages = [];
  final _user = const types.User(
    id: '82091008-a484-4a89-ae75-a22bf8d6f3ac',
  );
  final _chatBot = const types.User(
    id: 'F2091008-a484-4a89-ae75-a22bf8d6f3ac',
  );

  MainAppState() {
    Logger.root.level = Level.FINE;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  initState() {
    super.initState();
    _initChatModel();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('api_key') ?? '';
      _textFieldController.text = _apiKey;
    });
  }

  Future<void> _saveApiKey() async {
    _apiKey = _textFieldController.text;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', _apiKey);
  }

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  Future<void> _handleSendPressed(types.PartialText message) async {
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: const Uuid().v4(),
      text: message.text,
    );

    _addMessage(textMessage);

    final response = await _model!.generateContent([Content.text(message.text)]);
    print(response.text);
    final chatBotMessage = types.TextMessage(
      author: _chatBot,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: const Uuid().v4(),
      text: response.text ?? 'No response',
    );

    _addMessage(chatBotMessage);
  }


  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // TODO do the thing

      currentState = ApplicationState.ready;
      if (mounted) setState(() {});

    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  Future<void> _initChatModel() async {
    await _loadApiKey();

    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
    );
  }

  @override
  Future<void> cancel() async {
    // TODO any logic while canceling?

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Frame Gemini Chat',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Frame Gemini Chat'),
              actions: [getBatteryWidget()]),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: TextField(controller: _textFieldController, obscureText: true, obscuringCharacter: '*', decoration: const InputDecoration(hintText: 'Enter Gemini api_key'),)),
                    ElevatedButton(onPressed: _saveApiKey, child: const Text('Save'))
                  ],
                ),
                ElevatedButton(onPressed: run, child: const Text('Run')),
                Expanded(
                  child: Chat(
                    messages: _messages,
                    onSendPressed: _handleSendPressed,
                    showUserAvatars: true,
                    showUserNames: true,
                    user: _user,
                    theme: const DarkChatTheme(),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.file_open), const Icon(Icons.close)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
