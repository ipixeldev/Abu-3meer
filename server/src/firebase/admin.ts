import admin from 'firebase-admin';
import { config } from '../config.js';
import { isUnclassifiedPushTransportFailure } from '../services/notificationDomain.js';

let initialized = false;
let legacyMessagingTransportEnabled = false;

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
  let response: PushBatchResponse;
  try {
    response = await messaging.sendEachForMulticast(message);
  } catch (error) {
    if (legacyMessagingTransportEnabled || !isUnclassifiedPushTransportFailure(error)) {
      throw error;
    }
    legacyMessagingTransportEnabled = true;
    messaging.enableLegacyHttpTransport();
    console.warn(
      '[Firebase Admin] FCM HTTP/2 session failed before a provider response; retrying over HTTP/1.1.',
    );
    return await messaging.sendEachForMulticast(message);
  }

  // Firebase Admin's HTTP/2 batch transport can reject every request with a
  // plain Error (no Firebase/APNs code), especially after a session/socket
  // failure. Retry exactly once using the SDK's stable HTTP/1.1 transport.
  // Provider-coded failures are never retried here, so invalid tokens and
  // APNs credential errors continue through the normal recovery path.
  const unclassifiedTotalFailure =
    !legacyMessagingTransportEnabled &&
    response.successCount === 0 &&
    response.failureCount === tokens.length &&
    response.responses.every(
      result => !result.success && isUnclassifiedPushTransportFailure(result.error)
    );
  if (unclassifiedTotalFailure) {
    legacyMessagingTransportEnabled = true;
    messaging.enableLegacyHttpTransport();
    console.warn(
      '[Firebase Admin] FCM HTTP/2 transport failed without a provider code; retrying over HTTP/1.1.',
    );
    response = await messaging.sendEachForMulticast(message);
  }
  return response;
}
