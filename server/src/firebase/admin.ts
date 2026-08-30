import admin from 'firebase-admin';
import { config } from '../config.js';

let initialized = false;
let messagingTransportConfigured = false;

export function firebaseMessagingIsConfigured(): boolean {
  return Boolean(config.firebase.clientEmail && config.firebase.privateKey);
}

export function initFirebaseAdmin(): admin.app.App {
  if (!initialized) {
    if (config.firebase.clientEmail && config.firebase.privateKey) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: config.firebase.projectId,
          clientEmail: config.firebase.clientEmail,
          privateKey: config.firebase.privateKey,
        }),
      });
      console.log('[Firebase Admin] Initialized with Service Account Credentials.');
    } else {
      admin.initializeApp({
        projectId: config.firebase.projectId,
      });
      console.warn(
        '[Firebase Admin] Service-account credentials are missing. ID-token verification may use ambient credentials, but FCM push delivery is disabled.',
      );
    }
    initialized = true;
  }
  return admin.app();
}

export async function verifyFirebaseToken(idToken: string): Promise<admin.auth.DecodedIdToken> {
  initFirebaseAdmin();
  return await admin.auth().verifyIdToken(idToken);
}

export type PushBatchResponse = admin.messaging.BatchResponse;

export interface PushNotificationOptions {
  imageUrl?: string | null;
}

export async function sendPushNotification(
  tokens: string[],
  title: string,
  body: string,
  data?: Record<string, string>,
  options: PushNotificationOptions = {}
): Promise<PushBatchResponse> {
  if (!tokens.length) {
    return { responses: [], successCount: 0, failureCount: 0 };
  }
  if (!firebaseMessagingIsConfigured()) {
    throw Object.assign(
      new Error(
        'FCM is not configured on this server. Set FIREBASE_CLIENT_EMAIL and FIREBASE_PRIVATE_KEY.',
      ),
      { name: 'PushConfigurationError', statusCode: 503 },
    );
  }
  initFirebaseAdmin();

  const imageUrl = options.imageUrl?.trim() || undefined;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title,
      body,
      ...(imageUrl ? { imageUrl } : {}),
    },
    data: data || {},
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
          ...(imageUrl ? { mutableContent: true } : {}),
        },
      },
      ...(imageUrl ? { fcmOptions: { imageUrl } } : {}),
    },
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        ...(imageUrl ? { imageUrl } : {}),
        // Must match the channel created by NotificationService in Flutter.
        channelId: 'abu_3meer_high_importance',
      },
    },
  };

  const messaging = admin.messaging();
  if (!messagingTransportConfigured) {
    // Configure the stable HTTP/1.1 transport before the only provider call.
    // Retrying an HTTP/2 batch after an ambiguous socket/session failure can
    // deliver the same logical notification twice even though the first call
    // did not return an acknowledgement to this process.
    messaging.enableLegacyHttpTransport();
    messagingTransportConfigured = true;
  }
  return await messaging.sendEachForMulticast(message);
}
