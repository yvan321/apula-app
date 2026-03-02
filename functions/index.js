const functions = require("firebase-functions");
const admin = require("firebase-admin");
const twilio = require("twilio");
const nodemailer = require("nodemailer");
const {
  defineString,
  defineInt,
} = require("firebase-functions/params");

// Initialize Firebase Admin SDK
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

const TWILIO_SID = defineString("TWILIO_SID");
const TWILIO_FROM = defineString("TWILIO_FROM");
const TWILIO_AUTH_TOKEN = defineString("TWILIO_AUTH_TOKEN");
const SMS_COOLDOWN_SECONDS = defineInt("SMS_COOLDOWN_SECONDS", {
  default: 180,
});

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

function buildAlertEmailContent({ title, device, severity, alertLevel, snapshotUrl }) {
  const safeDevice = String(device || "Unknown");
  const severityText = `${(severity * 100).toFixed(1)}%`;
  const alertText = `${(alertLevel * 100).toFixed(1)}%`;
  const safeSnapshotUrl = String(snapshotUrl || "").trim();

  const subject = `APULA Alert: ${title.replace(/^[^A-Za-z0-9]+\s*/, "")}`;
  const text = [
    `${title}`,
    `Device: ${safeDevice}`,
    `Severity: ${severityText}`,
    `Alert Score: ${alertText}`,
    safeSnapshotUrl ? `Snapshot: ${safeSnapshotUrl}` : null,
    "Please check APULA immediately.",
  ].filter(Boolean).join("\n");

  const html = `
    <div style="font-family:Arial,sans-serif;line-height:1.5">
      <h2 style="margin-bottom:8px;">${title}</h2>
      <p style="margin:0 0 4px;"><strong>Device:</strong> ${safeDevice}</p>
      <p style="margin:0 0 4px;"><strong>Severity:</strong> ${severityText}</p>
      <p style="margin:0 0 12px;"><strong>Alert Score:</strong> ${alertText}</p>
      ${safeSnapshotUrl ? `<p style="margin:0 0 12px;"><a href="${safeSnapshotUrl}">View snapshot</a></p>` : ""}
      <p style="margin:0;">Please check APULA immediately.</p>
    </div>
  `;

  return { subject, text, html };
}

function isGlobalSmsEnabled() {
  const raw = String(process.env.APULA_SMS_ENABLED || "true").trim().toLowerCase();
  return raw !== "false" && raw !== "0" && raw !== "no";
}

function getMessagingServiceSid() {
  return String(process.env.TWILIO_MESSAGING_SERVICE_SID || "").trim();
}

function hasTwilioSenderConfig() {
  return Boolean(getMessagingServiceSid() || TWILIO_FROM.value());
}

function buildTwilioMessagePayload({ to, body }) {
  const messagingServiceSid = getMessagingServiceSid();
  if (messagingServiceSid) {
    return { to, body, messagingServiceSid };
  }

  const twilioFrom = TWILIO_FROM.value();
  if (!twilioFrom) {
    return null;
  }

  return { to, body, from: twilioFrom };
}

function formatTwilioFailureReason(reason) {
  const message = reason?.message || String(reason || "Unknown error");
  const code = reason?.code;

  if (code === 21612) {
    return `${message} [21612] Hint: Your current sender cannot deliver to this destination. Enable Philippines in Twilio Geo Permissions and use a sender/Messaging Service that supports SMS to +63 numbers.`;
  }

  if (code === 21608) {
    return `${message} [21608] Hint: Trial accounts can only send to verified recipient numbers.`;
  }

  return code ? `${message} [${code}]` : message;
}

const TERMINAL_SMS_FAILURE_STATUSES = new Set([
  "failed",
  "undelivered",
  "canceled",
]);

async function fetchTwilioPostSendStatuses(twilioClient, acceptedResults) {
  await new Promise((resolve) => setTimeout(resolve, 2500));

  const fetchResults = await Promise.allSettled(
    acceptedResults.map((result) =>
      twilioClient.messages(result.value.sid).fetch(),
    ),
  );

  return fetchResults.map((result, index) => {
    const sent = acceptedResults[index].value;

    if (result.status !== "fulfilled") {
      return {
        sid: sent.sid,
        to: sent.to,
        status: String(sent.status || "accepted"),
        errorCode: null,
        errorMessage: result.reason?.message || "Failed to fetch post-send status",
      };
    }

    const fetched = result.value;
    return {
      sid: fetched.sid,
      to: fetched.to,
      status: String(fetched.status || sent.status || "accepted"),
      errorCode: fetched.errorCode || null,
      errorMessage: fetched.errorMessage || null,
    };
  });
}

function buildTwilioDeliveryFailureDetails(statuses) {
  return statuses
    .map((item) => {
      const reason = formatTwilioFailureReason({
        code: item.errorCode,
        message: item.errorMessage || `Delivery status: ${item.status}`,
      });
      return `${item.to}: ${reason}`;
    })
    .slice(0, 2)
    .join(" | ");
}

function getTwilioClient() {
  const sid = TWILIO_SID.value();
  const authToken = TWILIO_AUTH_TOKEN.value();

  if (!sid || !authToken) {
    return null;
  }

  return twilio(sid, authToken);
}

function normalizePhone(phoneRaw) {
  if (!phoneRaw) return "";

  const cleaned = String(phoneRaw).replace(/[^\d+]/g, "");

  if (/^\+639\d{9}$/.test(cleaned)) {
    return cleaned;
  }

  if (/^639\d{9}$/.test(cleaned)) {
    return `+${cleaned}`;
  }

  if (/^09\d{9}$/.test(cleaned)) {
    return `+63${cleaned.substring(1)}`;
  }

  return "";
}

function getConfiguredSmsRecipients(userData) {
  const candidates = [];

  if (userData.phoneNumber) {
    candidates.push(userData.phoneNumber);
  }

  if (Array.isArray(userData.additionalPhoneNumbers)) {
    candidates.push(...userData.additionalPhoneNumbers);
  }

  const normalized = candidates
    .map((number) => normalizePhone(number))
    .filter((number) => number.length > 0);

  return [...new Set(normalized)];
}

function buildSmsBody({ title, device, severity }) {
  return `${title}\nDevice: ${device}\nSeverity: ${(severity * 100).toFixed(1)}%\nPlease check APULA immediately.`;
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
      const sendViaSms = userData.sendViaSms === true;
      const smsRecipients = getConfiguredSmsRecipients(userData);
      const smsCooldownSeconds = SMS_COOLDOWN_SECONDS.value();
      const twilioClient = getTwilioClient();
      const smsEnabledGlobally = isGlobalSmsEnabled();
      const emailEnabledGlobally = isGlobalEmailEnabled();
      const emailCooldownSeconds = getEmailCooldownSeconds();

      // Determine alert level (match GlobalAlertHandler thresholds)
      let title = "🔥 Fire Alert";
      let priority = "high";

      const severity = alert.severity || 0;
      const alertLevel = alert.alert || 0;

      if (severity >= 0.70 && alertLevel >= 0.80) {
        title = "🔴 EXTREME FIRE DANGER";
        priority = "high";
      } else if (severity >= 0.55 && alertLevel >= 0.75) {
        title = "🟠 IGNITION ANOMALY DETECTED";
        priority = "high";
      } else if (severity >= 0.40 && alertLevel >= 0.73) {
        title = "🟡 FIRE-LIKE ACTIVITY";
        priority = "normal";
      }

      const sendTasks = [];

      if (fcmToken) {
        const message = {
          token: fcmToken,
          notification: {
            title: title,
            body: `${alert.device || "Unknown"} | Severity: ${(severity * 100).toFixed(1)}%`,
          },
          data: {
            title: title,
            device: alert.device || "Unknown",
            severity: String(severity),
            alert: String(alertLevel),
            snapshotUrl: alert.snapshotUrl || "",
            type: alert.type || "FIRE_ALERT",
          },
          webpush: {
            priority: priority,
          },
          apns: {
            headers: {
              "apns-priority": priority === "high" ? "10" : "5",
            },
            aps: {
              badge: 1,
              sound: "default",
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

            if (lastEmailAt && now - lastEmailAt.getTime() < cooldownMs) {
              console.log(`⏳ Email cooldown active for ${userEmail}. Skipping email.`);
            } else {
              const primaryRecipient = emailRecipients[0];
              const bccRecipients = emailRecipients.slice(1);
              const emailContent = buildAlertEmailContent({
                title,
                device: alert.device || "Unknown",
                severity,
                alertLevel,
                snapshotUrl: alert.snapshotUrl || "",
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
                    `✅ Email alert sent to ${emailRecipients.length} recipient(s) for ${userEmail}`,
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

      if (sendViaSms && smsEnabledGlobally) {
        if (smsRecipients.length === 0) {
          console.log(`⚠️ SMS enabled but no valid phone numbers for ${userEmail}`);
        } else if (!twilioClient || !hasTwilioSenderConfig()) {
          console.log("⚠️ Twilio is not configured. Skipping SMS send.");
        } else {
          const now = Date.now();
          const lastSmsAt = userData.lastSmsAlertAt?.toDate?.();
          const cooldownMs = smsCooldownSeconds * 1000;

          if (lastSmsAt && now - lastSmsAt.getTime() < cooldownMs) {
            console.log(`⏳ SMS cooldown active for ${userEmail}. Skipping SMS.`);
          } else {
            const smsBody = buildSmsBody({
              title,
              device: alert.device || "Unknown",
              severity,
            });

            sendTasks.push(
              Promise.allSettled(
                smsRecipients.map((recipient) =>
                  twilioClient.messages.create(
                    buildTwilioMessagePayload({
                      to: recipient,
                      body: smsBody,
                    }),
                  ),
                ),
              ).then(async (results) => {
                const successful = results.filter(
                  (result) => result.status === "fulfilled",
                );

                if (successful.length === 0) {
                  console.log(`❌ SMS failed for all recipients of ${userEmail}`);
                  return;
                }

                const sids = successful.map((result) => result.value.sid);

                await userDoc.ref.update({
                  lastSmsAlertAt: admin.firestore.FieldValue.serverTimestamp(),
                  lastSmsSid: sids[0],
                  lastSmsSids: sids,
                  lastSmsRecipients: smsRecipients,
                });

                console.log(
                  `✅ SMS sent to ${successful.length}/${smsRecipients.length} recipients for ${userEmail}`,
                );
                })
                .catch((err) => {
                  console.log(`❌ SMS send error for ${userEmail}:`, err);
                }),
            );
          }
        }
      } else if (sendViaSms && !smsEnabledGlobally) {
        console.log(`ℹ️ SMS is globally disabled. Push-only mode active for ${userEmail}.`);
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

/**
 * Cloud Function: Send test SMS for currently logged-in user
 * Requires user to have sendViaSms=true and a phone number in users collection
 */
exports.sendTestSms = functions.https.onCall(async (data, context) => {
  const authEmail = context.auth?.token?.email;
  const payloadEmail = typeof data?.email === "string" ? data.email.trim() : "";
  const authUid = context.auth?.uid;
  const payloadUid = typeof data?.uid === "string" ? data.uid.trim() : "";

  const email = authEmail || payloadEmail;
  const uid = authUid || payloadUid;

  if (!email && !uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Missing user identity for test SMS.",
    );
  }

  const twilioClient = getTwilioClient();

  if (!twilioClient || !hasTwilioSenderConfig()) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Twilio sender is not configured (set TWILIO_FROM or TWILIO_MESSAGING_SERVICE_SID).",
    );
  }

  if (!isGlobalSmsEnabled()) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "SMS sending is currently disabled for this project. Push notifications remain active.",
    );
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
      throw new functions.https.HttpsError("not-found", "User not found.");
    }

    const userData = userSnapshot.docs[0].data();
    const sendViaSms = userData.sendViaSms === true;
    const smsRecipients = getConfiguredSmsRecipients(userData);

    if (!sendViaSms) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "SMS notifications are disabled for this user.",
      );
    }

    if (smsRecipients.length === 0) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "No valid phone number found for this user.",
      );
    }

    const smsBody =
      "APULA TEST ALERT\nThis is a test SMS notification from your APULA system.";

    const testResults = await Promise.allSettled(
      smsRecipients.map((recipient) =>
        twilioClient.messages.create(
          buildTwilioMessagePayload({
            to: recipient,
            body: smsBody,
          }),
        ),
      ),
    );

    const successful = testResults.filter((result) => result.status === "fulfilled");

    if (successful.length === 0) {
      const failureReasons = testResults
        .filter((result) => result.status === "rejected")
        .map((result) => formatTwilioFailureReason(result.reason));

      const details = failureReasons.length > 0
        ? ` Details: ${failureReasons.slice(0, 2).join(" | ")}`
        : "";

      throw new functions.https.HttpsError(
        "internal",
        `Failed to send test SMS to all configured numbers.${details}`,
      );
    }

    const postSendStatuses = await fetchTwilioPostSendStatuses(
      twilioClient,
      successful,
    );

    const terminalFailures = postSendStatuses.filter((item) =>
      TERMINAL_SMS_FAILURE_STATUSES.has(String(item.status || "").toLowerCase()),
    );

    if (terminalFailures.length === postSendStatuses.length) {
      const details = buildTwilioDeliveryFailureDetails(terminalFailures);
      throw new functions.https.HttpsError(
        "internal",
        `Twilio accepted but did not deliver the test SMS.${details ? ` Details: ${details}` : ""}`,
      );
    }

    const deliverySucceededCount = postSendStatuses.length - terminalFailures.length;

    await userSnapshot.docs[0].ref.update({
      lastSmsTestAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSmsSid: successful[0].value.sid,
      lastSmsSids: successful.map((result) => result.value.sid),
      lastSmsRecipients: smsRecipients,
      lastSmsDeliveryStatuses: postSendStatuses,
    });

    console.log(
      `✅ Test SMS accepted for ${successful.length}/${smsRecipients.length} recipients (${deliverySucceededCount} not in terminal-failure state) for ${email || uid}`,
    );
    return {
      success: true,
      sentCount: successful.length,
      deliverySucceededCount,
      recipientCount: smsRecipients.length,
      recipients: smsRecipients,
      statuses: postSendStatuses,
    };
  } catch (error) {
    console.error("❌ Error sending test SMS:", error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
      "internal",
      error.message || "Failed to send test SMS.",
    );
  }
});

/**
 * Cloud Function: Send test SMS from Firestore request doc
 * Fallback path when callable auth/invoker setup blocks direct call.
 */
exports.sendTestSmsOnRequestCreate = functions.firestore
  .document("sms_test_requests/{requestId}")
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

    const twilioClient = getTwilioClient();

    if (!twilioClient || !hasTwilioSenderConfig()) {
      await snap.ref.update({
        status: "failed",
        error: "Twilio sender is not configured (set TWILIO_FROM or TWILIO_MESSAGING_SERVICE_SID)",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (!isGlobalSmsEnabled()) {
      await snap.ref.update({
        status: "failed",
        error: "SMS sending is currently disabled for this project. Push notifications remain active.",
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
      const sendViaSms = userData.sendViaSms === true;
      const smsRecipients = getConfiguredSmsRecipients(userData);

      if (!sendViaSms) {
        await snap.ref.update({
          status: "failed",
          error: "SMS notifications are disabled",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      if (smsRecipients.length === 0) {
        await snap.ref.update({
          status: "failed",
          error: "No valid phone number found",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const smsBody =
        "APULA TEST ALERT\nThis is a test SMS notification from your APULA system.";

      const testResults = await Promise.allSettled(
        smsRecipients.map((recipient) =>
          twilioClient.messages.create(
            buildTwilioMessagePayload({
              to: recipient,
              body: smsBody,
            }),
          ),
        ),
      );

      const successful = testResults.filter((result) => result.status === "fulfilled");

      if (successful.length === 0) {
        const failureReasons = testResults
          .filter((result) => result.status === "rejected")
          .map((result) => formatTwilioFailureReason(result.reason));

        const details = failureReasons.length > 0
          ? ` Details: ${failureReasons.slice(0, 2).join(" | ")}`
          : "";

        await snap.ref.update({
          status: "failed",
          error: `Failed to send test SMS to all configured numbers.${details}`,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const postSendStatuses = await fetchTwilioPostSendStatuses(
        twilioClient,
        successful,
      );

      const terminalFailures = postSendStatuses.filter((item) =>
        TERMINAL_SMS_FAILURE_STATUSES.has(String(item.status || "").toLowerCase()),
      );

      if (terminalFailures.length === postSendStatuses.length) {
        const details = buildTwilioDeliveryFailureDetails(terminalFailures);
        await snap.ref.update({
          status: "failed",
          error: `Twilio accepted but did not deliver the test SMS.${details ? ` Details: ${details}` : ""}`,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const deliverySucceededCount = postSendStatuses.length - terminalFailures.length;

      await userDoc.ref.update({
        lastSmsTestAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSmsSid: successful[0].value.sid,
        lastSmsSids: successful.map((result) => result.value.sid),
        lastSmsRecipients: smsRecipients,
        lastSmsDeliveryStatuses: postSendStatuses,
      });

      await snap.ref.update({
        status: "sent",
        sentCount: successful.length,
        deliverySucceededCount,
        recipientCount: smsRecipients.length,
        recipients: smsRecipients,
        statuses: postSendStatuses,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      await snap.ref.update({
        status: "failed",
        error: error.message || "Unexpected error sending test SMS",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
