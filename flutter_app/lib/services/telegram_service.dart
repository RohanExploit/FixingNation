import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sends Telegram notifications via @vishwaguru_bot when a civic issue
/// is submitted. Fire-and-forget — never blocks the submission flow.
///
/// Setup:
///   1. Add @vishwaguru_bot to your Telegram group
///   2. Send a message in the group
///   3. Visit: https://api.telegram.org/bot<TOKEN>/getUpdates
///   4. Copy the chat "id" (negative number) into kTelegramChatId below
class TelegramService {
  static const _token  = '8493507107:AAF6EtBErAgA1J9_WOumQT5qOdIQxlvE2wI';
  static const _apiUrl = 'https://api.telegram.org/bot$_token/sendMessage';

  // ── Configure this ────────────────────────────────────────────────────────
  // Replace with your group/channel chat ID (negative number for groups).
  // e.g.  static const _chatId = '-1002345678901';
  static const _chatId = '1990648223';
  // ─────────────────────────────────────────────────────────────────────────

  /// Send a new-issue alert. Fire-and-forget — errors are logged only.
  static void notifyNewIssue({
    required String title,
    required String category,
    required String city,
    required String description,
    required double lat,
    required double lng,
    required String postId,
  }) {
    if (_chatId == 'REPLACE_WITH_CHAT_ID') {
      debugPrint('[Telegram] Chat ID not configured — skipping notification.');
      return;
    }

    // ignore: discarded_futures
    _send(_buildMessage(
      title:       title,
      category:    category,
      city:        city,
      description: description,
      lat:         lat,
      lng:         lng,
      postId:      postId,
    ));
  }

  static String _buildMessage({
    required String title,
    required String category,
    required String city,
    required String description,
    required double lat,
    required double lng,
    required String postId,
  }) {
    final categoryLabel = category
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    final cityLabel = '${city[0].toUpperCase()}${city.substring(1)}';
    final mapsUrl   = 'https://maps.google.com/?q=$lat,$lng';
    final shortDesc = description.length > 200
        ? '${description.substring(0, 200)}…'
        : description;

    return '''
🚨 *New Civic Issue Reported*
━━━━━━━━━━━━━━━━━━━━
📋 *Title:* ${_escape(title)}
🏷 *Category:* $categoryLabel
🏙 *City:* $cityLabel
📝 *Description:* ${_escape(shortDesc)}
📍 *Location:* [View on Maps]($mapsUrl)
━━━━━━━━━━━━━━━━━━━━
🔖 ID: `$postId`
✅ Status: Under Review
''';
  }

  static Future<void> _send(String text) async {
    try {
      final res = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id':    _chatId,
          'text':       text,
          'parse_mode': 'Markdown',
          'disable_web_page_preview': false,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('[Telegram] Notification failed (${res.statusCode}): ${res.body}');
      } else {
        debugPrint('[Telegram] Notification sent successfully.');
      }
    } catch (e) {
      debugPrint('[Telegram] Notification error: $e');
    }
  }

  /// Escape special Markdown characters for Telegram.
  static String _escape(String text) =>
      text.replaceAll('_', '\\_').replaceAll('*', '\\*').replaceAll('`', '\\`');
}
