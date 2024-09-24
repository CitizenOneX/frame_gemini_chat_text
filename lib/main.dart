import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
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
  ChatSession? _chat;
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

  // Speech to text state
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _partialResult = "N/A";
  String _finalResult = "N/A";
  String? _prevText;


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

    currentState = ApplicationState.initializing;

    // kick off chat model initialization asynchronously
    _initChatModel();

    // kick off speech-to-text initialization asynchronously
    _initSpeech();
  }

  /// Initialise our LLM
  Future<void> _initChatModel() async {
    await _loadApiKey();

    _initChatSession();
  }

  /// Starts a new Chat Session, either at application start or when the user clears the current conversation
  void _initChatSession() {
    _chat = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      systemInstruction: Content.text('You are a helpful bot that answers with short replies, preferably fewer than 50 words and without markdown or any other formatting because your replies will be displayed on a small text-only display.'),
      safetySettings: [
        // note: safety settings are disabled because it kept blocking "what is the photoelectric effect" due to safety.
        // Be nice and stay safe.
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
      ]
    ).startChat();
  }

  /// This has to happen only once per app, but microphone permission must be provided
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(onError: _onSpeechError);

    if (!_speechEnabled) {
      _finalResult = 'The user has denied the use of speech recognition. Microphone permission must be added manually in device settings.';
      _log.severe(_finalResult);
      currentState = ApplicationState.disconnected;
    }
    else {
      _log.fine('Speech-to-text initialized');
      // this will initialise before Frame is connected, so proceed to disconnected state
      currentState = ApplicationState.disconnected;
    }

    if (mounted) setState(() {});
  }

  /// Manually stop the active speech recognition session, but timeouts will also stop the listening
  Future<void> _stopListening() async {
    await _speechToText.stop();
  }

  /// Timeouts invoke this function, but also other permanent errors
  void _onSpeechError(SpeechRecognitionError error) {
    if (error.errorMsg != 'error_speech_timeout') {
      _log.severe(error.errorMsg);
      currentState = ApplicationState.ready;
    }
    else {
      currentState = ApplicationState.running;
    }
    if (mounted) setState(() {});
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

  void _clearChat() {
    setState(() {
      _messages.clear();
    });

    // start a new conversation with the model, removing history
    _initChatSession();
  }

  Future<void> _handleTextQuery(String request) async {
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: const Uuid().v4(),
      text: request,
    );

    _addMessage(textMessage);

    try {
      final response = await _chat!.sendMessage(Content.text(request));

      _log.info('Gemini response: ${response.text}');

      final chatBotMessage = types.TextMessage(
        author: _chatBot,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: const Uuid().v4(),
        text: response.text ?? 'No response',
      );

      _addMessage(chatBotMessage);

    } catch (e) {

      final chatBotMessage = types.TextMessage(
        author: _chatBot,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: const Uuid().v4(),
        text: 'Error: $e',
      );

      // show the error message for a short time
      _addMessage(chatBotMessage);

      await Future.delayed(const Duration(seconds: 5));

      // start a new conversation with the model, removing history
      _initChatSession();
    }
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // listen for STT
      await _speechToText.listen(
        listenOptions: SpeechListenOptions(
          cancelOnError: true, onDevice: false, listenMode: ListenMode.dictation
        ),
        onResult: (SpeechRecognitionResult result) async {
          if (currentState == ApplicationState.ready) {
            // user has cancelled already, don't process result
            // FIXME reinstate
            //return;
          }

          if (result.finalResult) {
            // on a final result we fetch the wiki content
            _finalResult = result.recognizedWords;
            _partialResult = '';
            _log.fine('Final result: $_finalResult');
            _stopListening();

            // add final result to chat stream
            _handleTextQuery(_finalResult);

            // send final query text to Frame line 1 (before we confirm the title)
            if (_finalResult != _prevText) {
              //await frame!.sendMessage(TxPlainText(msgCode: 0x0a, text: _finalResult));
              // TODO for now, just log result, can send a TextSpriteBlock in future
              _prevText = _finalResult;
            }

            currentState = ApplicationState.ready;
            if (mounted) setState(() {});
          }
          else {
            // partial result - just display in-progress text
            _partialResult = result.recognizedWords;
            if (mounted) setState((){});

            _log.fine('Partial result: $_partialResult, ${result.alternates}');
            if (_partialResult != _prevText) {
              // TODO for now, just log result, can send a TextSpriteBlock in future
              //await frame!.sendMessage(TxPlainText(msgCode: 0x0a, text: _partialResult));
              _prevText = _partialResult;
            }
          }
        }
      );

    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
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
                    onSendPressed: (p0) {},
                    showUserAvatars: true,
                    showUserNames: true,
                    user: _user,
                    theme: const DarkChatTheme(),
                    customBottomWidget: Row(
                      children: [
                        const Spacer(),
                        ...getChatActionButtonsWidgets(),
                      ]
                    ),
                  ),
                ),
              ],
            ),
          ),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }

  List<Widget> getChatActionButtonsWidgets() {
    switch (currentState) {
      case ApplicationState.ready:
        return [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: FloatingActionButton(onPressed: _clearChat, child: const Icon(Icons.create)),
          ),
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: FloatingActionButton(onPressed: run, child: const Icon(Icons.mic)),
          ),
        ];

      case ApplicationState.running:
        return [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: FloatingActionButton(onPressed: cancel, child: const Icon(Icons.cancel)),
          ),
        ];

      default:
        return [];
    }
  }

}
