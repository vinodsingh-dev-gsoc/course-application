const functions = require("firebase-functions");
const admin = require("firebase-admin");
const Razorpay = require("razorpay");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

// --- STARTUP CHECK ---
// Pehle hi check karlo ki environment variables hain ya nahi.
if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
  throw new Error(
      "Razorpay Key ID and Key Secret environment variables must be set!",
  );
}

const razorpay = new Razorpay({
  key_id: process.env.RAZORPAY_KEY_ID,
  key_secret: process.env.RAZORPAY_KEY_SECRET,
});

exports.createRazorpayOrder = functions.https.onCall(async (data, context) => {
  const amountInPaise = data.amount * 100;

  const options = {
    amount: amountInPaise,
    currency: "INR",
    receipt: `receipt_${new Date().getTime()}`,
  };

  try {
    const order = await razorpay.orders.create(options);
    console.log("Order created:", order);
    return {orderId: order.id};
  } catch (error) {
    console.error("Error creating Razorpay order:", error);
    throw new functions.https.HttpsError(
        "internal",
        "Could not create order.",
        error,
    );
  }
});

exports.verifyRazorpayPayment =functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "The function must be called while authenticated.",
    );
  }
  const {orderId, paymentId, signature, classId} = data;
  const userId = context.auth.uid;

  const generatedSignature = crypto.createHmac(
      "sha256",
      process.env.RAZORPAY_KEY_SECRET,
  ).update(`${orderId}|${paymentId}`)
      .digest("hex");

  if (generatedSignature !== signature) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Payment signature does not match.",
    );
  }

  try {
    const userRef = db.collection("users").doc(userId);
    await userRef.update({
      purchasedClasses: admin.firestore.FieldValue.arrayUnion(classId),
    });
    return {message: "Payment verified and access granted!"};
  } catch (error) {
    console.error("Error updating user document:", error);
    throw new functions.https.HttpsError(
        "internal",
        "Could not update user profile.",
        error,
    );
  }
});
