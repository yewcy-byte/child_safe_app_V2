const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');

admin.initializeApp();

const db = admin.firestore();
const SCAN_HEARTBEAT_STALE_MINUTES = 4;
const SCAN_HEARTBEAT_ALERT_COOLDOWN_MINUTES = 30;

async function writeRecoveryNotifyAudit(childId, payload) {
  if (!childId) {
    return;
  }

  await db
    .collection('users')
    .doc(childId)
    .collection('systemHealth')
    .doc('nativeScanRecoveryNotifyAudit')
    .set(
      {
        ...payload,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

exports.requestChildLocation = onCall(
  {
    region: 'us-central1',
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'You must be signed in.');
    }

    const parentId = request.auth.uid;
    const childId = String(request.data?.childId || '').trim();
    if (!childId) {
      throw new HttpsError('invalid-argument', 'childId is required.');
    }

    const childUserRef = db.collection('users').doc(childId);
    const childUserSnap = await childUserRef.get();
    if (!childUserSnap.exists) {
      throw new HttpsError('not-found', 'Child user does not exist.');
    }

    const childData = childUserSnap.data() || {};
    const linkedParentId = String(childData.parentId || '').trim();

    let authorized = linkedParentId === parentId;
    if (!authorized) {
      const childLinkSnap = await db
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .get();
      authorized = childLinkSnap.exists;
    }

    if (!authorized) {
      throw new HttpsError(
        'permission-denied',
        'You are not authorized to request this child location.',
      );
    }

    const token = String(childData.fcmToken || '').trim();
    if (!token) {
      throw new HttpsError(
        'failed-precondition',
        'Child device has no registered FCM token.',
      );
    }

    const requestedAt = new Date();
    const requestId = `${requestedAt.getTime()}_${childId}_${parentId}`;

    await childUserRef
      .collection('systemRequests')
      .doc('locationRefresh')
      .set(
        {
          requestId,
          requestedAt: admin.firestore.Timestamp.fromDate(requestedAt),
          requestedBy: parentId,
          status: 'pending',
        },
        { merge: true },
      );

    const message = {
      token,
      android: {
        priority: 'high',
      },
      data: {
        command: 'GET_LOCATION',
        childId,
        requestId,
        requestedAt: requestedAt.toISOString(),
      },
    };

    const messageId = await admin.messaging().send(message);

    return {
      ok: true,
      messageId,
      requestId,
    };
  },
);

exports.notifyParentOnScanRuntimeDown = onDocumentWritten(
  {
    region: 'us-central1',
    document: 'users/{childId}/systemHealth/scanRuntimeStatus',
  },
  async (event) => {
    const afterData = event.data?.after?.data();
    if (!afterData) {
      return;
    }

    const isRunning = Boolean(afterData.isRunning);
    const expectedRunning = Boolean(afterData.expectedRunning);
    const parentId = String(afterData.parentId || '').trim();

    if (!expectedRunning || isRunning || !parentId) {
      return;
    }

    const beforeData = event.data?.before?.data();
    const wasRunning = beforeData ? Boolean(beforeData.isRunning) : true;
    const wasExpectedRunning = beforeData
      ? Boolean(beforeData.expectedRunning)
      : false;

    // Notify only on transition to "down" while expected to run.
    if (!wasRunning && wasExpectedRunning) {
      return;
    }

    const childId = event.params.childId;
    const reason = String(afterData.reason || 'unknown').trim();

    const childSnap = await db.collection('users').doc(childId).get();

    const childData = childSnap.data() || {};
    const childName =
      String(childData.name || childData.username || childData.email || 'Child')
        .trim() || 'Child';

    const parentSnap = await db.collection('users').doc(parentId).get();
    const parentData = parentSnap.data() || {};
    const token = String(parentData.fcmToken || '').trim();

    if (!token) {
      return;
    }

    const message = {
      token,
      android: {
        priority: 'high',
        notification: {
          channelId: 'high_importance_channel',
        },
      },
      notification: {
        title: 'Scanner is not active',
        body: `${childName} scanner is not active. Please restart the app on the child device.`,
      },
      data: {
        type: 'scan_runtime_down',
        childId,
        parentId,
        reason,
      },
    };

    await admin.messaging().send(message);
  },
);

exports.notifyParentOnNativeScanRecovery = onDocumentWritten(
  {
    region: 'us-central1',
    document: 'users/{childId}/systemHealth/nativeScanRecovery',
  },
  async (event) => {
    const childId = event.params.childId;
    const afterData = event.data?.after?.data();
    if (!afterData) {
      await writeRecoveryNotifyAudit(childId, {
        status: 'skipped',
        reasonCode: 'missing_after_data',
      });
      return;
    }

    const requiresRecovery = Boolean(afterData.requiresRecovery);
    if (!requiresRecovery) {
      await writeRecoveryNotifyAudit(childId, {
        status: 'skipped',
        reasonCode: 'requires_recovery_false',
      });
      return;
    }

    const beforeData = event.data?.before?.data();
    const wasRecoveryRequired = beforeData ? Boolean(beforeData.requiresRecovery) : false;

    if (wasRecoveryRequired) {
      const beforeUpdatedAt = beforeData?.updatedAt?.toDate?.();
      const afterUpdatedAt = afterData?.updatedAt?.toDate?.();
      const beforeMs = beforeUpdatedAt instanceof Date ? beforeUpdatedAt.getTime() : 0;
      const afterMs = afterUpdatedAt instanceof Date ? afterUpdatedAt.getTime() : 0;
      const changedAt = afterMs > beforeMs;

      const beforeReason = String(beforeData?.reason || '').trim();
      const afterReason = String(afterData?.reason || '').trim();
      const reasonChanged = beforeReason !== afterReason;

      if (!changedAt && !reasonChanged) {
        await writeRecoveryNotifyAudit(childId, {
          status: 'skipped',
          reasonCode: 'already_true_no_change',
        });
        return;
      }
    }

    const reason = String(afterData.reason || 'Capture session unavailable').trim();

    const childSnap = await db.collection('users').doc(childId).get();
    const childData = childSnap.data() || {};
    const parentId = String(childData.parentId || '').trim();
    if (!parentId) {
      await writeRecoveryNotifyAudit(childId, {
        status: 'skipped',
        reasonCode: 'missing_parent_id',
      });
      return;
    }

    const childName =
      String(childData.name || childData.username || childData.email || 'Child')
        .trim() || 'Child';

    const parentSnap = await db.collection('users').doc(parentId).get();
    const parentData = parentSnap.data() || {};
    const token = String(parentData.fcmToken || '').trim();
    if (!token) {
      await writeRecoveryNotifyAudit(childId, {
        status: 'skipped',
        reasonCode: 'missing_parent_fcm_token',
        parentId,
      });
      return;
    }

    const alertDocRef = db
      .collection('users')
      .doc(childId)
      .collection('systemHealth')
      .doc('nativeScanRecoveryAlert');

    await admin.messaging().send({
      token,
      android: {
        priority: 'high',
        notification: {
          channelId: 'high_importance_channel',
        },
      },
      notification: {
        title: 'Screen casting permission needed',
        body: `${childName} needs screen casting permission again. Open the child app to re-grant permission.`,
      },
      data: {
        type: 'native_scan_recovery_required',
        childId,
        parentId,
        reason,
      },
    });

    await alertDocRef.set(
      {
        parentId,
        reason,
        lastNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await writeRecoveryNotifyAudit(childId, {
      status: 'sent',
      reasonCode: 'push_sent',
      parentId,
      reason,
    });
  },
);

exports.notifyParentOnScanHeartbeatMissing = onSchedule(
  {
    region: 'us-central1',
    schedule: 'every 2 minutes',
    timeZone: 'Etc/UTC',
    timeoutSeconds: 120,
    memory: '256MiB',
  },
  async () => {
    const now = Date.now();
    const staleCutoff = new Date(
      now - SCAN_HEARTBEAT_STALE_MINUTES * 60 * 1000,
    );
    const alertCooldownCutoff = new Date(
      now - SCAN_HEARTBEAT_ALERT_COOLDOWN_MINUTES * 60 * 1000,
    );

    const [shieldActiveSnap, isActiveSnap] = await Promise.all([
      db.collectionGroup('settings').where('shieldActive', '==', true).get(),
      db.collectionGroup('settings').where('isActive', '==', true).get(),
    ]);

    const protectedPairs = new Map();

    for (const protectionDoc of [
      ...shieldActiveSnap.docs,
      ...isActiveSnap.docs,
    ]) {
      if (protectionDoc.id !== 'protection_status') {
        continue;
      }

      const childDocRef = protectionDoc.ref.parent.parent;
      const childrenCollectionRef = childDocRef?.parent;
      const parentDocRef = childrenCollectionRef?.parent;

      const childId = String(childDocRef?.id || '').trim();
      const parentId = String(parentDocRef?.id || '').trim();

      if (!childId || !parentId) {
        continue;
      }

      protectedPairs.set(`${parentId}:${childId}`, { parentId, childId });
    }

    for (const pair of protectedPairs.values()) {
      const parentId = pair.parentId;
      const childId = pair.childId;

      try {
        const statusRef = db
          .collection('users')
          .doc(childId)
          .collection('systemHealth')
          .doc('scanRuntimeStatus');
        const alertRef = db
          .collection('users')
          .doc(childId)
          .collection('systemHealth')
          .doc('scanRuntimeAlertState');

        const [statusSnap, alertSnap, childSnap, parentSnap] = await Promise.all([
          statusRef.get(),
          alertRef.get(),
          db.collection('users').doc(childId).get(),
          db.collection('users').doc(parentId).get(),
        ]);

        const statusData = statusSnap.data() || {};
        const updatedAt = statusData.updatedAt;
        const hasFreshHeartbeat =
          updatedAt &&
          typeof updatedAt.toDate === 'function' &&
          updatedAt.toDate() >= staleCutoff;
        if (hasFreshHeartbeat) {
          continue;
        }

        const lastStaleAlertAt = alertSnap.data()?.lastStaleAlertAt;
        if (
          lastStaleAlertAt &&
          typeof lastStaleAlertAt.toDate === 'function' &&
          lastStaleAlertAt.toDate() > alertCooldownCutoff
        ) {
          continue;
        }

        const childData = childSnap.data() || {};
        const childName =
          String(
            childData.name || childData.username || childData.email || 'Child',
          ).trim() || 'Child';

        const parentData = parentSnap.data() || {};
        const token = String(parentData.fcmToken || '').trim();
        if (!token) {
          continue;
        }

        const minutesStale =
          updatedAt && typeof updatedAt.toDate === 'function'
            ? Math.max(
                SCAN_HEARTBEAT_STALE_MINUTES,
                Math.floor((now - updatedAt.toDate().getTime()) / 60000),
              )
            : SCAN_HEARTBEAT_STALE_MINUTES;

        await admin.messaging().send({
          token,
          android: {
            priority: 'high',
            notification: {
              channelId: 'high_importance_channel',
            },
          },
          notification: {
            title: 'Scanner is not active',
            body: `${childName} scanner is not active. Please restart the app on the child device.`,
          },
          data: {
            type: 'scan_runtime_stale',
            childId,
            parentId,
            reason: 'heartbeat_missing',
          },
        });

        await alertRef.set(
          {
            parentId,
            childId,
            lastStaleAlertAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } catch (_) {
        // Best-effort notification; skip failed records and continue.
      }
    }
  },
);
