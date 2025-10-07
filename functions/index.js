// functions/index.js
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

admin.initializeApp();

const ALLOWED_ADMINS = [
  "YOUR_ADMIN_EMAIL@example.com", // <-- change this email
];

exports.adminCreateUserWithTempPassword = onCall(async (request) => {
  // ----- Auth check (allowlist for now) -----
  const ctx = request.auth;
  if (!ctx || !ctx.token || !ctx.token.email) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const caller = ctx.token.email.toLowerCase();
  const allowed = ALLOWED_ADMINS.map((e) => e.toLowerCase()).includes(caller);
  if (!allowed) {
    throw new HttpsError("permission-denied", "Only admins can call this.");
  }

  // ----- Input -----
  const data = request.data || {};
  const {name, email, faculty, role, id} = data;
  if (!name || !email || !faculty || !role || !id) {
    throw new HttpsError(
        "invalid-argument",
        "Missing required fields: name, email, faculty, role, id",
    );
  }

  const db = getFirestore();

  try {
    // Generate a secure random temp password
    const tempPassword = crypto.randomBytes(12).toString("base64url");

    // Create or fetch user
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        userRecord = await admin.auth().createUser({
          email,
          password: tempPassword,
          displayName: name,
          emailVerified: false,
          disabled: false,
        });
      } else {
        throw e;
      }
    }

    // Merge profile in Firestore
    await db.collection("users").doc(email).set(
        {
          id,
          name,
          email,
          faculty,
          role,
          status: "invited",
          createdAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    // Send email via the Trigger Email extension (Firestore "mail" doc)
    await db.collection("mail").add({
      to: [email],
      message: {
        subject: "Your PEERS temporary password",
        text:
          `Hello ${name},\n\n` +
          "An admin created your PEERS account.\n\n" +
          `Email: ${email}\n` +
          `Temporary password: ${tempPassword}\n\n` +
          "Please sign in using the above credentials and change your " +
          "password from the Profile/Settings page.\n\n" +
          "If you didn’t expect this, ignore this email.\n\n" +
          "Thanks!",
      },
    });

    return {ok: true, emailSent: true, uid: userRecord.uid};
  } catch (err) {
    console.error(err);
    throw new HttpsError(
        "internal",
        err.message || "Failed to create user",
    );
  }
});
