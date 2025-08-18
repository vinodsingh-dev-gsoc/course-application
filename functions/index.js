const functions = require("firebase-functions");
const admin = require("firebase-admin");
const Razorpay = require("razorpay");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

const razorpaySecrets = ["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET"];

exports.createRazorpayOrder = functions
    .runWith({secrets: razorpaySecrets})
    .https.onCall(async (data, context) => {
      // Secrets ko function ke andar access karein
      const razorpayKeyId = process.env.RAZORPAY_KEY_ID;
      const razorpayKeySecret = process.env.RAZORPAY_KEY_SECRET;

      if (!razorpayKeyId || !razorpayKeySecret) {
        console.error("Razorpay secrets are not configured correctly.");
        throw new functions.https.HttpsError(
            "internal",
            "Server configuration error. Please contact support.",
        );
      }

      const razorpay = new Razorpay({
        key_id: razorpayKeyId,
        key_secret: razorpayKeySecret,
      });

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
            "Could not create payment order.",
            error,
        );
      }
    });

exports.verifyRazorpayPayment = functions
    .runWith({secrets: razorpaySecrets})
    .https.onCall(async (data, context) => {
      // Secret ko function ke andar access karein
      const razorpayKeySecret = process.env.RAZORPAY_KEY_SECRET;

      if (!razorpayKeySecret) {
        console.error("Razorpay secret key is not configured correctly.");
        throw new functions.https.HttpsError(
            "internal",
            "Server configuration error. Please contact support.",
        );
      }

      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "The function must be called while authenticated.",
        );
      }
      const {orderId, paymentId, signature, classId} = data;
      const userId = context.auth.uid;

      const generatedSignature = crypto
          .createHmac("sha256", razorpayKeySecret)
          .update(`${orderId}|${paymentId}`)
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
