import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';

import 'services/xai_ocr_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // If .env is missing in dev, continue; service will throw if key is missing
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fiş Okuyucu',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const OcrHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class OcrHomePage extends StatefulWidget {
  const OcrHomePage({super.key});

  @override
  State<OcrHomePage> createState() => _OcrHomePageState();
}

class _OcrHomePageState extends State<OcrHomePage> {
  final XaiOcrService _service = XaiOcrService();
  final ImagePicker _picker = ImagePicker();

  File? _imageFile;
  String? _ocrText;
  Map<String, dynamic>? _ocrJson;
  String? _errorMessage;
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _errorMessage = null;
      _ocrText = null;
      _ocrJson = null;
      _isLoading = true;
    });
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 95);
      if (picked == null) {
        setState(() => _isLoading = false);
        return;
      }

      final file = File(picked.path);
      setState(() => _imageFile = file);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _extractPlainText() async {
    if (_imageFile == null) return;
    setState(() {
      _errorMessage = null;
      _ocrText = null;
      _ocrJson = null;
      _isLoading = true;
    });
    try {
      final text = await _service.extractTextFromImage(_imageFile!);
      setState(() => _ocrText = text);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _extractJson() async {
    if (_imageFile == null) return;
    setState(() {
      _errorMessage = null;
      _ocrText = null;
      _ocrJson = null;
      _isLoading = true;
    });
    try {
      final data = await _service.extractReceiptJsonFromImage(_imageFile!);
      setState(() => _ocrJson = data);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Kopyalandı')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fiş Okuyucu')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo),
                      label: const Text('Galeriden Seç'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Kamera'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_imageFile != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _isLoading ? null : _extractPlainText,
                        child: const Text('Metin Çıkart'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _isLoading ? null : _extractJson,
                        child: const Text('JSON Formatında Çıkart'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_imageFile != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(_imageFile!, fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_isLoading) ...[
                        const Center(child: CircularProgressIndicator()),
                      ] else if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ] else if (_ocrText != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Çıkarılan Metin:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              tooltip: 'Kopyala',
                              icon: const Icon(Icons.copy),
                              onPressed: () => _copyToClipboard(_ocrText!),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(_ocrText!),
                      ] else if (_ocrJson != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'JSON Çıktısı:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Builder(
                              builder: (context) {
                                final pretty = JsonEncoder.withIndent(
                                  '  ',
                                ).convert(_ocrJson);
                                return IconButton(
                                  tooltip: 'Kopyala',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () => _copyToClipboard(pretty),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          JsonEncoder.withIndent('  ').convert(_ocrJson),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ] else
                        ...[],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
