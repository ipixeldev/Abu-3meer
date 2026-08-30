import admin from 'firebase-admin';
import { initFirebaseAdmin } from './admin.js';

/**
 * Firestore remains the compatibility store for the legacy loyalty system.
 * Only the self-hosted server may use this handle; mobile clients authorize
 * admin operations against PostgreSQL RBAC and never write these documents.
 */
export function getAdminFirestore(): admin.firestore.Firestore {
  initFirebaseAdmin();
  return admin.firestore();
}

export function firestoreTimestampToIso(value: unknown): string | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }
  return null;
}

export { admin as firebaseAdmin };
