import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const Color brandBlue = Color(0xFF4268F6);
const Color brandPurple = Color(0xFF8758F7);
const Color pageLight = Color(0xFFF4F7FC);
const Color lineLight = Color(0xFFE5EAF3);
const String landscapeUrl =
    'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1200&q=85';

void main() {
  runApp(const AIChatApp());
}

class AIChatApp extends StatefulWidget {
  const AIChatApp({super.key});

  @override
  State<AIChatApp> createState() => _AIChatAppState();
}

class _AIChatAppState extends State<AIChatApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandBlue,
        brightness: _dark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: _dark ? const Color(0xFF0B1120) : pageLight,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: _dark ? Brightness.dark : Brightness.light).textTheme,
      ),
      iconTheme: IconThemeData(
        color: _dark ? const Color(0xFFCBD5E1) : const Color(0xFF596780),
      ),
      dividerColor: _dark ? const Color(0xFF253248) : lineLight,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Chat',
      theme: base,
      darkTheme: base,
      home: ChatHome(
        dark: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.isUser,
    this.text = '',
    this.isPhysicsSample = false,
    this.isLoading = false,
    this.feedback,
    this.attachment,
    this.id,
    this.sources = const [],
    this.generatedImage,
    this.generatedImageBytes,
  });

  final bool isUser;
  String text;
  final bool isPhysicsSample;
  bool isLoading;
  String? feedback;
  PlatformFile? attachment;
  String? id;
  List<Map<String, dynamic>> sources;
  GeneratedImage? generatedImage;
  Uint8List? generatedImageBytes;
}

class ChatHome extends StatefulWidget {
  const ChatHome({
    super.key,
    required this.dark,
    required this.onToggleTheme,
  });

  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<ChatHome> createState() => _ChatHomeState();
}

class _ChatHomeState extends State<ChatHome> {
  int _page = 0;
  String _model = 'openai/gpt-oss-20b';
  bool _searchOn = false;
  bool _thinkingOn = true;
  bool _generatingImage = false;
  bool _imageReady = true;
  bool _busy = false;
  String? _activeConversationId;
  bool _historyLoading = false;
  String _chatSearchQuery = '';
  Uint8List? _generatedImageBytes;
  String? _generatedImageUrl;
  GeneratedImage? _generatedImage;
  final ApiService _api = ApiService();
  List<ApiConversation> _savedConversations = [];
  PlatformFile? _attachedImage;
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _imagePrompt = TextEditingController(
    text: 'A beautiful mountain landscape with a lake, sunrise, and snow-capped peaks',
  );
  final ScrollController _messageScroll = ScrollController();

  List<String> _recentChats = [
    'Solve this physics problem',
    'Create a beautiful landscape',
    'What is machine learning?',
    'Explain quantum mechanics',
    'Generate an image of a cat',
  ];

  late List<ChatMessage> _messages = _sampleMessages();

  Color get _canvas => widget.dark ? const Color(0xFF0B1120) : pageLight;
  Color get _surface => widget.dark ? const Color(0xFF111B2E) : Colors.white;
  Color get _text => widget.dark ? const Color(0xFFF1F5F9) : const Color(0xFF17233B);
  Color get _muted => widget.dark ? const Color(0xFF91A0B8) : const Color(0xFF71809A);
  Color get _line => widget.dark ? const Color(0xFF253248) : lineLight;

  @override
  void initState() {
    super.initState();
    if (ApiService.isConfigured) {
      _messages = [];
      unawaited(_refreshHistory());
    }
  }

  List<ChatMessage> _sampleMessages() => [
        ChatMessage(
          isUser: true,
          text:
              'Solve this physics problem step by step:\nA 2 kg ball is thrown vertically upward with a speed of 20 m/s. Find (a) the maximum height and (b) the total time in the air. Use g = 9.8 m/s^2.',
        ),
        ChatMessage(isUser: false, isPhysicsSample: true),
      ];

  @override
  void dispose() {
    _api.dispose();
    _composer.dispose();
    _imagePrompt.dispose();
    _messageScroll.dispose();
    super.dispose();
  }

  void _startNewChat() {
    setState(() {
      _page = 0;
      _messages = [];
      _activeConversationId = null;
      _busy = false;
      _attachedImage = null;
      _composer.clear();
    });
  }

  void _openRecent(String title) {
    final matches = _savedConversations.where((item) => item.title == title);
    if (matches.isNotEmpty) {
      unawaited(_loadSavedConversation(matches.first));
      return;
    }
    setState(() {
      _page = 0;
      _activeConversationId = null;
      _messages = title == 'Solve this physics problem'
          ? _sampleMessages()
          : [
              ChatMessage(isUser: true, text: title),
              ChatMessage(
                isUser: false,
                text: 'This is a local sample conversation. Connect the backend to load saved messages.',
              ),
            ];
    });
  }

  Future<void> _refreshHistory() async {
    if (!ApiService.isConfigured || _historyLoading) return;
    _historyLoading = true;
    try {
      final items = await _api.listConversations();
      if (!mounted) return;
      setState(() {
        _savedConversations = items;
        final savedTitles = items.map((item) => item.title).toList();
        _recentChats = [
          ...savedTitles,
          ..._recentChats.where((title) => !savedTitles.contains(title)),
        ].take(40).toList();
      });
    } catch (_) {
      // Keep local sample history visible when the backend is not ready.
    } finally {
      _historyLoading = false;
    }
  }

  Future<void> _loadSavedConversation(ApiConversation conversation) async {
    try {
      final history = await _api.getMessages(conversation.id);
      if (!mounted) return;
      setState(() {
        _activeConversationId = conversation.id;
        _page = 0;
        _messages = history
            .map((message) => ChatMessage(
                  isUser: message.role == 'user',
                  text: message.content,
                  id: message.id,
                  feedback: message.feedback,
                  sources: message.sources,
                  generatedImage: message.generatedImage,
                ))
            .toList();
      });
      _scrollToBottom();
      unawaited(_hydrateSavedImages());
    } catch (error) {
      _showInfo(error.toString());
    }
  }

  Future<void> _hydrateSavedImages() async {
    final pending = _messages.where((message) =>
      message.generatedImage != null &&
      message.generatedImage!.storedInR2 &&
      message.generatedImageBytes == null).toList();

    for (final message in pending) {
      try {
        final image = message.generatedImage;
        if (image == null) continue;
        final bytes = await _api.downloadGeneratedImage(image);
        if (!mounted) return;
        setState(() => message.generatedImageBytes = bytes);
      } catch (_) {
        // Keep the transcript usable when a saved asset is no longer accessible.
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      setState(() => _attachedImage = result.files.single);
      _showInfo('Image attached for frontend preview. Backend vision is not connected yet.');
    } catch (_) {
      _showInfo('Could not open the image picker on this platform.');
    }
  }

  bool _isImageGenerationRequest(String prompt) {
    final english = RegExp(
      r'\b(generate|create|draw|make|design|paint|illustrate)\b.{0,100}\b(image|picture|illustration|artwork|logo|wallpaper|poster|portrait|graphic|icon)\b',
      caseSensitive: false,
    ).hasMatch(prompt) ||
        RegExp(r'\b(draw|paint|illustrate)\b.{0,80}\b(cat|dog|landscape|portrait|person|character|dragon|city|scene|building|flower|animal)\b', caseSensitive: false).hasMatch(prompt) ||
        RegExp(
          r'\b(image|picture|illustration|artwork|logo|wallpaper|poster)\b.{0,80}\b(of|with|showing)\b',
          caseSensitive: false,
        ).hasMatch(prompt);
    final bengali = RegExp(
      r'(ছবি|ইমেজ).{0,80}(বানাও|তৈরি|আঁকো|জেনারেট|করো)|(বানাও|তৈরি করো|আঁকো).{0,80}(ছবি|ইমেজ)',
    ).hasMatch(prompt);
    return english || bengali;
  }

  String _mimeTypeForImage(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _generateImage() async {
    final prompt = _imagePrompt.text.trim();
    if (prompt.isEmpty) {
      _showInfo('Please describe the image first.');
      return;
    }
    if (_generatingImage) return;

    setState(() {
      _generatingImage = true;
      _imageReady = false;
    });

    try {
      if (ApiService.isConfigured) {
        final generated = await _api.generateImage(prompt, conversationId: _activeConversationId);
        final bytes = await _api.downloadGeneratedImage(generated);
        if (!mounted) return;
        setState(() {
          _generatedImage = generated;
          _activeConversationId = generated.conversationId ?? _activeConversationId;
          _generatedImageBytes = bytes;
          _generatedImageUrl = generated.imageUrl;
          _generatingImage = false;
          _imageReady = true;
        });
        _showInfo('Image generated successfully.');
        unawaited(_refreshHistory());
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        if (!mounted) return;
        setState(() {
          _generatingImage = false;
          _imageReady = true;
        });
        _showInfo('Preview only. Configure API_BASE_URL to enable Cloudflare image generation.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _generatingImage = false;
        _imageReady = _generatedImageBytes != null || _generatedImageUrl != null;
      });
      _showInfo('Image generation failed: ' + error.toString());
    }
  }

  Future<void> _downloadImage() async {
    try {
      Uint8List? bytes = _generatedImageBytes;
      if (bytes == null && _generatedImage != null) {
        bytes = await _api.downloadGeneratedImage(_generatedImage!);
      }
      if (bytes == null) {
        _showInfo('Generate an image before downloading it.');
        return;
      }
      await FileSaver.instance.saveFile(
        name: 'ai-chat-generated-image',
        bytes: bytes,
        ext: 'jpg',
        mimeType: MimeType.jpeg,
      );
      _showInfo('Image export started.');
    } catch (error) {
      _showInfo('Could not download image: ' + error.toString());
    }
  }

  Future<void> _downloadMessageImage(ChatMessage message) async {
    try {
      final generated = message.generatedImage;
      if (generated == null) {
        _showInfo('The generated image is not available to download.');
        return;
      }
      final bytes = message.generatedImageBytes ?? await _api.downloadGeneratedImage(generated);
      await FileSaver.instance.saveFile(
        name: 'ai-chat-generated-image',
        bytes: bytes,
        ext: 'jpg',
        mimeType: MimeType.jpeg,
      );
      _showInfo('Image export started.');
    } catch (error) {
      _showInfo('Could not download image: ' + error.toString());
    }
  }

  void _setFeedback(ChatMessage message, String reaction) {
    final next = message.feedback == reaction ? null : reaction;
    setState(() => message.feedback = next);
    if (ApiService.isConfigured && message.id != null) {
      unawaited(
        _api
            .sendFeedback(messageId: message.id!, reaction: next)
            .catchError((Object error) {
          if (mounted) _showInfo('Could not save feedback.');
        }),
      );
    }
  }


  Future<void> _sendMessage() async {
    final rawPrompt = _composer.text.trim();
    if ((rawPrompt.isEmpty && _attachedImage == null) || _busy) return;
    final prompt = rawPrompt.isEmpty ? 'Please analyze the attached image.' : rawPrompt;
    final attachment = _attachedImage;

    setState(() {
      _page = 0;
      _busy = true;
      _messages.add(ChatMessage(isUser: true, text: prompt, attachment: attachment));
      _messages.add(ChatMessage(isUser: false, isLoading: true));
      _composer.clear();
      _attachedImage = null;
    });
    _scrollToBottom();

    if (attachment == null && _isImageGenerationRequest(prompt)) {
      if (!ApiService.isConfigured) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        setState(() {
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last
              ..isLoading = false
              ..text = 'Image-generation request detected. Configure API_BASE_URL to connect Cloudflare Workers AI.';
          }
          _busy = false;
        });
        return;
      }

      try {
        final generated = await _api.generateImage(prompt, conversationId: _activeConversationId);
        final bytes = await _api.downloadGeneratedImage(generated);
        if (!mounted) return;
        setState(() {
          _activeConversationId = generated.conversationId ?? _activeConversationId;
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last
              ..isLoading = false
              ..id = generated.messageId
              ..text = 'Generated image'
              ..generatedImage = generated
              ..generatedImageBytes = bytes;
          }
          _busy = false;
        });
        unawaited(_refreshHistory());
      } catch (error) {
        if (!mounted) return;
        setState(() {
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last
              ..isLoading = false
              ..text = 'Image generation failed: ' + error.toString();
          }
          _busy = false;
        });
      }
      _scrollToBottom();
      return;
    }

    if (ApiService.isConfigured) {
      try {
        await for (final event in _api.streamChat(
          prompt: prompt,
          conversationId: _activeConversationId,
          imageBytes: attachment?.bytes,
          imageMimeType: attachment == null ? null : _mimeTypeForImage(attachment.name),
          model: _model,
          search: _searchOn,
          thinking: _thinkingOn,
        )) {
          if (!mounted) return;
          if (event.type == 'meta') {
            setState(() {
              _activeConversationId = event.conversationId ?? _activeConversationId;
              if (_messages.isNotEmpty && !_messages.last.isUser) {
                _messages.last
                  ..id = event.messageId
                  ..sources = event.sources;
              }
            });
          } else if (event.type == 'token' && event.token != null) {
            setState(() {
              if (_messages.isNotEmpty && !_messages.last.isUser) {
                _messages.last
                  ..isLoading = false
                  ..text += event.token!;
              }
            });
            _scrollToBottom();
          } else if (event.type == 'error') {
            setState(() {
              if (_messages.isNotEmpty && !_messages.last.isUser) {
                final pending = _messages.last;
                pending.isLoading = false;
                if (pending.text.isEmpty) {
                  pending.text = event.error ?? 'The response was interrupted. Please retry.';
                } else {
                  pending.text += '\n\n' + (event.error ?? 'The response was interrupted.');
                }
              }
              _busy = false;
            });
          } else if (event.type == 'done') {
            setState(() {
              if (_messages.isNotEmpty && !_messages.last.isUser) {
                _messages.last
                  ..isLoading = false
                  ..id = event.messageId ?? _messages.last.id;
              }
              _busy = false;
            });
            unawaited(_refreshHistory());
          }
        }

        if (mounted) {
          setState(() {
            if (_messages.isNotEmpty && !_messages.last.isUser) {
              _messages.last.isLoading = false;
            }
            _busy = false;
          });
        }
      } catch (error) {
        if (!mounted) return;
        setState(() {
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            final pending = _messages.last;
            pending.isLoading = false;
            if (pending.text.isEmpty) {
              pending.text = 'Request failed: ' + error.toString();
            } else {
              pending.text += '\n\nResponse interrupted: ' + error.toString();
            }
          }
          _busy = false;
        });
      }
      _scrollToBottom();
      return;
    }

    // UI-only fallback used until API_BASE_URL is supplied at build time.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((message) => message.isLoading);
      _messages.add(ChatMessage(isUser: false, text: _mockReply(prompt)));
      _busy = false;
    });
    _scrollToBottom();
  }

  String _mockReply(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('analyze the attached image') ||
        lower.contains('what is in this image') ||
        lower.contains('what do you see') ||
        lower.contains('describe this image')) {
      return 'Image received in the chat preview. Vision analysis will be powered by a Groq vision model after the backend is connected.';
    }
    if (lower.contains('generate an image') ||
        lower.contains('create an image') ||
        lower.contains('draw') ||
        lower.contains('picture of')) {
      return 'I can help turn that idea into an image. Open Image Generation in the sidebar, describe the scene, and use Generate Image to preview the image-generation flow. Live generation will be connected in the backend phase.';
    }
    if (lower.contains('pdf')) {
      return 'Use the PDF Export section to preview and export a formatted conversation. The PDF control is available in this frontend prototype.';
    }
    if (lower.contains('hello') || lower.contains('hi')) {
      return 'Hello! I’m your AI assistant. Ask me a question, share an image, or describe an image you want to create.';
    }
    return 'Here is a structured preview response to your question:\n\n1. **Understand the goal.** Identify the main task and the information needed.\n2. **Work through it clearly.** Break the problem into small, verifiable steps and explain the key reasoning.\n3. **Check the result.** Review assumptions and calculations before presenting the final conclusion.\n\nThis is sample frontend content. Groq streaming, real-time search, vision, and persistent memory will be wired up in the backend phase.';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messageScroll.hasClients) {
        _messageScroll.animateTo(
          _messageScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _exportPdf() async {
    final document = pw.Document();
    final lines = <pw.Widget>[
      pw.Text(
        'AI Chat - Conversation Export',
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.Text('Exported from the AI Chat frontend preview'),
      pw.SizedBox(height: 18),
    ];

    for (final message in _messages) {
      final label = message.isUser ? 'You' : 'AI Assistant';
      final body = message.isPhysicsSample
          ? 'Step-by-step solution\n\nGiven: u = 20 m/s, g = 9.8 m/s^2\nMaximum height: h = u^2 / (2g) = 400 / 19.6, approximately 20.41 m\nTime to reach the top: t = u / g = 20 / 9.8, approximately 2.04 s\nTotal time in air: T = 2t = 4.08 s\n\nFinal answer: maximum height = 20.41 m; total time = 4.08 s.'
          : message.isLoading
              ? 'Generating response…'
              : message.text;
      lines.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: pdf.PdfColor.fromHex('#DDE5F2')),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              pw.Text(body),
            ],
          ),
        ),
      );
    }

    document.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(36),
        build: (context) => lines,
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => document.save(),
      name: 'ai-chat-export.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final desktop = width >= 1000;
        final showImageRail = width >= 1450 && _page == 0;

        if (desktop) {
          return Scaffold(
            backgroundColor: _canvas,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 248, child: _sidebar()),
                Expanded(child: _currentPage()),
                if (showImageRail) SizedBox(width: 308, child: _imageRail()),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: _canvas,
          appBar: AppBar(
            backgroundColor: _surface,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 0,
            title: Row(
              children: [
                _brandMark(size: 30),
                const SizedBox(width: 9),
                Text(
                  _pageTitle(),
                  style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Toggle theme',
                onPressed: widget.onToggleTheme,
                icon: Icon(widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              ),
              const SizedBox(width: 6),
            ],
          ),
          drawer: Drawer(
            width: 280,
            backgroundColor: _surface,
            child: SafeArea(child: _sidebar(inDrawer: true)),
          ),
          body: _currentPage(),
        );
      },
    );
  }

  String _pageTitle() {
    switch (_page) {
      case 1:
        return 'Search Chats';
      case 2:
        return 'Image Generation';
      case 3:
        return 'PDF Export';
      case 4:
        return 'Settings';
      default:
        return 'AI Chat';
    }
  }

  Widget _brandMark({double size = 34}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: const LinearGradient(
          colors: [Color(0xFF5D8BFF), Color(0xFF8756F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: brandBlue.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.57),
    );
  }

  Widget _sidebar({bool inDrawer = false}) {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 18, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _brandMark(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Chat', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _text)),
                    Text('Your Intelligent Assistant', style: TextStyle(fontSize: 10.5, color: _muted)),
                  ],
                ),
              ),
              if (inDrawer)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 25),
          _navItem(Icons.add_rounded, 'New Chat', 0, primary: true, onTap: _startNewChat),
          const SizedBox(height: 5),
          _navItem(Icons.search_rounded, 'Search Chats', 1, onTap: () => setState(() => _page = 1)),
          _navItem(Icons.image_outlined, 'Image Generation', 2, onTap: () => setState(() => _page = 2)),
          _navItem(Icons.picture_as_pdf_outlined, 'PDF Export', 3, onTap: () => setState(() => _page = 3)),
          _navItem(Icons.settings_outlined, 'Settings', 4, onTap: () => setState(() => _page = 4)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: _line, height: 1),
          ),
          Row(
            children: [
              Text('Recent Chats', style: TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: _muted),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: _recentChats
                  .map(
                    (chat) => InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        _openRecent(chat);
                        if (inDrawer) Navigator.of(context).maybePop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined, size: 16, color: _muted),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                chat,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: _muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.dark ? const Color(0xFF17243A) : const Color(0xFFF4F7FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xFF426B9C),
                  child: Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Guest User', style: TextStyle(color: _text, fontSize: 11, fontWeight: FontWeight.w700)),
                      Text('Local preview', style: TextStyle(color: _muted, fontSize: 10)),
                    ],
                  ),
                ),
                Icon(Icons.logout_rounded, color: _muted, size: 17),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String label,
    int index, {
    bool primary = false,
    required VoidCallback onTap,
  }) {
    final active = primary || _page == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: active ? brandBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 18, color: active ? Colors.white : _muted),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : _text,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _currentPage() {
    switch (_page) {
      case 1:
        return _searchChatsPage();
      case 2:
        return _imageGenerationPage();
      case 3:
        return _pdfPage();
      case 4:
        return _settingsPage();
      default:
        return _chatPage();
    }
  }

  Widget _topBar({bool includeModel = true}) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(color: _surface, border: Border(bottom: BorderSide(color: _line))),
      child: Row(
        children: [
          if (includeModel)
            PopupMenuButton<String>(
              tooltip: 'Select AI model',
              initialValue: _model,
              onSelected: (value) => setState(() => _model = value),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'auto', child: Text('Auto · Recommended')),
                PopupMenuItem(value: 'openai/gpt-oss-20b', child: Text('Groq · GPT-OSS 20B')),
                PopupMenuItem(value: 'openai/gpt-oss-120b', child: Text('Groq · GPT-OSS 120B')),
                PopupMenuItem(value: 'qwen/qwen3.8-27b', child: Text('Groq · Qwen 3.8 Vision')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(10),
                  color: widget.dark ? const Color(0xFF17243A) : Colors.white,
                ),
                child: Row(
                  children: [
                    Icon(Icons.bubble_chart_rounded, size: 16, color: _muted),
                    const SizedBox(width: 7),
                    Text(_modelLabel, style: TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 5),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _muted),
                  ],
                ),
              ),
            ),
          const Spacer(),
          if (_page == 0 && MediaQuery.of(context).size.width >= 560)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: widget.dark ? const Color(0xFF202B42) : const Color(0xFFF1F4FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 13, color: brandBlue),
                  const SizedBox(width: 5),
                  Text('Thinking', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 5),
                  SizedBox(
                    height: 16,
                    width: 29,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: Switch(
                        value: _thinkingOn,
                        onChanged: (value) => setState(() => _thinkingOn = value),
                        activeColor: brandBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: widget.dark ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 19, color: _muted),
          ),
          IconButton(
            tooltip: 'More options',
            onPressed: () => _showInfo('The frontend preview is ready for API integration.'),
            icon: Icon(Icons.more_horiz_rounded, size: 20, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _chatPage() {
    return Column(
      children: [
        _topBar(),
        Expanded(
          child: _messages.isEmpty
              ? _welcomeScreen()
              : ListView.builder(
                  controller: _messageScroll,
                  padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: _messageView(_messages[index]),
                    ),
                  ),
                ),
        ),
        _composerBox(),
      ],
    );
  }

  Widget _welcomeScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [brandBlue, brandPurple]),
                  boxShadow: [
                    BoxShadow(color: brandBlue.withOpacity(0.22), blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 21),
              Text('How can I help you today?', style: TextStyle(color: _text, fontSize: 27, fontWeight: FontWeight.w800)),
              const SizedBox(height: 9),
              Text('Ask a question, solve a problem, or create something new.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 13)),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _suggestion(Icons.functions_rounded, 'Solve a math problem', 'Solve a quadratic equation step by step.'),
                  _suggestion(Icons.lightbulb_outline_rounded, 'Explain a concept', 'Explain quantum mechanics in simple terms.'),
                  _suggestion(Icons.image_outlined, 'Generate an image', 'Create an image of a peaceful mountain lake.'),
                  _suggestion(Icons.travel_explore_rounded, 'Search the web', 'Find the latest updates about renewable energy.'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestion(IconData icon, String title, String prompt) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () {
        _composer.text = prompt;
        _composer.selection = TextSelection.collapsed(offset: prompt.length);
      },
      child: Container(
        width: 235,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(13), border: Border.all(color: _line)),
        child: Row(
          children: [
            Icon(icon, size: 19, color: brandBlue),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _muted, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageView(ChatMessage message) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 570),
          margin: const EdgeInsets.only(bottom: 24, left: 50),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          decoration: BoxDecoration(
            color: widget.dark ? const Color(0xFF1C315A) : const Color(0xFFEAF0FF),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.attachment?.bytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.memory(
                    message.attachment!.bytes!,
                    width: 230,
                    height: 145,
                    fit: BoxFit.cover,
                  ),
                ),
              if (message.attachment != null)
                Padding(
                  padding: const EdgeInsets.only(top: 7, bottom: 4),
                  child: Text(
                    message.attachment!.name,
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                ),
              SelectableText(message.text, style: TextStyle(color: _text, fontSize: 13, height: 1.55)),
            ],
          ),
        ),
      );
    }

    if (message.isLoading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _assistantAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Preparing your answer', style: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(width: 8),
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: brandBlue)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _skeletonLine(width: 290),
                  const SizedBox(height: 8),
                  _skeletonLine(width: 420),
                  const SizedBox(height: 8),
                  _skeletonLine(width: 350),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 27),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _assistantAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('AI Assistant', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text(_modelLabel, style: TextStyle(color: _muted, fontSize: 10)),
                    const Spacer(),
                    Icon(Icons.more_horiz_rounded, size: 18, color: _muted),
                  ],
                ),
                const SizedBox(height: 14),
                if (message.isPhysicsSample) _physicsAnswer() else _plainAnswer(message.text),
                if (message.generatedImageBytes != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      message.generatedImageBytes!,
                      width: 420,
                      height: 300,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => _landscapePlaceholder(),
                    ),
                  ),
                ] else if (message.generatedImage?.imageUrl != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      message.generatedImage!.imageUrl!,
                      width: 420,
                      height: 300,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => _landscapePlaceholder(),
                    ),
                  ),
                ],
                if (message.sources.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: message.sources.map((source) {
                      final title = source['title'] as String? ?? 'Source';
                      final url = source['url'] as String? ?? '';
                      return ActionChip(
                        avatar: const Icon(Icons.open_in_new_rounded, size: 13, color: brandBlue),
                        label: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: _text)),
                        backgroundColor: _surface,
                        side: BorderSide(color: _line),
                        onPressed: () {
                          final target = Uri.tryParse(url);
                          if (target != null && (target.scheme == 'http' || target.scheme == 'https')) {
                            unawaited(launchUrl(target, mode: LaunchMode.externalApplication));
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 13),
                Wrap(
                  spacing: 2,
                  children: [
                    _messageAction(Icons.copy_rounded, 'Copy answer', () {
                      final text = message.isPhysicsSample
                          ? 'Maximum height: 20.41 m. Total time in air: 4.08 s.'
                          : message.text;
                      Clipboard.setData(ClipboardData(text: text));
                      _showInfo('Answer copied.');
                    }),
                    _messageAction(
                      message.feedback == 'like' ? Icons.thumb_up : Icons.thumb_up_outlined,
                      'Like',
                      () => _setFeedback(message, 'like'),
                      active: message.feedback == 'like',
                    ),
                    _messageAction(
                      message.feedback == 'dislike' ? Icons.thumb_down : Icons.thumb_down_outlined,
                      'Dislike',
                      () => _setFeedback(message, 'dislike'),
                      active: message.feedback == 'dislike',
                    ),
                    if (message.generatedImage != null)
                      _messageAction(Icons.download_rounded, 'Download image', () => _downloadMessageImage(message)),
                    _messageAction(Icons.picture_as_pdf_outlined, 'Download PDF', _exportPdf),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _assistantAvatar() {
    return Container(
      width: 29,
      height: 29,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.dark ? const Color(0xFF1B2D52) : const Color(0xFFE8EDFF),
      ),
      child: const Icon(Icons.auto_awesome_rounded, size: 16, color: brandBlue),
    );
  }

  Widget _skeletonLine({double width = 240}) {
    return Container(
      height: 10,
      width: width,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      decoration: BoxDecoration(
        color: widget.dark ? const Color(0xFF202C42) : const Color(0xFFE8EDF5),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _physicsAnswer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step-by-Step Solution', style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 13),
        _numberedHeading('1.', 'Given Data'),
        _bulletText('Mass, m = 2 kg'),
        _bulletText('Initial velocity, u = 20 m/s (upward)'),
        _bulletText('Acceleration due to gravity, g = 9.8 m/s²'),
        const SizedBox(height: 13),
        _numberedHeading('2.', '(a) Maximum Height'),
        Text('At the highest point, final velocity v = 0. Using the equation:', style: TextStyle(color: _text, fontSize: 12, height: 1.55)),
        const SizedBox(height: 9),
        _equationBox('v² = u² − 2gh     →     h = u² / (2g)'),
        const SizedBox(height: 8),
        _equationBox('h = (20)² / (2 × 9.8) = 400 / 19.6 ≈ 20.41 m', highlight: false),
        const SizedBox(height: 13),
        _numberedHeading('3.', '(b) Total Time in the Air'),
        Text('Time to reach the top:', style: TextStyle(color: _text, fontSize: 12, height: 1.5)),
        const SizedBox(height: 7),
        _equationBox('t = u / g = 20 / 9.8 ≈ 2.04 s', highlight: false),
        const SizedBox(height: 7),
        Text('Total time = 2 × 2.04 = 4.08 s', style: TextStyle(color: _text, fontSize: 12, height: 1.5)),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: widget.dark ? const Color(0xFF142647) : const Color(0xFFEEF3FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.dark ? const Color(0xFF294879) : const Color(0xFFDCE6FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Final Answer', style: TextStyle(color: brandBlue, fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text('(a) Maximum height = 20.41 m', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('(b) Total time in the air = 4.08 s', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numberedHeading(String number, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(number, style: const TextStyle(color: brandBlue, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(width: 7),
          Expanded(child: Text(title, style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  Widget _bulletText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(color: _muted, fontSize: 12)),
          Expanded(child: Text(text, style: TextStyle(color: _text, fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }

  Widget _equationBox(String equation, {bool highlight = true}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: highlight
            ? (widget.dark ? const Color(0xFF15243C) : const Color(0xFFF6F8FD))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: highlight ? Border.all(color: _line) : null,
      ),
      child: SelectableText(
        equation,
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'serif', fontSize: 13, color: _text, fontWeight: FontWeight.w600, height: 1.45),
      ),
    );
  }

  Widget _plainAnswer(String text) => _formattedAnswer(text);

  Widget _formattedAnswer(String content) {
    final equationPattern = RegExp(
      r'(\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\)|\$[^$\n]+\$)',
    );
    final matches = equationPattern.allMatches(content).toList();
    if (matches.isEmpty) return _markdownBlock(content);

    final children = <Widget>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        children.add(_markdownBlock(content.substring(offset, match.start)));
      }

      final token = match.group(0) ?? '';
      final isDisplay = token.startsWith(r'$$') || token.startsWith(r'\[');
      var expression = token;
      if (token.startsWith(r'$$')) {
        expression = token.substring(2, token.length - 2);
      } else if (token.startsWith(r'\[') || token.startsWith(r'\(')) {
        expression = token.substring(2, token.length - 2);
      } else if (token.startsWith(r'$')) {
        expression = token.substring(1, token.length - 1);
      }

      try {
        final mathWidget = Math.tex(
          expression,
          mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
          textStyle: TextStyle(fontSize: 14, color: _text),
        );
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: isDisplay ? 8 : 2),
            child: isDisplay
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: mathWidget,
                  )
                : Align(alignment: Alignment.centerLeft, child: mathWidget),
          ),
        );
      } catch (_) {
        children.add(SelectableText(token, style: TextStyle(color: _text, fontSize: 13)));
      }
      offset = match.end;
    }

    if (offset < content.length) {
      children.add(_markdownBlock(content.substring(offset)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _markdownBlock(String data) {
    if (data.trim().isEmpty) return const SizedBox(height: 5);
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: base.copyWith(
        p: TextStyle(color: _text, fontSize: 13, height: 1.7),
        h1: TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w800),
        h2: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w800),
        h3: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w800),
        strong: TextStyle(color: _text, fontWeight: FontWeight.w800),
        em: TextStyle(color: _text, fontStyle: FontStyle.italic),
        a: const TextStyle(color: brandBlue, decoration: TextDecoration.underline),
        code: TextStyle(
          color: _text,
          fontFamily: 'monospace',
          fontSize: 12,
          backgroundColor: widget.dark ? const Color(0xFF202C42) : const Color(0xFFF0F3F9),
        ),
      ),
      onTapLink: (text, href, title) {
        if (href == null) return;
        final target = Uri.tryParse(href);
        if (target != null && (target.scheme == 'http' || target.scheme == 'https')) {
          unawaited(launchUrl(target, mode: LaunchMode.externalApplication));
        }
      },
    );
  }


  Widget _messageAction(IconData icon, String tooltip, VoidCallback onTap, {bool active = false}) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 17,
      style: IconButton.styleFrom(
        foregroundColor: active ? brandBlue : _muted,
        backgroundColor: active ? brandBlue.withOpacity(0.08) : Colors.transparent,
      ),
      icon: Icon(icon),
    );
  }

  Widget _composerBox() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(22, 13, 22, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 9, 8, 8),
                decoration: BoxDecoration(
                  color: widget.dark ? const Color(0xFF101A2C) : Colors.white,
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: widget.dark
                      ? []
                      : [
                          BoxShadow(
                            color: const Color(0xFF263B67).withOpacity(0.045),
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ],
                ),
                child: Column(
                  children: [
                    if (_attachedImage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                        decoration: BoxDecoration(
                          color: widget.dark ? const Color(0xFF17243A) : const Color(0xFFF3F6FD),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _line),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.image_outlined, color: brandBlue, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _attachedImage!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: _text, fontSize: 10.5),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove image',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() => _attachedImage = null),
                              icon: Icon(Icons.close_rounded, size: 16, color: _muted),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      onSubmitted: (_) => _sendMessage(),
                      style: TextStyle(color: _text, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Type your message here…',
                        hintStyle: TextStyle(color: _muted, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 7),
                      ),
                    ),
                    Row(
                      children: [
                        _composerTool(Icons.attach_file_rounded, 'Attach image', _pickImage),
                        _composerTool(Icons.image_outlined, 'Generate image', () => setState(() => _page = 2)),
                        _composerTool(Icons.travel_explore_rounded, _searchOn ? 'Disable web search' : 'Enable web search', () => setState(() => _searchOn = !_searchOn), active: _searchOn),
                        const SizedBox(width: 5),
                        Flexible(
                          child: PopupMenuButton<String>(
                          tooltip: 'Model selector',
                          onSelected: (value) => setState(() => _model = value),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'auto', child: Text('Auto · Recommended')),
                            PopupMenuItem(value: 'openai/gpt-oss-20b', child: Text('Groq · GPT-OSS 20B')),
                            PopupMenuItem(value: 'openai/gpt-oss-120b', child: Text('Groq · GPT-OSS 120B')),
                            PopupMenuItem(value: 'qwen/qwen3.8-27b', child: Text('Groq · Qwen 3.8 Vision')),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: widget.dark ? const Color(0xFF1C2A43) : const Color(0xFFF4F6FB),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.bubble_chart_rounded, color: _muted, size: 14),
                                const SizedBox(width: 5),
                                Flexible(child: Text(_modelShortLabel, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: _muted))),
                                Icon(Icons.keyboard_arrow_down_rounded, color: _muted, size: 14),
                              ],
                            ),
                          ),
                        )),
                        const Spacer(),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            gradient: const LinearGradient(colors: [brandBlue, brandPurple]),
                          ),
                          child: IconButton(
                            tooltip: 'Send message',
                            onPressed: _busy ? null : _sendMessage,
                            padding: EdgeInsets.zero,
                            icon: Icon(_busy ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded, size: 19, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchOn
                    ? 'Web search preview is enabled · Live provider connection comes later'
                    : 'AI can make mistakes. Check important information.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composerTool(IconData icon, String tooltip, VoidCallback onTap, {bool active = false}) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 17,
      style: IconButton.styleFrom(
        foregroundColor: active ? brandBlue : _muted,
        backgroundColor: active ? brandBlue.withOpacity(0.09) : Colors.transparent,
        padding: const EdgeInsets.all(8),
      ),
      icon: Icon(icon),
    );
  }

  Widget _imageRail() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(17),
      ),
      child: _imagePanelContent(rail: true),
    );
  }

  Widget _imagePanelContent({bool rail = false}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: const LinearGradient(colors: [brandPurple, brandBlue]),
                ),
                child: const Icon(Icons.image_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 9),
              Expanded(child: Text('Image Generation', style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w800))),
              if (rail)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4E9), borderRadius: BorderRadius.circular(7)),
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_rounded, size: 12, color: Color(0xFFF08B2D)),
                      SizedBox(width: 4),
                      Text('Cloudflare AI', style: TextStyle(color: Color(0xFF89521F), fontSize: 9, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 17),
          TextField(
            controller: _imagePrompt,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(fontSize: 11.5, height: 1.5, color: _text),
            decoration: InputDecoration(
              hintText: 'Describe the image you want to create…',
              hintStyle: TextStyle(color: _muted, fontSize: 11),
              filled: true,
              fillColor: widget.dark ? const Color(0xFF0C1527) : const Color(0xFFFAFBFE),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: _line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: _line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: brandBlue)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              onPressed: _generatingImage ? null : _generateImage,
              style: FilledButton.styleFrom(
                backgroundColor: brandPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _generatingImage
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text(_generatingImage ? 'Generating preview…' : 'Generate Image', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _imageReady
                  ? (_generatedImageBytes != null
                      ? Image.memory(
                          _generatedImageBytes!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => _landscapePlaceholder(),
                        )
                      : (_generatedImageUrl != null
                          ? Image.network(
                              _generatedImageUrl!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => _landscapePlaceholder(),
                            )
                          : Image.network(
                              landscapeUrl,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => _landscapePlaceholder(),
                            )))
                  : Container(
                      color: widget.dark ? const Color(0xFF17243A) : const Color(0xFFF1F4FD),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: brandBlue),
                            const SizedBox(height: 12),
                            Text('Preparing your image…', style: TextStyle(color: _muted, fontSize: 11)),
                            const SizedBox(height: 6),
                            Text('This is a UI preview', style: TextStyle(color: _muted, fontSize: 9)),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloadImage,
                  icon: const Icon(Icons.download_rounded, size: 15),
                  label: const Text('Download', style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(foregroundColor: _text, side: BorderSide(color: _line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generateImage,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Regenerate', style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(foregroundColor: _text, side: BorderSide(color: _line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                ),
              ),
            ],
          ),
          if (!rail) const SizedBox(height: 14),
          if (!rail) Text('Prompt tips', style: TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 12)),
          if (!rail)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Describe the subject, lighting, style, and composition for a more specific result.', style: TextStyle(color: _muted, height: 1.5, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _landscapePlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB9DAFA), Color(0xFF789FCC), Color(0xFF27476F)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: const Alignment(0, -0.05),
            child: Icon(Icons.landscape_rounded, size: 130, color: Colors.white.withOpacity(0.72)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(height: 75, color: const Color(0xFF173B51).withOpacity(0.35)),
          ),
          const Positioned(
            left: 12,
            bottom: 12,
            child: Text('Mountain lake · Image preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _imageGenerationPage() {
    return Column(
      children: [
        _topBar(includeModel: false),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              if (narrow) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(height: 470, child: _imagePanelContent()),
                      const SizedBox(height: 16),
                      SizedBox(height: 500, child: _imagePreviewCard()),
                    ],
                  ),
                );
              }

              return SizedBox(
                height: constraints.maxHeight,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1050),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 4, child: _imagePanelContent()),
                        const SizedBox(width: 20),
                        Expanded(flex: 5, child: _imagePreviewCard()),
                      ],
                    ),
                  ),
                ),
              ),
            );
            },
          ),
        ),
      ],
    );
  }

  Widget _imagePreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your generated image', style: TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 5),
          Text('Preview image output and download controls', style: TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                landscapeUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stack) => _landscapePlaceholder(),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showInfo('Download will be enabled when image storage is connected.'),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download image'),
              ),
              FilledButton.icon(
                onPressed: () => _showInfo('Real image generation will be wired to Cloudflare Workers AI.'),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Regenerate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchChatsPage() {
    return Column(
      children: [
        _topBar(includeModel: false),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Search your conversations', style: TextStyle(color: _text, fontSize: 23, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Find a past question or return to an earlier topic.', style: TextStyle(color: _muted, fontSize: 12)),
                    const SizedBox(height: 22),
                    TextField(
                      onChanged: (value) => setState(() => _chatSearchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'Search chats…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: _surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: _line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: _line)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: ListView(
                        children: _recentChats.where((title) => title.toLowerCase().contains(_chatSearchQuery.toLowerCase())).map((title) {
                          return Card(
                            elevation: 0,
                            color: _surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: BorderSide(color: _line)),
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: widget.dark ? const Color(0xFF1E2E4A) : const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(11)),
                                child: const Icon(Icons.forum_outlined, color: brandBlue),
                              ),
                              title: Text(title, style: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 12)),
                              subtitle: Text('Saved conversation · Local preview', style: TextStyle(color: _muted, fontSize: 10)),
                              trailing: Icon(Icons.chevron_right_rounded, color: _muted),
                              onTap: () => _openRecent(title),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pdfPage() {
    return Column(
      children: [
        _topBar(includeModel: false),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 720;
              if (narrow) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(height: 380, child: _pdfExportCard()),
                      const SizedBox(height: 16),
                      SizedBox(height: 500, child: _pdfPreviewCard()),
                    ],
                  ),
                );
              }

              return SizedBox(
                height: constraints.maxHeight,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: _pdfExportCard()),
                        const SizedBox(width: 20),
                        Expanded(flex: 4, child: _pdfPreviewCard()),
                      ],
                    ),
                  ),
                ),
              ),
            );
            },
          ),
        ),
      ],
    );
  }

  Widget _pdfExportCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE85A7A), size: 32),
          const SizedBox(height: 16),
          Text('Export chat as PDF', style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Save a clean copy of this answer or the whole conversation.', style: TextStyle(color: _muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 20),
          _featureLine(Icons.description_outlined, 'Readable headings and paragraphs'),
          _featureLine(Icons.functions_rounded, 'Step-by-step solution content'),
          _featureLine(Icons.file_download_outlined, 'Print, save, or share PDF'),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _exportPdf,
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('Export conversation to PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('PDF is generated locally in this frontend preview.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 9.5)),
        ],
      ),
    );
  }

  Widget _pdfPreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: widget.dark ? const Color(0xFF101827) : const Color(0xFFE9EEF7),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(22),
      child: Center(
        child: AspectRatio(
          aspectRatio: 0.76,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, color: brandBlue, size: 16),
                  SizedBox(width: 6),
                  Text('AI Chat Export', style: TextStyle(color: Color(0xFF17233B), fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 16),
                const Text('Physics Problem Solution', style: TextStyle(color: Color(0xFF17233B), fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 9),
                const Text('Given data', style: TextStyle(color: Color(0xFF4268F6), fontWeight: FontWeight.w700, fontSize: 10)),
                const SizedBox(height: 5),
                const Text('u = 20 m/s\ng = 9.8 m/s²', style: TextStyle(color: Color(0xFF34445F), fontSize: 9, height: 1.5)),
                const SizedBox(height: 12),
                const Text('Maximum height', style: TextStyle(color: Color(0xFF4268F6), fontWeight: FontWeight.w700, fontSize: 10)),
                const SizedBox(height: 5),
                const Text('h = u² / (2g)\n  = 400 / 19.6\n  ≈ 20.41 m', style: TextStyle(color: Color(0xFF34445F), fontSize: 9, height: 1.6)),
                const SizedBox(height: 12),
                const Text('Final answer', style: TextStyle(color: Color(0xFF4268F6), fontWeight: FontWeight.w700, fontSize: 10)),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: const Color(0xFFEEF3FF), borderRadius: BorderRadius.circular(7)),
                  child: const Text('Maximum height: 20.41 m\nTotal time: 4.08 s', style: TextStyle(color: Color(0xFF17233B), fontSize: 9, height: 1.5)),
                ),
                const Spacer(),
                const Divider(color: Color(0xFFE5EAF3)),
                const Text('Generated from your conversation', style: TextStyle(color: Color(0xFF8B97AB), fontSize: 7.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _featureLine(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: brandBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: _text, fontSize: 11.5))),
        ],
      ),
    );
  }

  Widget _settingsPage() {
    return Column(
      children: [
        _topBar(includeModel: false),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(26),
                children: [
                  Text('Settings', style: TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  Text('Make AI Chat feel right for you.', style: TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 21),
                  _settingsCard(
                    title: 'Appearance',
                    icon: Icons.palette_outlined,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Theme', style: TextStyle(color: _text, fontSize: 12))),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, icon: Icon(Icons.light_mode_outlined, size: 16), label: Text('Light')),
                              ButtonSegment(value: true, icon: Icon(Icons.dark_mode_outlined, size: 16), label: Text('Dark')),
                            ],
                            selected: {widget.dark},
                            onSelectionChanged: (values) {
                              if (values.first != widget.dark) widget.onToggleTheme();
                            },
                            showSelectedIcon: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _settingRow('Language', 'Auto-detect'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _settingsCard(
                    title: 'Chat Behavior',
                    icon: Icons.chat_bubble_outline_rounded,
                    children: [
                      _toggleRow('Show thinking status', _thinkingOn, (value) => setState(() => _thinkingOn = value)),
                      _toggleRow('Show web search badge', _searchOn, (value) => setState(() => _searchOn = value)),
                      _toggleRow('Auto-save chat history', true, (value) => _showInfo('Persistent save will be connected to MongoDB later.')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _settingsCard(
                    title: 'AI Models',
                    icon: Icons.hub_outlined,
                    children: [
                      _settingRow('Current model', _model),
                      const SizedBox(height: 8),
                      Text('Model selection is a UI preview until Groq is connected.', style: TextStyle(color: _muted, fontSize: 10.5)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _settingsCard(
                    title: 'About',
                    icon: Icons.info_outline_rounded,
                    children: [
                      _settingRow('Application', 'AI Chat Flutter'),
                      _settingRow('Storage', 'Local preview'),
                      _settingRow('Backend', 'Not connected yet'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: _surface, border: Border.all(color: _line), borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: brandBlue, size: 18),
              const SizedBox(width: 9),
              Text(title, style: TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _settingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: _text, fontSize: 11.5))),
          Text(value, style: TextStyle(color: _muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: _text, fontSize: 11.5))),
          Switch.adaptive(value: value, onChanged: onChanged, activeColor: brandBlue),
        ],
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
