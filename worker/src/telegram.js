/**
 * telegram.js — @vishwaguru_bot webhook handler
 *
 * Submission flow (user → bot):
 *   /report → title → description → category (keyboard) → city (keyboard)
 *           → location pin → photo (or /skip) → submitted for review
 *
 * Approval flow (owner → bot):
 *   Bot sends formatted card to TELEGRAM_OWNER_CHAT_ID with ✅ Approve / ❌ Deny
 *   On Approve → Firestore document created → post appears in app feed
 *   On Deny    → submitter notified
 *
 * Required env:
 *   TELEGRAM_BOT_TOKEN       (secret)
 *   TELEGRAM_OWNER_CHAT_ID   (var)
 *   FIREBASE_SERVICE_ACCOUNT (secret)
 *   FIREBASE_PROJECT_ID      (var)
 *   PENDING_SUBMISSIONS      (KV namespace binding)
 */

import { getFirebaseAccessToken } from './auth.js';
import { createDocument }         from './firestore.js';

// ── Constants ────────────────────────────────────────────────────────────────

const CITIES = [
  { value: 'pune',      label: 'Pune'      },
  { value: 'mumbai',    label: 'Mumbai'    },
  { value: 'bangalore', label: 'Bangalore' },
];

const CATEGORIES = [
  { value: 'road_damage',  label: 'Road Damage'   },
  { value: 'garbage',      label: 'Garbage'       },
  { value: 'electricity',  label: 'Electricity'   },
  { value: 'water',        label: 'Water'         },
  { value: 'safety',       label: 'Public Safety' },
  { value: 'corruption',   label: 'Corruption'    },
  { value: 'other',        label: 'Other'         },
];

// ── Entry point ──────────────────────────────────────────────────────────────

export async function handleTelegramWebhook(request, env) {
  let update;
  try {
    update = await request.json();
  } catch {
    return new Response('Bad Request', { status: 400 });
  }

  const ctx = {
    token:       env.TELEGRAM_BOT_TOKEN,
    ownerChatId: String(env.TELEGRAM_OWNER_CHAT_ID || '1990648223'),
    kv:          env.PENDING_SUBMISSIONS,
    env,
  };

  try {
    if (update.callback_query) {
      await handleCallbackQuery(update.callback_query, ctx);
      await tgCall(ctx.token, 'answerCallbackQuery', {
        callback_query_id: update.callback_query.id,
      });
    } else if (update.message) {
      await handleMessage(update.message, ctx);
    }
  } catch (err) {
    console.error('[telegram] Unhandled error:', err.message);
  }

  return new Response('OK');
}

// ── Message handler ──────────────────────────────────────────────────────────

async function handleMessage(msg, ctx) {
  const chatId = String(msg.chat.id);
  const text   = (msg.text || '').trim();

  // ── Commands ──
  if (text === '/start' || text === '/help') {
    await clearState(ctx.kv, chatId);
    await send(ctx.token, chatId,
      '👋 Welcome to *FixingNation Bot*\\!\n\n' +
      'Report a civic issue and get it reviewed for posting on the public feed\\.\n\n' +
      'Tap /report to start\\.'
    );
    return;
  }

  if (text === '/report') {
    await setState(ctx.kv, chatId, {
      step: 'waiting_title',
      data: {
        submitterChatId: chatId,
        submitterName:
          [msg.from?.first_name, msg.from?.last_name].filter(Boolean).join(' ') ||
          'Anonymous',
      },
    });
    await send(ctx.token, chatId,
      '📋 *Step 1 / 5* — What is the *title* of the issue?\n\n' +
      '_Example: Large pothole on MG Road_'
    );
    return;
  }

  if (text === '/cancel') {
    await clearState(ctx.kv, chatId);
    await send(ctx.token, chatId, '❌ Report cancelled\\. Send /report to start again\\.');
    return;
  }

  // ── Conversation steps ──
  const state = await getState(ctx.kv, chatId);

  switch (state.step) {
    case 'waiting_title': {
      if (text.length < 5) {
        await send(ctx.token, chatId, '⚠️ Title is too short\\. Please be more descriptive\\.');
        return;
      }
      state.data.title = text.slice(0, 200);
      state.step = 'waiting_description';
      await setState(ctx.kv, chatId, state);
      await send(ctx.token, chatId,
        '📝 *Step 2 / 5* — Describe the issue in detail\\.\n\n' +
        '_What exactly is the problem? How long has it been there?_'
      );
      break;
    }

    case 'waiting_description': {
      if (text.length < 10) {
        await send(ctx.token, chatId, '⚠️ Description is too short\\. Please provide more detail\\.');
        return;
      }
      state.data.description = text.slice(0, 1000);
      state.step = 'waiting_category';
      await setState(ctx.kv, chatId, state);
      await tgCall(ctx.token, 'sendMessage', {
        chat_id:      chatId,
        text:         '🏷 *Step 3 / 5* — Select the *category*:',
        parse_mode:   'MarkdownV2',
        reply_markup: {
          inline_keyboard: [
            CATEGORIES.slice(0, 3).map(c => ({ text: c.label, callback_data: `cat:${c.value}` })),
            CATEGORIES.slice(3, 6).map(c => ({ text: c.label, callback_data: `cat:${c.value}` })),
            [{ text: CATEGORIES[6].label, callback_data: `cat:${CATEGORIES[6].value}` }],
          ],
        },
      });
      break;
    }

    case 'waiting_location': {
      if (msg.location) {
        const { latitude: lat, longitude: lng } = msg.location;
        state.data.lat     = lat;
        state.data.lng     = lng;
        state.data.geohash = encodeGeohash(lat, lng);
        state.step         = 'waiting_photo';
        await setState(ctx.kv, chatId, state);
        await send(ctx.token, chatId,
          '📸 *Step 5 / 5* — Send a *photo* of the issue, or type /skip to submit without one\\.'
        );
      } else {
        await send(ctx.token, chatId,
          '📍 Please share your location using Telegram\'s 📎 attachment menu → *Location*\\.'
        );
      }
      break;
    }

    case 'waiting_photo': {
      if (text === '/skip' || msg.photo) {
        if (msg.photo) {
          // Pick the largest available resolution
          state.data.photoFileId = msg.photo[msg.photo.length - 1].file_id;
        }
        await sendForOwnerReview(state.data, ctx);
        await clearState(ctx.kv, chatId);
      } else {
        await send(ctx.token, chatId,
          '📸 Please send a photo, or type /skip to submit without one\\.'
        );
      }
      break;
    }

    default:
      await send(ctx.token, chatId,
        'Send /report to report a new issue, or /help for more info\\.'
      );
  }
}

// ── Callback query handler ───────────────────────────────────────────────────

async function handleCallbackQuery(cbq, ctx) {
  const data        = cbq.data || '';
  const fromId      = String(cbq.from.id);
  const msgChatId   = String(cbq.message.chat.id);
  const msgId       = cbq.message.message_id;

  // ── Category selection (submitter) ──
  if (data.startsWith('cat:')) {
    const category = data.slice(4);
    const state    = await getState(ctx.kv, fromId);
    if (state.step !== 'waiting_category') return;

    const catLabel = CATEGORIES.find(c => c.value === category)?.label || category;
    state.data.category = category;
    state.step          = 'waiting_city';
    await setState(ctx.kv, fromId, state);

    // Update the keyboard message
    await tgCall(ctx.token, 'editMessageText', {
      chat_id:    fromId,
      message_id: msgId,
      text:       `🏷 Category: *${escMd(catLabel)}* ✅`,
      parse_mode: 'MarkdownV2',
    });

    // Show city keyboard
    await tgCall(ctx.token, 'sendMessage', {
      chat_id:      fromId,
      text:         '🏙 *Step 4 / 5* — Select your *city*:',
      parse_mode:   'MarkdownV2',
      reply_markup: {
        inline_keyboard: [
          CITIES.map(c => ({ text: c.label, callback_data: `city:${c.value}` })),
        ],
      },
    });
    return;
  }

  // ── City selection (submitter) ──
  if (data.startsWith('city:')) {
    const city  = data.slice(5);
    const state = await getState(ctx.kv, fromId);
    if (state.step !== 'waiting_city') return;

    const cityLabel = CITIES.find(c => c.value === city)?.label || city;
    state.data.city = city;
    state.step      = 'waiting_location';
    await setState(ctx.kv, fromId, state);

    await tgCall(ctx.token, 'editMessageText', {
      chat_id:    fromId,
      message_id: msgId,
      text:       `🏙 City: *${escMd(cityLabel)}* ✅`,
      parse_mode: 'MarkdownV2',
    });

    await send(ctx.token, fromId,
      '📍 *Step 4\\.5 / 5* — Share your *location*\\.\n\n' +
      'Tap 📎 → *Location* in the attachment menu\\.'
    );
    return;
  }

  // ── Owner: Approve ──
  if (data.startsWith('approve:')) {
    if (fromId !== ctx.ownerChatId) return; // only owner can approve

    const subId = data.slice(8);
    const sub   = await getSub(ctx.kv, subId);

    if (!sub) {
      await tgCall(ctx.token, 'sendMessage', {
        chat_id: msgChatId,
        text:    `⚠️ Submission \`${subId.slice(0, 8)}…\` not found \\(may have expired\\)\\.`,
        parse_mode: 'MarkdownV2',
      });
      return;
    }

    try {
      const photoUrl = sub.photoFileId
        ? await getTelegramFileUrl(ctx.token, sub.photoFileId)
        : null;

      const postId = await createFirestorePost(ctx.env, {
        ...sub,
        mediaUrls: photoUrl ? [photoUrl] : [],
      });

      await ctx.kv.delete(`sub:${subId}`);

      // Edit owner message
      await editApprovalMessage(ctx.token, msgChatId, msgId, sub.photoFileId,
        `✅ *APPROVED* — \`${postId}\``
      );

      // Notify submitter
      await send(ctx.token, sub.submitterChatId,
        `✅ Your issue "*${escMd(sub.title)}*" has been approved and is now live on FixingNation\\!`
      );
    } catch (err) {
      console.error('[telegram] Firestore create failed:', err.message);
      await send(ctx.token, msgChatId, `❌ Error creating post: ${escMd(err.message)}`);
    }
    return;
  }

  // ── Owner: Deny ──
  if (data.startsWith('deny:')) {
    if (fromId !== ctx.ownerChatId) return;

    const subId = data.slice(5);
    const sub   = await getSub(ctx.kv, subId);

    if (!sub) return;

    await ctx.kv.delete(`sub:${subId}`);

    await editApprovalMessage(ctx.token, msgChatId, msgId, sub.photoFileId, '❌ *DENIED*');

    await send(ctx.token, sub.submitterChatId,
      `❌ Your issue "*${escMd(sub.title)}*" was reviewed and not approved for posting\\.`
    );
  }
}

// ── Send submission to owner for review ──────────────────────────────────────

async function sendForOwnerReview(data, ctx) {
  const subId = crypto.randomUUID();
  await ctx.kv.put(`sub:${subId}`, JSON.stringify(data), { expirationTtl: 86400 });

  const catLabel  = CATEGORIES.find(c => c.value === data.category)?.label || data.category || 'Unknown';
  const cityLabel = CITIES.find(c => c.value === data.city)?.label || data.city || 'Unknown';
  const mapsUrl   = `https://maps.google.com/?q=${data.lat},${data.lng}`;

  const caption =
    `🚨 *New Submission for Review*\n` +
    `━━━━━━━━━━━━━━━━━━━━\n` +
    `📋 *Title:* ${escMd(data.title)}\n` +
    `📝 *Desc:* ${escMd((data.description || '').slice(0, 300))}\n` +
    `🏷 *Category:* ${escMd(catLabel)}\n` +
    `🏙 *City:* ${escMd(cityLabel)}\n` +
    `📍 *Location:* [View on Maps](${mapsUrl})\n` +
    `👤 *From:* ${escMd(data.submitterName || 'Unknown')}\n` +
    `━━━━━━━━━━━━━━━━━━━━`;

  const buttons = {
    inline_keyboard: [[
      { text: '✅ Approve', callback_data: `approve:${subId}` },
      { text: '❌ Deny',    callback_data: `deny:${subId}`    },
    ]],
  };

  if (data.photoFileId) {
    await tgCall(ctx.token, 'sendPhoto', {
      chat_id:      ctx.ownerChatId,
      photo:        data.photoFileId,
      caption,
      parse_mode:   'MarkdownV2',
      reply_markup: buttons,
    });
  } else {
    await tgCall(ctx.token, 'sendMessage', {
      chat_id:                  ctx.ownerChatId,
      text:                     caption,
      parse_mode:               'MarkdownV2',
      disable_web_page_preview: false,
      reply_markup:             buttons,
    });
  }

  await send(ctx.token, data.submitterChatId,
    '🎉 Your report has been submitted for review\\! ' +
    "You'll be notified once it's approved or denied\\."
  );
}

// ── Firestore document creation ──────────────────────────────────────────────

async function createFirestorePost(env, sub) {
  const accessToken = await getFirebaseAccessToken(env.FIREBASE_SERVICE_ACCOUNT);
  return createDocument(
    env.FIREBASE_PROJECT_ID,
    accessToken,
    'posts',
    {
      authorId:      `tg:${sub.submitterChatId}`,
      title:         sub.title,
      description:   sub.description || sub.title,
      category:      sub.category    || 'other',
      lat:           sub.lat         ?? 0,
      lng:           sub.lng         ?? 0,
      geohash:       sub.geohash     || '',
      city:          sub.city        || '',
      mediaUrls:     sub.mediaUrls   || [],
      status:        'under_review',
      source:        'telegram',
      upvotes:       0,
      commentsCount: 0,
      sharesCount:   0,
      createdAt:     new Date().toISOString(),
      updatedAt:     new Date().toISOString(),
    }
  );
}

// ── Telegram file URL ────────────────────────────────────────────────────────

async function getTelegramFileUrl(token, fileId) {
  const res  = await fetch(`https://api.telegram.org/bot${token}/getFile?file_id=${fileId}`);
  const json = await res.json();
  if (!json.ok) return null;
  return `https://api.telegram.org/file/bot${token}/${json.result.file_path}`;
}

// ── Edit owner's approval card after decision ────────────────────────────────

async function editApprovalMessage(token, chatId, msgId, hasPhoto, newText) {
  if (hasPhoto) {
    const result = await tgCall(token, 'editMessageCaption', {
      chat_id:      chatId,
      message_id:   msgId,
      caption:      newText,
      parse_mode:   'MarkdownV2',
      reply_markup: { inline_keyboard: [] },
    });
    if (!result.ok) {
      // Fallback: if caption edit fails, try text
      await tgCall(token, 'editMessageText', {
        chat_id:      chatId,
        message_id:   msgId,
        text:         newText,
        parse_mode:   'MarkdownV2',
        reply_markup: { inline_keyboard: [] },
      });
    }
  } else {
    await tgCall(token, 'editMessageText', {
      chat_id:      chatId,
      message_id:   msgId,
      text:         newText,
      parse_mode:   'MarkdownV2',
      reply_markup: { inline_keyboard: [] },
    });
  }
}

// ── KV helpers ───────────────────────────────────────────────────────────────

async function getState(kv, chatId) {
  const raw = await kv.get(`state:${chatId}`);
  return raw ? JSON.parse(raw) : { step: 'idle', data: {} };
}

async function setState(kv, chatId, state) {
  await kv.put(`state:${chatId}`, JSON.stringify(state), { expirationTtl: 3600 });
}

async function clearState(kv, chatId) {
  await kv.delete(`state:${chatId}`);
}

async function getSub(kv, subId) {
  const raw = await kv.get(`sub:${subId}`);
  return raw ? JSON.parse(raw) : null;
}

// ── Telegram API helpers ─────────────────────────────────────────────────────

async function tgCall(token, method, body) {
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(body),
  });
  return res.json();
}

/** Sends a MarkdownV2 message. */
async function send(token, chatId, text) {
  return tgCall(token, 'sendMessage', {
    chat_id:    chatId,
    text,
    parse_mode: 'MarkdownV2',
  });
}

// ── Utilities ────────────────────────────────────────────────────────────────

/** Escape MarkdownV2 special characters. */
function escMd(text) {
  return String(text || '').replace(/[_*[\]()~`>#+=|{}.!\\-]/g, '\\$&');
}

/** Simple geohash encoder (precision 6). */
function encodeGeohash(lat, lng, precision = 6) {
  const BASE32  = '0123456789bcdefghjkmnpqrstuvwxyz';
  let minLat = -90, maxLat = 90, minLng = -180, maxLng = 180;
  let bits = 0, hashVal = 0, result = '';
  let isLng = true;

  while (result.length < precision) {
    if (isLng) {
      const mid = (minLng + maxLng) / 2;
      if (lng >= mid) { hashVal = (hashVal << 1) | 1; minLng = mid; }
      else            { hashVal = hashVal << 1;        maxLng = mid; }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (lat >= mid) { hashVal = (hashVal << 1) | 1; minLat = mid; }
      else            { hashVal = hashVal << 1;        maxLat = mid; }
    }
    isLng = !isLng;
    if (++bits === 5) {
      result  += BASE32[hashVal];
      bits     = 0;
      hashVal  = 0;
    }
  }
  return result;
}
