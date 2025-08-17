const functions = require("firebase-functions");
const admin = require("firebase-admin");
const Razorpay = require("razorpay");
const crypto = require("crypto"); // Signature verify karne ke liye zaroori

admin.initializeApp();
const db = admin.firestore();

// Razorpay instance ko Key ID aur Key Secret ke saath initialize karo
const razorpay = new Razorpay({
  key_id: "rzp_test_R63e5HcDWJPQmZ", // Aapki Key ID
  key_secret: "Tq1JUEoj63fpa4DxHM21ipWi", // Aapka Key Secret
});

/**
 * Naya Razorpay order banata hai.
 */
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
        "internal", "Could not create order.",
    );
  }
});


/**
 * Payment ko verify karta hai aur user ko class ka access deta hai.
 */
exports.verifyRazorpayPayment=functions.https.onCall(async (data, context) => {
  const {orderId, paymentId, signature, classId} = data;
  const userId = context.auth.uid;

  // SIGNATURE VERIFICATION (SECURITY KE LIYE BAHUT ZAROORI)
  const generatedSignature = crypto.createHmac(
      "sha256", "Tq1JUEoj63fpa4DxHM21ipWi", // Yahan apna Key Secret daalo
  ).update(orderId + "|" + paymentId)
      .digest("hex");

  if (generatedSignature !== signature) {
    throw new functions.https.HttpsError(
        "invalid-argument", "Payment signature does not match.",
    );
  }

  // User ke document mein purchased class ki ID add karo
  const userRef = db.collection("users").doc(userId);
  await userRef.update({
    purchasedClasses: admin.firestore.FieldValue.arrayUnion(classId),
  });

  return {message: "Payment verified and access granted!"};
});

