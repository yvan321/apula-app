const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// Initialize Firebase Admin SDK
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

let _emailTransporter = null;

function parseBoolEnv(name, defaultValue = false) {
  const raw = String(process.env[name] ?? "").trim().toLowerCase();
  if (!raw) return defaultValue;
  return raw === "true" || raw === "1" || raw === "yes";
}

function isGlobalEmailEnabled() {
  return parseBoolEnv("APULA_EMAIL_ENABLED", true);
}

function getEmailCooldownSeconds() {
  const raw = Number(process.env.EMAIL_COOLDOWN_SECONDS || 180);
  if (!Number.isFinite(raw) || raw < 0) {
    return 180;
  }
  return Math.floor(raw);
}

function isValidEmail(emailRaw) {
  const email = String(emailRaw || "").trim().toLowerCase();
  if (!email) return false;
  return /^[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}$/.test(email);
}

function getConfiguredEmailRecipients(userData) {
  const recipients = [];

  if (isValidEmail(userData.notificationEmail)) {
    recipients.push(String(userData.notificationEmail).trim().toLowerCase());
  }

  if (Array.isArray(userData.additionalEmails)) {
    for (const email of userData.additionalEmails) {
      if (isValidEmail(email)) {
        recipients.push(String(email).trim().toLowerCase());
      }
    }
  }

  return [...new Set(recipients)];
}

function getEmailSenderAddress() {
  return String(process.env.EMAIL_FROM || process.env.SMTP_FROM || "").trim();
}

function hasEmailConfig() {
  const host = String(process.env.SMTP_HOST || "").trim();
  const port = Number(process.env.SMTP_PORT || 0);
  const user = String(process.env.SMTP_USER || "").trim();
  const pass = String(process.env.SMTP_PASS || "").trim();
  const from = getEmailSenderAddress();

  return Boolean(host && port > 0 && user && pass && from);
}

function getEmailTransporter() {
  if (_emailTransporter) {
    return _emailTransporter;
  }

  if (!hasEmailConfig()) {
    return null;
  }

  const host = String(process.env.SMTP_HOST || "").trim();
  const port = Number(process.env.SMTP_PORT || 587);
  const secure = parseBoolEnv("SMTP_SECURE", port === 465);
  const user = String(process.env.SMTP_USER || "").trim();
  const pass = String(process.env.SMTP_PASS || "").trim();

  _emailTransporter = nodemailer.createTransport({
    host,
    port,
    secure,
    auth: { user, pass },
  });

  return _emailTransporter;
}

function formatDominantSource(source) {
  const normalized = String(source || "unknown").trim().toLowerCase();
  if (normalized === "cctv") return "CCTV / Vision";
  if (normalized === "sensor") return "Sensor / IoT";
  if (normalized === "mixed") return "Mixed (both)";
  return "Unknown";
}

function buildAlertEmailContent({ title, device, severity, alertLevel, snapshotUrl, dominantSource }) {
  const safeDevice = String(device || "Unknown");
  const severityText = `${(severity * 100).toFixed(1)}%`;
  const alertText = `${(alertLevel * 100).toFixed(1)}%`;
  const safeSnapshotUrl = String(snapshotUrl || "").trim();
  const sourceText = formatDominantSource(dominantSource);

  const subject = `APULA Alert: ${title.replace(/^[^A-Za-z0-9]+\s*/, "")}`;
  const text = [
    `${title}`,
    `Device: ${safeDevice}`,
    `Severity: ${severityText}`,
    `Alert Score: ${alertText}`,
    `Likely Trigger: ${sourceText}`,
    safeSnapshotUrl ? `Snapshot: ${safeSnapshotUrl}` : null,
    "Please check APULA immediately.",
  ].filter(Boolean).join("\n");

  const html = `
    <div style="font-family:Arial,sans-serif;line-height:1.5">
      <h2 style="margin-bottom:8px;">${title}</h2>
      <p style="margin:0 0 4px;"><strong>Device:</strong> ${safeDevice}</p>
      <p style="margin:0 0 4px;"><strong>Severity:</strong> ${severityText}</p>
      <p style="margin:0 0 12px;"><strong>Alert Score:</strong> ${alertText}</p>
      <p style="margin:0 0 12px;"><strong>Likely Trigger:</strong> ${sourceText}</p>
      ${safeSnapshotUrl ? `<p style="margin:0 0 12px;"><a href="${safeSnapshotUrl}">View snapshot</a></p>` : ""}
      <p style="margin:0;">Please check APULA immediately.</p>
    </div>
  `;

  return { subject, text, html };
}

function isResolvedStatus(status) {
  return String(status || "").trim().toLowerCase() === "resolved";
}

async function sendDispatchResolvedNotification({
  dispatchData,
  dispatchId,
  collectionName,
}) {
  const userEmail = dispatchData.userEmail;

  if (!userEmail) {
    console.log(
      `⚠️ ${collectionName}/${dispatchId} has no userEmail. Skipping resolved push.`,
    );
    return;
  }

  const userSnapshot = await db
    .collection("users")
    .where("email", "==", userEmail)
    .limit(1)
    .get();

  if (userSnapshot.empty) {
    console.log(`⚠️ User not found for resolved dispatch email: ${userEmail}`);
    return;
  }

  const userData = userSnapshot.docs[0].data();
  const fcmToken = userData.fcmToken;

  if (!fcmToken) {
    console.log(`⚠️ No FCM token for resolved dispatch user: ${userEmail}`);
    return;
  }

  const location = dispatchData.location || dispatchData.device || "Unknown Location";

  await db.collection("user_alerts").add({
    type: "✅ Dispatch Resolved",
    deviceName: location,
    snapshotUrl: dispatchData.snapshotUrl || "",
    severity: dispatchData.severity || 0,
    alert: dispatchData.alert || 0,
    read: false,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    userEmail,
    userId: userData.uid || null,
    sourceCollection: collectionName,
    sourceDispatchId: dispatchId,
    message: `${location} incident has been marked as resolved.`,
  });

  const message = {
    token: fcmToken,
    notification: {
      title: "✅ Dispatch Resolved",
      body: `${location} incident has been marked as resolved.`,
    },
    data: {
      type: "DISPATCH_RESOLVED",
      dispatchId,
      collection: collectionName,
      location: String(location),
      status: "resolved",
      userEmail,
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      aps: {
        badge: 1,
        sound: "default",
      },
    },
    webpush: {
      priority: "high",
    },
  };

  const response = await messaging.send(message);
  console.log(
    `✅ Resolved dispatch push sent to ${userEmail} for ${collectionName}/${dispatchId}. Message ID: ${response}`,
  );
}

/**
 * Cloud Function: Triggered when a new alert is created in user_alerts collection
 * Sends FCM notification to the user's device
 */
exports.sendAlertNotificationOnCreate = functions.firestore
  .document("user_alerts/{alertId}")
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    const userEmail = alert.userEmail;
    const userId = alert.userId;

    if (!userEmail) {
      console.log("⚠️ No userEmail in alert, skipping notification");
      return;
    }

    try {
      // Get user document to find FCM token + notification settings.
      // Resolve by uid first (most reliable), then fallback to email.
      let userSnapshot;
      if (userId) {
        userSnapshot = await db
          .collection("users")
          .where("uid", "==", userId)
          .limit(1)
          .get();
      }

      if (!userSnapshot || userSnapshot.empty) {
        userSnapshot = await db
          .collection("users")
          .where("email", "==", userEmail)
          .limit(1)
          .get();
      }

      if (userSnapshot.empty) {
        console.log(`⚠️ User not found for email: ${userEmail}`);
        return;
      }

      const userDoc = userSnapshot.docs[0];
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;
      const emailRecipients = getConfiguredEmailRecipients(userData);
      const emailEnabledGlobally = isGlobalEmailEnabled();
      const emailCooldownSeconds = getEmailCooldownSeconds();

      // Determine alert level (match GlobalAlertHandler thresholds)
      let title = "🔥 Fire Alert";
      let priority = "high";

      const severity = alert.severity || 0;
      const alertLevel = alert.alert || 0;
      const dominantSource = alert.dominantSource || alert.source || "unknown";
      const sourceLabel = formatDominantSource(dominantSource);

      // Escalation detection: Check if this is a level jump (caution -> ignition/confirmation)
      const lastAlertLevel = alert.lastAlertLevel || 0;
      const hasEscalated = severity >= 0.60 && lastAlertLevel < 0.50;

      // Match thresholds from global_alert_handler.dart
      const isCaution = (severity >= 0.46 && alertLevel >= 0.60) || (severity >= 0.55 && alertLevel >= 0.45);
      const isConfirmation = (severity >= 0.70 && alertLevel >= 0.40) || (severity >= 0.95 && alertLevel >= 0.55);
      const isDangerous = (severity >= 0.90 && alertLevel >= 0.70);
      const singleSignalHighSpike = (severity >= 0.90 || alertLevel >= 0.90) && !(severity >= 0.90 && alertLevel >= 0.90);

      if (isDangerous) {
        title = "🔴 EXTREME FIRE DANGER";
        priority = "high";
      } else if (isConfirmation || singleSignalHighSpike) {
        title = "⚠️ CONFIRMATION REQUIRED: FIRE-LIKE ACTIVITY";
        priority = "high";
      } else if (isCaution) {
        title = "🟡 CAUTION: FIRE-LIKE ACTIVITY";
        priority = "normal";
      }

      const sendTasks = [];

      if (fcmToken) {
        const snapshotUrl = alert.snapshotUrl || "";
        const message = {
          token: fcmToken,
          notification: {
            title: title,
            body: `${alert.device || "Unknown"} | Severity: ${(severity * 100).toFixed(1)}% | Source: ${sourceLabel}`,
          },
          data: {
            alertId: context.params.alertId,
            title: title,
            device: alert.device || "Unknown",
            severity: String(severity),
            alert: String(alertLevel),
            dominantSource: String(dominantSource),
            dominantSourceLabel: sourceLabel,
            source: String(dominantSource),
            sourceLabel,
            snapshotUrl: snapshotUrl,
            type: alert.type || "FIRE_ALERT",
          },
          webpush: {
            priority: priority,
            data: {
              alertId: context.params.alertId,
            }
          },
          apns: {
            headers: {
              "apns-priority": priority === "high" ? "10" : "5",
            },
            aps: {
              badge: 1,
              sound: "default",
            },
            fcmOptions: {
              analyticsLabel: "fire_alert",
            },
          },
          android: {
            priority: priority === "high" ? "high" : "normal",
            data: {
              alertId: context.params.alertId,
            },
            notification: {
              imageUrl: snapshotUrl || undefined,
              title: title,
              body: `${alert.device || "Unknown"} | Severity: ${(severity * 100).toFixed(1)}%`,
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        };

        sendTasks.push(
          messaging.send(message).then((response) => {
            console.log(`✅ FCM alert sent to ${userEmail}. Message ID: ${response}`);
          }),
        );
      } else {
        console.log(`⚠️ No FCM token for user: ${userEmail}`);
      }

      if (emailEnabledGlobally) {
        if (emailRecipients.length === 0) {
          console.log(`⚠️ No configured notificationEmail/additionalEmails for ${userEmail}`);
        } else {
          const transporter = getEmailTransporter();
          const from = getEmailSenderAddress();

          if (!transporter || !from) {
            console.log("⚠️ Email is enabled but SMTP config is incomplete. Skipping email send.");
          } else {
            const now = Date.now();
            const lastEmailAt = userData.lastEmailAlertAt?.toDate?.();
            const cooldownMs = emailCooldownSeconds * 1000;
            
            // Bypass cooldown for escalated alerts (caution -> confirmation/dangerous)
            const shouldBypassCooldown = hasEscalated || isDangerous;

            if (lastEmailAt && now - lastEmailAt.getTime() < cooldownMs && !shouldBypassCooldown) {
              console.log(`⏳ Email cooldown active for ${userEmail}. Skipping email.`);
            } else {
              if (shouldBypassCooldown && lastEmailAt && now - lastEmailAt.getTime() < cooldownMs) {
                console.log(`⚡ Alert escalation detected - bypassing cooldown for ${userEmail}`);
              }
              
              const primaryRecipient = emailRecipients[0];
              const bccRecipients = emailRecipients.slice(1);
              const escapationMsg = hasEscalated ? " [ESCALATED - Cooldown Bypassed]" : "";
              const emailContent = buildAlertEmailContent({
                title: title + escapationMsg,
                device: alert.device || "Unknown",
                severity,
                alertLevel,
                snapshotUrl: alert.snapshotUrl || "",
                dominantSource,
              });

              sendTasks.push(
                transporter.sendMail({
                  from,
                  to: primaryRecipient,
                  bcc: bccRecipients.length > 0 ? bccRecipients : undefined,
                  subject: emailContent.subject,
                  text: emailContent.text,
                  html: emailContent.html,
                }).then(async (info) => {
                  await userDoc.ref.update({
                    lastEmailAlertAt: admin.firestore.FieldValue.serverTimestamp(),
                    lastEmailRecipients: emailRecipients,
                    lastEmailMessageId: info?.messageId || null,
                  });

                  console.log(
                    `✅ Email alert sent to ${emailRecipients.length} recipient(s) for ${userEmail}${escapationMsg}`,
                  );
                }).catch((err) => {
                  console.log(`❌ Email send error for ${userEmail}:`, err?.message || err);
                }),
              );
            }
          }
        }
      } else {
        console.log(`ℹ️ Email is globally disabled. Skipping email send for ${userEmail}.`);
      }

      if (sendTasks.length === 0) {
        console.log(`⚠️ No notification channel available for ${userEmail}`);
        return;
      }

      await Promise.all(sendTasks);
      return;
    } catch (error) {
      console.error(`❌ Error sending notification to ${userEmail}:`, error);
      throw error;
    }
  });

/**
 * Cloud Function: Notify user when a dispatcher alert is marked resolved
 */
exports.notifyDispatchResolvedOnAlertsUpdate = functions.firestore
  .document("alerts/{dispatchId}")
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};

    const wasResolved = isResolvedStatus(beforeData.status);
    const isResolved = isResolvedStatus(afterData.status);

    if (!isResolved || wasResolved) {
      return;
    }

    await sendDispatchResolvedNotification({
      dispatchData: afterData,
      dispatchId: context.params.dispatchId,
      collectionName: "alerts",
    });
  });

/**
 * Cloud Function: Notify user when a dispatch record is marked resolved
 */
exports.notifyDispatchResolvedOnDispatchesUpdate = functions.firestore
  .document("dispatches/{dispatchId}")
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};

    const wasResolved = isResolvedStatus(beforeData.status);
    const isResolved = isResolvedStatus(afterData.status);

    if (!isResolved || wasResolved) {
      return;
    }

    await sendDispatchResolvedNotification({
      dispatchData: afterData,
      dispatchId: context.params.dispatchId,
      collectionName: "dispatches",
    });
  });

/**
 * Cloud Function: Update user's FCM token
 * Call this via Cloud Function when user logs in or token refreshes
 */
exports.updateFcmToken = functions.https.onCall(async (data, context) => {
  const { email, fcmToken } = data;

  if (!email || !fcmToken) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "email and fcmToken are required",
    );
  }

  try {
    // Find user by email
    const userSnapshot = await db
      .collection("users")
      .where("email", "==", email)
      .limit(1)
      .get();

    if (userSnapshot.empty) {
      throw new functions.https.HttpsError("not-found", "User not found");
    }

    const userDoc = userSnapshot.docs[0];
    await userDoc.ref.update({
      fcmToken: fcmToken,
      lastFcmUpdate: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`✅ FCM token updated for ${email}`);
    return { success: true, message: "FCM token updated" };
  } catch (error) {
    console.error("❌ Error updating FCM token:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Cloud Function: Send test email from Firestore request doc
 * Uses Firestore trigger to avoid callable IAM/invoker restrictions.
 */
exports.sendTestEmailOnRequestCreate = functions.firestore
  .document("email_test_requests/{requestId}")
  .onCreate(async (snap, context) => {
    const requestData = snap.data() || {};
    const email = typeof requestData.email === "string" ? requestData.email.trim() : "";
    const uid = typeof requestData.uid === "string" ? requestData.uid.trim() : "";

    if (!email && !uid) {
      await snap.ref.update({
        status: "failed",
        error: "Missing email/uid in request",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (!isGlobalEmailEnabled()) {
      await snap.ref.update({
        status: "failed",
        error: "Email sending is currently disabled for this project.",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const transporter = getEmailTransporter();
    const from = getEmailSenderAddress();

    if (!transporter || !from) {
      await snap.ref.update({
        status: "failed",
        error: "SMTP is not configured. Please set SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, and SMTP_FROM.",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    try {
      let userSnapshot;
      if (email) {
        userSnapshot = await db
          .collection("users")
          .where("email", "==", email)
          .limit(1)
          .get();
      } else {
        userSnapshot = await db
          .collection("users")
          .where("uid", "==", uid)
          .limit(1)
          .get();
      }

      if (userSnapshot.empty) {
        await snap.ref.update({
          status: "failed",
          error: "User not found",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const userDoc = userSnapshot.docs[0];
      const userData = userDoc.data();
      const recipients = getConfiguredEmailRecipients(userData);

      if (recipients.length === 0) {
        await snap.ref.update({
          status: "failed",
          error: "No notification recipients configured. Please set notificationEmail/additionalEmails in Notification Settings.",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const primaryRecipient = recipients[0];
      const bccRecipients = recipients.slice(1);

      const testSubject = "APULA Test Email";
      const testText =
        "This is a test email notification from your APULA system. If you received this, email alerts are configured correctly.";
      const testHtml = `
        <div style="font-family:Arial,sans-serif;line-height:1.5">
          <h2 style="margin-bottom:8px;">APULA Test Email</h2>
          <p style="margin:0;">This is a test email notification from your APULA system.</p>
          <p style="margin:8px 0 0;">If you received this, email alerts are configured correctly.</p>
        </div>
      `;

      const info = await transporter.sendMail({
        from,
        to: primaryRecipient,
        bcc: bccRecipients.length > 0 ? bccRecipients : undefined,
        subject: testSubject,
        text: testText,
        html: testHtml,
      });

      await userDoc.ref.update({
        lastEmailTestAt: admin.firestore.FieldValue.serverTimestamp(),
        lastEmailRecipients: recipients,
        lastEmailMessageId: info?.messageId || null,
      });

      await snap.ref.update({
        status: "sent",
        recipientCount: recipients.length,
        recipients,
        messageId: info?.messageId || null,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      await snap.ref.update({
        status: "failed",
        error: error?.message || "Failed to send test email.",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

