const admin = require('firebase-admin');
const crypto = require('crypto');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const { createClient } = require('@supabase/supabase-js');

admin.initializeApp();

const MPESA_MARKET = process.env.MPESA_MARKET || 'vodacomLES';
const MPESA_ENVIRONMENT = process.env.MPESA_ENVIRONMENT || 'openapi';
const MPESA_COUNTRY = process.env.MPESA_COUNTRY || 'LES';
const MPESA_CURRENCY = process.env.MPESA_CURRENCY || 'LSL';
const MPESA_SERVICE_PROVIDER_CODE =
  process.env.MPESA_SERVICE_PROVIDER_CODE || '116352';
const MPESA_ORIGIN = process.env.MPESA_ORIGIN || '*';
const DELIVERY_COMMISSION_RATE = Number(
  process.env.DELIVERY_COMMISSION_RATE || '0.08',
);
const PICKUP_COMMISSION_RATE = Number(
  process.env.PICKUP_COMMISSION_RATE || '0.05',
);
const DELIVERY_PARTNER_MSISDN =
  process.env.DELIVERY_PARTNER_MSISDN || '26650898333';
const MPESA_PUBLIC_KEY = process.env.MPESA_PUBLIC_KEY || `-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAietPTdEyyoV/wvxRjS5p
Sn3ZBQH9hnVtQC9SFLgM9IkomEX9Vu9fBg2MzWSSqkQlaYIGFGH3d69Q5NOWkRo+
Y8p5a61sc9hZ+ItAiEL9KIbZzhnMwi12jUYCTff0bVTsTGSNUePQ2V42sToOIKCe
BpUtwWKhhW3CSpK7S1iJhS9H22/BT/pk21Jd8btwMLUHfVD95iXbHNM8u6vFaYuH
czx966T7gpa9RGGXRtiOr3ScJq1515tzOSOsHTPHLTun59nxxJiEjKoI4Lb9h6Il
auvcGAQHp5q6/2XmxuqZdGzh39uLac8tMSmY3vC3fiHYC3iMyTb7eXqATIhDUOf9
mOSbgZMS19iiVZvz8igDl950IMcelJwcj0qCLoufLE5y8ud5WIw47OCVkD7tcAEP
mVWlCQ744SIM5afw+Jg50T1SEtu3q3GiL0UQ6KTLDyDEt5BL9HWXAIXsjFdPDpX1
jtxZavVQV+Jd7FXhuPQuDbh12liTROREdzatYWRnrhzeOJ5Se9xeXLvYSj8DmAI4
iFf2cVtWCzj/02uK4+iIGXlX7lHP1W+tycLS7Pe2RdtC2+oz5RSSqb5jI4+3iEY/
vZjSMBVk69pCDzZy4ZE8LBgyEvSabJ/cddwWmShcRS+21XvGQ1uXYLv0FCTEHHob
Cfmn2y8bJBb/Hct53BaojWUCAwEAAQ==
-----END PUBLIC KEY-----`;

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variable.');
  }

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

function getMpesaApiKey() {
  const apiKey = process.env.MPESA_API_KEY;
  if (!apiKey) {
    throw new HttpsError('failed-precondition', 'Missing MPESA_API_KEY environment variable.');
  }
  return apiKey;
}

function mpesaUrl(path) {
  return `https://openapi.m-pesa.com/${MPESA_ENVIRONMENT}/ipg/v2/${MPESA_MARKET}/${path}`;
}

function encryptForMpesa(value) {
  return crypto.publicEncrypt(
    {
      key: MPESA_PUBLIC_KEY,
      padding: crypto.constants.RSA_PKCS1_PADDING,
    },
    Buffer.from(value),
  ).toString('base64');
}

async function parseMpesaResponse(response, fallbackMessage) {
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};

  if (response.ok) {
    return body;
  }

  const message = body.output_ResponseDesc || body.error || fallbackMessage;
  throw new Error(`${message} (HTTP ${response.status})`);
}

async function getMpesaSessionId() {
  const encryptedApiKey = encryptForMpesa(getMpesaApiKey());
  const response = await fetch(mpesaUrl('getSession/'), {
    method: 'GET',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${encryptedApiKey}`,
      Origin: MPESA_ORIGIN,
    },
  });
  const body = await parseMpesaResponse(response, 'Session request failed');
  const sessionId = body.output_SessionID;
  if (!sessionId) {
    throw new Error('M-Pesa did not return a session ID.');
  }
  return sessionId;
}

async function makeMpesaPayment(path, paymentDetails, fallbackMessage) {
  const sessionId = await getMpesaSessionId();
  const encryptedSessionId = encryptForMpesa(sessionId);
  const response = await fetch(mpesaUrl(path), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${encryptedSessionId}`,
      Origin: MPESA_ORIGIN,
    },
    body: JSON.stringify(paymentDetails),
  });
  const body = await parseMpesaResponse(response, fallbackMessage);
  const responseCode = body.output_ResponseCode;
  if (responseCode && responseCode !== 'INS-0') {
    throw new Error(body.output_ResponseDesc || fallbackMessage);
  }
  return body;
}

function normalizeMsisdn(rawValue, label) {
  const digitsOnly = String(rawValue || '').replace(/\D/g, '');
  if (digitsOnly.startsWith('266') && digitsOnly.length === 11) {
    return digitsOnly;
  }
  if (digitsOnly.length === 8) {
    return `266${digitsOnly}`;
  }
  throw new HttpsError(
    'invalid-argument',
    `${label} must be an 8-digit Lesotho number or start with 266.`,
  );
}

function amountStringFromCents(cents) {
  return (cents / 100).toFixed(2);
}

function generateConversationId(length = 32) {
  return crypto.randomBytes(length).toString('hex').slice(0, length);
}

function generateTransactionReference() {
  const randomNumber = crypto.randomInt(1000, 10000);
  const randomLetter = String.fromCharCode(65 + crypto.randomInt(0, 26));
  return `T${randomNumber}${randomLetter}`;
}

function inferOrderType(order) {
  const rawItems = Array.isArray(order.items_json) ? order.items_json : [];
  const firstItemOrderType = rawItems[0]?.order_type;
  if (firstItemOrderType) {
    return String(firstItemOrderType).toLowerCase();
  }
  if (order.service_type) {
    return String(order.service_type).toLowerCase();
  }
  const deliveryFeeCents = Number(order.delivery_fee_cents || 0);
  return deliveryFeeCents > 0 || order.delivery_address ? 'delivery' : 'pickup';
}

async function verifySupabaseUser(supabase, accessToken) {
  if (!accessToken) {
    throw new HttpsError('unauthenticated', 'Missing Supabase access token.');
  }

  const { data, error } = await supabase.auth.getUser(accessToken);
  if (error || !data?.user) {
    throw new HttpsError('unauthenticated', 'Invalid Supabase access token.');
  }
  return data.user;
}

exports.processOrderPayment = onCall(async (request) => {
  const data = request.data || {};
  const orderId = String(data.orderId || '').trim();
  const customerMsisdn = String(data.customerMSISDN || '').trim();
  const supabaseAccessToken = String(data.supabaseAccessToken || '').trim();

  if (!orderId) {
    throw new HttpsError('invalid-argument', 'Order ID is required.');
  }
  if (!customerMsisdn) {
    throw new HttpsError('invalid-argument', 'Customer M-Pesa number is required.');
  }

  const supabase = getSupabaseAdmin();
  const user = await verifySupabaseUser(supabase, supabaseAccessToken);

  const { data: order, error: orderError } = await supabase
    .from('orders')
    .select('*')
    .eq('id', orderId)
    .maybeSingle();

  if (orderError) {
    throw new HttpsError('internal', orderError.message);
  }
  if (!order) {
    throw new HttpsError('not-found', 'Order was not found.');
  }
  if (String(order.customer_id) !== String(user.id)) {
    throw new HttpsError('permission-denied', 'You can only pay for your own order.');
  }
  if (String(order.status) !== 'accepted') {
    throw new HttpsError('failed-precondition', 'Only accepted orders can be paid.');
  }

  const { data: restaurant, error: restaurantError } = await supabase
    .from('restaurants')
    .select('*')
    .eq('id', order.restaurant_id)
    .maybeSingle();

  if (restaurantError) {
    throw new HttpsError('internal', restaurantError.message);
  }
  if (!restaurant) {
    throw new HttpsError('not-found', 'Restaurant was not found.');
  }

  const restaurantMsisdn = normalizeMsisdn(
    restaurant.restuarant_number || restaurant.restaurant_number,
    'Restaurant M-Pesa number',
  );
  const normalizedCustomerMsisdn = normalizeMsisdn(
    customerMsisdn,
    'Customer M-Pesa number',
  );

  const totalCents = Number(order.total_cents || 0);
  const deliveryFeeCents = Number(order.delivery_fee_cents || 0);
  const subtotalCents = Number(order.subtotal_cents || Math.max(totalCents - deliveryFeeCents, 0));
  if (!Number.isFinite(totalCents) || totalCents <= 0) {
    throw new HttpsError('failed-precondition', 'Order total is invalid.');
  }

  const orderType = inferOrderType(order);
  const commissionRate =
    orderType === 'delivery' ? DELIVERY_COMMISSION_RATE : PICKUP_COMMISSION_RATE;
  // Platform commission applies exclusively to the food subtotal
  const platformCommissionCents = Math.round(subtotalCents * commissionRate);
  // Restaurant payout is strictly based on the food subtotal minus platform commission (zero delivery fee)
  const restaurantPayoutCents = Math.max(subtotalCents - platformCommissionCents, 0);
  // Delivery payout is 100% of the delivery fee without percentile deduction
  const deliveryPayoutCents = orderType === 'delivery' ? deliveryFeeCents : 0;

  if (order.mpesa_transaction_id && order.mpesa_b2c_transaction_id) {
    return {
      success: true,
      alreadyPaid: true,
      c2bTransactionId: order.mpesa_transaction_id,
      b2cTransactionId: order.mpesa_b2c_transaction_id,
      deliveryB2cTransactionId: order.mpesa_delivery_b2c_transaction_id,
      platformCommissionCents,
      restaurantPayoutCents,
      deliveryPayoutCents,
    };
  }

  let c2bTransactionId = order.mpesa_transaction_id;
  let c2bResponse = null;
  if (!c2bTransactionId) {
    const c2bTransactionReference = generateTransactionReference();
    c2bResponse = await makeMpesaPayment(
      'c2bPayment/singleStage/',
      {
        input_Amount: amountStringFromCents(totalCents),
        input_Country: MPESA_COUNTRY,
        input_Currency: MPESA_CURRENCY,
        input_CustomerMSISDN: normalizedCustomerMsisdn,
        input_ServiceProviderCode: MPESA_SERVICE_PROVIDER_CODE,
        input_ThirdPartyConversationID: generateConversationId(),
        input_TransactionReference: c2bTransactionReference,
        input_PurchasedItemsDesc:
          orderType === 'delivery' ? 'Food order and delivery' : 'Food order pickup',
      },
      'C2B payment failed',
    );
    c2bTransactionId = c2bResponse.output_TransactionID || c2bTransactionReference;

    await supabase
      .from('orders')
      .update({
        mpesa_transaction_id: c2bTransactionId,
        platform_commission_cents: platformCommissionCents,
        restaurant_payout_cents: restaurantPayoutCents,
        delivery_payout_cents: deliveryPayoutCents,
        payment_status: 'customer_paid',
        payment_error: null,
      })
      .eq('id', orderId);
  }

  let restaurantB2cResponse = null;
  let deliveryB2cResponse = null;
  let restaurantB2cTransactionId = null;
  let deliveryB2cTransactionId = null;
  let restaurantPayoutError = null;
  let deliveryPayoutError = null;

  // 1. Restaurant Payout (Food portion only)
  try {
    const b2cTransactionReference = generateTransactionReference();
    restaurantB2cResponse = await makeMpesaPayment(
      'b2cPayment/',
      {
        input_Amount: amountStringFromCents(restaurantPayoutCents),
        input_Country: MPESA_COUNTRY,
        input_Currency: MPESA_CURRENCY,
        input_CustomerMSISDN: restaurantMsisdn,
        input_ServiceProviderCode: MPESA_SERVICE_PROVIDER_CODE,
        input_ThirdPartyConversationID: generateConversationId(),
        input_TransactionReference: b2cTransactionReference,
        input_PaymentItemsDesc: 'Restaurant food order payout',
      },
      'Restaurant payout failed',
    );

    restaurantB2cTransactionId =
      restaurantB2cResponse.output_TransactionID || b2cTransactionReference;
  } catch (error) {
    restaurantPayoutError = error.message || String(error);
    logger.error('Restaurant B2C payout failed after customer payment', {
      orderId,
      c2bTransactionId,
      error: restaurantPayoutError,
    });
  }

  // 2. Delivery Partner Payout (100% of delivery fee)
  if (deliveryPayoutCents > 0) {
    try {
      const deliveryPartnerMsisdn = normalizeMsisdn(
        DELIVERY_PARTNER_MSISDN,
        'Delivery Partner M-Pesa number',
      );
      const deliveryB2cReference = generateTransactionReference();
      deliveryB2cResponse = await makeMpesaPayment(
        'b2cPayment/',
        {
          input_Amount: amountStringFromCents(deliveryPayoutCents),
          input_Country: MPESA_COUNTRY,
          input_Currency: MPESA_CURRENCY,
          input_CustomerMSISDN: deliveryPartnerMsisdn,
          input_ServiceProviderCode: MPESA_SERVICE_PROVIDER_CODE,
          input_ThirdPartyConversationID: generateConversationId(),
          input_TransactionReference: deliveryB2cReference,
          input_PaymentItemsDesc: 'Delivery fee payout',
        },
        'Delivery fee payout failed',
      );

      deliveryB2cTransactionId =
        deliveryB2cResponse.output_TransactionID || deliveryB2cReference;
    } catch (error) {
      deliveryPayoutError = error.message || String(error);
      logger.error('Delivery B2C payout failed after customer payment', {
        orderId,
        c2bTransactionId,
        error: deliveryPayoutError,
      });
    }
  }

  const combinedError = [restaurantPayoutError, deliveryPayoutError]
    .filter(Boolean)
    .join('; ');
  const finalStatus = combinedError ? 'payout_error' : 'paid';

  await supabase
    .from('orders')
    .update({
      mpesa_b2c_transaction_id: restaurantB2cTransactionId,
      mpesa_delivery_b2c_transaction_id: deliveryB2cTransactionId,
      platform_commission_cents: platformCommissionCents,
      restaurant_payout_cents: restaurantPayoutCents,
      delivery_payout_cents: deliveryPayoutCents,
      payment_status: finalStatus,
      payment_error: combinedError || null,
    })
    .eq('id', orderId);

  return {
    success: true,
    payoutPending: Boolean(combinedError),
    c2bTransactionId,
    b2cTransactionId: restaurantB2cTransactionId,
    deliveryB2cTransactionId,
    platformCommissionCents,
    restaurantPayoutCents,
    deliveryPayoutCents,
    payoutError: combinedError || null,
    c2bResponse,
    restaurantB2cResponse,
    deliveryB2cResponse,
  };
});

exports.sendOrderStatusNotification = onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method not allowed');
    return;
  }

  try {
    const payload = req.body || {};
    const record = payload.record || {};
    const oldRecord = payload.old_record || {};

    const orderId = String(record.id || '');
    const customerId = String(record.customer_id || '');
    const nextStatus = String(record.order_status || record.status || '');
    const previousStatus = String(oldRecord.order_status || oldRecord.status || '');

    if (!orderId || !customerId || !nextStatus || previousStatus === nextStatus) {
      res.status(200).json({ skipped: true });
      return;
    }

    const supabase = getSupabaseAdmin();
    const { data: profile, error } = await supabase
        .from('users')
        .select('push_tokens')
        .eq('id', customerId)
        .maybeSingle();

    if (error) {
      throw error;
    }

    const tokens = Array.isArray(profile?.push_tokens)
      ? profile.push_tokens.filter(Boolean)
      : [];

    if (tokens.length === 0) {
      res.status(200).json({ skipped: true, reason: 'no_tokens' });
      return;
    }

    const prettyStatus = nextStatus.replace(/_/g, ' ');
    const shortId = orderId.slice(0, 6).toUpperCase();

    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'Order update',
        body: `Order #${shortId} is now ${prettyStatus}.`,
      },
      data: {
        orderId,
        orderStatus: nextStatus,
        screen: 'orders',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'order_updates',
        },
      },
    });

    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.success) {
        const code = result.error && result.error.code;
        if (
          code === 'messaging/invalid-registration-token' ||
          code === 'messaging/registration-token-not-registered'
        ) {
          invalidTokens.push(tokens[index]);
        }
      }
    });

    if (invalidTokens.length > 0) {
      const filteredTokens = tokens.filter((token) => !invalidTokens.includes(token));
      await supabase.from('users').update({ push_tokens: filteredTokens }).eq('id', customerId);
    }

    logger.info('Supabase order status notification processed', {
      orderId,
      previousStatus,
      nextStatus,
      sent: response.successCount,
      failed: response.failureCount,
    });

    res.status(200).json({
      success: true,
      sent: response.successCount,
      failed: response.failureCount,
    });
  } catch (error) {
    logger.error('Notification webhook failed', error);
    res.status(500).json({ error: error.message || String(error) });
  }
});
