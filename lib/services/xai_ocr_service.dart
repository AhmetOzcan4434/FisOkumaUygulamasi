import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class XaiOcrService {
  XaiOcrService();

  String get _apiKey => dotenv.env['XAI_API_KEY']?.trim() ?? '';
  String get _baseUrl =>
      dotenv.env['XAI_BASE_URL']?.trim() ??
      'https://api.x.ai/v1/chat/completions';
  String get _model => dotenv.env['XAI_MODEL']?.trim() ?? 'grok-4-latest';
  String get _visionModel {
    // Prefer explicit vision model if provided
    final envVision = dotenv.env['XAI_VISION_MODEL']?.trim();
    if (envVision != null && envVision.isNotEmpty) return envVision;

    // If XAI_MODEL already points to a vision-capable model, use it
    final lower = _model.toLowerCase();
    if (lower.contains('vision') || lower.contains('grok-3')) {
      return _model;
    }

    // Safe default known to support image inputs
    return 'grok-3';
  }

  /// Extracts text from the given [imageFile] by sending it to xAI Grok as a
  /// multimodal chat completion request.
  /// Returns plain text content from the first choice.
  Future<String> extractTextFromImage(
    File imageFile, {
    String? instruction,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError('XAI_API_KEY is not set. Define it in .env');
    }

    final bytes = await imageFile.readAsBytes();
    final mime = _inferMimeType(imageFile.path);
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

    final uri = Uri.parse(_baseUrl);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };

    final systemPrompt = instruction?.trim().isNotEmpty == true
        ? instruction!.trim()
        : 'You are an OCR assistant. Extract all readable text from the image and return only the text.';

    final body = <String, dynamic>{
      'model': _visionModel,
      'messages': [
        {
          'role': 'system',
          'content': [
            {'type': 'text', 'text': systemPrompt},
          ],
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text':
                  'Extract text from this image and return plain UTF-8 text only.',
            },
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ],
      'stream': false,
      'temperature': 0,
    };

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('xAI error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    // Typical structure: { choices: [ { message: { content: '...' } } ] }
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      if (message != null) {
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content.trim();
        }
        // Some providers may return an array of content parts
        if (content is List && content.isNotEmpty) {
          final buffer = StringBuffer();
          for (final part in content) {
            if (part is Map &&
                part['type'] == 'output_text' &&
                part['text'] is String) {
              buffer.write(part['text']);
            } else if (part is Map &&
                part['type'] == 'text' &&
                part['text'] is String) {
              buffer.write(part['text']);
            }
          }
          final aggregated = buffer.toString().trim();
          if (aggregated.isNotEmpty) return aggregated;
        }
      }
    }

    // Fallback to raw JSON string if we cannot parse expected shape
    return response.body;
  }

  /// Extracts structured receipt-like information from the given [imageFile].
  /// Returns a map matching the schema:
  /// {
  ///   "belge_numarasi": String,
  ///   "harcama_tutari": double,
  ///   "para_birimi": String,
  ///   "kdv_tutari": double,
  ///   "urunler": [ { "ad": String, "adet": double, "birim_fiyat": double } ]
  /// }
  /// Missing values are coerced to empty string for strings, 0.0 for numbers, and [] for lists.
  Future<Map<String, dynamic>> extractReceiptJsonFromImage(
    File imageFile,
  ) async {
    if (_apiKey.isEmpty) {
      throw StateError('XAI_API_KEY is not set. Define it in .env');
    }

    final bytes = await imageFile.readAsBytes();
    final mime = _inferMimeType(imageFile.path);
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

    final uri = Uri.parse(_baseUrl);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };

    final instruction =
        'You are a precise information extraction system. Extract receipt/invoice information and return STRICT JSON only with this exact schema: '
        '{"belge_numarasi": string, "harcama_tutari": number, "para_birimi": string, "kdv_tutari": number, "urunler": [{"ad": string, "adet": number, "birim_fiyat": number}]}. '
        'Rules: 1) Respond with JSON only, no prose. 2) Use numbers (not strings) for numeric fields. 3) If a value is missing or unreadable, use empty string for strings, 0 for numbers, and [] for the list. 4) Do not add extra keys. 5), kdv_tutari is the VAT amount.';

    final body = <String, dynamic>{
      'model': _visionModel,
      'messages': [
        {
          'role': 'system',
          'content': [
            {'type': 'text', 'text': instruction},
          ],
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text':
                  'Extract and return only JSON for this image according to the schema.',
            },
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ],
      'stream': false,
      'temperature': 0,
    };

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('xAI error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    String? contentStr;
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      if (message != null) {
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          contentStr = content.trim();
        } else if (content is List && content.isNotEmpty) {
          final buffer = StringBuffer();
          for (final part in content) {
            if (part is Map &&
                part['type'] == 'output_text' &&
                part['text'] is String) {
              buffer.write(part['text']);
            } else if (part is Map &&
                part['type'] == 'text' &&
                part['text'] is String) {
              buffer.write(part['text']);
            }
          }
          final aggregated = buffer.toString().trim();
          if (aggregated.isNotEmpty) contentStr = aggregated;
        }
      }
    }

    final parsed = _tryParseReceiptJson(contentStr ?? response.body);
    return _coerceToReceiptSchema(parsed);
  }

  Map<String, dynamic> _tryParseReceiptJson(String text) {
    // Prefer fenced code block content if present
    final fenceRegex = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      multiLine: true,
    );
    final fenceMatch = fenceRegex.firstMatch(text);
    String candidate = text.trim();
    if (fenceMatch != null && fenceMatch.groupCount >= 1) {
      candidate = fenceMatch.group(1)!.trim();
    } else {
      // Fallback: extract first JSON object heuristically
      final start = candidate.indexOf('{');
      final end = candidate.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        candidate = candidate.substring(start, end + 1);
      }
    }
    try {
      final obj = jsonDecode(candidate);
      if (obj is Map<String, dynamic>) return obj;
      if (obj is Map) return obj.cast<String, dynamic>();
    } catch (_) {
      // ignore and fall through
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _coerceToReceiptSchema(Map<String, dynamic> input) {
    String asString(dynamic v) => (v is String) ? v : '';
    double asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        return parsed ?? 0.0;
      }
      return 0.0;
    }

    final List<dynamic> rawItems = (input['urunler'] is List)
        ? input['urunler'] as List
        : const [];
    final List<Map<String, dynamic>> items = rawItems.map((e) {
      final map = (e is Map) ? e.cast<String, dynamic>() : <String, dynamic>{};
      return <String, dynamic>{
        'ad': asString(map['ad']),
        'adet': asDouble(map['adet']),
        'birim_fiyat': asDouble(map['birim_fiyat']),
      };
    }).toList();

    return <String, dynamic>{
      'belge_numarasi': asString(input['belge_numarasi']),
      'harcama_tutari': asDouble(input['harcama_tutari']),
      'para_birimi': asString(input['para_birimi']),
      'kdv_tutari': asDouble(input['kdv_tutari']),
      'urunler': items,
    };
  }

  String _inferMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'application/octet-stream';
  }
}
